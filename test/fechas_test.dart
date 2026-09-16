// Los cuatro formateadores de `lib/fechas.dart`, que estaban al 0 %.
//
// No es una laguna cosmética: aquí vivía un fallo de zona horaria que se veía
// en dos pantallas. Postgres guarda `timestamptz`, PostgREST lo manda con
// offset y `DateTime.parse` devuelve un instante EN UTC; leerle `.day` a ese
// instante es leer el día que era en Londres. En Perú (UTC-5) eso corre un día
// entero todo lo que pasa después de las 19:00.
//
// Los casos que fijan eso usan una hora UTC que cae en el día anterior en
// cualquier zona al oeste de Greenwich, y comprueban que el resultado coincide
// con el `DateTime` local equivalente — no con una cadena fija, porque la
// suite tiene que pasar igual en la máquina de Arequipa y en la de un CI en
// UTC.
import "package:flutter_test/flutter_test.dart";
import "package:matr_u/fechas.dart";

void main() {
  group("formatos", () {
    final d = DateTime(2026, 9, 14, 10, 30);

    test("día y mes corto", () => expect(fechaDiaMes(d), "14 sep"));
    test("con año", () => expect(fechaDiaMesAno(d), "14 sep 2026"));
    test(
      "dentro de una frase",
      () => expect(fechaLarga(d), "14 de septiembre"),
    );
    test("mes y año", () => expect(mesAno(d), "sep 2026"));

    test("los doce meses tienen nombre corto y largo", () {
      const cortos = [
        "ene",
        "feb",
        "mar",
        "abr",
        "may",
        "jun",
        "jul",
        "ago",
        "sep",
        "oct",
        "nov",
        "dic",
      ];
      for (var m = 1; m <= 12; m++) {
        final f = DateTime(2026, m, 15, 12);
        expect(mesCorto(f), cortos[m - 1]);
        expect(mesLargo(f).startsWith(cortos[m - 1].substring(0, 3)), isTrue);
      }
    });

    test("enero y diciembre no se salen del índice", () {
      expect(mesCorto(DateTime(2026, 1, 1, 12)), "ene");
      expect(mesCorto(DateTime(2026, 12, 31, 12)), "dic");
    });
  });

  group("un instante UTC se cuenta en hora local", () {
    // 02:00 UTC del 15 de septiembre. En cualquier zona con offset negativo
    // —Perú, UTC-5— eso todavía es el 14 por la noche.
    final utc = DateTime.utc(2026, 9, 15, 2);
    final local = utc.toLocal();

    test("fechaDiaMes usa el día local, no el de UTC", () {
      expect(fechaDiaMes(utc), fechaDiaMes(local));
      expect(fechaDiaMes(utc), "${local.day} ${mesCorto(local)}");
    });

    test("fechaDiaMesAno no mezcla el día de una zona con el año de otra", () {
      expect(fechaDiaMesAno(utc), fechaDiaMesAno(local));
    });

    test("fechaLarga usa el día local", () {
      expect(fechaLarga(utc), fechaLarga(local));
    });

    // El caso de «miembro desde»: quien se registró el último día del mes por
    // la noche veía el mes siguiente.
    test("mesAno no adelanta el mes de quien se registró de noche", () {
      final finDeMes = DateTime.utc(2026, 9, 1, 2);
      expect(mesAno(finDeMes), mesAno(finDeMes.toLocal()));
    });

    test("un DateTime ya local pasa sin cambiar", () {
      final ya = DateTime(2026, 9, 14, 21);
      expect(fechaDiaMes(ya), "14 sep");
      expect(mesAno(ya), "sep 2026");
    });
  });
}
