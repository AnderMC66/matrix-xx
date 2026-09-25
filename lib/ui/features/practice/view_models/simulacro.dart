/// Los tres modelos del simulacro: la lista, el examen y el resultado.
library;

import "dart:async";

import "package:matr_u/data/repositories/sesion.dart";
import "package:matr_u/data/repositories/simulacro.dart";
import "package:matr_u/domain/models/preguntas.dart";
import "package:matr_u/domain/models/simulacro.dart";
import "package:matr_u/ui/core/vista_modelo.dart";

/// Lo que `/simulacros` enseña: los publicados, el intento a medias si lo hay,
/// y el historial.
typedef DatosSimulacro = (
  List<SimulacroResumen> simulacros,
  Intento? enCurso,
  List<Intento> historial,
);

/// El modelo de la lista de simulacros.
class ModeloSimulacro extends VistaModelo {
  // Perezosos: resuelven `Supabase.instance.client`. Ver `ModeloInicio`.
  late final RepositorioSimulacro _repo = _repoDado ?? RepositorioSimulacro();
  late final Sesion _sesion = _sesionDada ?? Sesion();

  final RepositorioSimulacro? _repoDado;
  final Sesion? _sesionDada;

  ModeloSimulacro({RepositorioSimulacro? repositorio, Sesion? sesion})
    : _repoDado = repositorio,
      _sesionDada = sesion;

  bool get hayCuenta => _sesion.hayCuenta;

  /// El repositorio, para pasárselo a la sesión de examen y al resultado.
  ///
  /// Comparten el mismo, y no uno nuevo cada uno, por lo mismo que en
  /// práctica: son pasos de una misma cosa.
  RepositorioSimulacro get repositorio => _repo;

  Estado<DatosSimulacro> _datos = const Inactivo();
  Estado<DatosSimulacro> get datos => _datos;

  Future<void> cargar() {
    if (!hayCuenta) return Future.value();
    return pedir<DatosSimulacro>("datos", _pedir, (estado) => _datos = estado);
  }

  /// Las tres a la vez, como en Progreso y en Inicio.
  ///
  /// Un registro `(await a, await b, await c)` parece paralelo y no lo es:
  /// Dart evalúa los campos en orden, así que eran tres viajes encadenados
  /// contra Supabase para pintar una pantalla cuyos tres datos no dependen
  /// entre sí. Esta pestaña se rehace cada vez que se entra, así que esas tres
  /// latencias se pagaban enteras en cada visita.
  Future<DatosSimulacro> _pedir() async {
    final resultados = await Future.wait([
      _repo.publicados(),
      _repo.intentoEnCurso(),
      _repo.historial(),
    ]);
    return (
      resultados[0] as List<SimulacroResumen>,
      resultados[1] as Intento?,
      resultados[2] as List<Intento>,
    );
  }

  /// Abre un intento nuevo y devuelve su id.
  Future<int> empezar(int simulacroId) => _repo.iniciar(simulacroId);
}

/// En qué punto está el guardado de una respuesta.
enum Guardado { guardando, guardado, error }

/// El modelo del examen en curso.
///
/// Es el que más cosas lleva a la vez: el cronómetro, la respuesta marcada de
/// cada pregunta, el estado de guardado de cada una, y el cierre —que puede
/// dispararlo el alumno o el propio reloj—.
class ModeloSesionSimulacro extends VistaModelo {
  final int intentoId;

  late final RepositorioSimulacro _repo = _repoDado ?? RepositorioSimulacro();
  final RepositorioSimulacro? _repoDado;

  ModeloSesionSimulacro({
    required this.intentoId,
    RepositorioSimulacro? repositorio,
  }) : _repoDado = repositorio;

  RepositorioSimulacro get repositorio => _repo;

  List<PreguntaSimulacro>? _preguntas;
  List<PreguntaSimulacro>? get preguntas => _preguntas;

  SimulacroResumen? _simulacro;
  SimulacroResumen? get simulacro => _simulacro;

  String? _errorCarga;
  String? get errorCarga => _errorCarga;

  int _indice = 0;
  int get indice => _indice;

  final _respuestas = <int, Letra>{};
  Map<int, Letra> get respuestas => _respuestas;

  final _estado = <int, Guardado>{};
  Map<int, Guardado> get estado => _estado;

  /// La última letra elegida por pregunta. Sirve para descartar el resultado
  /// de un guardado que llegó tarde: si el alumno ya cambió de alternativa
  /// mientras el envío anterior seguía en vuelo, ese resultado no debe pisar
  /// la elección más reciente.
  final _ultimaLetra = <int, Letra>{};

  DateTime? _limite;
  Duration _restante = Duration.zero;
  Duration get restante => _restante;

  Timer? _reloj;
  bool _finalizando = false;

  /// El intento al que hay que llevar al alumno, o `null` mientras el examen
  /// sigue.
  ///
  /// El modelo **no navega**: publica que ya terminó, y la vista, que es la
  /// que tiene `BuildContext`, empuja la ruta. Un modelo que sabe de
  /// `Navigator` deja de poder probarse sin árbol de widgets.
  int? _irAlResultadoDe;
  int? get irAlResultadoDe => _irAlResultadoDe;

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  Future<void> cargar() async {
    try {
      final intento = await _repo.intento(intentoId);
      if (intento == null) {
        _errorCarga = "Este intento no existe o no es tuyo.";
        avisar();
        return;
      }
      // Ya cerrado: no hay sesión que retomar, al resultado.
      if (!intento.enCurso) {
        _irAlResultadoDe = intento.id;
        avisar();
        return;
      }

      final simulacro = await _repo.simulacro(intento.simulacroId);
      final preguntas = await _repo.preguntasDe(intento);

      // El plazo sale de `iniciado_en` + `duracion_minutos`, ambos del
      // servidor. El reloj del dispositivo solo decide cómo se ve la cuenta
      // atrás: quien rechaza una respuesta tardía es Postgres, desde
      // `20260827120000_cronometro_en_servidor.sql`. Un móvil con la hora
      // corrida muestra mal el cronómetro, pero no gana ni pierde tiempo.
      _limite = intento.iniciadoEn.add(
        Duration(minutes: simulacro?.duracionMinutos ?? 0),
      );
      _simulacro = simulacro;
      _preguntas = preguntas;
      for (final p in preguntas) {
        if (p.respuestaPrevia case final l?) {
          _respuestas[p.preguntaId] = l;
          _ultimaLetra[p.preguntaId] = l;
          _estado[p.preguntaId] = Guardado.guardado;
        }
      }
      avisar();
      _arrancarReloj();
    } on Object catch (e) {
      _errorCarga = "$e";
      avisar();
    }
  }

  void _arrancarReloj() {
    void tic() {
      final limite = _limite;
      if (limite == null) return;
      final restante = limite.difference(DateTime.now().toUtc());
      _restante = restante.isNegative ? Duration.zero : restante;
      avisar();
      if (restante.isNegative || restante == Duration.zero) {
        _reloj?.cancel();
        finalizar();
      }
    }

    tic();
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) => tic());
  }

  void irA(int indice) {
    _indice = indice;
    avisar();
  }

  void marcar(int preguntaId, Letra letra) {
    _respuestas[preguntaId] = letra;
    _ultimaLetra[preguntaId] = letra;
    avisar();
    _guardar(preguntaId, letra);
  }

  /// Guarda una respuesta, reintentando hasta 3 veces con espera creciente.
  ///
  /// El plazo agotado NO se reintenta: no es un fallo de red, y machacar el
  /// servidor tres veces para acabar diciéndole al alumno «revisa tu
  /// conexión» cuando lo que pasó es que se acabó el examen sería mentirle.
  /// Se cierra el intento, que es lo que el cronómetro iba a hacer igual.
  Future<void> _guardar(int preguntaId, Letra letra) async {
    _estado[preguntaId] = Guardado.guardando;
    avisar();

    for (var intento = 0; intento < 3; intento++) {
      try {
        await _repo.responder(
          intentoId: intentoId,
          preguntaId: preguntaId,
          letra: letra,
        );
        if (_ultimaLetra[preguntaId] == letra) {
          _estado[preguntaId] = Guardado.guardado;
          avisar();
        }
        return;
      } on TiempoAgotado {
        await finalizar();
        return;
      } on Object catch (_) {
        if (intento < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 800 * (intento + 1)),
          );
        }
      }
    }

    if (_ultimaLetra[preguntaId] == letra) {
      _estado[preguntaId] = Guardado.error;
      avisar();
    }
  }

  /// Cuántas quedan sin responder. Lo usa el diálogo de confirmación.
  int get sinResponder => (_preguntas?.length ?? 0) - _respuestas.length;

  Future<void> finalizar() async {
    if (_finalizando) return;
    _finalizando = true;
    _reloj?.cancel();

    try {
      await _repo.finalizar(intentoId);
    } on Object catch (_) {
      // Aunque el cierre explícito falle, se va igual al resultado: si el
      // intento ya estaba cerrado (doble pulsación, o el cronómetro justo
      // después de un envío manual) `finalizar_intento` es idempotente y no
      // hay nada que reintentar.
    }
    _irAlResultadoDe = intentoId;
    avisar();
  }
}

/// Lo que se ve al terminar: el intento, el desglose y el percentil.
typedef DatosResultado = (
  Intento intento,
  List<ResultadoPregunta> desglose,
  PercentilSimulacro? percentil,
);

class ModeloResultado extends VistaModelo {
  final int intentoId;

  late final RepositorioSimulacro _repo = _repoDado ?? RepositorioSimulacro();
  final RepositorioSimulacro? _repoDado;

  ModeloResultado({required this.intentoId, RepositorioSimulacro? repositorio})
    : _repoDado = repositorio;

  Estado<DatosResultado> _datos = const Inactivo();
  Estado<DatosResultado> get datos => _datos;

  Future<void> cargar() =>
      pedir<DatosResultado>("datos", _pedir, (estado) => _datos = estado);

  /// El intento primero —las otras dos lo necesitan—, y después las dos
  /// juntas.
  ///
  /// El desglose y el percentil no dependen entre sí, así que encadenarlos
  /// sumaba una latencia de más justo cuando el alumno acaba de terminar un
  /// examen de tres horas y quiere ver su nota.
  Future<DatosResultado> _pedir() async {
    final intento = await _repo.intento(intentoId);
    // `ErrorSimulacro` y no una cadena suelta: lanzar un `String` deja fuera
    // a cualquier `on Exception catch`, y el tipo ya existe para esto.
    if (intento == null) {
      throw const ErrorSimulacro("Este intento no existe o no es tuyo.");
    }
    final resultados = await Future.wait([
      _repo.resultado(intento),
      _repo.percentil(intento.id),
    ]);
    return (
      intento,
      resultados[0] as List<ResultadoPregunta>,
      resultados[1] as PercentilSimulacro?,
    );
  }
}
