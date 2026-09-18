import "package:flutter/material.dart";

/// El tema de la app: un `ColorScheme` de Material 3 derivado de una semilla,
/// una escala tipográfica de siete tamaños, y los tokens propios que M3 no
/// tiene.
///
/// **Esto sustituye a una paleta escrita a mano, y el cambio es de fondo.**
/// Antes había quince constantes de color sueltas, elevación 0 en todo,
/// `surfaceTint` transparente y ninguna escala de texto: 191 `fontSize`
/// literales repartidos por las pantallas, con 26 tamaños distintos —10, 10,5,
/// 11, 11,5, 12, 12,5…—. Eso no era un estilo, era la ausencia de uno: nadie
/// decidió que un metadato midiera 12,5 px aquí y 11,5 allí.
///
/// Con un `ColorScheme` de verdad, Flutter aporta gratis lo que había que
/// pintar a mano: elevación tonal, capas de estado en cada pulsación, y treinta
/// roles de color que se derivan solos y mantienen el contraste entre sí.

/// La semilla de la que sale todo.
///
/// **Era `#8A1538`, el granate del ícono, y se cambió a propósito.** Dos
/// motivos, los dos comprobados y no opinados:
///
/// **El granate era también el color del error.** `error: Paleta.acento`, y en
/// `practica.dart` la alternativa fallada se pintaba con él. Así que la marca
/// era a la vez «esta es nuestra función estrella» y «te equivocaste», en una
/// app donde el alumno falla constantemente. Material 3 deriva `error` aparte
/// de la semilla —#BA1A1A en claro, #FFB4AB en oscuro— y eso deshace el cruce
/// sin que haya que acordarse.
///
/// **El granate no sobrevive al modo oscuro.** `ColorScheme.fromSeed` lo
/// convierte en #FFB2BD, un rosa. El comentario que había aquí ya lo decía
/// —«en oscuro el granate se aclaraba a un rosa que no es la marca»— y por eso
/// la app se había fijado en claro. El índigo aguanta: #3525CD en claro,
/// #C3C0FF en oscuro, azul en los dos.
///
/// El ícono del launcher sigue siendo el lockup granate. Hay que regenerarlo
/// —ver LEEME.md— y hasta entonces no pega con lo que hay dentro.
const semillaMarca = Color(0xFF4F46E5);

/// `fidelity` y no la variante por defecto.
///
/// `tonalSpot`, que es lo que usa `fromSeed` si no se le dice nada, desatura la
/// semilla para armonizarla: #4F46E5 sale como #5A5892, un gris azulado. Es la
/// razón por la que tantas apps con `fromSeed` se ven lavadas.
///
/// `fidelity` conserva el color pedido: lo deja tal cual como
/// `primaryContainer` (#4F46E5) y deriva el resto alrededor. Lo que se elige es
/// lo que se ve.
const _variante = DynamicSchemeVariant.fidelity;

/// **Las superficies se neutralizan a mano, y es lo que separa esta app de
/// una plantilla.**
///
/// `fidelity` tiñe también los grises con la semilla: `surface` salía #FCF8FF
/// y `surfaceContainer` #F0ECF9, los dos lavanda. Eso es lo que hace que
/// tantas apps con `fromSeed` se reconozcan al instante como «Material 3 por
/// defecto» — no el color de acento, sino el fondo teñido.
///
/// Aquí el índigo se queda donde tiene que estar —botones, cifras, lo
/// seleccionado— y el papel sobre el que se lee vuelve a ser papel. En una app
/// que son mayormente párrafos de teoría y enunciados, el fondo tiene que
/// desaparecer, no aportar.
ColorScheme _esquema(Brightness brillo) {
  final base = ColorScheme.fromSeed(
    seedColor: semillaMarca,
    brightness: brillo,
    dynamicSchemeVariant: _variante,
  );
  return brillo == Brightness.light
      ? base.copyWith(
          surface: const Color(0xFFFFFFFF),
          surfaceContainerLowest: const Color(0xFFFFFFFF),
          surfaceContainerLow: const Color(0xFFF7F7F9),
          surfaceContainer: const Color(0xFFF1F1F4),
          surfaceContainerHigh: const Color(0xFFEBEBEF),
          surfaceContainerHighest: const Color(0xFFE5E5EA),
          onSurface: const Color(0xFF16171B),
          onSurfaceVariant: const Color(0xFF55575F),
          outline: const Color(0xFF8B8D95),
          // #DDDEE3 daba 1,26:1 sobre la superficie clara: un borde que no
          // se ve no separa nada. Lo caza `tema_contraste_test.dart`.
          outlineVariant: const Color(0xFFD2D3DA),
        )
      : base.copyWith(
          surface: const Color(0xFF101115),
          surfaceContainerLowest: const Color(0xFF0A0B0E),
          surfaceContainerLow: const Color(0xFF16171C),
          surfaceContainer: const Color(0xFF1A1B21),
          surfaceContainerHigh: const Color(0xFF212229),
          surfaceContainerHighest: const Color(0xFF282A32),
          onSurface: const Color(0xFFE7E8EC),
          onSurfaceVariant: const Color(0xFFA9ABB4),
          outline: const Color(0xFF70727B),
          outlineVariant: const Color(0xFF2F313A),
          // El `errorContainer` oscuro de M3 es #93000A, un rojo saturado que
          // al lado del ámbar y el verde —los dos contenedores apagados— se
          // lee como una alarma y no como una nota. Se baja al mismo registro:
          // fondo profundo, texto claro. El rol `error` a secas no se toca,
          // que es el que de verdad tiene que gritar.
          errorContainer: const Color(0xFF4A1116),
          onErrorContainer: const Color(0xFFFFB4AB),
        );
}

/// Los colores que Material 3 no trae y esta app sí necesita.
///
/// M3 define roles para primario, error y superficies, pero no para «acertaste»
/// ni «cuidado con esto»: no son decoración, son parte del contenido de una app
/// de examen. Van en un `ThemeExtension` y no en constantes sueltas porque
/// **tienen que cambiar con el tema**: un verde que se lee sobre blanco
/// desaparece sobre #13121B.
///
/// Cada par está comprobado contra WCAG AA en `tema_contraste_test.dart`, en
/// los dos modos. Un token que no llega a 4,5:1 rompe la suite.
@immutable
class ColoresApp extends ThemeExtension<ColoresApp> {
  /// Para texto e iconos de «correcta», sobre la superficie del tema.
  final Color exito;

  /// Fondo de un bloque de acierto, con [enExitoContenedor] encima.
  final Color exitoContenedor;
  final Color enExitoContenedor;

  /// Para advertencias que no son errores: «te falta hoy», «son pocas».
  final Color aviso;
  final Color avisoContenedor;
  final Color enAvisoContenedor;

  const ColoresApp({
    required this.exito,
    required this.exitoContenedor,
    required this.enExitoContenedor,
    required this.aviso,
    required this.avisoContenedor,
    required this.enAvisoContenedor,
  });

  static const claro = ColoresApp(
    exito: Color(0xFF0B6B3F), // 6,6:1 sobre #FCF8FF
    exitoContenedor: Color(0xFFD7F0E2),
    enExitoContenedor: Color(0xFF04371F), // 10,9:1 sobre su contenedor
    aviso: Color(0xFF8A5A00), // 5,0:1 sobre #FCF8FF
    avisoContenedor: Color(0xFFFBEBC8),
    enAvisoContenedor: Color(0xFF3D2800), // 11,6:1 sobre su contenedor
  );

  static const oscuro = ColoresApp(
    exito: Color(0xFF6FDBA8), // 10,2:1 sobre #13121B
    exitoContenedor: Color(0xFF0A3D25),
    enExitoContenedor: Color(0xFFA8F2CC),
    aviso: Color(0xFFF1C27A), // 10,9:1 sobre #13121B
    avisoContenedor: Color(0xFF40300A),
    enAvisoContenedor: Color(0xFFFFE2B0),
  );

  @override
  ColoresApp copyWith({
    Color? exito,
    Color? exitoContenedor,
    Color? enExitoContenedor,
    Color? aviso,
    Color? avisoContenedor,
    Color? enAvisoContenedor,
  }) => ColoresApp(
    exito: exito ?? this.exito,
    exitoContenedor: exitoContenedor ?? this.exitoContenedor,
    enExitoContenedor: enExitoContenedor ?? this.enExitoContenedor,
    aviso: aviso ?? this.aviso,
    avisoContenedor: avisoContenedor ?? this.avisoContenedor,
    enAvisoContenedor: enAvisoContenedor ?? this.enAvisoContenedor,
  );

  @override
  ColoresApp lerp(ColoresApp? otro, double t) {
    if (otro == null) return this;
    return ColoresApp(
      exito: Color.lerp(exito, otro.exito, t)!,
      exitoContenedor: Color.lerp(exitoContenedor, otro.exitoContenedor, t)!,
      enExitoContenedor: Color.lerp(
        enExitoContenedor,
        otro.enExitoContenedor,
        t,
      )!,
      aviso: Color.lerp(aviso, otro.aviso, t)!,
      avisoContenedor: Color.lerp(avisoContenedor, otro.avisoContenedor, t)!,
      enAvisoContenedor: Color.lerp(
        enAvisoContenedor,
        otro.enAvisoContenedor,
        t,
      )!,
    );
  }
}

/// Atajos para no escribir `Theme.of(context)` cuatro veces por widget.
///
/// Son lo que sustituye a `Paleta.texto` y compañía. La diferencia no es de
/// escritura: `Paleta.texto` era una constante y no podía saber en qué tema
/// estaba, así que con dos temas habría pintado negro sobre negro.
extension TemaDeContexto on BuildContext {
  ColorScheme get esquema => Theme.of(this).colorScheme;
  TextTheme get textos => Theme.of(this).textTheme;
  ColoresApp get colores => Theme.of(this).extension<ColoresApp>()!;
}

/// Ocho tamaños, en vez de veintiséis.
///
/// Los nombres son los roles de Material 3, no invenciones: quien conozca M3
/// sabe dónde va cada uno, y los widgets de Flutter ya los usan por defecto
/// —`ListTile` coge `bodyLarge` para el título, `AppBar` coge `titleLarge`—, así
/// que la mitad de los estilos a mano dejan de hacer falta.
///
/// La escala sube por saltos claros (11 · 12 · 14 · 16 · 20 · 24 · 32 · 44).
/// Los medios puntos que había —12,5 · 13,5 · 14,5 · 15,5— no distinguían
/// nada: a esa diferencia el ojo no llega, y lo único que conseguían era que
/// dos cosas del mismo rango parecieran de rangos distintos por accidente.
TextTheme _tipografia(ColorScheme c) => TextTheme(
  // La cifra que ES la pantalla: el puntaje al acabar un simulacro, el
  // porcentaje de una tanda. Se lee de pie, en el micro, de un vistazo.
  displayMedium: TextStyle(
    fontSize: 38,
    fontWeight: FontWeight.w800,
    height: 1.05,
    letterSpacing: -1,
    color: c.primary,
  ),
  // Cifras destacadas dentro de una tarjeta: la racha, un contador.
  displaySmall: TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    height: 1.15,
    letterSpacing: -0.5,
    color: c.onSurface,
  ),
  // Titular de portada.
  headlineMedium: TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.3,
    color: c.onSurface,
  ),
  // Título de pantalla o de sección de teoría.
  headlineSmall: TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.3,
    color: c.onSurface,
  ),
  // Título de tarjeta.
  titleMedium: TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: c.onSurface,
  ),
  // Cuerpo: enunciados, teoría, todo lo que se lee de verdad.
  //
  // 16 px y `height: 1.6`. El cuerpo NO baja de 16: es el mínimo legible en
  // móvil y lo que evita que Android encoja el texto en pantallas densas.
  // 1,45 y no 1,6. El 1,6 es interlineado de lectura larga y está bien para un
  // párrafo de teoría suelto, pero aplicado a TODO —títulos de lista,
  // alternativas, avisos— separa tanto que en una pantalla cabe la mitad. La
  // teoría recupera su aire con el espaciado entre bloques, que es donde
  // corresponde.
  bodyLarge: TextStyle(fontSize: 16, height: 1.45, color: c.onSurface),
  // Texto secundario: descripciones, detalles de un aviso.
  bodyMedium: TextStyle(fontSize: 14, height: 1.4, color: c.onSurfaceVariant),
  // Metadatos: «14 sep · aceptado», «3 de 20».
  bodySmall: TextStyle(fontSize: 12, height: 1.35, color: c.onSurfaceVariant),
  // Etiquetas de control: botones, pestañas, chips.
  labelLarge: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    color: c.onSurface,
  ),
  labelMedium: TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
    color: c.onSurfaceVariant,
  ),
  // Rótulos en mayúsculas: «LO QUE YA RENDISTE».
  labelSmall: TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
    color: c.onSurfaceVariant,
  ),
);

/// Radios contenidos: 10 para lo pequeño, 12 para tarjetas, 20 para diálogos.
///
/// **Eran 12 / 16 / 28 y se veían blandos.** El redondeo generoso de M3 por
/// defecto funciona en una app de fotos o de música; en una de estudio, que es
/// texto denso en listas largas, convierte cada elemento en una píldora y hace
/// que todo parezca del mismo peso. Con esquinas más cerradas la lista se lee
/// como una lista.
const radioChico = 10.0;
const radioTarjeta = 12.0;
const radioGrande = 20.0;

ThemeData construirTema([Brightness brillo = Brightness.light]) {
  final c = _esquema(brillo);

  // **La base se construye primero para poder leer de ella el `textTheme` ya
  // fusionado**, y no es un rodeo.
  //
  // `_tipografia` no fija `fontFamily`: deja que la ponga la plataforma, que
  // es lo correcto —Roboto en Android, San Francisco en iOS—. Pero `ThemeData`
  // solo hace esa fusión para el `textTheme` que recibe; si los temas de
  // componente se arman con los estilos CRUDOS, los botones, la barra y las
  // listas se quedan sin familia y caen al tipo por defecto, que no tiene por
  // qué ser el mismo.
  //
  // Se vio al rendir capturas: el cuerpo y los titulares salían en Roboto y
  // las etiquetas de botón, en otra cosa. En el emulador la diferencia es
  // menor porque el sistema resuelve las dos a Roboto, pero «que coincidan por
  // casualidad» no es lo mismo que «que salgan del mismo sitio».
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: c,
    textTheme: _tipografia(c),
  );
  final textos = base.textTheme;

  return base.copyWith(
    scaffoldBackgroundColor: c.surface,
    extensions: [
      brillo == Brightness.light ? ColoresApp.claro : ColoresApp.oscuro,
    ],

    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      foregroundColor: c.onSurface,
      // El tinte de superficie al hacer scroll es de M3 y estaba apagado. Es lo
      // que separa la barra del contenido sin pintar una línea: la barra se
      // tiñe sola cuando hay algo debajo.
      scrolledUnderElevation: 3,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: textos.titleMedium,
    ),

    cardTheme: CardThemeData(
      color: c.surface,
      // Elevación 0 con un borde tenue: en M3 las tarjetas se separan por tono,
      // no por sombra. Una sombra sobre una superficie ya teñida se lee como
      // suciedad.
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radioTarjeta),
        side: BorderSide(color: c.outlineVariant),
      ),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // 46 de alto y 18 de lado. El mínimo táctil de 48 lo sigue cumpliendo
        // el área de toque, que Material extiende más allá del borde pintado.
        minimumSize: const Size(64, 46),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        textStyle: textos.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radioChico),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 46),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        textStyle: textos.labelLarge,
        side: BorderSide(color: c.outline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radioChico),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 44),
        textStyle: textos.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radioChico),
        ),
      ),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surfaceContainer,
      // Un tinte del primario en vez del `secondaryContainer` lavanda, que es
      // la señal más reconocible de un tema sin tocar.
      indicatorColor: c.primary.withValues(alpha: 0.14),
      elevation: 0,
      // 80 dp es la altura de M3; la de M2 era 56 y apretaba icono y etiqueta.
      // 68 y no los 80 de M3: con cinco destinos y etiqueta siempre visible,
      // 80 dp se comen el 10 % de un móvil de 844.
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (estados) => textos.labelMedium!.copyWith(
          color: estados.contains(WidgetState.selected)
              ? c.onSecondaryContainer
              : c.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (estados) => IconThemeData(
          size: 24,
          color: estados.contains(WidgetState.selected)
              ? c.onSecondaryContainer
              : c.onSurfaceVariant,
        ),
      ),
    ),

    chipTheme: ChipThemeData(
      labelStyle: textos.labelLarge,
      side: BorderSide(color: c.outlineVariant),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radioChico),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceContainerHighest,
      // Sin borde visible en reposo y con uno de acento al enfocar: es el campo
      // de M3, y deja el formulario mucho más tranquilo que cinco rectángulos.
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radioChico),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radioChico),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radioChico),
        borderSide: BorderSide(color: c.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radioChico),
        borderSide: BorderSide(color: c.error, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      labelStyle: textos.bodyMedium,
      helperStyle: textos.bodySmall,
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: c.surfaceContainerHigh,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radioGrande),
      ),
      titleTextStyle: textos.headlineSmall,
      contentTextStyle: textos.bodyMedium,
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.inverseSurface,
      contentTextStyle: textos.bodyMedium!.copyWith(color: c.onInverseSurface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radioChico),
      ),
    ),

    listTileTheme: ListTileThemeData(
      titleTextStyle: textos.titleMedium,
      subtitleTextStyle: textos.bodySmall,
      iconColor: c.onSurfaceVariant,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radioChico),
      ),
    ),

    dividerTheme: DividerThemeData(color: c.outlineVariant, thickness: 1),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.primary,
      linearTrackColor: c.surfaceContainerHighest,
    ),
  );
}
