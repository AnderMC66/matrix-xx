/// Configuración que entra por `--dart-define-from-file=config/dev.json`.
///
/// No se leen archivos `.env` en tiempo de ejecución a propósito: en una app
/// compilada no existe `process.cwd()`, y un `.env` dentro de los assets viaja
/// en claro dentro del APK. `--dart-define` inyecta los valores en compilación.
///
/// La clave publishable es pública por diseño (viaja al navegador también en
/// la web), pero la `SUPABASE_SECRET_KEY` NUNCA debe entrar aquí: saltaría RLS
/// y cualquiera podría extraerla del binario.
class Config {
  static const urlSupabase = String.fromEnvironment("SUPABASE_URL");
  static const clavePublishable = String.fromEnvironment(
    "SUPABASE_PUBLISHABLE_KEY",
  );

  /// De dónde se descargan las figuras (`/preguntas/<archivo>` y
  /// `/teoria-figuras/<archivo>`). NO es Supabase Storage — eso era una
  /// intención de ESTADO.md que nunca se implementó. Las 3 590 figuras de
  /// teoría y la de preguntas viven, hoy, como estáticos versionados en
  /// `public/` del repo web y las sirve el mismo CDN de Vercel que sirve la
  /// página: se comprobó pidiendo `icon-512.png` contra este dominio (HTTP
  /// 200) y las rutas de figuras reales (HTTP 404 — están en el repo pero el
  /// despliegue de producción vigente es anterior a que se subieran; un
  /// `vercel --prod` desde MATRIX-U las resuelve solo, sin tocar esta app).
  ///
  /// Que la app dependa de la web en vez de bajarlas todas al APK es
  /// deliberado: 83 MB de figuras no caben en un binario móvil razonable, y
  /// este mismo dominio ya las sirve gratis vía CDN a quien las pida.
  static const urlSitio = String.fromEnvironment(
    "URL_SITIO",
    defaultValue: "https://matrix-u.vercel.app",
  );

  /// `geo-2027-004-trapecio.svg` → URL completa contra `urlSitio`. Mismo
  /// prefijo `/preguntas/` que usa `rutaPublicaFigura()` en la web
  /// (`src/lib/figuras.ts`).
  static String urlFiguraPregunta(String archivo) =>
      "$urlSitio/preguntas/$archivo";

  /// Igual que arriba, para las figuras de teoría — prefijo `/teoria-figuras/`,
  /// como `rutaPublicaFiguraTeoria()` en `src/lib/figuras-teoria.ts`.
  static String urlFiguraTeoria(String archivo) =>
      "$urlSitio/teoria-figuras/$archivo";

  static bool get configurado =>
      urlSupabase.isNotEmpty && clavePublishable.isNotEmpty;

  /// Mensaje para la pantalla de arranque cuando falta configuración, en vez
  /// de un crash opaco dentro del cliente de Supabase.
  static const ayuda =
      "Falta la configuración de Supabase.\n\n"
      "Copia config/dev.ejemplo.json a config/dev.json, rellena los dos "
      "valores y arranca con:\n\n"
      "flutter run --dart-define-from-file=config/dev.json";
}
