import "package:flutter/material.dart";

import "../datos/sesion.dart";
import "../tema.dart";
import "../widgets/nota.dart";

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
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Text(
          _registrando ? "Crea tu cuenta" : "Entra a Matrix U",
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Paleta.texto,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _registrando
              ? "Tu progreso, tus repasos y tus simulacros quedan guardados."
              : "Necesitas cuenta para practicar: la respuesta correcta la "
                    "resuelve el servidor.",
          style: const TextStyle(
            color: Paleta.textoSuave,
            fontSize: 13.5,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),

        if (_registrando) ...[
          _Campo(
            controlador: _nombre,
            etiqueta: "Nombre",
            icono: Icons.person_outline,
            capitalizar: true,
            autocompletar: const [AutofillHints.name],
          ),
          const SizedBox(height: 12),
        ],

        _Campo(
          controlador: _correo,
          etiqueta: "Correo",
          icono: Icons.mail_outline,
          teclado: TextInputType.emailAddress,
          autocompletar: const [AutofillHints.username],
        ),
        const SizedBox(height: 12),
        _Campo(
          controlador: _contrasena,
          etiqueta: "Contraseña",
          icono: Icons.lock_outline,
          oculto: true,
          alEnviar: _enviando ? null : _enviar,
          // `newPassword` al registrarse para que el gestor ofrezca generar
          // una, `password` al entrar para que ofrezca la guardada.
          autocompletar: _registrando
              ? const [AutofillHints.newPassword]
              : const [AutofillHints.password],
        ),

        if (_registrando && _areas != null) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _area,
            decoration: const InputDecoration(
              labelText: "Área de postulación (opcional)",
              prefixIcon: Icon(Icons.school_outlined, size: 20),
              border: OutlineInputBorder(),
            ),
            items: [
              for (final a in _areas!)
                DropdownMenuItem(value: a.id, child: Text(a.nombre)),
            ],
            onChanged: (v) => setState(() => _area = v),
          ),
        ],

        if (_error != null) ...[
          const SizedBox(height: 16),
          Nota.error(texto: _error!, icono: Icons.error_outline),
        ],
        if (_aviso != null) ...[
          const SizedBox(height: 16),
          Nota.exito(texto: _aviso!, icono: Icons.mark_email_unread_outlined),
        ],

        const SizedBox(height: 20),
        FilledButton(
          onPressed: _enviando ? null : _enviar,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: _enviando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Paleta.acentoContraste,
                  ),
                )
              : Text(_registrando ? "Crear cuenta" : "Entrar"),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _enviando
              ? null
              : () => setState(() {
                  _registrando = !_registrando;
                  _error = null;
                  _aviso = null;
                }),
          child: Text(
            _registrando
                ? "Ya tengo cuenta"
                : "No tengo cuenta, quiero registrarme",
          ),
        ),
        // Solo al entrar: quien se está registrando todavía no tiene
        // contraseña que olvidar, y el enlace ahí solo sería ruido.
        if (!_registrando)
          TextButton(
            onPressed: _enviando ? null : _recuperar,
            style: TextButton.styleFrom(foregroundColor: Paleta.textoSuave),
            child: const Text("Olvidé mi contraseña"),
          ),
      ],
    );
  }
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
        const Text(
          "Elige tu contraseña nueva",
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Paleta.texto,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          "Al menos 8 caracteres. Este enlace sirve una sola vez: si sales "
          "ahora sin cambiarla, hay que pedir otro correo.",
          style: TextStyle(
            color: Paleta.textoSuave,
            fontSize: 13.5,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        _Campo(
          controlador: _nueva,
          etiqueta: "Contraseña nueva",
          icono: Icons.lock_outline,
          oculto: true,
          autocompletar: const [AutofillHints.newPassword],
        ),
        const SizedBox(height: 12),
        _Campo(
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
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Paleta.acentoContraste,
                  ),
                )
              : const Text("Guardar la contraseña"),
        ),
      ],
    ),
  );
}

/// Un campo del formulario.
///
/// Es `StatefulWidget` por una sola cosa: el ojo de «ver la contraseña», que
/// tiene que recordar si está abierto. **No es un adorno.** El campo va
/// enmascarado, el teclado del móvil no corrige y la contraseña mínima son 8
/// caracteres: sin forma de mirar lo escrito, un dedo que resbala se lee en
/// pantalla como «Correo o contraseña incorrectos», que manda al alumno a
/// dudar del correo. Es el fallo de acceso más común que hay y el más barato
/// de quitar.
///
/// [autocompletar] conecta el campo con el gestor de contraseñas del sistema
/// (`autofillHints`). Sin eso, Android no ofrece guardar ni rellenar nada, y
/// quien usa un gestor tiene que copiar y pegar a mano entre dos apps.
class _Campo extends StatefulWidget {
  final TextEditingController controlador;
  final String etiqueta;
  final IconData icono;
  final bool oculto;
  final bool capitalizar;
  final TextInputType? teclado;
  final VoidCallback? alEnviar;
  final List<String>? autocompletar;

  const _Campo({
    required this.controlador,
    required this.etiqueta,
    required this.icono,
    this.oculto = false,
    this.capitalizar = false,
    this.teclado,
    this.alEnviar,
    this.autocompletar,
  });

  @override
  State<_Campo> createState() => _CampoState();
}

class _CampoState extends State<_Campo> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) => TextField(
    controller: widget.controlador,
    obscureText: widget.oculto && !_visible,
    keyboardType: widget.teclado,
    autocorrect: false,
    autofillHints: widget.autocompletar,
    textCapitalization: widget.capitalizar
        ? TextCapitalization.words
        : TextCapitalization.none,
    textInputAction: widget.alEnviar != null
        ? TextInputAction.done
        : TextInputAction.next,
    onSubmitted: widget.alEnviar == null ? null : (_) => widget.alEnviar!(),
    decoration: InputDecoration(
      labelText: widget.etiqueta,
      prefixIcon: Icon(widget.icono, size: 20),
      border: const OutlineInputBorder(),
      suffixIcon: !widget.oculto
          ? null
          : IconButton(
              // El tooltip es también la etiqueta que lee el lector de
              // pantalla: un ojo sin nombre se anuncia como «botón».
              tooltip: _visible ? "Ocultar la contraseña" : "Ver la contraseña",
              icon: Icon(
                _visible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
                color: Paleta.textoTenue,
              ),
              onPressed: () => setState(() => _visible = !_visible),
            ),
    ),
  );
}
