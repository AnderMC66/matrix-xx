import "package:flutter/material.dart";
import "package:matr_u/domain/models/temario.dart";
import "package:matr_u/ui/core/theme/tema.dart";
import "package:matr_u/ui/features/study/view_models/catalogo.dart";
import "package:matr_u/ui/features/study/views/curso.dart";
import "package:matr_u/ui/features/study/views/temario.dart"
    show PantallaTemario;

/// `/buscar` — encontrar un subtema por nombre o código.
///
/// Réplica de `src/app/buscar/page.tsx`. La web escribe la consulta en la URL
/// con 200 ms de retardo (`campo-busqueda.tsx`) para no lanzar una navegación
/// por cada tecla; aquí no hay URL que actualizar, pero el motivo del
/// retardo es el mismo — `Temario.buscar()` recorre 956 subtemas en cada
/// llamada, y sin el debounce cada tecla dispara un recorrido completo.
class PantallaBuscar extends StatefulWidget {
  /// El modelo de vista, inyectable. Si no llega, la pantalla construye el
  /// suyo con los repositorios de produccion.
  final ModeloBuscar? modelo;

  const PantallaBuscar({super.key, this.modelo});

  @override
  State<PantallaBuscar> createState() => _PantallaBuscarState();
}

class _PantallaBuscarState extends State<PantallaBuscar> {
  late final ModeloBuscar _modelo = widget.modelo ?? ModeloBuscar();
  late final bool _esMio = widget.modelo == null;

  /// El controlador se queda en la vista: es estado del `TextField`, no del
  /// modelo. El modelo recibe el texto ya escrito y decide que hacer con el.
  final _controlador = TextEditingController();

  @override
  void initState() {
    super.initState();
    _modelo.cargar();
  }

  @override
  void dispose() {
    _controlador.dispose();
    if (_esMio) _modelo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _modelo,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text("Buscar en el temario")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _controlador,
              onChanged: _modelo.escribir,
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
                          _modelo.escribir("");
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
            ),
          ),
          if (_modelo.consulta.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _modelo.resultados.isEmpty
                      ? "Sin resultados."
                      : _modelo.resultados.length >= ModeloBuscar.limite
                      ? "Más de $ModeloBuscar.limite resultados. Afina la búsqueda."
                      : "${_modelo.resultados.length} "
                            "${_modelo.resultados.length == 1 ? "resultado" : "resultados"}.",
                  style: context.textos.bodySmall!.copyWith(
                    color: context.esquema.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          Expanded(
            child: _modelo.consulta.trim().isEmpty
                ? _EstadoVacio(temario: _modelo.temario)
                : _modelo.resultados.isEmpty
                ? const _SinResultados()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: _modelo.resultados.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) =>
                        _FilaResultado(resultado: _modelo.resultados[i]),
                  ),
          ),
        ],
      ),
    ),
  );
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
          color: context.esquema.secondaryContainer,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(
          Icons.menu_book_outlined,
          size: 17,
          color: context.esquema.primary,
        ),
      ),
      title: Text(subtema.nombre, style: context.textos.bodyMedium),
      subtitle: Text(
        "${curso.nombre} · ${tema.romano}. ${tema.nombre}"
        "${subtema.grupo != null ? " · ${subtema.grupo}" : ""}",
        style: context.textos.bodySmall!.copyWith(
          color: context.esquema.onSurfaceVariant,
        ),
      ),
      trailing: Text(
        subtema.codigo,
        style: context.textos.labelSmall!.copyWith(
          color: context.esquema.onSurfaceVariant,
        ),
      ),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => PantallaCurso(curso: curso))),
    );
  }
}

/// El estado vacío de Buscar: qué se puede escribir aquí, y una salida al
/// temario completo para quien no sabe qué buscar.
///
/// **Va dentro de un `SingleChildScrollView` por la misma razón que `Aviso`.**
/// Este widget es, de hecho, una novena copia a mano del que aquella
/// consolidación reunió en `widgets/aviso.dart`: se quedó fuera porque tiene
/// una línea de ejemplos en monoespaciada que `Aviso` no sabe pintar, y con
/// ella se quedó fuera también el arreglo. Un `Center` con un `Column` dentro
/// no puede encoger: con el tipo de letra del sistema al máximo, el icono más
/// el párrafo más los ejemplos más el botón pasaban de lo que mide una
/// pantalla de 568 px y desbordaban 118 px por abajo —el botón «Ver el temario
/// completo» quedaba fuera y era inalcanzable—. Medido con Roboto, no con la
/// fuente de prueba.
class _EstadoVacio extends StatelessWidget {
  final Temario? temario;
  const _EstadoVacio({required this.temario});

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 30, color: context.esquema.onSurfaceVariant),
          const SizedBox(height: 14),
          Text(
            temario == null
                ? "Cargando el temario…"
                : "Encuentra en segundos cualquiera de los "
                      "${temario!.totalSubtemas} subtemas del sílabo, "
                      "por su nombre o su código.",
            textAlign: TextAlign.center,
            style: context.textos.bodyMedium!.copyWith(
              color: context.esquema.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "FIS-09 · Vallejo · Ley de Coulomb",
            style: context.textos.bodySmall!.copyWith(
              fontFamily: "monospace",
              color: context.esquema.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const PantallaTemario())),
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
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: EdgeInsets.all(28),
      child: Text(
        "Sin resultados. Prueba con menos palabras, o solo el código del "
        "curso.",
        textAlign: TextAlign.center,
        style: context.textos.bodyMedium!.copyWith(
          color: context.esquema.onSurfaceVariant,
        ),
      ),
    ),
  );
}
