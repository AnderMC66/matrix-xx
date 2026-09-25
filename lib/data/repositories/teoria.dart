import "package:matr_u/data/services/catalogo.dart";
import "package:matr_u/domain/models/teoria.dart";

/// Carga perezosa de los 15 cursos con teoría.
///
/// El listado se pide entero (son 15 archivos, ~5,4 MB) solo cuando se abre
/// `/teoria`; en la web esto lo resolvía el prerenderizado de Next, aquí lo
/// resuelve el caché del `Catalogo`.
class RepositorioTeoria {
  final _catalogo = Catalogo.instancia;

  Future<List<CursoTeoria>> cursos() async {
    final crudos = await _catalogo.todos("teoria");
    final lista = crudos
        .map((j) => CursoTeoria.desdeJson(j as Map<String, dynamic>))
        .toList();
    lista.sort((a, b) => a.nombre.compareTo(b.nombre));
    return lista;
  }

  Future<CursoTeoria> curso(String slug) async {
    final j = await _catalogo.archivo("teoria", "$slug.json");
    return CursoTeoria.desdeJson(j as Map<String, dynamic>);
  }
}
