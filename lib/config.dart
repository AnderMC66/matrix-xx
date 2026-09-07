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
