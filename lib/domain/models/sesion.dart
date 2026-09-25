class AreaPostulacion {
  final int id;
  final String nombre;
  const AreaPostulacion({required this.id, required this.nombre});
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
  // El caso más común de todos en un móvil, y el único que llegaba en inglés:
  // «Unable to validate email address: invalid format». Un dedo gordo escribe
  // "gmail.con" o se come la arroba, y el alumno leía una frase en inglés que
  // ni siquiera nombra el campo. No se valida antes con una expresión regular
  // a propósito: quien decide qué correo es válido es el servidor de auth, y
  // una regular propia acabaría rechazando direcciones legítimas.
  if (m.contains("unable to validate email") ||
      m.contains("invalid email") ||
      m.contains("email address") && m.contains("invalid")) {
    return "Ese correo no parece válido. Revísalo y vuelve a intentar.";
  }
  if (m.contains("rate limit") || m.contains("too many")) {
    return "Demasiados intentos. Espera unos minutos.";
  }
  // Los tres de la recuperación de contraseña. Sin ellos, la pantalla nueva
  // era la única de la app capaz de enseñar inglés.
  if (m.contains("should be different from the old password") ||
      m.contains("same_password")) {
    return "Esa es la contraseña que ya tenías. Elige otra.";
  }
  if (m.contains("token has expired") ||
      m.contains("invalid or has expired") ||
      m.contains("otp_expired")) {
    return "Ese enlace ya venció. Pide otro correo de recuperación.";
  }
  if (m.contains("auth session missing")) {
    return "El enlace ya no vale. Pide otro correo de recuperación.";
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
