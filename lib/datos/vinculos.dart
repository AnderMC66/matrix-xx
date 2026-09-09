import "preguntas.dart";
import "temario.dart";
import "teoria.dart";

/// Puerto de `src/lib/vinculos.ts`: une las tres piezas que hasta ahora
/// vivían aisladas — el temario oficial (19 cursos), la teoría importada
/// (15 cursos) y el banco de preguntas — declarando la única correspondencia
/// que existe entre las dos taxonomías.
///
/// **Es a nivel de CURSO y nada más, y no por falta de intentarlo.** La web
/// midió emparejar los 956 subtemas oficiales contra los 1 949 títulos de
/// teoría por similitud de palabras: solo 18% daba un candidato fuerte, con
/// falsos positivos dentro de ese 18% («Relaciones entre conjuntos» →
/// «RELACIONES ENTRE LÍNEAS Y ÁNGULOS»). Enlazar subtema→sección exige
/// criterio pedagógico, no ingeniería; enlazar subtema→curso de teoría es
/// exacto, y es lo que este mapeo hace.
///
/// Dos asimetrías reales del material, no errores de este archivo:
///
///  - `matematica` sirve a CUATRO cursos oficiales (Aritmética, Álgebra,
///    Geometría, Trigonometría): el banco importado no los separa.
///  - Comprensión Lectora no tiene teoría y nunca la tendrá desde esta
///    fuente: coherente con que se entrena con textos, no con teoría
///    declarativa.
const _teoriaPorCurso = <String, String?>{
  "ARI": "matematica",
  "ALG": "matematica",
  "GEO": "matematica",
  "TRI": "matematica",
  "RM": "razonamiento_matematico",
  "RL": "razonamiento_logico",
  "RV": "razonamiento_verbal",
  "LEN": "lenguaje",
  "LIT": "literatura",
  "ING": "ingles",
  "FIL": "filosofia",
  "PSI": "psicologia",
  "HIS": "historia",
  "GEG": "geografia",
  "QUI": "quimica",
  "BIO": "biologia",
  "FIS": "fisica",
  "CIV": "civica",
  "CL": null,
};

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

class RepositorioVinculos {
  final RepositorioTeoria _teoriaRepo;
  final RepositorioPreguntas _preguntasRepo;

  RepositorioVinculos({
    RepositorioTeoria? teoria,
    RepositorioPreguntas? preguntas,
  }) : _teoriaRepo = teoria ?? RepositorioTeoria(),
       _preguntasRepo = preguntas ?? RepositorioPreguntas();

  /// La teoría que le corresponde a un curso oficial, o `null` si no hay
  /// —porque el curso no tiene teoría (Comprensión Lectora), o porque este
  /// APK no trae ese archivo.
  Future<CursoTeoria?> teoriaDeCurso(String codigoCurso) async {
    final slug = _teoriaPorCurso[codigoCurso];
    if (slug == null) return null;
    try {
      return await _teoriaRepo.curso(slug);
    } catch (_) {
      return null;
    }
  }

  Future<ResumenCurso> resumenDeCurso(Curso curso) async {
    final banco = await _preguntasRepo.cargar();
    final conteo = banco.conteoPorSubtema();
    final teoria = await teoriaDeCurso(curso.codigo);

    var subtemasConPreguntas = 0;
    for (final tema in curso.temas) {
      for (final subtema in tema.subtemas) {
        if ((conteo[subtema.codigo] ?? 0) > 0) subtemasConPreguntas++;
      }
    }

    return ResumenCurso(
      preguntas: banco.deCurso(curso.slug).length,
      subtemasConPreguntas: subtemasConPreguntas,
      // Todas las secciones del árbol, con o sin contenido — igual que
      // `totalTemas` en la web (cuenta nodos, no hojas con markdown). Es lo
      // que ve el alumno como "cuántas secciones tiene este curso" antes de
      // entrar, y algunas son solo encabezados de índice.
      teoria: teoria?.secciones.length ?? 0,
      teoriaSlug: teoria?.slug,
    );
  }
}
