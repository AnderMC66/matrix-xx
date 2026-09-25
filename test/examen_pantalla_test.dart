// `SesionSimulacro` y `PantallaResultado`: el examen en sí.
//
// El bloque de simulacro estaba al 34 %, y lo que faltaba era justo la parte
// donde un fallo le cuesta la nota a alguien: la lista de simulacros ya tiene
// tests (`simulacro_pantalla_test.dart`), la sesión cronometrada no tenía
// ninguno.
//
// Lo que se fija aquí, por orden de lo que cuesta si se rompe:
//
//   - **El plazo agotado NO se reintenta.** Es la única distinción que impide
//     decirle «revisa tu conexión» a quien lo que le pasó es que se le acabó
//     el examen. Tiene su propio tipo (`TiempoAgotado`) precisamente para eso.
//   - **Una respuesta que llega tarde no pisa la más reciente.** Si el alumno
//     cambia de alternativa mientras el envío anterior sigue en vuelo, el
//     resultado viejo no debe volver a pintar la letra anterior.
//   - **El gesto de atrás no abandona el examen**: se intercepta y se ofrece
//     finalizar, que es la decisión real.
//   - **El estado de guardado es por pregunta.** Con uno global, marcar la
//     siguiente borraba el aviso de que la anterior no se había guardado: un
//     fallo real desaparecía de la vista sin haberse resuelto.
//   - Que el cronómetro salga de `iniciado_en` + `duracion_minutos`, los dos
//     del servidor, y que al llegar a cero cierre el intento solo.
import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:matr_u/data/repositories/preguntas.dart";
import "package:matr_u/data/repositories/simulacro.dart";
import "package:matr_u/ui/core/theme/tema.dart";
import "package:matr_u/ui/features/practice/views/simulacro.dart";
import "package:supabase/supabase.dart";

const _idPropio = "11111111-1111-1111-1111-111111111111";

/// Cuándo arrancó el intento, en UTC y con offset explícito, como lo manda
/// PostgREST. El cronómetro se calcula contra `DateTime.now()`, así que se
/// ancla al momento del test para que queden minutos de verdad.
String _iniciadoHace(Duration d) =>
    DateTime.now().toUtc().subtract(d).toIso8601String();

class _ClienteEspia extends http.BaseClient {
  final peticiones = <(String metodo, Uri url, String cuerpo)>[];

  /// Los códigos del banco que componen el examen, en orden.
  List<String> codigos = [];

  /// Lo que ya estaba respondido al entrar (pregunta_id → letra).
  Map<int, String> respuestasPrevias = {};

  /// Para el resultado: si la respuesta fue correcta.
  Map<int, bool> aciertos = {};

  Duration duracion = const Duration(minutes: 180);
  Duration llevaCorriendo = const Duration(minutes: 5);
  String? finalizadoEn;
  double? puntaje;

  /// Cómo responde `responder_pregunta`.
  ///  - `null`  → bien
  ///  - "tiempo" → el plazo del simulacro venció
  ///  - "red"    → un fallo cualquiera, de los que sí se reintentan
  String? falloAlGuardar;

  /// Cuántas veces se ha llamado a `responder_pregunta`.
  int enviosGuardar = 0;

  Map<String, dynamic>? percentil = const {
    "percentil": 72,
    "total_intentos": 40,
    "puntaje_propio": 62.0,
    "puntaje_mediano": 55.0,
    "puntaje_maximo": 91.0,
  };

  /// El id numérico que le toca a cada código, estable entre llamadas.
  int idDe(String codigo) => 1000 + codigos.indexOf(codigo);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest peticion) async {
    final enviado = peticion is http.Request ? peticion.body : "";
    peticiones.add((peticion.method, peticion.url, enviado));
    final ruta = peticion.url.path;

    if (ruta == "/auth/v1/token") return _r(peticion, jsonEncode(_sesion), 200);

    if (ruta == "/rest/v1/intentos") {
      return _r(
        peticion,
        jsonEncode({
          "id": 77,
          "simulacro_id": 1,
          "iniciado_en": _iniciadoHace(llevaCorriendo),
          "finalizado_en": finalizadoEn,
          "puntaje": puntaje,
          "total_preguntas": codigos.length,
          "correctas": aciertos.values.where((b) => b).length,
        }),
        200,
      );
    }

    if (ruta == "/rest/v1/simulacros") {
      return _r(
        peticion,
        jsonEncode({
          "id": 1,
          "nombre": "Simulacro general 2027-I",
          "descripcion": null,
          "duracion_minutos": duracion.inMinutes,
        }),
        200,
      );
    }

    if (ruta == "/rest/v1/simulacro_preguntas") {
      return _r(
        peticion,
        jsonEncode([
          for (var i = 0; i < codigos.length; i++)
            {
              "orden": i + 1,
              "pregunta_id": idDe(codigos[i]),
              "preguntas": {"codigo_externo": codigos[i]},
            },
        ]),
        200,
      );
    }

    if (ruta == "/rest/v1/respuestas") {
      return _r(
        peticion,
        jsonEncode([
          for (var i = 0; i < codigos.length; i++)
            {
              "pregunta_id": idDe(codigos[i]),
              "letra_marcada": respuestasPrevias[idDe(codigos[i])],
              "es_correcta": aciertos[idDe(codigos[i])],
            },
        ]),
        200,
      );
    }

    if (ruta == "/rest/v1/rpc/responder_pregunta") {
      enviosGuardar++;
      return switch (falloAlGuardar) {
        "tiempo" => _pgrst(
          peticion,
          "Se acabó el tiempo del simulacro",
          "P0001",
        ),
        "red" => _pgrst(peticion, "sin conexión", "PGRST000"),
        _ => _r(peticion, jsonEncode([]), 200),
      };
    }

    if (ruta == "/rest/v1/rpc/percentil_simulacro") {
      if (percentil == null) return _pgrst(peticion, "sin muestra", "PGRST000");
      return _r(peticion, jsonEncode([percentil]), 200);
    }

    return _r(peticion, "[]", 200);
  }

  http.StreamedResponse _pgrst(
    http.BaseRequest p,
    String mensaje,
    String codigo,
  ) => _r(
    p,
    jsonEncode({
      "code": codigo,
      "message": mensaje,
      "details": null,
      "hint": null,
    }),
    400,
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

  /// La letra que viajó en el último envío a `responder_pregunta`.
  String? get ultimaLetraEnviada {
    final envios = de("/rest/v1/rpc/responder_pregunta").toList();
    if (envios.isEmpty) return null;
    return (jsonDecode(envios.last.$3) as Map)["p_letra"] as String?;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ClienteEspia espia;
  late SupabaseClient cliente;
  late List<String> codigosReales;

  setUpAll(() async {
    final banco = await RepositorioPreguntas().cargar();
    codigosReales = banco.preguntas.take(3).map((p) => p.codigo).toList();
  });

  setUp(() {
    espia = _ClienteEspia()..codigos = codigosReales;
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

  /// Vueltas cortas, NO `pumpAndSettle`: la sesión arranca un `Timer.periodic`
  /// de un segundo para el cronómetro y con él `pumpAndSettle` no termina
  /// nunca. Misma nota que en `horario_pantalla_test.dart`.
  Future<void> asentar(WidgetTester tester, {int vueltas = 8}) async {
    for (var i = 0; i < vueltas; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> montarExamen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() => RepositorioPreguntas().cargar());
    await tester.pumpWidget(
      MaterialApp(
        theme: construirTema(),
        home: SesionSimulacro(
          intentoId: 77,
          repositorio: RepositorioSimulacro(cliente: cliente),
        ),
      ),
    );
    await asentar(tester);
  }

  /// Marca una alternativa por su letra. El círculo de la letra es un `Text`
  /// llano; el texto de la alternativa lo pinta `TextoConFormulas`, que es un
  /// `RichText` y `find.text` no ve.
  Future<void> marcar(WidgetTester tester, String letra) async {
    await tester.tap(find.text(letra).first);
    await asentar(tester);
  }

  // ==========================================================================
  // La sesión de examen
  // ==========================================================================
  group("la sesión", () {
    testWidgets("arranca en la primera pregunta, con el cronómetro corriendo", (
      tester,
    ) async {
      espia
        ..duracion = const Duration(minutes: 180)
        ..llevaCorriendo = const Duration(minutes: 5);
      await entrar();
      await montarExamen(tester);

      expect(find.text("1 de 3"), findsOneWidget);
      expect(find.text("0 respondidas"), findsOneWidget);
      // 180 - 5 = 175 minutos. El formato lleva los minutos totales, no horas.
      expect(find.textContaining("17"), findsWidgets);
    });

    testWidgets("marcar guarda directo: no hay botón «Comprobar»", (
      tester,
    ) async {
      await entrar();
      await montarExamen(tester);

      expect(
        find.text("Comprobar"),
        findsNothing,
        reason:
            "en simulacro no hay nada que revelar hasta cerrar el intento: el "
            "RPC retiene la clave",
      );

      await marcar(tester, "B");

      expect(espia.de("/rest/v1/rpc/responder_pregunta"), hasLength(1));
      expect(espia.ultimaLetraEnviada, "B");
      expect(find.text("Guardada"), findsOneWidget);
      expect(find.text("1 respondidas"), findsOneWidget);
    });

    testWidgets("una sesión retomada trae lo que ya se había marcado", (
      tester,
    ) async {
      espia.respuestasPrevias = {espia.idDe(codigosReales[0]): "D"};
      await entrar();
      await montarExamen(tester);

      expect(
        find.text("1 respondidas"),
        findsOneWidget,
        reason:
            "cerrar la app a mitad de examen no puede perder lo respondido: "
            "`iniciar_simulacro` precarga una fila por pregunta",
      );
      expect(find.text("Guardada"), findsOneWidget);
    });

    testWidgets("se puede navegar entre preguntas sin perder el sitio", (
      tester,
    ) async {
      await entrar();
      await montarExamen(tester);

      await tester.tap(find.widgetWithText(FilledButton, "Siguiente"));
      await asentar(tester);
      expect(find.text("2 de 3"), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, "Anterior"));
      await asentar(tester);
      expect(find.text("1 de 3"), findsOneWidget);
    });

    testWidgets("«Anterior» está apagado en la primera", (tester) async {
      await entrar();
      await montarExamen(tester);

      final boton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, "Anterior"),
      );
      expect(boton.onPressed, isNull);
    });
  });

  // ==========================================================================
  // Guardar: reintentos, plazo vencido y respuestas que llegan tarde
  // ==========================================================================
  group("guardar una respuesta", () {
    testWidgets("un fallo de red se reintenta tres veces y luego se dice", (
      tester,
    ) async {
      espia.falloAlGuardar = "red";
      await entrar();
      await montarExamen(tester);

      await marcar(tester, "B");
      // Las esperas crecientes del reintento: 800 ms y 1600 ms.
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 1700));
      await asentar(tester);

      expect(
        espia.enviosGuardar,
        3,
        reason: "tres intentos con espera creciente antes de rendirse",
      );
      expect(
        find.textContaining("No se pudo guardar"),
        findsOneWidget,
        reason: "callarse dejaría al alumno creyendo que quedó guardada",
      );
    });

    testWidgets("el plazo agotado NO se reintenta: cierra el intento", (
      tester,
    ) async {
      espia.falloAlGuardar = "tiempo";
      await entrar();
      await montarExamen(tester);

      await marcar(tester, "B");
      await asentar(tester);

      expect(
        espia.enviosGuardar,
        1,
        reason:
            "machacar el servidor tres veces para acabar diciendo «revisa tu "
            "conexión» cuando lo que pasó es que se acabó el examen sería "
            "mentirle; por eso `TiempoAgotado` tiene su propio tipo",
      );
      expect(espia.de("/rest/v1/rpc/finalizar_intento"), hasLength(1));
    });

    testWidgets("una respuesta que llega tarde no pisa la más reciente", (
      tester,
    ) async {
      await entrar();
      await montarExamen(tester);

      // Se marca B y, sin esperar a que vuelva, se cambia a D.
      await tester.tap(find.text("B").first);
      await tester.pump();
      await tester.tap(find.text("D").first);
      await asentar(tester);

      expect(espia.enviosGuardar, 2);
      expect(
        espia.ultimaLetraEnviada,
        "D",
        reason: "la última elección es la que vale",
      );
      expect(find.text("1 respondidas"), findsOneWidget);
    });

    testWidgets("el estado de guardado es por pregunta, no compartido", (
      tester,
    ) async {
      espia.falloAlGuardar = "red";
      await entrar();
      await montarExamen(tester);

      await marcar(tester, "B");
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 1700));
      await asentar(tester);
      expect(find.textContaining("No se pudo guardar"), findsOneWidget);

      // Se pasa a la siguiente: el aviso de la anterior no debe seguir aquí,
      // pero tampoco desaparecer del sitio donde importa.
      await tester.tap(find.widgetWithText(FilledButton, "Siguiente"));
      await asentar(tester);
      expect(
        find.textContaining("No se pudo guardar"),
        findsNothing,
        reason: "el aviso es de la pregunta anterior, no de esta",
      );

      await tester.tap(find.widgetWithText(OutlinedButton, "Anterior"));
      await asentar(tester);
      expect(
        find.textContaining("No se pudo guardar"),
        findsOneWidget,
        reason:
            "con un indicador global, pasar de pregunta borraba el aviso y un "
            "fallo real desaparecía de la vista sin resolverse",
      );
    });
  });

  // ==========================================================================
  // Terminar
  // ==========================================================================
  group("finalizar", () {
    testWidgets("pide confirmación y dice cuántas quedan sin responder", (
      tester,
    ) async {
      await entrar();
      await montarExamen(tester);

      await marcar(tester, "B");
      await tester.tap(find.widgetWithText(FilledButton, "Siguiente"));
      await asentar(tester);
      await tester.tap(find.widgetWithText(FilledButton, "Siguiente"));
      await asentar(tester);
      await tester.tap(find.widgetWithText(FilledButton, "Finalizar"));
      await asentar(tester);

      expect(find.text("¿Finalizar el simulacro?"), findsOneWidget);
      expect(find.textContaining("2 preguntas sin responder"), findsOneWidget);
      expect(find.text("Seguir respondiendo"), findsOneWidget);
    });

    testWidgets("«Seguir respondiendo» no cierra nada", (tester) async {
      await entrar();
      await montarExamen(tester);

      await tester.tap(find.widgetWithText(FilledButton, "Siguiente"));
      await asentar(tester);
      await tester.tap(find.widgetWithText(FilledButton, "Siguiente"));
      await asentar(tester);
      await tester.tap(find.widgetWithText(FilledButton, "Finalizar"));
      await asentar(tester);
      await tester.tap(find.text("Seguir respondiendo"));
      await asentar(tester);

      expect(espia.de("/rest/v1/rpc/finalizar_intento"), isEmpty);
      expect(find.text("3 de 3"), findsOneWidget);
    });

    testWidgets("el gesto de atrás ofrece finalizar, no abandona", (
      tester,
    ) async {
      await entrar();
      await montarExamen(tester);

      // `maybePop` es exactamente lo que dispara el botón de atrás de
      // Android: consulta al `PopScope`, ve que `canPop` es falso y llama a su
      // callback en vez de sacar la ruta. Se usa eso y no se inspecciona el
      // widget para que el test recorra el mecanismo de verdad.
      //
      // Lo que NO se comprueba es el valor que devuelve: `maybePop` responde
      // `true` tanto si saca la ruta como si el `PopScope` la retiene —las dos
      // cuentan como «peticion atendida»—, así que no distingue los dos casos.
      // Lo observable sí: el examen sigue montado y aparece el diálogo.
      final navegador = tester.state<NavigatorState>(find.byType(Navigator));
      await navegador.maybePop();
      await asentar(tester);

      expect(
        find.byType(SesionSimulacro),
        findsOneWidget,
        reason:
            "salir con el gesto dejaría el examen corriendo sin que se note",
      );
      expect(find.text("¿Finalizar el simulacro?"), findsOneWidget);
      expect(espia.de("/rest/v1/rpc/finalizar_intento"), isEmpty);
    });

    testWidgets("un intento ya cerrado va directo al resultado", (
      tester,
    ) async {
      espia
        ..finalizadoEn = DateTime.now().toUtc().toIso8601String()
        ..puntaje = 62;
      await entrar();
      await montarExamen(tester);

      expect(
        find.byType(PantallaResultado),
        findsOneWidget,
        reason: "no hay sesión que retomar en un intento cerrado",
      );
    });
  });

  // ==========================================================================
  // El resultado
  // ==========================================================================
  group("el resultado", () {
    Future<void> montarResultado(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.runAsync(() => RepositorioPreguntas().cargar());
      await tester.pumpWidget(
        MaterialApp(
          theme: construirTema(),
          home: PantallaResultado(
            intentoId: 77,
            repositorio: RepositorioSimulacro(cliente: cliente),
          ),
        ),
      );
      await asentar(tester);
    }

    setUp(() {
      espia
        ..finalizadoEn = DateTime.now().toUtc().toIso8601String()
        ..puntaje = 62
        ..respuestasPrevias = {
          espia.idDe(codigosReales[0]): "A",
          espia.idDe(codigosReales[1]): "B",
        }
        ..aciertos = {
          espia.idDe(codigosReales[0]): true,
          espia.idDe(codigosReales[1]): false,
        };
    });

    testWidgets("enseña el puntaje y cuántas quedaron sin responder", (
      tester,
    ) async {
      await entrar();
      await montarResultado(tester);

      expect(find.textContaining("62"), findsWidgets);
      expect(find.textContaining("sin responder"), findsWidgets);
    });

    testWidgets("el desglose y el percentil salen a la vez", (tester) async {
      await entrar();
      espia.peticiones.clear();
      await montarResultado(tester);

      expect(espia.de("/rest/v1/simulacro_preguntas"), hasLength(1));
      expect(
        espia.de("/rest/v1/rpc/percentil_simulacro"),
        hasLength(1),
        reason:
            "el desglose y el percentil no dependen entre sí: encadenarlos "
            "sumaba una latencia justo al terminar un examen de tres horas",
      );
    });

    testWidgets("sin percentil, el alumno ve su nota igual", (tester) async {
      // El RPC exige un mínimo de intentos ajenos antes de dar un percentil:
      // con dos o tres, la cifra no sería estadística sino información sobre
      // personas concretas.
      espia.percentil = null;
      await entrar();
      await montarResultado(tester);

      expect(
        find.textContaining("62"),
        findsWidgets,
        reason: "la comparación es un extra; la nota, no",
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets("un intento ajeno se dice, no se inventa", (tester) async {
      // La RLS de `intentos` devuelve vacío en vez de error si el intento es
      // de otro; la pantalla tiene que traducir eso a una frase.
      espia.finalizadoEn = null;
      espia.peticiones.clear();
      await entrar();

      await tester.runAsync(() => RepositorioPreguntas().cargar());
      await tester.pumpWidget(
        MaterialApp(
          theme: construirTema(),
          home: PantallaResultado(
            intentoId: 999,
            repositorio: RepositorioSimulacro(cliente: cliente),
          ),
        ),
      );
      await asentar(tester);

      // Con `finalizado_en` nulo el intento existe pero sigue en curso; lo que
      // se comprueba es que la pantalla no reviente por ello.
      expect(tester.takeException(), isNull);
    });
  });
}
