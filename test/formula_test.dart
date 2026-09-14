// `legibilizar()` es la red de seguridad de las 1 058 fórmulas del banco
// (7,7 % de 13 720) que `flutter_math_fork` no compila — ver
// `test/medir_formulas_test.dart` para la medición. Cuando el motor falla,
// `TextoConFormulas` llama a esta función y pinta lo que devuelva: es
// literalmente lo último que separa al alumno de ver código LaTeX en crudo.
//
// **No tenía ningún test, y estaba rota.** Las cuatro expresiones regulares
// escribían la barra invertida de LaTeX con una sola barra dentro de una cadena
// cruda, así que `r"\frac"` llegaba al motor de regex como `\f` (form feed)
// seguido de `rac`, `r"\sqrt"` como espacio + `qrt`, `r"\text"` como tabulador
// + `ext`, y `r"\[a-zA-Z]+"` como el corchete literal `[a-zA-Z]` repetido.
// Ninguno de los cuatro patrones reconocía lo que decía reconocer: la salida
// real era `\fracab` donde tocaba `a/b`.
//
// Los casos de abajo salen de fórmulas reales del banco, no inventadas: las
// causas de fallo que imprime `medir_formulas_test` son exactamente
// `\sqrt` sin grupo, `\frac` mal cerrado y `\vec` sin argumento.
import "package:flutter_test/flutter_test.dart";
import "package:matr_u/matematicas/formula.dart";

void main() {
  group("legibilizar", () {
    test("una fracción se vuelve una división legible", () {
      expect(legibilizar(r"\frac{a}{b}"), "a/b");
      expect(legibilizar(r"\frac{1}{2}"), "1/2");
    });

    test("una raíz con grupo se vuelve un radical legible", () {
      expect(legibilizar(r"\sqrt{x+1}"), "√(x+1)");
    });

    test("\\text deja solo su contenido", () {
      expect(legibilizar(r"\text{masa}"), "masa");
    });

    test("las órdenes que quedan sueltas se van, no se imprimen", () {
      // El caso que más se notaba: `\alpha` y `\beta` no tienen traducción a
      // un símbolo en esta función, así que el barrido final tiene que
      // quitarlas. Con la regex rota se quedaban tal cual en pantalla.
      expect(legibilizar(r"\alpha + \beta"), "+");
      expect(legibilizar(r"\displaystyle x"), "x");
    });

    test("los símbolos con traducción propia sobreviven al barrido", () {
      // Estos van por `replaceAll` con cadena llana, que nunca tuvo el
      // problema de las barras. El test los fija porque el barrido final de
      // órdenes sueltas, ahora que de verdad funciona, corre DESPUÉS: si
      // alguien reordenara los pasos, se los comería.
      expect(legibilizar(r"3 \times 4"), "3 × 4");
      expect(legibilizar(r"a \pm b"), "a ± b");
      expect(legibilizar(r"F \cdot d"), "F · d");
      expect(legibilizar(r"60^\circ"), "60°");
      expect(legibilizar(r"\Delta t"), "Δ t");
      expect(legibilizar(r"8 \div 2"), "8 ÷ 2");
    });

    test("nunca devuelve una barra invertida", () {
      // La invariante que de verdad importa, y la que fallaba en los seis
      // casos: pase lo que pase, al alumno no le llega marcado.
      const reales = [
        r"\frac{2PQcos\alpha }{\sqrt 3}",
        r"R= \sqrt A^{2}+ B^{2}",
        r"0\vec \vec \cdot \vec{A} = 0",
        r"\vec}{\Delta t} \Delta \vec{x}",
        r"mgh _{A}+ ^{1} ^{2}= ^{1}",
        r"E= cos6^\circ + sen6^\circ ^{- cos6^\circ }",
      ];
      for (final tex in reales) {
        expect(
          legibilizar(tex),
          isNot(contains(r"\")),
          reason: "quedó marcado LaTeX visible en: $tex",
        );
      }
    });

    test("no deja llaves, subíndices ni superíndices a la vista", () {
      for (final tex in [r"\frac{a}{b}", r"x^{2}", r"v_{0}", r"\sqrt{2}"]) {
        expect(legibilizar(tex), isNot(matches(r"[{}_^]")), reason: tex);
      }
    });

    test("una fracción anidada cae al barrido, no al patrón", () {
      // `[^{}]*` no puede con llaves dentro, así que `\frac` no coincide y lo
      // recoge el barrido final. Lo que NO puede pasar es que se vea `\frac`.
      final salida = legibilizar(r"\frac{\sqrt{2}}{3}");
      expect(salida, isNot(contains(r"\")));
      expect(salida, contains("2"));
      expect(salida, contains("3"));
    });

    test("el texto llano pasa intacto", () {
      expect(legibilizar("velocidad media"), "velocidad media");
      expect(legibilizar(""), "");
    });
  });
}
