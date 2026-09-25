// Las capas solo apuntan hacia dentro.
//
// Separar `domain/`, `data/` y `ui/` en carpetas no separa nada por sí solo:
// basta un `import` para que un modelo empiece a saber de widgets, y a partir
// de ahí la estructura es decoración. Lo que sostiene una arquitectura por
// capas es la **dirección** de las dependencias, y eso no lo comprueba el
// compilador —importar «hacia fuera» es Dart perfectamente válido—.
//
// De ahí este archivo. Es un test de la forma del repo, no de su
// comportamiento, como `sin_spinner_eterno_test.dart`.
//
// La regla, de dentro hacia fuera:
//
//   domain/   no importa NADA del proyecto salvo otro domain/.
//   data/     importa domain/ y core/. Nunca ui/.
//   core/     no importa ni data/ ni ui/ ni domain/: son utilidades sueltas.
//   ui/       importa lo que necesite. Es la capa de fuera.
//
// El caso que de verdad quiere atrapar esto es el segundo: un repositorio que
// devuelve un `Color`, un `Icon` o un `BuildContext` porque en su momento era
// lo más corto. Cuando eso pasa, la capa de datos deja de poder probarse sin
// levantar un árbol de widgets, que es exactamente el agujero del que salió
// este proyecto —las pantallas construían `Supabase.instance.client` en su
// estado y ninguna se podía montar en un test—.
import "dart:io";

import "package:flutter_test/flutter_test.dart";

/// Los imports de `package:matr_u/...` de un archivo.
List<String> _importaDelProyecto(File archivo) {
  final propios = <String>[];
  for (final linea in archivo.readAsLinesSync()) {
    final recorte = linea.trimLeft();
    if (!recorte.startsWith("import") && !recorte.startsWith("export")) {
      // Los imports van arriba del todo: en cuanto empieza el código, fuera.
      if (recorte.isNotEmpty &&
          !recorte.startsWith("//") &&
          !recorte.startsWith("library") &&
          !recorte.startsWith("part")) {
        break;
      }
      continue;
    }
    final comillas = RegExp('"([^"]+)"').firstMatch(recorte);
    final uri = comillas?.group(1);
    if (uri != null && uri.startsWith("package:matr_u/")) {
      propios.add(uri.substring("package:matr_u/".length));
    }
  }
  return propios;
}

List<File> _dartsDe(String carpeta) {
  final dir = Directory(carpeta);
  if (!dir.existsSync()) return const [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith(".dart"))
      .toList();
}

/// Comprueba que nada bajo [carpeta] importa algo de [prohibidas].
void _exigir({
  required String carpeta,
  required List<String> prohibidas,
  required String porque,
}) {
  final culpables = <String>[];
  for (final archivo in _dartsDe(carpeta)) {
    for (final uri in _importaDelProyecto(archivo)) {
      if (prohibidas.any(uri.startsWith)) {
        culpables.add("${archivo.path.replaceAll(r"\", "/")}  ->  $uri");
      }
    }
  }
  expect(culpables, isEmpty, reason: "$porque\n\n${culpables.join("\n")}\n");
}

void main() {
  test("el dominio no sabe de dónde salen sus datos ni cómo se pintan", () {
    _exigir(
      carpeta: "lib/domain",
      prohibidas: ["data/", "ui/", "core/", "main.dart"],
      porque:
          "Un modelo que importa su repositorio deja de poder construirse en "
          "un test sin tocar la red, y deja de poder reusarse desde otro "
          "origen de datos. El dominio es el centro: todo apunta hacia él, y "
          "él a nadie.",
    );
  });

  test("los datos no saben de la interfaz", () {
    _exigir(
      carpeta: "lib/data",
      prohibidas: ["ui/", "main.dart"],
      porque:
          "Es la que más fácil se rompe: basta que un repositorio devuelva un "
          "Color o reciba un BuildContext. A partir de ahí la capa de datos "
          "no se puede probar sin levantar un árbol de widgets.",
    );
  });

  test("las utilidades de core no dependen de nadie del proyecto", () {
    _exigir(
      carpeta: "lib/core",
      prohibidas: ["data/", "ui/", "domain/", "main.dart"],
      porque:
          "`core/` son fechas, fórmulas y configuración: piezas sueltas que "
          "usan las tres capas. Si empieza a importar, deja de ser la base y "
          "se vuelve un nudo.",
    );
  });

  test("los repositorios viven en data/repositories y en ningún otro sitio", () {
    // La separación se deshace por el camino fácil: alguien añade
    // `RepositorioX` al lado del modelo que devuelve, «que es donde se usa».
    final fuera = <String>[];
    for (final carpeta in ["lib/domain", "lib/ui", "lib/core"]) {
      for (final archivo in _dartsDe(carpeta)) {
        final fuente = archivo.readAsStringSync();
        final m = RegExp(
          r"^class (Repositorio[A-Za-z0-9_]*)",
          multiLine: true,
        ).firstMatch(fuente);
        if (m != null) {
          fuera.add("${archivo.path.replaceAll(r"\", "/")}  ${m[1]}");
        }
      }
    }
    expect(fuera, isEmpty, reason: fuera.join("\n"));
  });

  test("solo data/ habla con Supabase y con el bundle de assets", () {
    // Las dos fronteras externas de la app. Si `ui/` las cruza directamente,
    // esa pantalla vuelve a ser imposible de montar en un test.
    final culpables = <String>[];
    for (final carpeta in ["lib/domain", "lib/ui", "lib/core"]) {
      for (final archivo in _dartsDe(carpeta)) {
        for (final linea in archivo.readAsLinesSync()) {
          // Los comentarios no son código. Media docena de pantallas EXPLICAN
          // en su doc por qué reciben sus repositorios ya construidos —«…
          // resuelve `Supabase.instance.client` en su constructor, así que…»—,
          // y sin esta línea la comprobación señalaba justo a los archivos que
          // hacen lo correcto. Es el mismo tropiezo que ya tuvo el
          // comprobador de `setState` de flecha.
          final recorte = linea.trimLeft();
          if (recorte.startsWith("//")) continue;
          if (linea.contains("Supabase.instance") ||
              linea.contains("rootBundle")) {
            culpables.add(
              "${archivo.path.replaceAll(r"\", "/")}  ${linea.trim()}",
            );
          }
        }
      }
    }
    expect(culpables, isEmpty, reason: culpables.join("\n"));
  });
}
