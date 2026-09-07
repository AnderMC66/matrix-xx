import "package:flutter/material.dart";

/// La paleta sale de `src/app/globals.css`, token por token.
///
/// La app web quedó fijada en **tema claro** a propósito (ESTADO.md § 8, "La
/// app pasa a claro fijo"): en oscuro el granate de marca se aclaraba a un
/// rosa que no es la marca. Aquí se replica esa decisión — un solo tema — para
/// que las dos plataformas se vean iguales.
class Paleta {
  static const fondo = Color(0xFFFFFFFF);
  static const superficie = Color(0xFFF7F7F8);
  static const superficieAlta = Color(0xFFFFFFFF);
  static const borde = Color(0xFFE3E3E6);
  static const bordeFuerte = Color(0xFFC8C9CE);

  static const texto = Color(0xFF16171A); // 16.7:1
  static const textoSuave = Color(0xFF5D6066); // 5.9:1
  static const textoTenue = Color(0xFF686B72); // 4.99:1 — solo metadatos

  /// El granate exacto del ícono. 9.35:1 sobre blanco.
  static const acento = Color(0xFF8A1538);
  static const acentoSuave = Color(0xFFFBE9EE);
  static const acentoContraste = Color(0xFFFFFFFF);

  static const exito = Color(0xFF0B6B3F); // 6.6:1
  static const exitoSuave = Color(0xFFE7F4EE);
  static const aviso = Color(0xFF8A5A00); // 5.9:1
  static const avisoSuave = Color(0xFFFDF3DD);
}

ThemeData construirTema() {
  final base = ThemeData.light(useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: Paleta.superficie,
    colorScheme: base.colorScheme.copyWith(
      primary: Paleta.acento,
      onPrimary: Paleta.acentoContraste,
      primaryContainer: Paleta.acentoSuave,
      onPrimaryContainer: Paleta.acento,
      surface: Paleta.superficieAlta,
      onSurface: Paleta.texto,
      outline: Paleta.borde,
      outlineVariant: Paleta.bordeFuerte,
      error: Paleta.acento,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Paleta.fondo,
      foregroundColor: Paleta.texto,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Paleta.superficieAlta,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Paleta.borde),
      ),
      margin: EdgeInsets.zero,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Paleta.fondo,
      indicatorColor: Paleta.acentoSuave,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (estados) => TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: estados.contains(WidgetState.selected)
              ? Paleta.acento
              : Paleta.textoSuave,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (estados) => IconThemeData(
          color: estados.contains(WidgetState.selected)
              ? Paleta.acento
              : Paleta.textoSuave,
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Paleta.borde, thickness: 1),
  );
}
