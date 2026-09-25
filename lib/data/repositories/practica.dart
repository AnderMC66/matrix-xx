import "package:matr_u/domain/models/practica.dart";
import "package:matr_u/domain/models/preguntas.dart";
import "package:supabase_flutter/supabase_flutter.dart";
class RepositorioPractica {
  final SupabaseClient _cliente;

  RepositorioPractica({SupabaseClient? cliente})
    : _cliente = cliente ?? Supabase.instance.client;

  /// El intento vigente. Nace en la primera respuesta y se reutiliza hasta que
  /// la tanda se cierra.
  int? _intentoId;

  /// El intento vigente, o `null` si todavía no se respondió nada. La
  /// pantalla lo consulta para decidir si puede ofrecer el reporte de error:
  /// sin intento no hay sesión, y `reportes_error` exige `perfil_id`.
  int? get intentoId => _intentoId;

  /// Responde una pregunta, creando el intento si es la primera.
  ///
  /// Exige sesión. La web cae aquí a `corregir()` local para el alumno
  /// anónimo, pero eso solo es posible con la clave a mano, y en el móvil la
  /// clave no viaja (ver `preguntas.dart`). Sin sesión no hay corrección
  /// posible, y decirlo claro es mejor que fingir una.
  Future<Correccion> responder({
    required String codigoPregunta,
    required Letra marcada,
    int? segundos,
  }) async {
    final usuario = _cliente.auth.currentUser;
    if (usuario == null) {
      throw const ErrorPractica(
        "Entra a tu cuenta para practicar: la respuesta correcta la resuelve "
        "el servidor, no la app.",
      );
    }

    _intentoId ??= await _crearIntento(usuario.id);

    // `responder_pregunta` trabaja con el id numérico, y el banco local se
    // indexa por `codigo_externo`. La traducción la hace la base, que además
    // filtra por `estado = publicada`: una pregunta retirada deja de poder
    // responderse aunque siga en el APK de una versión vieja.
    final fila = await _cliente
        .from("preguntas")
        .select("id")
        .eq("codigo_externo", codigoPregunta)
        .eq("estado", "publicada")
        .maybeSingle();

    if (fila == null) {
      throw const ErrorPractica("Esa pregunta ya no está disponible.");
    }

    final datos = await _cliente.rpc(
      "responder_pregunta",
      params: {
        "p_intento_id": _intentoId,
        "p_pregunta_id": fila["id"],
        "p_letra": marcada.etiqueta,
        "p_segundos": ?segundos,
      },
    );

    // El RPC devuelve `setof`, así que llega una lista de una fila; según la
    // versión del cliente puede llegar ya desenvuelta.
    final resultado =
        (datos is List ? datos.firstOrNull : datos) as Map<String, dynamic>?;
    if (resultado == null) {
      throw const ErrorPractica("El servidor no devolvió una corrección.");
    }

    final clave = letraDesde(resultado["clave"] as String? ?? "");
    if (clave == null) {
      // En modo simulacro el RPC retiene la clave hasta finalizar. Si aparece
      // aquí es que el intento no es de práctica, y mostrar "correcta: null"
      // sería peor que decirlo.
      throw const ErrorPractica(
        "Este intento no es de práctica: el servidor retiene la clave.",
      );
    }

    return Correccion(
      esCorrecta: resultado["es_correcta"] as bool? ?? false,
      clave: clave,
      explicacion: (resultado["explicacion_md"] as String?)?.trim(),
    );
  }

  Future<int> _crearIntento(String perfilId) async {
    final fila = await _cliente
        .from("intentos")
        .insert({"perfil_id": perfilId, "modo": "practica"})
        .select("id")
        .single();
    return fila["id"] as int;
  }

  /// Cierra la tanda. Sin intento no hay nada que cerrar — pasa cuando el
  /// alumno abre la práctica y sale sin responder.
  Future<void> finalizar() async {
    final id = _intentoId;
    if (id == null) return;
    await _cliente.rpc("finalizar_intento", params: {"p_intento_id": id});
    _intentoId = null;
  }

  /// Los motivos que ofrece el desplegable, copiados de `MOTIVOS_REPORTE`.
  ///
  /// La lista está repetida en tres sitios a propósito —interfaz, servidor y
  /// el `check` de la tabla en `20260827120100_limitar_reportes.sql`—: cada
  /// uno protege de algo distinto, y el de la base es el único que no se puede
  /// saltar. Esta copia es el primero de los tres, no un cuarto.
  static const motivosReporte = [
    "Clave incorrecta",
    "Enunciado confuso",
    "Falta de información",
    "Otro",
  ];

  /// Mismo tope que el `check` de la tabla.
  static const _maxDetalle = 1000;

  /// Reporta un error en una pregunta. `true` si ya había un reporte abierto.
  Future<bool> reportar({
    required String codigoPregunta,
    required String motivo,
    String? detalle,
  }) async {
    if (!motivosReporte.contains(motivo)) {
      throw const ErrorPractica("Motivo no válido");
    }
    if (_cliente.auth.currentUser == null) {
      throw const ErrorPractica("Entra a tu cuenta para reportar un error.");
    }

    // El campo arranca vacío: sin esto, todo reporte sin detalle guardaría una
    // cadena vacía y la bandeja del docente no podría distinguir "no escribió
    // nada" de "escribió y se borró".
    final recortado = detalle?.trim();
    final limpio = (recortado == null || recortado.isEmpty)
        ? null
        : recortado.substring(0, recortado.length.clamp(0, _maxDetalle));

    final pregunta = await _cliente
        .from("preguntas")
        .select("id")
        .eq("codigo_externo", codigoPregunta)
        .maybeSingle();
    if (pregunta == null) {
      throw const ErrorPractica("Pregunta no encontrada");
    }

    try {
      await _cliente.from("reportes_error").insert({
        "perfil_id": _cliente.auth.currentUser!.id,
        "pregunta_id": pregunta["id"],
        "motivo": motivo,
        "detalle": limpio,
      });
      return false;
    } on PostgrestException catch (e) {
      // El índice único parcial impide dos reportes ABIERTOS de la misma
      // pregunta. No es un fallo que enseñar como error: el alumno ya reportó
      // esto y su reporte sigue en la cola.
      if (e.code == "23505") return true;
      rethrow;
    }
  }
}

class ErrorPractica implements Exception {
  final String mensaje;
  const ErrorPractica(this.mensaje);

  @override
  String toString() => mensaje;
}
