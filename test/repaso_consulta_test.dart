// `RepositorioRepaso`: la capa de repetición espaciada.
//
// Estaba al **0 % de cobertura** pese a aceptar un cliente inyectado desde
// siempre. Es la capa que decide qué se le pone delante al alumno cada día, y
// la que sostiene la invariante central del proyecto: los RPC devuelven solo
// `codigo_externo`, nunca el enunciado ni la clave, y el APK pone el resto.
// Sin tests, esa invariante vivía en un comentario.
//
// Mismo cliente espía que `simulacro_consulta_test.dart`.
import "dart:convert";

import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:matr_u/data/repositories/preguntas.dart";
import "package:matr_u/data/repositories/repaso.dart";
import "package:supabase/supabase.dart";

const _idPropio = "11111111-1111-1111-1111-111111111111";

class _ClienteEspia extends http.BaseClient {
  final peticiones = <(String metodo, Uri url, String cuerpo)>[];

  /// Lo que contesta cada RPC, por nombre.
  final respuestas = <String, Object?>{};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest peticion) async {
    final enviado = peticion is http.Request ? peticion.body : "";
    peticiones.add((peticion.method, peticion.url, enviado));
    final ruta = peticion.url.path;

    if (ruta.startsWith("/rest/v1/rpc/")) {
      final nombre = ruta.split("/").last;
      return _json(peticion, jsonEncode(respuestas[nombre] ?? []));
    }
    if (ruta == "/auth/v1/token") {
      return _json(
        peticion,
        jsonEncode({
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
      );
    }
    return _json(peticion, "[]");
  }

  http.StreamedResponse _json(http.BaseRequest p, String cuerpo) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(cuerpo)),
        200,
        headers: const {"content-type": "application/json; charset=utf-8"},
        request: p,
      );

  Iterable<Uri> get rpcs =>
      peticiones.map((p) => p.$2).where((u) => u.path.contains("/rpc/"));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ClienteEspia espia;
  late SupabaseClient cliente;
  late RepositorioRepaso repo;

  /// Dos códigos que existen de verdad en el banco del APK, más uno que no.
  late String codigoReal;
  late String otroReal;

  setUpAll(() async {
    final banco = await RepositorioPreguntas().cargar();
    codigoReal = banco.preguntas.first.codigo;
    otroReal = banco.preguntas[1].codigo;
  });

  setUp(() async {
    espia = _ClienteEspia();
    cliente = SupabaseClient(
      "https://proyecto.supabase.co",
      "sb_publishable_de_mentira",
      httpClient: espia,
    );
    repo = RepositorioRepaso(cliente: cliente);
    await cliente.auth.signInWithPassword(
      email: "alumno@ejemplo.test",
      password: "da-igual",
    );
    espia.peticiones.clear();
  });

  tearDown(() async => cliente.dispose());

  group("sin sesión no se arma ninguna petición", () {
    // El comentario de `_porCodigos` explica por qué la llamada llega como
    // función y no como Future ya construido: con un Future de parámetro, la
    // petición quedaba armada aunque no hubiera cuenta, y que no llegara a
    // salir dependía de un detalle interno de `postgrest`. Esto lo fija.
    setUp(() async {
      await cliente.auth.signOut();
      espia.peticiones.clear();
    });

    test("pendientes", () async {
      expect(await repo.pendientes(), isEmpty);
      expect(espia.rpcs, isEmpty);
    });

    test("falladas", () async {
      expect(await repo.falladas(), isEmpty);
      expect(espia.rpcs, isEmpty);
    });

    test("recomendadas", () async {
      expect(await repo.recomendadas(), isEmpty);
      expect(espia.rpcs, isEmpty);
    });

    test("resumen", () async {
      expect(await repo.resumen(), isNull);
      expect(espia.rpcs, isEmpty);
    });
  });

  group("los códigos se cruzan contra el banco del APK", () {
    test("un código conocido se resuelve a su pregunta entera", () async {
      espia.respuestas["repasos_pendientes"] = [
        {"codigo_externo": codigoReal},
      ];

      final preguntas = await repo.pendientes();

      expect(preguntas, hasLength(1));
      expect(preguntas.single.codigo, codigoReal);
      expect(
        preguntas.single.enunciado,
        isNotEmpty,
        reason: "el enunciado lo pone el APK: el RPC no lo manda",
      );
      expect(preguntas.single.alternativas, hasLength(5));
    });

    test("un código que el APK no tiene se descarta en silencio", () async {
      // Pasa de verdad: una pregunta retirada del banco después de que el
      // alumno la respondiera. Descartarla es mejor que romper la pantalla.
      espia.respuestas["preguntas_falladas"] = [
        {"codigo_externo": codigoReal},
        {"codigo_externo": "NO-EXISTE-000"},
        {"codigo_externo": otroReal},
      ];

      final preguntas = await repo.falladas();

      expect(preguntas.map((p) => p.codigo), [codigoReal, otroReal]);
    });

    test("se conserva el orden que mandó Postgres", () async {
      // El orden ES la recomendación: primero lo que más conviene repasar.
      espia.respuestas["preguntas_recomendadas"] = [
        {"codigo_externo": otroReal},
        {"codigo_externo": codigoReal},
      ];

      final preguntas = await repo.recomendadas();

      expect(preguntas.map((p) => p.codigo), [otroReal, codigoReal]);
    });

    test("una respuesta que no es lista da vacío, no una excepción", () async {
      espia.respuestas["repasos_pendientes"] = {"error": "raro"};
      expect(await repo.pendientes(), isEmpty);
    });
  });

  group("parámetros que llegan al RPC", () {
    test("el límite de pendientes viaja", () async {
      await repo.pendientes(limite: 7);

      final cuerpo = espia.peticiones
          .firstWhere((p) => p.$2.path.endsWith("repasos_pendientes"))
          .$3;
      expect(jsonDecode(cuerpo), containsPair("p_limite", 7));
    });

    test("sin curso, `p_curso_codigo` ni se manda", () async {
      await repo.recomendadas();

      final cuerpo = jsonDecode(
        espia.peticiones
            .firstWhere((p) => p.$2.path.endsWith("preguntas_recomendadas"))
            .$3,
      );
      expect(
        cuerpo,
        isNot(contains("p_curso_codigo")),
        reason: "mandar null y no mandar nada no significan lo mismo en el RPC",
      );
    });

    test("con curso, va el código", () async {
      await repo.recomendadas(cursoCodigo: "ALG");

      final cuerpo = jsonDecode(
        espia.peticiones
            .firstWhere((p) => p.$2.path.endsWith("preguntas_recomendadas"))
            .$3,
      );
      expect(cuerpo, containsPair("p_curso_codigo", "ALG"));
    });
  });

  group("resumen", () {
    test("una fila desenvuelta se lee igual que dentro de una lista", () async {
      // El RPC es `setof`: según la versión del cliente llega de las dos
      // formas, y `_primeraFila` existe justo para eso.
      for (final forma in [
        {
          "pendientes_hoy": 3,
          "proxima_fecha": "2026-09-20",
          "total_programados": 40,
        },
        [
          {
            "pendientes_hoy": 3,
            "proxima_fecha": "2026-09-20",
            "total_programados": 40,
          },
        ],
      ]) {
        espia.respuestas["resumen_repasos"] = forma;
        final r = await repo.resumen();
        expect(r!.pendientesHoy, 3);
        expect(r.totalProgramados, 40);
        expect(r.sinHistorial, isFalse);
      }
    });

    test("la fecha se ancla al mediodía para que no se corra de día", () async {
      // Llega como `date` sin hora. Sin el anclaje, un desfase de zona la
      // movería al día anterior o al siguiente.
      espia.respuestas["resumen_repasos"] = {
        "pendientes_hoy": 0,
        "proxima_fecha": "2026-09-20",
        "total_programados": 5,
      };

      final r = await repo.resumen();

      expect(r!.proximaFecha, DateTime(2026, 9, 20, 12));
    });

    test("sin fecha próxima, el campo queda nulo", () async {
      espia.respuestas["resumen_repasos"] = {
        "pendientes_hoy": 0,
        "proxima_fecha": null,
        "total_programados": 0,
      };

      final r = await repo.resumen();

      expect(r!.proximaFecha, isNull);
      expect(r.sinHistorial, isTrue);
    });

    test("una lista vacía significa «todavía nada»", () async {
      espia.respuestas["resumen_repasos"] = [];
      expect(await repo.resumen(), isNull);
    });
  });
}
