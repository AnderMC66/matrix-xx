import "package:flutter/gestures.dart";
import "package:flutter/material.dart";

import "../datos/preguntas.dart";
import "../datos/progreso.dart";
import "../datos/repaso.dart";
import "../datos/sesion.dart";
import "../datos/temario.dart";
import "../tema.dart";
import "../widgets/aviso.dart";
import "practica.dart";

/// `/practica/adaptativa` — práctica que elige las preguntas por ti.
///
/// Réplica de `src/app/practica/adaptativa/page.tsx`: primero los subtemas
/// donde peor vas, y dentro de ellos lo que nunca viste o fallaste, de menor
/// a mayor dificultad. Lo que ya dominas no vuelve a salir aquí.
///
/// [cursoSlug] la acota a un curso; `null` mezcla todo el banco — mismo
/// contrato que el parámetro `?curso=` de la web.
class PantallaPracticaAdaptativa extends StatefulWidget {
  final String? cursoSlug;
  const PantallaPracticaAdaptativa({super.key, this.cursoSlug});

  @override
  State<PantallaPracticaAdaptativa> createState() =>
      _PantallaPracticaAdaptativaState();
}

class _PantallaPracticaAdaptativaState
    extends State<PantallaPracticaAdaptativa> {
  final _repaso = RepositorioRepaso();
  final _progreso = RepositorioProgreso();
  final _sesion = Sesion();

  Future<_Datos>? _carga;

  @override
  void initState() {
    super.initState();
    if (_sesion.hayCuenta) _carga = _pedir();
  }

  Future<_Datos> _pedir() async {
    final temario = await RepositorioTemario().cargar();
    final curso = widget.cursoSlug == null
        ? null
        : temario.curso(widget.cursoSlug!);

    // El RPC trabaja con el código del curso (`FIS`), la pantalla con su
    // slug (`fisica`), que es lo que usa el resto de la app.
    final preguntas = await _repaso.recomendadas(
      cursoCodigo: curso?.codigo,
      limite: 20,
    );
    final desatendidos = widget.cursoSlug == null
        ? await _progreso.cursosDesatendidos()
        : const <CursoDesatendido>[];

    // Cuánto cubre el banco, para no felicitar al alumno por dominar un curso
    // del que apenas hay preguntas. Sale del APK, no del servidor.
    final banco = await RepositorioPreguntas().cargar();
    final conteo = banco.conteoPorSubtema();
    var cubiertos = 0;
    for (final tema in curso?.temas ?? const <Tema>[]) {
      for (final sub in tema.subtemas) {
        if ((conteo[sub.codigo] ?? 0) > 0) cubiertos++;
      }
    }

    return _Datos(
      curso: curso,
      preguntas: preguntas,
      desatendidos: desatendidos,
      enElBanco: curso == null ? banco.total : banco.deCurso(curso.slug).length,
      subtemasCubiertos: cubiertos,
      subtemasTotales: curso?.totalSubtemas ?? 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_sesion.hayCuenta) {
      return const Aviso(
        icono: Icons.lock_outline,
        titulo: "La práctica adaptativa necesita tu cuenta",
        detalle:
            "Elige las preguntas según tu historial de respuestas, que vive "
            "en el servidor.\n\nUsa el botón de entrar, arriba a la derecha.",
      );
    }

    return FutureBuilder<_Datos>(
      future: _carga,
      builder: (context, snap) {
        if (snap.hasError) {
          return Aviso(
            icono: Icons.cloud_off_outlined,
            titulo: "No se pudo cargar",
            detalle: "${snap.error}",
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final datos = snap.data!;
        final curso = datos.curso;

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Text(
              curso != null
                  ? "${curso.nombre}, a tu medida"
                  : "Lo que más te conviene ahora",
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Paleta.texto,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Elegimos las preguntas por ti: empiezan por los subtemas "
              "donde peor vas, y lo que ya dominas no vuelve a salir.",
              style: TextStyle(
                fontSize: 13,
                color: Paleta.textoSuave,
                height: 1.5,
              ),
            ),
            if (curso == null && datos.desatendidos.isNotEmpty) ...[
              const SizedBox(height: 16),
              _AvisoMasFlojo(curso: datos.desatendidos.first),
            ],
            const SizedBox(height: 22),
            if (datos.preguntas.isEmpty)
              _NadaPendiente(
                curso: curso,
                enElBanco: datos.enElBanco,
                subtemasCubiertos: datos.subtemasCubiertos,
                subtemasTotales: datos.subtemasTotales,
              )
            else
              _EmpezarSesion(curso: curso, preguntas: datos.preguntas),
            if (curso != null) ...[
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => const PantallaPracticaAdaptativa(),
                    ),
                  ),
                  child: const Text("Practicar de todos los cursos"),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Datos {
  final Curso? curso;
  final List<Pregunta> preguntas;
  final List<CursoDesatendido> desatendidos;

  /// Cuántas preguntas tiene el banco del APK para este curso (o en total).
  final int enElBanco;

  /// Cuántos subtemas del curso tienen al menos una pregunta, y cuántos hay.
  final int subtemasCubiertos;
  final int subtemasTotales;

  const _Datos({
    required this.curso,
    required this.preguntas,
    required this.desatendidos,
    required this.enElBanco,
    required this.subtemasCubiertos,
    required this.subtemasTotales,
  });
}

/// «Tu curso más flojo ahora es X», con X pulsable.
///
/// Es `StatefulWidget` por el `TapGestureRecognizer`, no por tener estado.
/// Un reconocedor dentro de un `TextSpan` hay que liberarlo —lo dice la
/// documentación de `TextSpan.recognizer`— y creándolo dentro de `build` se
/// fabricaba uno nuevo en cada reconstrucción sin soltar el anterior. Esta
/// pantalla se reconstruye al girar el móvil, al abrirse el teclado y en cada
/// `setState`, así que la fuga no era teórica.
class _AvisoMasFlojo extends StatefulWidget {
  final CursoDesatendido curso;
  const _AvisoMasFlojo({required this.curso});

  @override
  State<_AvisoMasFlojo> createState() => _AvisoMasFlojoState();
}

class _AvisoMasFlojoState extends State<_AvisoMasFlojo> {
  late final TapGestureRecognizer _pulsar = TapGestureRecognizer()
    ..onTap = () => Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            PantallaPracticaAdaptativa(cursoSlug: widget.curso.slug),
      ),
    );

  @override
  void dispose() {
    _pulsar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Paleta.superficie,
      border: Border.all(color: Paleta.borde),
      borderRadius: BorderRadius.circular(12),
    ),
    child: RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 13.5,
          height: 1.5,
          color: Paleta.textoSuave,
        ),
        children: [
          const TextSpan(text: "Tu curso más flojo ahora es "),
          TextSpan(
            text: widget.curso.nombre,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Paleta.acento,
            ),
            recognizer: _pulsar,
          ),
          if (widget.curso.porcentaje != null)
            TextSpan(text: " (${widget.curso.porcentaje} % de acierto)."),
        ],
      ),
    ),
  );
}

class _EmpezarSesion extends StatelessWidget {
  final Curso? curso;
  final List<Pregunta> preguntas;
  const _EmpezarSesion({required this.curso, required this.preguntas});

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: () => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SesionPractica(
          titulo: curso?.nombre ?? "Práctica adaptativa",
          preguntas: preguntas,
        ),
      ),
    ),
    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
    child: Text(
      "Empezar · ${preguntas.length} ${preguntas.length == 1 ? "pregunta" : "preguntas"}",
    ),
  );
}

/// Cuando la adaptativa no tiene nada que recomendar.
///
/// **Decía «Has acertado todo lo que hay en el banco» y eso se lee como “ya
/// dominas este curso”.** No es lo mismo: el banco cubre hoy el 21,5 % del
/// sílabo, y hay cursos como Álgebra con 6 preguntas repartidas en 3 de sus
/// 60 subtemas. Felicitar a alguien por terminarlas, sin decirle cuántas
/// eran, le hace creer que puede pasar a otra cosa — justo antes del examen
/// que decide su cupo.
///
/// Las cifras salen del banco del APK, que ya está cargado, así que decir la
/// verdad no cuesta ninguna petición.
class _NadaPendiente extends StatelessWidget {
  final Curso? curso;
  final int enElBanco;
  final int subtemasCubiertos;
  final int subtemasTotales;

  const _NadaPendiente({
    required this.curso,
    required this.enElBanco,
    required this.subtemasCubiertos,
    required this.subtemasTotales,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 34),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Paleta.borde),
    ),
    child: Column(
      children: [
        Text(
          curso != null
              ? "Nada pendiente en ${curso!.nombre}"
              : "Nada pendiente por ahora",
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: Paleta.texto,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          enElBanco == 0
              ? "Todavía no hay preguntas de este curso en el banco."
              : "Ya respondiste bien "
                    "${enElBanco == 1 ? "la única pregunta" : "las $enElBanco preguntas"}"
                    "${curso != null ? " que hay de este curso" : " del banco"}."
                    " Vuelve por los repasos programados para no olvidarlo.",
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: Paleta.textoSuave,
            height: 1.5,
          ),
        ),
        // La cobertura del sílabo es lo que impide leer esto como «curso
        // terminado». Solo se enseña si hay hueco que enseñar.
        if (curso != null &&
            subtemasTotales > 0 &&
            subtemasCubiertos < subtemasTotales) ...[
          const SizedBox(height: 10),
          Text(
            "Ojo: el banco cubre $subtemasCubiertos de los $subtemasTotales "
            "subtemas del sílabo en ${curso!.nombre}. Lo que falta hay que "
            "estudiarlo en la teoría.",
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              color: Paleta.aviso,
              height: 1.45,
            ),
          ),
        ],
      ],
    ),
  );
}
