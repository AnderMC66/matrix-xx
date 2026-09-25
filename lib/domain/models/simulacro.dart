import "package:matr_u/domain/models/preguntas.dart";

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
  return fecha.isUtc
      ? fecha
      : DateTime.utc(
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
