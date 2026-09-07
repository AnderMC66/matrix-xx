import "package:flutter/material.dart";
import "package:flutter_math_fork/flutter_math.dart";

import "../tema.dart";

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
String legibilizar(String tex) {
  return tex
      .replaceAllMapped(
        RegExp(r"\frac\{([^{}]*)\}\{([^{}]*)\}"),
        (m) => "${m[1]}/${m[2]}",
      )
      .replaceAllMapped(RegExp(r"\sqrt\{([^{}]*)\}"), (m) => "√(${m[1]})")
      .replaceAll(r"\times", "×")
      .replaceAll(r"\div", "÷")
      .replaceAll(r"\pm", "±")
      .replaceAll(r"\cdot", "·")
      .replaceAll(r"\Delta", "Δ")
      .replaceAll(r"\circ", "°")
      .replaceAll(r"\vec", "")
      .replaceAll(r"\overline", "")
      .replaceAllMapped(RegExp(r"\text\{([^{}]*)\}"), (m) => m[1] ?? "")
      .replaceAll(RegExp(r"\[a-zA-Z]+"), "")
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

  const TextoConFormulas(
    this.texto, {
    super.key,
    this.estilo,
    this.alFallar,
  });

  @override
  Widget build(BuildContext context) {
    final estiloBase =
        estilo ??
        DefaultTextStyle.of(context).style.copyWith(
          fontSize: 16,
          height: 1.6,
          color: Paleta.texto,
        );

    final trozos = partir(texto);
    final hayBloque = trozos.any((t) => t is TrozoFormula && t.enBloque);

    // Sin fórmulas en bloque todo cabe en un párrafo continuo, que es lo que
    // permite que una fórmula en línea quede a media frase, como en la web.
    if (!hayBloque) {
      return RichText(
        text: TextSpan(
          style: estiloBase,
          children: trozos.map((t) => _span(t, estiloBase)).toList(),
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
            child: Center(child: _formula(t.tex, estiloBase, true)),
          ),
        );
      } else {
        acumulado.add(_span(t, estiloBase));
      }
    }
    volcar();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: filas,
    );
  }

  InlineSpan _span(Trozo t, TextStyle estiloBase) {
    if (t is TrozoTexto) return TextSpan(text: t.texto);
    final f = t as TrozoFormula;
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: _formula(f.tex, estiloBase, false),
    );
  }

  Widget _formula(String tex, TextStyle estiloBase, bool enBloque) {
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
            color: Paleta.aviso,
            backgroundColor: Paleta.avisoSuave,
          ),
        );
      },
    );
  }
}
