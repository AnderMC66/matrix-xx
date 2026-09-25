
/// Puerto de `src/lib/horario.ts` + `src/app/horario/acciones.ts`.
///
/// Utilidades puras (`proximaOcurrencia`, `proximoBloque`, `formatearHora`)
/// más el CRUD contra `horarios_estudio`. Sin dependencias de plataforma:
/// nada aquí toca `Timer` ni notificaciones — eso vive en la pantalla.
library;

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
