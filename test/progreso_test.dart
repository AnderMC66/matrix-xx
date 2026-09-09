// La agregación del diagnóstico, que es la única lógica de Progreso que no es
// una llamada a Supabase — y la que decide qué ve el alumno primero.
//
// Importa el desempate de `prioridades`: sin él, un subtema con una sola
// respuesta fallada desplaza a otro con daño real, y la pantalla recomienda
// repasar lo que no toca.
import "package:flutter_test/flutter_test.dart";
import "package:matr_u/datos/progreso.dart";

SubtemaDiagnostico _s({
  required int id,
  required double pct,
  required int respondidas,
  String curso = "Álgebra",
}) => SubtemaDiagnostico(
  subtemaId: id,
  codigo: "ALG-01-${id.toString().padLeft(2, "0")}",
  nombre: "Subtema $id",
  temaNombre: "Tema",
  cursoNombre: curso,
  respondidas: respondidas,
  correctas: (respondidas * pct / 100).round(),
  porcentaje: pct,
);

void main() {
  group("diagnóstico vacío", () {
    test("no divide entre cero", () {
      const d = Diagnostico([]);
      expect(d.vacio, isTrue);
      expect(d.aciertoGlobal, 0);
      expect(d.respondidas, 0);
      expect(d.consolidados, 0);
      expect(d.prioridades, isEmpty);
    });
  });

  group("totales", () {
    final d = Diagnostico([
      _s(id: 1, pct: 100, respondidas: 10), // 10 correctas
      _s(id: 2, pct: 50, respondidas: 10), // 5 correctas
    ]);

    test("el acierto global sale del crudo, no del promedio de porcentajes", () {
      // Promediar 100 % y 50 % daría 75 %. Lo correcto es 15/20 = 75 % aquí,
      // pero el test que lo distingue es el de abajo, con pesos distintos.
      expect(d.respondidas, 20);
      expect(d.correctas, 15);
      expect(d.aciertoGlobal, 75);
    });

    test("un subtema con más volumen pesa más", () {
      final pesado = Diagnostico([
        _s(id: 1, pct: 100, respondidas: 2), // 2 de 2
        _s(id: 2, pct: 0, respondidas: 18), // 0 de 18
      ]);
      // El promedio de porcentajes diría 50 %; el real es 2/20 = 10 %.
      expect(pesado.aciertoGlobal, 10);
    });

    test("cuenta como dominados los que llegan al umbral", () {
      final d = Diagnostico([
        _s(id: 1, pct: 70, respondidas: 10), // justo en el umbral: cuenta
        _s(id: 2, pct: 69, respondidas: 10), // justo debajo: no
        _s(id: 3, pct: 95, respondidas: 10),
      ]);
      expect(d.consolidados, 2);
    });
  });

  group("prioridades", () {
    test("deja fuera lo ya consolidado", () {
      final d = Diagnostico([
        _s(id: 1, pct: 90, respondidas: 10),
        _s(id: 2, pct: 30, respondidas: 10),
      ]);
      expect(d.prioridades.map((s) => s.subtemaId), [2]);
    });

    test("ordena por acierto, del peor al menos malo", () {
      final d = Diagnostico([
        _s(id: 1, pct: 60, respondidas: 10),
        _s(id: 2, pct: 20, respondidas: 10),
        _s(id: 3, pct: 40, respondidas: 10),
      ]);
      expect(d.prioridades.map((s) => s.subtemaId), [2, 3, 1]);
    });

    test("a igual acierto, primero el de más volumen", () {
      // Fallar 5 de 10 pesa más que fallar 1 de 2, aunque ambos sean 50 %.
      final d = Diagnostico([
        _s(id: 1, pct: 50, respondidas: 2),
        _s(id: 2, pct: 50, respondidas: 10),
      ]);
      expect(d.prioridades.map((s) => s.subtemaId), [2, 1]);
    });

    test("nunca devuelve más de cinco", () {
      final d = Diagnostico([
        for (var i = 1; i <= 9; i++) _s(id: i, pct: 10.0 * i, respondidas: 10),
      ]);
      expect(d.prioridades, hasLength(5));
    });
  });

  group("agrupado por curso", () {
    test("junta los subtemas de cada curso", () {
      final d = Diagnostico([
        _s(id: 1, pct: 50, respondidas: 4, curso: "Álgebra"),
        _s(id: 2, pct: 50, respondidas: 4, curso: "Física"),
        _s(id: 3, pct: 50, respondidas: 4, curso: "Álgebra"),
      ]);
      expect(d.porCurso.keys, containsAll(["Álgebra", "Física"]));
      expect(d.porCurso["Álgebra"], hasLength(2));
      expect(d.porCurso["Física"], hasLength(1));
    });
  });

  group("racha", () {
    test("cero días no cuenta como racha arrancada", () {
      const r = Racha(diasActual: 0, diasMaxima: 4, estudiadoHoy: false);
      expect(r.arrancada, isFalse);
    });

    test("un día ya es racha", () {
      const r = Racha(diasActual: 1, diasMaxima: 1, estudiadoHoy: true);
      expect(r.arrancada, isTrue);
    });
  });

  group("perfil", () {
    test("reconoce al staff igual que esStaff() en la web", () {
      Perfil con(String rol) => Perfil(
        nombre: "x",
        rol: rol,
        plan: "gratis",
        creditos: 0,
        creadoEn: DateTime.utc(2026),
        areaNombre: null,
      );
      expect(con("admin").esStaff, isTrue);
      expect(con("docente").esStaff, isTrue);
      expect(con("alumno").esStaff, isFalse);
    });
  });
}
