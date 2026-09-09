/**
 * Encuentra las figuras de teoría que decodifican a un rectángulo de un solo
 * color —en la práctica, siempre negro puro— y escribe su lista en
 * `assets/figuras_rotas.json`.
 *
 * No es un problema de red ni de esta app: verificado bajando las 3 590
 * figuras contra el sitio real, las 3 590 responden HTTP 200 con
 * `image/webp` válido. Y no es una regresión del paso de optimización a
 * WebP tampoco: el PNG original en
 * `base de datos matrix/markdown/assets/<hash>.png`, antes de cualquier
 * conversión, YA es negro para estas 149. El defecto viene de la extracción
 * del PDF, en el mismo lote que ESTADO.md ya documenta para las fórmulas
 * rotas — solo que aquí era invisible: mientras las figuras dieron 404 (ver
 * LEEME.md, «Las figuras»), nunca llegó a mostrarse ninguna, negra o no.
 *
 * `FiguraRed` (`lib/pantallas/figura_red.dart`) consulta esta lista antes de
 * pedir la imagen por red: sin ella, el alumno vería un rectángulo negro
 * sólido en mitad de la teoría —peor que el aviso "no disponible" que
 * muestra hoy, porque no da ninguna pista de qué falta—.
 *
 * Requiere `sharp` para decodificar WebP y medir la varianza de píxel. No es
 * dependencia del proyecto —Flutter no usa npm— así que se instala aparte,
 * solo para correr esto:
 *
 *   npm install --no-save sharp
 *   node tool/detectar-figuras-rotas.mjs
 *
 * Vuelve a correrlo si el repo web trae figuras nuevas (`teoria:sincronizar`
 * las agrega a `public/teoria-figuras/`): una figura nueva no entra
 * automáticamente en la lista.
 */
import { readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { exigirRepo } from "./repo.mjs";

let sharp;
try {
  ({ default: sharp } = await import("sharp"));
} catch {
  console.error(
    "Falta `sharp`. Instálalo aparte, solo para esta herramienta:\n\n" +
      "  npm install --no-save sharp\n",
  );
  process.exit(1);
}

const repo = exigirRepo();
const dirFiguras = join(repo, "public", "teoria-figuras");
const salida = join(import.meta.dirname, "..", "assets", "figuras_rotas.json");

// Por debajo de esto, ningún trazo ni letra sobrevivió: es un rectángulo de
// un solo color, no un diagrama. Los 149 casos medidos dieron 0.00 exacto
// (negro puro); el margen deja pasar una compresión WebP con ruido mínimo
// sin dejar de atrapar el caso real.
const UMBRAL_STDEV = 3;

const archivos = readdirSync(dirFiguras);
const rotas = [];

for (const [i, archivo] of archivos.entries()) {
  try {
    const { channels } = await sharp(join(dirFiguras, archivo)).stats();
    const maxStdev = Math.max(...channels.map((c) => c.stdev));
    if (maxStdev < UMBRAL_STDEV) rotas.push(archivo);
  } catch (e) {
    console.error(`  no se pudo decodificar ${archivo}: ${e.message}`);
  }
  if ((i + 1) % 500 === 0) {
    console.error(`  ${i + 1}/${archivos.length}`);
  }
}

rotas.sort();
writeFileSync(salida, `${JSON.stringify(rotas, null, 1)}\n`);

console.log(
  `\n${rotas.length} de ${archivos.length} figuras (${((rotas.length * 100) / archivos.length).toFixed(1)} %) ` +
    `son un solo color.\n→ assets/figuras_rotas.json`,
);
