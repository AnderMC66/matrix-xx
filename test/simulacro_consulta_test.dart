// `intentoEnCurso()` buscaba «el intento de simulacro abierto más reciente que
// yo pueda ver», sin filtrar por dueño, confiando en RLS.
//
// **Y RLS no alcanzaba, porque la política de `intentos` deja ver «el dueño o
// un admin».** A un alumno le devolvía el suyo, correcto; a un docente o a un
// admin con un examen ajeno a medias en la base le devolvía EL DE OTRA
// PERSONA, y la tarjeta «Tienes un simulacro a medias» le ofrecía el botón
// «Retomar» para responderlo en su nombre. La diferencia con `intento(id)`,
// que sí puede apoyarse en RLS, es que aquella recibe un id concreto y solo
// pregunta «¿me dejas verlo?»: esta buscaba a ciegas, y buscar a ciegas con
// permisos amplios encuentra lo que no toca.
//
// Cómo se prueba sin tocar Supabase: `RepositorioSimulacro` acepta un
// `SupabaseClient` inyectado (la misma costura que usa el arnés de
// integración), y `SupabaseClient` acepta un `http.Client`. Con los dos se
// puede iniciar una sesión falsa y **leer la URL que la app construye de
// verdad** — que es exactamente lo que el fallo tenía mal. No hay red: el
// cliente falso responde de memoria.
import "dart:convert";

import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:matr_u/data/models/simulacro.dart";
import "package:supabase/supabase.dart";

const _idPropio = "11111111-1111-1111-1111-111111111111";
const _idAjeno = "99999999-9999-9999-9999-999999999999";

/// Cliente HTTP de mentira: apunta las peticiones y contesta lo mínimo.
///
/// Para `intentos` **aplica los filtros `eq.` de la URL**, igual que PostgREST.
/// Eso es lo que hace útil al test: modela un servidor donde RLS deja ver las
/// filas de otros (la política real: «el dueño o un admin»), así que la única
/// cosa que puede excluir un intento ajeno es que la app pida el filtro. Si no
/// lo pide, la fila ajena llega — que es exactamente lo que pasaba.
class _ClienteEspia extends http.BaseClient {
  final peticiones = <Uri>[];

  /// Las filas que el servidor tiene, antes de filtrar.
  List<Map<String, dynamic>> intentos = const [];

  List<Map<String, dynamic>> _filtrar(Uri url) => intentos.where((fila) {
    for (final MapEntry(key: columna, value: criterio)
        in url.queryParameters.entries) {
      if (!fila.containsKey(columna)) continue;
      final valor = fila[columna];
      final coincide = switch (criterio) {
        "is.null" => valor == null,
        // Lo que emite `.not("finalizado_en", "is", null)`.
        "not.is.null" => valor != null,
        _ when criterio.startsWith("eq.") => "$valor" == criterio.substring(3),
        _ => true,
      };
      if (!coincide) return false;
    }
    return true;
  }).toList();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest peticion) async {
    peticiones.add(peticion.url);
    final ruta = peticion.url.path;

    final cuerpo = switch (ruta) {
      // `signInWithPassword`: lo justo para que `currentUser` exista.
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
      "/rest/v1/intentos" => jsonEncode(_filtrar(peticion.url)),
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

/// La fila que Postgres devolvería para un intento abierto de simulacro.
Map<String, dynamic> _filaIntento({required int id, required String dueno}) => {
  "id": id,
  "perfil_id": dueno,
  "simulacro_id": 7,
  "iniciado_en": "2026-09-11T10:00:00+00:00",
  "finalizado_en": null,
  "puntaje": null,
  "total_preguntas": null,
  "correctas": null,
};

/// Un intento ya terminado, con su puntaje.
Map<String, dynamic> _filaCerrada({
  required int id,
  required String dueno,
  required String fin,
  double puntaje = 72,
}) => {
  "id": id,
  "perfil_id": dueno,
  "simulacro_id": 7,
  "iniciado_en": "2026-09-11T10:00:00+00:00",
  "finalizado_en": fin,
  "puntaje": puntaje,
  "total_preguntas": 50,
  "correctas": 36,
};

void main() {
  late _ClienteEspia espia;
  late SupabaseClient cliente;

  setUp(() async {
    espia = _ClienteEspia();
    cliente = SupabaseClient(
      "https://proyecto.supabase.co",
      "sb_publishable_de_mentira",
      httpClient: espia,
    );
    await cliente.auth.signInWithPassword(
      email: "alumno@ejemplo.test",
      password: "da-igual",
    );
    espia.peticiones.clear();
  });

  tearDown(() async => cliente.dispose());

  /// La URL de la consulta a `intentos`, ya decodificada.
  Uri consultaDeIntentos() => espia.peticiones.firstWhere(
    (u) => u.path == "/rest/v1/intentos",
    orElse: () => throw StateError("no se consultó `intentos`"),
  );

  test("la consulta restringe por perfil_id, no solo por modo", () async {
    espia.intentos = [_filaIntento(id: 1, dueno: _idPropio)];

    await RepositorioSimulacro(cliente: cliente).intentoEnCurso();

    final filtros = consultaDeIntentos().queryParameters;
    expect(
      filtros["perfil_id"],
      "eq.$_idPropio",
      reason:
          "sin este filtro, un admin recibe el intento abierto de otro alumno: "
          "la política de `intentos` deja ver «el dueño o un admin»",
    );
    // Los filtros que ya estaban siguen ahí: el arreglo añade, no sustituye.
    expect(filtros["modo"], "eq.simulacro");
    expect(filtros["finalizado_en"], "is.null");
  });

  test(
    "el intento abierto de OTRA persona no llega, ni siendo admin",
    () async {
      // El servidor tiene un único intento abierto y es de otro alumno — la
      // situación de un docente o admin, a quien RLS se lo deja ver. Con el
      // filtro, la consulta ni lo pide. Sin el filtro, esto devolvía el examen
      // ajeno y «Retomar» lo abría.
      espia.intentos = [_filaIntento(id: 500, dueno: _idAjeno)];

      final intento = await RepositorioSimulacro(cliente: cliente)
          .intentoEnCurso();

      expect(
        intento,
        isNull,
        reason: "se ofreció retomar el simulacro a medias de otra persona",
      );
    },
  );

  test("entre el propio y uno ajeno, elige el propio", () async {
    // El ajeno es más reciente: sin filtro, `order(iniciado_en desc).limit(1)`
    // se lo quedaba a él.
    espia.intentos = [
      _filaIntento(id: 500, dueno: _idAjeno),
      _filaIntento(id: 7, dueno: _idPropio),
    ];

    final intento = await RepositorioSimulacro(cliente: cliente)
        .intentoEnCurso();

    expect(intento?.id, 7);
  });

  test("un intento propio abierto se devuelve", () async {
    espia.intentos = [_filaIntento(id: 42, dueno: _idPropio)];

    final intento = await RepositorioSimulacro(cliente: cliente)
        .intentoEnCurso();

    expect(intento, isNotNull);
    expect(intento!.id, 42);
    expect(intento.enCurso, isTrue);
  });

  test("sin sesión no se consulta la tabla en absoluto", () async {
    await cliente.auth.signOut();
    espia.peticiones.clear();

    final intento = await RepositorioSimulacro(cliente: cliente)
        .intentoEnCurso();

    expect(intento, isNull);
    expect(
      espia.peticiones.where((u) => u.path == "/rest/v1/intentos"),
      isEmpty,
      reason: "la guarda de sesión va antes de armar la petición",
    );
  });

  // ── Historial ───────────────────────────────────────────────────────────
  //
  // Un simulacro terminado era inalcanzable para siempre: el resultado se veía
  // una vez, al acabar, y el puntaje, el percentil y el desglose por curso se
  // quedaban en Postgres sin que ninguna pantalla los leyera.

  test("el historial pide solo los intentos CERRADOS y propios", () async {
    espia.intentos = [
      _filaCerrada(id: 1, dueno: _idPropio, fin: "2026-09-12T11:00:00+00:00"),
    ];

    await RepositorioSimulacro(cliente: cliente).historial();

    final filtros = consultaDeIntentos().queryParameters;
    expect(filtros["perfil_id"], "eq.$_idPropio");
    expect(filtros["modo"], "eq.simulacro");
    expect(
      filtros["finalizado_en"],
      "not.is.null",
      reason: "sin esto entraría también el examen que está a medias",
    );
  });

  test("un intento a medias no aparece en el historial", () async {
    espia.intentos = [
      _filaIntento(id: 9, dueno: _idPropio), // finalizado_en == null
      _filaCerrada(id: 1, dueno: _idPropio, fin: "2026-09-12T11:00:00+00:00"),
    ];

    final lista = await RepositorioSimulacro(cliente: cliente).historial();

    expect(lista.map((i) => i.id), [1]);
    expect(lista.single.enCurso, isFalse);
  });

  test("el historial de otra persona no llega", () async {
    espia.intentos = [
      _filaCerrada(id: 500, dueno: _idAjeno, fin: "2026-09-13T11:00:00+00:00"),
    ];

    expect(
      await RepositorioSimulacro(cliente: cliente).historial(),
      isEmpty,
      reason: "la política de `intentos` deja ver también al admin",
    );
  });

  test("el puntaje y el recuento llegan enteros", () async {
    espia.intentos = [
      _filaCerrada(
        id: 3,
        dueno: _idPropio,
        fin: "2026-09-12T11:00:00+00:00",
        puntaje: 72,
      ),
    ];

    final i = (await RepositorioSimulacro(cliente: cliente).historial()).single;

    expect(i.puntaje, 72);
    expect(i.correctas, 36);
    expect(i.totalPreguntas, 50);
    expect(i.finalizadoEn!.isUtc, isTrue);
  });

  test("sin sesión el historial es vacío y no consulta nada", () async {
    await cliente.auth.signOut();
    espia.peticiones.clear();

    expect(await RepositorioSimulacro(cliente: cliente).historial(), isEmpty);
    expect(
      espia.peticiones.where((u) => u.path == "/rest/v1/intentos"),
      isEmpty,
    );
  });

  test("iniciado_en llega como UTC aunque el texto traiga offset", () async {
    // Lo que sostiene el cronómetro del examen: 5 horas de error en Perú
    // (UTC-5) serían un plazo agotado nada más empezar, o al revés.
    espia.intentos = [_filaIntento(id: 1, dueno: _idPropio)];

    final intento = await RepositorioSimulacro(cliente: cliente)
        .intentoEnCurso();

    expect(intento!.iniciadoEn.isUtc, isTrue);
    expect(intento.iniciadoEn, DateTime.utc(2026, 9, 11, 10));
  });
}
