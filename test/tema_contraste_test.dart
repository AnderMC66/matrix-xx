// El contraste del tema, en los dos modos.
//
// **Existe porque el modo oscuro dobla la superficie donde algo puede volverse
// ilegible, y nadie lo ve hasta que alguien con la pantalla al 20 % de brillo
// intenta leer un aviso en el micro.** Un color que se eligió mirando el modo
// claro no dice nada del otro: el verde de «correcta» que se lee sobre blanco
// desaparece sobre #13121B.
//
// Los pares de Material 3 los garantiza el propio algoritmo —`onSurface` sobre
// `surface`, `onPrimary` sobre `primary`— y se comprueban igual, porque
// `fidelity` no es la variante por defecto y conviene no dar por hecho que se
// comporta como `tonalSpot`.
//
// Los que de verdad hay que vigilar son los de `ColoresApp`: esos los elegí a
// mano, no los deriva nadie, y son los únicos que pueden bajar de 4,5:1 sin
// que salte nada más.
//
// El umbral es WCAG AA para texto normal (4,5:1). No se usa el de texto grande
// (3:1) a propósito: casi todo lo que lleva estos colores son etiquetas de
// 11–14 px.
import "dart:math" as math;

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:matr_u/ui/core/theme/tema.dart";

/// Luminancia relativa según WCAG 2.1.
double _luminancia(Color c) {
  double canal(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * canal(c.r) + 0.7152 * canal(c.g) + 0.0722 * canal(c.b);
}

double contraste(Color a, Color b) {
  final la = _luminancia(a);
  final lb = _luminancia(b);
  final claro = math.max(la, lb);
  final oscuro = math.min(la, lb);
  return (claro + 0.05) / (oscuro + 0.05);
}

String _hex(Color c) =>
    "#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}";

void main() {
  test("el cálculo de contraste es el de WCAG", () {
    // Negro sobre blanco = 21:1, el máximo posible. Si esto falla, el resto de
    // este archivo no significa nada.
    expect(
      contraste(const Color(0xFF000000), const Color(0xFFFFFFFF)),
      closeTo(21, 0.01),
    );
    expect(
      contraste(const Color(0xFFFFFFFF), const Color(0xFFFFFFFF)),
      closeTo(1, 0.01),
    );
  });

  for (final brillo in [Brightness.light, Brightness.dark]) {
    final modo = brillo == Brightness.light ? "claro" : "oscuro";
    final tema = construirTema(brillo);
    final c = tema.colorScheme;
    final propios = tema.extension<ColoresApp>()!;

    group("modo $modo", () {
      /// Comprueba un par y, si falla, dice los dos colores y la cifra: sin
      /// eso, «esperaba ≥ 4.5» no le dice a nadie qué token retocar.
      void exigir(String que, Color frente, Color fondo, {double min = 4.5}) {
        final ratio = contraste(frente, fondo);
        expect(
          ratio,
          greaterThanOrEqualTo(min),
          reason:
              "$que: ${_hex(frente)} sobre ${_hex(fondo)} da "
              "${ratio.toStringAsFixed(2)}:1, y hace falta $min:1",
        );
      }

      test("el texto principal se lee sobre cada superficie", () {
        exigir("onSurface / surface", c.onSurface, c.surface);
        exigir(
          "onSurface / surfaceContainerLow",
          c.onSurface,
          c.surfaceContainerLow,
        );
        exigir(
          "onSurface / surfaceContainerHigh",
          c.onSurface,
          c.surfaceContainerHigh,
        );
      });

      test("el texto secundario también, que es donde suele fallar", () {
        // `onSurfaceVariant` es el color de los metadatos: fechas, «3 de 20»,
        // descripciones. Es el que más tienta bajar de contraste porque
        // «tiene que verse menos», y el que más gente lee.
        exigir("onSurfaceVariant / surface", c.onSurfaceVariant, c.surface);
        exigir(
          "onSurfaceVariant / surfaceContainer",
          c.onSurfaceVariant,
          c.surfaceContainer,
        );
      });

      test("lo que va encima de los rellenos de color", () {
        exigir("onPrimary / primary", c.onPrimary, c.primary);
        exigir(
          "onPrimaryContainer / primaryContainer",
          c.onPrimaryContainer,
          c.primaryContainer,
        );
        exigir(
          "onSecondaryContainer / secondaryContainer",
          c.onSecondaryContainer,
          c.secondaryContainer,
        );
        exigir("onError / error", c.onError, c.error);
        exigir(
          "onErrorContainer / errorContainer",
          c.onErrorContainer,
          c.errorContainer,
        );
      });

      test("el veredicto de práctica, en sus dos caras", () {
        // `_Veredicto` pinta el título —«Correcta» o «La respuesta era D»— con
        // `exito` y con `error` SOBRE su contenedor, no sobre la superficie.
        // Es el par que de verdad se ve, y el que faltaba: la caja de fallo
        // estuvo pintada con `secondaryContainer`, el lila de la marca, con el
        // título en rojo encima.
        exigir(
          "exito / exitoContenedor",
          propios.exito,
          propios.exitoContenedor,
        );
        exigir("error / errorContainer", c.error, c.errorContainer);
        // La explicación va en negro sobre las dos cajas, no en el color del
        // veredicto: ver la nota en `_Veredicto`.
        exigir(
          "onSurface / exitoContenedor",
          c.onSurface,
          propios.exitoContenedor,
        );
        exigir("onSurface / errorContainer", c.onSurface, c.errorContainer);
      });

      test("el error se lee sobre la superficie, no solo sobre su contenedor", () {
        // Se usa como color de texto suelto —el mensaje bajo un campo— así que
        // el par que importa es contra la superficie.
        exigir("error / surface", c.error, c.surface);
      });

      test("los tokens propios, que son los que elegí a mano", () {
        exigir("exito / surface", propios.exito, c.surface);
        exigir(
          "enExitoContenedor / exitoContenedor",
          propios.enExitoContenedor,
          propios.exitoContenedor,
        );
        exigir("aviso / surface", propios.aviso, c.surface);
        exigir(
          "enAvisoContenedor / avisoContenedor",
          propios.enAvisoContenedor,
          propios.avisoContenedor,
        );
      });

      test("los bordes se ven, que si no la tarjeta flota sin recortarse", () {
        // 3:1 y no 4,5:1: es el umbral de WCAG para elementos no textuales, y
        // un borde que llegara a 4,5 sería una raya negra.
        exigir("outline / surface", c.outline, c.surface, min: 3);
        exigir(
          "outlineVariant / surfaceContainerLow",
          c.outlineVariant,
          c.surfaceContainerLow,
          min: 1.3,
        );
      });
    });
  }

  test("los dos modos existen y son distintos", () {
    final claro = construirTema(Brightness.light);
    final oscuro = construirTema(Brightness.dark);

    expect(claro.colorScheme.brightness, Brightness.light);
    expect(oscuro.colorScheme.brightness, Brightness.dark);
    expect(
      claro.colorScheme.surface,
      isNot(oscuro.colorScheme.surface),
      reason: "si coincidieran, el tema oscuro no sería tal",
    );
    expect(
      claro.extension<ColoresApp>()!.exito,
      isNot(oscuro.extension<ColoresApp>()!.exito),
      reason:
          "el verde de «correcta» tiene que cambiar con el tema; si no, "
          "desaparece sobre el fondo oscuro",
    );
  });

  test("la semilla sobrevive al modo oscuro, que es por lo que se cambió", () {
    // El granate anterior derivaba a #FFB2BD, un rosa: por eso la app estaba
    // fijada en claro. Lo que se comprueba aquí es que el índigo no repita esa
    // historia — que su primario oscuro siga siendo más azul que rojo.
    final oscuro = construirTema(Brightness.dark).colorScheme.primary;
    expect(
      oscuro.b,
      greaterThan(oscuro.r),
      reason:
          "${_hex(oscuro)} tiene más rojo que azul: la semilla no aguanta el "
          "modo oscuro, que es exactamente lo que le pasaba al granate",
    );
  });
}
