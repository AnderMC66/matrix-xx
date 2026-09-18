import "package:flutter/material.dart";

import "../tema.dart";

/// Lo que se pinta cuando no hay contenido que pintar: sin sesión, sin datos
/// todavía, sin red, o un error de carga.
///
/// **Por qué es un archivo aparte.** Ocho pantallas tenían su propia copia
/// privada de este widget —`_Aviso` en horario, panel, práctica, práctica
/// adaptativa, progreso, repaso y simulacro, más `_Error` en teoría— y las
/// copias ya habían derivado: el ícono medía 32 en una y 34 en las otras, el
/// interlineado del detalle era 1.5 o 1.55 según el archivo, el título de
/// práctica se quedó sin `fontSize` y salía a 14 mientras el resto salía a 15,
/// y solo dos de las ocho se molestaban en no dejar un hueco de 8 px cuando el
/// detalle venía vacío. Ninguna de esas diferencias fue una decisión; son el
/// rastro de copiar y pegar. Con veinte llamadas repartidas por la app, el
/// alumno ve este widget más que muchas pantallas completas, así que la deriva
/// se nota.
///
/// [compacto] lo mete en un recuadro con borde en vez de centrarlo en la
/// pantalla: es para incrustarlo dentro de una lista que ya tiene contenido
/// alrededor —el horario sin bloques, debajo de su cabecera— y no para ocupar
/// el cuerpo entero.
///
/// [esError] pinta el ícono con el color de error del tema. **Antes lo pintaba
/// con el de marca**, que era el mismo: el granate hacía de acento y de error a
/// la vez. Material 3 los deriva por separado, así que ahora un fallo se ve
/// como un fallo y no como la marca.
///
/// Se reserva para el error que dice que algo está mal en la app misma —el
/// catálogo local que no carga, ver [Aviso.contenidoLocal]— y no para el estado
/// vacío ni para la red caída, que son situaciones normales y llevan el gris de
/// texto secundario.
class Aviso extends StatelessWidget {
  final IconData icono;
  final String titulo;

  /// Puede venir vacío: entonces no se reserva ni el hueco ni la línea.
  final String detalle;

  /// Etiqueta y acción de un botón bajo el texto, casi siempre "Reintentar".
  final (String, VoidCallback)? accion;

  final bool compacto;
  final bool esError;

  const Aviso({
    super.key,
    required this.icono,
    required this.titulo,
    this.detalle = "",
    this.accion,
    this.compacto = false,
    this.esError = false,
  });

  /// El catálogo del APK (temario, teoría, preguntas) no se pudo leer.
  ///
  /// Es el único fallo de esta app que tiene una causa concreta y una
  /// solución concreta, así que las cuatro pantallas que cargan assets
  /// —teoría, práctica, curso y temario— dicen exactamente lo mismo en vez
  /// de cada una lo suyo: el catálogo se sincroniza desde el repo web y sin
  /// ese paso no hay contenido que mostrar.
  factory Aviso.contenidoLocal({
    required String titulo,
    required Object error,
  }) => Aviso(
    icono: Icons.error_outline,
    titulo: titulo,
    detalle: "$error\n\n¿Corriste `node tool/sincronizar-datos.mjs`?",
    esError: true,
  );

  @override
  Widget build(BuildContext context) {
    final contenido = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icono,
          size: compacto ? 26 : 34,
          color: esError
              ? context.esquema.error
              : context.esquema.onSurfaceVariant,
        ),
        SizedBox(height: compacto ? 10 : 14),
        Text(
          titulo,
          textAlign: TextAlign.center,
          style: context.textos.titleMedium,
        ),
        if (detalle.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            detalle,
            textAlign: TextAlign.center,
            style: context.textos.bodyMedium,
          ),
        ],
        if (accion case final a?) ...[
          const SizedBox(height: 20),
          OutlinedButton(onPressed: a.$2, child: Text(a.$1)),
        ],
      ],
    );

    if (compacto) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(color: context.esquema.outlineVariant),
          borderRadius: BorderRadius.circular(radioTarjeta),
        ),
        child: contenido,
      );
    }

    // `SingleChildScrollView` y no un `Center` a secas: con el tipo de letra
    // del sistema al máximo, un detalle de tres líneas más el botón pasan de
    // lo que mide una pantalla corta y el `Column` desbordaría.
    return Center(
      child: SingleChildScrollView(
        child: Padding(padding: const EdgeInsets.all(28), child: contenido),
      ),
    );
  }
}
