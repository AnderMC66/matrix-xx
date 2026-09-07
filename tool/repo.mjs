/**
 * Dónde vive el repositorio web (MATRIX-U), del que sale todo el contenido.
 *
 * Este proyecto Flutter está FUERA de ese repositorio, así que la ruta no se
 * puede deducir: se configura aquí, o con la variable de entorno
 * `MATRIX_U_REPO` si tu copia está en otro sitio.
 *
 * El contenido tiene una sola fuente de verdad y es la del repo web
 * (`data/**\/*.json`, generado a su vez por los scripts `npm run teoria:*` y
 * `preguntas:*`). Aquí solo se copia. Nunca edites `assets/datos/` a mano: lo
 * sobrescribe el siguiente `sincronizar-datos`.
 */
import { existsSync } from "node:fs";

export const RUTA_REPO =
  process.env.MATRIX_U_REPO ?? "C:/source/MATRIX-U";

export function exigirRepo() {
  if (!existsSync(RUTA_REPO)) {
    console.error(
      `No encuentro el repositorio web en:\n  ${RUTA_REPO}\n\n` +
        "Corrige la ruta en tool/repo.mjs, o exporta MATRIX_U_REPO apuntando " +
        "a tu copia.",
    );
    process.exit(1);
  }
  return RUTA_REPO;
}
