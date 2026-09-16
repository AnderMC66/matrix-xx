import "package:supabase_flutter/supabase_flutter.dart";

/// Autenticación. Equivale a `src/app/entrar/acciones.ts`, con dos cosas que
/// aquí desaparecen y una que no.
///
/// **Desaparece el origen calculado.** En la web, `origen()` construye el
/// `emailRedirectTo` a partir de las cabeceras porque cada previsualización de
/// Vercel tiene su dominio y `x-forwarded-host` es falsificable. Una app no
/// tiene cabeceras ni dominio, así que aquí no se manda `emailRedirectTo` y el
/// enlace del correo va donde diga la «Site URL» del proyecto de Supabase: la
/// web.
///
/// **El `deep link` ahora existe de verdad.** Este comentario daba por hecho
/// que el enlace volvía a la app «por un deep link, que se declara en el
/// manifiesto» y en el manifiesto no había ninguno, así que el correo abría la
/// web y se volvía a mano. Desde el 2026-09-16 está declarado
/// ([enlaceRetorno]) y los dos correos que manda esta clase —confirmar la
/// cuenta y recuperar la contraseña— apuntan ahí.
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
/// A dónde vuelven los correos de auth: el `intent-filter` de
/// `AndroidManifest.xml`.
///
/// Tiene que coincidir **carácter por carácter** con una «Redirect URL» dada
/// de alta en el panel de Supabase (Authentication → URL Configuration). Si no
/// está en esa lista, el servidor de auth ignora lo que se le mande y usa la
/// «Site URL» — la web— sin avisar de nada: el correo llega, el enlace abre el
/// navegador y parece que la app no tiene deep link. Es el fallo más difícil
/// de diagnosticar de todo este tramo, porque no hay ningún error en ninguna
/// parte.
///
/// El esquema es `matrixu` y no `com.ander_u.matr_u` porque un esquema de URI
/// no admite guiones bajos (RFC 3986); ver la nota del manifiesto.
const enlaceRetorno = "matrixu://acceso";

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
        emailRedirectTo: enlaceRetorno,
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

  /// Manda el correo con el enlace para poner una contraseña nueva.
  ///
  /// **Antes no existía ninguna vía, y eso era lo más grave que le quedaba al
  /// acceso.** Quien olvidaba su contraseña se quedaba fuera de su progreso,
  /// su racha y sus simulacros sin ninguna salida dentro de la app: la
  /// pantalla solo sabía entrar y registrarse, y registrarse con el mismo
  /// correo devuelve «Ya existe una cuenta con ese correo».
  ///
  /// **Nunca dice si el correo está registrado o no**, y quien llama tampoco
  /// debe deducirlo: Supabase responde igual en los dos casos a propósito,
  /// porque un formulario que distingue «no existe» de «te mandamos el correo»
  /// es un comprobador de quién tiene cuenta aquí. La pantalla enseña el mismo
  /// acuse pase lo que pase.
  ///
  /// El enlace vuelve por [enlaceRetorno]; sin el `intent-filter` del
  /// manifiesto abriría la web, donde el token de un solo uso no sirve para
  /// esta app.
  Future<void> recuperarContrasena(String correo) async {
    if (correo.trim().isEmpty) {
      throw const ErrorSesion("Escribe tu correo para mandarte el enlace.");
    }
    try {
      await _cliente.auth.resetPasswordForEmail(
        correo.trim(),
        redirectTo: enlaceRetorno,
      );
    } on AuthException catch (e) {
      throw ErrorSesion(traducir(e.message));
    }
  }

  /// Pone la contraseña nueva. Exige la sesión temporal que abre el enlace de
  /// recuperación —o una sesión normal, si alguien la cambia estando dentro.
  ///
  /// Los 8 caracteres se comprueban aquí por lo mismo que en [registrarse]:
  /// para dar el aviso en español antes de gastar una petición. El servidor lo
  /// vuelve a comprobar de todos modos, que es quien manda.
  Future<void> cambiarContrasena(String nueva) async {
    if (nueva.length < 8) {
      throw const ErrorSesion(
        "La contraseña debe tener al menos 8 caracteres.",
      );
    }
    if (usuario == null) {
      throw const ErrorSesion(
        "El enlace ya no vale. Pide otro correo de recuperación.",
      );
    }
    try {
      await _cliente.auth.updateUser(UserAttributes(password: nueva));
    } on AuthException catch (e) {
      throw ErrorSesion(traducir(e.message));
    }
  }

  /// Borra la cuenta y todo lo que cuelga de ella, y cierra la sesión.
  ///
  /// **Es requisito de Google Play, no una mejora.** Toda app que deje crear
  /// una cuenta tiene que dejar borrarla desde dentro; sin esto la ficha se
  /// rechaza.
  ///
  /// Pasa por el RPC `eliminar_mi_cuenta` porque borrar de `auth.users` es
  /// una operación de administrador: con la clave publishable no se puede, y
  /// la secret key no puede viajar en un APK. La función resuelve a quién
  /// borrar con `auth.uid()` y no acepta parámetros, así que no hay forma de
  /// pedirle que borre a otro — ver
  /// `20260914120000_borrar_cuenta.sql` en el repo web.
  ///
  /// El `signOut` local va después y fuera del `try`: si el borrado salió
  /// bien, la sesión que quedaba en el dispositivo apunta a un usuario que ya
  /// no existe, y dejarla ahí haría que la siguiente pantalla fallara con un
  /// error incomprensible en vez de volver al estado de "sin cuenta".
  Future<void> eliminarCuenta() async {
    if (usuario == null) {
      throw const ErrorSesion("No hay ninguna sesión que borrar.");
    }
    try {
      await _cliente.rpc("eliminar_mi_cuenta");
    } on PostgrestException catch (e) {
      // PGRST202 = la función no está en la base. Pasa si el APK se publicó
      // antes de aplicar la migración, y el mensaje crudo de PostgREST no le
      // dice nada al alumno.
      if (e.code == "PGRST202") {
        throw const ErrorSesion(
          "El servidor todavía no admite el borrado de cuenta. Escríbenos y "
          "la borramos nosotros.",
        );
      }
      throw ErrorSesion(traducir(e.message));
    }
    await _cliente.auth.signOut();
  }

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
