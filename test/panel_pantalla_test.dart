// `PantallaPanel`: la portada del panel de docente/admin.
//
// Estaba al **0,7 % de cobertura**, y es la pantalla donde más caro sale un
// fallo silencioso: decide qué ve alguien con permisos para publicar
// preguntas. Lo que se fija aquí:
//
//   - **Que un alumno no vea el panel.** El control de acceso real vive en la
//     base —las seis funciones comprueban `es_staff()` por dentro—, pero esta
//     capa es la que evita enseñar un panel vacío a quien no le toca, y una
//     regresión aquí no rompería ningún test de `datos/`.
//   - Que «Personas» sea **solo de admin**: un docente no administra roles.
//   - Que el rol se lea de `perfiles` en cada carga y no de un claim del
//     token, porque `cambiar_rol` puede degradar a alguien con la sesión viva.
import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:matr_u/data/repositories/panel.dart";
import "package:matr_u/ui/core/theme/tema.dart";
import "package:matr_u/ui/features/dashboard/view_models/panel.dart";
import "package:matr_u/ui/features/dashboard/views/panel.dart";
import "package:supabase/supabase.dart";

const _idPropio = "11111111-1111-1111-1111-111111111111";

class _ClienteEspia extends http.BaseClient {
  final peticiones = <(String metodo, Uri url, String cuerpo)>[];

  /// Lo que devuelve `perfiles` para el rol propio.
  String rol = "docente";

  /// Si se pone, `resumen_panel` falla.
  bool fallaElResumen = false;

  Map<String, dynamic> resumen = const {
    "sin_auditar": 7,
    "publicadas": 392,
    "en_auditoria": 2,
    "borradores": 0,
    "retiradas": 1,
    "reportes_abiertos": 3,
    "personas": 58,
  };

  @override
  Future<http.StreamedResponse> send(http.BaseRequest peticion) async {
    final enviado = peticion is http.Request ? peticion.body : "";
    peticiones.add((peticion.method, peticion.url, enviado));
    final ruta = peticion.url.path;

    if (ruta == "/auth/v1/token") return _r(peticion, jsonEncode(_sesion), 200);
    if (ruta == "/rest/v1/perfiles") {
      return _r(peticion, jsonEncode({"rol": rol}), 200);
    }
    if (ruta == "/rest/v1/rpc/resumen_panel") {
      if (fallaElResumen) {
        return _r(
          peticion,
          jsonEncode({
            "code": "PGRST000",
            "message": "sin conexión",
            "details": null,
            "hint": null,
          }),
          500,
        );
      }
      return _r(peticion, jsonEncode([resumen]), 200);
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
      "email": "docente@ejemplo.test",
      "app_metadata": <String, dynamic>{},
      "user_metadata": <String, dynamic>{},
      "created_at": "2026-01-01T00:00:00Z",
    },
  };

  Iterable<(String, Uri, String)> de(String ruta) =>
      peticiones.where((p) => p.$2.path == ruta);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ClienteEspia espia;
  late SupabaseClient cliente;

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
    email: "docente@ejemplo.test",
    password: "da-igual",
  );

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> montar(WidgetTester tester) async {
    // Una ventana alta a propósito: el panel son seis tarjetas dentro de un
    // `ListView`, que construye sus hijos según lo que cabe en la vista. Con
    // los 600 px de alto por defecto, «Personas» —la última— no llega a
    // existir en el árbol, y `findsNothing` daría verde tanto si la pantalla
    // la oculta bien como si simplemente no se pintó.
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: construirTema(),
        home: PantallaPanel(
          modelo: ModeloPanel(repositorio: RepositorioPanel(cliente: cliente)),
        ),
      ),
    );
    await asentar(tester);
  }

  testWidgets("un docente ve el resumen con sus cifras", (tester) async {
    await entrar();
    await montar(tester);

    expect(find.text("Revisión y soporte"), findsOneWidget);
    expect(find.text("Sin auditar"), findsOneWidget);
    expect(find.text("7"), findsOneWidget);
    expect(find.text("Reportes abiertos"), findsOneWidget);
    expect(find.text("3"), findsOneWidget);
  });

  testWidgets("un alumno no ve el panel ni pide el resumen", (tester) async {
    espia.rol = "alumno";
    await entrar();
    await montar(tester);

    expect(find.textContaining("No tienes acceso al panel"), findsOneWidget);
    expect(find.text("Revisión y soporte"), findsNothing);
    expect(
      espia.de("/rest/v1/rpc/resumen_panel"),
      isEmpty,
      reason:
          "sin rol de staff no se llega ni a preguntar: la base lo negaría, "
          "pero pedirlo igual es enseñar que existe",
    );
  });

  testWidgets("sin sesión tampoco hay panel", (tester) async {
    await montar(tester);

    expect(find.textContaining("No tienes acceso al panel"), findsOneWidget);
    expect(espia.de("/rest/v1/perfiles"), isEmpty);
  });

  testWidgets("un docente no ve «Personas»", (tester) async {
    espia.rol = "docente";
    await entrar();
    await montar(tester);

    // Las otras cinco sí: lo que falta es solo la de administrar roles.
    expect(find.text("Sin auditar"), findsOneWidget);
    expect(find.text("Retiradas"), findsOneWidget);
    expect(
      find.text("Personas"),
      findsNothing,
      reason: "administrar roles no es trabajo de un docente",
    );
  });

  testWidgets("un admin sí ve Personas", (tester) async {
    espia.rol = "admin";
    await entrar();
    await montar(tester);

    expect(find.text("Personas"), findsOneWidget);
    expect(find.text("58"), findsOneWidget);
  });

  testWidgets("el rol se relee en cada carga, no se cachea del token", (
    tester,
  ) async {
    await entrar();
    await montar(tester);

    expect(
      espia.de("/rest/v1/perfiles"),
      hasLength(1),
      reason:
          "`cambiar_rol` puede degradar a alguien con la sesión viva: un "
          "claim del token seguiría diciendo lo de antes hasta caducar",
    );
  });

  testWidgets("si el resumen falla, hay aviso y «Reintentar»", (tester) async {
    espia.fallaElResumen = true;
    await entrar();
    await montar(tester);

    expect(find.textContaining("No se pudo abrir el panel"), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, "Reintentar"), findsOneWidget);

    espia.fallaElResumen = false;
    await tester.tap(find.widgetWithText(OutlinedButton, "Reintentar"));
    await asentar(tester);

    expect(find.text("Revisión y soporte"), findsOneWidget);
  });
}
