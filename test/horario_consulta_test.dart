// Lo que `RepositorioHorario` escribe y borra, sin tocar la red.
//
// El caso que motivó el archivo: `crear()` no devolvía nada, así que la
// pantalla metía el bloque nuevo en su lista con un id NEGATIVO inventado
// —«provisional hasta la próxima recarga»— y esa recarga no existe, porque el
// horario solo se carga en `initState`. Borrar un bloque recién creado, sin
// salir de la pantalla, mandaba el `delete` contra una fila inexistente.
// PostgREST no se queja cuando no encuentra nada, así que el bloque
// desaparecía de la pantalla y seguía en la base hasta la siguiente visita.
//
// Mismo cliente espía que `simulacro_consulta_test.dart`.
import "dart:convert";

import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:matr_u/data/models/horario.dart";
import "package:supabase/supabase.dart";

const _idPropio = "11111111-1111-1111-1111-111111111111";

class _ClienteEspia extends http.BaseClient {
  final peticiones = <(String metodo, Uri url, String cuerpo)>[];

  /// El id que Postgres devuelve al insertar.
  int idNuevo = 77;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest peticion) async {
    final enviado = peticion is http.Request ? peticion.body : "";
    peticiones.add((peticion.method, peticion.url, enviado));
    final ruta = peticion.url.path;

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
      "/rest/v1/cursos" => jsonEncode({"id": 5}),
      "/rest/v1/horarios_estudio" =>
        peticion.method == "POST" ? jsonEncode({"id": idNuevo}) : "[]",
      _ => "[]",
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
  late RepositorioHorario repo;

  setUp(() async {
    espia = _ClienteEspia();
    cliente = SupabaseClient(
      "https://proyecto.supabase.co",
      "sb_publishable_de_mentira",
      httpClient: espia,
    );
    repo = RepositorioHorario(cliente: cliente);
    await cliente.auth.signInWithPassword(
      email: "alumno@ejemplo.test",
      password: "da-igual",
    );
    espia.peticiones.clear();
  });

  tearDown(() async => cliente.dispose());

  Future<int> crearBloque() => repo.crear(
    cursoCodigo: "ALG",
    diaSemana: 1,
    horaInicio: "17:00:00",
    duracionMinutos: 60,
  );

  test("crear devuelve el id que puso Postgres, no uno inventado", () async {
    espia.idNuevo = 4321;

    final id = await crearBloque();

    expect(id, 4321);
    expect(
      id,
      greaterThan(0),
      reason: "un id negativo era la señal de que estaba inventado",
    );
  });

  test("el bloque recién creado se puede borrar de verdad", () async {
    // La secuencia exacta que fallaba: crear y borrar sin recargar.
    final id = await crearBloque();
    espia.peticiones.clear();

    await repo.eliminar(id);

    final borrado = espia.peticiones.firstWhere(
      (p) => p.$1 == "DELETE",
      orElse: () => throw StateError("no se mandó ningún DELETE"),
    );
    expect(
      borrado.$2.queryParameters["id"],
      "eq.$id",
      reason: "el delete tiene que ir contra la fila que se acaba de insertar",
    );
    expect(borrado.$2.queryParameters["perfil_id"], "eq.$_idPropio");
  });

  test("el insert pide el id de vuelta", () async {
    await crearBloque();

    final insert = espia.peticiones.firstWhere(
      (p) => p.$1 == "POST" && p.$2.path == "/rest/v1/horarios_estudio",
    );
    expect(
      insert.$2.queryParameters["select"],
      isNotNull,
      reason: "sin `.select(\"id\")` la respuesta vuelve vacía",
    );
  });

  group("las validaciones van antes de tocar la red", () {
    test("un día fuera de 0..6 se rechaza aquí", () async {
      await expectLater(
        repo.crear(
          cursoCodigo: "ALG",
          diaSemana: 7,
          horaInicio: "17:00:00",
          duracionMinutos: 60,
        ),
        throwsA(isA<ErrorHorario>()),
      );
      expect(espia.peticiones, isEmpty);
    });

    test("una duración de más de 8 horas se rechaza aquí", () async {
      await expectLater(
        repo.crear(
          cursoCodigo: "ALG",
          diaSemana: 1,
          horaInicio: "17:00:00",
          duracionMinutos: 481,
        ),
        throwsA(isA<ErrorHorario>()),
      );
      expect(espia.peticiones, isEmpty);
    });

    test("una duración de cero también", () async {
      await expectLater(
        repo.crear(
          cursoCodigo: "ALG",
          diaSemana: 1,
          horaInicio: "17:00:00",
          duracionMinutos: 0,
        ),
        throwsA(isA<ErrorHorario>()),
      );
      expect(espia.peticiones, isEmpty);
    });
  });
}
