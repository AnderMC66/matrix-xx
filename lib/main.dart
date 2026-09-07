import "package:flutter/material.dart";
import "package:supabase_flutter/supabase_flutter.dart";

import "config.dart";
import "pantallas/teoria.dart";
import "tema.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sin configuración no se inicializa el cliente: así el fallo es una
  // pantalla que explica qué falta, y no una excepción opaca dentro de
  // Supabase la primera vez que alguien pulsa "Entrar".
  if (Config.configurado) {
    await Supabase.initialize(
      url: Config.urlSupabase,
      publishableKey: Config.clavePublishable,
    );
  }

  runApp(const AppMatrixU());
}

class AppMatrixU extends StatelessWidget {
  const AppMatrixU({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: "Matrix U",
    debugShowCheckedModeBanner: false,
    theme: construirTema(),
    home: const Armazon(),
  );
}

/// Los cinco destinos son los mismos que la barra móvil de la web
/// (`src/components/nav-mobile.tsx`), en el mismo orden.
class Armazon extends StatefulWidget {
  const Armazon({super.key});

  @override
  State<Armazon> createState() => _ArmazonState();
}

class _ArmazonState extends State<Armazon> {
  int _destino = 1; // arranca en Teoría: es lo único portado por ahora

  static const _titulos = [
    "Repaso",
    "Teoría",
    "Práctica",
    "Simulacro",
    "Progreso",
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _titulos[_destino],
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Paleta.borde),
        ),
      ),
      body: switch (_destino) {
        1 => const PantallaTeoria(),
        _ => _PorPortar(nombre: _titulos[_destino]),
      },
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
}

/// Marcador honesto: la sección existe en la web y todavía no aquí. Es
/// preferible a una pantalla en blanco que parece un fallo.
class _PorPortar extends StatelessWidget {
  final String nombre;
  const _PorPortar({required this.nombre});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.construction_outlined, size: 40, color: Paleta.textoTenue),
          const SizedBox(height: 16),
          Text(
            "$nombre todavía no está portado",
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Paleta.texto,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Existe en la web. Va en el siguiente tramo del porte.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Paleta.textoSuave, fontSize: 13),
          ),
        ],
      ),
    ),
  );
}
