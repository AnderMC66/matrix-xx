import "dart:convert";

import "package:flutter/services.dart" show rootBundle;

/// Las figuras de teoría que decodifican a un rectángulo de un solo color
/// —en la práctica, siempre negro puro—, generadas por
/// `tool/detectar-figuras-rotas.mjs`.
///
/// **No es un problema de red.** Las 3 590 figuras responden HTTP 200 con
/// `image/webp` válido contra el sitio real; estas 149 (4,2 %) decodifican
/// correctamente y el resultado es negro sólido. **Tampoco es una regresión
/// del paso de optimización a WebP**: se comprobó el PNG original en
/// `base de datos matrix/markdown/assets/<hash>.png`, antes de cualquier
/// conversión, y ya era negro. El defecto viene de la extracción del PDF —
/// el mismo lote que `ESTADO.md` documenta para las fórmulas rotas—, y
/// estaba invisible hasta que se arregló el despliegue de las figuras: con
/// el 404 de antes, ninguna llegaba a mostrarse, negra o no.
///
/// Sin esta lista, `FiguraRed` mostraría un rectángulo negro sólido en mitad
/// de la teoría: peor que el aviso «figura sin contenido», que al menos dice
/// qué pasó. `tool/detectar-figuras-rotas.mjs` explica cómo se regenera si
/// el banco de contenido trae figuras nuevas.
class RepositorioFigurasRotas {
  /// La que usa la app de verdad, precargada en `main.dart` antes de que
  /// cualquier pantalla se muestre.
  static final instancia = RepositorioFigurasRotas();

  Set<String>? _nombres;

  /// Se llama una vez al arrancar la app (`main.dart`), para que la consulta
  /// en `FiguraRed` sea síncrona y no le añada un `FutureBuilder` más al
  /// árbol por cada una de las miles de figuras que aparecen en teoría.
  Future<void> cargar() async {
    if (_nombres != null) return;
    try {
      final texto = await rootBundle.loadString("assets/figuras_rotas.json");
      _nombres = (jsonDecode(texto) as List).cast<String>().toSet();
    } catch (_) {
      // Sin el asset, ninguna figura se marca como rota: se degrada al
      // comportamiento de antes de que existiera esta lista, no a un error.
      _nombres = const {};
    }
  }

  /// `false` mientras no se haya llamado a [cargar] — es la opción segura:
  /// en el peor caso se intenta cargar por red una figura rota (y cae al
  /// aviso normal por `errorBuilder` si la red falla), nunca al revés.
  bool esta(String nombreArchivo) => _nombres?.contains(nombreArchivo) ?? false;
}
