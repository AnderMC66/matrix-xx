import "package:supabase_flutter/supabase_flutter.dart";

import "preguntas.dart";

/// Puerto de `src/lib/simulacros.ts` + `src/app/simulacros/acciones.ts`.
///
/// A diferencia de `temario.dart` y `preguntas.dart`, este módulo **sí**
/// consulta Supabase en vivo: qué preguntas trae un simulacro, en qué orden, y
/// qué respondió ya el alumno vive en Postgres (`simulacro_preguntas`,
/// `respuestas`), no en los assets.
///
/// El enunciado de cada pregunta sí se reusa del banco local: `codigo_externo`
/// conecta cada fila de `public.preguntas` con la pregunta idéntica del APK
/// —es la misma fuente que sembró la base—, así que no hace falta bajar los
/// enunciados por red ni reimplementar nada.

class SimulacroResumen {
  final int id;
  final String nombre;
  final String? descripcion;
  final int duracionMinutos;

  const SimulacroResumen({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.duracionMinutos,
  });
}

class Intento {
  final int id;
  final int simulacroId;
  final DateTime iniciadoEn;
  final DateTime? finalizadoEn;
  final double? puntaje;
  final int? totalPreguntas;
  final int? correctas;

  const Intento({
    required this.id,
    required this.simulacroId,
    required this.iniciadoEn,
    required this.finalizadoEn,
    required this.puntaje,
    required this.totalPreguntas,
    required this.correctas,
  });

  bool get enCurso => finalizadoEn == null;
}

/// Una pregunta dentro de un intento: la del banco, más lo que la base añade.
class PreguntaSimulacro {
  final Pregunta pregunta;

  /// El id numérico real en `public.preguntas`, el que exige el RPC. En
  /// simulacro no hace falta resolver `codigo_externo` en cada envío como en
  /// práctica: la sesión ya trabaja con el id desde que se armó.
  final int preguntaId;

  /// Lo que ya se había marcado, si la sesión se retoma a mitad.
  final Letra? respuestaPrevia;

  const PreguntaSimulacro({
    required this.pregunta,
    required this.preguntaId,
    required this.respuestaPrevia,
  });
}

class PercentilSimulacro {
  /// `null` cuando todavía no hay muestra suficiente para que signifique algo.
  final int? percentil;
  final int totalIntentos;
  final double puntajePropio;
  final double? puntajeMediano;
  final double? puntajeMaximo;

  const PercentilSimulacro({
    required this.percentil,
    required this.totalIntentos,
    required this.puntajePropio,
    required this.puntajeMediano,
    required this.puntajeMaximo,
  });
}

/// El detalle por pregunta de un intento ya cerrado. Recién aquí es seguro
/// revelar si cada respuesta fue correcta: antes de finalizar,
/// `responder_pregunta` retiene esa información a propósito.
class ResultadoPregunta {
  final int preguntaId;
  final String codigo;
  final String cursoNombre;
  final String subtemaNombre;
  final Letra? letraMarcada;
  final bool? esCorrecta;

  const ResultadoPregunta({
    required this.preguntaId,
    required this.codigo,
    required this.cursoNombre,
    required this.subtemaNombre,
    required this.letraMarcada,
    required this.esCorrecta,
  });

  bool get sinResponder => letraMarcada == null;
}

/// El servidor rechazó la respuesta porque el plazo del simulacro venció.
///
/// Tiene su propio tipo porque **no es un fallo de red**: reintentarlo sería
/// pedirle al alumno que revise su conexión cuando lo que pasó es que se acabó
/// el examen. Desde `20260827120000_cronometro_en_servidor.sql` el plazo lo
/// hace cumplir Postgres, no el cronómetro de la pantalla.
class TiempoAgotado implements Exception {
  const TiempoAgotado();

  @override
  String toString() => "Se acabó el tiempo del simulacro.";
}

class ErrorSimulacro implements Exception {
  final String mensaje;
  const ErrorSimulacro(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Parsea un `timestamptz` de Postgres a un instante **siempre en UTC**.
///
/// `DateTime.parse` decide la zona por el texto: con offset (`...+00:00`, `Z`)
/// marca UTC, y sin él devuelve un `DateTime` en hora local. PostgREST manda
/// el offset, así que hoy siempre cae en el primer caso — pero de eso depende
/// el cronómetro del examen, y confundirse cuesta 5 horas de reloj en Perú
/// (UTC-5): un alumno vería el plazo agotado nada más empezar, o al revés.
///
/// Ante la duda se interpreta como UTC, que es lo que Postgres guarda.
DateTime instanteUtc(String texto) {
  final fecha = DateTime.parse(texto);
  return fecha.isUtc ? fecha : DateTime.utc(
    fecha.year,
    fecha.month,
    fecha.day,
    fecha.hour,
    fecha.minute,
    fecha.second,
    fecha.millisecond,
    fecha.microsecond,
  );
}

class RepositorioSimulacro {
  final SupabaseClient _cliente;
  final RepositorioPreguntas _preguntas;

  RepositorioSimulacro({
    SupabaseClient? cliente,
    RepositorioPreguntas? preguntas,
  }) : _cliente = cliente ?? Supabase.instance.client,
       _preguntas = preguntas ?? RepositorioPreguntas();

  bool get hayCuenta => _cliente.auth.currentUser != null;

  Future<List<SimulacroResumen>> publicados() async {
    final filas = await _cliente
        .from("simulacros")
        .select("id, nombre, descripcion, duracion_minutos")
        .eq("publicado", true)
        .order("id");

    return [
      for (final s in filas)
        SimulacroResumen(
          id: s["id"] as int,
          nombre: s["nombre"] as String,
          descripcion: s["descripcion"] as String?,
          duracionMinutos: s["duracion_minutos"] as int,
        ),
    ];
  }

  Future<SimulacroResumen?> simulacro(int id) async {
    final s = await _cliente
        .from("simulacros")
        .select("id, nombre, descripcion, duracion_minutos")
        .eq("id", id)
        .eq("publicado", true)
        .maybeSingle();
    if (s == null) return null;

    return SimulacroResumen(
      id: s["id"] as int,
      nombre: s["nombre"] as String,
      descripcion: s["descripcion"] as String?,
      duracionMinutos: s["duracion_minutos"] as int,
    );
  }

  /// Arranca un simulacro: el RPC crea el intento y precarga una respuesta en
  /// blanco por pregunta (`20260806120400_motor_simulacros.sql`).
  Future<int> iniciar(int simulacroId) async {
    if (!hayCuenta) {
      throw const ErrorSimulacro("Entra a tu cuenta para rendir un simulacro.");
    }
    final datos = await _cliente.rpc(
      "iniciar_simulacro",
      params: {"p_simulacro_id": simulacroId},
    );
    if (datos is int) return datos;
    throw const ErrorSimulacro("El servidor no devolvió el intento.");
  }

  /// El intento tal cual está en Postgres.
  ///
  /// La RLS de `intentos` ya restringe a "el dueño o un admin": si el intento
  /// es de otro usuario esto devuelve `null`, no un error, y quien llama
  /// decide qué hacer.
  Future<Intento?> intento(int intentoId) async {
    final f = await _cliente
        .from("intentos")
        .select(
          "id, simulacro_id, iniciado_en, finalizado_en, puntaje, "
          "total_preguntas, correctas",
        )
        .eq("id", intentoId)
        .eq("modo", "simulacro")
        .maybeSingle();
    if (f == null || f["simulacro_id"] == null) return null;

    final fin = f["finalizado_en"] as String?;
    return Intento(
      id: f["id"] as int,
      simulacroId: f["simulacro_id"] as int,
      iniciadoEn: instanteUtc(f["iniciado_en"] as String),
      finalizadoEn: fin == null ? null : instanteUtc(fin),
      puntaje: (f["puntaje"] as num?)?.toDouble(),
      totalPreguntas: f["total_preguntas"] as int?,
      correctas: f["correctas"] as int?,
    );
  }

  /// El intento en curso del alumno, si dejó uno a medias.
  ///
  /// No existe en la web —allí se llega por URL, y el enlace de un intento a
  /// medias queda en el historial del navegador—. En una app no hay barra de
  /// direcciones: sin esto, cerrar la app a mitad de examen dejaría el intento
  /// abierto e inalcanzable, corriendo su cronómetro hasta agotarse.
  Future<Intento?> intentoEnCurso() async {
    if (!hayCuenta) return null;

    final f = await _cliente
        .from("intentos")
        .select(
          "id, simulacro_id, iniciado_en, finalizado_en, puntaje, "
          "total_preguntas, correctas",
        )
        .eq("modo", "simulacro")
        .isFilter("finalizado_en", null)
        .order("iniciado_en", ascending: false)
        .limit(1)
        .maybeSingle();
    if (f == null || f["simulacro_id"] == null) return null;

    return Intento(
      id: f["id"] as int,
      simulacroId: f["simulacro_id"] as int,
      iniciadoEn: instanteUtc(f["iniciado_en"] as String),
      finalizadoEn: null,
      puntaje: (f["puntaje"] as num?)?.toDouble(),
      totalPreguntas: f["total_preguntas"] as int?,
      correctas: f["correctas"] as int?,
    );
  }

  /// Las preguntas de un intento, en el orden del simulacro, con lo que ya se
  /// hubiera respondido.
  ///
  /// El orden sale de `simulacro_preguntas`, no de las respuestas: como
  /// `iniciar_simulacro` precarga una fila en blanco por pregunta, esta
  /// consulta encuentra siempre el examen completo aunque no se haya
  /// respondido nada.
  Future<List<PreguntaSimulacro>> preguntasDe(Intento intento) async {
    final orden = await _cliente
        .from("simulacro_preguntas")
        .select("orden, pregunta_id, preguntas(codigo_externo)")
        .eq("simulacro_id", intento.simulacroId)
        .order("orden");

    final respuestas = await _cliente
        .from("respuestas")
        .select("pregunta_id, letra_marcada")
        .eq("intento_id", intento.id);

    final marcadaPor = {
      for (final r in respuestas)
        r["pregunta_id"] as int: letraDesde(r["letra_marcada"] as String? ?? ""),
    };

    final banco = await _preguntas.cargar();
    final lista = <PreguntaSimulacro>[];

    for (final fila in orden) {
      final codigo =
          (fila["preguntas"] as Map?)?["codigo_externo"] as String?;
      if (codigo == null) continue;
      final pregunta = banco.porCodigo(codigo);
      // Se ignora en vez de romper la sesión entera: una pregunta que la base
      // tiene y este APK no (versión vieja) cuesta un hueco, no el examen.
      if (pregunta == null) continue;

      final preguntaId = fila["pregunta_id"] as int;
      lista.add(
        PreguntaSimulacro(
          pregunta: pregunta,
          preguntaId: preguntaId,
          respuestaPrevia: marcadaPor[preguntaId],
        ),
      );
    }

    return lista;
  }

  /// Guarda una respuesta. En modo simulacro el RPC devuelve `clave: null` —
  /// la retiene hasta finalizar—, así que aquí no hay nada que revelar.
  Future<void> responder({
    required int intentoId,
    required int preguntaId,
    required Letra letra,
    int? segundos,
  }) async {
    try {
      await _cliente.rpc(
        "responder_pregunta",
        params: {
          "p_intento_id": intentoId,
          "p_pregunta_id": preguntaId,
          "p_letra": letra.etiqueta,
          "p_segundos": ?segundos,
        },
      );
    } on PostgrestException catch (e) {
      if (RegExp("tiempo del simulacro", caseSensitive: false)
          .hasMatch(e.message)) {
        throw const TiempoAgotado();
      }
      rethrow;
    }
  }

  /// Cierra el intento. `finalizar_intento` es idempotente: cerrarlo dos veces
  /// (doble pulsación, o el cronómetro justo después de un envío manual) no es
  /// un error que haya que enseñar.
  Future<void> finalizar(int intentoId) =>
      _cliente.rpc("finalizar_intento", params: {"p_intento_id": intentoId});

  /// Cómo quedó este intento frente a los demás postulantes.
  ///
  /// El RPC solo devuelve agregados —nunca de quién es cada puntaje— y exige un
  /// mínimo de intentos ajenos antes de dar un percentil: con dos o tres, la
  /// cifra no sería estadística sino información sobre personas concretas.
  Future<PercentilSimulacro?> percentil(int intentoId) async {
    try {
      final datos = await _cliente.rpc(
        "percentil_simulacro",
        params: {"p_intento_id": intentoId},
      );
      final fila = datos is List
          ? (datos.isEmpty ? null : datos.first as Map<String, dynamic>?)
          : datos as Map<String, dynamic>?;
      if (fila == null) return null;

      return PercentilSimulacro(
        percentil: (fila["percentil"] as num?)?.round(),
        totalIntentos: fila["total_intentos"] as int? ?? 0,
        puntajePropio: (fila["puntaje_propio"] as num?)?.toDouble() ?? 0,
        puntajeMediano: (fila["puntaje_mediano"] as num?)?.toDouble(),
        puntajeMaximo: (fila["puntaje_maximo"] as num?)?.toDouble(),
      );
    } catch (_) {
      // La comparación es un extra: si falla, el alumno igual debe ver su nota.
      return null;
    }
  }

  Future<List<ResultadoPregunta>> resultado(Intento intento) async {
    final orden = await _cliente
        .from("simulacro_preguntas")
        .select("orden, pregunta_id, preguntas(codigo_externo)")
        .eq("simulacro_id", intento.simulacroId)
        .order("orden");

    final respuestas = await _cliente
        .from("respuestas")
        .select("pregunta_id, letra_marcada, es_correcta")
        .eq("intento_id", intento.id);

    final porPregunta = {
      for (final r in respuestas) r["pregunta_id"] as int: r,
    };

    final banco = await _preguntas.cargar();
    final lista = <ResultadoPregunta>[];

    for (final fila in orden) {
      final codigo =
          (fila["preguntas"] as Map?)?["codigo_externo"] as String?;
      if (codigo == null) continue;
      final pregunta = banco.porCodigo(codigo);
      if (pregunta == null) continue;

      final preguntaId = fila["pregunta_id"] as int;
      final r = porPregunta[preguntaId];

      lista.add(
        ResultadoPregunta(
          preguntaId: preguntaId,
          codigo: codigo,
          cursoNombre: pregunta.cursoNombre,
          subtemaNombre: pregunta.subtemaNombre,
          letraMarcada: letraDesde(r?["letra_marcada"] as String? ?? ""),
          esCorrecta: r?["es_correcta"] as bool?,
        ),
      );
    }

    return lista;
  }
}
