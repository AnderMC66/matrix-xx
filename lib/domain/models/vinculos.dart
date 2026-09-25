
/// Todo lo que hace falta para pintar la cabecera de un curso de un tirón.
class ResumenCurso {
  /// Preguntas del banco propio en este curso.
  final int preguntas;

  /// Subtemas del curso que tienen al menos una pregunta.
  final int subtemasConPreguntas;

  /// Secciones de teoría disponibles; 0 si el curso no tiene teoría.
  final int teoria;

  /// Slug del curso de teoría, para enlazar. `null` si no hay.
  final String? teoriaSlug;

  const ResumenCurso({
    required this.preguntas,
    required this.subtemasConPreguntas,
    required this.teoria,
    required this.teoriaSlug,
  });
}
