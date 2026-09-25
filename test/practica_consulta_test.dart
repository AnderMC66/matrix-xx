// `RepositorioPractica`: corregir una respuesta y reportar un error.
//
// Estaba al **1,9 % de cobertura**, y es la capa donde vive la invariante que
// sostiene todo el diseño del banco: la app no sabe la respuesta correcta.
// Corregir pasa siempre por el RPC `responder_pregunta`, que es quien conoce
// la clave. Lo que este archivo fija es que esa ruta no se pueda saltar por
// accidente, y que el intento nazca cuando debe.
//
// Mismo cliente espía que `simulacro_consulta_test.dart`.
import "dart:convert";

import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:matr_u/data/repositories/practica.dart";
import "package:matr_u/domain/models/practica.dart";
import "package:matr_u/domain/models/preguntas.dart";
import "package:supabase/supabase.dart";

const _idPropio = "11111111-1111-1111-1111-111111111111";

class _ClienteEspia extends http.BaseClient {
  final peticiones = <(String metodo, Uri url, String cuerpo)>[];

  /// `null` = la pregunta no está publicada.
  Map<String, dynamic>? filaPregunta = {"id": 900};

  /// Lo que devuelve `responder_pregunta`.
  Object? correccion = [
    {"es_correcta": true, "clave": "C", "explicacion_md": "  Porque sí.  "},
  ];

  /// Código de error para el insert en `reportes_error`, si lo hay.
  String? errorReporte;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest peticion) async {
    final enviado = peticion is http.Request ? peticion.body : "";
    peticiones.add((peticion.method, peticion.url, enviado));
    final ruta = peticion.url.path;

    if (ruta == "/auth/v1/token") {
      return _json(peticion, jsonEncode(_sesion), 200);
    }
    if (ruta == "/rest/v1/preguntas") {
      return _json(peticion, jsonEncode(filaPregunta), 200);
    }
    if (ruta == "/rest/v1/rpc/responder_pregunta") {
      return _json(peticion, jsonEncode(correccion), 200);
    }
    if (ruta == "/rest/v1/intentos") {
      return _json(peticion, jsonEncode({"id": 42}), 200);
    }
    if (ruta == "/rest/v1/reportes_error" && errorReporte != null) {
      return _json(
        peticion,
        jsonEncode({
          "code": errorReporte,
          "message": "x",
          "details": null,
          "hint": null,
        }),
        400,
      );
    }
    return _json(peticion, "[]", 200);
  }

  http.StreamedResponse _json(http.BaseRequest p, String cuerpo, int estado) =>
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

/// El cuerpo de un insert. `postgrest` manda un objeto suelto cuando se
/// inserta una fila y una lista cuando son varias; se normaliza aquí para que
/// el test no dependa de cuál de las dos elija la versión del cliente.
Map<String, dynamic> filaEnviada(String cuerpo) {
  final json = jsonDecode(cuerpo);
  return (json is List ? json.first : json) as Map<String, dynamic>;
}

void main() {
  late _ClienteEspia espia;
  late SupabaseClient cliente;
  late RepositorioPractica repo;

  setUp(() async {
    espia = _ClienteEspia();
    cliente = SupabaseClient(
      "https://proyecto.supabase.co",
      "sb_publishable_de_mentira",
      httpClient: espia,
    );
    repo = RepositorioPractica(cliente: cliente);
    await cliente.auth.signInWithPassword(
      email: "alumno@ejemplo.test",
      password: "da-igual",
    );
    espia.peticiones.clear();
  });

  tearDown(() async => cliente.dispose());

  Future<Correccion> responder() =>
      repo.responder(codigoPregunta: "QUI-2027-001", marcada: Letra.c);

  group("responder", () {
    test("sin sesión no llama a nada y lo dice claro", () async {
      await cliente.auth.signOut();
      espia.peticiones.clear();

      await expectLater(responder(), throwsA(isA<ErrorPractica>()));
      expect(
        espia.peticiones,
        isEmpty,
        reason:
            "sin cuenta no hay corrección posible: la clave la tiene el RPC",
      );
    });

    test("el intento nace con la PRIMERA respuesta, no antes", () async {
      expect(
        repo.intentoId,
        isNull,
        reason: "abrir la práctica y salir no debe dejar una fila en intentos",
      );

      await responder();

      expect(repo.intentoId, 42);
      expect(espia.de("/rest/v1/intentos"), hasLength(1));
    });

    test("la segunda respuesta reutiliza el intento", () async {
      await responder();
      espia.peticiones.clear();

      await responder();

      expect(espia.de("/rest/v1/intentos"), isEmpty);
    });

    test("solo responde preguntas publicadas", () async {
      await responder();

      final consulta = espia.de("/rest/v1/preguntas").first.$2;
      expect(consulta.queryParameters["codigo_externo"], "eq.QUI-2027-001");
      expect(
        consulta.queryParameters["estado"],
        "eq.publicada",
        reason:
            "una pregunta retirada no se puede responder ni desde un APK "
            "viejo",
      );
    });

    test(
      "una pregunta que ya no está da un aviso, no un fallo opaco",
      () async {
        espia.filaPregunta = null;

        await expectLater(responder(), throwsA(isA<ErrorPractica>()));
      },
    );

    test("la corrección se lee y la explicación llega recortada", () async {
      final c = await responder();

      expect(c.esCorrecta, isTrue);
      expect(c.clave, Letra.c);
      expect(c.explicacion, "Porque sí.");
    });

    test(
      "da igual que el RPC devuelva la fila suelta o en una lista",
      () async {
        espia.correccion = {
          "es_correcta": false,
          "clave": "a",
          "explicacion_md": null,
        };

        final c = await responder();

        expect(c.esCorrecta, isFalse);
        expect(c.clave, Letra.a);
        expect(c.explicacion, isNull);
      },
    );

    test("si el RPC retiene la clave, se dice en vez de inventarla", () async {
      // Pasa si el intento no es de práctica: en simulacro la clave no se
      // revela hasta finalizar. Enseñar «correcta: null» sería peor.
      espia.correccion = [
        {"es_correcta": null, "clave": null, "explicacion_md": null},
      ];

      await expectLater(responder(), throwsA(isA<ErrorPractica>()));
    });

    test("los segundos viajan solo si se pasan", () async {
      await repo.responder(
        codigoPregunta: "QUI-2027-001",
        marcada: Letra.b,
        segundos: 12,
      );

      final cuerpo = jsonDecode(
        espia.de("/rest/v1/rpc/responder_pregunta").first.$3,
      );
      expect(cuerpo, containsPair("p_segundos", 12));
      expect(cuerpo, containsPair("p_letra", "B"));
    });
  });

  group("finalizar", () {
    test("sin intento no hay nada que cerrar", () async {
      await repo.finalizar();
      expect(espia.peticiones, isEmpty);
    });

    test("cierra el intento y lo olvida", () async {
      await responder();
      espia.peticiones.clear();

      await repo.finalizar();

      expect(espia.de("/rest/v1/rpc/finalizar_intento"), hasLength(1));
      expect(repo.intentoId, isNull);
    });
  });

  group("reportar", () {
    test("un motivo fuera de la lista se rechaza aquí", () async {
      await expectLater(
        repo.reportar(codigoPregunta: "QUI-2027-001", motivo: "Inventado"),
        throwsA(isA<ErrorPractica>()),
      );
      expect(espia.peticiones, isEmpty);
    });

    test("los cuatro motivos de la interfaz sí pasan", () async {
      for (final motivo in RepositorioPractica.motivosReporte) {
        expect(
          await repo.reportar(codigoPregunta: "QUI-2027-001", motivo: motivo),
          isFalse,
        );
      }
    });

    test(
      "un detalle en blanco se guarda como nulo, no como cadena vacía",
      () async {
        // Sin esto, la bandeja del docente no distingue «no escribió nada» de
        // «escribió y lo borró».
        await repo.reportar(
          codigoPregunta: "QUI-2027-001",
          motivo: "Otro",
          detalle: "   ",
        );

        final fila = filaEnviada(espia.de("/rest/v1/reportes_error").first.$3);
        expect(fila["detalle"], isNull);
      },
    );

    test("un detalle largo se recorta al tope de la tabla", () async {
      await repo.reportar(
        codigoPregunta: "QUI-2027-001",
        motivo: "Otro",
        detalle: "x" * 1500,
      );

      final fila = filaEnviada(espia.de("/rest/v1/reportes_error").first.$3);
      expect((fila["detalle"] as String).length, 1000);
    });

    test(
      "reportar dos veces la misma no es un error: ya estaba en la cola",
      () async {
        espia.errorReporte = "23505"; // índice único parcial

        expect(
          await repo.reportar(codigoPregunta: "QUI-2027-001", motivo: "Otro"),
          isTrue,
        );
      },
    );

    test("otro error de Postgres sí sube", () async {
      espia.errorReporte = "42501";

      await expectLater(
        repo.reportar(codigoPregunta: "QUI-2027-001", motivo: "Otro"),
        throwsA(isA<PostgrestException>()),
      );
    });
  });
}
