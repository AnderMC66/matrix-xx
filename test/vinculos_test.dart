// El mapeo curso oficial → curso de teoría, y lo que construye sobre él.
//
// Es la única correspondencia entre las dos taxonomías del proyecto, y a
// diferencia de todo lo demás en `datos/`, no se puede derivar de los datos
// mismos: es una tabla escrita a mano en `vinculos.dart`. Un código de curso
// que cambie en el temario, o un archivo de teoría que se renombre, la
// desincroniza en silencio — el curso simplemente deja de ofrecer el botón
// "Estudiar la teoría", sin ningún error.
import "package:flutter_test/flutter_test.dart";
import "package:matr_u/data/models/preguntas.dart";
import "package:matr_u/data/models/temario.dart";
import "package:matr_u/data/models/teoria.dart";
import "package:matr_u/data/models/vinculos.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("teoriaDeCurso", () {
    test(
      "resuelve al mismo curso de teoría que la web para cada área",
      () async {
        final repo = RepositorioVinculos();
        final temario = await RepositorioTemario().cargar();

        // Los cuatro cursos de matemática comparten un solo curso de teoría:
        // el banco importado no los separa. Es la asimetría documentada, no
        // un error si los cuatro dan el mismo slug.
        for (final codigo in ["ARI", "ALG", "GEO", "TRI"]) {
          final curso = temario.cursos.firstWhere((c) => c.codigo == codigo);
          final teoria = await repo.teoriaDeCurso(curso.codigo);
          expect(teoria?.slug, "matematica", reason: codigo);
        }
      },
    );

    test("comprensión lectora no tiene teoría, y no es un error", () async {
      final repo = RepositorioVinculos();
      final teoria = await repo.teoriaDeCurso("CL");
      expect(teoria, isNull);
    });

    test(
      "cada código de curso mapeado existe de verdad en el temario",
      () async {
        final temario = await RepositorioTemario().cargar();
        final codigos = temario.cursos.map((c) => c.codigo).toSet();

        // Si esto falla, `vinculos.dart` quedó desincronizado del temario real
        // — un código que ya no existe, o un curso nuevo sin entrada.
        const mapeados = [
          "ARI",
          "ALG",
          "GEO",
          "TRI",
          "RM",
          "RL",
          "RV",
          "LEN",
          "LIT",
          "ING",
          "FIL",
          "PSI",
          "HIS",
          "GEG",
          "QUI",
          "BIO",
          "FIS",
          "CIV",
          "CL",
        ];
        expect(codigos, containsAll(mapeados));
        expect(
          mapeados.toSet(),
          codigos,
          reason: "algún curso quedó sin mapear",
        );
      },
    );

    test("cada slug de teoría mapeado carga un archivo real", () async {
      final repo = RepositorioVinculos();
      final temario = await RepositorioTemario().cargar();

      for (final curso in temario.cursos) {
        final teoria = await repo.teoriaDeCurso(curso.codigo);
        // `null` es válido (Comprensión Lectora); lo que no puede pasar es
        // que exista una entrada pero el archivo no cargue.
        if (teoria != null) {
          expect(teoria.secciones, isNotEmpty, reason: curso.codigo);
        }
      }
    });
  });

  group("resumenDeCurso", () {
    test(
      "los subtemas con preguntas nunca superan el total del curso",
      () async {
        final repo = RepositorioVinculos();
        final temario = await RepositorioTemario().cargar();
        final banco = await RepositorioPreguntas().cargar();

        // Un curso con preguntas de verdad, para que el test no pase por
        // vacuidad (0 <= 0 siempre es cierto y no prueba nada).
        final curso = temario.cursos.firstWhere(
          (c) => banco.deCurso(c.slug).isNotEmpty,
        );
        final resumen = await repo.resumenDeCurso(curso);

        expect(resumen.preguntas, banco.deCurso(curso.slug).length);
        expect(
          resumen.subtemasConPreguntas,
          lessThanOrEqualTo(curso.totalSubtemas),
        );
        expect(resumen.subtemasConPreguntas, greaterThan(0));
      },
    );

    test("un curso sin teoría da teoriaSlug null y teoria 0", () async {
      final repo = RepositorioVinculos();
      final temario = await RepositorioTemario().cargar();
      final cl = temario.cursos.firstWhere((c) => c.codigo == "CL");

      final resumen = await repo.resumenDeCurso(cl);
      expect(resumen.teoriaSlug, isNull);
      expect(resumen.teoria, 0);
    });

    test(
      "el conteo de teoría cuenta el árbol entero, no solo el contenido",
      () async {
        // Réplica de `totalTemas` en la web: nodos del árbol, con o sin
        // markdown. Si un curso de teoría real tiene encabezados sin contenido
        // propio, esta cifra debe ser mayor que `conContenido`.
        final teoria = await RepositorioTeoria().curso("fisica");
        expect(
          teoria.secciones.length,
          greaterThanOrEqualTo(teoria.conContenido),
        );
      },
    );
  });
}
