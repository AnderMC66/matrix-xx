import "package:flutter/cupertino.dart" show CupertinoPageTransitionsBuilder;
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
          // `systemGroupedBackground`: el lienzo NO es blanco. Es el gris
          // sobre el que flotan las tarjetas blancas, y es lo que hace que
          // una lista agrupada de iOS se lea como tarjetas y no como bloques
          // pegados al fondo.
          surface: const Color(0xFFF2F2F7),
          // Las tarjetas, blancas puras. El contraste entre #FFFFFF y
          // #F2F2F7 es todo lo que separa una fila de su fondo: ni bordes ni
          // sombras duras.
          surfaceContainerLowest: const Color(0xFFFFFFFF),
          surfaceContainerLow: const Color(0xFFFFFFFF),
          // `tertiarySystemFill`: el relleno de los campos de texto.
          surfaceContainer: const Color(0xFFE5E5EA),
          surfaceContainerHigh: const Color(0xFFE5E5EA),
          surfaceContainerHighest: const Color(0xFFD1D1D6),
          onSurface: const Color(0xFF000000),
          // **#636366 y no el #8E8E93 de iOS.** Sobre #F2F2F7, el gris de
          // sistema de Apple da 2,85:1 y WCAG AA pide 4,5:1 para texto
          // pequeno. Apple se lo permite porque sus reglas de contraste son
          // otras; aqui el texto secundario es casi todo de 12-14 px y se lee
          // en un micro con el brillo bajo. El #8E8E93 sigue disponible en
          // [ColoresApp.grisSutil] para lo decorativo.
          onSurfaceVariant: const Color(0xFF636366),
          // **`outline` dibuja bordes de CONTROL** —el de un boton secundario—
          // y WCAG 1.4.11 le pide 3:1. El separador de iOS (#C6C6C8) da 1,53:1
          // y no vale para eso; vive aparte, en [ColoresApp.separador], porque
          // ahi si es decorativo: dentro de una tarjeta agrupada quien separa
          // las filas es la tarjeta, y la linea solo insinua.
          outline: const Color(0xFF79797E),
          outlineVariant: const Color(0xFFD6D6DB),
        )
      : base.copyWith(
          // Negro puro: es lo que hace que en un OLED la tarjeta #1C1C1E
          // parezca elevada sin pintar ni una sombra.
          surface: const Color(0xFF000000),
          surfaceContainerLowest: const Color(0xFF1C1C1E),
          surfaceContainerLow: const Color(0xFF1C1C1E),
          surfaceContainer: const Color(0xFF2C2C2E),
          surfaceContainerHigh: const Color(0xFF2C2C2E),
          surfaceContainerHighest: const Color(0xFF3A3A3C),
          onSurface: const Color(0xFFFFFFFF),
          // #9A9AA0 y no el #8E8E93 literal: sobre negro el de Apple cumple
          // de sobra (6,6:1), pero sobre el relleno de campo #2C2C2E se queda
          // en 4,27:1. Dos puntos mas claro y pasa en los dos fondos.
          onSurfaceVariant: const Color(0xFF9A9AA0),
          outline: const Color(0xFF6E6E73),
          outlineVariant: const Color(0xFF3A3A3C),
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

  /// El `systemGrey` literal de iOS (#8E8E93), **solo para lo decorativo**:
  /// marcadores de posicion, iconos apagados, el chevron de una fila.
  ///
  /// No es para texto que haya que leer. Sobre el fondo claro da 2,85:1 y WCAG
  /// AA pide 4,5:1; para eso esta `onSurfaceVariant`, que en claro es mas
  /// profundo justo por esto.
  final Color grisSutil;

  /// La linea entre filas de una tarjeta agrupada (#C6C6C8 / #38383A).
  ///
  /// Deliberadamente por debajo del 3:1 que WCAG pide a los bordes de control,
  /// y no es un descuido: aqui no delimita nada que se pueda pulsar. Lo que
  /// agrupa es la tarjeta blanca sobre el fondo gris; la linea solo evita que
  /// dos filas se lean como un parrafo. Un separador al 3:1 seria una raya.
  final Color separador;

  const ColoresApp({
    required this.exito,
    required this.exitoContenedor,
    required this.enExitoContenedor,
    required this.aviso,
    required this.avisoContenedor,
    required this.enAvisoContenedor,
    required this.grisSutil,
    required this.separador,
  });

  static const claro = ColoresApp(
    exito: Color(0xFF0B6B3F), // 6,6:1 sobre #FCF8FF
    exitoContenedor: Color(0xFFD7F0E2),
    enExitoContenedor: Color(0xFF04371F), // 10,9:1 sobre su contenedor
    aviso: Color(0xFF8A5A00), // 5,0:1 sobre #FCF8FF
    avisoContenedor: Color(0xFFFBEBC8),
    enAvisoContenedor: Color(0xFF3D2800), // 11,6:1 sobre su contenedor
    grisSutil: Color(0xFF8E8E93),
    separador: Color(0xFFC6C6C8),
  );

  static const oscuro = ColoresApp(
    exito: Color(0xFF6FDBA8), // 10,2:1 sobre #13121B
    exitoContenedor: Color(0xFF0A3D25),
    enExitoContenedor: Color(0xFFA8F2CC),
    aviso: Color(0xFFF1C27A), // 10,9:1 sobre #13121B
    avisoContenedor: Color(0xFF40300A),
    enAvisoContenedor: Color(0xFFFFE2B0),
    grisSutil: Color(0xFF8E8E93),
    separador: Color(0xFF38383A),
  );

  @override
  ColoresApp copyWith({
    Color? exito,
    Color? exitoContenedor,
    Color? enExitoContenedor,
    Color? aviso,
    Color? avisoContenedor,
    Color? enAvisoContenedor,
    Color? grisSutil,
    Color? separador,
  }) => ColoresApp(
    exito: exito ?? this.exito,
    exitoContenedor: exitoContenedor ?? this.exitoContenedor,
    enExitoContenedor: enExitoContenedor ?? this.enExitoContenedor,
    aviso: aviso ?? this.aviso,
    avisoContenedor: avisoContenedor ?? this.avisoContenedor,
    enAvisoContenedor: enAvisoContenedor ?? this.enAvisoContenedor,
    grisSutil: grisSutil ?? this.grisSutil,
    separador: separador ?? this.separador,
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
      grisSutil: Color.lerp(grisSutil, otro.grisSutil, t)!,
      separador: Color.lerp(separador, otro.separador, t)!,
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
/// La tipografia de iOS es mas apretada de lo que Flutter pone por defecto.
///
/// SF Pro lleva *tracking* negativo en los tamanos grandes y casi nulo en el
/// cuerpo; Roboto viene con tracking positivo. Ese solo ajuste es la mitad de
/// lo que hace que un titulo «parezca de iOS», y no cuesta ninguna fuente.
///
/// **SF Pro no se puede empaquetar en una app de Android**: la licencia de
/// Apple la limita a sus plataformas. La alternativa honesta es Inter, que es
/// casi indistinguible en pantalla; hay que bajarla como asset. Mientras no
/// este, la del sistema con estas metricas se acerca bastante. Ver LEEME.md.
TextTheme _tipografia(ColorScheme c) => TextTheme(
  // *Large Title* de iOS: 34 px, peso fuerte, tracking negativo. Es la pieza
  // mas reconocible del lenguaje — la cabecera grande que se encoge al hacer
  // scroll.
  displayLarge: TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    height: 1.15,
    letterSpacing: -0.9,
    color: c.onSurface,
  ),
  // La cifra que ES la pantalla: el puntaje al acabar un simulacro, el
  // porcentaje de una tanda. Se lee de pie, en el micro, de un vistazo.
  displayMedium: TextStyle(
    fontSize: 38,
    fontWeight: FontWeight.w700,
    height: 1.05,
    letterSpacing: -1.2,
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
  bodyLarge: TextStyle(
    fontSize: 16,
    height: 1.45,
    letterSpacing: -0.2,
    color: c.onSurface,
  ),
  // Texto secundario: descripciones, detalles de un aviso.
  bodyMedium: TextStyle(fontSize: 14, height: 1.4, color: c.onSurfaceVariant),
  // Metadatos: «14 sep · aceptado», «3 de 20».
  bodySmall: TextStyle(fontSize: 12, height: 1.35, color: c.onSurfaceVariant),
  // Etiquetas de control: botones, pestañas, chips.
  labelLarge: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
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

/// Radios al gusto de iOS: 12 para campos, 18 para tarjetas agrupadas,
/// 14 para el boton prominente y 28 para hojas modales.
///
/// iOS usa esquinas continuas (*squircle*) mas que circulares; Flutter no las
/// trae de serie y la diferencia a estos tamanos es de un pixel o dos, asi que
/// se usa `BorderRadius.circular` y se compensa con radios algo mayores.
const radioCampo = 12.0;
const radioTarjeta = 18.0;
const radioBoton = 14.0;
const radioHoja = 28.0;

/// La sombra de una tarjeta agrupada: muy difusa y muy tenue.
///
/// Es lo contrario de la sombra de Material: nada de un borde oscuro pegado al
/// contenedor, sino un halo ancho que apenas se ve y que solo sirve para
/// despegar la tarjeta del gris del fondo. En oscuro no se pinta —sobre negro
/// una sombra no existe— y el relieve lo da el propio #1C1C1E.
List<BoxShadow> sombraTarjeta(Brightness brillo) => brillo == Brightness.dark
    ? const []
    : const [
        BoxShadow(
          color: Color(0x0F000000),
          blurRadius: 24,
          offset: Offset(0, 8),
          spreadRadius: -4,
        ),
      ];

/// Alias que conservan los nombres anteriores para el resto de pantallas.
const radioChico = radioCampo;
const radioGrande = radioHoja;

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

    // **Deslizar desde el borde para volver, tambien en Android.**
    //
    // `CupertinoPageTransitionsBuilder` no solo cambia la animacion —la nueva
    // pantalla entra desde la derecha y la anterior se va con parallax—: trae
    // el gesto de arrastre desde el borde izquierdo, que es lo que un usuario
    // de iOS busca con el pulgar antes de mirar si hay flecha.
    //
    // Se aplica a las dos plataformas a proposito. En Android convive con el
    // boton de atras del sistema y con el gesto predictivo: no sustituye a
    // ninguno, se suma.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    extensions: [
      brillo == Brightness.light ? ColoresApp.claro : ColoresApp.oscuro,
    ],

    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      foregroundColor: c.onSurface,
      // El tinte de superficie al hacer scroll es de M3 y estaba apagado. Es lo
      // que separa la barra del contenido sin pintar una línea: la barra se
      // tiñe sola cuando hay algo debajo.
      //
      // Pero M3 tiñe con `primary`, y con la semilla índigo eso pintaba una
      // franja lila sobre la barra en cuanto se bajaba un dedo. En iOS la
      // barra al hacer scroll no se tiñe de la marca: se vuelve un gris
      // neutro y algo traslúcido. `onSurface` da exactamente eso —negro al
      // 5 % sobre #F2F2F7 en claro, blanco al 5 % sobre negro en oscuro— sin
      // renunciar a la separación.
      surfaceTintColor: c.onSurface,
      scrolledUnderElevation: 3,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: textos.titleMedium,
    ),

    cardTheme: CardThemeData(
      color: c.surfaceContainerLowest,
      // Sin borde y sin elevacion de Material: la tarjeta se separa del fondo
      // porque el fondo NO es blanco (#F2F2F7), no porque lleve una linea.
      // La sombra difusa la pone quien dibuja el contenedor, con
      // `sombraTarjeta`, para poder omitirla en oscuro.
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radioTarjeta),
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
          borderRadius: BorderRadius.circular(radioBoton),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 50),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
      fillColor: c.surfaceContainer,
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
      // Un anillo fino al enfocar, no los 2 px de Material. iOS no lo pinta
      // en absoluto, pero un campo enfocado sin ninguna senal visible es un
      // fallo de accesibilidad para quien navega con teclado: se deja el
      // minimo que se ve.
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radioCampo),
        borderSide: BorderSide(color: c.primary, width: 1.5),
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
