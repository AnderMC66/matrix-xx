import "dart:async";

import "package:matr_u/data/repositories/horario.dart";
import "package:matr_u/data/repositories/progreso.dart";
import "package:matr_u/data/repositories/repaso.dart";
import "package:matr_u/data/repositories/sesion.dart";
import "package:matr_u/domain/models/horario.dart";
import "package:matr_u/domain/models/progreso.dart";
import "package:matr_u/domain/models/repaso.dart";
import "package:matr_u/ui/core/vista_modelo.dart";

/// Lo que la portada enseña de quien ha entrado.
///
/// **No son las cifras de un expediente.** No hay «cursos activos» ni
/// «promedio»: esto no es un aula virtual, es preparación para un examen de
/// admisión, y lo que mueve el estudio aquí es el acierto por subtema, la
/// constancia y qué toca repasar hoy.
class PanelPersonal {
  final Diagnostico diagnostico;
  final Racha? racha;
  final ResumenRepasos? repasos;
  final ({BloqueHorario bloque, DateTime cuando})? proximo;
  final CursoDesatendido? descuidado;
  final Perfil? perfil;

  const PanelPersonal({
    required this.diagnostico,
    required this.racha,
    required this.repasos,
    required this.proximo,
    required this.descuidado,
    required this.perfil,
  });
}

/// El modelo de vista de la portada.
class ModeloInicio extends VistaModelo {
  // Los repositorios son `late`, no del constructor, y no es un detalle: se
  // construyen la PRIMERA VEZ que se usan. Cada uno resuelve
  // `Supabase.instance.client`, asi que armarlos en la lista de
  // inicializacion hace que crear el modelo reviente en cuanto Supabase no
  // este listo — que es justo lo que pasa mientras `Arranque` todavia
  // inicializa, y lo que rompio tres tests de `arranque_test`.
  late final Sesion _sesion = _sesionDada ?? Sesion();
  late final RepositorioProgreso _progreso =
      _progresoDado ?? RepositorioProgreso();
  late final RepositorioRepaso _repasos = _repasosDados ?? RepositorioRepaso();
  late final RepositorioHorario _horario =
      _horarioDado ?? RepositorioHorario();

  final Sesion? _sesionDada;
  final RepositorioProgreso? _progresoDado;
  final RepositorioRepaso? _repasosDados;
  final RepositorioHorario? _horarioDado;

  StreamSubscription<dynamic>? _escucha;

  /// De quién es el panel que hay publicado, o `null` si no hay sesión.
  String? _duenoDelPanel;

  ModeloInicio({
    Sesion? sesion,
    RepositorioProgreso? progreso,
    RepositorioRepaso? repasos,
    RepositorioHorario? horario,
  }) : _sesionDada = sesion,
       _progresoDado = progreso,
       _repasosDados = repasos,
       _horarioDado = horario;

  bool get hayCuenta => _sesion.hayCuenta;

  Estado<PanelPersonal> _panel = const Inactivo();
  Estado<PanelPersonal> get panel => _panel;

  /// Arranca el modelo: carga si hay sesión y se queda escuchando los cambios.
  ///
  /// **Sin esto, entrar no cambiaba nada de la portada.** Leía `hayCuenta` una
  /// sola vez y `PantallaEntrar` se abre ENCIMA: al cerrarse tras un acceso
  /// correcto, la portada seguía diciendo «Crear cuenta o entrar» con la
  /// sesión ya iniciada, y había que salir y volver.
  void arrancar() {
    if (hayCuenta) {
      _duenoDelPanel = _sesion.usuario!.id;
      cargar();
    }

    _escucha = _sesion.cambios.listen((_) {
      // Solo cuando cambia DE QUIÉN es la sesión.
      //
      // El flujo emite mucho más que entrar y salir: al suscribirse suelta ya
      // un `initialSession`, y después un `tokenRefreshed` cada hora. Sin este
      // filtro, abrir la app con sesión pedía el panel dos veces.
      final ahora = _sesion.usuario?.id;
      if (ahora == _duenoDelPanel) return;
      _duenoDelPanel = ahora;

      if (ahora == null) {
        _panel = const Inactivo();
        avisar();
      } else {
        cargar();
      }
    });
  }

  @override
  void dispose() {
    _escucha?.cancel();
    super.dispose();
  }

  Future<void> cargar() {
    if (!hayCuenta) return Future.value();
    return pedir<PanelPersonal>("panel", _pedir, (estado) => _panel = estado);
  }

  Future<PanelPersonal> _pedir() async {
    // Las seis a la vez: ninguna depende de otra, y encadenarlas sumaba seis
    // latencias antes de que la portada enseñara nada. Ver la nota equivalente
    // en el modelo de Progreso.
    final resultados = await Future.wait([
      _progreso.diagnostico(),
      _progreso.racha(),
      _repasos.resumen(),
      _horario.obtener(),
      _progreso.cursosDesatendidos(),
      _progreso.perfil(),
    ]);

    final diagnostico = resultados[0] as Diagnostico;
    final racha = resultados[1] as Racha?;
    final resumenRepasos = resultados[2] as ResumenRepasos?;
    final horario = resultados[3] as List<BloqueHorario>;
    final desatendidos = resultados[4] as List<CursoDesatendido>;
    final perfil = resultados[5] as Perfil?;

    // Aviso dirigido: el curso más flojo que además lleva días sin tocarse.
    // El umbral de 2 días evita regañar a quien practicó ayer; el de 70 %
    // evita llamar «flojo» a un curso que va bien. Mismos números que la web.
    CursoDesatendido? descuidado;
    for (final c in desatendidos) {
      if (c.porcentaje != null &&
          c.porcentaje! < 70 &&
          c.diasSinPracticar >= 2) {
        descuidado = c;
        break;
      }
    }

    return PanelPersonal(
      diagnostico: diagnostico,
      racha: racha,
      repasos: resumenRepasos,
      proximo: proximoBloque(horario, DateTime.now()),
      descuidado: descuidado,
      perfil: perfil,
    );
  }
}
