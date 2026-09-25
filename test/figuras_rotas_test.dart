// Las figuras que decodifican a un solo color, medidas contra el corpus
// real con `tool/detectar-figuras-rotas.mjs`.
//
// La cifra exacta (149 de 3 590, 4,2 %) importa porque es la evidencia de que
// esto no es un problema de red ni de esta app: las 3 590 responden HTTP 200
// contra el sitio real, y el PNG original —antes de cualquier optimización a
// WebP— ya era negro para estas 149. Si esta cifra cambia mucho de golpe, es
// señal de que el banco de contenido cambió y hay que volver a correr la
// herramienta, no de que algo se rompió aquí.
import "package:flutter_test/flutter_test.dart";
import "package:matr_u/data/models/figuras_rotas.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("RepositorioFigurasRotas", () {
    test("carga el asset real con la cifra medida", () async {
      final repo = RepositorioFigurasRotas.instancia;
      await repo.cargar();

      // Una muestra verificada a mano, viendo el píxel: negro puro en las
      // tres, confirmado también en su PNG original antes de convertir a
      // WebP.
      expect(repo.esta("020d3622f04d7e76.webp"), isTrue);
      expect(repo.esta("041be758416b61d4.webp"), isTrue);
      expect(repo.esta("6092a5ba5bdb938b.webp"), isTrue);

      // Una figura con contenido real (los diagramas de vectores que se
      // vieron en el emulador) no debe estar en la lista.
      expect(repo.esta("8fc119d04b59a8e6.webp"), isFalse);
    });

    test("un nombre que no existe en absoluto no está roto", () async {
      final repo = RepositorioFigurasRotas.instancia;
      await repo.cargar();
      expect(repo.esta("no-existe-este-archivo.webp"), isFalse);
    });

    test("cargar() es idempotente: llamarlo dos veces no falla", () async {
      final repo = RepositorioFigurasRotas.instancia;
      await repo.cargar();
      await repo.cargar();
      expect(repo.esta("020d3622f04d7e76.webp"), isTrue);
    });

    test("sin cargar todavía, esta() devuelve false y no lanza", () {
      // Fail-safe deliberado: si algo pide una figura antes de que termine
      // la carga (no debería pasar, `Arranque` la espera), el peor caso es
      // intentar la red de una figura rota — nunca una excepción. Se usa una
      // instancia nueva, no el singleton, porque ese ya está cargado por los
      // tests de arriba.
      final repo = RepositorioFigurasRotas();
      expect(repo.esta("020d3622f04d7e76.webp"), isFalse);
    });
  });
}
