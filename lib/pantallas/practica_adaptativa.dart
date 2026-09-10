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

    return _Datos(
      curso: curso,
      preguntas: preguntas,
      desatendidos: desatendidos,
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
              _NadaPendiente(curso: curso)
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

  const _Datos({
    required this.curso,
    required this.preguntas,
    required this.desatendidos,
  });
}

class _AvisoMasFlojo extends StatelessWidget {
  final CursoDesatendido curso;
  const _AvisoMasFlojo({required this.curso});

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
            text: curso.nombre,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Paleta.acento,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) =>
                      PantallaPracticaAdaptativa(cursoSlug: curso.slug),
                ),
              ),
          ),
          if (curso.porcentaje != null)
            TextSpan(text: " (${curso.porcentaje} % de acierto)."),
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

class _NadaPendiente extends StatelessWidget {
  final Curso? curso;
  const _NadaPendiente({required this.curso});

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
          "Has acertado todo lo que hay en el banco"
          "${curso != null ? " de este curso" : ""}. Vuelve por los "
          "repasos programados para no olvidarlo.",
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: Paleta.textoSuave,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}
