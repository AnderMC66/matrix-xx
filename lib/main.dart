import "dart:async";

import "package:flutter/material.dart";
import "package:supabase_flutter/supabase_flutter.dart";

import "config.dart";
import "datos/figuras_rotas.dart";
import "datos/sesion.dart";
import "pantallas/buscar.dart";
import "pantallas/entrar.dart";
import "pantallas/inicio.dart";
import "pantallas/practica.dart";
import "pantallas/progreso.dart";
import "pantallas/repaso.dart";
import "pantallas/simulacro.dart";
import "pantallas/teoria.dart";
import "tema.dart";
import "widgets/aviso.dart";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AppMatrixU());
}

class AppMatrixU extends StatelessWidget {
  const AppMatrixU({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: "Matrix U",
    debugShowCheckedModeBanner: false,
    theme: construirTema(),
    home: const Arranque(),
  );
}

/// Inicializa Supabase antes de montar el resto de la app.
///
/// Deliberadamente NO se hace con un `await` en `main()` antes de `runApp()`
/// —así estaba, y así fallaba—: en un *hot restart* (no en un APK instalado
/// normalmente, que siempre arranca en frío) el motor de Flutter puede
/// disparar un primer "warm up frame" apenas reinicia el isolate, sin
/// esperar a que ese `await` termine. Ese frame reconstruye lo último que
/// `runApp()` recibió, y si eso ya era `Armazon` —que construye `Sesion()`
/// como campo de instancia, y `Sesion()` toca `Supabase.instance.client` en
/// su propio constructor— revienta con «You must initialize the supabase
/// instance before calling Supabase.instance», porque el nuevo isolate
/// resetea ese singleton y el `main()` nuevo todavía no llegó a
/// reinicializarlo.
///
/// Aquí ese primer build nunca toca Supabase: solo decide entre un aviso, un
/// spinner o `Armazon`, y quien dispara la inicialización de verdad es
/// `initState()` — que el framework garantiza que corre DESPUÉS del primer
/// build, nunca antes, warm-up-frame incluido.
class Arranque extends StatefulWidget {
  /// Sustituye la inicialización real. Existe para los tests: la suite corre
  /// sin `--dart-define-from-file`, así que `Config.configurado` es `false` y
  /// sin esta costura el camino del fallo de inicialización es inalcanzable —
  /// `build` sale antes por `_SinConfigurar`. Pasarlo también salta esa salida,
  /// porque quien inyecta una inicialización está diciendo que hay algo que
  /// inicializar. En producción nadie lo pasa.
  final Future<void> Function()? inicializador;

  const Arranque({super.key, this.inicializador});

  @override
  State<Arranque> createState() => _ArranqueState();
}

class _ArranqueState extends State<Arranque> {
  // No es `late final`: «Reintentar» tiene que poder rehacer el intento. No
  // hace falta ninguna guarda contra inicializar dos veces — `initialize()`
  // devuelve la instancia existente si ya está inicializada.
  Future<void>? _inicializacion;

  @override
  void initState() {
    super.initState();
    _reintentar();
  }

  void _reintentar() {
    setState(() {
      _inicializacion = _inicializar();
    });
  }

  Future<void> _inicializar() async {
    if (widget.inicializador case final propio?) return propio();

    // Teoría (y sus figuras) funciona sin sesión ni Supabase configurado, así
    // que esta carga no puede depender de `Config.configurado`.
    await RepositorioFigurasRotas.instancia.cargar();

    if (!Config.configurado) return;
    await Supabase.initialize(
      url: Config.urlSupabase,
      publishableKey: Config.clavePublishable,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Sin configuración no hay nada que inicializar: el fallo es una
    // pantalla que explica qué falta, y no una excepción opaca dentro de
    // Supabase la primera vez que alguien pulsa "Entrar".
    if (!Config.configurado && widget.inicializador == null) {
      return const _SinConfigurar();
    }

    return FutureBuilder<void>(
      future: _inicializacion,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        // Si la inicialización lanzó, `connectionState` llega a `done` igual.
        // Seguir adelante montaba `PantallaInicio`, cuyo estado construye
        // `Sesion()` como campo de instancia, y `Sesion()` toca
        // `Supabase.instance.client` — que sin inicializar lanza la misma
        // excepción que toda la coreografía de esta clase evita en el hot
        // restart. El resultado era una pantalla roja en el arranque en vez
        // del fallo explicado que ya existe para la configuración ausente.
        if (snapshot.hasError) {
          return _NoArranco(error: snapshot.error!, alReintentar: _reintentar);
        }
        return const PantallaInicio();
      },
    );
  }
}

class _NoArranco extends StatelessWidget {
  final Object error;
  final VoidCallback alReintentar;

  const _NoArranco({required this.error, required this.alReintentar});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Aviso(
      icono: Icons.error_outline,
      titulo: "La app no pudo arrancar",
      detalle:
          "No se pudo inicializar la conexión con el servidor.\n\n"
          "$error",
      accion: ("Reintentar", alReintentar),
      esError: true,
    ),
  );
}

class _SinConfigurar extends StatelessWidget {
  const _SinConfigurar();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          Config.ayuda,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Paleta.textoSuave, height: 1.5),
        ),
      ),
    ),
  );
}

/// Los cinco destinos son los mismos que la barra móvil de la web
/// (`src/components/nav-mobile.tsx`), en el mismo orden.
class Armazon extends StatefulWidget {
  /// Qué pestaña abrir primero. Lo usa `PantallaInicio` para que un acceso
  /// directo («Empezar a practicar») caiga en la pestaña que promete, no
  /// siempre en la misma.
  final int destinoInicial;

  /// Sustituye la sesión real. Existe para los tests, igual que
  /// [Arranque.inicializador]: `Sesion()` toca `Supabase.instance.client` en
  /// su constructor, así que sin esta costura el armazón no se puede montar
  /// fuera de una app con Supabase inicializado. En producción nadie la pasa.
  final Sesion? sesion;

  const Armazon({super.key, this.destinoInicial = 1, this.sesion});

  @override
  State<Armazon> createState() => _ArmazonState();
}

class _ArmazonState extends State<Armazon> {
  late int _destino =
      widget.destinoInicial; // por defecto Teoría: se lee sin cuenta

  late final _sesion = widget.sesion ?? Sesion();
  StreamSubscription<AuthState>? _escucha;

  static const _titulos = [
    "Repaso",
    "Teoría",
    "Práctica",
    "Simulacro",
    "Progreso",
  ];

  @override
  void initState() {
    super.initState();
    // Entrar o salir cambia lo que puede hacer media app (practicar, repasar,
    // ver progreso), así que el armazón se reconstruye con cada cambio en vez
    // de que cada pantalla consulte la sesión por su cuenta.
    if (Config.configurado) {
      _escucha = _sesion.cambios.listen((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _escucha?.cancel();
    super.dispose();
  }

  /// Las pestañas de catálogo que ya se visitaron. Se construyen la primera
  /// vez y a partir de ahí se quedan montadas, con su scroll y su estado.
  ///
  /// Perezoso a propósito: montar las cinco pantallas en el primer frame
  /// haría que abrir la app cargara el banco y la teoría de golpe, y la
  /// mayoría de sesiones no pasan por todas.
  final _visitadas = <int, Widget>{};

  /// Una pestaña de catálogo: se monta una vez y se conserva.
  Widget _catalogo(int indice, Widget pantalla) {
    if (_destino == indice) _visitadas[indice] ??= pantalla;
    return _visitadas[indice] ?? const SizedBox.shrink();
  }

  /// Una pestaña que lee del servidor: solo existe mientras se mira, para que
  /// lo que enseña sea de ahora y no de la última vez que se pasó por aquí.
  Widget _servidor(int indice, Widget pantalla) =>
      _destino == indice ? pantalla : const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    final hayCuenta = Config.configurado && _sesion.hayCuenta;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _titulos[_destino],
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          // `Inicio` (`/`) tampoco vive en la barra móvil de la web —el
          // header con el logo que lleva ahí está oculto en móvil— así que
          // en la práctica solo se llega la primera vez que se abre la app.
          // Este ícono es la única forma de volver después.
          IconButton(
            tooltip: "Inicio",
            icon: const Icon(Icons.home_outlined, color: Paleta.textoSuave),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const PantallaInicio())),
          ),
          // En la web, Temario y Buscar viven en el nav de escritorio, no en
          // la barra móvil (que ya tiene sus cinco huecos, sin sitio para
          // más). Aquí un solo ícono de lupa basta como puerta de entrada a
          // las dos: el estado vacío de Buscar ofrece "Ver el temario
          // completo", así que no hace falta un segundo ícono para Temario.
          IconButton(
            tooltip: "Buscar en el temario",
            icon: const Icon(Icons.search, color: Paleta.textoSuave),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const PantallaBuscar())),
          ),
          if (Config.configurado)
            IconButton(
              tooltip: hayCuenta ? "Cerrar sesión" : "Entrar",
              icon: Icon(
                hayCuenta ? Icons.logout : Icons.login,
                color: Paleta.textoSuave,
              ),
              onPressed: () async {
                if (hayCuenta) {
                  await _sesion.salir();
                } else {
                  _abrirEntrar();
                }
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Paleta.borde),
        ),
      ),
      // Teoría y Práctica se quedan montadas; las otras tres se rehacen.
      //
      // Antes esto era un `switch` que devolvía una pantalla distinta por
      // pestaña, así que cambiar de pestaña DESTRUÍA la anterior: volver a
      // Teoría después de mirar Práctica te devolvía al principio de la lista
      // de cursos, y lo mismo con el índice de secciones o con la búsqueda a
      // medio escribir. En una app que se usa a ratos, entre clase y clase,
      // perder el sitio en cada ida y vuelta se nota más que ninguna otra
      // cosa de esta pantalla.
      //
      // **Pero no se conservan las cinco, y la diferencia importa.** Teoría y
      // Práctica se alimentan del catálogo del APK, que es inmutable: guardar
      // su estado no puede enseñar nada viejo. Repaso, Simulacro y Progreso
      // leen del servidor lo que el propio alumno acaba de cambiar —responder
      // una pregunta mueve la racha, el calendario de repasos y el
      // diagnóstico—, así que mantenerlas vivas mostraría cifras de hace un
      // rato como si fueran de ahora. Esas se siguen rehaciendo al entrar,
      // que es lo que las mantiene honestas.
      //
      // La clave por sesión sigue estando por el motivo de siempre: sin ella,
      // Repaso y Simulacro conservarían el `Future` que resolvieron sin
      // cuenta y seguirían pidiendo iniciar sesión después de haberla
      // iniciado.
      body: IndexedStack(
        index: _destino,
        children: [
          _servidor(0, PantallaRepaso(key: ValueKey(hayCuenta))),
          _catalogo(1, const PantallaTeoria()),
          _catalogo(2, const PantallaPractica()),
          _servidor(3, PantallaSimulacro(key: ValueKey(hayCuenta))),
          _servidor(4, PantallaProgreso(key: ValueKey(hayCuenta))),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _destino,
        onDestinationSelected: (i) => setState(() => _destino = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.replay_outlined),
            selectedIcon: Icon(Icons.replay),
            label: "Repaso",
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: "Teoría",
          ),
          NavigationDestination(
            icon: Icon(Icons.edit_outlined),
            selectedIcon: Icon(Icons.edit),
            label: "Práctica",
          ),
          NavigationDestination(
            icon: Icon(Icons.timer_outlined),
            selectedIcon: Icon(Icons.timer),
            label: "Simulacro",
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: "Progreso",
          ),
        ],
      ),
    );
  }

  void _abrirEntrar() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (contextoRuta) => Scaffold(
          appBar: AppBar(title: const Text("Acceso")),
          body: PantallaEntrar(
            alEntrar: () => Navigator.of(contextoRuta).pop(),
          ),
        ),
      ),
    );
  }
}
