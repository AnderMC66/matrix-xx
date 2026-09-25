import "package:matr_u/data/models/catalogo.dart";

/// Puerto de `src/lib/temario.ts`: el temario oficial UNSA.
///
/// Mismas reglas de codificación que la web, y esto no es un detalle estético:
/// los códigos que salen de aquí (`FIS-09-03`) son literalmente los que
/// `scripts/generar-seed-temario.mjs` dejó en Postgres, y son la clave con la
/// que el banco de preguntas se cruza con el temario. Si el `padStart(2)` o el
/// orden de los subtemas se desviaran un ápice, `preguntas.dart` dejaría de
/// encontrar la ubicación de cada pregunta y el banco entero se vaciaría en
/// silencio — por eso `test/temario_test.dart` fija los códigos.
///
/// Diferencia con la web: allí `cacheDeDirectorio` revalida por `mtime` porque
/// editar un JSON en desarrollo debe verse al recargar. Aquí los archivos son
/// assets inmutables dentro del binario, así que se cargan una vez y ya.

enum TipoSubtema { contenido, capacidad }

class Subtema {
  final String codigo;
  final String nombre;
  final String? grupo;
  final TipoSubtema tipo;

  const Subtema({
    required this.codigo,
    required this.nombre,
    required this.grupo,
    required this.tipo,
  });
}

class Tema {
  final String codigo;
  final int numero;
  final String romano;
  final String nombre;
  final String? grupo;
  final List<Subtema> subtemas;

  /// El sílabo no desglosa este tema; el subtema es un marcador provisional.
  final bool pendienteDesglose;

  const Tema({
    required this.codigo,
    required this.numero,
    required this.romano,
    required this.nombre,
    required this.grupo,
    required this.subtemas,
    required this.pendienteDesglose,
  });
}

class Curso {
  final String codigo;
  final String nombre;
  final String slug;
  final String? nota;
  final String areaCodigo;
  final String areaNombre;
  final List<Tema> temas;

  const Curso({
    required this.codigo,
    required this.nombre,
    required this.slug,
    required this.nota,
    required this.areaCodigo,
    required this.areaNombre,
    required this.temas,
  });

  int get totalSubtemas => temas.fold(0, (n, t) => n + t.subtemas.length);
}

class AreaTematica {
  final String codigo;
  final String nombre;
  final int orden;
  final List<Curso> cursos;

  const AreaTematica({
    required this.codigo,
    required this.nombre,
    required this.orden,
    required this.cursos,
  });
}

/// Dónde vive un subtema dentro del árbol. Es lo que el banco de preguntas
/// necesita para ponerle nombre de curso y de tema a cada pregunta.
class Ubicacion {
  final Subtema subtema;
  final Tema tema;
  final Curso curso;

  const Ubicacion({
    required this.subtema,
    required this.tema,
    required this.curso,
  });
}

const _unidades = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"];
const _decenas = ["", "X", "XX", "XXX", "XL", "L", "LX", "LXX", "LXXX", "XC"];

String _aRomano(int n) => _decenas[n ~/ 10] + _unidades[n % 10];

String _pad(int n) => n.toString().padLeft(2, "0");

/// El temario cargado, ya indexado. Se construye una vez.
class Temario {
  final List<AreaTematica> areas;
  final Map<String, Ubicacion> _porSubtema;
  final Map<String, Curso> _porSlug;

  Temario._(this.areas, this._porSubtema, this._porSlug);

  List<Curso> get cursos => areas.expand((a) => a.cursos).toList();

  List<Tema> get temas => cursos.expand((c) => c.temas).toList();

  Curso? curso(String slug) => _porSlug[slug];

  /// Dónde cae un código de subtema, o `null` si no existe en el temario.
  Ubicacion? ubicacion(String codigoSubtema) => _porSubtema[codigoSubtema];

  int get totalSubtemas => _porSubtema.length;

  int get temasPendientes => temas.where((t) => t.pendienteDesglose).length;

  /// Búsqueda por subtema, insensible a tildes y a mayúsculas: escribir
  /// "quimica" tiene que encontrar "Química". Todos los términos deben
  /// aparecer, que es como se comporta `buscar()` en la web.
  List<Ubicacion> buscar(String consulta, {int limite = 200}) {
    final terminos = _normalizar(consulta.trim())
        .split(RegExp(r"\s+"))
        .where((t) => t.isNotEmpty)
        .toList();
    if (terminos.isEmpty) return const [];

    final resultados = <Ubicacion>[];
    for (final curso in cursos) {
      for (final tema in curso.temas) {
        for (final subtema in tema.subtemas) {
          final heno = _normalizar(
            "${subtema.codigo} ${subtema.nombre} ${subtema.grupo ?? ""} "
            "${tema.nombre} ${curso.nombre}",
          );
          if (terminos.every(heno.contains)) {
            resultados.add(
              Ubicacion(subtema: subtema, tema: tema, curso: curso),
            );
            if (resultados.length >= limite) return resultados;
          }
        }
      }
    }
    return resultados;
  }
}

/// Dart no trae `normalize("NFD")`, así que las tildes se mapean a mano. La
/// lista cubre lo que aparece en un temario en español; añadir una letra es
/// una entrada más.
const _sinTilde = {
  "á": "a",
  "é": "e",
  "í": "i",
  "ó": "o",
  "ú": "u",
  "ü": "u",
  "ñ": "n",
  "à": "a",
  "è": "e",
  "ì": "i",
  "ò": "o",
  "ù": "u",
};

String _normalizar(String texto) {
  final minuscula = texto.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in minuscula.runes) {
    final c = String.fromCharCode(rune);
    buffer.write(_sinTilde[c] ?? c);
  }
  return buffer.toString();
}

class RepositorioTemario {
  final _catalogo = Catalogo.instancia;

  Temario? _cargado;

  Future<Temario> cargar() async {
    final yaEsta = _cargado;
    if (yaEsta != null) return yaEsta;

    final crudos = await _catalogo.todos("temario");
    final areas =
        crudos.map((j) => _areaDesde(j as Map<String, dynamic>)).toList()
          ..sort((a, b) => a.orden.compareTo(b.orden));

    final porSubtema = <String, Ubicacion>{};
    final porSlug = <String, Curso>{};
    for (final area in areas) {
      for (final curso in area.cursos) {
        porSlug[curso.slug] = curso;
        for (final tema in curso.temas) {
          for (final subtema in tema.subtemas) {
            porSubtema[subtema.codigo] = Ubicacion(
              subtema: subtema,
              tema: tema,
              curso: curso,
            );
          }
        }
      }
    }

    return _cargado = Temario._(areas, porSubtema, porSlug);
  }

  AreaTematica _areaDesde(Map<String, dynamic> j) {
    final codigoArea = j["codigo"] as String;
    final nombreArea = j["nombre"] as String;

    final cursos = (j["cursos"] as List)
        .cast<Map<String, dynamic>>()
        .map((c) => _cursoDesde(c, codigoArea, nombreArea))
        .toList();

    return AreaTematica(
      codigo: codigoArea,
      nombre: nombreArea,
      orden: j["orden"] as int,
      cursos: cursos,
    );
  }

  Curso _cursoDesde(
    Map<String, dynamic> j,
    String areaCodigo,
    String areaNombre,
  ) {
    final codigoCurso = j["codigo"] as String;
    final tipo = j["tipoSubtema"] == "capacidad"
        ? TipoSubtema.capacidad
        : TipoSubtema.contenido;

    final temas = (j["temas"] as List)
        .cast<Map<String, dynamic>>()
        .map((t) => _temaDesde(t, codigoCurso, tipo))
        .toList();

    return Curso(
      codigo: codigoCurso,
      nombre: j["nombre"] as String,
      slug: j["slug"] as String,
      nota: j["nota"] as String?,
      areaCodigo: areaCodigo,
      areaNombre: areaNombre,
      temas: temas,
    );
  }

  Tema _temaDesde(
    Map<String, dynamic> j,
    String codigoCurso,
    TipoSubtema tipo,
  ) {
    final numero = j["numero"] as int;
    final codigoTema = "$codigoCurso-${_pad(numero)}";
    final lista = (j["subtemas"] as List?) ?? const [];

    // Un tema sin desglosar recibe igualmente un subtema `-00`, porque el
    // banco necesita poder etiquetar preguntas contra él mientras el sílabo
    // no se detalle. Misma decisión que en la web.
    final subtemas = lista.isEmpty
        ? [
            Subtema(
              codigo: "$codigoTema-00",
              nombre: "General (pendiente de desglose)",
              grupo: null,
              tipo: tipo,
            ),
          ]
        : [
            for (final (i, crudo) in lista.indexed)
              Subtema(
                codigo: "$codigoTema-${_pad(i + 1)}",
                nombre: crudo is String
                    ? crudo
                    : (crudo as Map<String, dynamic>)["nombre"] as String,
                grupo: crudo is String
                    ? null
                    : (crudo as Map<String, dynamic>)["grupo"] as String?,
                tipo: tipo,
              ),
          ];

    return Tema(
      codigo: codigoTema,
      numero: numero,
      romano: _aRomano(numero),
      nombre: j["nombre"] as String,
      grupo: j["grupo"] as String?,
      subtemas: subtemas,
      pendienteDesglose: lista.isEmpty,
    );
  }
}
