// El arranque de la app, y la regresión concreta que motivó separarlo de
// `main()`: construir `Armazon` —que construye `Sesion()`, y `Sesion()` toca
// `Supabase.instance.client`— antes de que Supabase esté inicializado no
// debe lanzar nunca una excepción sin capturar, ni en el primer build.
//
// Sin `--dart-define-from-file=config/dev.json` (que es como corre esta
// suite), `Config.configurado` es `false`: es exactamente el caso "sin
// configuración en absoluto", y antes de este archivo crasheaba con la misma
// aserción de Supabase que se veía en el hot restart real — `Armazon` se
// construía sin condición, incluso sin credenciales.
//
// El otro caso real —el warm-up-frame de un hot restart reconstruyendo el
// árbol antes de que `await Supabase.initialize()` termine— no se puede
// reproducir en un widget test (no hay isolate que reiniciar), así que queda
// cubierto por revisión de código: `Arranque.build()` nunca toca
// `Supabase.instance`, solo `Config.configurado`, y quien la inicializa de
// verdad es `initState()`, que el framework garantiza posterior al primer
// build.
import "package:flutter_test/flutter_test.dart";
import "package:matr_u/config.dart";
import "package:matr_u/main.dart";

void main() {
  testWidgets(
    "sin configuración, arranca sin excepciones y muestra la ayuda",
    (tester) async {
      expect(
        Config.configurado,
        isFalse,
        reason: "este test asume que corre sin --dart-define-from-file",
      );

      await tester.pumpWidget(const AppMatrixU());
      await tester.pumpAndSettle();

      // Ninguna excepción llegó a la consola de errores del widget tree.
      expect(tester.takeException(), isNull);
      expect(find.textContaining(Config.ayuda), findsOneWidget);
    },
  );

  testWidgets(
    "el primer build no depende de que Supabase ya esté listo",
    (tester) async {
      // `pumpWidget` solo hace UN frame — el primer build, el mismo que un
      // warm-up-frame prematuro dispararía en un hot restart real. Si
      // `Arranque.build()` tocara `Supabase.instance` aquí, esto fallaría
      // igual que fallaba antes de separar el arranque de `main()`.
      await tester.pumpWidget(const AppMatrixU());
      expect(tester.takeException(), isNull);
    },
  );
}
