// `RepositorioPanel`: lo que el docente y el admin leen y escriben.
//
// Estaba al **1,8 %**, y es la capa con más consecuencias por fila: publica
// preguntas que verán todos los alumnos y reparte permisos. El control de
// acceso real vive en Postgres —las seis funciones comprueban
// `es_staff()`/`es_admin()` por dentro—, así que lo que se prueba aquí no es
// quién puede, sino que lo que se manda y lo que se lee sean lo que dicen.
//
// Mismo cliente espía que los otros archivos `*_consulta_test.dart`.
import "dart:convert";

import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:matr_u/data/repositories/panel.dart";
import "package:matr_u/domain/models/panel.dart";
import "package:matr_u/domain/models/preguntas.dart" show Letra;
import "package:supabase/supabase.dart";

const _idPropio = "11111111-1111-1111-1111-111111111111";

class _ClienteEspia extends http.BaseClient {
  final peticiones = <(String metodo, Uri url, String cuerpo)>[];

  /// Respuesta por nombre de RPC.
  final rpc = <String, Object?>{};

  /// Respuesta por tabla.
  final tablas = <String, Object?>{};

  /// Si se pone, la próxima llamada a un RPC contesta con este error.
  String? errorRpc;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest peticion) async {
    final enviado = peticion is http.Request ? peticion.body : "";
    peticiones.add((peticion.method, peticion.url, enviado));
    final ruta = peticion.url.path;

    if (ruta == "/auth/v1/token") return _r(peticion, jsonEncode(_sesion), 200);

    if (ruta.startsWith("/rest/v1/rpc/")) {
      if (errorRpc != null) {
        return _r(
          peticion,
          jsonEncode({
            "code": "P0001",
            "message": errorRpc,
            "details": null,
            "hint": null,
          }),
          400,
        );
      }
      return _r(peticion, jsonEncode(rpc[ruta.split("/").last] ?? []), 200);
    }

    final tabla = ruta.replaceFirst("/rest/v1/", "");
    return _r(peticion, jsonEncode(tablas[tabla] ?? []), 200);
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

  (String, Uri, String) ultima(String fragmento) =>
      peticiones.lastWhere((p) => p.$2.path.contains(fragmento));
}

void main() {
  late _ClienteEspia espia;
  late SupabaseClient cliente;
  late RepositorioPanel repo;

  setUp(() async {
    espia = _ClienteEspia();
    cliente = SupabaseClient(
      "https://proyecto.supabase.co",
      "sb_publishable_de_mentira",
      httpClient: espia,
    );
    repo = RepositorioPanel(cliente: cliente);
    await cliente.auth.signInWithPassword(
      email: "docente@ejemplo.test",
      password: "da-igual",
    );
    espia.peticiones.clear();
  });

  tearDown(() async => cliente.dispose());

  group("rolActual", () {
    test("sin sesión es nulo y no consulta", () async {
      await cliente.auth.signOut();
      espia.peticiones.clear();

      expect(await repo.rolActual(), isNull);
      expect(espia.peticiones, isEmpty);
    });

    test("lee de perfiles, no de un claim del token", () async {
      // El rol puede cambiar mientras la sesión sigue viva: un token emitido
      // antes del cambio seguiría diciendo lo de antes hasta que caduque.
      espia.tablas["perfiles"] = {"rol": "admin"};

      expect(await repo.rolActual(), Rol.admin);

      final consulta = espia.ultima("perfiles").$2;
      expect(consulta.queryParameters["id"], "eq.$_idPropio");
    });

    test("un rol desconocido cae en alumno, no en staff", () async {
      espia.tablas["perfiles"] = {"rol": "inventado"};
      expect(await repo.rolActual(), Rol.alumno);
      expect(esStaff(await repo.rolActual()), isFalse);
    });

    test("sin fila de perfil, nulo", () async {
      espia.tablas["perfiles"] = null;
      expect(await repo.rolActual(), isNull);
    });
  });

  group("paraRevision", () {
    test("la clave ausente NO se convierte en «A»", () async {
      // Es la pantalla que existe para auditar esa letra: inventarla haría
      // que un docente publicara una clave falsa con su visto bueno.
      espia.rpc["preguntas_para_revision"] = [
        {
          "id": 1,
          "codigo_externo": "QUI-2027-001",
          "enunciado_md": "¿?",
          "clave": null,
          "estado": "sin_auditar",
          "alternativas": [],
        },
      ];

      final p = (await repo.paraRevision(filtro: "sin_auditar")).single;

      expect(p.clave, isNull);
    });

    test("una clave legible se lee", () async {
      espia.rpc["preguntas_para_revision"] = [
        {
          "id": 1,
          "clave": "d",
          "enunciado_md": "x",
          "alternativas": [
            {"letra": "A", "texto_md": "uno"},
            {"letra": "B", "texto_md": "dos"},
          ],
        },
      ];

      final p = (await repo.paraRevision(filtro: "publicada")).single;

      expect(p.clave, Letra.d);
      expect(p.alternativas.map((a) => a.letra), [Letra.a, Letra.b]);
    });

    test("una alternativa con letra ilegible se descarta, no rompe", () async {
      espia.rpc["preguntas_para_revision"] = [
        {
          "id": 1,
          "clave": "a",
          "alternativas": [
            {"letra": "A", "texto_md": "uno"},
            {"letra": "?", "texto_md": "basura"},
          ],
        },
      ];

      final p = (await repo.paraRevision(filtro: "publicada")).single;

      expect(p.alternativas, hasLength(1));
    });

    test(
      "el filtro y el curso viajan; sin curso no se manda el parámetro",
      () async {
        await repo.paraRevision(filtro: "sin_auditar");
        var cuerpo = jsonDecode(espia.ultima("preguntas_para_revision").$3);
        expect(cuerpo, containsPair("p_filtro", "sin_auditar"));
        expect(cuerpo, isNot(contains("p_curso_codigo")));

        await repo.paraRevision(filtro: "publicada", cursoCodigo: "QUI");
        cuerpo = jsonDecode(espia.ultima("preguntas_para_revision").$3);
        expect(cuerpo, containsPair("p_curso_codigo", "QUI"));
      },
    );
  });

  group("dictaminar", () {
    test("una pregunta se manda con su id y su estado", () async {
      await repo.dictaminarPregunta(preguntaId: 7, estado: "publicada");

      final cuerpo = jsonDecode(espia.ultima("revisar_pregunta").$3);
      expect(cuerpo, containsPair("p_pregunta_id", 7));
      expect(cuerpo, containsPair("p_estado", "publicada"));
    });

    test("el error de Postgres llega traducido a ErrorPanel", () async {
      // El RPC rechaza lo que no debe pasar; la app tiene que enseñar SU
      // mensaje, no un fallo genérico.
      espia.errorRpc = "no puedes auditar tu propia pregunta";

      await expectLater(
        repo.dictaminarPregunta(preguntaId: 7, estado: "publicada"),
        throwsA(
          isA<ErrorPanel>().having(
            (e) => e.mensaje,
            "mensaje",
            contains("auditar"),
          ),
        ),
      );
    });

    test("un reporte se resuelve igual", () async {
      await repo.dictaminarReporte(reporteId: 3, estado: "aceptado");

      final cuerpo = jsonDecode(espia.ultima("resolver_reporte").$3);
      expect(cuerpo, containsPair("p_reporte_id", 3));
      expect(cuerpo, containsPair("p_estado", "aceptado"));
    });
  });

  group("reportes", () {
    test("«todos» no filtra por estado; un estado concreto sí", () async {
      await repo.reportes("todos");
      expect(
        espia.ultima("reportes_error").$2.queryParameters,
        isNot(contains("estado")),
      );

      await repo.reportes("abierto");
      expect(
        espia.ultima("reportes_error").$2.queryParameters["estado"],
        "eq.abierto",
      );
    });

    test("se lee la pregunta anidada, y su ausencia no rompe", () async {
      espia.tablas["reportes_error"] = [
        {
          "id": 1,
          "motivo": "Clave incorrecta",
          "detalle": null,
          "estado": "abierto",
          "creado_en": "2026-09-01T10:00:00+00:00",
          "pregunta_id": 5,
          "preguntas": {"codigo_externo": "QUI-2027-001", "enunciado_md": "¿?"},
        },
        {
          "id": 2,
          "motivo": "Otro",
          "detalle": "algo",
          "estado": "abierto",
          "creado_en": "2026-09-02T10:00:00+00:00",
          "pregunta_id": 6,
          "preguntas": null,
        },
      ];

      final lista = await repo.reportes("abierto");

      expect(lista, hasLength(2));
      expect(lista.first.preguntaCodigo, "QUI-2027-001");
      expect(lista.last.preguntaCodigo, isNull);
    });
  });

  group("personas y roles", () {
    test(
      "una lista vacía no es un fallo: es un docente, no un admin",
      () async {
        // `personas_del_panel` comprueba `es_admin()` por dentro y le devuelve
        // vacío a un docente.
        espia.rpc["personas_del_panel"] = [];
        expect(await repo.personas(), isEmpty);
      },
    );

    test("se leen los campos de cada persona", () async {
      espia.rpc["personas_del_panel"] = [
        {
          "id": "abc",
          "nombre": "Ana",
          "correo": "ana@x.test",
          "rol": "docente",
          "plan": "gratis",
        },
      ];

      final p = (await repo.personas()).single;

      expect(p.id, "abc");
      expect(p.rol, Rol.docente);
      expect(esStaff(p.rol), isTrue);
    });

    test("cambiar el rol manda el nombre que espera el RPC", () async {
      await repo.cambiarRol(perfilId: "abc", rol: Rol.admin);

      final cuerpo = jsonDecode(espia.ultima("cambiar_rol").$3);
      expect(cuerpo, containsPair("p_perfil_id", "abc"));
      expect(cuerpo, containsPair("p_rol", "admin"));
    });

    test(
      "quitar el último admin lo rechaza la base, y se ve el porqué",
      () async {
        espia.errorRpc = "no puedes quitar el último administrador";

        await expectLater(
          repo.cambiarRol(perfilId: "abc", rol: Rol.alumno),
          throwsA(
            isA<ErrorPanel>().having(
              (e) => e.mensaje,
              "mensaje",
              contains("último administrador"),
            ),
          ),
        );
      },
    );
  });

  group("resumen", () {
    test("una fila suelta o dentro de una lista se leen igual", () async {
      for (final forma in [
        {"sin_auditar": 4, "publicadas": 380, "reportes_abiertos": 2},
        [
          {"sin_auditar": 4, "publicadas": 380, "reportes_abiertos": 2},
        ],
      ]) {
        espia.rpc["resumen_panel"] = forma;
        final r = await repo.resumen();
        expect(r!.sinAuditar, 4);
        expect(r.publicadas, 380);
        expect(r.reportesAbiertos, 2);
      }
    });

    test("los campos que falten valen cero, no rompen la pantalla", () async {
      espia.rpc["resumen_panel"] = {"sin_auditar": 1};
      final r = await repo.resumen();
      expect(r!.sinAuditar, 1);
      expect(r.personas, 0);
    });
  });
}
