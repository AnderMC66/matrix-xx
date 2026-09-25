import "package:matr_u/domain/models/progreso.dart";
import "package:supabase_flutter/supabase_flutter.dart";

class RepositorioProgreso {
  final SupabaseClient _cliente;

  RepositorioProgreso({SupabaseClient? cliente})
    : _cliente = cliente ?? Supabase.instance.client;

  User? get usuario => _cliente.auth.currentUser;

  bool get hayCuenta => usuario != null;

  /// Atraviesa la política `perfil_propio_lectura`: solo devuelve la fila si su
  /// id coincide con `auth.uid()`. Que llegue algo prueba a la vez que el
  /// disparador creó el perfil y que RLS deja verlo.
  Future<Perfil?> perfil() async {
    final u = usuario;
    if (u == null) return null;

    final f = await _cliente
        .from("perfiles")
        .select(
          "nombre, rol, plan, creditos, creado_en, areas_postulacion(nombre)",
        )
        .eq("id", u.id)
        .maybeSingle();
    if (f == null) return null;

    return Perfil(
      nombre: f["nombre"] as String?,
      rol: f["rol"] as String? ?? "alumno",
      plan: f["plan"] as String? ?? "—",
      creditos: f["creditos"] as int? ?? 0,
      creadoEn: DateTime.parse(f["creado_en"] as String),
      areaNombre: (f["areas_postulacion"] as Map?)?["nombre"] as String?,
    );
  }

  Future<Racha?> racha() async {
    if (!hayCuenta) return null;

    final fila = _primeraFila(await _cliente.rpc("racha_estudio"));
    if (fila == null) return null;

    return Racha(
      diasActual: fila["dias_actual"] as int? ?? 0,
      diasMaxima: fila["dias_maxima"] as int? ?? 0,
      estudiadoHoy: fila["estudiado_hoy"] as bool? ?? false,
    );
  }

  Future<Diagnostico> diagnostico() async {
    if (!hayCuenta) return const Diagnostico([]);

    final datos = await _cliente.rpc("diagnostico_por_subtema");
    if (datos is! List) return const Diagnostico([]);

    return Diagnostico([
      for (final f in datos.cast<Map<String, dynamic>>())
        SubtemaDiagnostico(
          subtemaId: f["subtema_id"] as int,
          codigo: f["subtema_codigo"] as String? ?? "",
          nombre: f["subtema_nombre"] as String? ?? "",
          temaNombre: f["tema_nombre"] as String? ?? "",
          cursoNombre: f["curso_nombre"] as String? ?? "",
          // `bigint` y `numeric` llegan como `num`, y a veces como texto según
          // el tamaño: se normalizan aquí en vez de confiar en el tipo.
          respondidas: _entero(f["respondidas"]),
          correctas: _entero(f["correctas"]),
          porcentaje: _decimal(f["porcentaje"]),
        ),
    ]);
  }

  Future<List<CursoDesatendido>> cursosDesatendidos() async {
    if (!hayCuenta) return const [];

    final datos = await _cliente.rpc("cursos_desatendidos");
    if (datos is! List) return const [];

    return [
      for (final f in datos.cast<Map<String, dynamic>>())
        CursoDesatendido(
          codigo: f["curso_codigo"] as String,
          nombre: f["curso_nombre"] as String,
          slug: f["curso_slug"] as String,
          respondidas: _entero(f["respondidas"]),
          porcentaje: f["porcentaje"] == null ? null : _entero(f["porcentaje"]),
          diasSinPracticar: f["dias_sin_practicar"] as int? ?? 0,
        ),
    ];
  }

  Future<List<ReporteResuelto>> reportesResueltos() async {
    final u = usuario;
    if (u == null) return const [];

    final filas = await _cliente
        .from("reportes_error")
        .select("id, motivo, estado, resuelto_en, preguntas(codigo_externo)")
        .eq("perfil_id", u.id)
        .neq("estado", "abierto")
        .isFilter("visto_por_autor_en", null)
        .order("resuelto_en", ascending: false);

    return [
      for (final r in filas)
        ReporteResuelto(
          id: r["id"] as int,
          motivo: r["motivo"] as String,
          estado: r["estado"] as String,
          preguntaCodigo:
              (r["preguntas"] as Map?)?["codigo_externo"] as String?,
        ),
    ];
  }

  /// Marca como vistos los reportes ya resueltos.
  ///
  /// Pasa por un RPC y no por un `update` directo porque la política
  /// `reportes_update` es solo para staff a propósito: si el autor pudiera
  /// escribir en su propia fila, podría marcarse el reporte como aceptado él
  /// mismo.
  Future<void> marcarReportesVistos() async {
    if (!hayCuenta) return;
    await _cliente.rpc("marcar_reportes_vistos");
  }
}

int _entero(dynamic v) => switch (v) {
  final int n => n,
  final num n => n.round(),
  final String s => int.tryParse(s) ?? 0,
  _ => 0,
};

double _decimal(dynamic v) => switch (v) {
  final num n => n.toDouble(),
  final String s => double.tryParse(s) ?? 0,
  _ => 0,
};

Map<String, dynamic>? _primeraFila(dynamic datos) {
  if (datos is List) {
    return datos.isEmpty ? null : datos.first as Map<String, dynamic>?;
  }
  return datos as Map<String, dynamic>?;
}
