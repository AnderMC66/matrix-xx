/// Los tres modelos de la pestaña de práctica: la lista de cursos, la portada
/// de un subtema y la tanda.
library;

import "package:matr_u/data/repositories/practica.dart";
import "package:matr_u/data/repositories/preguntas.dart";
import "package:matr_u/data/repositories/sesion.dart";
import "package:matr_u/domain/models/practica.dart";
import "package:matr_u/domain/models/preguntas.dart";
import "package:matr_u/ui/core/vista_modelo.dart";

/// La lista de cursos con preguntas.
class ModeloPractica extends VistaModelo {
  late final RepositorioPreguntas _repo = _repoDado ?? RepositorioPreguntas();
  final RepositorioPreguntas? _repoDado;

  ModeloPractica({RepositorioPreguntas? repositorio}) : _repoDado = repositorio;

  Estado<Banco> _banco = const Inactivo();
  Estado<Banco> get banco => _banco;

  Future<void> cargar() =>
      pedir<Banco>("banco", _repo.cargar, (estado) => _banco = estado);
}

/// Las preguntas de un subtema.
class ModeloPracticaSubtema extends VistaModelo {
  final String codigo;

  late final RepositorioPreguntas _repo = _repoDado ?? RepositorioPreguntas();
  final RepositorioPreguntas? _repoDado;

  ModeloPracticaSubtema({required this.codigo, RepositorioPreguntas? banco})
    : _repoDado = banco;

  Estado<List<Pregunta>> _preguntas = const Inactivo();
  Estado<List<Pregunta>> get preguntas => _preguntas;

  Future<void> cargar() => pedir<List<Pregunta>>(
    "preguntas",
    () async => (await _repo.cargar()).deSubtema(codigo),
    (estado) => _preguntas = estado,
  );
}

/// Una tanda de práctica: qué pregunta va, qué se marcó y qué dijo el servidor.
///
/// **Aquí no hay `Estado<T>`.** Las preguntas llegan ya resueltas desde quien
/// abre la tanda, así que no hay carga inicial que representar; lo que sí hay
/// es un envío en vuelo por pregunta, y eso son un `bool` y un `String?`.
class ModeloSesionPractica extends VistaModelo {
  final List<Pregunta> preguntas;

  // Perezosos: resuelven `Supabase.instance.client`. Ver la nota en
  // `ModeloInicio`.
  late final RepositorioPractica _repo = _repoDado ?? RepositorioPractica();
  late final Sesion _sesion = _sesionDada ?? Sesion();

  final RepositorioPractica? _repoDado;
  final Sesion? _sesionDada;

  ModeloSesionPractica({
    required this.preguntas,
    RepositorioPractica? repositorio,
    Sesion? sesion,
  }) : _repoDado = repositorio,
       _sesionDada = sesion;

  bool get hayCuenta => _sesion.hayCuenta;

  /// El repositorio, para el widget de reporte de error.
  ///
  /// Es la unica fuga de la capa de datos hacia la vista que queda en la app,
  /// y esta acotada: `_Reporte` necesita el mismo intento abierto que la
  /// tanda —el RPC exige `intento_id`— y darle un repositorio propio abriria
  /// un intento distinto. Envolverlo en dos metodos del modelo escondería esa
  /// relacion sin quitarla.
  RepositorioPractica get repositorio => _repo;

  /// Hay un intento abierto al que colgar un reporte.
  bool get hayIntento => _repo.intentoId != null;

  int _indice = 0;
  int get indice => _indice;

  Letra? _marcada;
  Letra? get marcada => _marcada;

  Correccion? _correccion;
  Correccion? get correccion => _correccion;

  bool _enviando = false;
  bool get enviando => _enviando;

  String? _error;
  String? get error => _error;

  int _aciertos = 0;
  int get aciertos => _aciertos;

  bool _terminada = false;
  bool get terminada => _terminada;

  /// Cuándo se mostró la pregunta actual, para medir el tiempo que el RPC
  /// guarda en `respuestas.segundos`. Se reinicia en cada avance.
  DateTime _mostradaEn = DateTime.now();

  Pregunta get pregunta => preguntas[_indice];

  /// **Salir a mitad de tanda también la cierra.**
  ///
  /// `finalizar()` solo se llamaba al pasar de la última pregunta, y esa es la
  /// forma menos frecuente de terminar una práctica: lo normal es responder
  /// cinco de veinte y volver atrás. El intento quedaba abierto en `intentos`
  /// para siempre —nadie lo vuelve a tocar, porque la siguiente tanda
  /// construye un `RepositorioPractica` nuevo y abre otro—, así que sus
  /// totales nunca se consolidaban y la tabla acumulaba una fila huérfana por
  /// cada abandono. No era visible en ninguna pantalla, que es justo por lo
  /// que había durado.
  ///
  /// Va sin `await` porque `dispose` es síncrono, y el fallo se traga a
  /// propósito: el modelo ya no existe, no hay a quién avisar, y
  /// `finalizar_intento` es idempotente. Lo que no puede es tirar una
  /// excepción sin capturar desde un `dispose`.
  @override
  void dispose() {
    _repo.finalizar().catchError((_) {});
    super.dispose();
  }

  void marcar(Letra letra) {
    if (_correccion != null) return;
    _marcada = letra;
    avisar();
  }

  Future<void> responder() async {
    final marcada = _marcada;
    if (marcada == null || _correccion != null) return;

    _enviando = true;
    _error = null;
    avisar();

    try {
      final correccion = await _repo.responder(
        codigoPregunta: pregunta.codigo,
        marcada: marcada,
        segundos: DateTime.now().difference(_mostradaEn).inSeconds,
      );
      _correccion = correccion;
      if (correccion.esCorrecta) _aciertos++;
    } on ErrorPractica catch (e) {
      _error = e.mensaje;
    } on Object catch (e) {
      _error = "No se pudo enviar la respuesta. $e";
    } finally {
      _enviando = false;
      avisar();
    }
  }

  Future<void> avanzar() async {
    if (_indice + 1 >= preguntas.length) {
      // Cerrar el intento consolida el resumen del lado del servidor. Si falla
      // no se le arruina el resumen al alumno: ya respondió todo.
      try {
        await _repo.finalizar();
      } on Object catch (_) {
        // Sin nada que decir: la tanda terminó igual.
      }
      _terminada = true;
      avisar();
      return;
    }
    _indice++;
    _marcada = null;
    _correccion = null;
    _error = null;
    _mostradaEn = DateTime.now();
    avisar();
  }
}
