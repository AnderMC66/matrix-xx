import "dart:ui" show ImageFilter;

import "package:flutter/material.dart";

import "../tema.dart";

/// Las piezas del lenguaje visual de iOS que esta app usa.
///
/// **Por qué son widgets de Material estilizados y no widgets de Cupertino.**
/// La tentación es usar `CupertinoTextField`, `CupertinoButton` y compañía,
/// pero se pierde más de lo que se gana:
///
///   - `CupertinoTextField` no participa del `AutofillGroup` de Material igual
///     que `TextField`, y el gestor de contraseñas de Android es justo lo que
///     hace soportable escribir una contraseña de 8 caracteres en un móvil.
///   - Los widgets de Cupertino no leen el `ColorScheme`, así que habría que
///     pasarles el color a mano en cada sitio — que es exactamente el problema
///     del que salió esta app.
///   - Y romperían los tests que buscan por tipo (`find.widgetWithText(
///     TextField, "Correo")`), sin ganar un píxel: una vez estilizado, un
///     `TextField` con relleno gris y sin borde ES el campo de iOS.
///
/// Lo que sí se toma de Cupertino es lo que no se puede imitar: la transición
/// de página con gesto de volver, que se activa en `tema.dart`.

// ============================================================================
// Tarjeta agrupada (inset grouped)
// ============================================================================

/// El contenedor de una lista agrupada de iOS: tarjeta blanca sobre el fondo
/// gris, con margen lateral y esquinas muy redondeadas.
///
/// Es la unidad con la que se construye toda pantalla de ajustes de iOS, y
/// funciona igual de bien para un panel de progreso: agrupa cosas que van
/// juntas sin necesidad de títulos ni líneas.
///
/// [titulo] va FUERA de la tarjeta, arriba y en gris pequeño, como los
/// encabezados de sección de iOS. No dentro: dentro competiría con el
/// contenido.
class GrupoInset extends StatelessWidget {
  final String? titulo;

  /// Las filas. Entre cada dos se pinta un separador con sangría izquierda,
  /// que es el detalle que más delata a una lista de iOS bien hecha: la línea
  /// no llega al borde, arranca donde arranca el texto.
  final List<Widget> filas;

  /// Sangría del separador. 16 por defecto; súbela si las filas llevan icono
  /// a la izquierda, para que la línea arranque después del icono.
  final double sangriaSeparador;

  final EdgeInsets margen;

  const GrupoInset({
    super.key,
    this.titulo,
    required this.filas,
    this.sangriaSeparador = 16,
    this.margen = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context) {
    final brillo = Theme.of(context).brightness;

    return Padding(
      padding: margen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (titulo case final t?) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(t.toUpperCase(), style: context.textos.labelSmall),
            ),
          ],
          DecoratedBox(
            decoration: BoxDecoration(
              color: context.esquema.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(radioTarjeta),
              boxShadow: sombraTarjeta(brillo),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radioTarjeta),
              child: Column(
                children: [
                  for (var i = 0; i < filas.length; i++) ...[
                    filas[i],
                    if (i < filas.length - 1)
                      Padding(
                        padding: EdgeInsets.only(left: sangriaSeparador),
                        child: Divider(
                          height: 1,
                          thickness: 0.5,
                          color: context.colores.separador,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Una fila dentro de un [GrupoInset]: icono opcional, texto, valor y chevron.
///
/// El chevron solo aparece si hay [onTap]: en iOS es una promesa de que algo
/// pasa al pulsar, y ponerlo en una fila muerta es mentir.
class FilaInset extends StatelessWidget {
  final IconData? icono;

  /// Color de la pastilla del icono. iOS colorea el cuadro, no el glifo.
  final Color? colorIcono;

  final String titulo;
  final String? subtitulo;

  /// El texto gris a la derecha, antes del chevron.
  final String? valor;

  final Widget? alFinal;
  final VoidCallback? onTap;

  const FilaInset({
    super.key,
    this.icono,
    this.colorIcono,
    required this.titulo,
    this.subtitulo,
    this.valor,
    this.alFinal,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final contenido = Padding(
      // 11 de alto deja la fila en 44 con una sola línea, que es el mínimo
      // táctil de Apple.
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          if (icono case final ic?) ...[
            _PastillaIcono(
              icono: ic,
              color: colorIcono ?? context.esquema.primary,
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: context.textos.bodyLarge),
                if (subtitulo case final s?)
                  Text(s, style: context.textos.bodySmall),
              ],
            ),
          ),
          if (valor case final v?) ...[
            const SizedBox(width: 8),
            Text(
              v,
              style: context.textos.bodyLarge?.copyWith(
                color: context.esquema.onSurfaceVariant,
              ),
            ),
          ],
          if (alFinal case final w?) ...[const SizedBox(width: 8), w],
          ?(onTap == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: context.colores.grisSutil,
                  ),
                )),
        ],
      ),
    );

    if (onTap == null) return contenido;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: contenido),
    );
  }
}

/// El cuadro de color con el glifo dentro, como los iconos de Ajustes.
class _PastillaIcono extends StatelessWidget {
  final IconData icono;
  final Color color;
  const _PastillaIcono({required this.icono, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 30,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(8),
    ),
    // **El glifo se elige por la luminancia de la pastilla, no fijo a blanco.**
    //
    // En claro las pastillas son colores saturados y el blanco va bien; en
    // oscuro los mismos tokens son pasteles —el error es #FFB4AB, el exito
    // #6FDBA8— y un glifo blanco encima se pierde. Se vio en la captura del
    // modo oscuro: los iconos de Repaso y Simulacros casi no se leian.
    child: Icon(
      icono,
      size: 18,
      color: color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
    ),
  );
}

// ============================================================================
// Campo de texto
// ============================================================================

/// El campo de iOS: relleno gris, sin borde, esquinas de 12.
///
/// Sigue siendo un `TextField` de Material por lo que explica la cabecera de
/// este archivo — autocompletado, tests y `ColorScheme`.
class CampoIOS extends StatefulWidget {
  final TextEditingController controlador;
  final String etiqueta;
  final IconData? icono;
  final bool oculto;
  final bool capitalizar;
  final TextInputType? teclado;
  final VoidCallback? alEnviar;
  final List<String>? autocompletar;

  /// Mensaje de error bajo el campo. En iOS el error no repinta el campo de
  /// rojo entero: pone una línea de texto debajo y tiñe solo el borde.
  final String? error;

  const CampoIOS({
    super.key,
    required this.controlador,
    required this.etiqueta,
    this.icono,
    this.oculto = false,
    this.capitalizar = false,
    this.teclado,
    this.alEnviar,
    this.autocompletar,
    this.error,
  });

  @override
  State<CampoIOS> createState() => _CampoIOSState();
}

class _CampoIOSState extends State<CampoIOS> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) => TextField(
    controller: widget.controlador,
    obscureText: widget.oculto && !_visible,
    keyboardType: widget.teclado,
    autocorrect: false,
    autofillHints: widget.autocompletar,
    style: context.textos.bodyLarge,
    textCapitalization: widget.capitalizar
        ? TextCapitalization.words
        : TextCapitalization.none,
    textInputAction: widget.alEnviar != null
        ? TextInputAction.done
        : TextInputAction.next,
    onSubmitted: widget.alEnviar == null ? null : (_) => widget.alEnviar!(),
    decoration: InputDecoration(
      // **Sin relleno propio: lo pone el grupo.**
      //
      // En un formulario agrupado de iOS la fila ES la tarjeta blanca, y lo
      // que separa un campo del siguiente es la linea con sangria, no un
      // rectangulo gris por campo. Con `filled: true` los campos se leian
      // como dos pastillas sueltas dentro de la tarjeta, cada una con sus
      // esquinas: dos bordes redondeados donde deberia haber uno.
      //
      // El gris #E5E5EA de `surfaceContainer` sigue siendo el relleno correcto
      // para un campo SUELTO —una busqueda—, y por eso vive en el tema.
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(vertical: 14),
      // `hintText` y no `labelText`: la etiqueta flotante es de Material. En
      // iOS el campo lleva un marcador de posición que desaparece al escribir,
      // y el contexto lo da el grupo, no una etiqueta que se encoge.
      hintText: widget.etiqueta,
      hintStyle: context.textos.bodyLarge?.copyWith(
        color: context.colores.grisSutil,
      ),
      errorText: widget.error,
      prefixIcon: widget.icono == null
          ? null
          : Icon(widget.icono, size: 20, color: context.colores.grisSutil),
      prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      suffixIcon: !widget.oculto
          ? null
          : IconButton(
              // El tooltip es también lo que lee el lector de pantalla: un ojo
              // sin nombre se anuncia como «botón».
              tooltip: _visible ? "Ocultar la contraseña" : "Ver la contraseña",
              icon: Icon(
                _visible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
                color: context.colores.grisSutil,
              ),
              onPressed: () => setState(() => _visible = !_visible),
            ),
    ),
  );
}

// ============================================================================
// Botones
// ============================================================================

/// La acción principal: ancho completo, alto 50, esquinas de 14.
///
/// En iOS la acción principal ocupa el ancho de la pantalla y se coloca donde
/// llega el pulgar. Un botón de 50 dp es más alto que el de Material a
/// propósito.
class BotonPrincipal extends StatelessWidget {
  final String texto;
  final VoidCallback? onPressed;
  final bool cargando;

  const BotonPrincipal({
    super.key,
    required this.texto,
    required this.onPressed,
    this.cargando = false,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: cargando ? null : onPressed,
      child: cargando
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: context.esquema.onPrimary,
              ),
            )
          : Text(texto),
    ),
  );
}

/// La acción secundaria: relleno translúcido del color de acento, sin borde.
///
/// Es el botón «tinted» de iOS. No lleva borde porque en iOS el relleno ya
/// dice que es pulsable, y un contorno más un relleno compiten.
class BotonSecundario extends StatelessWidget {
  final String texto;
  final IconData? icono;
  final VoidCallback? onPressed;

  const BotonSecundario({
    super.key,
    required this.texto,
    this.icono,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton.tonal(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: context.esquema.primary.withValues(alpha: 0.12),
        foregroundColor: context.esquema.primary,
        elevation: 0,
      ),
      child: icono == null
          ? Text(texto)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icono, size: 18),
                const SizedBox(width: 8),
                Text(texto),
              ],
            ),
    ),
  );
}

// ============================================================================
// Vidrio esmerilado
// ============================================================================

/// Una barra con el fondo desenfocado, como las de iOS.
///
/// **El desenfoque no es decoración: es información.** Dice que hay contenido
/// pasando por debajo. Por eso la barra inferior solo se difumina si la lista
/// puede desplazarse — sobre una pantalla vacía sería un efecto sin causa.
///
/// `ImageFilter.blur` obliga a rasterizar la capa de debajo en cada frame, así
/// que se usa en dos sitios contados (barra inferior y cabecera) y nunca
/// dentro de una lista que se desplaza.
class BarraDifuminada extends StatelessWidget {
  final Widget hijo;

  /// Cuánto desenfoque. 18 es lo que usa iOS en las barras; por debajo de 10
  /// se lee como suciedad en vez de como cristal.
  final double desenfoque;

  /// Si va arriba, el separador se pinta abajo; si va abajo, arriba.
  final bool esCabecera;

  const BarraDifuminada({
    super.key,
    required this.hijo,
    this.desenfoque = 18,
    this.esCabecera = false,
  });

  @override
  Widget build(BuildContext context) {
    final linea = BorderSide(color: context.colores.separador, width: 0.5);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: desenfoque, sigmaY: desenfoque),
        child: DecoratedBox(
          decoration: BoxDecoration(
            // Translúcido, no transparente: sin algo de color el texto de
            // debajo se leería a través del desenfoque.
            color: context.esquema.surface.withValues(alpha: 0.82),
            border: Border(
              top: esCabecera ? BorderSide.none : linea,
              bottom: esCabecera ? linea : BorderSide.none,
            ),
          ),
          child: hijo,
        ),
      ),
    );
  }
}

/// La cabecera con *Large Title* de iOS.
///
/// El título grande vive en el cuerpo de la lista, no en la barra: así se
/// desplaza con el contenido y desaparece al bajar, que es el comportamiento
/// que lo hace reconocible. Quien quiera además una barra pequeña al hacer
/// scroll puede envolver en un `SliverAppBar`; para las dos pantallas de esta
/// app la versión simple basta y ahorra un `CustomScrollView`.
class TituloGrande extends StatelessWidget {
  final String texto;
  final String? subtitulo;
  final Widget? alFinal;

  const TituloGrande({
    super.key,
    required this.texto,
    this.subtitulo,
    this.alFinal,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(texto, style: context.textos.displayLarge),
              if (subtitulo case final s?) ...[
                const SizedBox(height: 4),
                Text(s, style: context.textos.bodyMedium),
              ],
            ],
          ),
        ),
        ?alFinal,
      ],
    ),
  );
}

/// El círculo con iniciales que sustituye a la foto de perfil.
///
/// **`perfiles` no tiene columna de avatar**, así que una foto sería un hueco
/// que nunca se llena. Las iniciales ocupan el mismo sitio, tienen el mismo
/// peso visual y salen de un dato que sí existe.
class AvatarIniciales extends StatelessWidget {
  final String? nombre;
  final double tamano;

  const AvatarIniciales({super.key, required this.nombre, this.tamano = 40});

  String get _iniciales {
    final partes = (nombre ?? "").trim().split(RegExp(r"\s+"))
      ..removeWhere((p) => p.isEmpty);
    if (partes.isEmpty) return "?";
    if (partes.length == 1) return partes.first.characters.first.toUpperCase();
    return (partes.first.characters.first + partes[1].characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) => Container(
    width: tamano,
    height: tamano,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: context.esquema.primary.withValues(alpha: 0.12),
      shape: BoxShape.circle,
      // El borde fino que pedía el diseño: sin él, sobre el gris del fondo el
      // círculo se difumina.
      border: Border.all(color: context.esquema.primary.withValues(alpha: 0.3)),
    ),
    child: Text(
      _iniciales,
      style: context.textos.labelLarge?.copyWith(
        color: context.esquema.primary,
        fontSize: tamano * 0.38,
      ),
    ),
  );
}
