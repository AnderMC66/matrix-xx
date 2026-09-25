// `PantallaProgreso`: perfil, racha, repasos, próximo bloque, diagnóstico y
// reportes resueltos.
//
// Estaba al **0,9 % de cobertura**, y es la pantalla con más piezas de la app.
// Lo que fija este archivo no está cubierto por `datos/`, porque es cableado
// de pantalla:
//
//   - **Las seis peticiones salen a la vez.** Seis `await` en fila eran seis
//     latencias sumadas cada vez que se abre Progreso, con datos móviles.
//   - **El enlace al panel aparece solo para staff**, y el del horario
//     siempre — las dos cosas que LEEME.md daba por no portadas hasta la
//     auditoría del 2026-09-16.
//   - **Un usuario sin perfil se señala**, no se disimula: significa que el
//     disparador `al_crear_usuario` no corrió, y callarlo deja a alguien con
//     una cuenta a medias sin saberlo.
//   - Que el acuse de «reportes vistos» no tumbe la pantalla si falla la red.
import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:matr_u/data/repositories/horario.dart";
import "package:matr_u/data/repositories/progreso.dart";
import "package:matr_u/data/repositories/repaso.dart";
import "package:matr_u/data/repositories/sesion.dart";
import "package:matr_u/ui/core/theme/tema.dart";
import "package:matr_u/ui/features/dashboard/views/progreso.dart";
import "package:supabase/supabase.dart";

const _idPropio = "11111111-1111-1111-1111-111111111111";

class _ClienteEspia extends http.BaseClient {
  final peticiones = <(String metodo, Uri url, String cuerpo)>[];

  /// `null` = el usuario existe pero no tiene fila en `perfiles`.
  Map<String, dynamic>? perfil = {
    "nombre": "Ana Quispe",
    "rol": "alumno",
    "plan": "gratis",
    "creditos": 0,
    "creado_en": "2026-03-02T15:00:00+00:00",
    "areas_postulacion": {"nombre": "Ingenierías"},
  };

  Map<String, dynamic> racha = const {
    "dias_actual": 4,
    "dias_maxima": 11,
    "estudiado_hoy": false,
  };

  Map<String, dynamic> resumenRepasos = const {
    "pendientes_hoy": 6,
    "proxima_fecha": "2026-09-18",
    "total_programados": 40,
  };

  List<Map<String, dynamic>> horario = [];
  List<Map<String, dynamic>> diagnostico = [];
  List<Map<String, dynamic>> reportes = [];

  bool fallaLaCarga = false;
  bool fallaElAcuse = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest peticion) async {
    final enviado = peticion is http.Request ? peticion.body : "";
    peticiones.add((peticion.method, peticion.url, enviado));
    final ruta = peticion.url.path;

    if (ruta == "/auth/v1/token") return _r(peticion, jsonEncode(_sesion), 200);
    if (fallaLaCarga && ruta.startsWith("/rest/v1/")) return _fallo(peticion);

    return switch (ruta) {
      "/rest/v1/perfiles" => _r(peticion, jsonEncode(perfil), 200),
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
      "/rest/v1/reportes_error" => _r(peticion, jsonEncode(reportes), 200),
      "/rest/v1/rpc/marcar_reportes_vistos" =>
        fallaElAcuse ? _fallo(peticion) : _r(peticion, "null", 200),
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

Map<String, dynamic> _subtema({
  required String codigo,
  required String nombre,
  required String curso,
  required int respondidas,
  required int correctas,
}) => {
  "subtema_id": codigo.hashCode.abs() % 10000,
  "subtema_codigo": codigo,
  "subtema_nombre": nombre,
  "tema_nombre": "Un tema",
  "curso_nombre": curso,
  "respondidas": respondidas,
  "correctas": correctas,
  "porcentaje": respondidas == 0 ? 0 : correctas * 100 / respondidas,
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
    // Alta a propósito: Progreso es un `ListView` largo y sus hijos se
    // construyen según lo que cabe. Ver la nota de `panel_pantalla_test.dart`.
    tester.view.physicalSize = const Size(1000, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: construirTema(),
        home: Scaffold(
          body: PantallaProgreso(
            progreso: RepositorioProgreso(cliente: cliente),
            repasos: RepositorioRepaso(cliente: cliente),
            horario: RepositorioHorario(cliente: cliente),
            sesion: Sesion(cliente: cliente),
          ),
        ),
      ),
    );
    await asentar(tester);
  }

  testWidgets("sin sesión pide la cuenta y no consulta nada", (tester) async {
    await montar(tester);

    expect(
      find.textContaining("Tu progreso necesita tu cuenta"),
      findsOneWidget,
    );
    expect(
      espia.peticiones.where((p) => p.$2.path.startsWith("/rest/")),
      isEmpty,
    );
  });

  testWidgets("las seis peticiones salen a la vez, no una detrás de otra", (
    tester,
  ) async {
    await entrar();
    espia.peticiones.clear();
    await montar(tester);

    for (final ruta in [
      "/rest/v1/perfiles",
      "/rest/v1/rpc/racha_estudio",
      "/rest/v1/rpc/resumen_repasos",
      "/rest/v1/horarios_estudio",
      "/rest/v1/rpc/diagnostico_por_subtema",
      "/rest/v1/reportes_error",
    ]) {
      expect(
        espia.de(ruta),
        hasLength(1),
        reason:
            "$ruta no se pidió: encadenadas, seis latencias se suman cada vez "
            "que se abre Progreso con datos móviles",
      );
    }
  });

  testWidgets("pinta el perfil y la racha", (tester) async {
    await entrar();
    await montar(tester);

    expect(find.text("Ana Quispe"), findsOneWidget);
    expect(find.text("ana@ejemplo.test"), findsOneWidget);
    // Las etiquetas del perfil («Área Ingenierías», «Plan gratis»…) son
    // `RichText` de dos tramos, así que `find.text` no las ve: se buscan con
    // `findRichText`, que sí mira dentro.
    expect(
      find.textContaining("Ingenierías", findRichText: true),
      findsOneWidget,
    );
    // La tarjeta de racha pinta la cifra y la unidad en dos `Text` aparte,
    // para que el número pueda ir a 32 px y la palabra a 12,5.
    expect(find.text("4"), findsOneWidget);
    expect(find.text("días"), findsOneWidget);
    expect(
      find.textContaining("Todavía no estudias hoy"),
      findsOneWidget,
      reason:
          "`estudiado_hoy` es `false`: sin ese recordatorio la racha parece "
          "ya asegurada y no invita a estudiar hoy también",
    );
  });

  testWidgets("la fecha de alta se cuenta en hora local", (tester) async {
    // 2026-03-02T15:00Z. Lo que se fija es que el mes salga del `DateTime`
    // local y no de un instante UTC leído como si fuera de aquí — el fallo
    // que tenían esta pantalla y la de reportes hasta la auditoría del
    // 2026-09-16. Se compara contra el local calculado, no contra una cadena
    // fija, para que la suite pase igual en Arequipa y en un CI en UTC.
    await entrar();
    await montar(tester);

    final esperado = DateTime.parse("2026-03-02T15:00:00+00:00").toLocal();
    const meses = [
      "ene",
      "feb",
      "mar",
      "abr",
      "may",
      "jun",
      "jul",
      "ago",
      "sep",
      "oct",
      "nov",
      "dic",
    ];
    expect(
      find.textContaining(
        "Desde ${meses[esperado.month - 1]} ${esperado.year}",
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets("un usuario sin perfil se señala, no se disimula", (
    tester,
  ) async {
    espia.perfil = null;
    await entrar();
    await montar(tester);

    expect(
      find.textContaining("al_crear_usuario"),
      findsOneWidget,
      reason:
          "sin el aviso, alguien con la cuenta a medias no tiene forma de "
          "saber por qué nada se le guarda",
    );
  });

  group("enlaces a otras pantallas", () {
    testWidgets("el horario se ofrece siempre", (tester) async {
      await entrar();
      await montar(tester);

      expect(find.textContaining("Programar un bloque"), findsOneWidget);
    });

    testWidgets("el panel solo aparece para staff", (tester) async {
      await entrar();
      await montar(tester);
      expect(find.textContaining("Panel de"), findsNothing);
    });

    testWidgets("un docente sí ve el enlace al panel", (tester) async {
      espia.perfil = {...espia.perfil!, "rol": "docente"};
      await entrar();
      await montar(tester);

      expect(
        find.textContaining("Panel de"),
        findsOneWidget,
        reason:
            "LEEME.md daba esto por no portado hasta la auditoría; lo está, "
            "y abre `PantallaPanel` de verdad",
      );
    });
  });

  group("diagnóstico", () {
    testWidgets("sin respuestas todavía, lo dice", (tester) async {
      await entrar();
      await montar(tester);

      expect(find.text("Tu diagnóstico está vacío"), findsOneWidget);
    });

    testWidgets("el acierto global sale del crudo, no del promedio", (
      tester,
    ) async {
      // 1 de 2 (50 %) y 36 de 40 (90 %). El promedio de porcentajes daría
      // 70 %; el crudo, 37 de 42 = 88 %. Con volúmenes distintos son cifras
      // muy diferentes, y la web usa el crudo.
      espia.diagnostico = [
        _subtema(
          codigo: "ALG-01-01",
          nombre: "Conjuntos",
          curso: "Álgebra",
          respondidas: 2,
          correctas: 1,
        ),
        _subtema(
          codigo: "BIO-01-01",
          nombre: "La célula",
          curso: "Biología",
          respondidas: 40,
          correctas: 36,
        ),
      ];
      await entrar();
      await montar(tester);

      expect(find.text("88 %"), findsOneWidget);
      expect(
        find.text("70 %"),
        findsNothing,
        reason: "eso sería el promedio de porcentajes, no el acierto real",
      );
    });
  });

  group("reportes resueltos", () {
    setUp(() {
      espia.reportes = [
        {
          "id": 3,
          "motivo": "Clave incorrecta",
          "estado": "aceptado",
          "resuelto_en": "2026-09-12T10:00:00+00:00",
          "preguntas": {"codigo_externo": "QUI-2027-014"},
        },
      ];
    });

    testWidgets("se muestran cuando el docente ya los revisó", (tester) async {
      await entrar();
      await montar(tester);

      expect(find.textContaining("Clave incorrecta"), findsOneWidget);
    });

    testWidgets("si el acuse falla, la pantalla no se rompe", (tester) async {
      espia.fallaElAcuse = true;
      await entrar();
      await montar(tester);

      await tester.tap(find.textContaining("Entendido"));
      await asentar(tester);

      expect(
        tester.takeException(),
        isNull,
        reason:
            "sin el `catch`, un fallo de red aquí sale como excepción sin "
            "capturar desde un `onPressed`",
      );
      // Y el aviso sigue ahí: no se marcó nada, así que volverá a aparecer.
      expect(find.textContaining("Clave incorrecta"), findsOneWidget);
    });
  });

  testWidgets("si la carga falla, hay aviso y «Reintentar»", (tester) async {
    espia.fallaLaCarga = true;
    await entrar();
    await montar(tester);

    expect(
      find.textContaining("No se pudo cargar tu progreso"),
      findsOneWidget,
    );

    espia.fallaLaCarga = false;
    await tester.tap(find.widgetWithText(OutlinedButton, "Reintentar"));
    await asentar(tester);

    expect(find.text("Ana Quispe"), findsOneWidget);
  });
}
