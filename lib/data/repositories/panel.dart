import "package:matr_u/domain/models/panel.dart";
import "package:matr_u/domain/models/preguntas.dart";
import "package:supabase_flutter/supabase_flutter.dart";

Rol _rolDesde(String? texto) => switch (texto) {
  "docente" => Rol.docente,
  "admin" => Rol.admin,
  _ => Rol.alumno,
};

class ErrorPanel implements Exception {
  final String mensaje;
  const ErrorPanel(this.mensaje);

  @override
  String toString() => mensaje;
}

class RepositorioPanel {
  final SupabaseClient _cliente;

  RepositorioPanel({SupabaseClient? cliente})
    : _cliente = cliente ?? Supabase.instance.client;

  /// Se lee de `perfiles` y no de un claim del token: el rol puede cambiar
  /// mientras la sesión sigue viva (`cambiar_rol`), y un token emitido antes
  /// del cambio seguiría diciendo lo de antes hasta que caduque.
  Future<Rol?> rolActual() async {
    final u = _cliente.auth.currentUser;
    if (u == null) return null;
    final f = await _cliente
        .from("perfiles")
        .select("rol")
        .eq("id", u.id)
        .maybeSingle();
    return f == null ? null : _rolDesde(f["rol"] as String?);
  }

  Future<ResumenPanel?> resumen() async {
    final fila = _primeraFila(await _cliente.rpc("resumen_panel"));
    if (fila == null) return null;
    return ResumenPanel(
      sinAuditar: fila["sin_auditar"] as int? ?? 0,
      publicadas: fila["publicadas"] as int? ?? 0,
      enAuditoria: fila["en_auditoria"] as int? ?? 0,
      borradores: fila["borradores"] as int? ?? 0,
      retiradas: fila["retiradas"] as int? ?? 0,
      reportesAbiertos: fila["reportes_abiertos"] as int? ?? 0,
      personas: fila["personas"] as int? ?? 0,
    );
  }

  /// `preguntas.clave` está revocada por columna a `authenticated`, así que
  /// esto no se puede resolver con un `select`: la clave —lo único que de
  /// verdad hay que revisar— solo sale por el RPC.
  Future<List<PreguntaRevision>> paraRevision({
    required String filtro,
    String? cursoCodigo,
  }) async {
    final datos = await _cliente.rpc(
      "preguntas_para_revision",
      params: {
        "p_filtro": filtro,
        "p_curso_codigo": ?cursoCodigo,
        "p_limite": 20,
      },
    );
    if (datos is! List) return const [];

    return [
      for (final p in datos.cast<Map<String, dynamic>>())
        PreguntaRevision(
          id: p["id"] as int,
          codigo: p["codigo_externo"] as String?,
          enunciadoMd: p["enunciado_md"] as String? ?? "",
          imagenUrl: p["enunciado_imagen_url"] as String?,
          imagenAlt: p["enunciado_imagen_alt"] as String?,
          clave: letraDesde(p["clave"] as String? ?? ""),
          explicacionMd: p["explicacion_md"] as String?,
          estado: p["estado"] as String? ?? "",
          dificultad: p["dificultad"] as String? ?? "",
          auditada: p["auditado_en"] != null,
          curso: p["curso_nombre"] as String? ?? "",
          subtema: p["subtema_nombre"] as String? ?? "",
          reportesAbiertos: p["reportes_abiertos"] as int? ?? 0,
          alternativas: [
            for (final a
                in (p["alternativas"] as List? ?? const [])
                    .cast<Map<String, dynamic>>())
              if (letraDesde(a["letra"] as String? ?? "") case final l?)
                AlternativaRevision(
                  letra: l,
                  textoMd: a["texto_md"] as String? ?? "",
                  imagenUrl: a["imagen_url"] as String?,
                  imagenAlt: a["imagen_alt"] as String?,
                ),
          ],
        ),
    ];
  }

  /// Los tres destinos con sentido tras mirar una pregunta —`borrador` no
  /// aparece: es el estado de algo a medio escribir, y lo que llega a
  /// revisión ya está escrito.
  Future<void> dictaminarPregunta({
    required int preguntaId,
    required String estado,
  }) async {
    try {
      await _cliente.rpc(
        "revisar_pregunta",
        params: {"p_pregunta_id": preguntaId, "p_estado": estado},
      );
    } on PostgrestException catch (e) {
      throw ErrorPanel(e.message);
    }
  }

  /// Aquí sí basta un `select`: la política `reportes_select` tiene rama de
  /// staff. No se muestra quién reportó a propósito —`perfiles_select` deja
  /// ver perfiles ajenos a los admin y no a los docentes—, y para decidir si
  /// el reporte tiene razón hace falta la pregunta, no el alumno.
  Future<List<ReporteStaff>> reportes(String estado) async {
    final consulta = _cliente
        .from("reportes_error")
        .select(
          "id, motivo, detalle, estado, creado_en, pregunta_id, "
          "preguntas(codigo_externo, enunciado_md)",
        );
    final filas =
        await (estado == "todos" ? consulta : consulta.eq("estado", estado))
            .order("creado_en", ascending: false)
            .limit(50);

    return [
      for (final r in filas)
        ReporteStaff(
          id: r["id"] as int,
          motivo: r["motivo"] as String,
          detalle: r["detalle"] as String?,
          estado: r["estado"] as String,
          creadoEn: DateTime.parse(r["creado_en"] as String),
          preguntaId: r["pregunta_id"] as int,
          preguntaCodigo:
              (r["preguntas"] as Map?)?["codigo_externo"] as String?,
          preguntaEnunciado:
              (r["preguntas"] as Map?)?["enunciado_md"] as String?,
        ),
    ];
  }

  Future<void> dictaminarReporte({
    required int reporteId,
    required String estado,
  }) async {
    try {
      await _cliente.rpc(
        "resolver_reporte",
        params: {"p_reporte_id": reporteId, "p_estado": estado},
      );
    } on PostgrestException catch (e) {
      throw ErrorPanel(e.message);
    }
  }

  /// Solo para admin: el RPC comprueba `es_admin()` por dentro y le
  /// devolvería una lista vacía a un docente.
  Future<List<Persona>> personas() async {
    final datos = await _cliente.rpc("personas_del_panel");
    if (datos is! List) return const [];

    return [
      for (final p in datos.cast<Map<String, dynamic>>())
        Persona(
          id: p["id"] as String,
          nombre: p["nombre"] as String? ?? "",
          correo: p["correo"] as String? ?? "",
          rol: _rolDesde(p["rol"] as String?),
          plan: p["plan"] as String? ?? "",
        ),
    ];
  }

  /// Pasa por RPC porque `perfiles` no concede `update` sobre `rol` a nadie.
  /// El RPC comprueba `es_admin()` por dentro y se niega a quitar el último
  /// administrador.
  Future<void> cambiarRol({required String perfilId, required Rol rol}) async {
    try {
      await _cliente.rpc(
        "cambiar_rol",
        params: {"p_perfil_id": perfilId, "p_rol": rol.nombre},
      );
    } on PostgrestException catch (e) {
      throw ErrorPanel(e.message);
    }
  }
}

Map<String, dynamic>? _primeraFila(dynamic datos) {
  if (datos is List) {
    return datos.isEmpty ? null : datos.first as Map<String, dynamic>?;
  }
  return datos as Map<String, dynamic>?;
}
