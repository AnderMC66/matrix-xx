import "package:supabase_flutter/supabase_flutter.dart";

import "preguntas.dart";

/// Puerto de `src/app/repaso/acciones.ts`.
///
/// Todo lo de aquí cruza códigos que devuelve Postgres contra el banco local.
/// Es a propósito, y en el móvil el motivo pesa aún más que en la web: los RPC
/// nunca devuelven el enunciado ni —sobre todo— la clave, solo el
/// `codigo_externo`, así que ni por accidente pueden filtrar la respuesta
/// correcta. El enunciado lo pone el APK; la clave, nadie hasta que respondes.
///
/// Un código puede no encontrarse (pregunta retirada del banco después de que
/// el alumno la respondiera). `Banco.porCodigos` lo descarta en silencio en
/// vez de romper la pantalla.
class ResumenRepasos {
  final int pendientesHoy;
  final DateTime? proximaFecha;
  final int totalProgramados;

  const ResumenRepasos({
    required this.pendientesHoy,
    required this.proximaFecha,
    required this.totalProgramados,
  });

  /// Sin nada programado, el alumno todavía no ha respondido lo suficiente
  /// como para que la repetición espaciada tenga algo que decir.
  bool get sinHistorial => totalProgramados == 0;
}

class RepositorioRepaso {
  final SupabaseClient _cliente;
  final RepositorioPreguntas _preguntas;

  RepositorioRepaso({SupabaseClient? cliente, RepositorioPreguntas? preguntas})
    : _cliente = cliente ?? Supabase.instance.client,
      _preguntas = preguntas ?? RepositorioPreguntas();

  bool get hayCuenta => _cliente.auth.currentUser != null;

  Future<ResumenRepasos?> resumen() async {
    if (!hayCuenta) return null;

    final datos = await _cliente.rpc("resumen_repasos");
    final fila = _primeraFila(datos);
    if (fila == null) return null;

    final fecha = fila["proxima_fecha"] as String?;
    return ResumenRepasos(
      pendientesHoy: fila["pendientes_hoy"] as int? ?? 0,
      // Llega como `date` de Postgres ("2026-09-14"), sin hora. Se ancla al
      // mediodía para que ningún desfase de zona horaria la corra un día, que
      // es justo lo que hace la web con `T12:00:00`.
      proximaFecha: fecha == null ? null : DateTime.parse("${fecha}T12:00:00"),
      totalProgramados: fila["total_programados"] as int? ?? 0,
    );
  }

  /// Lo que toca repasar hoy según el calendario de repetición espaciada.
  Future<List<Pregunta>> pendientes({int limite = 30}) => _porCodigos(
    () => _cliente.rpc("repasos_pendientes", params: {"p_limite": limite}),
  );

  /// Preguntas cuya última respuesta sigue siendo incorrecta.
  Future<List<Pregunta>> falladas() =>
      _porCodigos(() => _cliente.rpc("preguntas_falladas"));

  /// Práctica adaptativa: prioriza los subtemas más flojos y, dentro de ellos,
  /// lo que el alumno no ha visto o falló.
  Future<List<Pregunta>> recomendadas({String? cursoCodigo, int limite = 20}) =>
      _porCodigos(
        () => _cliente.rpc(
          "preguntas_recomendadas",
          params: {"p_curso_codigo": ?cursoCodigo, "p_limite": limite},
        ),
      );

  /// La llamada llega como función, no como `Future` ya construido: así el
  /// guard de sesión se evalúa ANTES de armar la petición. Con un `Future` de
  /// parámetro, la petición quedaba construida aunque no hubiera cuenta, y que
  /// no llegara a salir dependía de un detalle interno de `postgrest` (los
  /// constructores solo ejecutan al esperarlos). Eso no es una garantía que
  /// convenga heredar.
  Future<List<Pregunta>> _porCodigos(Future<dynamic> Function() llamada) async {
    if (!hayCuenta) return const [];

    final datos = await llamada();
    if (datos is! List) return const [];

    final banco = await _preguntas.cargar();
    return banco.porCodigos([
      for (final f in datos)
        if ((f as Map)["codigo_externo"] case final String c) c,
    ]);
  }
}

/// Un RPC `setof` llega como lista; según la versión del cliente puede venir
/// ya desenvuelto. Se normaliza en un sitio para no repetir el `is List` en
/// cada llamada.
Map<String, dynamic>? _primeraFila(dynamic datos) {
  if (datos is List) {
    return datos.isEmpty ? null : datos.first as Map<String, dynamic>?;
  }
  return datos as Map<String, dynamic>?;
}
