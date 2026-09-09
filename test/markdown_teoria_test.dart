// El parser de teoría, bloque a bloque.
//
// El caso que justifica el archivo entero es «no parte una fórmula que ocupa
// varias líneas»: el 27 % de las secciones tiene alguna, y romperla no da
// error — da una fórmula partida en dos párrafos, que es peor porque parece
// contenido.
import "package:flutter_test/flutter_test.dart";
import "package:matr_u/datos/markdown_teoria.dart";

void main() {
  group("separación en bloques", () {
    test("cada línea del PDF es su propio bloque", () {
      final b = analizarTeoria("Primera línea\nSegunda línea\nTercera");
      expect(b, hasLength(3));
      expect(b.whereType<ParrafoTeoria>().map((p) => p.texto), [
        "Primera línea",
        "Segunda línea",
        "Tercera",
      ]);
    });

    test("las líneas en blanco no generan bloques vacíos", () {
      final b = analizarTeoria("Una\n\n\n   \nDos");
      expect(b, hasLength(2));
    });

    test("un markdown vacío no da bloques", () {
      expect(analizarTeoria(""), isEmpty);
      expect(analizarTeoria("   \n  \n"), isEmpty);
    });
  });

  group("fórmulas", () {
    test("una fórmula \$\$…\$\$ multilínea sobrevive entera", () {
      final b = analizarTeoria(
        "Antes\n\$\$\nx = \frac{a}{b}\n+ c\n\$\$\nDespués",
      );
      final parrafos = b.whereType<ParrafoTeoria>().toList();
      expect(parrafos, hasLength(3));
      // La del medio conserva sus saltos internos: no se partió en tres.
      expect(parrafos[1].texto, contains("x = \frac{a}{b}"));
      expect(parrafos[1].texto, contains("+ c"));
      expect(parrafos[1].texto.startsWith(r"$$"), isTrue);
      expect(parrafos[1].texto.endsWith(r"$$"), isTrue);
    });

    test("una fórmula en línea se queda dentro de su párrafo", () {
      final b = analizarTeoria(r"La energía es $E = mc^2$ siempre.");
      expect(b, hasLength(1));
      expect(
        (b.single as ParrafoTeoria).texto,
        r"La energía es $E = mc^2$ siempre.",
      );
    });

    test("un salto dentro de la fórmula no crea un título falso", () {
      // Si el marcador se rompiera, `**` sueltos dentro de la fórmula podrían
      // clasificarse como título.
      final b = analizarTeoria("\$\$\na ** b\n\$\$");
      expect(b, hasLength(1));
      expect(b.single, isA<ParrafoTeoria>());
    });
  });

  group("títulos", () {
    test("una línea entera en negrita es un título", () {
      final b = analizarTeoria("**TEMA 1:**\nEl análisis vectorial es…");
      expect(b.first, isA<TituloTeoria>());
      expect((b.first as TituloTeoria).texto, "TEMA 1:");
      expect(b[1], isA<ParrafoTeoria>());
    });

    test("una negrita a media frase NO es un título", () {
      final b = analizarTeoria("Esto es **importante** pero sigue el párrafo.");
      expect(b.single, isA<ParrafoTeoria>());
    });

    test("los encabezados # conservan su nivel", () {
      final b = analizarTeoria("# Uno\n## Dos\n#### Cuatro");
      final n = b.cast<TituloTeoria>().map((t) => t.nivel).toList();
      // El nivel se recorta a 3: más allá no hay escala tipográfica que lo
      // distinga en un móvil.
      expect(n, [1, 2, 3]);
    });
  });

  group("figuras", () {
    test("una figura sola es su propio bloque", () {
      final b = analizarTeoria("![figura](assets/8fc119d04b59a8e6.webp)");
      expect(b.single, isA<FiguraTeoria>());
      expect(
        (b.single as FiguraTeoria).archivo,
        "8fc119d04b59a8e6.webp",
      );
    });

    test("una figura incrustada se separa del texto que la rodea", () {
      // Es el caso real del corpus: el marcador aparecía a mitad de frase.
      final b = analizarTeoria(
        "son: longitud, masa,\n![figura](assets/a1.webp)\ntemperatura y trabajo",
      );
      expect(b.map((x) => x.runtimeType.toString()), [
        "ParrafoTeoria",
        "FiguraTeoria",
        "ParrafoTeoria",
      ]);
    });

    test("dos figuras seguidas en la misma línea dan dos bloques", () {
      final b = analizarTeoria("![f](assets/a.webp)![f](assets/b.webp)");
      expect(b.whereType<FiguraTeoria>(), hasLength(2));
    });

    test("un nombre con salto de directorio se degrada a texto", () {
      final b = analizarTeoria("![Diagrama](assets/../../etc/passwd)");
      expect(b.whereType<FiguraTeoria>(), isEmpty);
      expect((b.single as ParrafoTeoria).texto, "Diagrama");
    });

    test("nombreFiguraValido rechaza rutas y acepta nombres llanos", () {
      expect(nombreFiguraValido("8fc119d04b59a8e6.webp"), isTrue);
      expect(nombreFiguraValido("a/b.webp"), isFalse);
      expect(nombreFiguraValido("../x.webp"), isFalse);
    });
  });

  group("listas", () {
    test("las viñetas se normalizan a un solo símbolo", () {
      final b = analizarTeoria("- uno\n* dos");
      final items = b.cast<ItemTeoria>();
      expect(items.map((i) => i.marca), ["•", "•"]);
      expect(items.map((i) => i.texto), ["uno", "dos"]);
    });

    test("la lista numerada conserva su número", () {
      // El número es contenido, no adorno: el PDF numera pasos de un método.
      final b = analizarTeoria("1. primero\n2. segundo");
      expect(b.cast<ItemTeoria>().map((i) => i.marca), ["1.", "2."]);
    });

    test("un número a mitad de frase no crea una lista", () {
      final b = analizarTeoria("Se obtiene 3. Luego se simplifica.");
      expect(b.single, isA<ParrafoTeoria>());
    });
  });
}
