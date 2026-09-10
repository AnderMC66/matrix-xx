import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";

import "../datos/figuras_rotas.dart";
import "../tema.dart";

/// Carga una figura desde el mismo sitio que sirve `matr_u`
/// (`Config.urlSitio` — ver el porqué ahí: es el CDN estático de la web, no
/// Supabase Storage).
///
/// Un `.svg` se pinta con `flutter_svg`, no con `Image.network`: el decoder
/// de Flutter solo entiende imágenes rasterizadas, así que le daría bytes que
/// no sabe leer y caería al aviso tras el viaje de red. Hoy es una sola figura
/// del banco —el trapecio de `GEO-06-01`—, y hasta el 2026-09-10 esa pregunta
/// se mostraba sin su figura. Se sumó la librería igualmente porque la
/// herramienta de autoría del repo web emite SVG: cada figura nueva que se
/// dibuje ahí llega en ese formato, así que el caso crece, no se queda en uno.
///
/// Fuera de eso nunca deja un hueco roto ni el ícono de error del sistema.
/// Tres casos caen al mismo aviso «no disponible»:
///
///  - el archivo está en `RepositorioFigurasRotas` — decodifica bien pero es
///    un rectángulo de un solo color, casi siempre negro puro. No es un
///    problema de red: viene roto desde la extracción del PDF de origen, y
///    mostrarlo sería peor que el aviso, porque un rectángulo negro no dice
///    nada de lo que falta;
///  - no hay red, o la app corre sin conexión;
///  - el servidor responde algo que no es 200 (una figura nueva que el
///    despliegue de producción todavía no tiene).
///
/// [grande] elige la presentación: recuadro con borde y proporción reservada
/// para las figuras de una pregunta —pocas, y cada una puede decidir si el
/// ejercicio se resuelve—, o línea compacta para las de teoría, que aparecen
/// miles de veces y donde un recuadro por cada una convertiría la lectura en
/// un campo de avisos.
class FiguraRed extends StatelessWidget {
  final String url;
  final String alt;
  final double proporcion;
  final bool grande;

  const FiguraRed({
    super.key,
    required this.url,
    required this.alt,
    this.proporcion = 4 / 3,
    this.grande = false,
  });

  bool get _esSvg => url.toLowerCase().endsWith(".svg");

  /// El último segmento de la URL: `.../teoria-figuras/<archivo>` →
  /// `<archivo>`, que es como `RepositorioFigurasRotas` los identifica.
  String get _nombreArchivo => Uri.parse(url).pathSegments.last;

  bool get _esRota => RepositorioFigurasRotas.instancia.esta(_nombreArchivo);

  /// El `alt` que vale la pena anunciar. La teoría trae casi siempre el
  /// literal "figura", que no describe nada: leerlo en voz alta es ruido, y
  /// Flutter ya anuncia que hay una imagen. Las de preguntas sí describen.
  String? get _etiqueta {
    final limpio = alt.trim();
    if (limpio.isEmpty || limpio.toLowerCase() == "figura") return null;
    return limpio;
  }

  @override
  Widget build(BuildContext context) {
    if (_esRota) {
      return _Ausente(
        alt: alt,
        proporcion: proporcion,
        grande: grande,
        sinContenido: true,
      );
    }

    return grande ? _grande(context) : _compacta(context);
  }

  /// Preguntas: el hueco se reserva desde el primer instante con la
  /// proporción real —para que el enunciado no salte al resolver la carga—,
  /// e igual de grande si la imagen no llega.
  Widget _grande(BuildContext context) {
    final ausente = _Ausente(alt: alt, proporcion: proporcion, grande: true);

    return AspectRatio(
      aspectRatio: proporcion,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: _esSvg
            ? SvgPicture.network(
                url,
                fit: BoxFit.contain,
                semanticsLabel: _etiqueta,
                placeholderBuilder: (_) => _girando(),
                errorBuilder: (context, error, stack) => ausente,
              )
            : Image.network(
                url,
                fit: BoxFit.contain,
                // El `alt` del banco no es decorativo: describe la figura
                // entera («Trapecio ABCD con la base menor AB de 6 cm
                // arriba…»), que en una pregunta de geometría es la mitad del
                // enunciado. Sin esto, un lector de pantalla anuncia la imagen
                // y no dice nada de ella — y solo cuando la figura FALLA
                // aparecía el texto, que es justo al revés de lo que hace
                // falta.
                semanticLabel: _etiqueta,
                loadingBuilder: (context, child, progreso) =>
                    progreso == null ? child : _girando(),
                errorBuilder: (context, error, stack) => ausente,
              ),
      ),
    );
  }

  Widget _girando() => Container(
    color: Paleta.superficie,
    alignment: Alignment.center,
    child: const SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );

  /// Teoría: mientras se resuelve, sigue mostrando la misma línea compacta
  /// —solo cambia el texto a «cargando»—, no un bloque de tamaño reservado.
  /// Con 3 827 apariciones, un placeholder grande por figura convertiría el
  /// primer segundo de cada sección en una pared de recuadros vacíos.
  Widget _compacta(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 320),
    child: _esSvg
        // Hoy ninguna figura de teoría es SVG (3 498 `.webp` y 92 `.png`),
        // pero el widget lo sirve igual: si mañana entra una, se pinta en vez
        // de caer al aviso por una rama que nadie recordaba actualizar.
        ? SvgPicture.network(
            url,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            semanticsLabel: _etiqueta,
            placeholderBuilder: (_) => _Ausente(alt: alt, cargando: true),
            errorBuilder: (context, error, stack) => _Ausente(alt: alt),
          )
        : Image.network(
            url,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            semanticLabel: _etiqueta,
            loadingBuilder: (context, child, progreso) =>
                progreso == null ? child : _Ausente(alt: alt, cargando: true),
            errorBuilder: (context, error, stack) => _Ausente(alt: alt),
          ),
  );
}

class _Ausente extends StatelessWidget {
  final String alt;
  final double proporcion;
  final bool grande;
  final bool cargando;

  /// El archivo existe y decodifica bien, pero es un rectángulo de un solo
  /// color: distinto de "todavía no está" —esta nunca va a aparecer, sea
  /// cuando sea— y merece decirlo distinto para no prometer algo que no va a
  /// pasar.
  final bool sinContenido;

  const _Ausente({
    required this.alt,
    this.proporcion = 4 / 3,
    this.grande = false,
    this.cargando = false,
    this.sinContenido = false,
  });

  @override
  Widget build(BuildContext context) {
    final descriptivo = alt.trim().toLowerCase() != "figura";
    final texto = cargando
        ? "Cargando figura…"
        : sinContenido
        ? (descriptivo
              ? "$alt (sin contenido en el original)"
              : "Figura sin contenido en el original")
        : descriptivo
        ? alt
        : "Figura (no disponible todavía)";

    if (!grande) {
      return Row(
        children: [
          Icon(
            cargando ? Icons.hourglass_empty : Icons.image_outlined,
            size: 15,
            color: Paleta.textoTenue,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              texto,
              style: const TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: Paleta.textoTenue,
              ),
            ),
          ),
        ],
      );
    }

    return AspectRatio(
      aspectRatio: proporcion,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Paleta.superficie,
          border: Border.all(color: Paleta.borde),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  cargando ? Icons.hourglass_empty : Icons.image_outlined,
                  size: 22,
                  color: Paleta.textoTenue,
                ),
                const SizedBox(height: 8),
                Text(
                  texto,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: Paleta.textoSuave,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
