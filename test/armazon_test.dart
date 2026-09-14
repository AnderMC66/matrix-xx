// El armazón de pestañas: qué se conserva al cambiar de una a otra y qué no.
//
// Antes, el cuerpo era un `switch` que devolvía una pantalla distinta por
// pestaña, así que cambiar de pestaña DESTRUÍA la anterior. Volver a Teoría
// después de mirar Práctica te devolvía al principio de la lista de cursos, y
// lo mismo con el índice de secciones o con una búsqueda a medio escribir. En
// una app que se usa a ratos, entre clase y clase, perder el sitio en cada ida
// y vuelta se nota más que ninguna otra cosa.
//
// Lo que este archivo fija es la decisión, que tiene dos mitades y sería fácil
// romper a medias:
//
//   Teoría y Práctica     se conservan. Se alimentan del catálogo del APK, que
//                         es inmutable: guardar su estado no puede enseñar
//                         nada viejo.
//   Repaso, Simulacro,    NO se conservan. Leen del servidor lo que el propio
//   Progreso              alumno acaba de cambiar —responder una pregunta
//                         mueve la racha, los repasos y el diagnóstico—, así
//                         que mantenerlas vivas mostraría cifras de hace un
//                         rato como si fueran de ahora.
//
// `Armazon` acepta una `Sesion` inyectada porque `Sesion()` toca
// `Supabase.instance.client` en su constructor. Se le da una construida sobre
// un `http.Client` falso, sin sesión iniciada: así las tres pestañas de
// servidor enseñan su aviso de «necesitas tu cuenta» en vez de pedir red.
import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:matr_u/datos/preguntas.dart";
import "package:matr_u/datos/sesion.dart";
import "package:matr_u/datos/temario.dart";
import "package:matr_u/datos/teoria.dart";
import "package:matr_u/main.dart";
import "package:matr_u/tema.dart";
import "package:supabase/supabase.dart";

class _ClienteMudo extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest peticion) async =>
      http.StreamedResponse(
        Stream.value(utf8.encode("[]")),
        200,
        headers: const {"content-type": "application/json; charset=utf-8"},
        request: peticion,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SupabaseClient cliente;

  setUp(() {
    cliente = SupabaseClient(
      "https://proyecto.supabase.co",
      "sb_publishable_de_mentira",
      httpClient: _ClienteMudo(),
    );
  });

  tearDown(() async => cliente.dispose());

  /// Deja el catálogo en memoria: `rootBundle` descomprime en un isolate y
  /// `testWidgets` corre en async falso. Ver la nota larga de
  /// `desborde_test.dart`.
  Future<void> calentar(WidgetTester tester) => tester.runAsync(() async {
    await RepositorioTemario().cargar();
    await RepositorioPreguntas().cargar();
    await RepositorioTeoria().cursos();
  });

  Future<void> montar(WidgetTester tester, {int destino = 1}) async {
    await calentar(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: construirTema(),
        home: Armazon(
          destinoInicial: destino,
          sesion: Sesion(cliente: cliente),
        ),
      ),
    );
    await tester.pump();
  }

  /// Pulsa una pestaña de la barra inferior por su etiqueta.
  Future<void> irA(WidgetTester tester, String etiqueta) async {
    await tester.tap(find.text(etiqueta));
    await tester.pump();
    await tester.pump();
  }

  testWidgets("arranca en Teoría y la pinta", (tester) async {
    await montar(tester);

    expect(find.text("Teoría"), findsWidgets);
    expect(
      find.text("Biología"),
      findsOneWidget,
      reason: "el primer curso de teoría por orden alfabético",
    );
  });

  testWidgets("Teoría conserva su sitio al ir y volver", (tester) async {
    await montar(tester);
    expect(find.text("Biología"), findsOneWidget);

    // Desplazar la lista de cursos hasta perder de vista el primero.
    await tester.drag(find.text("Biología"), const Offset(0, -400));
    await tester.pump();
    expect(
      find.text("Biología"),
      findsNothing,
      reason: "si sigue visible, el arrastre no llegó y el test no prueba nada",
    );

    await irA(tester, "Práctica");
    await irA(tester, "Teoría");

    expect(
      find.text("Biología"),
      findsNothing,
      reason:
          "al volver, Teoría se rebobinó al principio: la pestaña se está "
          "destruyendo al cambiar en vez de conservarse",
    );
  });

  testWidgets("Práctica también conserva su sitio", (tester) async {
    await montar(tester, destino: 2);
    expect(find.text("Biología"), findsOneWidget);

    await tester.drag(find.text("Biología"), const Offset(0, -400));
    await tester.pump();
    expect(find.text("Biología"), findsNothing);

    await irA(tester, "Teoría");
    await irA(tester, "Práctica");

    expect(find.text("Biología"), findsNothing);
  });

  testWidgets("una pestaña sin visitar no se monta", (tester) async {
    // Perezoso a propósito: montar las cinco en el primer frame haría que
    // abrir la app cargara el banco y la teoría de golpe.
    await montar(tester);

    expect(
      find.text("392 preguntas resueltas y verificadas"),
      findsNothing,
      reason: "Práctica no se ha visitado todavía y ya estaba construida",
    );

    await irA(tester, "Práctica");
    expect(find.text("392 preguntas resueltas y verificadas"), findsOneWidget);
  });

  // La otra mitad de la decisión —que Repaso, Simulacro y Progreso NO se
  // conservan— no se puede probar aquí, y conviene decirlo en vez de dejar el
  // hueco callado: esas tres pantallas construyen su propio `Sesion()` dentro
  // del estado, y `Sesion()` toca `Supabase.instance.client` en el
  // constructor. Montarlas en un test lanza «You must initialize the supabase
  // instance» antes de pintar nada. `Armazon` sí acepta la sesión inyectada;
  // ellas no la propagan.
  //
  // Es la misma limitación que deja fuera a diez de las catorce pantallas en
  // `desborde_test.dart`. Se cierra el día que las pantallas reciban sus
  // repositorios en vez de fabricarlos.
}
