import "dart:convert";

import "package:flutter/services.dart" show rootBundle;

/// Lee el catálogo (temario, teoría, preguntas) desde los assets.
///
/// Equivale a `src/lib/{temario,teoria,preguntas}.ts` de la web, pero con una
/// diferencia de fondo: allí `readFileSync` va al disco en cada petición y el
/// caché (`cache-datos.ts`) se invalida por `mtime`. Aquí los archivos son
/// inmutables —viajan dentro del binario—, así que basta con memorizar el
/// resultado la primera vez y no volver a mirar.
///
/// `assets/datos/` lo produce `node tool/sincronizar-datos.mjs` desde el repo
/// web. No es fuente de verdad: no lo edites a mano.
class Catalogo {
  Catalogo._();
  static final instancia = Catalogo._();

  final _cache = <String, dynamic>{};

  /// Los nombres de archivo de una carpeta, según su `_indice.json`.
  ///
  /// Flutter no puede listar un directorio de assets en tiempo de ejecución,
  /// por eso el índice se genera al sincronizar.
  Future<List<String>> indice(String carpeta) async {
    final crudo = await _leer("assets/datos/$carpeta/_indice.json");
    return (crudo as List).cast<String>();
  }

  /// Un archivo del catálogo, ya decodificado.
  Future<dynamic> archivo(String carpeta, String nombre) =>
      _leer("assets/datos/$carpeta/$nombre");

  /// Todos los archivos de una carpeta, en el orden del índice.
  Future<List<dynamic>> todos(String carpeta) async {
    final nombres = await indice(carpeta);
    return Future.wait(nombres.map((n) => archivo(carpeta, n)));
  }

  Future<dynamic> _leer(String ruta) async {
    final yaEsta = _cache[ruta];
    if (yaEsta != null) return yaEsta;
    final texto = await rootBundle.loadString(ruta);
    final valor = jsonDecode(texto);
    _cache[ruta] = valor;
    return valor;
  }
}
