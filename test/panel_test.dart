// `esStaff()` es la comprobación que decide si `PantallaPanel` muestra el
// panel o el aviso de «no tienes acceso» — pero, como en la web, es
// conveniencia y no el control de acceso real: las seis funciones del panel
// comprueban `es_staff()`/`es_admin()` dentro de Postgres igual. Lo que este
// test fija es que la conveniencia clasifica los tres roles como la base
// los clasifica.
import "package:flutter_test/flutter_test.dart";
import "package:matr_u/datos/panel.dart";

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
}
