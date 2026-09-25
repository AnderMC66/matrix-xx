import "package:matr_u/data/repositories/sesion.dart";
import "package:matr_u/domain/models/sesion.dart";
import "package:matr_u/ui/core/vista_modelo.dart";

/// El modelo de la pantalla de acceso.
///
/// **Los textos escritos no están aquí.** Correo, contraseña y nombre siguen
/// en tres `TextEditingController` de la vista: son estado del campo, y
/// duplicarlos en el modelo obligaría a mantener los dos lados en sincronía
/// para no ganar nada. El modelo recibe los tres valores cuando toca enviar.
class ModeloEntrar extends VistaModelo {
  // Perezosa: resuelve `Supabase.instance.client`. Ver la nota en
  // `ModeloInicio`.
  late final Sesion _sesion = _sesionDada ?? Sesion();
  final Sesion? _sesionDada;

  ModeloEntrar({Sesion? sesion}) : _sesionDada = sesion;

  bool _registrando = false;
  bool get registrando => _registrando;

  bool _enviando = false;
  bool get enviando => _enviando;

  String? _error;
  String? get error => _error;

  String? _aviso;
  String? get aviso => _aviso;

  List<AreaPostulacion>? _areas;
  List<AreaPostulacion>? get areas => _areas;

  int? _area;
  int? get area => _area;

  /// Pide las áreas de postulación.
  ///
  /// Solo hacen falta al registrarse, así que se piden una vez y en segundo
  /// plano: un fallo de red aquí no debe bloquear el formulario de entrar, que
  /// es el camino del 90 % de las visitas. Por eso el fallo se traga.
  Future<void> cargarAreas() async {
    try {
      _areas = await _sesion.areas();
      avisar();
    } on Object catch (_) {
      // Sin áreas, el selector no se pinta y entrar sigue funcionando.
    }
  }

  void cambiarModo({required bool registrando}) {
    _registrando = registrando;
    _error = null;
    _aviso = null;
    avisar();
  }

  void elegirArea(int? id) {
    _area = id;
    avisar();
  }

  /// Entra o se registra, según el modo. Avisa a [alEntrar] si ya hay sesión.
  Future<void> enviar({
    required String correo,
    required String contrasena,
    required String nombre,
    required void Function() alEntrar,
  }) async {
    _enviando = true;
    _error = null;
    _aviso = null;
    avisar();

    try {
      if (_registrando) {
        final faltaConfirmar = await _sesion.registrarse(
          correo: correo,
          contrasena: contrasena,
          nombre: nombre,
          areaPostulacionId: _area,
        );
        if (faltaConfirmar) {
          _aviso =
              "Cuenta creada. Te enviamos un correo de confirmación: "
              "ábrelo para poder entrar.";
          return;
        }
      } else {
        await _sesion.entrar(correo, contrasena);
      }
      alEntrar();
    } on ErrorSesion catch (e) {
      _error = e.mensaje;
    } on Object catch (e) {
      _error = "No se pudo conectar. $e";
    } finally {
      _enviando = false;
      avisar();
    }
  }

  /// Manda el correo de recuperación.
  ///
  /// **El acuse es el mismo exista la cuenta o no**, y no por descuido: el
  /// servidor de auth responde igual en los dos casos a propósito, y si esto
  /// distinguiera «no hay cuenta con ese correo» de «te lo mandamos», sería un
  /// comprobador de quién está registrado que cualquiera podría usar sin tener
  /// cuenta.
  Future<void> recuperar(String correo) async {
    _enviando = true;
    _error = null;
    _aviso = null;
    avisar();

    try {
      await _sesion.recuperarContrasena(correo);
      _aviso =
          "Si hay una cuenta con ese correo, le acaba de llegar un enlace "
          "para poner una contraseña nueva. Ábrelo desde este mismo "
          "teléfono: te devuelve a la app.";
    } on ErrorSesion catch (e) {
      _error = e.mensaje;
    } on Object catch (e) {
      _error = "No se pudo conectar. $e";
    } finally {
      _enviando = false;
      avisar();
    }
  }
}
