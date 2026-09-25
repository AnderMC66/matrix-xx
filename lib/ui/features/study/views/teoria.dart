import "package:flutter/material.dart";
import "package:matr_u/core/config/config.dart";
import "package:matr_u/core/utils/matematicas/formula.dart";
import "package:matr_u/data/models/markdown_teoria.dart";
import "package:matr_u/data/models/teoria.dart";
import "package:matr_u/ui/core/theme/tema.dart";
import "package:matr_u/ui/core/widgets/aviso.dart";
import "package:matr_u/ui/features/practice/views/figura_red.dart";

/// `/teoria` — los 15 cursos con teoría.
class PantallaTeoria extends StatefulWidget {
  const PantallaTeoria({super.key});

  @override
  State<PantallaTeoria> createState() => _PantallaTeoriaState();
}

class _PantallaTeoriaState extends State<PantallaTeoria> {
  final _repo = RepositorioTeoria();
  late final Future<List<CursoTeoria>> _cursos = _repo.cursos();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CursoTeoria>>(
      future: _cursos,
      builder: (context, snap) {
        if (snap.hasError) {
          return Aviso.contenidoLocal(
            titulo: "No se pudo cargar la teoría",
            error: snap.error!,
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final cursos = snap.data!;
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: cursos.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final curso = cursos[i];
            return Card(
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                title: Text(
                  curso.nombre,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: context.esquema.onSurface,
                  ),
                ),
                subtitle: Text(
                  "${curso.conContenido} secciones",
                  style: TextStyle(color: context.esquema.onSurfaceVariant),
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  color: context.esquema.onSurfaceVariant,
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PantallaCursoTeoria(curso: curso),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// `/teoria/[curso]` — el índice de secciones de un curso.
class PantallaCursoTeoria extends StatelessWidget {
  final CursoTeoria curso;
  const PantallaCursoTeoria({super.key, required this.curso});

  @override
  Widget build(BuildContext context) {
    final conContenido = curso.secciones
        .where((s) => s.tieneContenido)
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(curso.nombre)),
      body: ListView.separated(
        itemCount: conContenido.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final s = conContenido[i];
          return ListTile(
            // La sangría refleja el nivel del árbol, como el índice de la web.
            contentPadding: EdgeInsets.only(
              left: 16.0 + (s.nivel - 2).clamp(0, 3) * 14,
              right: 16,
            ),
            title: Text(
              s.tituloConNumero,
              // El nivel del árbol se lee en el peso y en la sangría, no en un
              // punto de tamaño: 15 contra 14 no distinguía una sección de su
              // subsección, solo hacía el índice irregular.
              style: s.nivel <= 2
                  ? context.textos.titleMedium
                  : context.textos.bodyLarge,
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PantallaSeccion(
                  curso: curso,
                  indice: i,
                  secciones: conContenido,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// `/teoria/[curso]/[id]` — una sección, con sus fórmulas.
///
/// Replica la navegación anterior/siguiente que se añadió a la web en
/// `cde83bc` («navegación entre secciones de teoría»).
class PantallaSeccion extends StatelessWidget {
  final CursoTeoria curso;
  final List<SeccionTeoria> secciones;
  final int indice;

  const PantallaSeccion({
    super.key,
    required this.curso,
    required this.secciones,
    required this.indice,
  });

  void _ir(BuildContext context, int nuevo) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            PantallaSeccion(curso: curso, secciones: secciones, indice: nuevo),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = secciones[indice];
    final hayAnterior = indice > 0;
    final haySiguiente = indice < secciones.length - 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(curso.nombre, style: context.textos.bodyLarge),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            s.tituloConNumero,
            style: context.textos.headlineMedium!.copyWith(
              fontWeight: FontWeight.w700,
              color: context.esquema.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          for (final bloque in analizarTeoria(s.markdown))
            _Bloque(bloque: bloque),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: hayAnterior
                      ? () => _ir(context, indice - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left, size: 18),
                  label: const Text("Anterior"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: haySiguiente
                      ? () => _ir(context, indice + 1)
                      : null,
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.chevron_right, size: 18),
                  label: const Text("Siguiente"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pinta un bloque de teoría según lo que `analizarTeoria` decidió que es.
///
/// Cada caso lleva su propio espaciado porque el original es un PDF: sin aire
/// entre bloques, un título y su párrafo se leen como una sola frase larga.
class _Bloque extends StatelessWidget {
  final BloqueTeoria bloque;
  const _Bloque({required this.bloque});

  @override
  Widget build(BuildContext context) {
    // **Era un `static const TextStyle` de 15,5 px**, y por serlo no podía
    // saber en qué tema estaba: con modo oscuro habría pintado texto casi
    // negro sobre fondo casi negro. Ahora es `bodyLarge` (16 px, interlineado
    // 1,6), que es el cuerpo de lectura de toda la app — y la teoría es
    // justamente lo que más se lee.
    final cuerpo = context.textos.bodyLarge;
    return switch (bloque) {
      TituloTeoria(:final texto, :final nivel) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: TextoConFormulas(
          texto,
          conMarcado: true,
          // 19 / 16,5 / 15,5 eran tres tamaños a ojo, y el tercero quedaba a
          // medio punto del cuerpo: un título que no se distingue de su párrafo
          // no es un título. Ahora son dos escalones reales de la escala.
          estilo: nivel <= 1
              ? context.textos.headlineSmall
              : context.textos.titleMedium,
        ),
      ),

      ParrafoTeoria(:final texto) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextoConFormulas(texto, conMarcado: true, estilo: cuerpo),
      ),

      ItemTeoria(:final texto, :final marca) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 26,
              child: Text(
                marca,
                // El interlineado se iguala al del cuerpo para que la viñeta
                // quede alineada con su primera línea, no flotando encima.
                style: context.textos.bodyLarge?.copyWith(
                  color: context.esquema.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: TextoConFormulas(texto, conMarcado: true, estilo: cuerpo),
            ),
          ],
        ),
      ),

      // Aparecen 3 827 veces en el corpus: en línea, compacta — un recuadro
      // grande por figura convertiría la lectura en un campo de marcadores.
      // Carga de verdad desde `Config.urlFiguraTeoria`; si no llega, cae al
      // mismo aviso pequeño que había antes de esto (ver `figura_red.dart`).
      FiguraTeoria(:final archivo, :final alt) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: FiguraRed(url: Config.urlFiguraTeoria(archivo), alt: alt),
      ),
    };
  }
}
