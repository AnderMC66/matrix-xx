import "package:matr_u/data/repositories/horario.dart";
import "package:matr_u/data/repositories/progreso.dart";
import "package:matr_u/data/repositories/repaso.dart";
import "package:matr_u/data/repositories/sesion.dart";
import "package:matr_u/domain/models/horario.dart";
import "package:matr_u/domain/models/progreso.dart";
import "package:matr_u/domain/models/repaso.dart";
import "package:matr_u/ui/core/vista_modelo.dart";

/// Lo que Progreso enseña de una vez. Era `_Datos`, privado de la vista.
typedef DatosProgreso = (
  Perfil?,
  Racha?,
  ResumenRepasos?,
  List<BloqueHorario>,
  Diagnostico,
  List<ReporteResuelto>,
);

/// El modelo de vista de `/progreso`.
class ModeloProgreso extends VistaModelo {
  // Perezosos a propósito: cada uno resuelve `Supabase.instance.client`, y
  // construirlos al crear el modelo lo haría reventar mientras `Arranque`
  // todavía inicializa. Ver la nota en `ModeloInicio`.
  late final RepositorioProgreso _repo = _repoDado ?? RepositorioProgreso();
  late final RepositorioRepaso _repasos = _repasosDados ?? RepositorioRepaso();
  late final RepositorioHorario _horario = _horarioDado ?? RepositorioHorario();
  late final Sesion _sesion = _sesionDada ?? Sesion();

  final RepositorioProgreso? _repoDado;
  final RepositorioRepaso? _repasosDados;
  final RepositorioHorario? _horarioDado;
  final Sesion? _sesionDada;

  ModeloProgreso({
    RepositorioProgreso? progreso,
    RepositorioRepaso? repasos,
    RepositorioHorario? horario,
    Sesion? sesion,
  }) : _repoDado = progreso,
       _repasosDados = repasos,
       _horarioDado = horario,
       _sesionDada = sesion;

  bool get hayCuenta => _sesion.hayCuenta;

  /// El correo de quien ha entrado, para la cabecera.
  String? get correo => _repo.usuario?.email;

  Estado<DatosProgreso> _datos = const Inactivo();
  Estado<DatosProgreso> get datos => _datos;

  Future<void> cargar() {
    if (!hayCuenta) return Future.value();
    return pedir<DatosProgreso>("datos", _pedir, (estado) => _datos = estado);
  }

  /// Las seis peticiones salen A LA VEZ, no una detrás de otra.
  ///
  /// Escrito como seis `await` seguidos, cada una esperaba a que terminara la
  /// anterior: seis viajes de ida y vuelta encadenados contra Supabase para
  /// pintar una pantalla cuyos seis datos no dependen entre sí. En el wifi de
  /// casa se nota poco; en los datos móviles con los que se estudia en el
  /// micro, son seis latencias sumadas cada vez que se abre Progreso.
  ///
  /// `Future.wait` las lanza juntas y espera a la más lenta, así que el coste
  /// pasa de la suma al máximo. Si alguna falla, propaga el error igual que
  /// antes y la vista enseña su aviso con «Reintentar».
  Future<DatosProgreso> _pedir() async {
    final resultados = await Future.wait([
      _repo.perfil(),
      _repo.racha(),
      _repasos.resumen(),
      _horario.obtener(),
      _repo.diagnostico(),
      _repo.reportesResueltos(),
    ]);

    return (
      resultados[0] as Perfil?,
      resultados[1] as Racha?,
      resultados[2] as ResumenRepasos?,
      resultados[3] as List<BloqueHorario>,
      resultados[4] as Diagnostico,
      resultados[5] as List<ReporteResuelto>,
    );
  }

  /// Elimina la cuenta. Devuelve el error si lo hubo, o `null` si se borró.
  ///
  /// La vista solo necesita saber si enseñar el `SnackBar`, así que el error
  /// vuelve como valor en vez de propagarse: la pantalla no tiene que envolver
  /// la llamada en su propio `try`.
  ///
  /// No se expone la `Sesion` entera para que el widget del boton la use: un
  /// modelo de vista esta justo para que la vista no tenga que tocar un
  /// repositorio.
  Future<Object?> eliminarCuenta() async {
    try {
      await _sesion.eliminarCuenta();
      return null;
    } on Object catch (error) {
      return error;
    }
  }

  /// Acusa recibo de los reportes ya resueltos y recarga.
  ///
  /// Si el RPC falla no hay nada que decirle al alumno: el acuse de «ya lo vi»
  /// no es información suya, y el aviso seguirá ahí la próxima vez, que es
  /// exactamente lo correcto.
  Future<void> marcarReportesVistos() async {
    try {
      await _repo.marcarReportesVistos();
    } on Object catch (_) {
      return;
    }
    await cargar();
  }
}
