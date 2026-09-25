import "package:matr_u/data/services/catalogo.dart";
import "package:matr_u/domain/models/temario.dart";

const _unidades = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"];
const _decenas = ["", "X", "XX", "XXX", "XL", "L", "LX", "LXX", "LXXX", "XC"];

String _aRomano(int n) => _decenas[n ~/ 10] + _unidades[n % 10];

String _pad(int n) => n.toString().padLeft(2, "0");

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

    return _cargado = Temario.indexando(areas);
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
