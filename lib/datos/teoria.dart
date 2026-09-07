import "catalogo.dart";

/// Una sección de teoría: el nodo de un árbol, con su markdown.
///
/// Réplica del modelo de `src/lib/teoria.ts`. Los campos salen tal cual de
/// `contenido.temas` del banco importado, y `padreId` es lo que convierte la
/// lista plana del JSON en el árbol que se ve en pantalla.
class SeccionTeoria {
  final int id;
  final int? padreId;
  final String? numero;
  final String titulo;
  final int nivel;
  final int orden;
  final String markdown;

  const SeccionTeoria({
    required this.id,
    required this.padreId,
    required this.numero,
    required this.titulo,
    required this.nivel,
    required this.orden,
    required this.markdown,
  });

  factory SeccionTeoria.desdeJson(Map<String, dynamic> j) => SeccionTeoria(
    id: j["id"] as int,
    padreId: j["padreId"] as int?,
    numero: j["numero"] as String?,
    titulo: (j["titulo"] as String).trim(),
    nivel: j["nivel"] as int? ?? 2,
    orden: j["orden"] as int? ?? 0,
    markdown: j["markdown"] as String? ?? "",
  );

  /// Una sección sin markdown es un encabezado del índice, no contenido.
  bool get tieneContenido => markdown.trim().isNotEmpty;

  String get tituloConNumero =>
      numero == null ? titulo : "$numero  $titulo";
}

class CursoTeoria {
  final String slug;
  final String nombre;
  final List<SeccionTeoria> secciones;

  const CursoTeoria({
    required this.slug,
    required this.nombre,
    required this.secciones,
  });

  int get conContenido => secciones.where((s) => s.tieneContenido).length;

  factory CursoTeoria.desdeJson(Map<String, dynamic> j) {
    final curso = j["curso"] as Map<String, dynamic>;
    final temas = (j["temas"] as List).cast<Map<String, dynamic>>();
    return CursoTeoria(
      slug: curso["slug"] as String,
      nombre: curso["nombre"] as String,
      secciones: temas.map(SeccionTeoria.desdeJson).toList()
        ..sort((a, b) => a.orden.compareTo(b.orden)),
    );
  }
}

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
