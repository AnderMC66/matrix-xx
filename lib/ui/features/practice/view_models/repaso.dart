import "package:matr_u/data/repositories/repaso.dart";
import "package:matr_u/data/repositories/sesion.dart";
import "package:matr_u/domain/models/preguntas.dart";
import "package:matr_u/domain/models/repaso.dart";
import "package:matr_u/ui/core/vista_modelo.dart";

/// Las dos formas de repasar. Vivía dentro de la pantalla como `_Modo`, y era
/// privado: el modo elegido es estado de la vista, así que ahora es del modelo
/// y tiene que poder nombrarse desde fuera.
enum ModoRepaso { programadas, falladas }

/// Lo que hace falta para pintar el repaso: las preguntas del modo elegido y
/// el resumen del calendario.
///
/// Van juntas en una sola petición porque se piden a la vez —no dependen entre
/// sí— y porque la pantalla no sabe qué enseñar hasta tener las dos: con cero
/// preguntas, el texto que se muestra depende del resumen.
typedef DatosRepaso = (List<Pregunta> preguntas, ResumenRepasos? resumen);

/// El modelo de vista de `/repaso`.
class ModeloRepaso extends VistaModelo {
  // Los repositorios son `late`, no del constructor, y no es un detalle: se
  // construyen la PRIMERA VEZ que se usan. Cada uno resuelve
  // `Supabase.instance.client`, asi que armarlos en la lista de
  // inicializacion hace que crear el modelo reviente en cuanto Supabase no
  // este listo — que es justo lo que pasa mientras `Arranque` todavia
  // inicializa, y lo que rompio tres tests de `arranque_test`.
  late final RepositorioRepaso _repositorio = _repoDado ?? RepositorioRepaso();
  late final Sesion _sesion = _sesionDada ?? Sesion();

  final RepositorioRepaso? _repoDado;
  final Sesion? _sesionDada;

  /// Repositorio y sesión inyectables, como en todo el proyecto: los dos
  /// resuelven `Supabase.instance.client` en su constructor, y sin esta
  /// costura el modelo no se podría construir en un test. En producción nadie
  /// los pasa.
  ModeloRepaso({RepositorioRepaso? repositorio, Sesion? sesion})
    : _repoDado = repositorio,
      _sesionDada = sesion;

  bool get hayCuenta => _sesion.hayCuenta;

  ModoRepaso _modo = ModoRepaso.programadas;
  ModoRepaso get modo => _modo;

  Estado<DatosRepaso> _datos = const Inactivo();
  Estado<DatosRepaso> get datos => _datos;

  /// Sin cuenta no se pide nada y el estado se queda en [Inactivo]. No es un
  /// fallo ni una carga: es la pantalla diciendo que la repetición espaciada
  /// se calcula con un historial que vive en el servidor.
  Future<void> cargar() {
    if (!hayCuenta) return Future.value();

    return pedir<DatosRepaso>("datos", () async {
      // Las dos a la vez: encadenarlas sumaba dos latencias antes de pintar
      // nada. Misma razón que en Progreso, Inicio y Simulacro.
      final resultados = await Future.wait([
        switch (_modo) {
          ModoRepaso.falladas => _repositorio.falladas(),
          ModoRepaso.programadas => _repositorio.pendientes(),
        },
        _repositorio.resumen(),
      ]);
      return (
        resultados[0] as List<Pregunta>,
        resultados[1] as ResumenRepasos?,
      );
    }, (estado) => _datos = estado);
  }

  void cambiarModo(ModoRepaso nuevo) {
    if (_modo == nuevo) return;
    _modo = nuevo;
    avisar(); // el chip se marca ya, sin esperar a la respuesta
    cargar();
  }
}
