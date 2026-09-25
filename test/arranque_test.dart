// El arranque de la app, y la regresión concreta que motivó separarlo de
// `main()`: construir `Armazon` —que construye `Sesion()`, y `Sesion()` toca
// `Supabase.instance.client`— antes de que Supabase esté inicializado no
// debe lanzar nunca una excepción sin capturar, ni en el primer build.
//
// Sin `--dart-define-from-file=config/dev.json` (que es como corre esta
// suite), `Config.configurado` es `false`: es exactamente el caso "sin
// configuración en absoluto", y antes de este archivo crasheaba con la misma
// aserción de Supabase que se veía en el hot restart real — `Armazon` se
// construía sin condición, incluso sin credenciales.
//
// El otro caso real —el warm-up-frame de un hot restart reconstruyendo el
// árbol antes de que `await Supabase.initialize()` termine— no se puede
// reproducir en un widget test (no hay isolate que reiniciar), así que queda
// cubierto por revisión de código: `Arranque.build()` nunca toca
// `Supabase.instance`, solo `Config.configurado`, y quien la inicializa de
// verdad es `initState()`, que el framework garantiza posterior al primer
// build.
import "dart:async";
import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:matr_u/core/config/config.dart";
import "package:matr_u/data/repositories/sesion.dart";
import "package:matr_u/main.dart";
import "package:matr_u/ui/core/theme/tema.dart";
import "package:matr_u/ui/features/auth/views/entrar.dart";
import "package:supabase/supabase.dart";

/// Un cliente que no sale a ninguna parte.
///
/// `autoRefreshToken: false` para que no arranque su `Timer.periodic` de
/// refresco, y un `http.Client` de mentira porque el binding de
/// `flutter_test` intercepta todo `HttpClient` real y lo fuerza a 400 — ver la
/// nota de `pubspec.yaml` sobre `test/integracion/`. Estas pruebas no ejercitan
/// ninguna petición: lo único que hace falta es que `Sesion` tenga un cliente
/// que construir.
SupabaseClient _clienteMudo() => SupabaseClient(
  "https://x.supabase.co",
  "clave",
  httpClient: _SinRed(),
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);

class _SinRed extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest peticion) async =>
      http.StreamedResponse(
        Stream.value(utf8.encode("{}")),
        200,
        headers: const {"content-type": "application/json; charset=utf-8"},
        request: peticion,
      );
}

/// Una sesión cuyo flujo de eventos de auth lo maneja el test.
///
/// `cambios` es un getter, así que basta con taparlo: el cliente que recibe
/// `super` no llega a usarse para nada en estas pruebas, pero tiene que ser
/// uno inyectado — `Sesion()` sin argumentos resolvería
/// `Supabase.instance.client` en el constructor y lanzaría antes de empezar.
class _SesionDirigida extends Sesion {
  _SesionDirigida(SupabaseClient cliente) : super(cliente: cliente);

  final _eventos = StreamController<AuthState>.broadcast();

  @override
  Stream<AuthState> get cambios => _eventos.stream;

  void recuperacion() => emitir(AuthChangeEvent.passwordRecovery);

  void emitir(AuthChangeEvent evento) => _eventos.add(AuthState(evento, null));

  Future<void> cerrar() => _eventos.close();
}

void main() {
  testWidgets("sin configuración, arranca sin excepciones y muestra la ayuda", (
    tester,
  ) async {
    expect(
      Config.configurado,
      isFalse,
      reason: "este test asume que corre sin --dart-define-from-file",
    );

    await tester.pumpWidget(const AppMatrixU());
    await tester.pumpAndSettle();

    // Ninguna excepción llegó a la consola de errores del widget tree.
    expect(tester.takeException(), isNull);
    expect(find.textContaining(Config.ayuda), findsOneWidget);
  });

  testWidgets("el primer build no depende de que Supabase ya esté listo", (
    tester,
  ) async {
    // `pumpWidget` solo hace UN frame — el primer build, el mismo que un
    // warm-up-frame prematuro dispararía en un hot restart real. Si
    // `Arranque.build()` tocara `Supabase.instance` aquí, esto fallaría
    // igual que fallaba antes de separar el arranque de `main()`.
    await tester.pumpWidget(const AppMatrixU());
    expect(tester.takeException(), isNull);
  });

  // ==========================================================================
  // Cuando la inicialización LANZA
  // ==========================================================================
  //
  // El agujero que cerró esto: el `FutureBuilder` del arranque solo miraba
  // `connectionState != done`. Si `Supabase.initialize()` lanzaba, el estado
  // llegaba a `done` igual y se montaba `PantallaInicio` — cuyo estado
  // construye `Sesion()` como campo de instancia, y `Sesion()` toca
  // `Supabase.instance.client`, que sin inicializar lanza. El resultado era
  // una pantalla roja en el arranque: exactamente la excepción que toda la
  // coreografía de `Arranque` evita por el otro camino, el del hot restart.
  //
  // `inicializador` es la costura que hace esto alcanzable: la suite corre sin
  // `--dart-define-from-file`, así que `Config.configurado` es `false` y
  // `build` saldría antes por `_SinConfigurar`.

  Widget conArranque(Future<void> Function() inicializador) => MaterialApp(
    theme: construirTema(),
    home: Arranque(inicializador: inicializador),
  );

  testWidgets("si la inicialización lanza, lo dice y no monta la app", (
    tester,
  ) async {
    await tester.pumpWidget(
      conArranque(() async => throw Exception("sin conexión")),
    );
    await tester.pumpAndSettle();

    // Ninguna excepción se escapó al árbol de widgets: el fallo está tratado,
    // no propagado.
    expect(tester.takeException(), isNull);
    expect(find.text("La app no pudo arrancar"), findsOneWidget);
    expect(find.textContaining("sin conexión"), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, "Reintentar"), findsOneWidget);
  });

  testWidgets("mientras inicializa muestra el spinner, no el fallo", (
    tester,
  ) async {
    final compuerta = Completer<void>();
    await tester.pumpWidget(conArranque(() => compuerta.future));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text("La app no pudo arrancar"), findsNothing);

    compuerta.completeError(Exception("se cayó a mitad"));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text("La app no pudo arrancar"), findsOneWidget);
  });

  testWidgets("Reintentar rehace la petición, no repinta el error viejo", (
    tester,
  ) async {
    // Los dos intentos fallan, con mensajes distintos. Es a propósito: el
    // camino del éxito no se puede ejercitar aquí, porque `Arranque` monta
    // entonces `PantallaInicio`, cuyo estado construye `Sesion()` y toca
    // `Supabase.instance.client` — que sin un Supabase real inicializado
    // lanza. Eso no es un defecto del test: es exactamente la cadena que
    // describe el comentario de `build()`, y la razón de que la rama
    // `hasError` tenga que existir. Lo que sí se puede comprobar, y es lo
    // que importa del botón, es que vuelve a llamar al inicializador y que
    // la pantalla refleja el intento NUEVO y no el anterior.
    // Cada intento entrega su propia compuerta, y el test decide cuándo se
    // rompe. No es rigor de más: bajo el reloj falso de `flutter_test`, un
    // `Future` que se rompe solo lo hace mientras `pump` adelanta el tiempo,
    // ANTES de construir el frame — así que el fallo del segundo intento
    // llegaría cuando el `FutureBuilder` todavía no se ha suscrito al nuevo
    // `Future`, y Dart lo reportaría como error no capturado. Es una carrera
    // del entorno de test, no de la app: `Supabase.initialize()` va por red y
    // nunca falla dentro del mismo frame en que se llamó.
    final compuertas = <Completer<void>>[];
    await tester.pumpWidget(
      conArranque(() {
        final compuerta = Completer<void>();
        compuertas.add(compuerta);
        return compuerta.future;
      }),
    );
    await tester.pump();

    expect(compuertas, hasLength(1));
    compuertas.last.completeError(Exception("fallo número 1"));
    await tester.pumpAndSettle();

    expect(find.textContaining("fallo número 1"), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, "Reintentar"));
    await tester.pump();

    expect(
      compuertas,
      hasLength(2),
      reason: "«Reintentar» tiene que rehacer la petición, no repintar",
    );
    compuertas.last.completeError(Exception("fallo número 2"));
    await tester.pumpAndSettle();

    expect(find.textContaining("fallo número 2"), findsOneWidget);
    expect(
      find.textContaining("fallo número 1"),
      findsNothing,
      reason: "se quedó pintando el error del intento anterior",
    );
    expect(tester.takeException(), isNull);
  });

  /// Varias vueltas cortas, NO `pumpAndSettle`.
  ///
  /// El `SupabaseClient` de estas pruebas trae su cliente de realtime, que
  /// programa trabajo periódico: `pumpAndSettle` avanza el reloj falso hasta
  /// que no quede nada pendiente y con eso nunca termina. Unas cuantas vueltas
  /// bastan — misma razón y misma solución que en `horario_pantalla_test.dart`.
  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  // ==========================================================================
  // El deep link del correo de recuperación
  // ==========================================================================
  //
  // Se escucha en `Arranque` y no en `Armazon` ni en `PantallaEntrar` porque el
  // enlace puede llegar con la app CERRADA: Android la arranca de cero con el
  // `VIEW` del `intent-filter`, y en ese arranque lo único montado es
  // `Arranque`. Si la escucha viviera más abajo, el alumno volvería del correo
  // a la portada y el token de un solo uso se perdería sin recoger.
  group("recuperación de contraseña por deep link", () {
    late SupabaseClient cliente;
    late _SesionDirigida sesion;

    setUp(() {
      cliente = _clienteMudo();
      sesion = _SesionDirigida(cliente);
    });

    // **Fuera del cuerpo del test a propósito.** `SupabaseClient.dispose()`
    // espera a que su cliente de realtime se cierre, y dentro de un
    // `testWidgets` eso corre bajo el reloj falso: el futuro no resuelve nunca
    // y el archivo entero se queda colgado hasta el tiempo límite de la suite.
    // En `tearDown` corre fuera de esa zona y termina.
    tearDown(() async {
      await sesion.cerrar();
      await cliente.dispose();
    });

    Future<void> montar(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: construirTema(),
          home: Arranque(inicializador: () async {}, sesion: sesion),
        ),
      );
      await asentar(tester);
    }

    testWidgets("un evento de recuperación abre la pantalla de contraseña", (
      tester,
    ) async {
      await montar(tester);
      expect(find.byType(PantallaNuevaContrasena), findsNothing);

      sesion.recuperacion();
      await asentar(tester);

      expect(
        find.byType(PantallaNuevaContrasena),
        findsOneWidget,
        reason:
            "sin esto, quien abre el enlace del correo vuelve a la portada y "
            "el token de un solo uso se pierde sin haber cambiado nada",
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets("dos eventos seguidos no apilan dos pantallas", (tester) async {
      // Supabase reemite el último evento de auth a cada suscriptor nuevo, y
      // un «Reintentar» vuelve a pasar por la misma escucha.
      await montar(tester);

      sesion.recuperacion();
      await asentar(tester);
      sesion.recuperacion();
      await asentar(tester);

      expect(find.byType(PantallaNuevaContrasena), findsOneWidget);
    });

    testWidgets("otros eventos de auth no abren nada", (tester) async {
      await montar(tester);

      sesion.emitir(AuthChangeEvent.signedOut);
      await asentar(tester);

      expect(find.byType(PantallaNuevaContrasena), findsNothing);
    });
  });
}
