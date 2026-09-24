// Ningún `FutureBuilder` de la app puede quedarse girando para siempre.
//
// Un `FutureBuilder` cuyo `builder` solo pregunta `if (!snap.hasData)` tiene un
// agujero silencioso: cuando el `Future` lanza, `hasData` sigue siendo `false`
// —el dato no llegó— pero el estado ya es `done`, así que no hay ningún frame
// posterior que cambie nada. El spinner se queda ahí. Para siempre. Sin
// mensaje, sin reintento, y sin nada en la consola de un APK de release.
//
// Pasó en cuatro sitios, los cuatro del panel de docente/admin
// (`PantallaPanel`, revisión, reportes y personas): con la red caída o un RPC
// que lanza, el docente veía un círculo girando y no tenía forma de salir de
// ahí más que cerrar la app. Las otras doce pantallas sí lo manejaban — no fue
// una decisión, fue un archivo donde se olvidó cuatro veces seguidas.
//
// **Por qué un test que lee el código y no widgets.** Un widget test de
// `PantallaPanel` exigiría inyectar el repositorio en la pantalla, porque
// construye `RepositorioPanel()` —y con él `Supabase.instance.client`— dentro
// de su propio estado. Y aun con eso, cubriría los cuatro sitios de hoy y
// ninguno de los que se escriban mañana. Esto cubre la clase entera de fallo:
// un `FutureBuilder` nuevo sin rama de error no compila un test rojo, lo
// enciende.
import "dart:io";

import "package:flutter_test/flutter_test.dart";

/// Los `.dart` de `lib/`, que es donde vive la interfaz.
List<File> _fuentes() =>
    Directory("lib")
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith(".dart"))
        .toList();

/// La lista de argumentos del `FutureBuilder` cuyo nombre acaba en [desde],
/// desde su `(` hasta el `)` que lo cierra.
///
/// Tiene que saltarse el argumento de tipo primero: en
/// `FutureBuilder<(Temario, int)>(…)` el primer `(` del texto es el de la
/// tupla del tipo, no el de la llamada, y quedarse con `(Temario, int)`
/// señalaba como roto a un builder que sí trata el error. Y cuenta paréntesis
/// para no cortar a mitad de un builder anidado.
String _cuerpo(String fuente, int desde) {
  var i = desde;

  while (i < fuente.length && fuente[i].trim().isEmpty) {
    i++;
  }

  // El argumento de tipo, si lo hay: `<…>` con anidamiento (`Map<String, int>`).
  if (i < fuente.length && fuente[i] == "<") {
    var angulos = 0;
    for (; i < fuente.length; i++) {
      if (fuente[i] == "<") angulos++;
      if (fuente[i] == ">") {
        angulos--;
        if (angulos == 0) {
          i++;
          break;
        }
      }
    }
  }

  final abre = fuente.indexOf("(", i);
  if (abre < 0) return "";

  var profundidad = 0;
  for (var j = abre; j < fuente.length; j++) {
    final c = fuente[j];
    if (c == "(") profundidad++;
    if (c == ")") {
      profundidad--;
      if (profundidad == 0) return fuente.substring(abre, j + 1);
    }
  }
  // Sin cierre: devolver el resto es lo seguro, porque si falta `hasError` el
  // test debe fallar, no pasar por no haber sabido delimitar.
  return fuente.substring(abre);
}

/// `true` si la posición [donde] cae en un comentario de línea.
///
/// Hace falta porque los comentarios de esta base de código hablan de los
/// widgets por su nombre —`figuras_rotas.dart` explica por qué NO añade un
/// `FutureBuilder` más al árbol— y una mención en prosa no es un widget.
bool _enComentario(String fuente, int donde) {
  final inicioLinea = fuente.lastIndexOf("\n", donde) + 1;
  return fuente.substring(inicioLinea, donde).contains("//");
}

void main() {
  test("todo FutureBuilder de lib/ trata el caso de error", () {
    final sinTratar = <String>[];

    for (final archivo in _fuentes()) {
      final fuente = archivo.readAsStringSync();
      final lineas = fuente.split("\n");

      for (final m in RegExp("FutureBuilder").allMatches(fuente)) {
        if (_enComentario(fuente, m.start)) continue;

        final cuerpo = _cuerpo(fuente, m.end);
        if (cuerpo.contains("hasError")) continue;

        // `snapshot.error` también vale: lo que importa es que el fallo tenga
        // un camino, no cómo se llama la propiedad que lo detecta.
        if (RegExp(r"\.error\b").hasMatch(cuerpo)) continue;

        final linea = fuente.substring(0, m.start).split("\n").length;
        sinTratar.add("${archivo.path}:$linea  ${lineas[linea - 1].trim()}");
      }
    }

    expect(
      sinTratar,
      isEmpty,
      reason:
          "estos FutureBuilder se quedan en el spinner si el Future lanza.\n"
          "Añade una rama `if (snap.hasError)` con un `Aviso` y, si la "
          "petición se puede rehacer, un botón de reintentar:\n\n"
          "${sinTratar.join("\n")}\n",
    );
  });

  // ==========================================================================
  // `setState(() => campo = algoQueDevuelveUnFuture())`
  // ==========================================================================
  //
  // Apareció escribiendo los tests de arriba, y estaba en siete sitios ya
  // escritos. Flutter comprueba lo que devuelve el closure de `setState`:
  //
  //     final Object? result = fn() as dynamic;
  //     assert(result is! Future, "...");
  //
  // Con cuerpo de flecha, `() => _carga = _pedir()` **devuelve** el `Future`
  // asignado, así que la aserción salta y la pantalla se cae con un error rojo.
  // Con cuerpo de bloque, `() { _carga = _pedir(); }` devuelve `null` y no pasa
  // nada. La misma línea, dos comportamientos.
  //
  // Es `assert`, o sea que en un APK de release no existe — y por eso sobrevivió
  // tanto: solo revienta en debug y perfil. Y los siete sitios estaban detrás de
  // «hay sesión» (`if (!_sesion.hayCuenta) return;`), así que la suite, que corre
  // sin credenciales, nunca llegaba a ejecutarlos. La primera vez que alguien
  // entre con su cuenta a un build de depuración y abra Progreso o Simulacro
  // —justo lo que se hace en una etapa de pruebas— se lo encuentra.
  test("ningún setState con cuerpo de flecha asigna un Future", () {
    // Los campos que guardan un `Future`: si un `setState` de flecha asigna a
    // uno de ellos, devuelve ese Future.
    final sospechosos = <String>[];

    for (final archivo in _fuentes()) {
      final fuente = archivo.readAsStringSync();

      // Los campos declarados como Future en este archivo.
      final campos = RegExp(
        r"^\s*(?:late\s+)?(?:final\s+)?Future<[^;]*?>\??\s+"
        r"(_[A-Za-z0-9]+)",
        multiLine: true,
      ).allMatches(fuente).map((m) => m[1]!).toSet();
      if (campos.isEmpty) continue;

      final lineas = fuente.split("\n");
      for (var i = 0; i < lineas.length; i++) {
        final linea = lineas[i];
        // Los comentarios no son código: el arreglo de `inicio.dart` explica
        // el fallo citando la forma mala, y sin esto el propio comentario que
        // documenta el arreglo hacía fallar la comprobación.
        if (linea.trimLeft().startsWith("//")) continue;
        final m = RegExp(r"setState\(\(\)\s*=>\s*(_[A-Za-z0-9]+)\s*=")
            .firstMatch(linea);
        if (m == null || !campos.contains(m[1])) continue;
        sospechosos.add("${archivo.path}:${i + 1}  ${linea.trim()}");
      }
    }

    expect(
      sospechosos,
      isEmpty,
      reason:
          "un setState de flecha que asigna un Future lo DEVUELVE, y Flutter "
          "lo rechaza con una aserción (error rojo en debug, invisible en "
          "release).\nUsa cuerpo de bloque: setState(() { _carga = _pedir(); "
          "});\n\n${sospechosos.join("\n")}\n",
    );
  });

  test("el test sabe reconocer un FutureBuilder sin rama de error", () {
    // Sin esto, un fallo en `_cuerpo()` dejaría el test de arriba en verde
    // para siempre sin que nadie lo note: comprobaría cero cosas y pasaría.
    const malo = """
      FutureBuilder<int>(
        future: algo,
        builder: (context, snap) {
          if (!snap.hasData) return const CircularProgressIndicator();
          return Text("\${snap.data}");
        },
      )
    """;
    expect(
      _cuerpo(malo, malo.indexOf("FutureBuilder") + 13),
      isNot(contains("hasError")),
    );

    const bueno = """
      FutureBuilder<int>(
        future: algo,
        builder: (context, snap) {
          if (snap.hasError) return const Text("vaya");
          if (!snap.hasData) return const CircularProgressIndicator();
          return Text("\${snap.data}");
        },
      )
    """;
    expect(
      _cuerpo(bueno, bueno.indexOf("FutureBuilder") + 13),
      contains("hasError"),
    );
  });

  test("el argumento de tipo no se confunde con la lista de argumentos", () {
    // La primera versión de este test señaló como rotos seis builders sanos:
    // en `FutureBuilder<(Temario, int)>(…)` se quedaba con `(Temario, int)`,
    // donde por supuesto no hay ningún `hasError`.
    const conTupla = """
      FutureBuilder<(Temario, int)>(
        future: algo,
        builder: (context, snap) {
          if (snap.hasError) return const Text("vaya");
          return const Text("ok");
        },
      )
    """;
    final cuerpo = _cuerpo(conTupla, conTupla.indexOf("FutureBuilder") + 13);
    expect(cuerpo, contains("hasError"));
    expect(cuerpo, contains("future: algo"));

    const conGenericoAnidado = """
      FutureBuilder<Map<String, List<int>>>(
        future: algo,
        builder: (c, s) {
          if (s.hasError) return const Text("vaya");
          return const Text("ok");
        },
      )
    """;
    expect(
      _cuerpo(
        conGenericoAnidado,
        conGenericoAnidado.indexOf("FutureBuilder") + 13,
      ),
      contains("hasError"),
    );
  });

  test("una mención en un comentario no es un widget", () {
    const fuente = """
      /// No le añade un `FutureBuilder` más al árbol por cada figura.
      void algo() {}
    """;
    expect(_enComentario(fuente, fuente.indexOf("FutureBuilder")), isTrue);
  });

  test("el recorte no se come un FutureBuilder anidado", () {
    // El caso que rompería un `indexOf(")")` ingenuo: el cierre del builder
    // interno no es el del externo.
    const anidado = """
      FutureBuilder<int>(
        future: a,
        builder: (c, s) => FutureBuilder<int>(future: b, builder: (c2, s2) {
          if (s2.hasError) return const Text("x");
          return const Text("y");
        }),
      )
    """;
    final cuerpo = _cuerpo(anidado, anidado.indexOf("FutureBuilder") + 13);
    expect(cuerpo, endsWith(")"));
    expect(cuerpo, contains("hasError"));
    expect(cuerpo, contains("future: b"));
  });
}
