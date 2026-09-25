import "package:flutter/material.dart";

import "package:matr_u/data/models/sesion.dart";
import "package:matr_u/ui/core/theme/tema.dart";
import "package:matr_u/ui/core/widgets/ios.dart";
import "package:matr_u/ui/core/widgets/nota.dart";

/// `/entrar` — acceso y registro en una sola pantalla, como en la web.
class PantallaEntrar extends StatefulWidget {
  /// Se llama cuando ya hay sesión, para que el armazón vuelva a construirse.
  final VoidCallback alEntrar;

  /// Sesión inyectable, igual que en `PantallaHorario` y `SesionPractica`.
  /// `Sesion()` resuelve `Supabase.instance.client` en su constructor, así que
  /// sin esta costura la pantalla no se puede montar en un test. En producción
  /// nadie la pasa.
  final Sesion? sesion;

  const PantallaEntrar({super.key, required this.alEntrar, this.sesion});

  @override
  State<PantallaEntrar> createState() => _PantallaEntrarState();
}

class _PantallaEntrarState extends State<PantallaEntrar> {
  late final _sesion = widget.sesion ?? Sesion();

  bool _registrando = false;
  bool _enviando = false;
  String? _error;
  String? _aviso;

  final _correo = TextEditingController();
  final _contrasena = TextEditingController();
  final _nombre = TextEditingController();

  List<AreaPostulacion>? _areas;
  int? _area;

  @override
  void initState() {
    super.initState();
    // Las áreas solo hacen falta al registrarse; se piden una vez y en
    // segundo plano, para que un fallo de red no bloquee el formulario de
    // entrar, que es el camino del 90 % de las visitas.
    _sesion
        .areas()
        .then((a) {
          if (mounted) setState(() => _areas = a);
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    _correo.dispose();
    _contrasena.dispose();
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    setState(() {
      _enviando = true;
      _error = null;
      _aviso = null;
    });

    try {
      if (_registrando) {
        final faltaConfirmar = await _sesion.registrarse(
          correo: _correo.text,
          contrasena: _contrasena.text,
          nombre: _nombre.text,
          areaPostulacionId: _area,
        );
        if (!mounted) return;
        if (faltaConfirmar) {
          setState(() {
            _aviso =
                "Cuenta creada. Te enviamos un correo de confirmación: "
                "ábrelo para poder entrar.";
          });
          return;
        }
      } else {
        await _sesion.entrar(_correo.text, _contrasena.text);
      }
      if (mounted) widget.alEntrar();
    } on ErrorSesion catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (e) {
      if (mounted) setState(() => _error = "No se pudo conectar. $e");
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  /// Manda el correo de recuperación.
  ///
  /// **El acuse es el mismo exista la cuenta o no**, y no por descuido: el
  /// servidor de auth responde igual en los dos casos a propósito, y si esta
  /// pantalla distinguiera «no hay cuenta con ese correo» de «te lo mandamos»,
  /// sería un comprobador de quién está registrado aquí que cualquiera podría
  /// usar sin tener cuenta.
  Future<void> _recuperar() async {
    setState(() {
      _enviando = true;
      _error = null;
      _aviso = null;
    });

    try {
      await _sesion.recuperarContrasena(_correo.text);
      if (mounted) {
        setState(() {
          _aviso =
              "Si hay una cuenta con ese correo, le acaba de llegar un "
              "enlace para poner una contraseña nueva. Ábrelo desde este "
              "mismo teléfono: te devuelve a la app.";
        });
      }
    } on ErrorSesion catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (e) {
      if (mounted) setState(() => _error = "No se pudo conectar. $e");
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // `AutofillGroup` envuelve el formulario entero: es lo que permite al
    // gestor del sistema rellenar correo y contraseña de una sola vez.
    return AutofillGroup(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          const SizedBox(height: 24),
          _Marca(registrando: _registrando),
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
              if (_registrando)
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
                alEnviar: _enviando ? null : _enviar,
                // `newPassword` al registrarse para que el gestor ofrezca
                // generar una; `password` al entrar para que ofrezca la
                // guardada.
                autocompletar: _registrando
                    ? const [AutofillHints.newPassword]
                    : const [AutofillHints.password],
              ),
            ],
          ),

          if (_registrando && _areas != null) ...[
            const SizedBox(height: 20),
            GrupoInset(
              titulo: "Área de postulación",
              filas: [
                for (final a in _areas!)
                  FilaInset(
                    titulo: a.nombre,
                    // Marca de verificación en vez de un desplegable: con
                    // cinco opciones, un `Dropdown` esconde cuatro detrás de
                    // un toque. Es el patrón de selección de iOS.
                    alFinal: _area == a.id
                        ? Icon(
                            Icons.check,
                            size: 20,
                            color: context.esquema.primary,
                          )
                        : null,
                    onTap: () =>
                        setState(() => _area = _area == a.id ? null : a.id),
                  ),
              ],
            ),
          ],

          // ---- Avisos -----------------------------------------------------
          if (_error case final e?) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Nota.error(texto: e, icono: Icons.error_outline),
            ),
          ],
          if (_aviso case final a?) ...[
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
                  texto: _registrando ? "Crear cuenta" : "Entrar",
                  cargando: _enviando,
                  onPressed: _enviar,
                ),
                const SizedBox(height: 10),
                BotonSecundario(
                  texto: _registrando
                      ? "Ya tengo cuenta"
                      : "No tengo cuenta, quiero registrarme",
                  onPressed: _enviando
                      ? null
                      : () => setState(() {
                          _registrando = !_registrando;
                          _error = null;
                          _aviso = null;
                        }),
                ),
              ],
            ),
          ),

          // Solo al entrar: quien se está registrando todavía no tiene
          // contraseña que olvidar, y el enlace ahí solo sería ruido.
          if (!_registrando) ...[
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: _enviando ? null : _recuperar,
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
              _registrando
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
    );
  }
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
