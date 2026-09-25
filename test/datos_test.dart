// Fija lo que la migración no puede romper sin que nos enteremos.
//
// Los tres bloques cubren riesgos distintos:
//
//   · El banco NO lleva claves. Es una regresión de seguridad, no un bug de
//     interfaz: si vuelve a colarse, el APK reparte el examen resuelto y nada
//     en la pantalla se ve distinto. Por eso se comprueba contra el asset real
//     y no contra un doble.
//
//   · Los códigos del temario coinciden con los de la web. Son la clave con la
//     que el banco se cruza con el temario; una desviación de un `padStart`
//     vacía el banco EN SILENCIO —cada pregunta se descarta por "ubicación no
//     encontrada"— y la pantalla solo muestra menos cursos.
//
//   · El banco carga de verdad contra el temario real. Es el test que atrapa
//     lo anterior si se escapa.

import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:matr_u/data/repositories/preguntas.dart";
import "package:matr_u/data/repositories/temario.dart";
import "package:matr_u/domain/models/preguntas.dart";

void main() {
  // Los repositorios leen por `rootBundle`, que en un test necesita el
  // binding inicializado.
  TestWidgetsFlutterBinding.ensureInitialized();

  group("el banco que viaja en el APK", () {
    // Se leen los archivos del disco, no por `rootBundle`: lo que importa aquí
    // es lo que `pubspec.yaml` va a empaquetar, byte a byte.
    final directorio = Directory("assets/datos/preguntas");
    final archivos = directorio
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith(".json"))
        .where((f) => !f.path.endsWith("_indice.json"))
        .toList();

    test("tiene archivos que revisar", () {
      expect(archivos, isNotEmpty, reason: "¿corriste sincronizar-datos.mjs?");
    });

    test("no contiene ninguna clave de respuesta", () {
      final conClave = <String>[];

      for (final archivo in archivos) {
        final doc = jsonDecode(archivo.readAsStringSync());
        for (final p in (doc["preguntas"] as List? ?? const [])) {
          if ((p as Map).containsKey("clave")) {
            conClave.add("${archivo.uri.pathSegments.last} #${p["numero"]}");
          }
        }
      }

      expect(
        conClave,
        isEmpty,
        reason:
            "${conClave.length} preguntas llevan la clave dentro del APK. "
            "Un APK es un ZIP: eso publica el banco resuelto. La clave la "
            "resuelve el RPC `responder_pregunta`, no el binario. "
            "Revisa `despublicar()` en tool/sincronizar-datos.mjs.",
      );
    });

    test("tampoco contiene explicaciones", () {
      // La explicación delata la respuesta tanto como la clave.
      for (final archivo in archivos) {
        final doc = jsonDecode(archivo.readAsStringSync());
        for (final p in (doc["preguntas"] as List? ?? const [])) {
          expect(
            (p as Map).containsKey("explicacion"),
            isFalse,
            reason: "${archivo.uri.pathSegments.last} #${p["numero"]}",
          );
        }
      }
    });
  });

  group("temario", () {
    test("genera los mismos códigos que la web", () async {
      final temario = await RepositorioTemario().cargar();

      // `FIS-09-03`: curso, tema con dos dígitos, subtema con dos dígitos.
      // Es el formato que `generar-seed-temario.mjs` dejó en Postgres.
      final patron = RegExp(r"^[A-Z]{2,4}-\d{2}-\d{2}$");
      for (final curso in temario.cursos) {
        for (final tema in curso.temas) {
          for (final subtema in tema.subtemas) {
            expect(
              patron.hasMatch(subtema.codigo),
              isTrue,
              reason: "código con forma inesperada: ${subtema.codigo}",
            );
          }
        }
      }
    });

    test("numera los subtemas desde 01 y en el orden del sílabo", () async {
      final temario = await RepositorioTemario().cargar();
      final tema = temario.cursos.first.temas.first;

      expect(tema.subtemas.first.codigo, endsWith("-01"));
      for (final (i, s) in tema.subtemas.indexed) {
        expect(s.codigo, endsWith("-${(i + 1).toString().padLeft(2, "0")}"));
      }
    });

    test("un tema sin desglosar recibe el subtema -00", () async {
      final temario = await RepositorioTemario().cargar();
      final pendientes = temario.temas
          .where((t) => t.pendienteDesglose)
          .toList();

      for (final t in pendientes) {
        expect(t.subtemas, hasLength(1));
        expect(t.subtemas.single.codigo, endsWith("-00"));
      }
    });

    test("los números de tema se pasan a romano", () async {
      final temario = await RepositorioTemario().cargar();
      final porNumero = {for (final t in temario.temas) t.numero: t.romano};

      expect(porNumero[1], "I");
      expect(porNumero[4], "IV");
      expect(porNumero[9], "IX");
      if (porNumero.containsKey(10)) expect(porNumero[10], "X");
      if (porNumero.containsKey(14)) expect(porNumero[14], "XIV");
    });

    test("la búsqueda ignora tildes", () async {
      final temario = await RepositorioTemario().cargar();
      final conTilde = temario.buscar("química");
      final sinTilde = temario.buscar("quimica");

      expect(sinTilde, hasLength(conTilde.length));
      expect(sinTilde, isNotEmpty);
    });

    test("la búsqueda exige todos los términos", () async {
      final temario = await RepositorioTemario().cargar();
      expect(temario.buscar("zzzz noexiste"), isEmpty);
      expect(temario.buscar("   "), isEmpty);
    });
  });

  group("banco de preguntas", () {
    test("carga y cruza con el temario", () async {
      final banco = await RepositorioPreguntas().cargar();

      expect(
        banco.total,
        greaterThan(0),
        reason:
            "El banco quedó vacío. Suele significar que los códigos de "
            "subtema del temario dejaron de coincidir con los del banco, y "
            "cada pregunta se descarta por ubicación no encontrada.",
      );
      expect(banco.sonEjemplos, isFalse, reason: "faltan los archivos reales");
    });

    test("cada pregunta tiene curso, subtema y cinco alternativas", () async {
      final banco = await RepositorioPreguntas().cargar();

      for (final p in banco.preguntas) {
        expect(p.cursoNombre, isNotEmpty, reason: p.codigo);
        expect(p.subtemaNombre, isNotEmpty, reason: p.codigo);
        expect(p.enunciado, isNotEmpty, reason: p.codigo);
        expect(p.alternativas, hasLength(5), reason: p.codigo);
        expect(
          p.alternativas.map((a) => a.letra),
          orderedEquals(letras),
          reason: p.codigo,
        );
      }
    });

    test("los códigos son únicos y con el formato del seed", () async {
      final banco = await RepositorioPreguntas().cargar();
      final vistos = <String>{};
      final patron = RegExp(r"^[A-Z]+-\d{4}-\d{3}$");

      for (final p in banco.preguntas) {
        expect(patron.hasMatch(p.codigo), isTrue, reason: p.codigo);
        expect(vistos.add(p.codigo), isTrue, reason: "duplicado: ${p.codigo}");
      }
    });

    test("el índice por código encuentra lo que hay y nada más", () async {
      final banco = await RepositorioPreguntas().cargar();
      final alguna = banco.preguntas.first;

      expect(banco.porCodigo(alguna.codigo)?.codigo, alguna.codigo);
      expect(banco.porCodigo("NO-0000-000"), isNull);
    });

    test("porCodigos descarta en silencio los que ya no están", () async {
      final banco = await RepositorioPreguntas().cargar();
      final alguna = banco.preguntas.first.codigo;

      // Es el caso de una pregunta retirada del banco después de que el alumno
      // la respondiera: el RPC devuelve su código y aquí ya no existe.
      expect(banco.porCodigos([alguna, "NO-0000-000"]), hasLength(1));
    });

    test("los conteos por curso suman el total", () async {
      final banco = await RepositorioPreguntas().cargar();
      final suma = banco.cursos().fold(0, (n, c) => n + c.total);

      expect(suma, banco.total);
      // Ordenados de más a menos, como en la web.
      final totales = banco.cursos().map((c) => c.total).toList();
      expect(totales, orderedEquals(List.of(totales)..sort((a, b) => b - a)));
    });

    // `deSubtema` es lo que hace accionable al diagnóstico: Progreso dice
    // «aquí pierdes puntos» y la fila lleva a practicar ESE subtema.
    test("deSubtema devuelve solo las de ese código", () async {
      final banco = await RepositorioPreguntas().cargar();
      final conteo = banco.conteoPorSubtema();
      // El subtema con más preguntas, para que el caso valga la pena.
      final codigo = conteo.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;

      final preguntas = banco.deSubtema(codigo);

      expect(preguntas, hasLength(conteo[codigo]));
      expect(
        preguntas.every((p) => p.subtemaCodigo == codigo),
        isTrue,
        reason: "se coló una pregunta de otro subtema",
      );
    });

    test(
      "deSubtema de un código inexistente devuelve vacío, no lanza",
      () async {
        // Pasa de verdad: el diagnóstico sale de las respuestas del alumno y el
        // banco del APK, y pueden no coincidir si la pregunta se retiró.
        final banco = await RepositorioPreguntas().cargar();
        expect(banco.deSubtema("NO-99-99"), isEmpty);
      },
    );

    test("deSubtema reparte el banco sin perder ni duplicar", () async {
      final banco = await RepositorioPreguntas().cargar();
      final conteo = banco.conteoPorSubtema();
      final suma = conteo.keys
          .map((c) => banco.deSubtema(c).length)
          .fold(0, (a, b) => a + b);
      expect(suma, banco.total);
    });

    test("las figuras rechazan nombres que no son un archivo llano", () {
      expect(
        Figura.desde({
          "src": "../secreto.svg",
          "alt": "",
          "ancho": 1,
          "alto": 1,
        }),
        isNull,
      );
      expect(
        Figura.desde({"src": "a/b.svg", "alt": "", "ancho": 1, "alto": 1}),
        isNull,
      );
      expect(
        Figura.desde({
          "src": "geo-2027-004.svg",
          "alt": "x",
          "ancho": 4,
          "alto": 2,
        }),
        isNotNull,
      );
    });
  });
}
