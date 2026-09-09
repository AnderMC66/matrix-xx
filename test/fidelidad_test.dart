// El puerto Dart tiene que dar exactamente los mismos números que el módulo
// TypeScript del que sale. Las cifras se calcularon con la lógica de
// `src/lib/{temario,preguntas}.ts` sobre los mismos datos.
//
// No es un test de "el código corre": es el que detecta que una regla de
// codificación se desvió. Si el temario deja de producir 956 subtemas, o el
// banco 392 preguntas, algo dejó de cruzar y la app pierde contenido sin
// mostrar ningún error.
//
// Cuando el contenido del repo web crezca, estas cifras suben: actualízalas
// corriendo la sincronización y leyendo el fallo, que dice el número nuevo.
import "package:flutter_test/flutter_test.dart";
import "package:matr_u/datos/preguntas.dart";
import "package:matr_u/datos/temario.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("el temario portado cuadra con el de la web", () async {
    final t = await RepositorioTemario().cargar();
    expect(t.cursos, hasLength(19));
    expect(t.temas, hasLength(207));
    expect(t.totalSubtemas, 956);
    expect(t.temasPendientes, 0);
  });

  test("el banco portado cuadra con el de la web", () async {
    final b = await RepositorioPreguntas().cargar();
    expect(b.total, 392);
    // Ninguna pregunta se pierde por ubicación no encontrada: si el cruce
    // fallara, este número bajaría en silencio.
    expect(b.preguntas.map((p) => p.codigo).toSet(), hasLength(392));
  });
}
