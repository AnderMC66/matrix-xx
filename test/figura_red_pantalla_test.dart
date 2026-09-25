// `FiguraRed`: cómo se pinta una figura que viene por red.
//
// Estaba al **0 %**, el último archivo de `lib/` sin una sola línea cubierta.
// Lo que se prueba aquí es todo lo que decide sin salir a la red, que resulta
// ser casi todo lo que importa:
//
//   - **Una figura de la lista de rotas no se pide siquiera.** Son 149 que
//     decodifican bien y son un rectángulo negro sólido: viene roto desde la
//     extracción del PDF, no es un fallo de red, y pedirlas para acabar
//     pintando negro sería peor que el aviso.
//   - **«sin contenido en el original» y «no disponible todavía» son avisos
//     distintos**, y la diferencia no es cosmética: el primero no va a
//     aparecer nunca, el segundo puede aparecer mañana. Prometer lo que no va
//     a pasar es lo que evita esa distinción.
//   - **El `alt` literal «figura» no se anuncia.** La teoría lo trae casi
//     siempre; leerlo en voz alta es ruido, y Flutter ya dice que hay una
//     imagen. Los `alt` de preguntas sí describen, y ahí la etiqueta es media
//     pregunta de geometría.
//   - **Las de pregunta reservan el hueco con su proporción real** para que el
//     enunciado no dé un salto mientras el alumno lee; las de teoría no, que
//     aparecen miles de veces y convertirían el primer segundo de cada sección
//     en una pared de recuadros.
//
// **Lo que este archivo NO prueba, y por qué.** La rama de «la descarga
// falló» no se puede ejercitar aquí: `cached_network_image` guarda en disco a
// través de `path_provider`, que necesita un canal de plataforma inexistente en
// un proceso de test, así que la carga ni progresa ni falla — se queda en el
// marcador. Forzarla exigiría un `CacheManager` falso y un arnés propio, y eso
// cuesta más de lo que rinde: lo que decide esta clase —qué figura ni se pide,
// qué `alt` se anuncia, qué forma reserva el hueco y qué cargador atiende cada
// formato— se decide ANTES de tocar la red, y es lo que está cubierto.
//
// Lo que sí se ve del camino de carga es el marcador, que también es una
// decisión: recuadro con proporción reservada en preguntas, una línea en
// teoría.
//
// Por lo mismo queda fuera la rama del `.svg`. Montarla dispara el cargador de
// `flutter_svg`, que pide los bytes por red y solo entonces intenta parsearlos;
// con el cuerpo vacío que devuelve el binding, el parser lanza «Invalid SVG
// data» **después** de que el test haya terminado, así que no hay forma de
// consumir esa excepción sin un arnés de red. Un test que falla por el reloj y
// no por el código es peor que no tenerlo. Hoy es una sola figura del banco
// —el trapecio de `GEO-06-01`— y `datos/preguntas.dart` ya fija que su `src`
// sobreviva a la carga.
import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter/services.dart" show rootBundle;
import "package:flutter_test/flutter_test.dart";
import "package:matr_u/data/repositories/figuras_rotas.dart";
import "package:matr_u/ui/core/theme/tema.dart";
import "package:matr_u/ui/features/practice/views/figura_red.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // La app la precarga en `main.dart` antes de mostrar nada, para que la
    // consulta de «¿está rota?» sea síncrona y no añada un `FutureBuilder` por
    // cada una de las miles de figuras de teoría.
    await RepositorioFigurasRotas.instancia.cargar();
  });

  /// Un nombre que de verdad está en `assets/figuras_rotas.json`.
  ///
  /// Se lee del asset en vez de fijar uno a mano: la lista la regenera
  /// `tool/detectar-figuras-rotas.mjs` cuando el banco de contenido cambia, y
  /// un nombre inventado aquí dejaría el test verde por el motivo equivocado
  /// —no por reconocer una figura rota, sino por no reconocer ninguna.
  late String unaRota;

  setUpAll(() async {
    final crudo = await rootBundle.loadString("assets/figuras_rotas.json");
    final nombres = (jsonDecode(crudo) as List).cast<String>();
    expect(
      nombres,
      isNotEmpty,
      reason: "la lista de rotas no puede estar vacía",
    );
    unaRota = nombres.first;
  });

  Future<void> montar(WidgetTester tester, Widget figura) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: construirTema(),
        home: Scaffold(body: SingleChildScrollView(child: figura)),
      ),
    );
    // Vueltas cortas: la descarga falla sola contra el binding de test.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  group("cuando la imagen no llega", () {
    testWidgets("la de una pregunta reserva el hueco con su proporción", (
      tester,
    ) async {
      await montar(
        tester,
        const FiguraRed(
          url: "https://ejemplo.test/preguntas/geo-001.webp",
          alt: "Trapecio ABCD con bases paralelas",
          proporcion: 16 / 9,
          grande: true,
        ),
      );

      final proporciones = tester
          .widgetList<AspectRatio>(find.byType(AspectRatio))
          .map((a) => a.aspectRatio);
      expect(
        proporciones,
        contains(16 / 9),
        reason:
            "sin el hueco reservado, el enunciado da un salto justo cuando el "
            "alumno lo está leyendo",
      );
    });

    testWidgets("el alt descriptivo de una pregunta sí se anuncia", (
      tester,
    ) async {
      await montar(
        tester,
        const FiguraRed(
          url: "https://ejemplo.test/preguntas/geo-001.webp",
          alt: "Trapecio ABCD con bases paralelas",
          grande: true,
        ),
      );

      final etiquetas = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .map((s) => s.properties.label)
          .whereType<String>();
      expect(
        etiquetas,
        contains("Trapecio ABCD con bases paralelas"),
        reason:
            "`CachedNetworkImage` no tiene `semanticLabel`, así que la etiqueta "
            "se pone a mano; en una pregunta de geometría el alt es media "
            "pregunta",
      );
    });

    testWidgets("la de teoría se queda en una línea, sin recuadro", (
      tester,
    ) async {
      await montar(
        tester,
        const FiguraRed(
          url: "https://ejemplo.test/teoria-figuras/bio-014.webp",
          alt: "figura",
        ),
      );

      expect(
        find.byType(AspectRatio),
        findsNothing,
        reason:
            "con 3 827 apariciones, un recuadro reservado por figura "
            "convertiría el primer segundo de cada sección en una pared de "
            "huecos vacíos",
      );
      expect(
        find.textContaining("Cargando figura"),
        findsOneWidget,
        reason: "mientras resuelve sigue siendo una línea, no un bloque",
      );
    });

    testWidgets("los dos avisos son distintos, y la diferencia importa", (
      tester,
    ) async {
      // Una rota: «sin contenido en el original» — esta no va a aparecer
      // nunca, por mucho que mejore la red.
      await montar(
        tester,
        FiguraRed(url: "https://ejemplo.test/teoria-figuras/$unaRota", alt: ""),
      );
      expect(
        find.textContaining("sin contenido en el original"),
        findsOneWidget,
      );
      expect(
        find.textContaining("no disponible todavía"),
        findsNothing,
        reason:
            "eso es lo otro: lo que todavía puede llegar. Prometer lo que no "
            "va a pasar es justo lo que esta distinción evita",
      );
    });
  });

  group("el alt que se anuncia", () {
    testWidgets("el literal «figura» no se lee en voz alta", (tester) async {
      await montar(
        tester,
        const FiguraRed(
          url: "https://ejemplo.test/teoria-figuras/bio-014.webp",
          alt: "figura",
        ),
      );

      final etiquetas = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .map((s) => s.properties.label)
          .whereType<String>();
      expect(
        etiquetas,
        isNot(contains("figura")),
        reason:
            "la teoría lo trae casi siempre y no describe nada; Flutter ya "
            "anuncia que hay una imagen",
      );
    });

    testWidgets("un alt vacío tampoco", (tester) async {
      await montar(
        tester,
        const FiguraRed(
          url: "https://ejemplo.test/teoria-figuras/bio-014.webp",
          alt: "   ",
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group("una figura rota", () {
    testWidgets("se declara sin contenido y no se pide por red", (
      tester,
    ) async {
      await montar(
        tester,
        FiguraRed(url: "https://ejemplo.test/teoria-figuras/$unaRota", alt: ""),
      );

      expect(
        find.textContaining("sin contenido en el original"),
        findsOneWidget,
      );
    });

    testWidgets("el repositorio distingue lo roto de lo que no está", (
      tester,
    ) async {
      expect(
        RepositorioFigurasRotas.instancia.esta("no-esta-en-la-lista.webp"),
        isFalse,
        reason:
            "un nombre desconocido nunca se marca como roto: en el peor caso "
            "se intenta cargar y cae al aviso normal, nunca al revés",
      );
    });
  });
}
