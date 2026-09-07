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
 *   - `clave` y `explicacion` de cada pregunta — ver `despublicar()`.
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
let clavesQuitadas = 0;

/**
 * Quita `clave` y `explicacion` de cada pregunta antes de escribirla.
 *
 * La REGLA CENTRAL de `src/lib/preguntas.ts` es que el tipo que cruza hacia el
 * cliente no lleva clave: en la web el banco completo se queda en el servidor
 * y en Postgres la columna `clave` está revocada para `authenticated`, de modo
 * que la única forma de conocer la respuesta es responder y que el RPC
 * `responder_pregunta` te la diga.
 *
 * Aquí no hay servidor donde esconderla. Un asset de Flutter es un archivo
 * dentro del APK, y un APK es un ZIP: copiar estos JSON tal cual publicaba las
 * claves de todo el banco a cualquiera con `unzip`. No es teórico —así estaba
 * hasta ahora, con 395 claves en `assets/datos/preguntas/`.
 *
 * Consecuencia de diseño, no accidente: la app **no puede corregir sola**. Sin
 * la clave, la corrección pasa siempre por el RPC, igual que en la web con
 * sesión iniciada. Eso quita la práctica anónima que la web sí ofrece —allí la
 * resuelve `corregir()` en el servidor— y es el precio de no repartir el banco
 * resuelto. Ver `lib/datos/preguntas.dart`.
 */
function despublicar(json) {
  if (!Array.isArray(json?.preguntas)) return json;

  for (const pregunta of json.preguntas) {
    if ("clave" in pregunta) clavesQuitadas++;
    delete pregunta.clave;
    delete pregunta.explicacion;
  }

  return json;
}

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
    // El temario y la teoría se copian byte a byte; las preguntas pasan por el
    // filtro. Se reserializa solo en ese caso para no reformatear archivos que
    // no hace falta tocar.
    const contenido =
      carpeta === "preguntas"
        ? Buffer.from(
            JSON.stringify(
              despublicar(JSON.parse(readFileSync(join(origen, archivo), "utf8"))),
              null,
              2,
            ) + "\n",
            "utf8",
          )
        : readFileSync(join(origen, archivo));

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
    `→ assets/datos/\n` +
    `${clavesQuitadas} claves y explicaciones retiradas del banco ` +
    `(las resuelve el RPC, no el APK).\n\n` +
    `Recuerda: las figuras de teoría no están aquí.`,
);
