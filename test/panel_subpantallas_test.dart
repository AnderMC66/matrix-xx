// Las tres subpantallas del panel: revisión, reportes y personas.
//
// La portada del panel ya tenía tests (`panel_pantalla_test.dart`); esto es lo
// que colgaba de ella y quedó fuera, que es donde el panel hace algo en vez de
// enseñar cifras: publicar preguntas, resolver reportes y repartir roles.
//
// El control de acceso real vive en Postgres —las seis funciones comprueban
// `es_staff()`/`es_admin()` por dentro—, así que lo que se fija aquí no es
// quién puede, sino que lo que se manda sea lo que la pantalla dice y que lo
// que vuelve se lea bien. Tres cosas concretas:
//
//   - **La clave se muestra aquí y en ningún otro sitio de la app**, y una
//     clave ausente NO puede convertirse en «A». Esta pantalla existe para
//     que un docente audite precisamente esa letra; una clave inventada,
//     auditada, se publica con el visto bueno de un profesor.
//   - **La `Key` por id de cada ficha.** Sin ella Flutter reutiliza el
//     `State` por posición: al dictaminar la primera, la lista se recarga y
//     el «Marcada como publicada» aparecía sobre la pregunta NUEVA que caía
//     en ese hueco, que nadie había tocado.
//   - **El error de Postgres llega con SU mensaje**, no como un fallo
//     genérico: «no puedes quitar el último administrador» es la única forma
//     de que un admin entienda por qué el cambio no entró.
import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:matr_u/data/repositories/panel.dart";
import "package:matr_u/data/repositories/sesion.dart";
import "package:matr_u/domain/models/panel.dart";
import "package:matr_u/ui/core/theme/tema.dart";
import "package:matr_u/ui/features/dashboard/views/panel.dart";
import "package:supabase/supabase.dart";

const _idPropio = "11111111-1111-1111-1111-111111111111";
const _idOtro = "22222222-2222-2222-2222-222222222222";

class _ClienteEspia extends http.BaseClient {
  final peticiones = <(String metodo, Uri url, String cuerpo)>[];

  List<Map<String, dynamic>> preguntas = [];
  List<Map<String, dynamic>> reportes = [];
  List<Map<String, dynamic>> personas = [];

  /// Si se pone, el RPC correspondiente responde con este error de Postgres.
  String? errorAlDictaminar;
  String? errorAlCambiarRol;

  bool fallaLaCarga = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest peticion) async {
    final enviado = peticion is http.Request ? peticion.body : "";
    peticiones.add((peticion.method, peticion.url, enviado));
    final ruta = peticion.url.path;

    if (ruta == "/auth/v1/token") return _r(peticion, jsonEncode(_sesion), 200);
    if (fallaLaCarga && ruta.startsWith("/rest/v1/")) {
      return _pgrst(peticion, "sin conexión");
    }

    return switch (ruta) {
      "/rest/v1/rpc/preguntas_para_revision" => _r(
        peticion,
        jsonEncode(preguntas),
        200,
      ),
      "/rest/v1/reportes_error" => _r(peticion, jsonEncode(reportes), 200),
      "/rest/v1/rpc/personas_del_panel" => _r(
        peticion,
        jsonEncode(personas),
        200,
      ),
      "/rest/v1/rpc/revisar_pregunta" || "/rest/v1/rpc/resolver_reporte" =>
        errorAlDictaminar == null
            ? _r(peticion, "null", 200)
            : _pgrst(peticion, errorAlDictaminar!),
      "/rest/v1/rpc/cambiar_rol" =>
        errorAlCambiarRol == null
            ? _r(peticion, "null", 200)
            : _pgrst(peticion, errorAlCambiarRol!),
      _ => _r(peticion, "[]", 200),
    };
  }

  http.StreamedResponse _pgrst(http.BaseRequest p, String mensaje) => _r(
    p,
    jsonEncode({
      "code": "P0001",
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
      "email": "admin@ejemplo.test",
      "app_metadata": <String, dynamic>{},
      "user_metadata": <String, dynamic>{},
      "created_at": "2026-01-01T00:00:00Z",
    },
  };

  Iterable<(String, Uri, String)> de(String ruta) =>
      peticiones.where((p) => p.$2.path == ruta);

  /// El cuerpo del último envío a un RPC, ya decodificado.
  Map<String, dynamic> ultimoEnvio(String ruta) =>
      jsonDecode(de(ruta).last.$3) as Map<String, dynamic>;
}

Map<String, dynamic> _pregunta({
  required int id,
  String? clave = "C",
  String estado = "borrador",
  String codigo = "QUI-2027-014",
}) => {
  "id": id,
  "codigo_externo": codigo,
  "enunciado_md": "¿Cuál es la masa molar del agua?",
  "enunciado_imagen_url": null,
  "enunciado_imagen_alt": null,
  "clave": clave,
  "explicacion_md": "Porque sí.",
  "estado": estado,
  "dificultad": "medio",
  "auditado_en": null,
  "curso_nombre": "Química",
  "subtema_nombre": "Materia",
  "reportes_abiertos": 0,
  "alternativas": [
    for (final l in ["A", "B", "C", "D", "E"])
      {
        "letra": l,
        "texto_md": "Opción $l",
        "imagen_url": null,
        "imagen_alt": null,
      },
  ],
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
    email: "admin@ejemplo.test",
    password: "da-igual",
  );

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> montar(WidgetTester tester, Widget pantalla) async {
    tester.view.physicalSize = const Size(1100, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: construirTema(), home: pantalla),
    );
    await asentar(tester);
  }

  // ==========================================================================
  // Revisión
  // ==========================================================================
  group("revisión de preguntas", () {
    Future<void> montarRevision(WidgetTester tester) => montar(
      tester,
      PantallaPanelRevision(repositorio: RepositorioPanel(cliente: cliente)),
    );

    testWidgets("la cola arranca en «Sin auditar»", (tester) async {
      espia.preguntas = [_pregunta(id: 1)];
      await entrar();
      await montarRevision(tester);

      expect(
        espia.ultimoEnvio("/rest/v1/rpc/preguntas_para_revision")["p_filtro"],
        "sin_auditar",
        reason: "es la cola que de verdad hay que mirar antes de publicar",
      );
      expect(find.textContaining("QUI-2027-014"), findsOneWidget);
    });

    testWidgets("la clave se muestra, porque es lo que hay que auditar", (
      tester,
    ) async {
      espia.preguntas = [_pregunta(id: 1, clave: "C")];
      await entrar();
      await montarRevision(tester);

      // La alternativa correcta se marca; la letra sale en su círculo.
      expect(find.text("C"), findsWidgets);
      expect(
        espia.de("/rest/v1/rpc/preguntas_para_revision"),
        hasLength(1),
        reason:
            "`preguntas.clave` está revocada por columna a `authenticated`: "
            "solo sale por el RPC, nunca por un `select`",
      );
    });

    testWidgets("una clave ausente NO se convierte en «A»", (tester) async {
      espia.preguntas = [_pregunta(id: 1, clave: null)];
      await entrar();
      await montarRevision(tester);

      expect(
        find.textContaining("no devolvió la clave"),
        findsOneWidget,
        reason:
            "de todos los sitios donde inventar un valor sale mal, este es el "
            "peor: una clave falsa auditada se publica con el visto bueno de "
            "un profesor",
      );
    });

    testWidgets("cada ficha lleva su Key por id", (tester) async {
      espia.preguntas = [
        _pregunta(id: 1, codigo: "QUI-2027-001"),
        _pregunta(id: 2, codigo: "QUI-2027-002"),
      ];
      await entrar();
      await montarRevision(tester);

      expect(find.byKey(const ValueKey(1)), findsOneWidget);
      expect(
        find.byKey(const ValueKey(2)),
        findsOneWidget,
        reason:
            "sin la Key, al dictaminar la primera el «Marcada como publicada» "
            "aparecía sobre la pregunta nueva que caía en ese hueco",
      );
    });

    testWidgets("publicar manda el estado que dice el botón", (tester) async {
      espia.preguntas = [_pregunta(id: 7)];
      await entrar();
      await montarRevision(tester);

      await tester.tap(find.text("Correcta, publicar"));
      await asentar(tester);

      final envio = espia.ultimoEnvio("/rest/v1/rpc/revisar_pregunta");
      expect(envio["p_pregunta_id"], 7);
      expect(envio["p_estado"], "publicada");
    });

    testWidgets("«borrador» no es un destino que se ofrezca", (tester) async {
      espia.preguntas = [_pregunta(id: 1)];
      await entrar();
      await montarRevision(tester);

      // El estado actual sí se lee en la cabecera de la ficha —es información
      // de la pregunta—; lo que no existe es un botón que la mande ahí.
      expect(find.textContaining("borrador"), findsOneWidget);
      for (final destino in [
        "Correcta, publicar",
        "Dudosa, sacar de circulación",
        "Retirar",
      ]) {
        expect(find.text(destino), findsOneWidget);
      }
      expect(
        find.text("Borrador"),
        findsNothing,
        reason:
            "es el estado de algo a medio escribir, y lo que llega a revisión "
            "ya está escrito",
      );
    });

    testWidgets("el error de Postgres llega con su mensaje", (tester) async {
      espia
        ..preguntas = [_pregunta(id: 7)]
        ..errorAlDictaminar = "solo un admin puede publicar";
      await entrar();
      await montarRevision(tester);

      await tester.tap(find.text("Correcta, publicar"));
      await asentar(tester);

      expect(
        find.textContaining("solo un admin puede publicar"),
        findsOneWidget,
      );
    });

    testWidgets("cambiar de filtro vuelve a pedir la cola", (tester) async {
      espia.preguntas = [_pregunta(id: 1)];
      await entrar();
      await montarRevision(tester);
      espia.peticiones.clear();

      await tester.tap(find.text("Publicadas"));
      await asentar(tester);

      expect(
        espia.ultimoEnvio("/rest/v1/rpc/preguntas_para_revision")["p_filtro"],
        "publicada",
      );
    });

    testWidgets("si la carga falla, hay aviso y «Reintentar»", (tester) async {
      espia.fallaLaCarga = true;
      await entrar();
      await montarRevision(tester);

      expect(
        find.textContaining("No se pudieron cargar las preguntas"),
        findsOneWidget,
      );
      expect(find.widgetWithText(OutlinedButton, "Reintentar"), findsOneWidget);
    });
  });

  // ==========================================================================
  // Reportes
  // ==========================================================================
  group("reportes", () {
    Future<void> montarReportes(WidgetTester tester) => montar(
      tester,
      PantallaPanelReportes(repositorio: RepositorioPanel(cliente: cliente)),
    );

    Map<String, dynamic> reporte({int id = 3, String estado = "abierto"}) => {
      "id": id,
      "motivo": "Clave incorrecta",
      "detalle": "La respuesta debería ser la B.",
      "estado": estado,
      "creado_en": "2026-09-12T10:00:00+00:00",
      "pregunta_id": 900,
      "preguntas": {
        "codigo_externo": "QUI-2027-014",
        "enunciado_md": "¿Cuál es la masa molar del agua?",
      },
    };

    testWidgets("arranca por los abiertos, que son los que hay que mirar", (
      tester,
    ) async {
      espia.reportes = [reporte()];
      await entrar();
      await montarReportes(tester);

      final consulta = espia.de("/rest/v1/reportes_error").first.$2;
      expect(consulta.queryParameters["estado"], "eq.abierto");
      expect(find.textContaining("Clave incorrecta"), findsOneWidget);
      expect(
        find.textContaining("La respuesta debería ser la B"),
        findsWidgets,
      );
    });

    testWidgets("no se enseña quién reportó", (tester) async {
      espia.reportes = [reporte()];
      await entrar();
      await montarReportes(tester);

      final consulta = espia.de("/rest/v1/reportes_error").first.$2;
      expect(
        consulta.queryParameters["select"],
        isNot(contains("perfil")),
        reason:
            "para decidir si el reporte tiene razón hace falta la pregunta, "
            "no el alumno; y `perfiles_select` deja ver perfiles ajenos a los "
            "admin y no a los docentes",
      );
    });

    testWidgets("aceptar manda el estado correcto", (tester) async {
      espia.reportes = [reporte()];
      await entrar();
      await montarReportes(tester);

      await tester.tap(find.text("Tenía razón"));
      await asentar(tester);

      final envio = espia.ultimoEnvio("/rest/v1/rpc/resolver_reporte");
      expect(envio["p_reporte_id"], 3);
      expect(envio["p_estado"], "aceptado");
    });

    testWidgets("sin reportes, lo dice", (tester) async {
      await entrar();
      await montarReportes(tester);

      expect(find.text("Nada por aquí"), findsOneWidget);
    });
  });

  // ==========================================================================
  // Personas
  // ==========================================================================
  group("personas y roles", () {
    Future<void> montarPersonas(WidgetTester tester) => montar(
      tester,
      PantallaPanelUsuarios(
        repositorio: RepositorioPanel(cliente: cliente),
        sesion: Sesion(cliente: cliente),
      ),
    );

    Map<String, dynamic> persona({
      required String id,
      String rol = "alumno",
      String nombre = "Ana Quispe",
    }) => {
      "id": id,
      "nombre": nombre,
      "correo": "$nombre@ejemplo.test",
      "rol": rol,
      "plan": "gratis",
    };

    testWidgets("lista a las personas con su rol", (tester) async {
      espia.personas = [
        persona(id: _idOtro, nombre: "Ana"),
        persona(
          id: "33333333-3333-3333-3333-333333333333",
          nombre: "Beto",
          rol: "docente",
        ),
      ];
      await entrar();
      await montarPersonas(tester);

      expect(find.textContaining("Ana"), findsWidgets);
      expect(find.textContaining("Beto"), findsWidgets);
    });

    testWidgets("cambiar un rol manda el id y el rol nuevo", (tester) async {
      espia.personas = [persona(id: _idOtro)];
      await entrar();
      await montarPersonas(tester);

      await tester.tap(find.byType(DropdownButton<Rol>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text("docente").last);
      await asentar(tester);

      final envio = espia.ultimoEnvio("/rest/v1/rpc/cambiar_rol");
      expect(envio["p_perfil_id"], _idOtro);
      expect(envio["p_rol"], "docente");
    });

    testWidgets("«no puedes quitar el último admin» se lee tal cual", (
      tester,
    ) async {
      espia
        ..personas = [persona(id: _idOtro, rol: "admin")]
        ..errorAlCambiarRol = "No puedes quitar el último administrador";
      await entrar();
      await montarPersonas(tester);

      await tester.tap(find.byType(DropdownButton<Rol>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text("alumno").last);
      await asentar(tester);

      expect(
        find.textContaining("último administrador"),
        findsWidgets,
        reason:
            "es la única forma de que un admin entienda por qué el cambio no "
            "entró; un fallo genérico le haría pensar que es la red",
      );
    });

    testWidgets("una lista vacía no se lee como avería", (tester) async {
      await entrar();
      await montarPersonas(tester);

      expect(
        tester.takeException(),
        isNull,
        reason:
            "es lo que `personas_del_panel` le devuelve a un docente que no "
            "es admin",
      );
    });
  });
}
