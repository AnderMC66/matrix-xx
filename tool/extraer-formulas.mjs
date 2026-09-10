/**
 * Extrae todas las fórmulas LaTeX del banco a `assets/formulas_banco.json`.
 *
 * Existe para una sola pregunta, la que decide la migración a Flutter: KaTeX
 * dibuja este banco en la web (con 1 854 fórmulas ya identificadas como rotas,
 * ESTADO.md § 8), y `flutter_math_fork` cubre menos LaTeX que KaTeX. ¿Cuánto
 * menos, sobre ESTAS fórmulas y no sobre un ejemplo de juguete?
 *
 * El resultado lo consume `test/medir_formulas_test.dart`, que lo mide sin
 * abrir la app. Y solo él: el archivo NO se declara en `pubspec.yaml`, así que
 * no viaja en el APK — el test lo lee del disco con `File(...)`.
 *
 * Correr:  node tool/extraer-formulas.mjs
 */
import { readdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { exigirRepo } from "./repo.mjs";

const aqui = dirname(fileURLToPath(import.meta.url));
const raiz = exigirRepo();
const salida = join(aqui, "..", "assets", "formulas_banco.json");

// Mismo patrón que src/lib/matematicas.ts.
const PATRON = /\$\$([\s\S]+?)\$\$|\$([^\n$]+?)\$/g;

/** Recorre cualquier JSON y devuelve todas sus cadenas. */
function* cadenas(valor) {
  if (typeof valor === "string") yield valor;
  else if (Array.isArray(valor)) for (const v of valor) yield* cadenas(v);
  else if (valor && typeof valor === "object")
    for (const v of Object.values(valor)) yield* cadenas(v);
}

const vistas = new Map(); // tex -> { tex, enBloque, origen }

function cosechar(texto, origen) {
  for (const m of texto.matchAll(PATRON)) {
    if (texto[m.index - 1] === "\\") continue;
    const enBloque = m[1] !== undefined;
    const tex = (m[1] ?? m[2]).trim();
    if (!tex || vistas.has(tex)) continue;
    vistas.set(tex, { tex, enBloque, origen });
  }
}

function recorrerCarpeta(sub) {
  const dir = join(raiz, "data", sub);
  if (!existsSync(dir)) return 0;
  let archivos = 0;
  for (const archivo of readdirSync(dir).filter((f) => f.endsWith(".json"))) {
    archivos++;
    const json = JSON.parse(readFileSync(join(dir, archivo), "utf8"));
    for (const s of cadenas(json)) cosechar(s, `${sub}/${archivo}`);
  }
  return archivos;
}

const nPreguntas = recorrerCarpeta("preguntas");
const nTeoria = recorrerCarpeta("teoria");

const formulas = [...vistas.values()];
writeFileSync(salida, JSON.stringify(formulas, null, 2) + "\n", "utf8");

const enBloque = formulas.filter((f) => f.enBloque).length;
console.log(
  `${formulas.length} fórmulas únicas ` +
    `(${enBloque} en bloque, ${formulas.length - enBloque} en línea)\n` +
    `  de ${nPreguntas} archivos de preguntas y ${nTeoria} de teoría\n` +
    `→ assets/formulas_banco.json`,
);
