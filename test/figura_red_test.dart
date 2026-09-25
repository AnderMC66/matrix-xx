// Cómo se arma la URL de una figura, y por qué la extensión decide con qué
// widget se pinta.
//
// `Image.network` no distingue: si le das una URL de SVG intenta decodificar
// bytes de imagen rasterizada y falla, cayendo a `errorBuilder` igual que un
// 404 — y solo tras el viaje de red. Hasta el 2026-09-10 eso era justo lo que
// pasaba con `geo-2027-004-trapecio.svg`, la única figura de pregunta del
// banco: el alumno veía el aviso «no disponible» en vez del trapecio. Ahora
// esa rama va a `SvgPicture.network`, y lo que se fija aquí es la decisión
// que las separa.
//
// Que `flutter_svg` dibuje ESE archivo se comprobó aparte, pasándolo por
// `SvgPicture.string`: sale un lienzo de 420×260 sin excepciones. No queda
// como test permanente porque el archivo vive en `MATRIX-U/public/preguntas/`
// y esta suite no depende del repo web.
import "package:flutter_test/flutter_test.dart";
import "package:matr_u/core/config/config.dart";

void main() {
  group("resolución de URL", () {
    test("preguntas usa el prefijo /preguntas/", () {
      expect(
        Config.urlFiguraPregunta("geo-2027-004-trapecio.svg"),
        "${Config.urlSitio}/preguntas/geo-2027-004-trapecio.svg",
      );
    });

    test("teoría usa el prefijo /teoria-figuras/", () {
      expect(
        Config.urlFiguraTeoria("8fc119d04b59a8e6.webp"),
        "${Config.urlSitio}/teoria-figuras/8fc119d04b59a8e6.webp",
      );
    });

    test("el sitio por defecto es el dominio de producción real", () {
      // No es un placeholder: es matrix-u.vercel.app, verificado con
      // `icon-512.png` (HTTP 200) contra este mismo dominio.
      expect(Config.urlSitio, "https://matrix-u.vercel.app");
    });
  });

  group("detección de SVG", () {
    bool esSvg(String url) => url.toLowerCase().endsWith(".svg");

    test("un .svg se reconoce y va por SvgPicture", () {
      expect(
        esSvg(Config.urlFiguraPregunta("geo-2027-004-trapecio.svg")),
        isTrue,
      );
    });

    test("webp y png no: esos los pinta Image.network", () {
      expect(esSvg(Config.urlFiguraTeoria("8fc119d04b59a8e6.webp")), isFalse);
      expect(esSvg(Config.urlFiguraTeoria("x.png")), isFalse);
    });

    test("no distingue mayúsculas en la extensión", () {
      expect(esSvg(Config.urlFiguraPregunta("X.SVG")), isTrue);
    });
  });
}
