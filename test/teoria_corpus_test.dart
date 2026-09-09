// Pasa el parser por las 1 829 secciones de teoría reales.
//
// Los tests de `markdown_teoria_test.dart` fijan el comportamiento con
// ejemplos escritos a mano; este comprueba el resultado sobre el contenido que
// el alumno va a leer de verdad, que es donde aparecen los casos que a nadie
// se le ocurre inventar.
//
// Las tres aserciones corresponden a los tres defectos medidos antes de
// portar `markdown-teoria.ts`:
//
//   · 865 secciones (47 %) mostraban líneas literales `![figura](assets/…)`
//     incrustadas a media frase.
//   · 984 secciones (54 %) mostraban los `**asteriscos**` de lo que en el PDF
//     original era un título.
//   · Y el riesgo al arreglarlo: separar líneas puede partir una fórmula
//     `$$…$$` de varias líneas, que hay en el 27 % de las secciones. Una
//     fórmula partida no da error — da dos trozos que parecen contenido—, así
//     que se cuenta antes y después y tienen que cuadrar exactamente.
//
// Si el contenido del repo web crece, las cifras del informe suben; lo que no
// puede cambiar es que los tres contadores de defecto sigan en cero.

// El recuento es la salida útil de este test.
// ignore_for_file: avoid_print

import "package:flutter_test/flutter_test.dart";
import "package:matr_u/datos/markdown_teoria.dart";
import "package:matr_u/datos/teoria.dart";

final _figura = RegExp(r"!\[[^\]]*\]\([^)]*\)");
final _tituloSinClasificar = RegExp(r"^\*\*[^*]+\*\*$");
final _formula = RegExp(r"\$\$([\s\S]+?)\$\$|\$([^\n$]+?)\$");

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("la teoría real se parte sin dejar marcado crudo ni romper fórmulas", () async {
    final cursos = await RepositorioTeoria().cursos();

    var secciones = 0;
    var marcadorCrudo = 0;
    var tituloCrudo = 0;
    var formulasAntes = 0;
    var formulasDespues = 0;
    final tipos = <String, int>{};

    for (final curso in cursos) {
      for (final seccion in curso.secciones) {
        if (!seccion.tieneContenido) continue;
        secciones++;
        formulasAntes += _formula.allMatches(seccion.markdown).length;

        for (final bloque in analizarTeoria(seccion.markdown)) {
          final tipo = bloque.runtimeType.toString();
          tipos[tipo] = (tipos[tipo] ?? 0) + 1;

          final texto = switch (bloque) {
            ParrafoTeoria(:final texto) => texto,
            TituloTeoria(:final texto) => texto,
            ItemTeoria(:final texto) => texto,
            // La figura ya no es texto: ese es justo el arreglo.
            FiguraTeoria() => "",
          };

          formulasDespues += _formula.allMatches(texto).length;
          if (_figura.hasMatch(texto)) marcadorCrudo++;
          if (_tituloSinClasificar.hasMatch(texto.trim())) tituloCrudo++;
        }
      }
    }

    print("");
    print("Secciones procesadas: $secciones");
    print("Bloques por tipo:     $tipos");
    print("Fórmulas: $formulasAntes antes · $formulasDespues después");
    print("");

    expect(
      secciones,
      greaterThan(0),
      reason: "¿corriste `node tool/sincronizar-datos.mjs`?",
    );
    expect(
      marcadorCrudo,
      0,
      reason: "$marcadorCrudo bloques siguen mostrando el marcador ![…] crudo",
    );
    expect(
      tituloCrudo,
      0,
      reason: "$tituloCrudo bloques siguen mostrando los ** de un título",
    );
    expect(
      formulasDespues,
      formulasAntes,
      reason:
          "Se perdieron o partieron fórmulas al separar líneas: "
          "$formulasAntes antes, $formulasDespues después. Revisa el paso de "
          "protección con centinelas en analizarTeoria().",
    );
  });
}
