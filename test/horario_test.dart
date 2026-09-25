// El horario semanal recurrente, y su aritmética de fechas — el mismo tipo
// de cálculo que ya mordió una vez en el cronómetro del simulacro
// (`simulacro_test.dart`), así que se prueba con el mismo cuidado.
import "package:flutter_test/flutter_test.dart";
import "package:matr_u/data/models/horario.dart";

void main() {
  group("proximaOcurrencia", () {
    // Miércoles 9 de septiembre de 2026, 10:00 — `DateTime.weekday` da 3.
    final miercoles = DateTime(2026, 9, 9, 10, 0);

    test("un día más adelante en la misma semana", () {
      // Viernes (weekday 5 → convención 0-domingo: 5) a las 17:00.
      final r = proximaOcurrencia(5, "17:00:00", miercoles);
      expect(r.year, 2026);
      expect(r.month, 9);
      expect(r.day, 11); // el viernes de esa semana
      expect(r.hour, 17);
    });

    test("el mismo día, más tarde hoy: cae hoy, no la semana que viene", () {
      final r = proximaOcurrencia(
        3,
        "18:00:00",
        miercoles,
      ); // miércoles, más tarde
      expect(r.day, 9);
      expect(r.hour, 18);
    });

    test("el mismo día, pero la hora ya pasó: salta a la semana siguiente", () {
      final r = proximaOcurrencia(
        3,
        "09:00:00",
        miercoles,
      ); // miércoles, ya pasó
      expect(r.day, 16); // el miércoles siguiente, no hoy
    });

    test("cruza al domingo (convención 0), no se confunde con lunes", () {
      final r = proximaOcurrencia(0, "08:00:00", miercoles);
      expect(r.day, 13); // domingo después del miércoles 9
      expect(r.weekday, DateTime.sunday);
    });

    test("acepta 'HH:MM' además de 'HH:MM:SS'", () {
      final r = proximaOcurrencia(5, "17:00", miercoles);
      expect(r.hour, 17);
      expect(r.minute, 0);
    });
  });

  group("proximoBloque", () {
    final ahora = DateTime(2026, 9, 9, 10, 0); // miércoles

    test("sin bloques, no hay próximo", () {
      expect(proximoBloque(const [], ahora), isNull);
    });

    test("elige el más cercano entre varios, no el primero de la lista", () {
      final lejos = _bloque(id: 1, dia: 5, hora: "17:00:00"); // viernes
      final cerca = _bloque(id: 2, dia: 3, hora: "18:00:00"); // hoy mismo
      final r = proximoBloque([lejos, cerca], ahora);
      expect(r?.bloque.id, 2);
    });
  });

  group("formatearHora", () {
    test("mañana", () {
      expect(formatearHora("09:30:00"), "9:30 a. m.");
    });

    test("mediodía es p. m., no a. m.", () {
      expect(formatearHora("12:00:00"), "12:00 p. m.");
    });

    test("medianoche es 12, no 0", () {
      expect(formatearHora("00:15:00"), "12:15 a. m.");
    });

    test("tarde", () {
      expect(formatearHora("17:05:00"), "5:05 p. m.");
    });
  });

  test("diasSemana empieza en domingo, igual que Postgres y la web", () {
    expect(diasSemana.first, "Domingo");
    expect(diasSemana.length, 7);
  });
}

BloqueHorario _bloque({
  required int id,
  required int dia,
  required String hora,
}) => BloqueHorario(
  id: id,
  cursoCodigo: "FIS",
  cursoNombre: "Física",
  cursoSlug: "fisica",
  diaSemana: dia,
  horaInicio: hora,
  duracionMinutos: 60,
);
