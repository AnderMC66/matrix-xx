/// Puerto de `src/lib/markdown-teoria.ts`: convierte el markdown crudo de una
/// sección de teoría en bloques que la pantalla sabe pintar.
///
/// **El orden de los pasos es lo único que importa aquí**, y es el mismo que
/// en la web:
///
/// 1. **Proteger las fórmulas.** Se sacan primero y se dejan marcadores en su
///    sitio. En la web esto lo consigue `renderizarMatematicas`, que emite
///    MathML en una sola línea; aquí no se puede renderizar todavía —eso pasa
///    al pintar—, así que se sustituyen por un centinela. Sin este paso el
///    paso 2 partiría por la mitad las fórmulas `$$…$$` que ocupan varias
///    líneas, y **el 27 % de las secciones tiene alguna** (499 de 1 829).
/// 2. **Cada línea es su propio bloque.** El extractor de PDF deja una línea
///    del documento original por línea de texto, unidas por `\n` simples. Sin
///    separarlas, todo queda en un párrafo gigante; separándolas, una figura
///    que estaba incrustada a mitad de frase pasa a ser su propio bloque, y
///    una línea que es enteramente `**negrita**` —el único recurso
///    tipográfico que trae el PDF para lo que funcionaba como título— queda
///    sola y se puede destacar como tal.
/// 3. **Clasificar.** Título, figura, ítem de lista o párrafo.
///
/// El parser cubre exactamente lo que hay en el corpus, medido sobre las 1 829
/// secciones con contenido: negrita 59 %, línea entera en negrita 54 %, figura
/// 47 %, lista numerada 7 %, viñeta 6 %, encabezado `#` 4 %, cursiva 3 %.
/// Tablas, citas, código y enlaces aparecen en menos del 1 % y se dejan pasar
/// como texto llano a propósito: un motor de markdown completo para cinco
/// casos sería más superficie de la que se gana.
library;

sealed class BloqueTeoria {
  const BloqueTeoria();
}

/// Un encabezado `#`, o una línea que era toda `**negrita**`.
class TituloTeoria extends BloqueTeoria {
  final String texto;
  final int nivel;
  const TituloTeoria(this.texto, {this.nivel = 2});
}

/// Texto corrido. Puede llevar LaTeX (`$…$`) y marcado en línea.
class ParrafoTeoria extends BloqueTeoria {
  final String texto;
  const ParrafoTeoria(this.texto);
}

/// Un ítem de lista. [marca] es la viñeta o el número original, que se
/// conserva porque en una lista numerada el número es contenido, no adorno.
class ItemTeoria extends BloqueTeoria {
  final String texto;
  final String marca;
  const ItemTeoria(this.texto, {required this.marca});
}

/// `![alt](assets/<hash>.<ext>)`.
///
/// [archivo] es el nombre suelto, sin el prefijo `assets/`: las figuras no
/// viajan en el APK y se resolverán contra Supabase Storage.
class FiguraTeoria extends BloqueTeoria {
  final String archivo;
  final String alt;
  const FiguraTeoria({required this.archivo, required this.alt});
}

/// Mismo patrón que `formula.dart`: `$$…$$` en bloque o `$…$` en línea.
final _formula = RegExp(r"\$\$([\s\S]+?)\$\$|\$([^\n$]+?)\$");

final _figura = RegExp(r"!\[([^\]]*)\]\(([^)]*)\)");
final _encabezado = RegExp(r"^(#{1,6})\s+(.*)$");
final _lineaNegrita = RegExp(r"^\*\*([^*]+)\*\*$");
final _vineta = RegExp(r"^([-*•])\s+(.*)$");
final _numerada = RegExp(r"^(\d+[.)])\s+(.*)$");

/// Centinelas en el Área de Uso Privado de Unicode. Se comprobó que no
/// aparecen en ninguno de los 15 archivos de teoría; si algún día lo hicieran,
/// lo peor que pasa es que esa fórmula se restaure en el sitio equivocado.
const _abre = "\uE000";
const _cierra = "\uE001";

/// Nombre de archivo llano, sin rutas ni saltos de directorio.
///
/// Es el mismo criterio que `nombreFiguraTeoriaValido` en la web. Allí evita
/// construir una ruta pública que apunte fuera de su carpeta; aquí, una URL de
/// Storage que apunte a otro sitio con un banco manipulado.
bool nombreFiguraValido(String nombre) =>
    RegExp(r"^[A-Za-z0-9._-]+$").hasMatch(nombre) && !nombre.contains("..");

/// Parte el markdown de una sección en bloques.
List<BloqueTeoria> analizarTeoria(String markdown) {
  if (markdown.trim().isEmpty) return const [];

  // --- 1. Proteger las fórmulas -------------------------------------------
  final formulas = <String>[];
  final protegido = markdown.replaceAllMapped(_formula, (m) {
    // Un `$` precedido de barra invertida es literal, igual que en
    // `formula.dart`. Se devuelve tal cual para no tratarlo como fórmula.
    if (m.start > 0 && markdown[m.start - 1] == r"\") return m[0]!;
    formulas.add(m[0]!);
    return "$_abre${formulas.length - 1}$_cierra";
  });

  // --- 2. Una línea, un bloque --------------------------------------------
  final bloques = <BloqueTeoria>[];
  for (final cruda in protegido.split("\n")) {
    final linea = cruda.trim();
    if (linea.isEmpty) continue;
    _clasificar(linea, formulas, bloques);
  }

  return bloques;
}

void _clasificar(
  String linea,
  List<String> formulas,
  List<BloqueTeoria> destino,
) {
  // Una figura puede venir sola en su línea (lo habitual) o pegada a texto.
  // En vez de elegir un caso, se extraen las figuras y el texto que las rodea
  // se sigue clasificando: así ninguna se pierde ni deja el marcador crudo a
  // media frase, que es justo lo que se veía antes de esto.
  if (_figura.hasMatch(linea)) {
    var cursor = 0;
    for (final m in _figura.allMatches(linea)) {
      final antes = linea.substring(cursor, m.start).trim();
      if (antes.isNotEmpty) _clasificarSimple(antes, formulas, destino);

      final href = m[2] ?? "";
      final archivo = href.replaceFirst(RegExp(r"^assets/"), "");
      final alt = (m[1] ?? "").trim();
      // Un nombre que no pasa la comprobación no se convierte en una figura
      // rota: se degrada al texto alternativo, que es lo que el lector
      // necesita de todos modos.
      if (nombreFiguraValido(archivo)) {
        destino.add(
          FiguraTeoria(archivo: archivo, alt: alt.isEmpty ? "Figura" : alt),
        );
      } else if (alt.isNotEmpty) {
        destino.add(ParrafoTeoria(_restaurar(alt, formulas)));
      }
      cursor = m.end;
    }
    final resto = linea.substring(cursor).trim();
    if (resto.isNotEmpty) _clasificarSimple(resto, formulas, destino);
    return;
  }

  _clasificarSimple(linea, formulas, destino);
}

void _clasificarSimple(
  String linea,
  List<String> formulas,
  List<BloqueTeoria> destino,
) {
  String texto(String s) => _restaurar(s.trim(), formulas);

  if (_encabezado.firstMatch(linea) case final m?) {
    destino.add(
      TituloTeoria(texto(m[2]!), nivel: m[1]!.length.clamp(1, 3)),
    );
    return;
  }

  // La línea entera en negrita es el título del PDF original: el extractor no
  // conserva encabezados, solo el `**` con que venían marcados.
  if (_lineaNegrita.firstMatch(linea) case final m?) {
    destino.add(TituloTeoria(texto(m[1]!)));
    return;
  }

  if (_vineta.firstMatch(linea) case final m?) {
    destino.add(ItemTeoria(texto(m[2]!), marca: "•"));
    return;
  }

  if (_numerada.firstMatch(linea) case final m?) {
    destino.add(ItemTeoria(texto(m[2]!), marca: m[1]!));
    return;
  }

  destino.add(ParrafoTeoria(texto(linea)));
}

String _restaurar(String texto, List<String> formulas) =>
    texto.replaceAllMapped(RegExp("$_abre(\\d+)$_cierra"), (m) {
      final i = int.parse(m[1]!);
      return i < formulas.length ? formulas[i] : m[0]!;
    });
