// `SesionPractica`, la tanda de preguntas.
//
// Segunda pantalla que acepta su repositorio inyectado, por el mismo motivo
// que `PantallaHorario`: `RepositorioPractica()` y `Sesion()` resuelven
// `Supabase.instance.client` en el constructor, así que montarla en un test
// lanzaba «You must initialize the supabase instance» antes de pintar nada.
//
// Lo que se prueba es la mitad que vive en la pantalla y no en el repositorio
// —que ya tiene el suyo en `practica_consulta_test.dart`—, y sobre todo el
// fallo que nadie veía: **salir a mitad de tanda dejaba el intento abierto**.
// `finalizar()` solo se llamaba al pasar de la última pregunta, que es la
// forma menos frecuente de terminar una práctica; lo normal es responder unas
// cuantas y volver atrás. Cada abandono dejaba una fila en `intentos` sin
// cerrar, sin totales y sin que ninguna pantalla lo delatara.
import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:matr_u/data/repositories/practica.dart";
import "package:matr_u/data/repositories/sesion.dart";
import "package:matr_u/domain/models/preguntas.dart";
import "package:matr_u/ui/core/theme/tema.dart";
import "package:matr_u/ui/features/practice/views/practica.dart";
import "package:supabase/supabase.dart";

const _idPropio = "11111111-1111-1111-1111-111111111111";

class _ClienteEspia extends http.BaseClient {
  final peticiones = <(String metodo, Uri url, String cuerpo)>[];

  /// Lo que devuelve `responder_pregunta`.
  Object? correccion = [
    {"es_correcta": true, "clave": "C", "explicacion_md": "Porque sí."},
  ];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest peticion) async {
    final enviado = peticion is http.Request ? peticion.body : "";
    peticiones.add((peticion.method, peticion.url, enviado));
    final ruta = peticion.url.path;

    if (ruta == "/auth/v1/token") return _r(peticion, jsonEncode(_sesion), 200);
    if (ruta == "/rest/v1/preguntas") {
      return _r(peticion, jsonEncode({"id": 900}), 200);
    }
    if (ruta == "/rest/v1/intentos") {
      return _r(peticion, jsonEncode({"id": 42}), 200);
    }
    if (ruta == "/rest/v1/rpc/responder_pregunta") {
      return _r(peticion, jsonEncode(correccion), 200);
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

/// Preguntas de mentira: la pantalla solo necesita enunciado y alternativas.
/// Ninguna trae `clave` porque el tipo no la tiene — es la invariante que
/// sostiene el diseño del banco, no un atajo del test.
List<Pregunta> _preguntas(int cuantas) => [
  for (var i = 1; i <= cuantas; i++)
    Pregunta(
      codigo: "QUI-2027-${i.toString().padLeft(3, "0")}",
      enunciado: "Enunciado número $i",
      imagen: null,
      dificultad: Dificultad.medio,
      alternativas: [
        for (final l in letras)
          Alternativa(letra: l, texto: "Opción ${l.etiqueta}", imagen: null),
      ],
      subtemaCodigo: "QUI-01-01",
      subtemaNombre: "Materia",
      temaNombre: "Química general",
      cursoNombre: "Química",
      cursoSlug: "quimica",
    ),
];

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
    email: "alumno@ejemplo.test",
    password: "da-igual",
  );

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  /// La tanda dentro de un `Navigator` de verdad, para poder salir de ella
  /// con un `pop` real y que `dispose` corra como corre en la app.
  Future<void> montar(WidgetTester tester, {int cuantas = 3}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: construirTema(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SesionPractica(
                      titulo: "Química",
                      preguntas: _preguntas(cuantas),
                      repositorio: RepositorioPractica(cliente: cliente),
                      sesion: Sesion(cliente: cliente),
                    ),
                  ),
                ),
                child: const Text("Abrir la tanda"),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text("Abrir la tanda"));
    await tester.pumpAndSettle();
  }

  /// Responde la pregunta en pantalla y espera la corrección.
  ///
  /// Se pulsa el círculo de la letra y no el texto de la alternativa: el
  /// texto lo pinta `TextoConFormulas`, que es un `RichText`, y `find.text`
  /// solo encuentra `Text`. El círculo sí lo es, y está dentro del mismo
  /// `InkWell`, así que el toque llega igual.
  Future<void> responder(WidgetTester tester) async {
    await tester.tap(find.text("C"));
    await asentar(tester);
    await tester.tap(find.text("Comprobar"));
    await asentar(tester);
  }

  testWidgets("la tanda arranca en la primera pregunta", (tester) async {
    await entrar();
    await montar(tester);

    expect(find.text("1 de 3"), findsOneWidget);
    expect(find.text("Comprobar"), findsOneWidget);
    expect(
      espia.de("/rest/v1/intentos"),
      isEmpty,
      reason: "abrir la tanda y no responder no debe crear un intento",
    );
  });

  testWidgets("salir a mitad de tanda CIERRA el intento", (tester) async {
    await entrar();
    await montar(tester);

    await responder(tester);
    expect(
      espia.de("/rest/v1/intentos"),
      hasLength(1),
      reason: "la primera respuesta es la que abre el intento",
    );

    // El alumno vuelve atrás sin llegar a la última pregunta: el gesto más
    // común de todos.
    final navegador = tester.state<NavigatorState>(find.byType(Navigator));
    navegador.pop();
    await tester.pumpAndSettle();

    expect(
      espia.de("/rest/v1/rpc/finalizar_intento"),
      hasLength(1),
      reason:
          "el intento se quedaba abierto para siempre: nadie lo vuelve a "
          "tocar, porque la siguiente tanda construye otro repositorio",
    );
  });

  testWidgets("salir sin responder nada no llama a finalizar", (tester) async {
    await entrar();
    await montar(tester);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    expect(
      espia.de("/rest/v1/rpc/finalizar_intento"),
      isEmpty,
      reason: "sin intento no hay nada que cerrar, y menos una petición",
    );
  });

  testWidgets("terminar la tanda la cierra UNA vez, no dos", (tester) async {
    await entrar();
    await montar(tester, cuantas: 1);

    await responder(tester);
    await tester.tap(find.text("Ver resumen"));
    await tester.pumpAndSettle();

    expect(find.text("1 de 1 correctas"), findsOneWidget);
    expect(espia.de("/rest/v1/rpc/finalizar_intento"), hasLength(1));

    // Y al salir del resumen tampoco se repite: `finalizar()` dejó el intento
    // en `null`, así que el `dispose` no tiene nada que cerrar.
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    expect(espia.de("/rest/v1/rpc/finalizar_intento"), hasLength(1));
  });

  testWidgets("sin sesión no corrige y lo dice claro", (tester) async {
    await montar(tester);
    await responder(tester);

    expect(
      find.textContaining("Entra a tu cuenta para practicar"),
      findsWidgets,
    );
    expect(
      espia.de("/rest/v1/rpc/responder_pregunta"),
      isEmpty,
      reason: "la clave la tiene el servidor: sin cuenta no hay corrección",
    );
  });

  testWidgets("un nombre de subtema largo no desborda la cabecera", (
    tester,
  ) async {
    // Salio en el movil: «Figuras literarias: metafora, simil, hiperbole,
    // anafora e hiperbaton» saco la franja amarilla de desborde y pego el
    // «3 de 28» al nombre. El `Text` llevaba `ellipsis`, pero suelto en un
    // `Row` no tiene ancho que respetar y toma el suyo intrinseco.
    tester.view
      ..physicalSize = const Size(960, 1704) // 320x568 a x3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final larga = _preguntas(1).map((p) => Pregunta(
      codigo: p.codigo,
      enunciado: p.enunciado,
      imagen: null,
      dificultad: p.dificultad,
      alternativas: p.alternativas,
      subtemaCodigo: p.subtemaCodigo,
      subtemaNombre:
          "Figuras literarias: metáfora, símil, hipérbole, anáfora e "
          "hipérbaton",
      temaNombre: p.temaNombre,
      cursoNombre: p.cursoNombre,
      cursoSlug: p.cursoSlug,
    )).toList();

    await tester.pumpWidget(
      MaterialApp(
        theme: construirTema(),
        home: SesionPractica(
          titulo: "Literatura",
          preguntas: larga,
          repositorio: RepositorioPractica(cliente: cliente),
          sesion: Sesion(cliente: cliente),
        ),
      ),
    );
    await asentar(tester);

    // Flutter reporta el desborde como excepcion del arbol: sin recogerla el
    // test pasa y el recuadro amarillo solo lo ve quien abre la app.
    expect(tester.takeException(), isNull);
  });
}
