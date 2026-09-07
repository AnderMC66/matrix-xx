import "package:flutter/material.dart";

import "../datos/teoria.dart";
import "../matematicas/formula.dart";
import "../tema.dart";

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
        if (snap.hasError) return _Error(error: snap.error!);
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
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Paleta.texto,
                  ),
                ),
                subtitle: Text(
                  "${curso.conContenido} secciones",
                  style: const TextStyle(color: Paleta.textoTenue),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Paleta.textoTenue,
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
    final conContenido =
        curso.secciones.where((s) => s.tieneContenido).toList();

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
              style: TextStyle(
                fontSize: s.nivel <= 2 ? 15 : 14,
                fontWeight: s.nivel <= 2 ? FontWeight.w600 : FontWeight.w400,
                color: Paleta.texto,
              ),
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
        builder: (_) => PantallaSeccion(
          curso: curso,
          secciones: secciones,
          indice: nuevo,
        ),
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
        title: Text(curso.nombre, style: const TextStyle(fontSize: 16)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            s.tituloConNumero,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Paleta.texto,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 16),
          // TODO: el markdown va crudo. Falta el paso de `markdown-teoria.ts`
          // que separa líneas, destaca los `**títulos**` y sustituye los
          // marcadores `![figura]` — las figuras están en Supabase Storage,
          // no en assets.
          TextoConFormulas(s.markdown),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: hayAnterior ? () => _ir(context, indice - 1) : null,
                  icon: const Icon(Icons.chevron_left, size: 18),
                  label: const Text("Anterior"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      haySiguiente ? () => _ir(context, indice + 1) : null,
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

class _Error extends StatelessWidget {
  final Object error;
  const _Error({required this.error});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Paleta.acento, size: 32),
          const SizedBox(height: 12),
          const Text(
            "No se pudo cargar la teoría",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            "$error\n\n¿Corriste `node tool/sincronizar-datos.mjs`?",
            textAlign: TextAlign.center,
            style: const TextStyle(color: Paleta.textoSuave, fontSize: 13),
          ),
        ],
      ),
    ),
  );
}
