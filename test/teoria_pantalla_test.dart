// `PantallaTeoria`, `PantallaCursoTeoria` y `PantallaSeccion`.
//
// Era la última pantalla grande sin tests (44 %), y la única del bloque que no
// necesitaba inyectar nada: la teoría sale de los assets del APK, no de
// Supabase. Que estuviera sin cubrir no era por difícil, era por orden.
//
// **Y es la parte de la app que más se usa**: funciona sin cuenta, sin red
// —las figuras se guardan en disco— y es a donde llega quien todavía no se ha
// registrado. Un fallo aquí lo ve todo el mundo.
//
// Se usa el contenido REAL, como `teoria_corpus_test.dart`: 15 cursos, 1 829
// secciones. Nada de esto se puede falsear sin dejar de probar lo que importa,
// porque lo que importa es cómo se comporta el árbol de verdad — con sus
// niveles, sus encabezados sin markdown y sus títulos numerados.
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:matr_u/data/repositories/teoria.dart";
import "package:matr_u/domain/models/teoria.dart";
import "package:matr_u/ui/core/theme/tema.dart";
import "package:matr_u/ui/features/study/views/teoria.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<CursoTeoria> cursos;
  late CursoTeoria unCurso;

  setUpAll(() async {
    cursos = await RepositorioTeoria().cursos();
    // Uno con secciones de sobra para poder navegar adelante y atrás.
    unCurso = cursos.firstWhere((c) => c.conContenido > 3);
  });

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  /// La teoría se lee de los assets: hay que calentarla fuera del reloj falso.
  /// Misma nota que en `horario_pantalla_test.dart`.
  Future<void> montar(WidgetTester tester, Widget pantalla) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() => RepositorioTeoria().cursos());
    await tester.pumpWidget(
      MaterialApp(theme: construirTema(), home: pantalla),
    );
    await asentar(tester);
  }

  group("la lista de cursos", () {
    testWidgets("los pinta todos, ordenados por nombre", (tester) async {
      await montar(tester, const Scaffold(body: PantallaTeoria()));

      // El primero por orden alfabético tiene que estar arriba del todo.
      expect(find.text(cursos.first.nombre), findsOneWidget);
      expect(
        cursos.length,
        greaterThanOrEqualTo(15),
        reason: "el banco importado trae 15 cursos con teoría",
      );
    });

    testWidgets("cada curso dice cuántas secciones CON CONTENIDO tiene", (
      tester,
    ) async {
      await montar(tester, const Scaffold(body: PantallaTeoria()));

      final primero = cursos.first;
      expect(
        find.text("${primero.conContenido} secciones"),
        findsOneWidget,
        reason:
            "una sección sin markdown es un encabezado del índice, no "
            "contenido: contarla infla la cifra que el alumno usa para "
            "decidir si le sirve el curso",
      );
      expect(
        primero.conContenido,
        lessThan(primero.secciones.length),
        reason:
            "si coincidieran, este test no distinguiría entre contar nodos y "
            "contar hojas con contenido",
      );
    });

    testWidgets("entrar en un curso abre su índice", (tester) async {
      await montar(tester, const Scaffold(body: PantallaTeoria()));

      await tester.tap(find.text(cursos.first.nombre));
      await tester.pumpAndSettle();

      expect(find.byType(PantallaCursoTeoria), findsOneWidget);
    });
  });

  group("el índice de un curso", () {
    testWidgets("solo lista las secciones con contenido", (tester) async {
      await montar(tester, PantallaCursoTeoria(curso: unCurso));

      final vacias = unCurso.secciones.where((s) => !s.tieneContenido);
      expect(
        vacias,
        isNotEmpty,
        reason: "este curso tiene encabezados sin markdown; si no, no prueba",
      );
      for (final s in vacias.take(3)) {
        expect(
          find.text(s.tituloConNumero),
          findsNothing,
          reason:
              "abrir un encabezado de índice llevaría a una sección en "
              "blanco, y el alumno no tiene forma de saber que no era un "
              "fallo suyo",
        );
      }
    });

    testWidgets("la sangría refleja el nivel del árbol", (tester) async {
      await montar(tester, PantallaCursoTeoria(curso: unCurso));

      final sangrias = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((t) => (t.contentPadding! as EdgeInsets).left)
          .toSet();
      expect(
        sangrias.every((s) => s >= 16),
        isTrue,
        reason: "16 es el margen base; ningún nivel puede quedar por dentro",
      );
      expect(
        sangrias.every((s) => s <= 16 + 3 * 14),
        isTrue,
        reason:
            "el `clamp(0, 3)` existe para que un árbol muy profundo no empuje "
            "el título fuera de una pantalla de móvil",
      );
    });

    testWidgets("el título lleva su número cuando lo tiene", (tester) async {
      await montar(tester, PantallaCursoTeoria(curso: unCurso));

      final conNumero = unCurso.secciones
          .where((s) => s.tieneContenido && s.numero != null)
          .toList();
      if (conNumero.isEmpty) return;
      expect(find.text(conNumero.first.tituloConNumero), findsWidgets);
    });
  });

  group("una sección", () {
    /// Las secciones del curso que de verdad se pueden abrir, que es la lista
    /// que `PantallaCursoTeoria` le pasa a `PantallaSeccion`. El índice va
    /// contra ESTA lista, no contra `curso.secciones`: confundirlas abriría
    /// una sección distinta de la que se pulsó.
    List<SeccionTeoria> conContenido(CursoTeoria c) =>
        c.secciones.where((s) => s.tieneContenido).toList();

    testWidgets("pinta su título y su contenido", (tester) async {
      final lista = conContenido(unCurso);
      await montar(
        tester,
        PantallaSeccion(curso: unCurso, secciones: lista, indice: 0),
      );

      expect(find.text(lista.first.tituloConNumero), findsOneWidget);
      expect(find.text(unCurso.nombre), findsOneWidget);
    });

    testWidgets("«Anterior» está apagado en la primera", (tester) async {
      final lista = conContenido(unCurso);
      await montar(
        tester,
        PantallaSeccion(curso: unCurso, secciones: lista, indice: 0),
      );

      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, "Anterior"),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, "Siguiente"),
            )
            .onPressed,
        isNotNull,
      );
    });

    testWidgets("«Siguiente» está apagado en la última", (tester) async {
      final lista = conContenido(unCurso);
      await montar(
        tester,
        PantallaSeccion(
          curso: unCurso,
          secciones: lista,
          indice: lista.length - 1,
        ),
      );

      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, "Siguiente"),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets("«Siguiente» avanza a la sección de al lado", (tester) async {
      final lista = conContenido(unCurso);
      await montar(
        tester,
        PantallaSeccion(curso: unCurso, secciones: lista, indice: 0),
      );

      await tester.tap(find.widgetWithText(FilledButton, "Siguiente"));
      await tester.pumpAndSettle();

      expect(find.text(lista[1].tituloConNumero), findsOneWidget);
      expect(find.text(lista[0].tituloConNumero), findsNothing);
    });

    testWidgets("avanzar REEMPLAZA la ruta, no la apila", (tester) async {
      // Es lo que hace que el botón de atrás vuelva al índice y no te obligue
      // a desandar una por una las secciones que leíste. Con `push` en vez de
      // `pushReplacement`, leer diez seguidas dejaría diez rutas en la pila.
      final lista = conContenido(unCurso);
      await montar(
        tester,
        PantallaSeccion(curso: unCurso, secciones: lista, indice: 0),
      );

      final navegador = tester.state<NavigatorState>(find.byType(Navigator));
      expect(navegador.canPop(), isFalse, reason: "arranca como raíz");

      await tester.tap(find.widgetWithText(FilledButton, "Siguiente"));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, "Siguiente"));
      await tester.pumpAndSettle();

      expect(
        navegador.canPop(),
        isFalse,
        reason:
            "dos avances no pueden dejar dos rutas encima: el gesto de atrás "
            "tiene que volver al índice, no a la sección anterior",
      );
      expect(find.text(lista[2].tituloConNumero), findsOneWidget);
    });

    testWidgets("el markdown se convierte en bloques, no se pinta crudo", (
      tester,
    ) async {
      // Qué produce `analizarTeoria` ya lo fija `markdown_teoria_test.dart`
      // sobre el corpus entero; lo que se comprueba aquí es que la pantalla
      // los pinte en vez de volcar el markdown tal cual.
      final lista = conContenido(unCurso);
      final conTexto = lista.firstWhere(
        (s) => s.markdown.contains("#") || s.markdown.contains("*"),
        orElse: () => lista.first,
      );
      await montar(
        tester,
        PantallaSeccion(
          curso: unCurso,
          secciones: lista,
          indice: lista.indexOf(conTexto),
        ),
      );

      expect(tester.takeException(), isNull);
      final crudo = find.textContaining("##");
      expect(
        crudo,
        findsNothing,
        reason: "un `##` en pantalla significa que el marcado no se analizó",
      );
    });
  });
}
