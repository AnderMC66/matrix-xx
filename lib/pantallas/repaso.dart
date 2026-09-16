import "package:flutter/material.dart";

import "../datos/preguntas.dart";
import "../datos/repaso.dart";
import "../datos/sesion.dart";
import "../fechas.dart";
import "../tema.dart";
import "../widgets/aviso.dart";
import "practica.dart";

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
  /// Repositorio y sesión inyectables, igual que en `PantallaHorario`. Los dos
  /// resuelven `Supabase.instance.client` en su constructor. En producción
  /// nadie los pasa.
  final RepositorioRepaso? repositorio;
  final Sesion? sesion;

  const PantallaRepaso({super.key, this.repositorio, this.sesion});

  @override
  State<PantallaRepaso> createState() => _PantallaRepasoState();
}

enum _Modo { programadas, falladas }

class _PantallaRepasoState extends State<PantallaRepaso> {
  late final _repo = widget.repositorio ?? RepositorioRepaso();
  late final _sesion = widget.sesion ?? Sesion();

  _Modo _modo = _Modo.programadas;
  Future<(List<Pregunta>, ResumenRepasos?)>? _carga;

  @override
  void initState() {
    super.initState();
    _recargar();
  }

  void _recargar() {
    if (!_sesion.hayCuenta) return;
    setState(() {
      // Las dos a la vez: la lista de preguntas y el resumen del calendario
      // no dependen entre sí, y encadenarlas sumaba dos latencias antes de
      // pintar nada. Misma razón que en Progreso, Inicio y Simulacro.
      _carga = () async {
        final resultados = await Future.wait([
          switch (_modo) {
            _Modo.falladas => _repo.falladas(),
            _Modo.programadas => _repo.pendientes(),
          },
          _repo.resumen(),
        ]);
        return (
          resultados[0] as List<Pregunta>,
          resultados[1] as ResumenRepasos?,
        );
      }();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_sesion.hayCuenta) {
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
              for (final m in _Modo.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      m == _Modo.programadas ? "Programadas hoy" : "Falladas",
                    ),
                    selected: _modo == m,
                    onSelected: (_) {
                      if (_modo == m) return;
                      _modo = m;
                      _recargar();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<(List<Pregunta>, ResumenRepasos?)>(
            future: _carga,
            builder: (context, snap) {
              if (snap.hasError) {
                return Aviso(
                  icono: Icons.cloud_off_outlined,
                  titulo: "No se pudo cargar el repaso",
                  detalle: "${snap.error}",
                  accion: ("Reintentar", _recargar),
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final (preguntas, resumen) = snap.data!;
              if (preguntas.isEmpty) {
                return _Vacio(modo: _modo, resumen: resumen);
              }

              return _Portada(
                modo: _modo,
                preguntas: preguntas,
                resumen: resumen,
                alTerminar: _recargar,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// La antesala de la tanda: cuántas hay y qué significan, con el botón que
/// abre la sesión. La web lo resuelve mostrando la sesión directamente porque
/// la cabecera de la página ya explica el modo; aquí esa cabecera no existe,
/// y entrar de golpe a una pregunta sin decir cuántas hay desorienta.
class _Portada extends StatelessWidget {
  final _Modo modo;
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
    final falladas = modo == _Modo.falladas;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text(
          falladas ? "Lo que sigues fallando" : "Toca repasar hoy",
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: Paleta.texto,
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
          style: const TextStyle(
            color: Paleta.textoSuave,
            fontSize: 13.5,
            height: 1.55,
          ),
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Paleta.acentoSuave,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Text(
                "${preguntas.length}",
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: Paleta.acento,
                  height: 1,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  preguntas.length == 1
                      ? "pregunta esperándote"
                      : "preguntas esperándote",
                  style: const TextStyle(
                    fontSize: 14,
                    color: Paleta.acento,
                    height: 1.35,
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
            style: const TextStyle(fontSize: 13, color: Paleta.textoTenue),
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
  final _Modo modo;
  final ResumenRepasos? resumen;

  const _Vacio({required this.modo, required this.resumen});

  @override
  Widget build(BuildContext context) {
    final falladas = modo == _Modo.falladas;
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
