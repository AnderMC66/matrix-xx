// `PantallaInicio`: la portada.
//
// Estaba al **0,5 % de cobertura**, y es la primera pantalla que ve todo el
// mundo al abrir la app. Lo que fija este archivo:
//
//   - **Sin cuenta se ve la portada entera**, con sus seis accesos y la
//     invitación a registrarse — no un muro ni un hueco.
//   - **Las cinco peticiones del panel personal salen a la vez.**
//   - **El aviso dirigido tiene umbrales, y no se inventa uno cualquiera**:
//     por debajo de 70 % de acierto y con 2 días o más sin tocar el curso.
//     Regañar a quien practicó ayer, o llamar «flojo» a un curso que va bien,
//     es peor que callarse.
//   - **Un fallo del panel se dice**, no se esconde: quien tiene sesión sabe
//     que su panel existe —lo vio ayer— y verlo desaparecer sin una palabra
//     se lee como que perdió la racha.
import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:matr_u/data/repositories/horario.dart";
import "package:matr_u/data/repositories/progreso.dart";
import "package:matr_u/data/repositories/repaso.dart";
import "package:matr_u/data/repositories/sesion.dart";
import "package:matr_u/ui/core/theme/tema.dart";
import "package:matr_u/ui/features/dashboard/view_models/inicio.dart";
import "package:matr_u/ui/features/dashboard/views/inicio.dart";
import "package:supabase/supabase.dart";

const _idPropio = "11111111-1111-1111-1111-111111111111";

class _ClienteEspia extends http.BaseClient {
  final peticiones = <(String metodo, Uri url, String cuerpo)>[];

  Map<String, dynamic> racha = const {
    "dias_actual": 3,
    "dias_maxima": 9,
    "estudiado_hoy": true,
  };

  Map<String, dynamic> resumenRepasos = const {
    "pendientes_hoy": 5,
    "proxima_fecha": "2026-09-18",
    "total_programados": 30,
  };

  List<Map<String, dynamic>> horario = [];
  List<Map<String, dynamic>> diagnostico = [];
  List<Map<String, dynamic>> desatendidos = [];

  bool fallaLaCarga = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest peticion) async {
    final enviado = peticion is http.Request ? peticion.body : "";
    peticiones.add((peticion.method, peticion.url, enviado));
    final ruta = peticion.url.path;

    if (ruta == "/auth/v1/token") return _r(peticion, jsonEncode(_sesion), 200);
    if (fallaLaCarga && ruta.startsWith("/rest/v1/")) return _fallo(peticion);

    return switch (ruta) {
      "/rest/v1/rpc/racha_estudio" => _r(peticion, jsonEncode([racha]), 200),
      "/rest/v1/rpc/resumen_repasos" => _r(
        peticion,
        jsonEncode([resumenRepasos]),
        200,
      ),
      "/rest/v1/horarios_estudio" => _r(peticion, jsonEncode(horario), 200),
      "/rest/v1/rpc/diagnostico_por_subtema" => _r(
        peticion,
        jsonEncode(diagnostico),
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

Map<String, dynamic> _curso({
  required String nombre,
  required int? porcentaje,
  required int dias,
}) => {
  "curso_codigo": "ALG",
  "curso_nombre": nombre,
  "curso_slug": "algebra",
  "respondidas": 12,
  "porcentaje": porcentaje,
  "dias_sin_practicar": dias,
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
    email: "ana@ejemplo.test",
    password: "da-igual",
  );

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: construirTema(),
        home: PantallaInicio(
          modelo: ModeloInicio(
            sesion: Sesion(cliente: cliente),
            progreso: RepositorioProgreso(cliente: cliente),
            repasos: RepositorioRepaso(cliente: cliente),
            horario: RepositorioHorario(cliente: cliente),
          ),
        ),
      ),
    );
    await asentar(tester);
  }

  group("sin cuenta", () {
    testWidgets("la portada se ve entera, con sus seis accesos", (
      tester,
    ) async {
      await montar(tester);

      expect(find.text("Matrix U"), findsOneWidget);
      expect(find.text("Practicar"), findsOneWidget);
      expect(find.text("Repaso"), findsOneWidget);
      expect(find.text("Adaptativa"), findsOneWidget);
      expect(find.text("Teoría"), findsOneWidget);
      expect(find.text("Simulacros"), findsOneWidget);
      expect(find.text("Buscar"), findsOneWidget);
    });

    testWidgets("invita a registrarse y no pide nada al servidor", (
      tester,
    ) async {
      await montar(tester);

      expect(find.textContaining("Crear cuenta o entrar"), findsOneWidget);
      expect(
        espia.peticiones.where((p) => p.$2.path.startsWith("/rest/")),
        isEmpty,
        reason: "sin sesión no hay panel personal que pedir",
      );
    });
  });

  group("con cuenta", () {
    testWidgets("las cinco peticiones salen a la vez", (tester) async {
      await entrar();
      espia.peticiones.clear();
      await montar(tester);

      for (final ruta in [
        "/rest/v1/rpc/diagnostico_por_subtema",
        "/rest/v1/rpc/racha_estudio",
        "/rest/v1/rpc/resumen_repasos",
        "/rest/v1/horarios_estudio",
        "/rest/v1/rpc/cursos_desatendidos",
      ]) {
        expect(
          espia.de(ruta),
          hasLength(1),
          reason: "$ruta no se pidió: encadenadas son cinco latencias sumadas",
        );
      }
    });

    testWidgets("la racha y los repasos aparecen en el panel", (tester) async {
      await entrar();
      await montar(tester);

      // La cifra y su etiqueta son dos `Text` distintos: el numero manda a
      // 38 px y la palabra solo lo clasifica. Antes iban en un `RichText`
      // unico, de ahi que estas aserciones cambiaran de forma — lo que se
      // comprueba sigue siendo lo mismo.
      expect(find.text("3"), findsOneWidget);
      expect(find.text("días seguidos"), findsOneWidget);
      expect(find.text("5"), findsOneWidget);
      expect(find.text("repasos para hoy"), findsOneWidget);
    });

    testWidgets("sin racha ni repasos no se pinta una caja vacía", (
      tester,
    ) async {
      espia.racha = const {
        "dias_actual": 0,
        "dias_maxima": 0,
        "estudiado_hoy": false,
      };
      espia.resumenRepasos = const {
        "pendientes_hoy": 0,
        "proxima_fecha": null,
        "total_programados": 0,
      };
      await entrar();
      await montar(tester);

      // Con las tres cifras a cero no se pinta ninguna: a quien abre la app
      // por primera vez, tres ceros en fila no le informan, le dicen que va
      // mal antes de haber empezado.
      expect(find.text("días seguidos"), findsNothing);
      expect(find.text("repasos para hoy"), findsNothing);
      // Pero la portada sigue completa.
      expect(find.text("Practicar"), findsOneWidget);
    });

    testWidgets("si el panel falla, se dice y hay «Reintentar»", (
      tester,
    ) async {
      espia.fallaLaCarga = true;
      await entrar();
      await montar(tester);

      expect(
        find.textContaining("No se pudo cargar tu panel"),
        findsOneWidget,
        reason:
            "callarse aquí se lee como que perdió la racha, no como que el "
            "servidor no contestó",
      );

      espia.fallaLaCarga = false;
      await tester.tap(find.widgetWithText(OutlinedButton, "Reintentar"));
      await asentar(tester);

      expect(find.textContaining("No se pudo cargar tu panel"), findsNothing);
    });
  });

  group("entrar con la portada ya abierta", () {
    testWidgets("la portada se entera y pide su panel", (tester) async {
      // `PantallaEntrar` se abre ENCIMA de la portada. Al cerrarse tras un
      // acceso correcto, la portada seguía pintando «Crear cuenta o entrar»
      // con la sesión ya iniciada: leía `hayCuenta` una vez, en `initState`.
      await montar(tester);
      expect(find.textContaining("Crear cuenta o entrar"), findsOneWidget);

      await entrar();
      await asentar(tester);

      expect(find.textContaining("Crear cuenta o entrar"), findsNothing);
      expect(
        espia.de("/rest/v1/rpc/racha_estudio"),
        hasLength(1),
        reason: "el panel es de quien acaba de entrar: hay que pedirlo",
      );
    });

    testWidgets("salir devuelve la portada sin panel", (tester) async {
      await entrar();
      await montar(tester);
      expect(find.text("días seguidos"), findsOneWidget);

      await cliente.auth.signOut();
      await asentar(tester);

      expect(find.textContaining("Crear cuenta o entrar"), findsOneWidget);
      expect(find.text("días seguidos"), findsNothing);
    });
  });

  group("el aviso de curso desatendido", () {
    testWidgets("aparece con un curso flojo que lleva días sin tocarse", (
      tester,
    ) async {
      espia.desatendidos = [_curso(nombre: "Álgebra", porcentaje: 41, dias: 6)];
      await entrar();
      await montar(tester);

      expect(
        find.textContaining("Álgebra", findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets("no regaña a quien practicó ayer", (tester) async {
      // Mismo 41 % de acierto, pero un solo día sin tocarlo.
      espia.desatendidos = [_curso(nombre: "Álgebra", porcentaje: 41, dias: 1)];
      await entrar();
      await montar(tester);

      expect(
        find.textContaining("Álgebra", findRichText: true),
        findsNothing,
        reason: "el umbral de 2 días existe justo para no dar la lata",
      );
    });

    testWidgets("no llama «flojo» a un curso que va bien", (tester) async {
      espia.desatendidos = [_curso(nombre: "Álgebra", porcentaje: 84, dias: 9)];
      await entrar();
      await montar(tester);

      expect(find.textContaining("Álgebra", findRichText: true), findsNothing);
    });

    testWidgets("un curso sin respuestas todavía no da porcentaje ni aviso", (
      tester,
    ) async {
      // `porcentaje` nulo significa «nunca tocado», no «flojo»: sin respuestas
      // no hay con qué medir, y el aviso diría una cifra inventada.
      espia.desatendidos = [
        _curso(nombre: "Álgebra", porcentaje: null, dias: 30),
      ];
      await entrar();
      await montar(tester);

      expect(find.textContaining("Álgebra", findRichText: true), findsNothing);
    });
  });
}
