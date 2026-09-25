// El widget que ocho pantallas pintaban por su cuenta, ahora uno solo.
//
// Lo que se fija aquí no es "que se vea bonito": es lo que las ocho copias
// hacían distinto entre sí sin que nadie lo decidiera. Un `detalle` vacío no
// debe dejar un hueco de 8 px —dos de las ocho lo evitaban, seis no—, y el
// mensaje del catálogo que no carga debe seguir diciendo qué herramienta hay
// que correr, que es la única pista útil que da esa pantalla.
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:matr_u/ui/core/widgets/aviso.dart";

Widget _envolver(Widget hijo) => MaterialApp(home: Scaffold(body: hijo));

void main() {
  testWidgets("con detalle vacío no pinta el segundo Text", (tester) async {
    await tester.pumpWidget(
      _envolver(
        const Aviso(icono: Icons.inbox_outlined, titulo: "Nada por aquí"),
      ),
    );

    expect(find.text("Nada por aquí"), findsOneWidget);
    expect(find.byType(Text), findsOneWidget);
  });

  testWidgets("con detalle, pinta título y detalle", (tester) async {
    await tester.pumpWidget(
      _envolver(
        const Aviso(
          icono: Icons.inbox_outlined,
          titulo: "Nada por aquí",
          detalle: "No hay preguntas con este filtro.",
        ),
      ),
    );

    expect(find.text("Nada por aquí"), findsOneWidget);
    expect(find.text("No hay preguntas con este filtro."), findsOneWidget);
  });

  testWidgets("la acción es un botón que se puede pulsar", (tester) async {
    var pulsado = 0;
    await tester.pumpWidget(
      _envolver(
        Aviso(
          icono: Icons.cloud_off_outlined,
          titulo: "No se pudo cargar",
          accion: ("Reintentar", () => pulsado++),
        ),
      ),
    );

    await tester.tap(find.text("Reintentar"));
    expect(pulsado, 1);
  });

  testWidgets("sin acción no hay ningún botón", (tester) async {
    await tester.pumpWidget(
      _envolver(
        const Aviso(icono: Icons.lock_outline, titulo: "Necesita cuenta"),
      ),
    );

    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets("contenidoLocal dice qué herramienta hay que correr", (
    tester,
  ) async {
    await tester.pumpWidget(
      _envolver(
        Aviso.contenidoLocal(
          titulo: "No se pudo cargar el banco",
          error: Exception("assets/datos/preguntas/_indice.json"),
        ),
      ),
    );

    expect(find.text("No se pudo cargar el banco"), findsOneWidget);
    // El detalle lleva el error tal cual —el nombre del archivo que faltó es
    // la mitad del diagnóstico— y encima la herramienta que lo trae.
    expect(
      find.textContaining("assets/datos/preguntas/_indice.json"),
      findsOneWidget,
    );
    expect(find.textContaining("sincronizar-datos.mjs"), findsOneWidget);
  });

  testWidgets("con la letra al máximo no desborda", (tester) async {
    // Un `Column` centrado sin scroll revienta con `textScaler` alto: es el
    // caso de un alumno con la letra grande del sistema abriendo la pantalla
    // más larga (título + tres líneas de detalle + botón) en un teléfono
    // corto. `SingleChildScrollView` es lo que lo sostiene.
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: _envolver(
          Aviso(
            icono: Icons.cloud_off_outlined,
            titulo: "No se pudo cargar tu progreso",
            detalle:
                "La racha, el diagnóstico y los repasos se calculan sobre tu "
                "historial de respuestas, y ahora mismo el servidor no "
                "responde.",
            accion: ("Reintentar", () {}),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
