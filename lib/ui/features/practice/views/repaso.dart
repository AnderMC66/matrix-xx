import "package:flutter/material.dart";
import "package:matr_u/core/utils/fechas.dart";
import "package:matr_u/domain/models/preguntas.dart";
import "package:matr_u/domain/models/repaso.dart";
import "package:matr_u/ui/core/theme/tema.dart";
import "package:matr_u/ui/core/vista_modelo.dart";
import "package:matr_u/ui/core/widgets/aviso.dart";
import "package:matr_u/ui/features/practice/view_models/repaso.dart";
import "package:matr_u/ui/features/practice/views/practica.dart";

/// `/repaso` — dos formas de repasar en una pantalla.
///
/// Réplica de `src/app/repaso/page.tsx`, incluida la razón de que las dos
/// convivan: responden a la misma pregunta —«¿qué me conviene volver a
/// ver?»— con criterios distintos. `Falladas` es lo que un alumno busca el día
/// antes del examen; `Programadas hoy` es lo que sostiene la retención a lo
/// largo de semanas.
///
/// La tanda la resuelve `SesionPractica`, el mismo widget que usa Práctica,
/// exactamente como la web reutiliza `<SesionPractica>` aquí: un repaso *es*
/// una práctica, solo cambia de dónde sale la lista de preguntas.
class PantallaRepaso extends StatefulWidget {
  /// El modelo de vista, inyectable. Si no llega, la pantalla construye el
  /// suyo con los repositorios de producción — el mismo patrón `?? X()` de
  /// siempre, ahora un nivel más arriba.
  final ModeloRepaso? modelo;

  const PantallaRepaso({super.key, this.modelo});

  @override
  State<PantallaRepaso> createState() => _PantallaRepasoState();
}

class _PantallaRepasoState extends State<PantallaRepaso> {
  late final ModeloRepaso _modelo = widget.modelo ?? ModeloRepaso();

  @override
  void initState() {
    super.initState();
    _modelo.cargar();
  }

  /// La pantalla libera el modelo SIEMPRE, tambien el inyectado.
  ///
  /// La primera version solo liberaba el que ella construia —«el inyectado es
  /// de quien lo paso»— y eso dejo el temporizador de Horario vivo despues de
  /// desmontar el arbol: «A Timer is still pending even after the widget tree
  /// was disposed». Quien inyecta un modelo se lo esta entregando a esta
  /// pantalla; leer sus campos despues sigue funcionando, lo unico que un
  /// `ChangeNotifier` liberado no admite es que alguien se suscriba.
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
        return const _SinCuenta(
          titulo: "El repaso necesita tu cuenta",
          detalle:
              "La repetición espaciada se calcula con tu historial de "
              "respuestas, que vive en el servidor.",
        );
      }

      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                for (final m in ModoRepaso.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        m == ModoRepaso.programadas
                            ? "Programadas hoy"
                            : "Falladas",
                      ),
                      selected: _modelo.modo == m,
                      onSelected: (_) => _modelo.cambiarModo(m),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: SegunEstado<DatosRepaso>(
              estado: _modelo.datos,
              tituloDelFallo: "No se pudo cargar el repaso",
              alReintentar: _modelo.cargar,
              cuandoListo: (datos) {
                final (preguntas, resumen) = datos;
                if (preguntas.isEmpty) {
                  return _Vacio(modo: _modelo.modo, resumen: resumen);
                }
                return _Portada(
                  modo: _modelo.modo,
                  preguntas: preguntas,
                  resumen: resumen,
                  alTerminar: _modelo.cargar,
                );
              },
            ),
          ),
        ],
      );
    },
  );
}

/// La antesala de la tanda: cuántas hay y qué significan, con el botón que
/// abre la sesión. La web lo resuelve mostrando la sesión directamente porque
/// la cabecera de la página ya explica el modo; aquí esa cabecera no existe,
/// y entrar de golpe a una pregunta sin decir cuántas hay desorienta.
class _Portada extends StatelessWidget {
  final ModoRepaso modo;
  final List<Pregunta> preguntas;
  final ResumenRepasos? resumen;
  final VoidCallback alTerminar;

  const _Portada({
    required this.modo,
    required this.preguntas,
    required this.resumen,
    required this.alTerminar,
  });

  @override
  Widget build(BuildContext context) {
    final falladas = modo == ModoRepaso.falladas;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text(
          falladas ? "Lo que sigues fallando" : "Toca repasar hoy",
          style: context.textos.headlineSmall!.copyWith(
            fontWeight: FontWeight.w700,
            color: context.esquema.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          falladas
              ? "Preguntas cuya última respuesta fue incorrecta. Si la "
                    "aciertas, sale de esta lista."
              : "Repetición espaciada: cada acierto aleja la siguiente vez "
                    "que te la preguntamos; cada fallo la trae de vuelta "
                    "mañana.",
          style: context.textos.bodyMedium!.copyWith(
            color: context.esquema.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: context.esquema.secondaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Text(
                "${preguntas.length}",
                style: context.textos.displaySmall!.copyWith(
                  fontWeight: FontWeight.w800,
                  color: context.esquema.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  preguntas.length == 1
                      ? "pregunta esperándote"
                      : "preguntas esperándote",
                  style: context.textos.bodyMedium!.copyWith(
                    color: context.esquema.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (resumen case final r? when r.pendientesHoy > 0 && falladas) ...[
          const SizedBox(height: 12),
          Text(
            "Además tienes ${r.pendientesHoy} programadas para hoy.",
            style: context.textos.bodyMedium!.copyWith(
              color: context.esquema.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 22),
        FilledButton(
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SesionPractica(
                  titulo: falladas ? "Repaso de falladas" : "Repaso de hoy",
                  preguntas: preguntas,
                  etiquetaSalida: "Volver al repaso",
                ),
              ),
            );
            // Al volver, el calendario ya cambió: lo que se acertó sale de la
            // lista y lo fallado vuelve mañana. Recargar es lo único honesto.
            alTerminar();
          },
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: const Text("Empezar"),
        ),
      ],
    );
  }
}

/// Un repaso vacío no es un error: en el modo programado es literalmente el
/// objetivo. El mensaje lo dice así y ofrece la siguiente acción útil, en vez
/// de dejar la pantalla muerta.
class _Vacio extends StatelessWidget {
  final ModoRepaso modo;
  final ResumenRepasos? resumen;

  const _Vacio({required this.modo, required this.resumen});

  @override
  Widget build(BuildContext context) {
    final falladas = modo == ModoRepaso.falladas;
    final sinHistorial = resumen?.sinHistorial ?? true;

    final titulo = sinHistorial
        ? "Todavía no hay nada que repasar"
        : falladas
        ? "No tienes preguntas falladas pendientes"
        : "Estás al día";

    final detalle = sinHistorial
        ? "Responde algunas preguntas y aquí aparecerán las que conviene "
              "volver a ver."
        : falladas
        ? "Todo lo que fallaste alguna vez lo has vuelto a acertar después."
        : resumen?.proximaFecha != null
        ? "El próximo repaso te toca el ${fechaLarga(resumen!.proximaFecha!)}."
        : "No hay repasos programados para hoy.";

    return Aviso(
      icono: sinHistorial ? Icons.inbox_outlined : Icons.check_circle_outline,
      titulo: titulo,
      detalle: detalle,
    );
  }
}

class _SinCuenta extends StatelessWidget {
  final String titulo;
  final String detalle;
  const _SinCuenta({required this.titulo, required this.detalle});

  @override
  Widget build(BuildContext context) => Aviso(
    icono: Icons.lock_outline,
    titulo: titulo,
    detalle: "$detalle\n\nUsa el botón de entrar, arriba a la derecha.",
  );
}
