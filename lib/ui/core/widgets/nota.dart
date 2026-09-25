import "package:flutter/material.dart";

import "package:matr_u/ui/core/theme/tema.dart";

/// Un recuadro de color con una frase dentro: lo que la app usa para decir
/// algo al margen del contenido —una advertencia del sílabo, un error de
/// envío, el acuse de un correo de confirmación.
///
/// **Por qué es un archivo aparte, otra vez.** Había cuatro `_Nota` privadas
/// —curso, progreso, práctica y entrar— y ya habían derivado: las de curso y
/// progreso eran idénticas byte a byte, la de práctica pintaba a 13 px lo que
/// las otras pintaban a 12,5, y la de entrar añadía un icono. Ninguna de esas
/// diferencias fue una decisión; es el mismo rastro que dejó ocho copias de
/// `_Aviso` antes de reunirse en `aviso.dart`, y por el mismo motivo se
/// arregla igual.
///
/// La diferencia con `Aviso` es de sitio, no de tono: `Aviso` ocupa el cuerpo
/// de una pantalla cuando no hay nada que mostrar; `Nota` se intercala entre
/// contenido que sí existe.
///
/// El tamaño sale ahora de `bodyMedium` (14) en vez de un 13 escrito a mano.
/// Los cuatro originales usaban 12,5 o 13 según el archivo, y ninguna de esas
/// diferencias fue una decisión.
/// Cada variante elige su par de colores del tema, no constantes.
enum _Tono { aviso, error, exito }

class Nota extends StatelessWidget {
  final String texto;
  final _Tono _tono;

  /// Opcional. Solo lo llevan las notas que interrumpen una tarea —el error
  /// al entrar, el aviso de «revisa tu correo»—, donde el icono es lo que
  /// hace que se mire antes de seguir.
  final IconData? icono;

  const Nota({super.key, required this.texto, this.icono})
    : _tono = _Tono.aviso;

  /// Algo salió mal y hay que reintentar.
  ///
  /// **Antes se pintaba con el granate de marca**, que era también el acento:
  /// un error y la función estrella de la app se veían igual. Ahora usa el rol
  /// `error` del tema, que Material 3 deriva aparte de la semilla.
  const Nota.error({super.key, required this.texto, this.icono})
    : _tono = _Tono.error;

  /// Algo salió bien pero todavía falta un paso fuera de la app.
  const Nota.exito({super.key, required this.texto, this.icono})
    : _tono = _Tono.exito;

  @override
  Widget build(BuildContext context) {
    final (color, fondo) = switch (_tono) {
      _Tono.aviso => (
        context.colores.enAvisoContenedor,
        context.colores.avisoContenedor,
      ),
      _Tono.error => (
        context.esquema.onErrorContainer,
        context.esquema.errorContainer,
      ),
      _Tono.exito => (
        context.colores.enExitoContenedor,
        context.colores.exitoContenedor,
      ),
    };

    final cuerpo = Text(
      texto,
      style: context.textos.bodyMedium?.copyWith(color: color),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(radioChico),
      ),
      child: icono == null
          ? cuerpo
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icono, size: 18, color: color),
                const SizedBox(width: 10),
                Expanded(child: cuerpo),
              ],
            ),
    );
  }
}
