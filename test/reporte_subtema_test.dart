// Lo que quedaba de `practica.dart`: el reporte de error y la práctica por
// subtema.
//
// Son las dos mitades que no toca `practica_pantalla_test.dart`, que cubre la
// tanda. Las dos existen por el mismo motivo —cerrar un ciclo que se quedaba
// abierto— y las dos tienen reglas que ningún test de `datos/` puede ver,
// porque viven en cómo se presentan:
//
//   - **El reporte tiene tres fases y una `Key`.** Sin la `Key` por código de
//     pregunta, el formulario abierto en la pregunta 3 seguía abierto en la 4
//     con el detalle ya escrito apuntando a otra pregunta.
//   - **«Ya lo habías reportado» no es un error.** El índice único parcial de
//     la tabla impide dos reportes abiertos de la misma pregunta a propósito;
//     enseñarlo en rojo haría pensar al alumno que falló algo suyo.
//   - **El tope de 1 000 caracteres va en el campo, no solo en el envío.** Con
//     el `check` de la tabla como única barrera, el alumno escribe 1 200 y el
//     error aparece al enviar, con el texto ya escrito.
//   - **La práctica por subtema dice cuántas preguntas hay ANTES de empezar.**
//     128 de los 206 subtemas con preguntas tienen exactamente una: prometer
//     «practica esto» y abrir una tanda de una sería engañar.
import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:matr_u/data/models/practica.dart";
import "package:matr_u/data/models/preguntas.dart";
import "package:matr_u/data/models/sesion.dart";
import "package:matr_u/ui/core/theme/tema.dart";
import "package:matr_u/ui/features/practice/views/practica.dart";
import "package:supabase/supabase.dart";

const _idPropio = "11111111-1111-1111-1111-111111111111";

class _ClienteEspia extends http.BaseClient {
  final peticiones = <(String metodo, Uri url, String cuerpo)>[];

  /// `null` = la pregunta no existe en la base.
  Map<String, dynamic>? filaPregunta = {"id": 900};

  /// Código de error para el insert en `reportes_error`, si lo hay.
  /// `23505` es el del índice único parcial: ya hay uno abierto.
  String? errorReporte;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest peticion) async {
    final enviado = peticion is http.Request ? peticion.body : "";
    peticiones.add((peticion.method, peticion.url, enviado));
    final ruta = peticion.url.path;

    if (ruta == "/auth/v1/token") return _r(peticion, jsonEncode(_sesion), 200);
    if (ruta == "/rest/v1/preguntas") {
      return _r(peticion, jsonEncode(filaPregunta), 200);
    }
    if (ruta == "/rest/v1/intentos") {
      return _r(peticion, jsonEncode({"id": 42}), 200);
    }
    if (ruta == "/rest/v1/rpc/responder_pregunta") {
      // El reporte solo aparece con la corrección ya en pantalla: se reporta
      // una pregunta cuando algo no cuadra al VER la respuesta, no antes.
      return _r(
        peticion,
        jsonEncode([
          {"es_correcta": true, "clave": "C", "explicacion_md": "Porque sí."},
        ]),
        200,
      );
    }
    if (ruta == "/rest/v1/reportes_error" && errorReporte != null) {
      return _r(
        peticion,
        jsonEncode({
          "code": errorReporte,
          "message": "duplicado",
          "details": null,
          "hint": null,
        }),
        400,
      );
    }
    return _r(peticion, "[]", 200);
  }

  http.StreamedResponse _r(http.BaseRequest p, String cuerpo, int estado) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(cuerpo)),
        estado,
        headers: const {"content-type": "application/json; charset=utf-8"},
        request: p,
      );

  static const _sesion = {
    "access_token": "falso",
    "token_type": "bearer",
    "expires_in": 3600,
    "refresh_token": "falso",
    "user": {
      "id": _idPropio,
      "aud": "authenticated",
      "role": "authenticated",
      "email": "alumno@ejemplo.test",
      "app_metadata": <String, dynamic>{},
      "user_metadata": <String, dynamic>{},
      "created_at": "2026-01-01T00:00:00Z",
    },
  };

  Iterable<(String, Uri, String)> de(String ruta) =>
      peticiones.where((p) => p.$2.path == ruta);

  /// La fila que se mandó a `reportes_error`. `postgrest` manda un objeto
  /// suelto al insertar una fila y una lista al insertar varias.
  Map<String, dynamic> get reporteEnviado {
    final json = jsonDecode(de("/rest/v1/reportes_error").last.$3);
    return (json is List ? json.first : json) as Map<String, dynamic>;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ClienteEspia espia;
  late SupabaseClient cliente;

  /// Un subtema del banco real con más de una pregunta, y otro con una sola.
  late String subtemaConVarias;
  late String subtemaConUna;

  setUpAll(() async {
    final banco = await RepositorioPreguntas().cargar();
    final conteo = banco.conteoPorSubtema();
    subtemaConVarias = conteo.entries.firstWhere((e) => e.value > 2).key;
    subtemaConUna = conteo.entries.firstWhere((e) => e.value == 1).key;
  });

  setUp(() {
    espia = _ClienteEspia();
    cliente = SupabaseClient(
      "https://proyecto.supabase.co",
      "sb_publishable_de_mentira",
      httpClient: espia,
    );
  });

  tearDown(() async => cliente.dispose());

  Future<void> entrar() => cliente.auth.signInWithPassword(
    email: "alumno@ejemplo.test",
    password: "da-igual",
  );

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> montar(WidgetTester tester, Widget pantalla) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() => RepositorioPreguntas().cargar());
    await tester.pumpWidget(
      MaterialApp(theme: construirTema(), home: pantalla),
    );
    await asentar(tester);
  }

  // ==========================================================================
  // El reporte de error
  // ==========================================================================
  group("reportar un error", () {
    /// El reporte vive dentro de la tanda y solo aparece con un intento ya
    /// abierto —sin sesión no hay a quién atribuirlo y la tabla exige
    /// `perfil_id`—, así que hay que responder una pregunta primero.
    Future<void> abrirElFormulario(WidgetTester tester) async {
      await tester.tap(find.text("C").first);
      await asentar(tester);
      await tester.tap(find.text("Comprobar"));
      await asentar(tester);
      await tester.tap(find.text("Reportar un error en esta pregunta"));
      await asentar(tester);
    }

    Future<void> montarTanda(WidgetTester tester) => montar(
      tester,
      Builder(
        builder: (context) => SesionPractica(
          titulo: "Química",
          preguntas: [
            Pregunta(
              codigo: "QUI-2027-001",
              enunciado: "Enunciado",
              imagen: null,
              dificultad: Dificultad.medio,
              alternativas: [
                for (final l in letras)
                  Alternativa(
                    letra: l,
                    texto: "Opción ${l.etiqueta}",
                    imagen: null,
                  ),
              ],
              subtemaCodigo: "QUI-01-01",
              subtemaNombre: "Materia",
              temaNombre: "Química general",
              cursoNombre: "Química",
              cursoSlug: "quimica",
            ),
          ],
          repositorio: RepositorioPractica(cliente: cliente),
          sesion: Sesion(cliente: cliente),
        ),
      ),
    );

    testWidgets("el enlace no aparece hasta que hay un intento abierto", (
      tester,
    ) async {
      await entrar();
      await montarTanda(tester);

      expect(
        find.text("Reportar un error en esta pregunta"),
        findsNothing,
        reason:
            "sin intento no hay a quién atribuirlo, y `reportes_error` exige "
            "`perfil_id`",
      );
    });

    testWidgets("el motivo sale de la lista cerrada, no de un campo libre", (
      tester,
    ) async {
      await entrar();
      await montarTanda(tester);
      await abrirElFormulario(tester);

      // Cerrado, el desplegable solo monta la opción elegida: hay que abrirlo
      // para ver las cuatro.
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      for (final motivo in RepositorioPractica.motivosReporte) {
        expect(
          find.text(motivo),
          findsWidgets,
          reason:
              "la lista está repetida en interfaz, servidor y el `check` de "
              "la tabla: cada uno protege de algo distinto, y el de la base "
              "es el único que no se puede saltar",
        );
      }
      expect(
        find.byType(TextField),
        findsOneWidget,
        reason:
            "el único campo libre es el detalle; el motivo no puede serlo o "
            "la bandeja del docente se llena de categorías de una sola fila",
      );
    });

    testWidgets("el campo de detalle trae el tope de la tabla", (tester) async {
      await entrar();
      await montarTanda(tester);
      await abrirElFormulario(tester);

      final campo = tester.widget<TextField>(
        find.widgetWithText(TextField, "Detalles (opcional)"),
      );
      expect(
        campo.maxLength,
        1000,
        reason:
            "sin el tope aquí, el alumno escribe 1 200 caracteres y el error "
            "solo aparece al enviar, con el texto ya escrito",
      );
    });

    testWidgets("enviarlo manda motivo y detalle, y lo acusa", (tester) async {
      await entrar();
      await montarTanda(tester);
      await abrirElFormulario(tester);

      await tester.enterText(
        find.widgetWithText(TextField, "Detalles (opcional)"),
        "  La clave debería ser la B.  ",
      );
      await tester.pump();
      await tester.tap(find.text("Enviar reporte"));
      await asentar(tester);

      final fila = espia.reporteEnviado;
      expect(fila["motivo"], "Clave incorrecta");
      expect(
        fila["detalle"],
        "La clave debería ser la B.",
        reason: "se recorta antes de mandarlo",
      );
      expect(find.textContaining("Reporte enviado"), findsOneWidget);
    });

    testWidgets("un detalle vacío viaja como nulo, no como cadena vacía", (
      tester,
    ) async {
      await entrar();
      await montarTanda(tester);
      await abrirElFormulario(tester);

      await tester.tap(find.text("Enviar reporte"));
      await asentar(tester);

      expect(
        espia.reporteEnviado["detalle"],
        isNull,
        reason:
            "con una cadena vacía, la bandeja del docente no distingue «no "
            "escribió nada» de «escribió y se borró»",
      );
    });

    testWidgets("«ya lo habías reportado» no se enseña como error", (
      tester,
    ) async {
      espia.errorReporte = "23505";
      await entrar();
      await montarTanda(tester);
      await abrirElFormulario(tester);

      await tester.tap(find.text("Enviar reporte"));
      await asentar(tester);

      expect(
        find.textContaining("sigue en la cola"),
        findsOneWidget,
        reason:
            "el índice único parcial lo impide a propósito; en rojo, el "
            "alumno creería que falló algo suyo",
      );
      expect(find.textContaining("No se pudo enviar"), findsNothing);
    });

    testWidgets("un fallo de verdad sí se dice, y deja reintentar", (
      tester,
    ) async {
      espia.errorReporte = "PGRST000";
      await entrar();
      await montarTanda(tester);
      await abrirElFormulario(tester);

      await tester.tap(find.text("Enviar reporte"));
      await asentar(tester);

      expect(
        find.textContaining("No se pudo enviar el reporte"),
        findsOneWidget,
      );
      expect(
        find.text("Enviar reporte"),
        findsOneWidget,
        reason: "el formulario sigue abierto: el reintento es el botón mismo",
      );
    });

    testWidgets("«Cancelar» cierra el formulario sin mandar nada", (
      tester,
    ) async {
      await entrar();
      await montarTanda(tester);
      await abrirElFormulario(tester);

      await tester.tap(find.text("Cancelar"));
      await asentar(tester);

      expect(find.text("Enviar reporte"), findsNothing);
      expect(find.text("Reportar un error en esta pregunta"), findsOneWidget);
      expect(espia.de("/rest/v1/reportes_error"), isEmpty);
    });
  });

  // ==========================================================================
  // Practicar un subtema suelto
  // ==========================================================================
  group("práctica por subtema", () {
    testWidgets("dice cuántas preguntas hay antes de empezar", (tester) async {
      await montar(
        tester,
        PantallaPracticaSubtema(codigo: subtemaConVarias, nombre: "Un subtema"),
      );

      expect(find.textContaining("preguntas de este subtema"), findsOneWidget);
      expect(find.text("Empezar"), findsOneWidget);
    });

    testWidgets("con una sola, avisa de que son pocas y lo dice en singular", (
      tester,
    ) async {
      await montar(
        tester,
        PantallaPracticaSubtema(codigo: subtemaConUna, nombre: "Un subtema"),
      );

      expect(find.text("Hay 1 pregunta de este subtema."), findsOneWidget);
      expect(
        find.textContaining("Son pocas"),
        findsOneWidget,
        reason:
            "128 de los 206 subtemas con preguntas tienen exactamente una: "
            "prometer «practica esto» y abrir una tanda de una sería engañar",
      );
      expect(find.text("Ver la pregunta"), findsOneWidget);
    });

    testWidgets("un subtema sin preguntas lo explica con su código", (
      tester,
    ) async {
      await montar(
        tester,
        const PantallaPracticaSubtema(
          codigo: "ALG-99-99",
          nombre: "Un subtema sin banco",
        ),
      );

      expect(
        find.textContaining("Todavía no hay preguntas de este subtema"),
        findsOneWidget,
      );
      expect(
        find.textContaining("ALG-99-99"),
        findsOneWidget,
        reason:
            "750 de los 956 subtemas del sílabo no tienen ninguna todavía; "
            "con el código delante no se lee como un error de la app",
      );
    });

    testWidgets("empezar abre la tanda con esas preguntas", (tester) async {
      await montar(
        tester,
        PantallaPracticaSubtema(
          codigo: subtemaConVarias,
          nombre: "Un subtema",
          repositorio: RepositorioPractica(cliente: cliente),
          sesion: Sesion(cliente: cliente),
        ),
      );

      await tester.tap(find.text("Empezar"));
      await tester.pumpAndSettle();

      expect(find.byType(SesionPractica), findsOneWidget);
      expect(find.text("Volver"), findsNothing, reason: "eso es del resumen");
    });
  });
}
