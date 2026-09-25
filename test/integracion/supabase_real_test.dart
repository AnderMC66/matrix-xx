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
// **Usa `package:test`, no `flutter_test`, y el paquete base `supabase`, no
// `supabase_flutter`.** No es un detalle de estilo: `flutter_test` corre con
// `TestWidgetsFlutterBinding`, que intercepta todo `HttpClient` y fuerza 400
// en cada petición —protección deliberada del framework contra que un widget
// test dispare red por accidente—, así que con ese binding esto no podía
// funcionar nunca, sin importar las credenciales. `Supabase.initialize()` de
// `supabase_flutter` tampoco sirve fuera de una app real: usa
// `shared_preferences` para persistir sesión, que necesita un canal de
// plataforma que no existe en un proceso de test. Todos los repositorios de
// `lib/datos/` aceptan un `SupabaseClient` inyectado (el mismo tipo en
// ambos paquetes) precisamente para poder darles este cliente de red pura.
//
// `flutter test` lo recoge como cualquier otro archivo, pero **se salta solo**
// si no hay credenciales: aparece como omitido, no como fallo, así que un
// `flutter test` normal nunca depende de él.
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
// ensucia tus estadísticas. Por eso está detrás de una bandera — y por eso
// ese bloque, que sí necesita leer `assets/datos/preguntas` a través de
// `RepositorioPreguntas`, solo se activa junto con la bandera: sin el
// binding de Flutter, `rootBundle` no puede leer assets, así que la
// escritura real de esta suite se corre aparte, no aquí.
//
// ignore_for_file: avoid_print
import "package:matr_u/core/config/config.dart";
import "package:matr_u/data/models/practica.dart";
import "package:matr_u/data/models/preguntas.dart" show EtiquetaLetra, Letra;
import "package:matr_u/data/models/progreso.dart";
import "package:matr_u/data/models/repaso.dart";
import "package:matr_u/data/models/simulacro.dart";
import "package:supabase/supabase.dart";
import "package:test/test.dart";

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
    cliente = SupabaseClient(Config.urlSupabase, Config.clavePublishable);
    final r = await cliente.auth.signInWithPassword(
      email: _correo,
      password: _contrasena,
    );
    print("\nSesión iniciada como ${r.user?.email} (${r.user?.id})\n");
  });

  tearDownAll(() async {
    if (saltar != null) return;
    await cliente.auth.signOut();
    await cliente.dispose();
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
      final repo = RepositorioProgreso(cliente: cliente);

      final perfil = await repo.perfil();
      print(
        "  perfil: ${perfil?.nombre} · rol ${perfil?.rol} "
        "· área ${perfil?.areaNombre} · staff ${perfil?.esStaff}",
      );
      expect(
        perfil,
        isNotNull,
        reason: "Sin perfil, el disparador al_crear_usuario no corrió",
      );

      final racha = await repo.racha();
      print(
        "  racha: ${racha?.diasActual} días "
        "(máx ${racha?.diasMaxima}, hoy ${racha?.estudiadoHoy})",
      );

      final d = await repo.diagnostico();
      print(
        "  diagnóstico: ${d.subtemas.length} subtemas · "
        "${d.aciertoGlobal} % global · ${d.respondidas} respondidas · "
        "${d.consolidados} dominados",
      );
      // Si hay datos, los agregados tienen que ser coherentes entre sí.
      if (!d.vacio) {
        expect(d.correctas, lessThanOrEqualTo(d.respondidas));
        expect(d.aciertoGlobal, inInclusiveRange(0, 100));
        expect(d.prioridades.length, lessThanOrEqualTo(5));
      }

      final reportes = await repo.reportesResueltos();
      print("  reportes resueltos sin ver: ${reportes.length}");
    });

    test("Repaso: resumen y las listas (sin cruzar contra el banco)", () async {
      final repo = RepositorioRepaso(cliente: cliente);

      final resumen = await repo.resumen();
      print(
        "  resumen: ${resumen?.pendientesHoy} para hoy de "
        "${resumen?.totalProgramados} · próxima ${resumen?.proximaFecha}",
      );

      // Sin `rootBundle` en este entorno, `RepositorioRepaso` no puede cruzar
      // los códigos contra `RepositorioPreguntas` (necesita leer assets, y
      // eso exige el binding de Flutter). Se llama al RPC directo para medir
      // la forma cruda, que es lo que este archivo puede verificar aquí; el
      // cruce completo contra el banco ya lo cubre `test/vinculos_test.dart`
      // y compañía con datos locales.
      await mostrarRpc(cliente, "repasos_pendientes", {"p_limite": 5});
      await mostrarRpc(cliente, "preguntas_falladas", null);
      await mostrarRpc(cliente, "preguntas_recomendadas", {"p_limite": 5});
    });

    test("Simulacro: lista, intento y preguntas", () async {
      final repo = RepositorioSimulacro(cliente: cliente);

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
        print(
          "      iniciado_en UTC: ${enCurso.iniciadoEn.isUtc} "
          "(${enCurso.iniciadoEn})",
        );
        expect(enCurso.iniciadoEn.isUtc, isTrue);
        // `preguntasDe` también cruza contra el banco local — se omite aquí
        // por el mismo motivo que en Repaso, y queda cubierto por los tests
        // que ya corren con datos locales.
      }
    });
  });

  group(
    "lo que ESCRIBE en la base",
    skip: saltar ?? (_escritura ? null : "Añade --dart-define=ESCRITURA=1"),
    () {
      test("responder una pregunta de práctica", () async {
        final repo = RepositorioPractica(cliente: cliente);

        // Sin `rootBundle` aquí no se puede resolver el banco local para
        // escoger una pregunta al azar: se usa un código real conocido del
        // banco publicado. Si ese código deja de existir, el error de
        // "pregunta no encontrada" es la propia señal de que hay que
        // actualizarlo.
        const codigoConocido = "ARI-2026-001";

        try {
          final c = await repo.responder(
            codigoPregunta: codigoConocido,
            marcada: Letra.a,
            segundos: 7,
          );
          print(
            "  $codigoConocido: correcta=${c.esCorrecta} "
            "clave=${c.clave.etiqueta} "
            "explicación=${c.explicacion == null ? "no" : "sí"}",
          );
          print("  intento creado: ${repo.intentoId}");

          expect(repo.intentoId, isNotNull);
          await repo.finalizar();
          print("  intento cerrado");
        } on ErrorPractica catch (e) {
          fail(
            "$e — ¿sigue existiendo $codigoConocido? Actualiza el código "
            "conocido en este test si el banco cambió.",
          );
        }
      });

      test("abrir y cerrar un simulacro", () async {
        final repo = RepositorioSimulacro(cliente: cliente);

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

        // El orden de preguntas sí se puede leer sin el banco local —solo
        // hace falta el id numérico, no el enunciado— así que se resuelve a
        // mano contra `simulacro_preguntas` en vez de usar `preguntasDe`.
        final orden = await cliente
            .from("simulacro_preguntas")
            .select("pregunta_id")
            .eq("simulacro_id", intento.simulacroId)
            .order("orden")
            .limit(1);
        expect(orden, isNotEmpty);
        final preguntaId = orden.first["pregunta_id"] as int;

        await repo.responder(
          intentoId: id,
          preguntaId: preguntaId,
          letra: Letra.a,
        );
        print("  respuesta guardada");

        await repo.finalizar(id);
        final cerrado = await repo.intento(id);
        print(
          "  cerrado · puntaje ${cerrado?.puntaje} "
          "· ${cerrado?.correctas}/${cerrado?.totalPreguntas}",
        );
        expect(cerrado!.enCurso, isFalse);

        final p = await repo.percentil(id);
        print("  percentil: ${p?.percentil} de ${p?.totalIntentos} intentos");
      });
    },
  );
}

Future<void> mostrarRpc(
  SupabaseClient cliente,
  String nombre,
  Map<String, dynamic>? params,
) async {
  final v = await cliente.rpc(nombre, params: params);
  print("  $nombre\n      ${forma(v)}");
}
