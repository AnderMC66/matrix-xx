import "package:flutter/material.dart";

import "../tema.dart";

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
/// El tamaño quedó en 13, que es el que usaban dos de las cuatro y el que se
/// lee mejor a un párrafo de distancia del texto principal.
class Nota extends StatelessWidget {
  final String texto;
  final Color color;
  final Color fondo;

  /// Opcional. Solo lo llevan las notas que interrumpen una tarea —el error
  /// al entrar, el aviso de «revisa tu correo»—, donde el icono es lo que
  /// hace que se mire antes de seguir.
  final IconData? icono;

  const Nota({
    super.key,
    required this.texto,
    this.color = Paleta.aviso,
    this.fondo = Paleta.avisoSuave,
    this.icono,
  });

  /// Algo salió mal y hay que reintentar.
  const Nota.error({super.key, required this.texto, this.icono})
    : color = Paleta.acento,
      fondo = Paleta.acentoSuave;

  /// Algo salió bien pero todavía falta un paso fuera de la app.
  const Nota.exito({super.key, required this.texto, this.icono})
    : color = Paleta.exito,
      fondo = Paleta.exitoSuave;

  @override
  Widget build(BuildContext context) {
    final cuerpo = Text(
      texto,
      style: TextStyle(fontSize: 13, height: 1.45, color: color),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(10),
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
