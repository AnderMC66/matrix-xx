/**
 * Copia el catálogo del repo web a `assets/datos/`.
 *
 * En la web, `src/lib/{temario,teoria,preguntas}.ts` leen `data/**\/*.json` con
 * `readFileSync` porque hay un servidor Node detrás. En una app compilada no
 * existe `process.cwd()`, así que el mismo JSON tiene que viajar dentro del
 * binario como asset. Esto lo copia.
 *
 * Lo que NO se copia, y por qué:
 *   - `data/candidatos/` y `candidatos-teoria/` — material sin clave, solo lo
 *     usa la herramienta de autoría en desarrollo. 6,5 MB que no pintan nada
 *     en un móvil.
 *   - `public/teoria-figuras/` — 3 590 archivos, 83 MB. Van a Supabase Storage.
 *
 * Correr:  node tool/sincronizar-datos.mjs
 */
import { readdirSync, readFileSync, writeFileSync, mkdirSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { exigirRepo } from "./repo.mjs";

const aqui = dirname(fileURLToPath(import.meta.url));
const repo = exigirRepo();
const destinoRaiz = join(aqui, "..", "assets", "datos");

const CARPETAS = ["temario", "teoria", "preguntas"];

let totalArchivos = 0;
let totalBytes = 0;

for (const carpeta of CARPETAS) {
  const origen = join(repo, "data", carpeta);
  const destino = join(destinoRaiz, carpeta);

  // Se borra primero para que un archivo eliminado en el repo desaparezca
  // aquí también, en vez de quedarse como fantasma dentro del APK.
  rmSync(destino, { recursive: true, force: true });
  mkdirSync(destino, { recursive: true });

  const archivos = readdirSync(origen).filter((f) => f.endsWith(".json"));
  const indice = [];

  for (const archivo of archivos) {
    const contenido = readFileSync(join(origen, archivo));
    writeFileSync(join(destino, archivo), contenido);
    indice.push(archivo);
    totalArchivos++;
    totalBytes += contenido.length;
  }

  // Flutter no sabe listar un directorio de assets en tiempo de ejecución
  // (`AssetManifest` sí, pero obliga a filtrar por prefijo y a acarrear el
  // manifiesto entero). Un índice explícito es más barato y más claro.
  indice.sort();
  writeFileSync(
    join(destino, "_indice.json"),
    JSON.stringify(indice, null, 2) + "\n",
    "utf8",
  );

  console.log(`  ${carpeta.padEnd(10)} ${archivos.length} archivos`);
}

console.log(
  `\n${totalArchivos} archivos · ${(totalBytes / 1024 / 1024).toFixed(1)} MB ` +
    `→ assets/datos/\n\nRecuerda: las figuras de teoría no están aquí.`,
);
