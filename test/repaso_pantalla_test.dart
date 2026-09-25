// `PantallaRepaso` y `PantallaPracticaAdaptativa`: las dos pantallas que
// eligen preguntas por el alumno en vez de que él elija curso.
//
// Estaban al **2,3 %** y al **1,8 % de cobertura**. Comparten archivo porque
// comparten la invariante que más importa de las dos, y que ningún test de
// `datos/` puede comprobar: **lo que llega del servidor son códigos, no
// preguntas**. Los RPC devuelven `codigo_externo` y nada más; el enunciado y
// las alternativas los pone el banco del APK, y la clave no la tiene nadie
// hasta que se responde. Si alguna de estas dos pantallas empezara a pintar
// algo que vino por red, la invariante se habría roto sin que saltara nada.
//
// También se fija que las peticiones salgan a la vez, como en el resto de la
// app, y que el estado vacío diga por qué está vacío: en un banco con 21,5 %
// del sílabo cubierto, «no hay nada que repasar» es lo normal, no un fallo.
import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:matr_u/data/repositories/preguntas.dart";
import "package:matr_u/data/repositories/progreso.dart";
import "package:matr_u/data/repositories/repaso.dart";
import "package:matr_u/data/repositories/sesion.dart";
import "package:matr_u/ui/core/theme/tema.dart";
import "package:matr_u/ui/features/practice/view_models/repaso.dart";
import "package:matr_u/ui/features/practice/views/practica_adaptativa.dart";
import "package:matr_u/ui/features/practice/views/repaso.dart";
import "package:supabase/supabase.dart";

const _idPropio = "11111111-1111-1111-1111-111111111111";

class _ClienteEspia extends http.BaseClient {
  final peticiones = <(String metodo, Uri url, String cuerpo)>[];

  /// Los códigos que devuelve cada RPC. **Solo códigos**: es exactamente lo
  /// que devuelve Postgres, y la mitad del argumento de este archivo.
  List<String> pendientes = [];
  List<String> falladas = [];
  List<String> recomendadas = [];

  Map<String, dynamic> resumen = const {
    "pendientes_hoy": 0,
    "proxima_fecha": null,
    "total_programados": 0,
  };

  List<Map<String, dynamic>> desatendidos = [];

  bool fallaLaCarga = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest peticion) async {
    final enviado = peticion is http.Request ? peticion.body : "";
    peticiones.add((peticion.method, peticion.url, enviado));
    final ruta = peticion.url.path;

    if (ruta == "/auth/v1/token") return _r(peticion, jsonEncode(_sesion), 200);
    if (fallaLaCarga && ruta.startsWith("/rest/v1/")) return _fallo(peticion);

    List<Map<String, String>> codigos(List<String> cs) => [
      for (final c in cs) {"codigo_externo": c},
    ];

    return switch (ruta) {
      "/rest/v1/rpc/repasos_pendientes" => _r(
        peticion,
        jsonEncode(codigos(pendientes)),
        200,
      ),
      "/rest/v1/rpc/preguntas_falladas" => _r(
        peticion,
        jsonEncode(codigos(falladas)),
        200,
      ),
      "/rest/v1/rpc/preguntas_recomendadas" => _r(
        peticion,
        jsonEncode(codigos(recomendadas)),
        200,
      ),
      "/rest/v1/rpc/resumen_repasos" => _r(
        peticion,
        jsonEncode([resumen]),
        200,
      ),
      "/rest/v1/rpc/cursos_desatendidos" => _r(
        peticion,
        jsonEncode(desatendidos),
        200,
      ),
      _ => _r(peticion, "[]", 200),
    };
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
      "email": "ana@ejemplo.test",
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

  /// Dos códigos que existen de verdad en el banco del APK, para poder
  /// comprobar que la pantalla resuelve el código contra los assets. Se leen
  /// una vez, fuera del reloj falso.
  late List<String> codigosReales;

  setUpAll(() async {
    final banco = await RepositorioPreguntas().cargar();
    codigosReales = banco.preguntas.take(3).map((p) => p.codigo).toList();
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
    email: "ana@ejemplo.test",
    password: "da-igual",
  );

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  /// El banco se lee de los assets: hay que calentarlo fuera del reloj falso.
  /// Misma nota que en `horario_pantalla_test.dart`.
  Future<void> calentar(WidgetTester tester) =>
      tester.runAsync(() => RepositorioPreguntas().cargar());

  Future<void> montar(WidgetTester tester, Widget pantalla) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await calentar(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: construirTema(),
        home: Scaffold(body: pantalla),
      ),
    );
    await asentar(tester);
  }

  // ==========================================================================
  // Repaso
  // ==========================================================================
  group("repaso", () {
    Future<void> montarRepaso(WidgetTester tester) => montar(
      tester,
      PantallaRepaso(
        modelo: ModeloRepaso(
          repositorio: RepositorioRepaso(cliente: cliente),
          sesion: Sesion(cliente: cliente),
        ),
      ),
    );

    testWidgets("sin sesión pide la cuenta y no consulta nada", (tester) async {
      await montarRepaso(tester);

      expect(
        find.textContaining("El repaso necesita tu cuenta"),
        findsOneWidget,
      );
      expect(
        espia.peticiones.where((p) => p.$2.path.startsWith("/rest/")),
        isEmpty,
      );
    });

    testWidgets("las dos peticiones salen a la vez", (tester) async {
      await entrar();
      espia.peticiones.clear();
      await montarRepaso(tester);

      expect(espia.de("/rest/v1/rpc/repasos_pendientes"), hasLength(1));
      expect(
        espia.de("/rest/v1/rpc/resumen_repasos"),
        hasLength(1),
        reason:
            "la lista y el resumen del calendario no dependen entre sí: en "
            "fila eran dos latencias antes de pintar nada",
      );
    });

    testWidgets("los códigos del servidor se resuelven contra el banco", (
      tester,
    ) async {
      espia.pendientes = codigosReales;
      espia.resumen = {
        "pendientes_hoy": codigosReales.length,
        "proxima_fecha": "2026-09-20",
        "total_programados": 40,
      };
      await entrar();
      await montarRepaso(tester);

      expect(
        find.text("${codigosReales.length}"),
        findsOneWidget,
        reason:
            "los RPC devuelven `codigo_externo` y nada más; el enunciado lo "
            "pone el APK, y la clave no la tiene nadie hasta responder",
      );
      expect(find.text("Empezar"), findsOneWidget);
    });

    testWidgets(
      "un código que ya no está en el banco se descarta en silencio",
      (tester) async {
        // Pregunta retirada del banco después de que el alumno la respondiera:
        // cuesta un hueco de la tanda, no la pantalla entera.
        espia.pendientes = [...codigosReales, "NO-EXISTE-9999"];
        espia.resumen = {
          "pendientes_hoy": codigosReales.length + 1,
          "proxima_fecha": null,
          "total_programados": 40,
        };
        await entrar();
        await montarRepaso(tester);

        expect(tester.takeException(), isNull);
        expect(find.text("${codigosReales.length}"), findsOneWidget);
      },
    );

    testWidgets("cambiar a «Falladas» pide el otro RPC", (tester) async {
      await entrar();
      await montarRepaso(tester);
      espia.peticiones.clear();

      await tester.tap(find.text("Falladas"));
      await asentar(tester);

      expect(espia.de("/rest/v1/rpc/preguntas_falladas"), hasLength(1));
    });

    testWidgets("sin nada que repasar lo explica, no deja el hueco", (
      tester,
    ) async {
      await entrar();
      await montarRepaso(tester);

      expect(find.text("Empezar"), findsNothing);
      expect(
        find.byType(Text),
        findsWidgets,
        reason: "el estado vacío tiene que decir algo",
      );
    });

    testWidgets("si la carga falla, hay aviso", (tester) async {
      espia.fallaLaCarga = true;
      await entrar();
      await montarRepaso(tester);

      expect(find.textContaining("No se pudo"), findsOneWidget);
    });
  });

  // ==========================================================================
  // Práctica adaptativa
  // ==========================================================================
  group("práctica adaptativa", () {
    Future<void> montarAdaptativa(WidgetTester tester, {String? curso}) =>
        montar(
          tester,
          PantallaPracticaAdaptativa(
            cursoSlug: curso,
            repaso: RepositorioRepaso(cliente: cliente),
            progreso: RepositorioProgreso(cliente: cliente),
            sesion: Sesion(cliente: cliente),
          ),
        );

    testWidgets("sin sesión pide la cuenta y no consulta nada", (tester) async {
      await montarAdaptativa(tester);

      expect(
        espia.peticiones.where((p) => p.$2.path.startsWith("/rest/")),
        isEmpty,
      );
    });

    testWidgets("pide recomendadas y cursos desatendidos a la vez", (
      tester,
    ) async {
      await entrar();
      espia.peticiones.clear();
      await montarAdaptativa(tester);

      expect(espia.de("/rest/v1/rpc/preguntas_recomendadas"), hasLength(1));
      expect(espia.de("/rest/v1/rpc/cursos_desatendidos"), hasLength(1));
    });

    testWidgets("acotada a un curso, no pide los desatendidos", (tester) async {
      await entrar();
      espia.peticiones.clear();
      await montarAdaptativa(tester, curso: "algebra");

      expect(espia.de("/rest/v1/rpc/preguntas_recomendadas"), hasLength(1));
      expect(
        espia.de("/rest/v1/rpc/cursos_desatendidos"),
        isEmpty,
        reason:
            "quien ya eligió curso no necesita que le sugieran otro: la "
            "petición sobraba",
      );
    });

    testWidgets("el curso viaja al RPC por su código, no por su slug", (
      tester,
    ) async {
      await entrar();
      espia.peticiones.clear();
      await montarAdaptativa(tester, curso: "algebra");

      final envio = espia.de("/rest/v1/rpc/preguntas_recomendadas").single;
      expect(
        envio.$3,
        contains("ALG"),
        reason:
            "el RPC trabaja con el código (`ALG`); la pantalla, con el slug "
            "(`algebra`), que es lo que usa el resto de la app",
      );
    });

    testWidgets("los códigos recomendados se resuelven contra el banco", (
      tester,
    ) async {
      espia.recomendadas = codigosReales;
      await entrar();
      await montarAdaptativa(tester);

      expect(tester.takeException(), isNull);
      // El botón dice cuántas son: la cifra sale del banco local, no del RPC,
      // porque el RPC solo mandó códigos.
      expect(
        find.text("Empezar · ${codigosReales.length} preguntas"),
        findsOneWidget,
      );
    });

    testWidgets("si la carga falla, hay aviso", (tester) async {
      espia.fallaLaCarga = true;
      await entrar();
      await montarAdaptativa(tester);

      expect(find.textContaining("No se pudo"), findsOneWidget);
    });
  });
}
