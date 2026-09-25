// El parser de teoría, bloque a bloque.
//
// El caso que justifica el archivo entero es «no parte una fórmula que ocupa
// varias líneas»: el 27 % de las secciones tiene alguna, y romperla no da
// error — da una fórmula partida en dos párrafos, que es peor porque parece
// contenido.
import "package:flutter_test/flutter_test.dart";
import "package:matr_u/domain/models/markdown_teoria.dart";

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
      expect((b.single as FiguraTeoria).archivo, "8fc119d04b59a8e6.webp");
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

    // ── La viñeta pegada ────────────────────────────────────────────────
    //
    // El extractor del PDF deja 638 líneas con el «•» soldado a la primera
    // palabra. Exigiendo un espacio detrás, ninguna se reconocía: salían como
    // párrafo con el símbolo dentro del texto, y así se veían en la app
    // («•Se dibuja el primer vector.»). Eran el 37 % de las viñetas del
    // corpus, peor en geografía, física y literatura.

    test("un «•» sin espacio detrás sigue siendo una viñeta", () {
      final b = analizarTeoria("•Los organismos se reproducen");
      expect(b.single, isA<ItemTeoria>());
      final item = b.single as ItemTeoria;
      expect(item.marca, "•");
      expect(
        item.texto,
        "Los organismos se reproducen",
        reason: "el símbolo no debe quedarse dentro del texto",
      );
    });

    test("con espacio o sin él, el resultado es el mismo", () {
      final pegada = analizarTeoria("•Uno").single as ItemTeoria;
      final suelta = analizarTeoria("• Uno").single as ItemTeoria;
      expect(pegada.texto, suelta.texto);
      expect(pegada.marca, suelta.marca);
    });

    test("un «•» solo, sin texto, no es una viñeta vacía", () {
      // Hay dos líneas así en el corpus. Una viñeta sin contenido sería un
      // hueco con un punto al lado.
      final b = analizarTeoria("•");
      expect(b.whereType<ItemTeoria>(), isEmpty);
    });

    test("el guion pegado NO se toca: «-5 °C» es una temperatura", () {
      // Aflojar `-` como se aflojó `•` convertiría números negativos en
      // listas. Son 56 líneas del corpus y no compensan el riesgo.
      final b = analizarTeoria("-5 °C es el punto de partida");
      expect(b.single, isA<ParrafoTeoria>());
    });

    test("el asterisco pegado tampoco: es cursiva y es multiplicación", () {
      final b = analizarTeoria("*a* por *b*");
      expect(b.single, isA<ParrafoTeoria>());
    });

    test("un número pegado al punto NO es una lista: son años de cita", () {
      // 459 líneas del corpus empiezan por dígito y punto sin espacio, y casi
      // todas son referencias bibliográficas.
      for (final linea in ["2008).", "723). Elsevier.", "1.65 millones"]) {
        expect(
          analizarTeoria(linea).single,
          isA<ParrafoTeoria>(),
          reason: linea,
        );
      }
    });

    test("una línea entera en negrita gana a la viñeta", () {
      // El orden de las reglas importa: `**…**` se decide antes.
      final b = analizarTeoria("**TRIÁNGULO**");
      expect(b.single, isA<TituloTeoria>());
    });
  });
}
