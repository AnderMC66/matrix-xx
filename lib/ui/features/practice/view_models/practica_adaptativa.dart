import "package:matr_u/data/repositories/preguntas.dart";
import "package:matr_u/data/repositories/progreso.dart";
import "package:matr_u/data/repositories/repaso.dart";
import "package:matr_u/data/repositories/sesion.dart";
import "package:matr_u/data/repositories/temario.dart";
import "package:matr_u/domain/models/preguntas.dart";
import "package:matr_u/domain/models/progreso.dart";
import "package:matr_u/domain/models/temario.dart";
import "package:matr_u/ui/core/vista_modelo.dart";

class DatosAdaptativa {
  final Curso? curso;
  final List<Pregunta> preguntas;
  final List<CursoDesatendido> desatendidos;

  /// Cuántas preguntas tiene el banco del APK para este curso (o en total).
  final int enElBanco;

  /// Cuántos subtemas del curso tienen al menos una pregunta, y cuántos hay.
  final int subtemasCubiertos;
  final int subtemasTotales;

  const DatosAdaptativa({
    required this.curso,
    required this.preguntas,
    required this.desatendidos,
    required this.enElBanco,
    required this.subtemasCubiertos,
    required this.subtemasTotales,
  });
}

/// El modelo de vista de la practica adaptativa.
class ModeloAdaptativa extends VistaModelo {
  /// El curso al que se acota, o `null` para toda la app.
  final String? cursoSlug;

  // Los repositorios son `late`, no del constructor, y no es un detalle: se
  // construyen la PRIMERA VEZ que se usan. Cada uno resuelve
  // `Supabase.instance.client`, asi que armarlos en la lista de
  // inicializacion hace que crear el modelo reviente en cuanto Supabase no
  // este listo — que es justo lo que pasa mientras `Arranque` todavia
  // inicializa, y lo que rompio tres tests de `arranque_test`.
  late final RepositorioRepaso _repaso = _repasoDado ?? RepositorioRepaso();
  late final RepositorioProgreso _progreso =
      _progresoDado ?? RepositorioProgreso();
  late final RepositorioTemario _temario = _temarioDado ?? RepositorioTemario();
  late final RepositorioPreguntas _banco =
      _bancoDado ?? RepositorioPreguntas();
  late final Sesion _sesion = _sesionDada ?? Sesion();

  final RepositorioRepaso? _repasoDado;
  final RepositorioProgreso? _progresoDado;
  final RepositorioTemario? _temarioDado;
  final RepositorioPreguntas? _bancoDado;
  final Sesion? _sesionDada;

  /// Repositorios y sesion inyectables. Los tres de red resuelven
  /// `Supabase.instance.client` en su constructor; los dos de catalogo leen de
  /// los assets. En produccion nadie los pasa.
  ModeloAdaptativa({
    this.cursoSlug,
    RepositorioRepaso? repaso,
    RepositorioProgreso? progreso,
    RepositorioTemario? temario,
    RepositorioPreguntas? banco,
    Sesion? sesion,
  }) : _repasoDado = repaso,
       _progresoDado = progreso,
       _temarioDado = temario,
       _bancoDado = banco,
       _sesionDada = sesion;

  bool get hayCuenta => _sesion.hayCuenta;

  Estado<DatosAdaptativa> _datos = const Inactivo();
  Estado<DatosAdaptativa> get datos => _datos;

  Future<void> cargar() {
    if (!hayCuenta) return Future.value();
    return pedir<DatosAdaptativa>("datos", _pedir, (estado) => _datos = estado);
  }

  Future<DatosAdaptativa> _pedir() async {
    final temario = await _temario.cargar();
    final curso = cursoSlug == null ? null : temario.curso(cursoSlug!);

    // Las dos peticiones de red a la vez, y con ellas la carga del banco:
    // ninguna depende de otra, y en fila eran dos latencias sumadas más la
    // lectura de los assets. Misma razón que en Progreso, Inicio, Simulacro y
    // Repaso.
    //
    // El RPC trabaja con el código del curso (`FIS`), la pantalla con su
    // slug (`fisica`), que es lo que usa el resto de la app.
    final resultados = await Future.wait([
      _repaso.recomendadas(cursoCodigo: curso?.codigo, limite: 20),
      cursoSlug == null
          ? _progreso.cursosDesatendidos()
          : Future.value(const <CursoDesatendido>[]),
      // Cuánto cubre el banco, para no felicitar al alumno por dominar un
      // curso del que apenas hay preguntas. Sale del APK, no del servidor.
      _banco.cargar(),
    ]);
    final preguntas = resultados[0] as List<Pregunta>;
    final desatendidos = resultados[1] as List<CursoDesatendido>;
    final banco = resultados[2] as Banco;
    final conteo = banco.conteoPorSubtema();
    var cubiertos = 0;
    for (final tema in curso?.temas ?? const <Tema>[]) {
      for (final sub in tema.subtemas) {
        if ((conteo[sub.codigo] ?? 0) > 0) cubiertos++;
      }
    }

    return DatosAdaptativa(
      curso: curso,
      preguntas: preguntas,
      desatendidos: desatendidos,
      enElBanco: curso == null ? banco.total : banco.deCurso(curso.slug).length,
      subtemasCubiertos: cubiertos,
      subtemasTotales: curso?.totalSubtemas ?? 0,
    );
  }
}
