// Dos cosas de la capa del panel que no necesitan servidor para probarse: la
// clasificación de roles y la clave de una pregunta en revisión.
//
// `esStaff()` es la comprobación que decide si `PantallaPanel` muestra el
// panel o el aviso de «no tienes acceso» — pero, como en la web, es
// conveniencia y no el control de acceso real: las seis funciones del panel
// comprueban `es_staff()`/`es_admin()` dentro de Postgres igual. Lo que este
// test fija es que la conveniencia clasifica los tres roles como la base
// los clasifica.
import "package:flutter_test/flutter_test.dart";
import "package:matr_u/datos/panel.dart";
import "package:matr_u/datos/preguntas.dart" show Letra;

void main() {
  group("esStaff", () {
    test("docente y admin son staff", () {
      expect(esStaff(Rol.docente), isTrue);
      expect(esStaff(Rol.admin), isTrue);
    });

    test("alumno no es staff", () {
      expect(esStaff(Rol.alumno), isFalse);
    });

    test("sin rol (sin sesión) no es staff", () {
      expect(esStaff(null), isFalse);
    });
  });

  // ==========================================================================
  // La clave de una pregunta en revisión
  // ==========================================================================
  //
  // `PreguntaRevision.clave` era `Letra` (no nullable) y se rellenaba con
  // `letraDesde(...) ?? Letra.a`. Una clave ausente o ilegible le llegaba al
  // docente como «la respuesta correcta es A», en verde y con su etiqueta
  // «clave» — en la única pantalla de toda la app que existe para auditar
  // precisamente esa letra. Una clave falsa auditada se publica con el visto
  // bueno de un profesor.
  //
  // El constructor no valida nada, así que lo que se fija aquí es el contrato
  // del tipo: que `null` sea representable, y que nada lo convierta en «A».
  group("la clave de una pregunta en revisión", () {
    PreguntaRevision conClave(Letra? clave) => PreguntaRevision(
      id: 1,
      codigo: "QUI-2027-001",
      enunciadoMd: "¿Cuánto pesa?",
      imagenUrl: null,
      imagenAlt: null,
      clave: clave,
      explicacionMd: null,
      estado: "sin_auditar",
      dificultad: "medio",
      auditada: false,
      curso: "Química",
      subtema: "Estequiometría",
      alternativas: const [],
      reportesAbiertos: 0,
    );

    test("puede no haber clave, y entonces no es la A", () {
      final p = conClave(null);
      expect(p.clave, isNull);
      expect(
        p.clave,
        isNot(Letra.a),
        reason: "el valor por defecto `?? Letra.a` presentaba A como correcta",
      );
    });

    test("sin clave, ninguna alternativa se marca como la correcta", () {
      // Es la comparación que hace la ficha: `a.letra == p.clave`. Con `null`
      // ninguna coincide, que es la degradación correcta — y el aviso de la
      // pantalla es lo que evita que se lea como «no encuentro la clave».
      final p = conClave(null);
      for (final letra in Letra.values) {
        expect(letra == p.clave, isFalse, reason: letra.name);
      }
    });

    test("con clave, se conserva tal cual", () {
      expect(conClave(Letra.c).clave, Letra.c);
      expect(conClave(Letra.a).clave, Letra.a);
    });
  });
}
