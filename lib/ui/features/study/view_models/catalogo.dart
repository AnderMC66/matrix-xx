/// Los modelos de las dos pantallas que leen el catálogo del APK.
///
/// Van juntos en un archivo porque comparten dependencias y forma —el banco y
/// el temario, leídos de los assets, sin red de por medio— y porque separarlos
/// serían dos archivos de treinta líneas.
///
/// **Aquí no hay `Inactivo`.** El catálogo viaja dentro del binario: no
/// depende de la sesión ni de que haya conexión, así que la carga arranca en
/// cuanto se crea el modelo y el único fallo posible es que falte un asset.
library;

import "dart:async";

import "package:matr_u/data/repositories/preguntas.dart";
import "package:matr_u/data/repositories/temario.dart";
import "package:matr_u/data/repositories/teoria.dart";
import "package:matr_u/data/repositories/vinculos.dart";
import "package:matr_u/domain/models/preguntas.dart";
import "package:matr_u/domain/models/temario.dart";
import "package:matr_u/domain/models/teoria.dart";
import "package:matr_u/domain/models/vinculos.dart";
import "package:matr_u/ui/core/vista_modelo.dart";

/// El temario entero, con cuántas preguntas hay en total.
typedef DatosTemario = (Temario temario, int preguntas);

class ModeloTemario extends VistaModelo {
  late final RepositorioTemario _temario = _temarioDado ?? RepositorioTemario();
  late final RepositorioPreguntas _banco = _bancoDado ?? RepositorioPreguntas();

  final RepositorioTemario? _temarioDado;
  final RepositorioPreguntas? _bancoDado;

  ModeloTemario({RepositorioTemario? temario, RepositorioPreguntas? banco})
    : _temarioDado = temario,
      _bancoDado = banco;

  Estado<DatosTemario> _datos = const Inactivo();
  Estado<DatosTemario> get datos => _datos;

  Future<void> cargar() => pedir<DatosTemario>("datos", () async {
    final temario = await _temario.cargar();
    final banco = await _banco.cargar();
    return (temario, banco.total);
  }, (estado) => _datos = estado);
}

/// Un curso con su resumen y cuántas preguntas tiene cada subtema.
typedef DatosCurso = (ResumenCurso resumen, Map<String, int> porSubtema);

class ModeloCurso extends VistaModelo {
  final Curso curso;

  late final RepositorioVinculos _vinculos =
      _vinculosDado ?? RepositorioVinculos();
  late final RepositorioPreguntas _banco = _bancoDado ?? RepositorioPreguntas();

  final RepositorioVinculos? _vinculosDado;
  final RepositorioPreguntas? _bancoDado;

  ModeloCurso({
    required this.curso,
    RepositorioVinculos? vinculos,
    RepositorioPreguntas? banco,
  }) : _vinculosDado = vinculos,
       _bancoDado = banco;

  Estado<DatosCurso> _datos = const Inactivo();
  Estado<DatosCurso> get datos => _datos;

  Future<void> cargar() => pedir<DatosCurso>("datos", () async {
    final resumen = await _vinculos.resumenDeCurso(curso);
    final banco = await _banco.cargar();
    return (resumen, banco.conteoPorSubtema());
  }, (estado) => _datos = estado);

  /// El curso de teoría que corresponde a este, o `null` si no lo tiene.
  ///
  /// La vista lo pide para decidir a dónde navegar. Devuelve el dato, no
  /// navega: quién empuja una ruta es cosa de la vista, y un modelo que sabe
  /// de `Navigator` deja de poder probarse sin árbol de widgets.
  Future<CursoTeoria?> teoria() => _vinculos.teoriaDeCurso(curso.codigo);

  /// Las preguntas del curso, para abrir una tanda.
  Future<List<Pregunta>> preguntas() async =>
      (await _banco.cargar()).deCurso(curso.slug);
}

/// El modelo de `/buscar`.
///
/// El **debounce vive aqui**, y no en la vista, porque es una decision sobre
/// cuando se hace el trabajo y no sobre como se pinta: `Temario.buscar`
/// recorre los 956 subtemas normalizando tildes en cada llamada, y sin
/// esperar a que el dedo pare, cada tecla dispara un recorrido entero.
///
/// Tenerlo aqui ademas lo hace probable sin widgets: antes habia que teclear
/// en un `TextField` de verdad y adelantar el reloj del test.
class ModeloBuscar extends VistaModelo {
  /// Cuanto se espera desde la ultima tecla.
  static const espera = Duration(milliseconds: 200);

  /// Cuantos resultados se pintan como mucho.
  static const limite = 200;

  late final RepositorioTemario _temario = _temarioDado ?? RepositorioTemario();
  final RepositorioTemario? _temarioDado;

  ModeloBuscar({RepositorioTemario? temario}) : _temarioDado = temario;

  Timer? _debounce;
  Temario? _cargado;

  String _consulta = "";
  String get consulta => _consulta;

  List<Ubicacion> _resultados = const [];
  List<Ubicacion> get resultados => _resultados;

  /// `true` hasta que el temario esta en memoria.
  bool get cargando => _cargado == null;

  /// El temario, o `null` mientras carga. El estado vacio lo usa para enseñar
  /// cuantos cursos hay antes de que se escriba nada.
  Temario? get temario => _cargado;

  Future<void> cargar() async {
    _cargado = await _temario.cargar();
    avisar();
  }

  void escribir(String texto) {
    _debounce?.cancel();
    _debounce = Timer(espera, () {
      _consulta = texto;
      final temario = _cargado;
      _resultados = temario == null || texto.trim().isEmpty
          ? const []
          : temario.buscar(texto, limite: limite);
      avisar();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

/// El modelo de la lista de cursos de teoría.
///
/// Es el más pequeño de la app —una lista y ya—, y existe por consistencia:
/// que una pantalla del mismo grupo mantenga su `FutureBuilder` obliga a quien
/// la lea a saber dos patrones en vez de uno.
class ModeloTeoria extends VistaModelo {
  late final RepositorioTeoria _repo = _repoDado ?? RepositorioTeoria();
  final RepositorioTeoria? _repoDado;

  ModeloTeoria({RepositorioTeoria? repositorio}) : _repoDado = repositorio;

  Estado<List<CursoTeoria>> _cursos = const Inactivo();
  Estado<List<CursoTeoria>> get cursos => _cursos;

  Future<void> cargar() => pedir<List<CursoTeoria>>(
    "cursos",
    _repo.cursos,
    (estado) => _cursos = estado,
  );
}
