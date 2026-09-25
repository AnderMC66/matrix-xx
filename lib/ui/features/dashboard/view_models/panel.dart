/// Los cuatro modelos del panel de staff: el resumen, la revisión de
/// preguntas, los reportes y las personas.
library;

import "package:matr_u/data/repositories/panel.dart";
import "package:matr_u/data/repositories/sesion.dart";
import "package:matr_u/domain/models/panel.dart";
import "package:matr_u/ui/core/vista_modelo.dart";

/// El rol de quien mira, y el resumen si tiene permiso para verlo.
typedef DatosPanel = (Rol? rol, ResumenPanel? resumen);

/// El resumen del panel.
class ModeloPanel extends VistaModelo {
  // Perezoso: resuelve `Supabase.instance.client`. Ver `ModeloInicio`.
  late final RepositorioPanel _repo = _repoDado ?? RepositorioPanel();
  final RepositorioPanel? _repoDado;

  ModeloPanel({RepositorioPanel? repositorio}) : _repoDado = repositorio;

  /// El repositorio, para pasárselo a las tres subpantallas. Comparten el
  /// mismo por lo mismo que en simulacro: son partes de una misma cosa.
  RepositorioPanel get repositorio => _repo;

  Estado<DatosPanel> _datos = const Inactivo();
  Estado<DatosPanel> get datos => _datos;

  Future<void> cargar() => pedir<DatosPanel>("datos", () async {
    // El rol primero: si no es staff no hay resumen que pedir, y pedirlo
    // sería un 403 garantizado contra las políticas de RLS.
    final rol = await _repo.rolActual();
    if (!esStaff(rol)) return (rol, null);
    return (rol, await _repo.resumen());
  }, (estado) => _datos = estado);
}

/// La revisión de preguntas, filtrada por estado.
class ModeloPanelRevision extends VistaModelo {
  late final RepositorioPanel _repo = _repoDado ?? RepositorioPanel();
  final RepositorioPanel? _repoDado;

  ModeloPanelRevision({
    required String filtroInicial,
    RepositorioPanel? repositorio,
  }) : _filtro = filtroInicial,
       _repoDado = repositorio;

  RepositorioPanel get repositorio => _repo;

  String _filtro;
  String get filtro => _filtro;

  Estado<List<PreguntaRevision>> _preguntas = const Inactivo();
  Estado<List<PreguntaRevision>> get preguntas => _preguntas;

  Future<void> cargar() => pedir<List<PreguntaRevision>>(
    "preguntas",
    () => _repo.paraRevision(filtro: _filtro),
    (estado) => _preguntas = estado,
  );

  void cambiarFiltro(String valor) {
    if (_filtro == valor) return;
    _filtro = valor;
    avisar(); // el chip se marca ya, sin esperar a la respuesta
    cargar();
  }
}

/// Los reportes de error, filtrados por estado.
class ModeloPanelReportes extends VistaModelo {
  late final RepositorioPanel _repo = _repoDado ?? RepositorioPanel();
  final RepositorioPanel? _repoDado;

  ModeloPanelReportes({RepositorioPanel? repositorio})
    : _repoDado = repositorio;

  RepositorioPanel get repositorio => _repo;

  String _filtro = "abierto";
  String get filtro => _filtro;

  Estado<List<ReporteStaff>> _reportes = const Inactivo();
  Estado<List<ReporteStaff>> get reportes => _reportes;

  Future<void> cargar() => pedir<List<ReporteStaff>>(
    "reportes",
    () => _repo.reportes(_filtro),
    (estado) => _reportes = estado,
  );

  void cambiarFiltro(String valor) {
    if (_filtro == valor) return;
    _filtro = valor;
    avisar();
    cargar();
  }
}

/// Las cuentas registradas y sus roles.
class ModeloPanelUsuarios extends VistaModelo {
  late final RepositorioPanel _repo = _repoDado ?? RepositorioPanel();
  late final Sesion _sesion = _sesionDada ?? Sesion();

  final RepositorioPanel? _repoDado;
  final Sesion? _sesionDada;

  ModeloPanelUsuarios({RepositorioPanel? repositorio, Sesion? sesion})
    : _repoDado = repositorio,
      _sesionDada = sesion;

  RepositorioPanel get repositorio => _repo;

  /// Quién está mirando. La fila de una persona lo usa para no dejarse
  /// cambiar el rol a sí misma.
  String? get idPropio => _sesion.usuario?.id;

  Estado<List<Persona>> _personas = const Inactivo();
  Estado<List<Persona>> get personas => _personas;

  Future<void> cargar() => pedir<List<Persona>>(
    "personas",
    _repo.personas,
    (estado) => _personas = estado,
  );
}
