// `alternativasDesde()` traducía un patrón irrefutable en una alternativa
// inventada.
//
// El código era `if (crudas[letra.etiqueta] case final cruda)`, sin el `?`.
// Un patrón así coincide SIEMPRE —también con `null`—, así que el bucle sobre
// las cinco letras producía cinco alternativas pasara lo que pasara: una
// pregunta con cuatro opciones en el JSON salía en pantalla con una quinta,
// vacía, pulsable y con su círculo de letra «E».
//
// Hoy las 392 preguntas del banco traen las cinco, así que no se veía. Las
// escribe gente a mano en `data/preguntas/*.json` del repo web, y la primera
// de cuatro opciones lo habría destapado en producción, delante de un alumno
// que podía marcar una respuesta que no existe.
//
// Lo que este archivo prueba y `datos_test.dart` no podía: ese test comprueba
// «cada pregunta tiene cinco alternativas», que pasaba igual —de hecho mejor—
// con la quinta fantasma. Aquí se mira el contenido, y sobre todo el caso que
// el banco actual no contiene.
import "package:flutter_test/flutter_test.dart";
import "package:matr_u/data/models/preguntas.dart";

void main() {
  group("alternativasDesde", () {
    test("cinco opciones dan cinco alternativas, en orden", () {
      final alts = alternativasDesde({
        "A": "18 g",
        "B": "20 g",
        "C": "22 g",
        "D": "24 g",
        "E": "26 g",
      });

      expect(alts.map((a) => a.letra), letras);
      expect(alts.map((a) => a.texto), [
        "18 g",
        "20 g",
        "22 g",
        "24 g",
        "26 g",
      ]);
    });

    test("cuatro opciones dan CUATRO alternativas, no cinco", () {
      final alts = alternativasDesde({"A": "1", "B": "2", "C": "3", "D": "4"});

      expect(alts, hasLength(4));
      expect(alts.map((a) => a.letra), [
        Letra.a,
        Letra.b,
        Letra.c,
        Letra.d,
      ], reason: "la E no está en el JSON: no debe existir en pantalla");
    });

    test("ninguna alternativa llega con el texto vacío y sin imagen", () {
      // La forma en que el fallo se veía: una tarjeta pulsable sin nada
      // dentro. Es la invariante que de verdad protege al alumno.
      for (final crudas in <Map<String, dynamic>>[
        {"A": "1", "B": "2", "C": "3", "D": "4"},
        {"A": "1", "B": "2", "C": "3"},
        {"A": "1", "B": "2"},
      ]) {
        for (final a in alternativasDesde(crudas)) {
          expect(
            a.texto.isNotEmpty || a.imagen != null,
            isTrue,
            reason: "alternativa ${a.letra.etiqueta} vacía en $crudas",
          );
        }
      }
    });

    test("un hueco en medio no desplaza a las demás", () {
      // Si faltara la C, la D sigue siendo la D: las letras salen de la clave
      // del JSON, no de la posición en la lista.
      final alts = alternativasDesde({"A": "1", "B": "2", "D": "4", "E": "5"});

      expect(alts, hasLength(4));
      expect(alts.map((a) => a.letra), [Letra.a, Letra.b, Letra.d, Letra.e]);
      expect(alts.last.texto, "5");
    });

    test("un mapa vacío no da ninguna alternativa", () {
      expect(alternativasDesde(const {}), isEmpty);
    });

    test("la forma con figura conserva texto e imagen", () {
      final alts = alternativasDesde({
        "A": {
          "texto": "La primera",
          "imagen": {
            "src": "geo-2027-004-trapecio.svg",
            "alt": "Trapecio ABCD",
            "ancho": 400,
            "alto": 300,
          },
        },
      });

      expect(alts, hasLength(1));
      expect(alts.single.texto, "La primera");
      expect(alts.single.imagen?.src, "geo-2027-004-trapecio.svg");
      expect(alts.single.imagen?.alt, "Trapecio ABCD");
    });

    test(
      "una opción con figura y sin texto es válida: la figura ES la opción",
      () {
        // «¿Cuál de estas gráficas…?» — el texto vacío aquí no es un hueco, es
        // el formato. Por eso la invariante de arriba acepta texto vacío CON
        // imagen, y solo rechaza vacío sin nada.
        final alts = alternativasDesde({
          "A": {
            "imagen": {"src": "g1.webp", "alt": "Recta creciente"},
          },
        });

        expect(alts.single.texto, isEmpty);
        expect(alts.single.imagen, isNotNull);
      },
    );

    test("una imagen con nombre no llano se descarta, la alternativa no", () {
      // `Figura.desde` rechaza rutas y saltos de directorio; el texto de la
      // alternativa sigue siendo válido y tiene que llegar.
      final alts = alternativasDesde({
        "A": {
          "texto": "18 g",
          "imagen": {"src": "../otro/sitio.webp", "alt": "x"},
        },
      });

      expect(alts.single.texto, "18 g");
      expect(alts.single.imagen, isNull);
    });
  });
}
