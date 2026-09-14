// Las pantallas que no necesitan sesión, en el móvil más estrecho que se
// vende y con el tipo de letra del sistema al máximo.
//
// Es la combinación que rompe diseños y que nadie prueba a mano: Android deja
// subir la letra hasta ×2 desde Accesibilidad, y un postulante que estudia dos
// horas al día en el móvil es exactamente quien la tiene subida. `aviso_test`
// ya cubría un widget suelto con esa condición; esto cubre pantallas enteras.
//
// 320×568 es el suelo real: el iPhone SE de primera generación y los Android
// baratos que se usan para estudiar. Si algo desborda ahí, desborda de verdad.
//
// Solo entran las pantallas que se pueden montar sin Supabase —teoría,
// temario, buscar, curso—, porque las demás construyen su repositorio con
// `Supabase.instance.client` dentro de su propio estado.
//
// ───────────────────────────────────────────────────────────────────────────
// **Sin cargar una fuente real, este archivo miente, y miente en la dirección
// que más cuesta: inventando desbordes que no existen.**
//
// `flutter_test` mide el texto con una fuente de prueba donde CADA glifo es un
// cuadro de un em completo. «54/88 con preguntas» mide 209 px ahí y 100 px con
// Roboto — el doble. La primera versión de este archivo señaló cuatro
// pantallas como rotas con la letra normal; comprobado después midiendo con
// Roboto en el navegador, ninguna lo estaba. Por eso aquí se carga la Roboto
// que trae el propio SDK antes de medir nada, y por eso el archivo entero se
// salta si no la encuentra: un desborde medido con la fuente de prueba no es
// un desborde, es ruido.
//
// **Y `calentar()` tampoco es opcional.** `rootBundle.loadString` descomprime
// en un isolate cuando el archivo pasa de unas decenas de KB, y los de teoría
// suman 5,4 MB. Un `testWidgets` corre en una zona de async FALSO donde ese
// trabajo nunca se completa, así que el `FutureBuilder` de la pantalla se
// queda en su spinner: el test no encontraba ningún desborde porque no había
// nada pintado, y pasaba. `tester.runAsync` sí ejecuta async de verdad, y
// cada test remata comprobando que el contenido está en pantalla — que es lo
// que impide que este archivo vuelva a pasar sin probar nada.
// ───────────────────────────────────────────────────────────────────────────
import "dart:io";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:matr_u/datos/preguntas.dart";
import "package:matr_u/datos/temario.dart";
import "package:matr_u/datos/teoria.dart";
import "package:matr_u/pantallas/buscar.dart";
import "package:matr_u/pantallas/curso.dart";
import "package:matr_u/pantallas/temario.dart";
import "package:matr_u/pantallas/teoria.dart";
import "package:matr_u/tema.dart";
import "package:matr_u/widgets/aviso.dart";

/// La Roboto que trae el SDK, o `null` si no está donde se espera.
///
/// `FLUTTER_ROOT` lo define `flutter test` al arrancar. Es la misma fuente que
/// usa Android de serie, así que medir con ella es medir lo que ve el alumno.
File? _roboto() {
  final raiz = Platform.environment["FLUTTER_ROOT"];
  if (raiz == null) return null;
  final f = File("$raiz/bin/cache/artifacts/material_fonts/roboto-regular.ttf");
  return f.existsSync() ? f : null;
}

/// El móvil más estrecho que hay que soportar.
const _estrecho = Size(320, 568);

void _configurar(WidgetTester tester, {required double escala}) {
  tester.view
    ..physicalSize = _estrecho * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = escala;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Deja el catálogo en memoria antes de pintar. Ver la nota de arriba.
Future<void> calentar(WidgetTester tester) async {
  await tester.runAsync(() async {
    await RepositorioTemario().cargar();
    await RepositorioPreguntas().cargar();
    await RepositorioTeoria().cursos();
  });
}

Widget _envolver(Widget pantalla) =>
    MaterialApp(theme: construirTema(), home: pantalla);

/// Monta la pantalla y devuelve el desborde que haya dejado, o `null`.
///
/// Flutter reporta un desborde como excepción del árbol, no como un fallo: sin
/// recogerla, el test pasa y el recuadro amarillo solo lo ve quien abre la app.
Future<String?> _desborde(WidgetTester tester, Widget pantalla) async {
  await tester.pumpWidget(_envolver(pantalla));
  await tester.pump();
  final e = tester.takeException();
  if (e == null) return null;
  final texto = e.toString();
  // Las figuras piden red, y en un widget test toda petición devuelve 400 a
  // propósito. Eso no es un desborde.
  if (texto.contains("HttpException") ||
      texto.contains("Invalid image data") ||
      texto.contains("statusCode")) {
    return null;
  }
  return texto.split("\n").first;
}

// Los tres desbordes que este archivo encontró están arreglados:
//
//   curso.dart:220        el Text «N/M con preguntas» ahora va en Flexible, así
//                         que se parte en dos líneas en vez de empujar la fila
//                         fuera de la tarjeta (desbordaba 0,43 px a ×1,0 y
//                         64 px a ×1,5).
//   buscar.dart:186       el estado vacío va dentro de un SingleChildScrollView,
//                         como ya hacía `Aviso` (desbordaba 118 px a ×2,0, con
//                         el botón «Ver el temario completo» fuera de alcance).
//   inicio.dart           la rejilla de accesos directos divide su
//                         childAspectRatio por la escala del tipo de letra.
//                         NO lo cubre este archivo: `PantallaInicio` construye
//                         `Sesion()` en su estado y no se puede montar sin
//                         Supabase.
//
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fuente = _roboto();
  if (fuente == null) {
    // Sin fuente real no se mide nada: ver la nota de arriba.
    test(
      "desbordes",
      () {},
      skip: "No encuentro roboto-regular.ttf en FLUTTER_ROOT",
    );
    return;
  }

  setUpAll(() async {
    final cargador = FontLoader("Roboto")
      ..addFont(Future.value(fuente.readAsBytesSync().buffer.asByteData()));
    await cargador.load();
  });

  for (final escala in [1.0, 1.5, 2.0]) {
    group("a 320 px con la letra ×$escala", () {
      testWidgets("Temario", (tester) async {
        _configurar(tester, escala: escala);
        await calentar(tester);

        expect(await _desborde(tester, const PantallaTemario()), isNull);
        // Prueba de que se pintó de verdad: la cifra de cursos del sílabo.
        expect(find.text("19"), findsOneWidget);
        expect(find.text("cursos"), findsOneWidget);
      });

      testWidgets("Teoría (los 15 cursos)", (tester) async {
        _configurar(tester, escala: escala);
        await calentar(tester);

        expect(await _desborde(tester, const PantallaTeoria()), isNull);
        // Biología es el primero por orden alfabético: el único que se puede
        // afirmar que está en pantalla sin depender de cuántos quepan.
        expect(find.text("Biología"), findsOneWidget);
      });

      testWidgets("Buscar, con resultados", (tester) async {
        _configurar(tester, escala: escala);
        await calentar(tester);

        await tester.pumpWidget(_envolver(const PantallaBuscar()));
        await tester.pump();
        // «quimica» sin tilde: pasa por el normalizador y da muchos aciertos.
        await tester.enterText(find.byType(TextField), "quimica");
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
        expect(find.textContaining("resultado"), findsWidgets);
      });

      testWidgets("Curso (el de nombre más largo)", (tester) async {
        _configurar(tester, escala: escala);
        await calentar(tester);

        final temario = await RepositorioTemario().cargar();
        final curso = temario.cursos.reduce(
          (a, b) => a.nombre.length >= b.nombre.length ? a : b,
        );

        expect(await _desborde(tester, PantallaCurso(curso: curso)), isNull);
        expect(find.text(curso.nombre), findsWidgets);
      });

      testWidgets("índice de un curso de teoría (Química, 234 secciones)", (
        tester,
      ) async {
        _configurar(tester, escala: escala);
        await calentar(tester);

        final cursos = await RepositorioTeoria().cursos();
        final curso = cursos.firstWhere((c) => c.slug == "quimica");

        expect(
          await _desborde(tester, PantallaCursoTeoria(curso: curso)),
          isNull,
        );
        expect(find.byType(ListTile), findsWidgets);
      });

      testWidgets("Aviso con acción y detalle largo", (tester) async {
        _configurar(tester, escala: escala);

        expect(
          await _desborde(
            tester,
            Scaffold(
              body: Aviso(
                icono: Icons.cloud_off_outlined,
                titulo: "No se pudieron cargar los simulacros",
                detalle:
                    "El cronómetro, el puntaje y la comparación con otros "
                    "postulantes se calculan en el servidor.",
                accion: ("Reintentar", () {}),
              ),
            ),
          ),
          isNull,
        );
        expect(find.text("Reintentar"), findsOneWidget);
      });
    });
  }
}
