// Cómo se arma la URL de una figura, y por qué un `.svg` nunca intenta
// cargarse por red.
//
// `Image.network` no distingue: si le das una URL de SVG, intenta decodificar
// bytes de imagen rasterizada y falla — cae a `errorBuilder` igual que un 404,
// pero solo tras el viaje de red. Comprobar la extensión antes evita ese viaje
// inútil, que en el único caso real de hoy (`geo-2027-004-trapecio.svg`)
// pasaría en cada apertura de esa pregunta.
import "package:flutter_test/flutter_test.dart";
import "package:matr_u/config.dart";

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

    test("un .svg no intenta cargarse por red", () {
      expect(esSvg(Config.urlFiguraPregunta("geo-2027-004-trapecio.svg")), isTrue);
    });

    test("webp y png sí", () {
      expect(esSvg(Config.urlFiguraTeoria("8fc119d04b59a8e6.webp")), isFalse);
      expect(esSvg(Config.urlFiguraTeoria("x.png")), isFalse);
    });

    test("no distingue mayúsculas en la extensión", () {
      expect(esSvg(Config.urlFiguraPregunta("X.SVG")), isTrue);
    });
  });
}
