import "package:matr_u/data/models/preguntas.dart";
import "package:supabase_flutter/supabase_flutter.dart";

/// Puerto de `src/lib/panel.ts` + `src/app/panel/acciones.ts`.
///
/// **El control de acceso real vive en la base, no aquí.** Las seis
/// funciones del panel comprueban `es_staff()`/`es_admin()` por dentro, así
/// que un alumno que llame al RPC a mano recibe una excepción o un conjunto
/// vacío aunque se salte esta pantalla — igual que en la web, donde
/// `exigirStaff()` es «conveniencia, no el control de acceso». Lo que evita
/// esta capa es enseñar un panel roto a quien no le toca, nada más.
enum Rol { alumno, docente, admin }

Rol _rolDesde(String? texto) => switch (texto) {
  "docente" => Rol.docente,
  "admin" => Rol.admin,
  _ => Rol.alumno,
};

extension on Rol {
  String get nombre => switch (this) {
    Rol.alumno => "alumno",
    Rol.docente => "docente",
    Rol.admin => "admin",
  };
}

bool esStaff(Rol? rol) => rol == Rol.docente || rol == Rol.admin;

class ResumenPanel {
  final int sinAuditar;
  final int publicadas;
  final int enAuditoria;
  final int borradores;
  final int retiradas;
  final int reportesAbiertos;
  final int personas;

  const ResumenPanel({
    required this.sinAuditar,
    required this.publicadas,
    required this.enAuditoria,
    required this.borradores,
    required this.retiradas,
    required this.reportesAbiertos,
    required this.personas,
  });
}

class AlternativaRevision {
  final Letra letra;
  final String textoMd;
  final String? imagenUrl;
  final String? imagenAlt;

  const AlternativaRevision({
    required this.letra,
    required this.textoMd,
    required this.imagenUrl,
    required this.imagenAlt,
  });
}

class PreguntaRevision {
  final int id;
  final String? codigo;
  final String enunciadoMd;
  final String? imagenUrl;
  final String? imagenAlt;

  /// `null` cuando el RPC no devolvió una letra legible.
  ///
  /// Es nullable a propósito, y antes no lo era: el valor por defecto era
  /// `Letra.a`, así que una clave ausente o ilegible se le presentaba al
  /// docente como «la respuesta correcta es A», en verde y con su etiqueta.
  /// De todos los sitios donde inventar un valor sale mal, este es el peor:
  /// la pantalla existe para que alguien audite precisamente esa letra, y una
  /// clave falsa auditada se publica con el visto bueno de un profesor. Sin
  /// letra no se marca ninguna alternativa y la ficha lo dice.
  final Letra? clave;

  final String? explicacionMd;
  final String estado;
  final String dificultad;
  final bool auditada;
  final String curso;
  final String subtema;
  final List<AlternativaRevision> alternativas;
  final int reportesAbiertos;

  const PreguntaRevision({
    required this.id,
    required this.codigo,
    required this.enunciadoMd,
    required this.imagenUrl,
    required this.imagenAlt,
    required this.clave,
    required this.explicacionMd,
    required this.estado,
    required this.dificultad,
    required this.auditada,
    required this.curso,
    required this.subtema,
    required this.alternativas,
    required this.reportesAbiertos,
  });
}

class ReporteStaff {
  final int id;
  final String motivo;
  final String? detalle;
  final String estado;
  final DateTime creadoEn;
  final int preguntaId;
  final String? preguntaCodigo;
  final String? preguntaEnunciado;

  const ReporteStaff({
    required this.id,
    required this.motivo,
    required this.detalle,
    required this.estado,
    required this.creadoEn,
    required this.preguntaId,
    required this.preguntaCodigo,
    required this.preguntaEnunciado,
  });
}

class Persona {
  final String id;
  final String nombre;
  final String correo;
  final Rol rol;
  final String plan;

  const Persona({
    required this.id,
    required this.nombre,
    required this.correo,
    required this.rol,
    required this.plan,
  });
}

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
