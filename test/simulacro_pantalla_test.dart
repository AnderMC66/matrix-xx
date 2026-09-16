// `PantallaSimulacro`: la lista de simulacros, el intento a medias y el
// historial.
//
// Estaba al **1,6 % de cobertura**, en el tramo con más reglas propias de la
// app móvil. Las tres que fija este archivo no existen en la web y no las
// cubre ningún test de `datos/`:
//
//   - **Mientras haya un intento abierto no se deja empezar otro.** En la web
//     se vuelve al examen a medias por el historial del navegador; aquí no hay
//     barra de direcciones, así que si se pudiera arrancar un segundo, el
//     primero se quedaría corriendo su cronómetro hasta agotarse solo.
//   - **El historial existe.** Antes, un simulacro terminado era inalcanzable
//     para siempre: el puntaje y el percentil seguían en Postgres y ninguna
//     pantalla los volvía a leer.
//   - **Las tres peticiones salen a la vez.** Estaban escritas como
//     `(await a, await b, await c)`, que parece paralelo y no lo es: Dart
//     evalúa los campos en orden.
import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:matr_u/datos/sesion.dart";
import "package:matr_u/datos/simulacro.dart";
import "package:matr_u/pantallas/simulacro.dart";
import "package:matr_u/tema.dart";
import "package:supabase/supabase.dart";

const _idPropio = "11111111-1111-1111-1111-111111111111";

class _ClienteEspia extends http.BaseClient {
  final peticiones = <(String metodo, Uri url, String cuerpo)>[];

  List<Map<String, dynamic>> simulacros = [
    {
      "id": 1,
      "nombre": "Simulacro general 2027-I",
      "descripcion": "Las cuatro áreas",
      "duracion_minutos": 180,
    },
  ];

  /// El intento abierto, si lo hay, y los ya cerrados.
  Map<String, dynamic>? enCurso;
  List<Map<String, dynamic>> historial = [];

  bool fallaLaCarga = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest peticion) async {
    final enviado = peticion is http.Request ? peticion.body : "";
    peticiones.add((peticion.method, peticion.url, enviado));
    final ruta = peticion.url.path;
    final consulta = peticion.url.queryParameters;

    if (ruta == "/auth/v1/token") return _r(peticion, jsonEncode(_sesion), 200);

    if (ruta == "/rest/v1/simulacros") {
      if (fallaLaCarga) return _fallo(peticion);
      // `.maybeSingle()` pide una fila; la lista pide todas.
      return _r(peticion, jsonEncode(simulacros), 200);
    }

    if (ruta == "/rest/v1/intentos") {
      if (fallaLaCarga) return _fallo(peticion);
      // El intento en curso se busca con `finalizado_en is null`; el
      // historial, con `not.is.null`. Es la única forma de distinguirlos.
      final filtro = consulta["finalizado_en"] ?? "";
      if (filtro.contains("not")) {
        return _r(peticion, jsonEncode(historial), 200);
      }
      return _r(peticion, jsonEncode(enCurso == null ? [] : [enCurso]), 200);
    }

    if (ruta == "/rest/v1/rpc/iniciar_simulacro") {
      return _r(peticion, "77", 200);
    }
    return _r(peticion, "[]", 200);
  }

  http.StreamedResponse _fallo(http.BaseRequest p) => _r(
    p,
    jsonEncode({
      "code": "PGRST000",
      "message": "sin conexión",
      "details": null,
      "hint": null,
    }),
    500,
  );

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
}

Map<String, dynamic> _intento({
  required int id,
  String? finalizadoEn,
  double? puntaje,
}) => {
  "id": id,
  "simulacro_id": 1,
  "iniciado_en": "2026-09-14T14:00:00+00:00",
  "finalizado_en": finalizadoEn,
  "puntaje": puntaje,
  "total_preguntas": puntaje == null ? null : 100,
  "correctas": puntaje?.round(),
};

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
    email: "alumno@ejemplo.test",
    password: "da-igual",
  );

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: construirTema(),
        home: Scaffold(
          body: PantallaSimulacro(
            repositorio: RepositorioSimulacro(cliente: cliente),
            sesion: Sesion(cliente: cliente),
          ),
        ),
      ),
    );
    await asentar(tester);
  }

  testWidgets("sin sesión pide la cuenta y no consulta nada", (tester) async {
    await montar(tester);

    expect(
      find.textContaining("El simulacro necesita tu cuenta"),
      findsOneWidget,
    );
    expect(espia.de("/rest/v1/simulacros"), isEmpty);
    expect(espia.de("/rest/v1/intentos"), isEmpty);
  });

  testWidgets("lista los simulacros publicados", (tester) async {
    await entrar();
    await montar(tester);

    expect(find.text("Simulacro general 2027-I"), findsOneWidget);
    expect(find.text("Empezar"), findsOneWidget);
  });

  testWidgets("sin simulacros publicados lo dice, no deja la pantalla vacía", (
    tester,
  ) async {
    espia.simulacros = [];
    await entrar();
    await montar(tester);

    expect(
      find.textContaining("Todavía no hay simulacros publicados"),
      findsOneWidget,
    );
  });

  testWidgets("las tres peticiones salen a la vez, no encadenadas", (
    tester,
  ) async {
    await entrar();
    espia.peticiones.clear();
    await montar(tester);

    // Escritas en fila, la consulta de `intentos` no podía existir hasta que
    // volviera la de `simulacros`. Lanzadas juntas, las tres están pedidas
    // antes de que ninguna responda — y aquí se ven las tres registradas.
    expect(espia.de("/rest/v1/simulacros"), hasLength(1));
    expect(
      espia.de("/rest/v1/intentos"),
      hasLength(2),
      reason: "el intento en curso y el historial son dos consultas",
    );
  });

  group("un intento a medias", () {
    testWidgets("se ofrece retomar y se bloquea empezar otro", (tester) async {
      espia.enCurso = _intento(id: 55);
      await entrar();
      await montar(tester);

      expect(find.text("Retomar"), findsOneWidget);
      expect(
        find.text("Termina el que tienes a medias"),
        findsOneWidget,
        reason:
            "si se pudiera arrancar un segundo, el primero seguiría corriendo "
            "su cronómetro hasta agotarse solo, y en una app no hay barra de "
            "direcciones para volver a él",
      );
      expect(find.text("Empezar"), findsNothing);
    });

    testWidgets("el botón bloqueado no llama a iniciar_simulacro", (
      tester,
    ) async {
      espia.enCurso = _intento(id: 55);
      await entrar();
      await montar(tester);

      await tester.tap(find.text("Termina el que tienes a medias"));
      await asentar(tester);

      expect(espia.de("/rest/v1/rpc/iniciar_simulacro"), isEmpty);
    });

    testWidgets("sin intento abierto, «Empezar» sí arranca uno", (
      tester,
    ) async {
      await entrar();
      await montar(tester);

      await tester.tap(find.text("Empezar"));
      await asentar(tester);

      expect(espia.de("/rest/v1/rpc/iniciar_simulacro"), hasLength(1));
    });
  });

  group("historial", () {
    testWidgets("los intentos cerrados se pueden volver a mirar", (
      tester,
    ) async {
      espia.historial = [
        _intento(
          id: 10,
          finalizadoEn: "2026-09-10T16:00:00+00:00",
          puntaje: 62,
        ),
        _intento(
          id: 11,
          finalizadoEn: "2026-08-30T16:00:00+00:00",
          puntaje: 48,
        ),
      ];
      await entrar();
      await montar(tester);

      expect(find.text("LO QUE YA RENDISTE"), findsOneWidget);
      expect(
        find.text("62 %"),
        findsOneWidget,
        reason:
            "sin el historial, un simulacro terminado era inalcanzable para "
            "siempre: el puntaje seguía en Postgres y nadie lo volvía a leer",
      );
      expect(find.text("48 %"), findsOneWidget);
    });

    testWidgets("sin nada rendido, no se pinta el encabezado", (tester) async {
      await entrar();
      await montar(tester);

      expect(find.text("LO QUE YA RENDISTE"), findsNothing);
    });
  });

  testWidgets("si la carga falla, hay aviso y «Reintentar»", (tester) async {
    espia.fallaLaCarga = true;
    await entrar();
    await montar(tester);

    expect(
      find.textContaining("No se pudieron cargar los simulacros"),
      findsOneWidget,
    );

    espia.fallaLaCarga = false;
    await tester.tap(find.widgetWithText(OutlinedButton, "Reintentar"));
    await asentar(tester);

    expect(find.text("Simulacro general 2027-I"), findsOneWidget);
  });
}
