// Ninguna lista puede dejar el estado de una fila pegado a la siguiente.
//
// Flutter reutiliza los `State` por POSICIÓN. Si un `itemBuilder` construye un
// `StatefulWidget` sin `key`, al cambiar los datos la fila que cae en el hueco
// número 0 hereda el estado de la que estaba antes ahí. No es un detalle
// teórico: en el panel de docente pasaba en las tres listas a la vez —al
// dictaminar una pregunta, la lista se recargaba y el «Marcada como
// publicada» aparecía sobre la pregunta NUEVA, que nadie había tocado— y en
// «Personas» era peor, porque `_FilaPersona` cachea el rol en un campo `late`
// y acababa enseñando el rol de alguien sobre el nombre de otro, en la
// pantalla que reparte permisos.
//
// El proyecto ya había tropezado y resuelto esto una vez: `_Reporte`, en
// practica.dart, lleva `ValueKey(_pregunta.codigo)` con un comentario que
// explica exactamente este fallo. Que volviera a aparecer en otro archivo es
// la razón de que esto sea un test y no una nota.
import "dart:io";

import "package:flutter_test/flutter_test.dart";

/// Los `.dart` de `lib/`.
List<File> _fuentes() =>
    Directory("lib")
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith(".dart"))
        .toList();

/// Los nombres de clase que extienden `StatefulWidget` en todo `lib/`.
Set<String> _statefulDeLib() {
  final nombres = <String>{};
  final patron = RegExp(r"class\s+(\w+)\s+extends\s+StatefulWidget");
  for (final archivo in _fuentes()) {
    for (final m in patron.allMatches(archivo.readAsStringSync())) {
      nombres.add(m[1]!);
    }
  }
  return nombres;
}

/// El primer widget que se construye dentro de un `itemBuilder`, junto con el
/// texto de su llamada hasta el paréntesis que la cierra.
///
/// Devuelve `null` si el builder no construye directamente un widget con
/// nombre (por ejemplo, si devuelve un `switch` o una variable).
({String widget, String llamada})? _widgetDelBuilder(
  String fuente,
  int desdeItemBuilder,
) {
  // `itemBuilder: (context, i) => Algo(` o `itemBuilder: (context, i) { ... `
  final flecha = fuente.indexOf("=>", desdeItemBuilder);
  if (flecha < 0) return null;

  final m = RegExp(r"=>\s*(?:const\s+)?(\w+)\s*\(")
      .matchAsPrefix(fuente, flecha);
  if (m == null) return null;

  final abre = fuente.indexOf("(", m.end - 1);
  var profundidad = 0;
  for (var i = abre; i < fuente.length; i++) {
    if (fuente[i] == "(") profundidad++;
    if (fuente[i] == ")") {
      profundidad--;
      if (profundidad == 0) {
        return (widget: m[1]!, llamada: fuente.substring(abre, i + 1));
      }
    }
  }
  return null;
}

void main() {
  test("todo itemBuilder que construye un StatefulWidget le pasa una key", () {
    final stateful = _statefulDeLib();
    expect(
      stateful,
      isNotEmpty,
      reason: "si no encuentra ninguno, el test no está mirando nada",
    );

    final sinClave = <String>[];

    for (final archivo in _fuentes()) {
      final fuente = archivo.readAsStringSync();
      for (final m in RegExp("itemBuilder:").allMatches(fuente)) {
        final construido = _widgetDelBuilder(fuente, m.end);
        if (construido == null) continue;
        if (!stateful.contains(construido.widget)) continue;
        if (construido.llamada.contains("key:")) continue;

        final linea = fuente.substring(0, m.start).split("\n").length;
        sinClave.add("${archivo.path}:$linea  → ${construido.widget}");
      }
    }

    expect(
      sinClave,
      isEmpty,
      reason:
          "estos itemBuilder construyen un StatefulWidget sin key, así que "
          "Flutter reutilizará su State por posición y el estado de una fila "
          "aparecerá sobre otra.\nPasa una `key: ValueKey(<id estable>)`:\n\n"
          "${sinClave.join("\n")}\n",
    );
  });

  test("el detector reconoce un itemBuilder sin key", () {
    // Sin esto, un fallo en `_widgetDelBuilder` dejaría el test de arriba en
    // verde comprobando cero cosas.
    const malo = """
      ListView.builder(
        itemCount: 3,
        itemBuilder: (context, i) => _Ficha(dato: datos[i]),
      )
    """;
    final r = _widgetDelBuilder(malo, malo.indexOf("itemBuilder:") + 12);
    expect(r?.widget, "_Ficha");
    expect(r!.llamada, isNot(contains("key:")));
  });

  test("el detector ve la key cuando está", () {
    const bueno = """
      ListView.builder(
        itemBuilder: (context, i) => _Ficha(
          key: ValueKey(datos[i].id),
          dato: datos[i],
        ),
      )
    """;
    final r = _widgetDelBuilder(bueno, bueno.indexOf("itemBuilder:") + 12);
    expect(r?.widget, "_Ficha");
    expect(r!.llamada, contains("key:"));
  });

  test("no se confunde con un widget anidado dentro del mismo builder", () {
    const anidado = """
      ListView.builder(
        itemBuilder: (context, i) => _Ficha(
          dato: datos[i],
          hijo: _Otro(key: ValueKey(i)),
        ),
      )
    """;
    final r = _widgetDelBuilder(anidado, anidado.indexOf("itemBuilder:") + 12);
    expect(r?.widget, "_Ficha");
    // La llamada abarca al hijo, así que este caso se daría por bueno aunque
    // la key esté en el sitio equivocado. Es el límite conocido del detector:
    // prefiere no gritar antes que gritar en falso, y el caso real —una key
    // suelta en un hijo— no se ha dado nunca en este repo.
    expect(r!.llamada, contains("_Otro"));
  });
}
