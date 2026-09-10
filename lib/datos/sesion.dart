import "package:supabase_flutter/supabase_flutter.dart";

/// Autenticación. Equivale a `src/app/entrar/acciones.ts`, con dos cosas que
/// aquí desaparecen y una que no.
///
/// **Desaparece el origen calculado.** En la web, `origen()` construye el
/// `emailRedirectTo` a partir de las cabeceras porque cada previsualización de
/// Vercel tiene su dominio y `x-forwarded-host` es falsificable. Una app no
/// tiene cabeceras ni dominio: el enlace de confirmación vuelve por un
/// `deep link`, que se declara en el manifiesto y no lo elige quien registra.
///
/// **Desaparece Turnstile.** El widget es un iframe de Cloudflare; no hay
/// equivalente nativo con `supabase_flutter`. Importa menos de lo que parece:
/// como razona esa misma acción, quien valida el captcha es el servidor de
/// auth de Supabase, no la app — y a un bot nunca le hizo falta pasar por
/// aquí, porque la clave publishable es pública y puede llamar a
/// `/auth/v1/signup` directo. Si se activa el CAPTCHA en el panel, esta
/// pantalla dejará de poder registrar hasta que se le ponga un widget nativo.
/// Está anotado en LEEME.md.
///
/// **Se conserva la traducción de errores**, portada literal: son los mismos
/// mensajes de Supabase, en inglés, y el alumno merece leerlos en español.
class Sesion {
  final SupabaseClient _cliente;

  Sesion({SupabaseClient? cliente})
    : _cliente = cliente ?? Supabase.instance.client;

  User? get usuario => _cliente.auth.currentUser;

  bool get hayCuenta => usuario != null;

  Stream<AuthState> get cambios => _cliente.auth.onAuthStateChange;

  Future<void> entrar(String correo, String contrasena) async {
    if (correo.trim().isEmpty || contrasena.isEmpty) {
      throw const ErrorSesion("Completa el correo y la contraseña.");
    }
    try {
      await _cliente.auth.signInWithPassword(
        email: correo.trim(),
        password: contrasena,
      );
    } on AuthException catch (e) {
      throw ErrorSesion(traducir(e.message));
    }
  }

  /// Devuelve `true` si el proyecto exige confirmar el correo y por tanto
  /// todavía no hay sesión: la pantalla debe decirlo, no dar por entrado.
  Future<bool> registrarse({
    required String correo,
    required String contrasena,
    required String nombre,
    int? areaPostulacionId,
  }) async {
    if (correo.trim().isEmpty || contrasena.isEmpty || nombre.trim().isEmpty) {
      throw const ErrorSesion("Completa tu nombre, correo y contraseña.");
    }
    // 8 es el mínimo configurado en el proyecto de Supabase
    // (`password_min_length`). Se comprueba aquí para dar el aviso en español
    // antes de gastar una petición.
    if (contrasena.length < 8) {
      throw const ErrorSesion(
        "La contraseña debe tener al menos 8 caracteres.",
      );
    }

    try {
      // `nombre` viaja en la metadata porque el disparador `al_crear_usuario`
      // lo lee de ahí para rellenar `public.perfiles`.
      final respuesta = await _cliente.auth.signUp(
        email: correo.trim(),
        password: contrasena,
        data: {"nombre": nombre.trim()},
      );

      if (respuesta.session == null) return true;

      if (areaPostulacionId != null) {
        // El perfil ya lo creó el disparador; aquí solo se completa el área.
        await _cliente
            .from("perfiles")
            .update({"area_postulacion_id": areaPostulacionId})
            .eq("id", respuesta.session!.user.id);
      }
      return false;
    } on AuthException catch (e) {
      throw ErrorSesion(traducir(e.message));
    }
  }

  Future<void> salir() => _cliente.auth.signOut();

  /// Las áreas de postulación, para el desplegable del registro.
  Future<List<AreaPostulacion>> areas() async {
    final filas = await _cliente
        .from("areas_postulacion")
        .select("id, nombre")
        .order("id");
    return [
      for (final f in filas)
        AreaPostulacion(id: f["id"] as int, nombre: f["nombre"] as String),
    ];
  }
}

class AreaPostulacion {
  final int id;
  final String nombre;
  const AreaPostulacion({required this.id, required this.nombre});
}

/// Un fallo ya traducido y listo para enseñarle al alumno.
class ErrorSesion implements Exception {
  final String mensaje;
  const ErrorSesion(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Portada tal cual de `traducir()` en `entrar/acciones.ts`. Los mensajes de
/// Supabase llegan en inglés y son los mismos en las dos plataformas.
String traducir(String mensaje) {
  final m = mensaje.toLowerCase();
  if (m.contains("invalid login credentials")) {
    return "Correo o contraseña incorrectos.";
  }
  if (m.contains("email not confirmed")) {
    return "Todavía no confirmaste tu correo. Revisa tu bandeja de entrada.";
  }
  if (m.contains("user already registered")) {
    return "Ya existe una cuenta con ese correo. Intenta entrar.";
  }
  if (m.contains("password should be at least")) {
    return "La contraseña debe tener al menos 8 caracteres.";
  }
  if (m.contains("rate limit") || m.contains("too many")) {
    return "Demasiados intentos. Espera unos minutos.";
  }
  if (m.contains("captcha")) {
    // En la web esto casi siempre era configuración. Aquí es más concreto: la
    // app no manda token porque no tiene widget, así que si el CAPTCHA está
    // activado en el panel, TODOS los registros desde el móvil fallan aquí.
    return "El proyecto exige un CAPTCHA que la app todavía no incluye. "
        "Entra desde la web mientras tanto.";
  }
  return mensaje;
}
