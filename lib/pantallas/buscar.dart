import "dart:async";

import "package:flutter/material.dart";

import "../datos/temario.dart";
import "../tema.dart";
import "curso.dart";
import "temario.dart" show PantallaTemario;

const _limite = 200;

/// `/buscar` — encontrar un subtema por nombre o código.
///
/// Réplica de `src/app/buscar/page.tsx`. La web escribe la consulta en la URL
/// con 200 ms de retardo (`campo-busqueda.tsx`) para no lanzar una navegación
/// por cada tecla; aquí no hay URL que actualizar, pero el motivo del
/// retardo es el mismo — `Temario.buscar()` recorre 956 subtemas en cada
/// llamada, y sin el debounce cada tecla dispara un recorrido completo.
class PantallaBuscar extends StatefulWidget {
  const PantallaBuscar({super.key});

  @override
  State<PantallaBuscar> createState() => _PantallaBuscarState();
}

class _PantallaBuscarState extends State<PantallaBuscar> {
  final _repo = RepositorioTemario();
  final _controlador = TextEditingController();
  Timer? _debounce;

  Temario? _temario;
  List<Ubicacion> _resultados = const [];
  String _consulta = "";

  @override
  void initState() {
    super.initState();
    _repo.cargar().then((t) {
      if (mounted) setState(() => _temario = t);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controlador.dispose();
    super.dispose();
  }

  void _alEscribir(String texto) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      final temario = _temario;
      setState(() {
        _consulta = texto;
        _resultados = temario == null || texto.trim().isEmpty
            ? const []
            : temario.buscar(texto, limite: _limite);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Buscar en el temario")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _controlador,
              onChanged: _alEscribir,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: "Ley de Coulomb, Vallejo, FIS-09…",
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _controlador.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _controlador.clear();
                          _alEscribir("");
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
            ),
          ),
          if (_consulta.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _resultados.isEmpty
                      ? "Sin resultados."
                      : _resultados.length >= _limite
                      ? "Más de $_limite resultados. Afina la búsqueda."
                      : "${_resultados.length} "
                            "${_resultados.length == 1 ? "resultado" : "resultados"}.",
                  style: const TextStyle(fontSize: 12.5, color: Paleta.textoSuave),
                ),
              ),
            ),
          Expanded(
            child: _consulta.trim().isEmpty
                ? _EstadoVacio(temario: _temario)
                : _resultados.isEmpty
                ? const _SinResultados()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: _resultados.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) => _FilaResultado(
                      resultado: _resultados[i],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilaResultado extends StatelessWidget {
  final Ubicacion resultado;
  const _FilaResultado({required this.resultado});

  @override
  Widget build(BuildContext context) {
    final subtema = resultado.subtema;
    final tema = resultado.tema;
    final curso = resultado.curso;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Paleta.acentoSuave,
          borderRadius: BorderRadius.circular(9),
        ),
        child: const Icon(Icons.menu_book_outlined, size: 17, color: Paleta.acento),
      ),
      title: Text(subtema.nombre, style: const TextStyle(fontSize: 14, height: 1.3)),
      subtitle: Text(
        "${curso.nombre} · ${tema.romano}. ${tema.nombre}"
        "${subtema.grupo != null ? " · ${subtema.grupo}" : ""}",
        style: const TextStyle(fontSize: 11.5, color: Paleta.textoTenue),
      ),
      trailing: Text(
        subtema.codigo,
        style: const TextStyle(fontSize: 10, color: Paleta.textoTenue),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PantallaCurso(curso: curso)),
      ),
    );
  }
}

class _EstadoVacio extends StatelessWidget {
  final Temario? temario;
  const _EstadoVacio({required this.temario});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search, size: 30, color: Paleta.textoTenue),
          const SizedBox(height: 14),
          Text(
            temario == null
                ? "Cargando el temario…"
                : "Encuentra en segundos cualquiera de los "
                      "${temario!.totalSubtemas} subtemas del sílabo, "
                      "por su nombre o su código.",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Paleta.textoSuave, height: 1.55),
          ),
          const SizedBox(height: 8),
          const Text(
            "FIS-09 · Vallejo · Ley de Coulomb",
            style: TextStyle(
              fontSize: 11.5,
              fontFamily: "monospace",
              color: Paleta.textoTenue,
            ),
          ),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PantallaTemario()),
            ),
            icon: const Icon(Icons.list_alt, size: 17),
            label: const Text("Ver el temario completo"),
          ),
        ],
      ),
    ),
  );
}

class _SinResultados extends StatelessWidget {
  const _SinResultados();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(28),
      child: Text(
        "Sin resultados. Prueba con menos palabras, o solo el código del "
        "curso.",
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: Paleta.textoSuave, height: 1.5),
      ),
    ),
  );
}
