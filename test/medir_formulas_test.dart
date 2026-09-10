// Mide cuántas fórmulas reales del banco NO compila `flutter_math_fork`.
//
// Este es el número que decide si la migración a Flutter es viable. La web
// dibuja el banco con KaTeX; flutter_math_fork implementa un subconjunto más
// estrecho. Antes de reescribir 9 000 líneas de interfaz conviene saber qué
// porcentaje del contenido se degrada al cambiar de motor.
//
// Solo parsea — no dibuja — así que corre en segundos y no necesita emulador.
// Va como test y no como script suelto porque el parser depende del entorno de
// Flutter (`dart run` no puede compilarlo):
//
//   node tool/extraer-formulas.mjs                # refresca el asset
//   flutter test test/medir_formulas_test.dart
//
// Imprime N fórmulas fallidas de cada tipo de error, que es lo que dice si el
// problema es notación reparable o contenido ya roto en el origen.

// El informe es la salida de esta herramienta: `print` es lo correcto aquí.
// ignore_for_file: avoid_print

import "dart:convert";
import "dart:io";

import "package:flutter_math_fork/flutter_math.dart" show ParseException;
import "package:flutter_math_fork/tex.dart";
import "package:flutter_test/flutter_test.dart";

/// Cuántas fórmulas fallidas se imprimen por cada tipo de error.
const _cuantosEjemplos = 3;

void main() {
  test("cuántas fórmulas del banco sobreviven a flutter_math_fork", () {
    _medir();
  });
}

void _medir() {
  final archivo = File("assets/formulas_banco.json");
  if (!archivo.existsSync()) {
    stderr.writeln(
      "No existe assets/formulas_banco.json.\n"
      "Genéralo con:  node tool/extraer-formulas.mjs",
    );
    exit(1);
  }

  final formulas = (jsonDecode(archivo.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  var ok = 0;
  final fallos = <String, List<String>>{}; // mensaje de error -> ejemplos
  final porOrigen = <String, int>{}; // archivo de origen -> fallos

  for (final f in formulas) {
    final tex = f["tex"] as String;
    try {
      TexParser(tex, const TexParserSettings()).parse();
      ok++;
    } catch (e) {
      final clave = _normalizarError(e);
      fallos.putIfAbsent(clave, () => []).add(tex);
      final origen = f["origen"] as String? ?? "?";
      porOrigen[origen] = (porOrigen[origen] ?? 0) + 1;
    }
  }

  final total = formulas.length;
  final nFallos = total - ok;
  final pct = total == 0 ? 0.0 : nFallos * 100 / total;

  print("");
  print("Fórmulas del banco:  $total");
  print("  compilan:          $ok");
  print("  fallan:            $nFallos  (${pct.toStringAsFixed(1)} %)");
  print("");

  if (nFallos == 0) {
    print("Ninguna fórmula se pierde al cambiar de motor.");
    return;
  }

  print("Causas, de más a menos frecuente:");
  final ordenadas = fallos.entries.toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));
  for (final e in ordenadas.take(12)) {
    print("  ${e.value.length.toString().padLeft(5)}  ${e.key}");
    for (final tex in e.value.take(_cuantosEjemplos)) {
      print("         · ${_recortar(tex)}");
    }
  }

  print("");
  print("Archivos más afectados:");
  final origenes = porOrigen.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in origenes.take(10)) {
    print("  ${e.value.toString().padLeft(5)}  ${e.key}");
  }
  print("");
}

/// Quita de los mensajes el texto concreto de cada fórmula para poder
/// agruparlos: sin esto cada error es único y no se ve ningún patrón.
///
/// `toString()` de `ParseException` no sirve —devuelve "Instance of ..."—, así
/// que se lee el campo `message`, y se le corta la parte que cita la fórmula
/// ("at position 12: …\sqrt A") porque es distinta en cada una.
String _normalizarError(Object e) {
  final crudo = e is ParseException ? e.message : e.toString();
  return crudo
      .replaceAll(RegExp(r"\s*at (position \d+|end of input):.*$"), "")
      .replaceAll(RegExp(r"'[^']*'"), "'…'")
      .replaceAll(RegExp(r"\s+"), " ")
      .trim();
}

String _recortar(String tex) {
  final limpio = tex.replaceAll("\n", " ");
  return limpio.length <= 72 ? limpio : "${limpio.substring(0, 69)}...";
}
