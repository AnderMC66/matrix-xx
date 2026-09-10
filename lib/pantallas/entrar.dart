import "package:flutter/material.dart";

import "../datos/sesion.dart";
import "../tema.dart";

/// `/entrar` — acceso y registro en una sola pantalla, como en la web.
class PantallaEntrar extends StatefulWidget {
  /// Se llama cuando ya hay sesión, para que el armazón vuelva a construirse.
  final VoidCallback alEntrar;

  const PantallaEntrar({super.key, required this.alEntrar});

  @override
  State<PantallaEntrar> createState() => _PantallaEntrarState();
}

class _PantallaEntrarState extends State<PantallaEntrar> {
  final _sesion = Sesion();

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
          ),
          const SizedBox(height: 12),
        ],

        _Campo(
          controlador: _correo,
          etiqueta: "Correo",
          icono: Icons.mail_outline,
          teclado: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        _Campo(
          controlador: _contrasena,
          etiqueta: "Contraseña",
          icono: Icons.lock_outline,
          oculto: true,
          alEnviar: _enviando ? null : _enviar,
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
          _Nota(texto: _error!, esError: true),
        ],
        if (_aviso != null) ...[
          const SizedBox(height: 16),
          _Nota(texto: _aviso!, esError: false),
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
      ],
    );
  }
}

class _Campo extends StatelessWidget {
  final TextEditingController controlador;
  final String etiqueta;
  final IconData icono;
  final bool oculto;
  final bool capitalizar;
  final TextInputType? teclado;
  final VoidCallback? alEnviar;

  const _Campo({
    required this.controlador,
    required this.etiqueta,
    required this.icono,
    this.oculto = false,
    this.capitalizar = false,
    this.teclado,
    this.alEnviar,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: controlador,
    obscureText: oculto,
    keyboardType: teclado,
    autocorrect: false,
    textCapitalization: capitalizar
        ? TextCapitalization.words
        : TextCapitalization.none,
    textInputAction: alEnviar != null
        ? TextInputAction.done
        : TextInputAction.next,
    onSubmitted: alEnviar == null ? null : (_) => alEnviar!(),
    decoration: InputDecoration(
      labelText: etiqueta,
      prefixIcon: Icon(icono, size: 20),
      border: const OutlineInputBorder(),
    ),
  );
}

class _Nota extends StatelessWidget {
  final String texto;
  final bool esError;
  const _Nota({required this.texto, required this.esError});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: esError ? Paleta.acentoSuave : Paleta.exitoSuave,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          esError ? Icons.error_outline : Icons.mark_email_unread_outlined,
          size: 18,
          color: esError ? Paleta.acento : Paleta.exito,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: esError ? Paleta.acento : Paleta.exito,
            ),
          ),
        ),
      ],
    ),
  );
}
