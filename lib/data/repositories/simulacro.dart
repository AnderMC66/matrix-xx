import "package:matr_u/data/repositories/preguntas.dart";
import "package:matr_u/domain/models/preguntas.dart";
import "package:matr_u/domain/models/simulacro.dart";
import "package:supabase_flutter/supabase_flutter.dart";
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
  ///
  /// **El filtro por `perfil_id` es obligatorio aquí, y RLS no basta.** La
  /// política de `intentos` deja ver «el dueño o un admin» (ver [intento]), y
  /// esta consulta pide *el intento abierto más reciente que yo pueda ver*: a
  /// un admin o docente eso le devolvía el examen a medias de OTRO alumno, y
  /// el botón «Retomar» se lo abría para responderlo en su nombre. Donde
  /// [intento] recibe un id concreto y RLS solo decide si lo deja pasar, esto
  /// busca a ciegas — y buscar a ciegas con permisos amplios encuentra lo que
  /// no toca.
  Future<Intento?> intentoEnCurso() async {
    final usuario = _cliente.auth.currentUser;
    if (usuario == null) return null;

    final f = await _cliente
        .from("intentos")
        .select(
          "id, simulacro_id, iniciado_en, finalizado_en, puntaje, "
          "total_preguntas, correctas",
        )
        .eq("perfil_id", usuario.id)
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

  /// Los simulacros que el alumno ya rindió, del más reciente al más antiguo.
  ///
  /// **Sin esto, un simulacro terminado era inalcanzable para siempre.** El
  /// resultado se veía una vez, al acabar, y nunca más: el puntaje, el
  /// percentil y el desglose por curso seguían en Postgres y ninguna pantalla
  /// los volvía a leer. Es exactamente el mismo razonamiento que justificó
  /// [intentoEnCurso] —«en una app no hay barra de direcciones»— aplicado a la
  /// otra mitad del problema, que se había quedado sin resolver. Y pesa más
  /// aquí: en un examen de cupo limitado, «¿cómo iba hace tres semanas?» es la
  /// pregunta que sostiene el estudio.
  ///
  /// El filtro por `perfil_id` es obligatorio por lo mismo que en
  /// [intentoEnCurso]: la política de `intentos` deja ver «el dueño o un
  /// admin», así que sin él un docente vería el historial ajeno.
  Future<List<Intento>> historial({int limite = 20}) async {
    final usuario = _cliente.auth.currentUser;
    if (usuario == null) return const [];

    final filas = await _cliente
        .from("intentos")
        .select(
          "id, simulacro_id, iniciado_en, finalizado_en, puntaje, "
          "total_preguntas, correctas",
        )
        .eq("perfil_id", usuario.id)
        .eq("modo", "simulacro")
        .not("finalizado_en", "is", null)
        .order("finalizado_en", ascending: false)
        .limit(limite);

    return [
      for (final f in filas)
        if (f["simulacro_id"] != null)
          Intento(
            id: f["id"] as int,
            simulacroId: f["simulacro_id"] as int,
            iniciadoEn: instanteUtc(f["iniciado_en"] as String),
            finalizadoEn: instanteUtc(f["finalizado_en"] as String),
            puntaje: (f["puntaje"] as num?)?.toDouble(),
            totalPreguntas: f["total_preguntas"] as int?,
            correctas: f["correctas"] as int?,
          ),
    ];
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
        r["pregunta_id"] as int: letraDesde(
          r["letra_marcada"] as String? ?? "",
        ),
    };

    final banco = await _preguntas.cargar();
    final lista = <PreguntaSimulacro>[];

    for (final fila in orden) {
      final codigo = (fila["preguntas"] as Map?)?["codigo_externo"] as String?;
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
      if (RegExp(
        "tiempo del simulacro",
        caseSensitive: false,
      ).hasMatch(e.message)) {
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
      final codigo = (fila["preguntas"] as Map?)?["codigo_externo"] as String?;
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
