import "package:flutter/material.dart";

import "package:matr_u/data/models/preguntas.dart";
import "package:matr_u/data/models/temario.dart";
import "package:matr_u/data/models/vinculos.dart";
import "package:matr_u/ui/core/theme/tema.dart";
import "package:matr_u/ui/core/widgets/aviso.dart";
import "package:matr_u/ui/core/widgets/nota.dart";
import "package:matr_u/ui/features/practice/views/practica.dart";
import "package:matr_u/ui/features/study/views/teoria.dart";

/// `/curso/[slug]` — el destino común de Buscar y Temario.
///
/// Réplica de `src/app/curso/[slug]/page.tsx`: antes de la sesión donde se
/// escribió esa página, «era un callejón sin salida — listaba los subtemas y
/// no llevaba a ninguna parte». Aquí no se repite ese error: los dos botones
/// de arriba son lo primero que se ve, no un adorno al final.
class PantallaCurso extends StatefulWidget {
  final Curso curso;
  const PantallaCurso({super.key, required this.curso});

  @override
  State<PantallaCurso> createState() => _PantallaCursoState();
}

class _PantallaCursoState extends State<PantallaCurso> {
  final _vinculos = RepositorioVinculos();
  late final Future<(ResumenCurso, Map<String, int>)> _carga = _cargar();

  Future<(ResumenCurso, Map<String, int>)> _cargar() async {
    final resumen = await _vinculos.resumenDeCurso(widget.curso);
    final banco = await RepositorioPreguntas().cargar();
    return (resumen, banco.conteoPorSubtema());
  }

  Future<void> _irATeoria() async {
    final teoria = await _vinculos.teoriaDeCurso(widget.curso.codigo);
    if (teoria == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PantallaCursoTeoria(curso: teoria)),
    );
  }

  Future<void> _irAPractica() async {
    final banco = await RepositorioPreguntas().cargar();
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SesionPractica(
          titulo: widget.curso.nombre,
          preguntas: banco.deCurso(widget.curso.slug),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final curso = widget.curso;

    return Scaffold(
      appBar: AppBar(
        title: Text(curso.nombre, style: context.textos.bodyLarge),
      ),
      body: FutureBuilder<(ResumenCurso, Map<String, int>)>(
        future: _carga,
        builder: (context, snap) {
          if (snap.hasError) {
            return Aviso.contenidoLocal(
              titulo: "No se pudo cargar el curso",
              error: snap.error!,
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (resumen, conteo) = snap.data!;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              Text(
                curso.areaNombre,
                style: context.textos.labelSmall!.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: context.esquema.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                curso.nombre,
                style: context.textos.headlineMedium!.copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.esquema.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "${curso.temas.length} temas · ${curso.totalSubtemas} subtemas · ${curso.codigo}",
                style: context.textos.bodySmall!.copyWith(
                  color: context.esquema.onSurfaceVariant,
                ),
              ),
              if (curso.nota case final nota? when nota.isNotEmpty) ...[
                const SizedBox(height: 12),
                Nota(texto: nota),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  if (resumen.teoriaSlug != null)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _irATeoria,
                        child: Text("Teoría · ${resumen.teoria} secciones"),
                      ),
                    ),
                  if (resumen.teoriaSlug != null && resumen.preguntas > 0)
                    const SizedBox(width: 10),
                  if (resumen.preguntas > 0)
                    Expanded(
                      child: FilledButton(
                        onPressed: _irAPractica,
                        child: Text("Practicar · ${resumen.preguntas}"),
                      ),
                    ),
                ],
              ),
              if (resumen.preguntas > 0) ...[
                const SizedBox(height: 8),
                Text(
                  "${resumen.subtemasConPreguntas} de ${curso.totalSubtemas} subtemas tienen preguntas.",
                  style: context.textos.bodySmall!.copyWith(
                    color: context.esquema.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 26),
              for (final tema in curso.temas) _Tema(tema: tema, conteo: conteo),
            ],
          );
        },
      ),
    );
  }
}

/// Un tema del sílabo. La franja de progreso no es "cuánto has estudiado"
/// —esta pantalla no consulta tu historial, la resuelve `Banco` en el APK—
/// sino cuánto del temario ya tiene una pregunta con la que practicarlo:
/// información honesta sobre el banco, no una barra de progreso personal
/// disfrazada.
class _Tema extends StatelessWidget {
  final Tema tema;
  final Map<String, int> conteo;
  const _Tema({required this.tema, required this.conteo});

  @override
  Widget build(BuildContext context) {
    final total = tema.subtemas.length;
    final conPreguntas = tema.subtemas
        .where((s) => (conteo[s.codigo] ?? 0) > 0)
        .length;
    final proporcion = total == 0 ? 0.0 : conPreguntas / total;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        border: Border.all(color: context.esquema.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.esquema.surfaceContainerLow,
              border: Border(
                bottom: BorderSide(color: context.esquema.outlineVariant),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.esquema.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tema.romano,
                    style: context.textos.labelSmall!.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.esquema.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tema.nombre,
                        style: context.textos.labelLarge!.copyWith(
                          fontWeight: FontWeight.w700,
                          color: context.esquema.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // La barra mide 70 px fijos y el texto crece con el
                      // tipo de letra del sistema, así que a 320 px esta fila
                      // no tenía holgura: desbordaba 0,43 px ya con la letra
                      // normal y 64 px con la letra a ×1,5 —dentro de lo que
                      // Android deja subir desde Accesibilidad—. El `Flexible`
                      // deja que el texto se parta en dos líneas en vez de
                      // empujar la fila fuera de la tarjeta; la barra sigue
                      // midiendo lo mismo, que es lo que la hace comparable
                      // entre temas.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: SizedBox(
                              width: 70,
                              height: 6,
                              child: LinearProgressIndicator(
                                value: proporcion,
                                backgroundColor: context.esquema.outlineVariant,
                                valueColor: AlwaysStoppedAnimation(
                                  context.esquema.primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              "$conPreguntas/$total con preguntas",
                              style: context.textos.labelSmall!.copyWith(
                                color: context.esquema.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (tema.pendienteDesglose) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: context.colores.avisoContenedor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            "sin desglose en el sílabo",
                            style: context.textos.labelSmall!.copyWith(
                              color: context.colores.aviso,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  tema.codigo,
                  style: context.textos.labelSmall!.copyWith(
                    color: context.esquema.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _ListaSubtemas(subtemas: tema.subtemas, conteo: conteo),
          ),
        ],
      ),
    );
  }
}

/// Algunos cursos (Geografía, Biología, Física, Literatura) agrupan sus
/// subtemas bajo un nivel A/B/C intermedio. Se respeta el orden original y
/// solo se inserta un encabezado cuando el grupo cambia.
class _ListaSubtemas extends StatelessWidget {
  final List<Subtema> subtemas;
  final Map<String, int> conteo;
  const _ListaSubtemas({required this.subtemas, required this.conteo});

  @override
  Widget build(BuildContext context) {
    final bloques = <(String?, List<Subtema>)>[];
    for (final s in subtemas) {
      if (bloques.isNotEmpty && bloques.last.$1 == s.grupo) {
        bloques.last.$2.add(s);
      } else {
        bloques.add((s.grupo, [s]));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (grupo, items) in bloques)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (grupo != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      grupo,
                      style: context.textos.labelSmall!.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: context.esquema.onSurfaceVariant,
                      ),
                    ),
                  ),
                for (final s in items) _FilaSubtema(subtema: s, conteo: conteo),
              ],
            ),
          ),
      ],
    );
  }
}

class _FilaSubtema extends StatelessWidget {
  final Subtema subtema;
  final Map<String, int> conteo;
  const _FilaSubtema({required this.subtema, required this.conteo});

  @override
  Widget build(BuildContext context) {
    final n = conteo[subtema.codigo] ?? 0;

    // Con preguntas, la fila lleva a practicar ese subtema suelto; sin ellas
    // no hay adónde ir y se queda como texto. Antes no llevaba a ningún lado
    // ni con preguntas: la cifra de la derecha era información y no una
    // puerta, que es justo lo que la web sí ofrece con `?subtema=`.
    final fila = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7, right: 8),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: context.esquema.outline,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              subtema.nombre,
              style: context.textos.bodyMedium!.copyWith(
                color: context.esquema.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (subtema.tipo == TipoSubtema.capacidad) ...[
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: context.esquema.secondaryContainer,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                "capacidad",
                style: context.textos.labelSmall!.copyWith(
                  color: context.esquema.primary,
                ),
              ),
            ),
          ],
          // Un subtema sin preguntas no muestra nada: un "0" repetido
          // cientos de veces sería ruido, y no hay sesión a la que llevar.
          if (n > 0) ...[
            Text(
              "$n",
              style: context.textos.labelSmall!.copyWith(
                fontWeight: FontWeight.w600,
                color: context.esquema.onSurfaceVariant,
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 15,
              color: context.esquema.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );

    if (n == 0) return fila;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PantallaPracticaSubtema(
              codigo: subtema.codigo,
              nombre: subtema.nombre,
            ),
          ),
        ),
        child: fila,
      ),
    );
  }
}
