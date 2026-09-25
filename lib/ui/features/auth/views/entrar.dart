import "package:flutter/material.dart";
import "package:matr_u/data/repositories/sesion.dart";
import "package:matr_u/ui/core/theme/tema.dart";
import "package:matr_u/ui/core/widgets/ios.dart";
import "package:matr_u/ui/core/widgets/nota.dart";
import "package:matr_u/ui/features/auth/view_models/entrar.dart";

/// `/entrar` — acceso y registro en una sola pantalla, como en la web.
class PantallaEntrar extends StatefulWidget {
  /// Se llama cuando ya hay sesion, para que el armazon vuelva a construirse.
  final VoidCallback alEntrar;

  /// El modelo de vista, inyectable. Si no llega, la pantalla construye el
  /// suyo con la sesion de produccion.
  final ModeloEntrar? modelo;

  const PantallaEntrar({super.key, required this.alEntrar, this.modelo});

  @override
  State<PantallaEntrar> createState() => _PantallaEntrarState();
}

class _PantallaEntrarState extends State<PantallaEntrar> {
  late final ModeloEntrar _modelo = widget.modelo ?? ModeloEntrar();

  /// Los tres campos se quedan aqui: son estado del `TextField`, y
  /// duplicarlos en el modelo obligaria a mantener los dos lados en
  /// sincronia para no ganar nada.
  final _correo = TextEditingController();
  final _contrasena = TextEditingController();
  final _nombre = TextEditingController();

  @override
  void initState() {
    super.initState();
    _modelo.cargarAreas();
  }

  @override
  void dispose() {
    _correo.dispose();
    _contrasena.dispose();
    _nombre.dispose();
    _modelo.dispose();
    super.dispose();
  }

  void _enviar() => _modelo.enviar(
    correo: _correo.text,
    contrasena: _contrasena.text,
    nombre: _nombre.text,
    alEntrar: widget.alEntrar,
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _modelo,
    // `AutofillGroup` envuelve el formulario entero: es lo que permite al
    // gestor del sistema rellenar correo y contraseña de una sola vez.
    builder: (context, _) => AutofillGroup(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          const SizedBox(height: 24),
          _Marca(registrando: _modelo.registrando),
          const SizedBox(height: 28),

          // ---- El formulario, como un grupo de iOS -------------------------
          //
          // Los campos van pegados dentro de UNA tarjeta, separados por una
          // línea con sangría. Es la diferencia visual más grande con Material,
          // donde cada campo es una caja suelta: aquí los tres se leen como
          // una cosa —«tus datos»— y no como tres preguntas seguidas.
          GrupoInset(
            sangriaSeparador: 52,
            filas: [
              if (_modelo.registrando)
                CampoIOS(
                  controlador: _nombre,
                  etiqueta: "Nombre",
                  icono: Icons.person_outline,
                  capitalizar: true,
                  autocompletar: const [AutofillHints.name],
                ),
              CampoIOS(
                controlador: _correo,
                etiqueta: "Correo",
                icono: Icons.alternate_email,
                teclado: TextInputType.emailAddress,
                autocompletar: const [AutofillHints.username],
              ),
              CampoIOS(
                controlador: _contrasena,
                etiqueta: "Contraseña",
                icono: Icons.lock_outline,
                oculto: true,
                alEnviar: _modelo.enviando ? null : _enviar,
                // `newPassword` al registrarse para que el gestor ofrezca
                // generar una; `password` al entrar para que ofrezca la
                // guardada.
                autocompletar: _modelo.registrando
                    ? const [AutofillHints.newPassword]
                    : const [AutofillHints.password],
              ),
            ],
          ),

          if (_modelo.registrando && _modelo.areas != null) ...[
            const SizedBox(height: 20),
            GrupoInset(
              titulo: "Área de postulación",
              filas: [
                for (final a in _modelo.areas!)
                  FilaInset(
                    titulo: a.nombre,
                    // Marca de verificación en vez de un desplegable: con
                    // cinco opciones, un `Dropdown` esconde cuatro detrás de
                    // un toque. Es el patrón de selección de iOS.
                    alFinal: _modelo.area == a.id
                        ? Icon(
                            Icons.check,
                            size: 20,
                            color: context.esquema.primary,
                          )
                        : null,
                    onTap: () =>
                        _modelo.elegirArea(_modelo.area == a.id ? null : a.id),
                  ),
              ],
            ),
          ],

          // ---- Avisos -----------------------------------------------------
          if (_modelo.error case final e?) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Nota.error(texto: e, icono: Icons.error_outline),
            ),
          ],
          if (_modelo.aviso case final a?) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Nota.exito(
                texto: a,
                icono: Icons.mark_email_unread_outlined,
              ),
            ),
          ],

          // ---- Acciones ---------------------------------------------------
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                BotonPrincipal(
                  texto: _modelo.registrando ? "Crear cuenta" : "Entrar",
                  cargando: _modelo.enviando,
                  onPressed: _enviar,
                ),
                const SizedBox(height: 10),
                BotonSecundario(
                  texto: _modelo.registrando
                      ? "Ya tengo cuenta"
                      : "No tengo cuenta, quiero registrarme",
                  onPressed: _modelo.enviando
                      ? null
                      : () => _modelo.cambiarModo(
                          registrando: !_modelo.registrando,
                        ),
                ),
              ],
            ),
          ),

          // Solo al entrar: quien se está registrando todavía no tiene
          // contraseña que olvidar, y el enlace ahí solo sería ruido.
          if (!_modelo.registrando) ...[
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: _modelo.enviando
                    ? null
                    : () => _modelo.recuperar(_correo.text),
                style: TextButton.styleFrom(
                  foregroundColor: context.esquema.onSurfaceVariant,
                ),
                child: const Text("Olvidé mi contraseña"),
              ),
            ),
          ],

          const SizedBox(height: 16),
          // **No hay «entrar con Google» ni acceso institucional**, y no es un
          // olvido: este proyecto no tiene ningún proveedor OAuth dado de alta
          // en Supabase. Un botón que no autentica es peor que ninguno.
          // Añadirlo son tres cosas: el proveedor en el panel, el
          // `intent-filter` —que ya existe, ver el manifiesto— y
          // `signInWithOAuth`. Ver LEEME.md.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _modelo.registrando
                  ? "Al crear la cuenta guardas tu progreso, tus repasos y tus "
                        "simulacros en el servidor."
                  : "La respuesta correcta la resuelve el servidor, no la app: "
                        "por eso practicar necesita cuenta.",
              textAlign: TextAlign.center,
              style: context.textos.bodySmall,
            ),
          ),
        ],
      ),
    ),
  );
}

/// La cabecera: logotipo, *Large Title* y subtítulo.
///
/// El logo es un glifo dentro de un cuadrado redondeado y no una imagen: la
/// marca de esta app es un lockup con texto que a 56 px no se leería. Un
/// símbolo simple aguanta cualquier tamaño y no depende de un asset.
class _Marca extends StatelessWidget {
  final bool registrando;
  const _Marca({required this.registrando});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.esquema.primary,
            borderRadius: BorderRadius.circular(16),
            // El halo del color de marca: es lo que hace que el cuadro se lea
            // como un objeto y no como un recorte pegado.
            boxShadow: [
              BoxShadow(
                color: context.esquema.primary.withValues(alpha: 0.28),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Text(
            "M",
            style: context.textos.displaySmall?.copyWith(
              color: context.esquema.onPrimary,
              fontSize: 30,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          registrando ? "Crea tu cuenta" : "Hola de nuevo",
          style: context.textos.displayLarge,
        ),
        const SizedBox(height: 6),
        Text(
          registrando
              ? "Un correo y una contraseña. Nada más."
              : "Entra para seguir donde lo dejaste.",
          style: context.textos.bodyLarge?.copyWith(
            color: context.esquema.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

/// Poner una contraseña nueva, al volver del enlace del correo.
///
/// La abre `Arranque` cuando Supabase emite `AuthChangeEvent.passwordRecovery`
/// —es decir, cuando el deep link `matrixu://acceso` trajo el token y el
/// cliente ya canjeó la sesión temporal—. No se llega aquí de ninguna otra
/// forma, y por eso no hay que pedir la contraseña anterior: quien abrió ese
/// correo ya demostró que la cuenta es suya.
///
/// Pide la contraseña dos veces porque el campo va enmascarado y esto no tiene
/// vuelta atrás: si se escribe mal, la sesión temporal se gasta igual y hay
/// que pedir otro correo. El ojo de `_Campo` ayuda, pero la segunda casilla es
/// la que evita el viaje.
class PantallaNuevaContrasena extends StatefulWidget {
  /// Se llama cuando la contraseña ya se cambió.
  final VoidCallback alCambiar;

  final Sesion? sesion;

  const PantallaNuevaContrasena({
    super.key,
    required this.alCambiar,
    this.sesion,
  });

  @override
  State<PantallaNuevaContrasena> createState() =>
      _PantallaNuevaContrasenaState();
}

class _PantallaNuevaContrasenaState extends State<PantallaNuevaContrasena> {
  late final _sesion = widget.sesion ?? Sesion();

  final _nueva = TextEditingController();
  final _repetida = TextEditingController();

  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _nueva.dispose();
    _repetida.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    // Se comprueba antes de salir a la red: el servidor no puede saber que el
    // alumno quiso escribir otra cosa.
    if (_nueva.text != _repetida.text) {
      setState(() => _error = "Las dos contraseñas no coinciden.");
      return;
    }

    setState(() {
      _enviando = true;
      _error = null;
    });

    try {
      await _sesion.cambiarContrasena(_nueva.text);
      if (mounted) widget.alCambiar();
    } on ErrorSesion catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (e) {
      if (mounted) setState(() => _error = "No se pudo conectar. $e");
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("Nueva contraseña")),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Text(
          "Elige tu contraseña nueva",
          style: context.textos.headlineMedium!.copyWith(
            fontWeight: FontWeight.w700,
            color: context.esquema.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "Al menos 8 caracteres. Este enlace sirve una sola vez: si sales "
          "ahora sin cambiarla, hay que pedir otro correo.",
          style: context.textos.bodyMedium!.copyWith(
            color: context.esquema.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        CampoIOS(
          controlador: _nueva,
          etiqueta: "Contraseña nueva",
          icono: Icons.lock_outline,
          oculto: true,
          autocompletar: const [AutofillHints.newPassword],
        ),
        const SizedBox(height: 12),
        CampoIOS(
          controlador: _repetida,
          etiqueta: "Repítela",
          icono: Icons.lock_reset_outlined,
          oculto: true,
          autocompletar: const [AutofillHints.newPassword],
          alEnviar: _enviando ? null : _enviar,
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Nota.error(texto: _error!, icono: Icons.error_outline),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _enviando ? null : _enviar,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: _enviando
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.esquema.onPrimary,
                  ),
                )
              : const Text("Guardar la contraseña"),
        ),
      ],
    ),
  );
}
