// `PantallaHorario`, la primera pantalla de servidor con tests.
//
// Estaba al **1 % de cobertura**, y no por difícil: por construir su
// repositorio y su sesión dentro del estado. `RepositorioHorario()` y
// `Sesion()` resuelven `Supabase.instance.client` en el constructor, así que
// montar el widget en un test lanzaba «You must initialize the supabase
// instance» antes de pintar nada. Medida la cobertura del proyecto, ese
// patrón es justo la frontera entre el 95 % de `datos/` y el 1 % de
// `pantallas/`. Ahora los acepta inyectados.
//
// Lo que se prueba aquí es la mitad que vive en la pantalla, no en el
// repositorio: que el bloque recién creado entre en la lista con el id que
// devolvió Postgres —el bug de los ids negativos tenía una mitad a cada
// lado—, que borrar lo quite, y que un fallo de carga tenga salida.
import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:matr_u/datos/horario.dart";
import "package:matr_u/datos/sesion.dart";
import "package:matr_u/datos/temario.dart";
import "package:matr_u/pantallas/horario.dart";
import "package:matr_u/tema.dart";
import "package:supabase/supabase.dart";

const _idPropio = "11111111-1111-1111-1111-111111111111";

class _ClienteEspia extends http.BaseClient {
  final peticiones = <(String metodo, Uri url, String cuerpo)>[];

  /// Los bloques que devuelve `GET /horarios_estudio`.
  List<Map<String, dynamic>> bloques = [];

  /// El id que Postgres asigna al insertar.
  int idNuevo = 501;

  /// Si se pone, toda lectura de `horarios_estudio` falla.
  bool fallaLaCarga = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest peticion) async {
    final enviado = peticion is http.Request ? peticion.body : "";
    peticiones.add((peticion.method, peticion.url, enviado));
    final ruta = peticion.url.path;

    if (ruta == "/auth/v1/token") return _r(peticion, jsonEncode(_sesion), 200);
    if (ruta == "/rest/v1/cursos") {
      return _r(peticion, jsonEncode({"id": 5}), 200);
    }

    if (ruta == "/rest/v1/horarios_estudio") {
      if (fallaLaCarga && peticion.method == "GET") {
        return _r(
          peticion,
          jsonEncode({
            "code": "PGRST000",
            "message": "sin conexión",
            "details": null,
            "hint": null,
          }),
          500,
        );
      }
      if (peticion.method == "POST") {
        return _r(peticion, jsonEncode({"id": idNuevo}), 200);
      }
      return _r(peticion, jsonEncode(bloques), 200);
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

  Iterable<(String, Uri, String)> get borrados =>
      peticiones.where((p) => p.$1 == "DELETE");
}

/// Un bloque tal como lo devuelve la consulta, con su curso anidado.
Map<String, dynamic> _bloque({
  required int id,
  int dia = 1,
  String hora = "17:00:00",
}) => {
  "id": id,
  "dia_semana": dia,
  "hora_inicio": hora,
  "duracion_minutos": 60,
  "cursos": {"codigo": "ALG", "nombre": "Álgebra", "slug": "algebra"},
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
    email: "alumno@ejemplo.test",
    password: "da-igual",
  );

  /// Varias vueltas cortas, NO `pumpAndSettle`.
  ///
  /// La pantalla arranca un `Timer.periodic` de 30 s para avisar del próximo
  /// bloque, y `pumpAndSettle` espera a que no queden temporizadores: con uno
  /// periódico, nunca termina. Unas cuantas vueltas bastan para que se
  /// resuelvan el temario y la consulta.
  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  /// El temario se lee de los assets: hay que calentarlo fuera del reloj
  /// falso. Ver la nota larga de `desborde_test.dart`.
  Future<void> montar(WidgetTester tester) async {
    await tester.runAsync(() => RepositorioTemario().cargar());
    await tester.pumpWidget(
      MaterialApp(
        theme: construirTema(),
        home: Scaffold(
          body: PantallaHorario(
            repositorio: RepositorioHorario(cliente: cliente),
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
      find.textContaining("El horario necesita tu cuenta"),
      findsOneWidget,
    );
    expect(
      espia.peticiones.where((p) => p.$2.path.contains("horarios_estudio")),
      isEmpty,
    );
  });

  testWidgets("sin bloques, lo dice y ofrece el formulario", (tester) async {
    await entrar();
    await montar(tester);

    expect(
      find.textContaining("Todavía no programaste ningún bloque"),
      findsOneWidget,
    );
    expect(find.text("Agregar al horario"), findsOneWidget);
  });

  testWidgets("los bloques existentes se agrupan por día", (tester) async {
    espia.bloques = [
      _bloque(id: 1, dia: 1, hora: "17:00:00"),
      _bloque(id: 2, dia: 3, hora: "08:30:00"),
    ];
    await entrar();
    await montar(tester);

    // La cabecera de cada día va en mayúsculas; «Lunes» en minúscula es el
    // desplegable del formulario, no la lista.
    expect(find.text("LUNES"), findsOneWidget);
    expect(find.text("MIÉRCOLES"), findsOneWidget);
    expect(find.text("Álgebra"), findsNWidgets(2));
    // `formatearHora` convierte el 24h de Postgres.
    expect(find.textContaining("5:00 p. m."), findsOneWidget);
    expect(find.textContaining("8:30 a. m."), findsOneWidget);
  });

  testWidgets("un bloque nuevo entra en la lista con el id de Postgres", (
    tester,
  ) async {
    // Es la mitad del bug de los ids inventados que vivía en la pantalla: si
    // vuelve a inventarse uno, el borrado de abajo dejaría de mandar `eq.501`.
    espia.idNuevo = 501;
    await entrar();
    await montar(tester);

    // El formulario arranca con el primer curso del temario, que es
    // Razonamiento Matemático: es lo que aparecerá en la lista.
    await tester.tap(find.text("Agregar al horario"));
    await asentar(tester);

    expect(find.text("Razonamiento Matemático"), findsNWidgets(2));

    await tester.tap(find.text("Quitar"));
    await asentar(tester);

    expect(espia.borrados, hasLength(1));
    expect(
      espia.borrados.first.$2.queryParameters["id"],
      "eq.501",
      reason:
          "el delete fue contra otro id: la pantalla volvió a inventarse uno "
          "y el bloque se quedaría en la base",
    );
    // Solo queda el del desplegable del formulario.
    expect(find.text("Razonamiento Matemático"), findsOneWidget);
  });

  testWidgets("si la carga falla, hay aviso y salida", (tester) async {
    espia.fallaLaCarga = true;
    await entrar();
    await montar(tester);

    expect(find.textContaining("No se pudo cargar el horario"), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, "Reintentar"),
      findsOneWidget,
      reason:
          "sin «Reintentar», la única salida de un fallo de red era salir de "
          "la pantalla y volver a entrar",
    );
  });

  testWidgets("«Reintentar» vuelve a pedirlo, y si va bien pinta la lista", (
    tester,
  ) async {
    espia.fallaLaCarga = true;
    await entrar();
    await montar(tester);
    expect(find.textContaining("No se pudo cargar"), findsOneWidget);

    espia.fallaLaCarga = false;
    espia.bloques = [_bloque(id: 9, dia: 5)];

    await tester.tap(find.widgetWithText(OutlinedButton, "Reintentar"));
    await asentar(tester);

    expect(find.textContaining("No se pudo cargar"), findsNothing);
    expect(find.text("VIERNES"), findsOneWidget);
  });
}
