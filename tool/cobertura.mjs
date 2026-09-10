/**
 * Cuánto del sílabo tiene con qué practicarse, curso por curso.
 *
 * El porte del código está terminado —las 22 rutas de producto funcionan— y
 * eso hace fácil confundir "la app está lista" con "la app está llena". No lo
 * está: el banco cubre una quinta parte de los subtemas oficiales, y muy
 * desigual. Un alumno de Biología abre Práctica y encuentra 67 preguntas; uno
 * de Razonamiento Verbal encuentra 3. Esa diferencia no se ve en ninguna
 * pantalla ni en ningún test, porque no es un fallo: es contenido que todavía
 * no se ha escrito.
 *
 * Esta herramienta la mide, para que la conversación sobre qué falta se tenga
 * con cifras. No arregla nada: el banco vive en el repo web
 * (`data/preguntas/*.json`) y ahí es donde se escribe.
 *
 * Correr:  node tool/cobertura.mjs
 *          node tool/cobertura.mjs --subtemas ARI    (los huecos de un curso)
 */
import { readdirSync, readFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const aqui = dirname(fileURLToPath(import.meta.url));
const datos = join(aqui, "..", "assets", "datos");

if (!existsSync(datos)) {
  console.error(
    "No existe assets/datos/.\n\nCórrelo después de:  node tool/sincronizar-datos.mjs",
  );
  process.exit(1);
}

/** Los códigos de subtema del sílabo, en orden, con su nombre y su curso. */
function leerTemario() {
  const subtemas = new Map();
  const cursos = [];

  for (const archivo of readdirSync(join(datos, "temario"))) {
    if (archivo === "_indice.json") continue;
    const area = JSON.parse(readFileSync(join(datos, "temario", archivo), "utf8"));

    for (const curso of area.cursos) {
      const propios = [];
      for (const tema of curso.temas) {
        const nt = String(tema.numero).padStart(2, "0");
        // Un tema sin desglose vale por un subtema: es como lo cuenta
        // `lib/datos/temario.dart`, que le pone "General (pendiente de
        // desglose)" para que el sílabo no tenga agujeros.
        const lista = tema.subtemas?.length ? tema.subtemas : ["General (pendiente de desglose)"];
        lista.forEach((nombre, i) => {
          const codigo = `${curso.codigo}-${nt}-${String(i + 1).padStart(2, "0")}`;
          subtemas.set(codigo, { curso: curso.codigo, tema: tema.nombre, nombre });
          propios.push(codigo);
        });
      }
      cursos.push({
        codigo: curso.codigo,
        nombre: curso.nombre,
        area: area.nombre,
        subtemas: propios,
      });
    }
  }
  return { subtemas, cursos };
}

/** Cuántas preguntas hay por código de subtema. */
function leerBanco() {
  const conteo = new Map();
  let total = 0;
  const huerfanas = [];

  for (const archivo of readdirSync(join(datos, "preguntas"))) {
    // `_indice.json` es el índice; los demás `_*.json` son los ejemplos de
    // desarrollo, que la app solo carga si no hay ningún archivo real. Misma
    // regla que `RepositorioPreguntas.cargar()`.
    if (archivo.startsWith("_")) continue;
    const doc = JSON.parse(readFileSync(join(datos, "preguntas", archivo), "utf8"));
    for (const p of doc.preguntas ?? []) {
      total++;
      conteo.set(p.subtema, (conteo.get(p.subtema) ?? 0) + 1);
      huerfanas.push([archivo, p.numero, p.subtema]);
    }
  }
  return { conteo, total, huerfanas };
}

const { subtemas, cursos } = leerTemario();
const { conteo, total, huerfanas } = leerBanco();

const cursoPedido = process.argv.includes("--subtemas")
  ? process.argv[process.argv.indexOf("--subtemas") + 1]
  : null;

if (cursoPedido) {
  const curso = cursos.find((c) => c.codigo === cursoPedido.toUpperCase());
  if (!curso) {
    console.error(`No conozco el curso "${cursoPedido}". Códigos: ${cursos.map((c) => c.codigo).join(", ")}`);
    process.exit(1);
  }
  const sin = curso.subtemas.filter((c) => !conteo.has(c));
  console.log(`\n${curso.nombre} — ${sin.length} de ${curso.subtemas.length} subtemas sin ninguna pregunta\n`);
  let temaActual = null;
  for (const codigo of sin) {
    const s = subtemas.get(codigo);
    if (s.tema !== temaActual) {
      temaActual = s.tema;
      console.log(`  ${temaActual}`);
    }
    console.log(`    ${codigo}  ${s.nombre}`);
  }
  console.log();
  process.exit(0);
}

const cubiertos = [...subtemas.keys()].filter((c) => conteo.has(c));
const rotas = huerfanas.filter(([, , codigo]) => !subtemas.has(codigo));

console.log(`\nBanco: ${total} preguntas`);
console.log(
  `Sílabo: ${cubiertos.length} de ${subtemas.size} subtemas tienen al menos una ` +
    `(${((cubiertos.length / subtemas.size) * 100).toFixed(1)} %)\n`,
);

const filas = cursos
  .map((c) => {
    const conPregunta = c.subtemas.filter((s) => conteo.has(s)).length;
    const preguntas = c.subtemas.reduce((n, s) => n + (conteo.get(s) ?? 0), 0);
    return { ...c, conPregunta, preguntas, cobertura: conPregunta / c.subtemas.length };
  })
  .sort((a, b) => a.cobertura - b.cobertura);

console.log("  curso                         preg.  subtemas cubiertos");
for (const f of filas) {
  const barra = "█".repeat(Math.round(f.cobertura * 20)).padEnd(20, "·");
  console.log(
    `  ${f.nombre.padEnd(28)} ${String(f.preguntas).padStart(4)}   ${barra} ` +
      `${String(f.conPregunta).padStart(3)}/${String(f.subtemas.length).padEnd(3)} ` +
      `${(f.cobertura * 100).toFixed(0).padStart(3)} %`,
  );
}

if (rotas.length) {
  // Un código que no existe en el sílabo NO es cosmético: `cargar()` descarta
  // esa pregunta en silencio, así que está en el archivo y no llega nunca a
  // ninguna pantalla.
  console.log(`\n${rotas.length} preguntas apuntan a un subtema que no existe y la app descarta:`);
  for (const [archivo, numero, codigo] of rotas.slice(0, 20)) {
    console.log(`  ${archivo} nº ${numero} → ${codigo}`);
  }
}

console.log(`\nLos huecos de un curso:  node tool/cobertura.mjs --subtemas ${filas[0].codigo}\n`);
