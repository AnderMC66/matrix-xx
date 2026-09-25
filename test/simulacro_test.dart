// Lo que se puede probar del simulacro sin un servidor detrás.
//
// El grueso del módulo son llamadas a Supabase, que no tiene sentido simular
// aquí: lo que sí conviene fijar es la aritmética de la que depende el examen
// —el instante de inicio y la cuenta atrás—, porque un error ahí no se ve como
// un fallo sino como un alumno al que se le acabó el tiempo antes de tiempo.
import "package:flutter_test/flutter_test.dart";
import "package:matr_u/data/models/simulacro.dart";
import "package:matr_u/ui/features/practice/views/simulacro.dart";

void main() {
  group("instante de inicio", () {
    test("respeta el offset que manda PostgREST", () {
      final d = instanteUtc("2026-09-07T21:44:00+00:00");
      expect(d.isUtc, isTrue);
      expect(d.hour, 21);
    });

    test("acepta la forma con Z", () {
      final d = instanteUtc("2026-09-07T21:44:00Z");
      expect(d.isUtc, isTrue);
      expect(d.hour, 21);
    });

    test("un texto sin zona se interpreta como UTC, no como local", () {
      // Es el caso que arruinaría el cronómetro: leerlo como hora local en
      // Perú (UTC-5) correría el plazo cinco horas.
      final d = instanteUtc("2026-09-07T21:44:00");
      expect(d.isUtc, isTrue);
      expect(d.hour, 21);
    });

    test("un offset distinto de cero se normaliza a UTC", () {
      final d = instanteUtc("2026-09-07T16:44:00-05:00");
      expect(d.isUtc, isTrue);
      expect(d.hour, 21);
    });
  });

  group("cuenta atrás", () {
    test("muestra mm:ss con ceros a la izquierda", () {
      expect(
        formatearRestante(const Duration(minutes: 7, seconds: 5)),
        "07:05",
      );
    });

    test("pasa de 60 minutos sin saltar a horas", () {
      // Un simulacro de 120 minutos arranca aquí, no en "02:00:00".
      expect(formatearRestante(const Duration(minutes: 120)), "120:00");
      expect(
        formatearRestante(const Duration(minutes: 89, seconds: 59)),
        "89:59",
      );
    });

    test("no enseña números negativos entre el fin y el cierre", () {
      expect(formatearRestante(const Duration(seconds: -3)), "00:00");
      expect(formatearRestante(Duration.zero), "00:00");
    });
  });

  group("modelo", () {
    test("un intento sin finalizar está en curso", () {
      final abierto = Intento(
        id: 1,
        simulacroId: 1,
        iniciadoEn: DateTime.utc(2026, 9, 7),
        finalizadoEn: null,
        puntaje: null,
        totalPreguntas: null,
        correctas: null,
      );
      expect(abierto.enCurso, isTrue);
    });

    test("una pregunta sin letra marcada cuenta como sin responder", () {
      const sin = ResultadoPregunta(
        preguntaId: 1,
        codigo: "ALG-2027-001",
        cursoNombre: "Álgebra",
        subtemaNombre: "Factorización",
        letraMarcada: null,
        esCorrecta: null,
      );
      expect(sin.sinResponder, isTrue);
    });
  });
}
