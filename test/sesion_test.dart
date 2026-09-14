// Lo que `Sesion` hace contra el servidor, sin tocar el servidor.
//
// Mismo montaje que `simulacro_consulta_test.dart`: un `http.Client` falso
// dentro de un `SupabaseClient` de verdad, para leer la petición que la app
// construye. `Sesion` acepta el cliente inyectado desde siempre.
//
// El foco es el borrado de cuenta, que es lo único irreversible de la app y
// además un requisito de Google Play: toda app que deje crear una cuenta tiene
// que dejar borrarla desde dentro.
import "dart:convert";

import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:matr_u/datos/sesion.dart";
import "package:supabase/supabase.dart";

const _idPropio = "11111111-1111-1111-1111-111111111111";

class _ClienteEspia extends http.BaseClient {
  final peticiones = <(String metodo, Uri url)>[];

  /// Qué contesta `POST /rest/v1/rpc/eliminar_mi_cuenta`.
  int estadoRpc = 200;
  String cuerpoRpc = "null";

  @override
  Future<http.StreamedResponse> send(http.BaseRequest peticion) async {
    peticiones.add((peticion.method, peticion.url));
    final ruta = peticion.url.path;

    if (ruta == "/rest/v1/rpc/eliminar_mi_cuenta") {
      return http.StreamedResponse(
        Stream.value(utf8.encode(cuerpoRpc)),
        estadoRpc,
        headers: const {"content-type": "application/json; charset=utf-8"},
        request: peticion,
      );
    }

    final cuerpo = switch (ruta) {
      "/auth/v1/token" => jsonEncode({
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
      }),
      _ => "{}",
    };
    return http.StreamedResponse(
      Stream.value(utf8.encode(cuerpo)),
      200,
      headers: const {"content-type": "application/json; charset=utf-8"},
      request: peticion,
    );
  }
}

void main() {
  late _ClienteEspia espia;
  late SupabaseClient cliente;
  late Sesion sesion;

  setUp(() async {
    espia = _ClienteEspia();
    cliente = SupabaseClient(
      "https://proyecto.supabase.co",
      "sb_publishable_de_mentira",
      httpClient: espia,
    );
    sesion = Sesion(cliente: cliente);
    await cliente.auth.signInWithPassword(
      email: "alumno@ejemplo.test",
      password: "da-igual",
    );
    espia.peticiones.clear();
  });

  tearDown(() async => cliente.dispose());

  group("eliminarCuenta", () {
    test("llama al RPC y no manda ningún id", () async {
      await sesion.eliminarCuenta();

      final rpc = espia.peticiones.firstWhere(
        (p) => p.$2.path == "/rest/v1/rpc/eliminar_mi_cuenta",
        orElse: () => throw StateError("no se llamó al RPC"),
      );
      expect(rpc.$1, "POST");
      expect(
        rpc.$2.query,
        isEmpty,
        reason:
            "la función resuelve al usuario con auth.uid(); mandarle un id "
            "sería darle la forma de borrar cuentas ajenas",
      );
    });

    test("cierra la sesión local después de borrar", () async {
      expect(sesion.hayCuenta, isTrue);

      await sesion.eliminarCuenta();

      expect(
        sesion.hayCuenta,
        isFalse,
        reason:
            "la sesión que queda en el dispositivo apunta a un usuario que ya "
            "no existe: la siguiente pantalla fallaría con un error opaco",
      );
    });

    test("sin sesión no llama a nada y lo dice", () async {
      await cliente.auth.signOut();
      espia.peticiones.clear();

      await expectLater(sesion.eliminarCuenta(), throwsA(isA<ErrorSesion>()));
      expect(
        espia.peticiones.where((p) => p.$2.path.contains("eliminar_mi_cuenta")),
        isEmpty,
      );
    });

    test("si la migración no está aplicada, el aviso es en español", () async {
      // PGRST202: la función no existe en la base. Pasa si el APK se publica
      // antes de aplicar `20260914120000_borrar_cuenta.sql`, y el mensaje
      // crudo de PostgREST no le dice nada a un alumno.
      espia.estadoRpc = 404;
      espia.cuerpoRpc = jsonEncode({
        "code": "PGRST202",
        "message": "Could not find the function public.eliminar_mi_cuenta",
        "details": null,
        "hint": null,
      });

      await expectLater(
        sesion.eliminarCuenta(),
        throwsA(
          isA<ErrorSesion>().having(
            (e) => e.mensaje,
            "mensaje",
            contains("todavía no admite"),
          ),
        ),
      );
    });

    test("si el borrado falla, la sesión NO se cierra", () async {
      espia.estadoRpc = 500;
      espia.cuerpoRpc = jsonEncode({
        "code": "XX000",
        "message": "boom",
        "details": null,
        "hint": null,
      });

      await expectLater(sesion.eliminarCuenta(), throwsA(isA<ErrorSesion>()));
      expect(
        sesion.hayCuenta,
        isTrue,
        reason:
            "cerrar la sesión de un borrado que falló haría creer al alumno "
            "que su cuenta ya no está",
      );
    });
  });

  group("traducir", () {
    test("los mensajes de Supabase llegan en español", () {
      expect(traducir("Invalid login credentials"), contains("incorrectos"));
      expect(traducir("Email not confirmed"), contains("confirmaste"));
      expect(traducir("User already registered"), contains("Ya existe"));
      expect(traducir("rate limit exceeded"), contains("Demasiados intentos"));
    });

    test("un mensaje que no conoce pasa tal cual, no se traga", () {
      expect(traducir("algo rarísimo"), "algo rarísimo");
    });
  });
}
