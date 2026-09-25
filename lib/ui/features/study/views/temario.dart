import "package:flutter/material.dart";

import "package:matr_u/data/models/preguntas.dart";
import "package:matr_u/data/models/temario.dart";
import "package:matr_u/ui/core/theme/tema.dart";
import "package:matr_u/ui/core/widgets/aviso.dart";
import "package:matr_u/ui/features/study/views/curso.dart";

/// `/temario` — el sílabo oficial, curso por curso.
///
/// Réplica de `src/app/temario/page.tsx`: primero las cifras del conjunto,
/// después el listado agrupado por área temática. La web reparte los cursos
/// en una retícula de dos columnas por área; aquí, con menos ancho, cada
/// curso es su propia fila — se pierde el "ritmo de índice de libro" del
/// diseño de escritorio, pero se gana que el nombre completo de un curso
/// largo («Educación Cívica») nunca se corta.
class PantallaTemario extends StatefulWidget {
  const PantallaTemario({super.key});

  @override
  State<PantallaTemario> createState() => _PantallaTemarioState();
}

class _PantallaTemarioState extends State<PantallaTemario> {
  late final Future<(Temario, int)> _carga = _cargar();

  Future<(Temario, int)> _cargar() async {
    final temario = await RepositorioTemario().cargar();
    final banco = await RepositorioPreguntas().cargar();
    return (temario, banco.total);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Temario oficial")),
      body: FutureBuilder<(Temario, int)>(
        future: _carga,
        builder: (context, snap) {
          if (snap.hasError) {
            return Aviso.contenidoLocal(
              titulo: "No se pudo cargar el temario",
              error: snap.error!,
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (temario, preguntas) = snap.data!;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text(
                "El sílabo, curso por curso",
                style: context.textos.headlineSmall!.copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.esquema.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "${temario.areas.expand((a) => a.cursos).length} cursos, "
                "tema por tema, para que sepas exactamente qué estudiar y "
                "encuentres en segundos dónde practicarlo.",
                style: context.textos.bodyMedium!.copyWith(
                  color: context.esquema.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              _FilaCifras(temario: temario, preguntas: preguntas),
              if (temario.temasPendientes > 0) ...[
                const SizedBox(height: 12),
                _AvisoPendientes(cantidad: temario.temasPendientes),
              ],
              const SizedBox(height: 26),
              for (final area in temario.areas) _BloqueArea(area: area),
            ],
          );
        },
      ),
    );
  }
}

class _FilaCifras extends StatelessWidget {
  final Temario temario;
  final int preguntas;
  const _FilaCifras({required this.temario, required this.preguntas});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 16),
    decoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: context.esquema.outlineVariant),
        bottom: BorderSide(color: context.esquema.outlineVariant),
      ),
    ),
    child: Row(
      children: [
        _Cifra(
          valor: temario.areas.expand((a) => a.cursos).length,
          etiqueta: "cursos",
        ),
        _Cifra(valor: temario.temas.length, etiqueta: "temas"),
        _Cifra(valor: temario.totalSubtemas, etiqueta: "subtemas"),
        _Cifra(valor: preguntas, etiqueta: "preguntas"),
      ],
    ),
  );
}

class _Cifra extends StatelessWidget {
  final int valor;
  final String etiqueta;
  const _Cifra({required this.valor, required this.etiqueta});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "$valor",
          style: context.textos.headlineMedium!.copyWith(
            fontWeight: FontWeight.w800,
            color: context.esquema.onSurface,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          etiqueta,
          style: context.textos.labelSmall!.copyWith(
            letterSpacing: 0.4,
            color: context.esquema.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class _AvisoPendientes extends StatelessWidget {
  final int cantidad;
  const _AvisoPendientes({required this.cantidad});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.colores.avisoContenedor,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 16, color: context.colores.aviso),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            "$cantidad temas siguen sin desglose de subtemas en el "
            "sílabo. Aparecen marcados como pendientes.",
            style: context.textos.bodySmall!.copyWith(
              color: context.colores.aviso,
            ),
          ),
        ),
      ],
    ),
  );
}

class _BloqueArea extends StatelessWidget {
  final AreaTematica area;
  const _BloqueArea({required this.area});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          area.nombre,
          style: context.textos.titleMedium!.copyWith(
            fontWeight: FontWeight.w700,
            color: context.esquema.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          "${area.cursos.length} ${area.cursos.length == 1 ? "curso" : "cursos"}",
          style: context.textos.bodySmall!.copyWith(
            color: context.esquema.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        for (final curso in area.cursos) _TarjetaCurso(curso: curso),
      ],
    ),
  );
}

class _TarjetaCurso extends StatelessWidget {
  final Curso curso;
  const _TarjetaCurso({required this.curso});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: context.esquema.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => PantallaCurso(curso: curso))),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: context.esquema.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.esquema.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.menu_book_outlined,
                  size: 18,
                  color: context.esquema.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      curso.nombre,
                      style: context.textos.labelLarge!.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.esquema.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "${curso.temas.length} temas · ${curso.totalSubtemas} subtemas",
                      style: context.textos.bodySmall!.copyWith(
                        color: context.esquema.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: context.esquema.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
