// Comprueba la capa Supabase contra el proyecto REAL.
//
// Por qué existe: todo lo demás en `test/` es lógica local y se verifica sola.
// Los 11 RPC, en cambio, están escritos contra una lectura de las firmas SQL,
// no contra respuestas de verdad. Lo que este archivo confirma es lo único que
// no se puede deducir del esquema: **la forma en que llega cada respuesta** —
// si un `setof` de una fila aterriza como lista o ya desenvuelto, si un
// `bigint` llega como `int` o como texto, si `iniciar_simulacro` devuelve un
// escalar pelado.
//
// `flutter test` lo recoge como cualquier otro archivo, pero **se salta solo**
// si no hay credenciales: aparece como `~6` saltados y la suite sigue en
// verde. Es a propósito — un test que necesita red y una cuenta real no debe
// poder romper la suite de nadie, y menos en un portátil sin conexión.
//
// Correr (solo lectura, no escribe nada):
//
//   flutter test test/integracion/supabase_real_test.dart \
//     --dart-define-from-file=config/dev.json \
//     --dart-define=CORREO=tu@correo --dart-define=CONTRASENA=...
//
// Añadir `--dart-define=ESCRITURA=1` para ejercitar también lo que MODIFICA la
// base: responder una pregunta, abrir y cerrar un simulacro. Eso deja filas
// reales en `intentos` y `respuestas` de esa cuenta, y mueve su racha y su
// diagnóstico. Con una cuenta de prueba da igual; con la tuya de verdad,
// ensucia tus estadísticas. Por eso está detrás de una bandera.

// El informe es la salida de esta herramienta.
// ignore_for_file: avoid_print

import "package:flutter_test/flutter_test.dart";
import "package:supabase_flutter/supabase_flutter.dart";

import "package:matr_u/config.dart";
import "package:matr_u/datos/practica.dart";
import "package:matr_u/datos/preguntas.dart";
import "package:matr_u/datos/progreso.dart";
import "package:matr_u/datos/repaso.dart";
import "package:matr_u/datos/simulacro.dart";

const _correo = String.fromEnvironment("CORREO");
const _contrasena = String.fromEnvironment("CONTRASENA");
const _escritura = bool.fromEnvironment("ESCRITURA");

/// Describe la forma cruda de lo que devolvió un RPC.
///
/// Es el dato que este archivo existe para conseguir: no «funcionó», sino
/// «llegó como lista de mapas con estas claves y estos tipos».
String forma(dynamic v) {
  if (v == null) return "null";
  if (v is List) {
    if (v.isEmpty) return "List vacía";
    final primera = v.first;
    if (primera is Map) {
      final claves = primera.entries
          .map((e) => "${e.key}: ${e.value.runtimeType}")
          .join(", ");
      return "List<Map> (${v.length}) → {$claves}";
    }
    return "List<${primera.runtimeType}> (${v.length})";
  }
  if (v is Map) {
    return "Map → {${v.entries.map((e) => "${e.key}: ${e.value.runtimeType}").join(", ")}}";
  }
  return "${v.runtimeType} = $v";
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final faltaConfig = !Config.configurado;
  final faltanCredenciales = _correo.isEmpty || _contrasena.isEmpty;
  final saltar = faltaConfig
      ? "Falta la configuración de Supabase: añade "
            "--dart-define-from-file=config/dev.json"
      : faltanCredenciales
      ? "Faltan credenciales: añade --dart-define=CORREO=… "
            "--dart-define=CONTRASENA=…"
      : null;

  late SupabaseClient cliente;

  setUpAll(() async {
    if (saltar != null) return;
    await Supabase.initialize(
      url: Config.urlSupabase,
      publishableKey: Config.clavePublishable,
    );
    cliente = Supabase.instance.client;
    final r = await cliente.auth.signInWithPassword(
      email: _correo,
      password: _contrasena,
    );
    print("\nSesión iniciada como ${r.user?.email} (${r.user?.id})\n");
  });

  tearDownAll(() async {
    if (saltar != null) return;
    await Supabase.instance.client.auth.signOut();
  });

  group("formas crudas de cada RPC", skip: saltar, () {
    Future<void> mostrar(String nombre, Map<String, dynamic>? params) async {
      try {
        final v = await cliente.rpc(nombre, params: params);
        print("  $nombre\n      ${forma(v)}");
      } catch (e) {
        print("  $nombre\n      ERROR: $e");
        rethrow;
      }
    }

    test("solo lectura", () async {
      print("--- RPC de lectura ---");
      await mostrar("racha_estudio", null);
      await mostrar("resumen_repasos", null);
      await mostrar("diagnostico_por_subtema", null);
      await mostrar("repasos_pendientes", {"p_limite": 5});
      await mostrar("preguntas_falladas", null);
      await mostrar("preguntas_recomendadas", {"p_limite": 5});
      print("");
    });
  });

  group("los repositorios aceptan lo que llega", skip: saltar, () {
    test("Progreso: perfil, racha y diagnóstico", () async {
      final repo = RepositorioProgreso();

      final perfil = await repo.perfil();
      print("  perfil: ${perfil?.nombre} · rol ${perfil?.rol} "
          "· área ${perfil?.areaNombre} · staff ${perfil?.esStaff}");
      expect(
        perfil,
        isNotNull,
        reason: "Sin perfil, el disparador al_crear_usuario no corrió",
      );

      final racha = await repo.racha();
      print("  racha: ${racha?.diasActual} días "
          "(máx ${racha?.diasMaxima}, hoy ${racha?.estudiadoHoy})");

      final d = await repo.diagnostico();
      print("  diagnóstico: ${d.subtemas.length} subtemas · "
          "${d.aciertoGlobal} % global · ${d.respondidas} respondidas · "
          "${d.consolidados} dominados");
      // Si hay datos, los agregados tienen que ser coherentes entre sí.
      if (!d.vacio) {
        expect(d.correctas, lessThanOrEqualTo(d.respondidas));
        expect(d.aciertoGlobal, inInclusiveRange(0, 100));
        expect(d.prioridades.length, lessThanOrEqualTo(5));
      }

      final reportes = await repo.reportesResueltos();
      print("  reportes resueltos sin ver: ${reportes.length}");
    });

    test("Repaso: resumen y las dos listas", () async {
      final repo = RepositorioRepaso();

      final resumen = await repo.resumen();
      print("  resumen: ${resumen?.pendientesHoy} para hoy de "
          "${resumen?.totalProgramados} · próxima ${resumen?.proximaFecha}");

      final pendientes = await repo.pendientes(limite: 5);
      final falladas = await repo.falladas();
      final recomendadas = await repo.recomendadas(limite: 5);
      print("  pendientes: ${pendientes.length} · falladas: ${falladas.length}"
          " · recomendadas: ${recomendadas.length}");

      // El cruce contra el banco local es lo que puede fallar en silencio: si
      // los códigos que devuelve Postgres no coinciden con los del APK, estas
      // listas salen vacías sin ningún error.
      for (final p in [...pendientes, ...falladas, ...recomendadas]) {
        expect(p.codigo, isNotEmpty);
        expect(p.alternativas, hasLength(5));
      }
    });

    test("Simulacro: lista, intento y preguntas", () async {
      final repo = RepositorioSimulacro();

      final publicados = await repo.publicados();
      print("  simulacros publicados: ${publicados.length}");
      for (final s in publicados) {
        print("      #${s.id} ${s.nombre} · ${s.duracionMinutos} min");
      }
      expect(
        publicados,
        isNotEmpty,
        reason: "Sin simulacros publicados no se puede verificar el resto",
      );

      final enCurso = await repo.intentoEnCurso();
      print("  intento en curso: ${enCurso?.id ?? "ninguno"}");

      // `iniciado_en` es lo que alimenta el cronómetro: comprobar que llega en
      // UTC es el punto del ejercicio.
      if (enCurso != null) {
        print("      iniciado_en UTC: ${enCurso.iniciadoEn.isUtc} "
            "(${enCurso.iniciadoEn})");
        expect(enCurso.iniciadoEn.isUtc, isTrue);
        final preguntas = await repo.preguntasDe(enCurso);
        print("      preguntas resueltas contra el banco: ${preguntas.length}");
      }
    });
  });

  group(
    "lo que ESCRIBE en la base",
    skip: saltar ?? (_escritura ? null : "Añade --dart-define=ESCRITURA=1"),
    () {
      test("responder una pregunta de práctica", () async {
        final banco = await RepositorioPreguntas().cargar();
        final pregunta = banco.preguntas.first;
        final repo = RepositorioPractica();

        final c = await repo.responder(
          codigoPregunta: pregunta.codigo,
          marcada: Letra.a,
          segundos: 7,
        );
        print("  ${pregunta.codigo}: correcta=${c.esCorrecta} "
            "clave=${c.clave.etiqueta} "
            "explicación=${c.explicacion == null ? "no" : "sí"}");
        print("  intento creado: ${repo.intentoId}");

        expect(repo.intentoId, isNotNull);
        await repo.finalizar();
        print("  intento cerrado");
      });

      test("abrir y cerrar un simulacro", () async {
        final repo = RepositorioSimulacro();

        // No se abre uno nuevo si ya hay uno a medias: cerrarlo desde aquí
        // arruinaría un examen real en curso.
        final abierto = await repo.intentoEnCurso();
        if (abierto != null) {
          print("  hay un intento a medias (#${abierto.id}): no se toca");
          return;
        }

        final publicados = await repo.publicados();
        final id = await repo.iniciar(publicados.first.id);
        print("  iniciar_simulacro devolvió: $id (${id.runtimeType})");

        final intento = await repo.intento(id);
        expect(intento, isNotNull);
        expect(intento!.enCurso, isTrue);

        final preguntas = await repo.preguntasDe(intento);
        print("  preguntas del intento: ${preguntas.length}");
        expect(preguntas, isNotEmpty);

        await repo.responder(
          intentoId: id,
          preguntaId: preguntas.first.preguntaId,
          letra: Letra.a,
        );
        print("  respuesta guardada");

        await repo.finalizar(id);
        final cerrado = await repo.intento(id);
        print("  cerrado · puntaje ${cerrado?.puntaje} "
            "· ${cerrado?.correctas}/${cerrado?.totalPreguntas}");
        expect(cerrado!.enCurso, isFalse);

        final p = await repo.percentil(id);
        print("  percentil: ${p?.percentil} de ${p?.totalIntentos} intentos");

        final detalle = await repo.resultado(cerrado);
        print("  detalle: ${detalle.length} preguntas · "
            "${detalle.where((r) => r.sinResponder).length} sin responder");
        expect(detalle, isNotEmpty);
      });
    },
  );
}
