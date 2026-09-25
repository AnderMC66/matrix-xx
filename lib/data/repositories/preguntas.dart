import "package:matr_u/data/repositories/temario.dart";
import "package:matr_u/data/services/catalogo.dart";
import "package:matr_u/domain/models/preguntas.dart";

Dificultad _dificultadDesde(String? texto) => switch (texto) {
  "facil" => Dificultad.facil,
  "dificil" => Dificultad.dificil,
  _ => Dificultad.medio,
};

class RepositorioPreguntas {
  final _catalogo = Catalogo.instancia;
  final RepositorioTemario _temario;

  RepositorioPreguntas({RepositorioTemario? temario})
    : _temario = temario ?? RepositorioTemario();

  Banco? _cargado;

  Future<Banco> cargar() async {
    final yaEsta = _cargado;
    if (yaEsta != null) return yaEsta;

    final temario = await _temario.cargar();
    final nombres = await _catalogo.indice("preguntas");

    // `_indice.json` es el índice mismo, no un archivo del banco; y los demás
    // `_*.json` son los ejemplos de desarrollo, que solo entran si no hay
    // ningún archivo real. Misma regla que `cargar()` en la web.
    final candidatos = nombres.where((n) => n != "_indice.json").toList();
    final reales = candidatos.where((n) => !n.startsWith("_")).toList();
    final sonEjemplos = reales.isEmpty;
    final archivos = (sonEjemplos ? candidatos : reales)..sort();

    final preguntas = <Pregunta>[];
    for (final archivo in archivos) {
      final doc =
          await _catalogo.archivo("preguntas", archivo) as Map<String, dynamic>;
      final prefijo = doc["prefijo"] as String;
      final ano = doc["anoExamen"] as int;

      for (final crudo
          in (doc["preguntas"] as List).cast<Map<String, dynamic>>()) {
        final subtema = crudo["subtema"] as String;
        final ubicacion = temario.ubicacion(subtema);
        // El generador del repo web ya reporta esto como error; aquí basta
        // con no inventar una ubicación.
        if (ubicacion == null) continue;

        final numero = (crudo["numero"] as int).toString().padLeft(3, "0");
        preguntas.add(
          Pregunta(
            codigo: "$prefijo-$ano-$numero",
            enunciado: crudo["enunciado"] as String? ?? "",
            imagen: Figura.desde(crudo["imagen"] as Map<String, dynamic>?),
            dificultad: _dificultadDesde(crudo["dificultad"] as String?),
            alternativas: alternativasDesde(
              (crudo["alternativas"] as Map?)?.cast<String, dynamic>() ??
                  const {},
            ),
            subtemaCodigo: subtema,
            subtemaNombre: ubicacion.subtema.nombre,
            temaNombre: ubicacion.tema.nombre,
            cursoNombre: ubicacion.curso.nombre,
            cursoSlug: ubicacion.curso.slug,
          ),
        );
      }
    }

    return _cargado = Banco.indexando(preguntas, sonEjemplos: sonEjemplos);
  }
}
