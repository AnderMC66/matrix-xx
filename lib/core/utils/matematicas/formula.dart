import "package:flutter/material.dart";
import "package:flutter_math_fork/flutter_math.dart";

import "package:matr_u/ui/core/theme/tema.dart";

/// Puerto a Flutter de `src/lib/matematicas.ts`.
///
/// **Por qué existe y por qué no es una traducción directa.** En la web, ese
/// módulo emite MathML y lo dibuja el navegador: cero fuentes, cero CSS, cero
/// JavaScript en el cliente. Flutter no tiene motor de MathML ni de HTML —
/// pinta widgets—, así que aquí el LaTeX pasa por `flutter_math_fork`, que
/// implementa un subconjunto de KaTeX **más estrecho**.
///
/// Se conserva lo que sí se puede conservar: el mismo patrón de delimitadores
/// (`$$…$$` en bloque, `$…$` en línea), el mismo escape de `\$` literal, y
/// sobre todo la **misma estrategia de respaldo** — `legibilizar()`, portada
/// tal cual. Una fórmula que no compila nunca le muestra LaTeX crudo al
/// alumno: muestra texto legible, degradado pero leíble.
///
/// El contador `fallos` es lo que convierte esto en una sonda: al abrir la
/// pantalla de prueba dice cuántas fórmulas reales del banco no sobreviven al
/// cambio de motor. Ese número es el que decide si la migración es viable.

/// `$$…$$` en bloque, o `$…$` en línea sin cruzar saltos de línea.
final _patron = RegExp(r"\$\$([\s\S]+?)\$\$|\$([^\n$]+?)\$");

/// Último recurso cuando el motor no puede con la fórmula: en vez de mostrarle
/// al alumno el código LaTeX en crudo, se despoja el marcado y se deja el
/// texto que queda. No reconstruye la fórmula original — parte del contenido
/// importado son tablas que la extracción convirtió mal en pseudo-fracciones
/// (ESTADO.md § 8, «Fórmulas rotas») — pero cambia "esto es código roto" por
/// "esto es una frase suelta", que es lo que un alumno puede al menos leer.
///
/// **Las barras van dobladas, y no es cosmético.** En una cadena cruda `r"\f"`
/// llega al motor de expresiones regulares como `\f`, que ahí significa
/// *form feed* — no la barra invertida de LaTeX seguida de una efe. Lo mismo
/// con `\s` (espacio), `\t` (tabulador) y `\[` (corchete literal). Escrito
/// así, esta función no reconocía NINGUNO de los cuatro patrones que dice
/// reconocer: `\frac{a}{b}` salía como `\fracab`, `\sqrt{x}` como `\sqrtx`, y
/// el barrido final de órdenes sueltas no barría nada. `\\` es la barra de
/// verdad. Los `replaceAll` de más abajo nunca tuvieron el problema porque
/// reciben una cadena llana, no un patrón: ahí `r"\times"` ya es literal.
String legibilizar(String tex) {
  return tex
      .replaceAllMapped(
        RegExp(r"\\frac\{([^{}]*)\}\{([^{}]*)\}"),
        (m) => "${m[1]}/${m[2]}",
      )
      .replaceAllMapped(RegExp(r"\\sqrt\{([^{}]*)\}"), (m) => "√(${m[1]})")
      .replaceAll(r"\times", "×")
      .replaceAll(r"\div", "÷")
      .replaceAll(r"\pm", "±")
      .replaceAll(r"\cdot", "·")
      .replaceAll(r"\Delta", "Δ")
      .replaceAll(r"\circ", "°")
      .replaceAll(r"\vec", "")
      .replaceAll(r"\overline", "")
      .replaceAllMapped(RegExp(r"\\text\{([^{}]*)\}"), (m) => m[1] ?? "")
      // Lo que quede con forma de orden LaTeX se va: a estas alturas es
      // marcado que nadie va a leer, no contenido.
      .replaceAll(RegExp(r"\\[a-zA-Z]+"), "")
      .replaceAll(RegExp(r"[{}_^]"), "")
      .replaceAll(RegExp(r"[ \t]{2,}"), " ")
      .trim();
}

/// Un trozo del texto ya clasificado: prosa, fórmula en línea o en bloque.
sealed class Trozo {
  const Trozo();
}

class TrozoTexto extends Trozo {
  final String texto;
  const TrozoTexto(this.texto);
}

class TrozoFormula extends Trozo {
  final String tex;
  final bool enBloque;
  const TrozoFormula(this.tex, this.enBloque);
}

/// Parte el texto en prosa y fórmulas, siguiendo la misma lógica que
/// `renderizarMatematicas` en la web (incluido el recorte de saltos de línea
/// pegados a una fórmula en bloque, que si no dejan un hueco enorme).
List<Trozo> partir(String texto) {
  final trozos = <Trozo>[];
  var cursor = 0;
  var recortarSaltosIniciales = false;

  for (final m in _patron.allMatches(texto)) {
    // Un `$` precedido de barra invertida es literal.
    if (m.start > 0 && texto[m.start - 1] == r"\") continue;

    final enBloque = m.group(1) != null;
    final tex = (m.group(1) ?? m.group(2) ?? "").trim();

    var previo = texto.substring(cursor, m.start);
    if (recortarSaltosIniciales) {
      previo = previo.replaceFirst(RegExp(r"^[ \t]*\n\s*"), "");
    }
    if (enBloque) previo = previo.replaceFirst(RegExp(r"\s*\n[ \t]*$"), "");

    if (previo.isNotEmpty) trozos.add(TrozoTexto(previo));
    trozos.add(TrozoFormula(tex, enBloque));
    cursor = m.end;
    recortarSaltosIniciales = enBloque;
  }

  var resto = texto.substring(cursor);
  if (recortarSaltosIniciales) {
    resto = resto.replaceFirst(RegExp(r"^[ \t]*\n\s*"), "");
  }
  if (resto.isNotEmpty) trozos.add(TrozoTexto(resto));

  return trozos;
}

/// Texto con fórmulas embebidas, listo para pintar.
///
/// [alFallar] se llama una vez por fórmula que el motor no compila. Sirve para
/// contar el daño real sobre el banco; en producción se deja en `null`.
class TextoConFormulas extends StatelessWidget {
  final String texto;
  final TextStyle? estilo;
  final void Function(String tex, String error)? alFallar;

  /// Interpreta `**negrita**` y `_cursiva_` en las partes de prosa.
  ///
  /// Apagado por defecto porque el banco de preguntas no usa marcado —cero de
  /// 395 enunciados llevan `**`— y encenderlo ahí solo añadiría el riesgo de
  /// que un asterisco matemático suelto se coma media frase. La teoría sí lo
  /// usa (59 % de las secciones) y lo enciende.
  final bool conMarcado;

  const TextoConFormulas(
    this.texto, {
    super.key,
    this.estilo,
    this.alFallar,
    this.conMarcado = false,
  });

  @override
  Widget build(BuildContext context) {
    // `bodyLarge` es el cuerpo de lectura de la app: 16 px, interlineado 1,6.
    // Estaba escrito a mano con esos mismos números, que es como se empieza a
    // tener dos fuentes de verdad para lo mismo.
    final estiloBase = estilo ?? context.textos.bodyLarge!;

    // Se resuelve una vez aquí, donde hay contexto, y viaja como argumento:
    // el fallback de una fórmula rota corre dentro de `flutter_math`, fuera
    // del árbol, y allí no hay `context` que consultar.
    final colores = context.colores;

    final trozos = partir(texto);
    final hayBloque = trozos.any((t) => t is TrozoFormula && t.enBloque);

    // Sin fórmulas en bloque todo cabe en un párrafo continuo, que es lo que
    // permite que una fórmula en línea quede a media frase, como en la web.
    if (!hayBloque) {
      return RichText(
        text: TextSpan(
          style: estiloBase,
          children: trozos.map((t) => _span(t, estiloBase, colores)).toList(),
        ),
      );
    }

    // Con bloques hace falta apilar: un bloque ocupa su propia línea.
    final filas = <Widget>[];
    var acumulado = <InlineSpan>[];

    void volcar() {
      if (acumulado.isEmpty) return;
      filas.add(
        RichText(
          text: TextSpan(style: estiloBase, children: List.of(acumulado)),
        ),
      );
      acumulado = <InlineSpan>[];
    }

    for (final t in trozos) {
      if (t is TrozoFormula && t.enBloque) {
        volcar();
        filas.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(child: _formula(t.tex, estiloBase, true, colores)),
          ),
        );
      } else {
        acumulado.add(_span(t, estiloBase, colores));
      }
    }
    volcar();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: filas,
    );
  }

  InlineSpan _span(Trozo t, TextStyle estiloBase, ColoresApp colores) {
    if (t is TrozoTexto) {
      return conMarcado
          ? TextSpan(children: spansConMarcado(t.texto, estiloBase))
          : TextSpan(text: t.texto);
    }
    final f = t as TrozoFormula;
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: _formula(f.tex, estiloBase, false, colores),
    );
  }

  /// [colores] llega resuelto y no se lee de un `context` aquí dentro:
  /// `onErrorFallback` es un callback que `flutter_math` invoca cuando le da la
  /// gana, fuera del árbol, y ahí no hay contexto que consultar.
  Widget _formula(
    String tex,
    TextStyle estiloBase,
    bool enBloque,
    ColoresApp colores,
  ) {
    return Math.tex(
      tex,
      textStyle: estiloBase.copyWith(
        fontSize: enBloque ? estiloBase.fontSize! * 1.1 : estiloBase.fontSize,
      ),
      mathStyle: enBloque ? MathStyle.display : MathStyle.text,
      onErrorFallback: (error) {
        alFallar?.call(tex, error.messageWithType);
        return Text(
          legibilizar(tex),
          style: estiloBase.copyWith(
            fontFamily: "monospace",
            color: colores.aviso,
            backgroundColor: colores.avisoContenedor,
          ),
        );
      },
    );
  }
}

/// `**negrita**` y `_cursiva_` dentro de un trozo de prosa.
///
/// Se resuelve a mano y no con un motor de markdown porque a esta función solo
/// llega texto que YA no tiene fórmulas —`partir()` las separó antes—, así que
/// no hay que preocuparse por un `_` de subíndice ni por un `*` de
/// multiplicación dentro de una expresión.
///
/// Aun así, la cursiva exige que el `_` no esté pegado a letra o número: en la
/// prosa de este corpus aparecen cosas como `v_1` fuera de fórmula, y sin esa
/// guarda se comerían media frase en cursiva.
List<InlineSpan> spansConMarcado(String texto, TextStyle base) {
  final spans = <InlineSpan>[];
  var cursor = 0;

  for (final m in _marcado.allMatches(texto)) {
    if (m.start > cursor) {
      spans.add(TextSpan(text: texto.substring(cursor, m.start)));
    }
    final negrita = m[1];
    spans.add(
      negrita != null
          ? TextSpan(
              text: negrita,
              style: base.copyWith(fontWeight: FontWeight.w700),
            )
          : TextSpan(
              text: m[2],
              style: base.copyWith(fontStyle: FontStyle.italic),
            ),
    );
    cursor = m.end;
  }

  if (cursor < texto.length) {
    spans.add(TextSpan(text: texto.substring(cursor)));
  }
  return spans;
}

final _marcado = RegExp(
  r"\*\*([^*]+)\*\*"
  r"|(?<![A-Za-z0-9])_([^_\n]+)_(?![A-Za-z0-9])",
);
