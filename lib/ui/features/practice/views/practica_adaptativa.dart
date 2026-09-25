import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:matr_u/domain/models/preguntas.dart";
import "package:matr_u/domain/models/progreso.dart";
import "package:matr_u/domain/models/temario.dart";
import "package:matr_u/ui/core/theme/tema.dart";
import "package:matr_u/ui/core/vista_modelo.dart";
import "package:matr_u/ui/core/widgets/aviso.dart";
import "package:matr_u/ui/features/practice/view_models/practica_adaptativa.dart";
import "package:matr_u/ui/features/practice/views/practica.dart";

/// La misma pantalla, con su propia barra, para cuando se empuja como ruta.
///
/// [PantallaPracticaAdaptativa] no trae `Scaffold` porque también se muestra
/// dentro del armazón, que ya pone uno. Este envoltorio existía duplicado
/// palabra por palabra en `inicio.dart` y en `practica.dart`; vive aquí, que
/// es donde vive la pantalla que envuelve.
class AdaptativaConBarra extends StatelessWidget {
  final ModeloAdaptativa? modelo;

  const AdaptativaConBarra({super.key, this.modelo});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("Práctica adaptativa")),
    body: PantallaPracticaAdaptativa(modelo: modelo),
  );
}

/// `/practica/adaptativa` — práctica que elige las preguntas por ti.
///
/// Réplica de `src/app/practica/adaptativa/page.tsx`: primero los subtemas
/// donde peor vas, y dentro de ellos lo que nunca viste o fallaste, de menor
/// a mayor dificultad. Lo que ya dominas no vuelve a salir aquí.
///
/// [PantallaPracticaAdaptativa.cursoSlug] la acota a un curso; `null` mezcla
/// todo el banco — mismo contrato que el parámetro `?curso=` de la web.
class PantallaPracticaAdaptativa extends StatefulWidget {
  /// El modelo de vista, inyectable. Si no llega, la pantalla construye el
  /// suyo con los repositorios de producción.
  final ModeloAdaptativa? modelo;

  /// El curso al que se acota. Solo se usa cuando no llega [modelo]: quien
  /// inyecta uno ya le ha dicho a cuál.
  final String? cursoSlug;

  const PantallaPracticaAdaptativa({super.key, this.cursoSlug, this.modelo});

  @override
  State<PantallaPracticaAdaptativa> createState() =>
      _PantallaPracticaAdaptativaState();
}

class _PantallaPracticaAdaptativaState
    extends State<PantallaPracticaAdaptativa> {
  late final ModeloAdaptativa _modelo =
      widget.modelo ?? ModeloAdaptativa(cursoSlug: widget.cursoSlug);

  @override
  void initState() {
    super.initState();
    _modelo.cargar();
  }

  @override
  void dispose() {
    _modelo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _modelo,
    builder: (context, _) {
      if (!_modelo.hayCuenta) {
        return const Aviso(
          icono: Icons.lock_outline,
          titulo: "La práctica adaptativa necesita tu cuenta",
          detalle:
              "Elige las preguntas según tu historial de respuestas, que vive "
              "en el servidor.\n\nUsa el botón de entrar, arriba a la derecha.",
        );
      }

      return SegunEstado<DatosAdaptativa>(
        estado: _modelo.datos,
        tituloDelFallo: "No se pudo cargar",
        alReintentar: _modelo.cargar,
        cuandoListo: (datos) {
          final curso = datos.curso;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              Text(
                curso != null
                    ? "${curso.nombre}, a tu medida"
                    : "Lo que más te conviene ahora",
                style: context.textos.headlineSmall!.copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.esquema.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Elegimos las preguntas por ti: empiezan por los subtemas "
                "donde peor vas, y lo que ya dominas no vuelve a salir.",
                style: context.textos.bodyMedium!.copyWith(
                  color: context.esquema.onSurfaceVariant,
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
    },
  );
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
      color: context.esquema.surfaceContainerLow,
      border: Border.all(color: context.esquema.outlineVariant),
      borderRadius: BorderRadius.circular(12),
    ),
    child: RichText(
      text: TextSpan(
        style: context.textos.bodyMedium!.copyWith(
          color: context.esquema.onSurfaceVariant,
        ),
        children: [
          const TextSpan(text: "Tu curso más flojo ahora es "),
          TextSpan(
            text: widget.curso.nombre,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: context.esquema.primary,
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
      border: Border.all(color: context.esquema.outlineVariant),
    ),
    child: Column(
      children: [
        Text(
          curso != null
              ? "Nada pendiente en ${curso!.nombre}"
              : "Nada pendiente por ahora",
          style: context.textos.titleMedium!.copyWith(
            fontWeight: FontWeight.w700,
            color: context.esquema.onSurface,
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
          style: context.textos.bodyMedium!.copyWith(
            color: context.esquema.onSurfaceVariant,
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
            style: context.textos.bodySmall!.copyWith(
              color: context.colores.aviso,
            ),
          ),
        ],
      ],
    ),
  );
}
