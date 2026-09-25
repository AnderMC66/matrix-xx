// `PantallaEntrar` y `PantallaNuevaContrasena`: el tramo de acceso entero.
//
// Estaba al **0 % de cobertura**, y es el único tramo de la app por el que
// pasa todo el mundo. Lo que se prueba aquí, en orden de importancia:
//
//   - **Recuperar la contraseña**, que hasta el 2026-09-16 no existía. Quien
//     la olvidaba se quedaba fuera de su progreso, su racha y sus simulacros
//     sin ninguna salida dentro de la app.
//   - Que el acuse de recuperación sea **el mismo exista la cuenta o no**: si
//     distinguiera los dos casos, el formulario sería un comprobador de quién
//     está registrado aquí, y cualquiera podría usarlo sin tener cuenta.
//   - Que los dos correos que manda la app —confirmar y recuperar— apunten al
//     deep link del manifiesto y no a la web.
//   - Que el ojo de «ver la contraseña» exista, porque el campo va enmascarado
//     y un dedo que resbala se lee en pantalla como «contraseña incorrecta».
import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:matr_u/data/repositories/sesion.dart";
import "package:matr_u/ui/core/theme/tema.dart";
import "package:matr_u/ui/features/auth/views/entrar.dart";
import "package:supabase/supabase.dart";

const _idPropio = "11111111-1111-1111-1111-111111111111";

class _ClienteEspia extends http.BaseClient {
  final peticiones = <(String metodo, Uri url, String cuerpo)>[];

  /// Si se pone, `/auth/v1/*` responde con este error de auth.
  ({int estado, String mensaje, String codigo})? falla;

  /// `false` cuando el proyecto no exige confirmar el correo: el registro
  /// devuelve sesión y se entra directo.
  bool exigeConfirmar = true;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest peticion) async {
    final enviado = peticion is http.Request ? peticion.body : "";
    peticiones.add((peticion.method, peticion.url, enviado));
    final ruta = peticion.url.path;

    if (falla case final f? when ruta.startsWith("/auth/v1/")) {
      return _r(
        peticion,
        jsonEncode({
          "error": f.codigo,
          "error_code": f.codigo,
          "msg": f.mensaje,
          "message": f.mensaje,
        }),
        f.estado,
      );
    }

    if (ruta == "/auth/v1/token") return _r(peticion, jsonEncode(_sesion), 200);
    if (ruta == "/auth/v1/signup") {
      // Sin sesión = hay que confirmar el correo.
      return _r(
        peticion,
        jsonEncode(exigeConfirmar ? _usuarioSolo : _sesion),
        200,
      );
    }
    if (ruta == "/auth/v1/recover") return _r(peticion, "{}", 200);
    if (ruta == "/auth/v1/user") {
      return _r(peticion, jsonEncode(_usuario), 200);
    }
    if (ruta == "/rest/v1/areas_postulacion") {
      return _r(
        peticion,
        jsonEncode([
          {"id": 1, "nombre": "Ingenierías"},
          {"id": 2, "nombre": "Biomédicas"},
        ]),
        200,
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

  static const _usuario = {
    "id": _idPropio,
    "aud": "authenticated",
    "role": "authenticated",
    "email": "alumno@ejemplo.test",
    "app_metadata": <String, dynamic>{},
    "user_metadata": <String, dynamic>{},
    "created_at": "2026-01-01T00:00:00Z",
  };

  static final _usuarioSolo = {..._usuario, "session": null};

  static const _sesion = {
    "access_token": "falso",
    "token_type": "bearer",
    "expires_in": 3600,
    "refresh_token": "falso",
    "user": _usuario,
  };

  Iterable<(String, Uri, String)> de(String ruta) =>
      peticiones.where((p) => p.$2.path == ruta);
}

/// El almacén que PKCE necesita, en memoria.
///
/// Sin esto, `signUp` y `resetPasswordForEmail` **no llegan a salir a la red**:
/// el flujo por defecto de `SupabaseClient` es PKCE, que guarda el
/// `code_verifier` antes de mandar el correo y aborta con «You need to provide
/// asyncStorage to perform pkce flow» si no tiene dónde. Los dos métodos que
/// esta suite ejercita son justo los dos que pasan por ahí.
///
/// En la app lo pone `supabase_flutter` con `shared_preferences`, que necesita
/// un canal de plataforma y por eso no existe aquí (mismo motivo por el que
/// `test/integracion/` construye el cliente a mano). Un `Map` cumple el
/// contrato entero.
class _AlmacenMemoria extends GotrueAsyncStorage {
  final _datos = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => _datos[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    _datos[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _datos.remove(key);
  }
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
      authOptions: AuthClientOptions(pkceAsyncStorage: _AlmacenMemoria()),
    );
  });

  tearDown(() async => cliente.dispose());

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  var entro = false;

  Future<void> montarEntrar(WidgetTester tester) async {
    entro = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: construirTema(),
        home: Scaffold(
          body: PantallaEntrar(
            sesion: Sesion(cliente: cliente),
            alEntrar: () => entro = true,
          ),
        ),
      ),
    );
    await asentar(tester);
  }

  Future<void> escribir(WidgetTester tester, String campo, String texto) async {
    await tester.enterText(find.widgetWithText(TextField, campo), texto);
    await tester.pump();
  }

  group("entrar", () {
    testWidgets("una sesión correcta avisa a quien la pidió", (tester) async {
      await montarEntrar(tester);

      await escribir(tester, "Correo", "alumno@ejemplo.test");
      await escribir(tester, "Contraseña", "contrasena-larga");
      await tester.tap(find.widgetWithText(FilledButton, "Entrar"));
      await asentar(tester);

      expect(entro, isTrue);
      expect(espia.de("/auth/v1/token"), hasLength(1));
    });

    testWidgets("el error del servidor se lee en español", (tester) async {
      espia.falla = (
        estado: 400,
        mensaje: "Invalid login credentials",
        codigo: "invalid_credentials",
      );
      await montarEntrar(tester);

      await escribir(tester, "Correo", "alumno@ejemplo.test");
      await escribir(tester, "Contraseña", "la-que-no-es");
      await tester.tap(find.widgetWithText(FilledButton, "Entrar"));
      await asentar(tester);

      expect(find.text("Correo o contraseña incorrectos."), findsOneWidget);
      expect(entro, isFalse);
    });

    testWidgets("se puede ver la contraseña escrita", (tester) async {
      await montarEntrar(tester);

      final campo = find.widgetWithText(TextField, "Contraseña");
      expect(
        tester.widget<TextField>(campo).obscureText,
        isTrue,
        reason: "arranca enmascarada",
      );

      await tester.tap(find.byTooltip("Ver la contraseña"));
      await tester.pump();

      expect(
        tester.widget<TextField>(campo).obscureText,
        isFalse,
        reason:
            "sin esto, un dedo que resbala se lee como «contraseña "
            "incorrecta» y manda a dudar del correo",
      );
      expect(find.byTooltip("Ocultar la contraseña"), findsOneWidget);
    });

    testWidgets("el correo se ofrece al gestor de contraseñas", (tester) async {
      await montarEntrar(tester);

      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, "Correo"))
            .autofillHints,
        contains(AutofillHints.username),
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, "Contraseña"))
            .autofillHints,
        contains(AutofillHints.password),
      );
    });
  });

  group("registrarse", () {
    testWidgets("el correo de confirmación vuelve a la app, no a la web", (
      tester,
    ) async {
      await montarEntrar(tester);
      await tester.tap(find.text("No tengo cuenta, quiero registrarme"));
      await asentar(tester);

      await escribir(tester, "Nombre", "Ana");
      await escribir(tester, "Correo", "ana@ejemplo.test");
      await escribir(tester, "Contraseña", "contrasena-larga");
      await tester.tap(find.widgetWithText(FilledButton, "Crear cuenta"));
      await asentar(tester);

      final alta = espia.de("/auth/v1/signup").single;
      expect(
        alta.$2.queryParameters["redirect_to"],
        enlaceRetorno,
        reason:
            "sin esto el enlace abre la web y el alumno vuelve a la app a "
            "mano; el `intent-filter` del manifiesto existe para esto",
      );
      expect(find.textContaining("Cuenta creada"), findsOneWidget);
      expect(entro, isFalse, reason: "todavía no hay sesión que usar");
    });

    testWidgets("una contraseña corta se para antes de gastar la petición", (
      tester,
    ) async {
      await montarEntrar(tester);
      await tester.tap(find.text("No tengo cuenta, quiero registrarme"));
      await asentar(tester);

      await escribir(tester, "Nombre", "Ana");
      await escribir(tester, "Correo", "ana@ejemplo.test");
      await escribir(tester, "Contraseña", "corta");
      await tester.tap(find.widgetWithText(FilledButton, "Crear cuenta"));
      await asentar(tester);

      expect(find.textContaining("al menos 8 caracteres"), findsOneWidget);
      expect(espia.de("/auth/v1/signup"), isEmpty);
    });

    testWidgets("no se ofrece recuperar la contraseña al registrarse", (
      tester,
    ) async {
      await montarEntrar(tester);
      expect(find.text("Olvidé mi contraseña"), findsOneWidget);

      await tester.tap(find.text("No tengo cuenta, quiero registrarme"));
      await asentar(tester);

      expect(
        find.text("Olvidé mi contraseña"),
        findsNothing,
        reason: "quien se registra no tiene todavía contraseña que olvidar",
      );
    });
  });

  group("recuperar la contraseña", () {
    testWidgets("manda el correo apuntando al deep link", (tester) async {
      await montarEntrar(tester);

      await escribir(tester, "Correo", "alumno@ejemplo.test");
      await tester.tap(find.text("Olvidé mi contraseña"));
      await asentar(tester);

      final envio = espia.de("/auth/v1/recover").single;
      expect(
        envio.$2.queryParameters["redirect_to"],
        enlaceRetorno,
        reason:
            "el token de recuperación es de un solo uso y solo sirve dentro "
            "de la app que lo pidió: si el enlace abre la web, no hay forma "
            "de terminar",
      );
      expect(
        find.textContaining("Si hay una cuenta con ese correo"),
        findsOneWidget,
      );
    });

    testWidgets("sin correo escrito no sale ninguna petición", (tester) async {
      await montarEntrar(tester);

      await tester.tap(find.text("Olvidé mi contraseña"));
      await asentar(tester);

      expect(espia.de("/auth/v1/recover"), isEmpty);
      expect(find.textContaining("Escribe tu correo"), findsOneWidget);
    });

    testWidgets("el acuse no revela si la cuenta existe", (tester) async {
      // El servidor de auth responde 200 exista o no la cuenta, a propósito.
      // Lo que se fija aquí es que la pantalla no añada por su cuenta una
      // distinción que el servidor evita: el texto es condicional («si hay
      // una cuenta…»), no una confirmación.
      await montarEntrar(tester);

      await escribir(tester, "Correo", "nadie@ejemplo.test");
      await tester.tap(find.text("Olvidé mi contraseña"));
      await asentar(tester);

      expect(
        find.textContaining("Si hay una cuenta con ese correo"),
        findsOneWidget,
      );
      expect(find.textContaining("no existe"), findsNothing);
      expect(find.textContaining("no está registrado"), findsNothing);
    });
  });

  group("poner la contraseña nueva", () {
    var cambio = false;

    Future<void> montar(WidgetTester tester) async {
      cambio = false;
      // La pantalla exige sesión: la de recuperación la abre el deep link.
      await cliente.auth.signInWithPassword(
        email: "alumno@ejemplo.test",
        password: "da-igual",
      );
      espia.peticiones.clear();
      await tester.pumpWidget(
        MaterialApp(
          theme: construirTema(),
          home: PantallaNuevaContrasena(
            sesion: Sesion(cliente: cliente),
            alCambiar: () => cambio = true,
          ),
        ),
      );
      await asentar(tester);
    }

    testWidgets("dos contraseñas iguales la guardan", (tester) async {
      await montar(tester);

      await escribir(tester, "Contraseña nueva", "contrasena-nueva");
      await escribir(tester, "Repítela", "contrasena-nueva");
      await tester.tap(
        find.widgetWithText(FilledButton, "Guardar la contraseña"),
      );
      await asentar(tester);

      expect(espia.de("/auth/v1/user"), hasLength(1));
      expect(cambio, isTrue);
    });

    testWidgets("si no coinciden, no sale ninguna petición", (tester) async {
      await montar(tester);

      await escribir(tester, "Contraseña nueva", "contrasena-nueva");
      await escribir(tester, "Repítela", "contrasena-nuevb");
      await tester.tap(
        find.widgetWithText(FilledButton, "Guardar la contraseña"),
      );
      await asentar(tester);

      expect(find.text("Las dos contraseñas no coinciden."), findsOneWidget);
      expect(
        espia.de("/auth/v1/user"),
        isEmpty,
        reason:
            "el servidor no puede saber que el alumno quiso escribir otra "
            "cosa, y la sesión de recuperación se gasta igual",
      );
      expect(cambio, isFalse);
    });

    testWidgets("una contraseña corta se para aquí", (tester) async {
      await montar(tester);

      await escribir(tester, "Contraseña nueva", "corta");
      await escribir(tester, "Repítela", "corta");
      await tester.tap(
        find.widgetWithText(FilledButton, "Guardar la contraseña"),
      );
      await asentar(tester);

      expect(find.textContaining("al menos 8 caracteres"), findsOneWidget);
      expect(espia.de("/auth/v1/user"), isEmpty);
    });

    testWidgets("un enlace vencido se lee en español", (tester) async {
      await montar(tester);
      espia.falla = (
        estado: 401,
        mensaje: "Token has expired or is invalid",
        codigo: "otp_expired",
      );

      await escribir(tester, "Contraseña nueva", "contrasena-nueva");
      await escribir(tester, "Repítela", "contrasena-nueva");
      await tester.tap(
        find.widgetWithText(FilledButton, "Guardar la contraseña"),
      );
      await asentar(tester);

      expect(find.textContaining("Ese enlace ya venció"), findsOneWidget);
      expect(cambio, isFalse);
    });
  });
}
