import "package:supabase_flutter/supabase_flutter.dart";

/// Puerto de `src/lib/horario.ts` + `src/app/horario/acciones.ts`.
///
/// Utilidades puras (`proximaOcurrencia`, `proximoBloque`, `formatearHora`)
/// más el CRUD contra `horarios_estudio`. Sin dependencias de plataforma:
/// nada aquí toca `Timer` ni notificaciones — eso vive en la pantalla.

const diasSemana = [
  "Domingo",
  "Lunes",
  "Martes",
  "Miércoles",
  "Jueves",
  "Viernes",
  "Sábado",
];

/// Próxima vez que ocurre un bloque semanal recurrente (`diaSemana` 0–6,
/// domingo primero, igual que `DateTime.weekday % 7`; `horaInicio`
/// "HH:MM" o "HH:MM:SS") a partir de [desde].
DateTime proximaOcurrencia(int diaSemana, String horaInicio, DateTime desde) {
  final partes = horaInicio.split(":");
  final horas = int.parse(partes[0]);
  final minutos = int.parse(partes[1]);

  var objetivo = DateTime(desde.year, desde.month, desde.day, horas, minutos);
  // `DateTime.weekday` es 1 (lunes) .. 7 (domingo); `% 7` lo convierte a la
  // misma convención 0 (domingo) .. 6 (sábado) que usa Postgres y la web.
  final diaActual = desde.weekday % 7;
  objetivo = objetivo.add(Duration(days: (diaSemana - diaActual + 7) % 7));
  if (!objetivo.isAfter(desde)) {
    objetivo = objetivo.add(const Duration(days: 7));
  }
  return objetivo;
}

/// `"17:00:00"` (24h, como llega de Postgres) → `"5:00 p. m."`.
String formatearHora(String horaInicio) {
  final partes = horaInicio.split(":");
  final horas24 = int.parse(partes[0]);
  final m = partes[1];
  final periodo = horas24 < 12 ? "a. m." : "p. m.";
  final horas12 = horas24 % 12 == 0 ? 12 : horas24 % 12;
  return "$horas12:$m $periodo";
}

class BloqueHorario {
  final int id;
  final String cursoCodigo;
  final String cursoNombre;
  final String cursoSlug;

  /// 0 = domingo … 6 = sábado.
  final int diaSemana;

  /// "HH:MM:SS", tal como lo devuelve Postgres para una columna `time`.
  final String horaInicio;
  final int duracionMinutos;

  const BloqueHorario({
    required this.id,
    required this.cursoCodigo,
    required this.cursoNombre,
    required this.cursoSlug,
    required this.diaSemana,
    required this.horaInicio,
    required this.duracionMinutos,
  });
}

/// El bloque semanal más próximo a partir de [desde], o `null` si no hay
/// ninguno.
({BloqueHorario bloque, DateTime cuando})? proximoBloque(
  List<BloqueHorario> horario,
  DateTime desde,
) {
  if (horario.isEmpty) return null;
  final candidatos = [
    for (final b in horario)
      (bloque: b, cuando: proximaOcurrencia(b.diaSemana, b.horaInicio, desde)),
  ]..sort((a, b) => a.cuando.compareTo(b.cuando));
  return candidatos.first;
}

class ErrorHorario implements Exception {
  final String mensaje;
  const ErrorHorario(this.mensaje);

  @override
  String toString() => mensaje;
}

class RepositorioHorario {
  final SupabaseClient _cliente;

  RepositorioHorario({SupabaseClient? cliente})
    : _cliente = cliente ?? Supabase.instance.client;

  /// `[]` sin sesión — igual que el resto de datos personales de la app,
  /// nunca un error: la ausencia de cuenta no es una falla.
  Future<List<BloqueHorario>> obtener() async {
    final usuario = _cliente.auth.currentUser;
    if (usuario == null) return const [];

    final filas = await _cliente
        .from("horarios_estudio")
        .select(
          "id, dia_semana, hora_inicio, duracion_minutos, cursos(codigo, nombre, slug)",
        )
        .eq("perfil_id", usuario.id)
        .order("dia_semana")
        .order("hora_inicio");

    return [
      for (final b in filas)
        if (b["cursos"] != null)
          BloqueHorario(
            id: b["id"] as int,
            cursoCodigo: (b["cursos"] as Map)["codigo"] as String,
            cursoNombre: (b["cursos"] as Map)["nombre"] as String,
            cursoSlug: (b["cursos"] as Map)["slug"] as String,
            diaSemana: b["dia_semana"] as int,
            horaInicio: b["hora_inicio"] as String,
            duracionMinutos: b["duracion_minutos"] as int,
          ),
    ];
  }

  /// [cursoCodigo] y no el slug porque es la columna `unique` real de la
  /// tabla `cursos`, y porque reutilizar el mismo campo que el resto de la
  /// app evita tener dos formas de nombrar el mismo curso en el código.
  Future<void> crear({
    required String cursoCodigo,
    required int diaSemana,
    required String horaInicio,
    required int duracionMinutos,
  }) async {
    if (diaSemana < 0 || diaSemana > 6) {
      throw const ErrorHorario("Día inválido");
    }
    if (duracionMinutos <= 0 || duracionMinutos > 480) {
      throw const ErrorHorario("La duración debe ser de hasta 8 horas");
    }

    final usuario = _cliente.auth.currentUser;
    if (usuario == null) {
      throw const ErrorHorario("No estás autenticado");
    }

    final curso = await _cliente
        .from("cursos")
        .select("id")
        .eq("codigo", cursoCodigo)
        .maybeSingle();
    if (curso == null) throw const ErrorHorario("Curso no encontrado");

    try {
      await _cliente.from("horarios_estudio").insert({
        "perfil_id": usuario.id,
        "curso_id": curso["id"],
        "dia_semana": diaSemana,
        "hora_inicio": horaInicio,
        "duracion_minutos": duracionMinutos,
      });
    } on PostgrestException catch (e) {
      if (e.code == "23505") {
        throw const ErrorHorario(
          "Ya tienes un bloque de ese curso a esa hora ese día",
        );
      }
      throw ErrorHorario(e.message);
    }
  }

  /// La RLS ya restringe el `delete` a `perfil_id = auth.uid()`; el `.eq` de
  /// más abajo es cinturón y tirantes, no la única barrera.
  Future<void> eliminar(int id) async {
    final usuario = _cliente.auth.currentUser;
    if (usuario == null) throw const ErrorHorario("No estás autenticado");

    await _cliente
        .from("horarios_estudio")
        .delete()
        .eq("id", id)
        .eq("perfil_id", usuario.id);
  }
}
