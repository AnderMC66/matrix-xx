import "dart:async";

import "package:flutter/material.dart";

import "../datos/preguntas.dart";
import "../datos/sesion.dart";
import "../datos/simulacro.dart";
import "../matematicas/formula.dart";
import "../tema.dart";
import "practica.dart" show FiguraPregunta;

/// `/simulacros` — los simulacros publicados, y el intento a medias si lo hay.
class PantallaSimulacro extends StatefulWidget {
  const PantallaSimulacro({super.key});

  @override
  State<PantallaSimulacro> createState() => _PantallaSimulacroState();
}

class _PantallaSimulacroState extends State<PantallaSimulacro> {
  final _repo = RepositorioSimulacro();
  final _sesion = Sesion();

  Future<(List<SimulacroResumen>, Intento?)>? _carga;

  @override
  void initState() {
    super.initState();
    _recargar();
  }

  Future<(List<SimulacroResumen>, Intento?)> _pedir() async =>
      (await _repo.publicados(), await _repo.intentoEnCurso());

  void _recargar() {
    if (!_sesion.hayCuenta) return;
    setState(() => _carga = _pedir());
  }

  @override
  Widget build(BuildContext context) {
    if (!_sesion.hayCuenta) {
      return const _Aviso(
        icono: Icons.lock_outline,
        titulo: "El simulacro necesita tu cuenta",
        detalle:
            "El cronómetro, el puntaje y la comparación con otros "
            "postulantes se calculan en el servidor.\n\n"
            "Usa el botón de entrar, arriba a la derecha.",
      );
    }

    return FutureBuilder<(List<SimulacroResumen>, Intento?)>(
      future: _carga,
      builder: (context, snap) {
        if (snap.hasError) {
          return _Aviso(
            icono: Icons.cloud_off_outlined,
            titulo: "No se pudieron cargar los simulacros",
            detalle: "${snap.error}",
            accion: ("Reintentar", _recargar),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final (simulacros, enCurso) = snap.data!;
        if (simulacros.isEmpty) {
          return const _Aviso(
            icono: Icons.inbox_outlined,
            titulo: "Todavía no hay simulacros publicados",
            detalle: "Aparecerán aquí en cuanto se publiquen.",
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (enCurso != null) ...[
              _IntentoEnCurso(intento: enCurso, alVolver: _recargar),
              const SizedBox(height: 16),
            ],
            for (final s in simulacros)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TarjetaSimulacro(
                  simulacro: s,
                  bloqueado: enCurso != null,
                  alVolver: _recargar,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Retomar un examen a medias.
///
/// No existe en la web, y hace falta aquí: allí se vuelve por el historial del
/// navegador, y en una app no hay barra de direcciones. Sin esto, cerrar la
/// app a mitad de examen dejaría el intento abierto e inalcanzable, con su
/// cronómetro corriendo hasta agotarse solo.
class _IntentoEnCurso extends StatelessWidget {
  final Intento intento;
  final VoidCallback alVolver;

  const _IntentoEnCurso({required this.intento, required this.alVolver});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Paleta.avisoSuave,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Paleta.aviso.withValues(alpha: 0.35)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.timer_outlined, size: 18, color: Paleta.aviso),
            SizedBox(width: 8),
            Text(
              "Tienes un simulacro a medias",
              style: TextStyle(fontWeight: FontWeight.w700, color: Paleta.aviso),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          "El cronómetro sigue corriendo desde que lo empezaste: el plazo lo "
          "lleva el servidor, no esta pantalla.",
          style: TextStyle(fontSize: 12.5, color: Paleta.aviso, height: 1.45),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => _abrirSesion(context, intento.id, alVolver),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(42)),
          child: const Text("Retomar"),
        ),
      ],
    ),
  );
}

class _TarjetaSimulacro extends StatefulWidget {
  final SimulacroResumen simulacro;
  final bool bloqueado;
  final VoidCallback alVolver;

  const _TarjetaSimulacro({
    required this.simulacro,
    required this.bloqueado,
    required this.alVolver,
  });

  @override
  State<_TarjetaSimulacro> createState() => _TarjetaSimulacroState();
}

class _TarjetaSimulacroState extends State<_TarjetaSimulacro> {
  final _repo = RepositorioSimulacro();
  bool _iniciando = false;

  Future<void> _empezar() async {
    setState(() => _iniciando = true);
    try {
      final intentoId = await _repo.iniciar(widget.simulacro.id);
      if (!mounted) return;
      await _abrirSesion(context, intentoId, widget.alVolver);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("No se pudo empezar: $e")),
      );
    } finally {
      if (mounted) setState(() => _iniciando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.simulacro;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.nombre,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Paleta.texto,
              ),
            ),
            if (s.descripcion case final d? when d.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                d,
                style: const TextStyle(
                  fontSize: 13,
                  color: Paleta.textoSuave,
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.schedule, size: 15, color: Paleta.textoTenue),
                const SizedBox(width: 6),
                Text(
                  "${s.duracionMinutos} minutos",
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Paleta.textoTenue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton(
              // Con un intento abierto no se deja empezar otro: el de arriba
              // hay que cerrarlo o retomarlo. Dos exámenes a la vez es un
              // estado que ni el alumno ni el percentil saben interpretar.
              onPressed: widget.bloqueado || _iniciando ? null : _empezar,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
              child: Text(
                _iniciando
                    ? "Preparando…"
                    : widget.bloqueado
                    ? "Termina el que tienes a medias"
                    : "Empezar",
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _abrirSesion(
  BuildContext context,
  int intentoId,
  VoidCallback alVolver,
) async {
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => SesionSimulacro(intentoId: intentoId)),
  );
  alVolver();
}

/// La sesión de examen.
///
/// Réplica de `components/sesion-simulacro.tsx`, y las diferencias con la
/// práctica son las mismas que allí: sin revelación inmediata (el RPC retiene
/// la clave hasta cerrar el intento), sin botón «Comprobar» —marcar guarda
/// directo—, un cronómetro de examen completo en vez de uno por pregunta, y
/// navegación libre entre preguntas en vez de un flujo de una sola vía.
class SesionSimulacro extends StatefulWidget {
  final int intentoId;
  const SesionSimulacro({super.key, required this.intentoId});

  @override
  State<SesionSimulacro> createState() => _SesionSimulacroState();
}

enum _Guardado { guardando, guardado, error }

class _SesionSimulacroState extends State<SesionSimulacro> {
  final _repo = RepositorioSimulacro();

  List<PreguntaSimulacro>? _preguntas;
  SimulacroResumen? _simulacro;
  String? _errorCarga;

  int _indice = 0;
  final _respuestas = <int, Letra>{};
  final _estado = <int, _Guardado>{};

  /// La última letra elegida por pregunta. Sirve para descartar el resultado
  /// de un guardado que llegó tarde: si el alumno ya cambió de alternativa
  /// mientras el envío anterior seguía en vuelo, ese resultado no debe pisar
  /// la elección más reciente.
  final _ultimaLetra = <int, Letra>{};

  DateTime? _limite;
  Duration _restante = Duration.zero;
  Timer? _reloj;
  bool _finalizando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final intento = await _repo.intento(widget.intentoId);
      if (intento == null) {
        setState(() => _errorCarga = "Este intento no existe o no es tuyo.");
        return;
      }
      // Ya cerrado: no hay sesión que retomar, al resultado.
      if (!intento.enCurso) {
        if (mounted) _irAlResultado(intento.id);
        return;
      }

      final simulacro = await _repo.simulacro(intento.simulacroId);
      final preguntas = await _repo.preguntasDe(intento);
      if (!mounted) return;

      // El plazo sale de `iniciado_en` + `duracion_minutos`, ambos del
      // servidor. El reloj del dispositivo solo decide cómo se ve la cuenta
      // atrás: quien rechaza una respuesta tardía es Postgres, desde
      // `20260827120000_cronometro_en_servidor.sql`. Un móvil con la hora
      // corrida muestra mal el cronómetro, pero no gana ni pierde tiempo.
      final limite = intento.iniciadoEn.add(
        Duration(minutes: simulacro?.duracionMinutos ?? 0),
      );

      setState(() {
        _simulacro = simulacro;
        _preguntas = preguntas;
        _limite = limite;
        for (final p in preguntas) {
          if (p.respuestaPrevia case final l?) {
            _respuestas[p.preguntaId] = l;
            _ultimaLetra[p.preguntaId] = l;
            _estado[p.preguntaId] = _Guardado.guardado;
          }
        }
      });
      _arrancarReloj();
    } catch (e) {
      if (mounted) setState(() => _errorCarga = "$e");
    }
  }

  void _arrancarReloj() {
    void tic() {
      final limite = _limite;
      if (limite == null) return;
      final restante = limite.difference(DateTime.now().toUtc());
      setState(() => _restante = restante.isNegative ? Duration.zero : restante);
      if (restante.isNegative || restante == Duration.zero) {
        _reloj?.cancel();
        _finalizar();
      }
    }

    tic();
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) => tic());
  }

  /// Guarda una respuesta, reintentando hasta 3 veces con espera creciente.
  ///
  /// El plazo agotado NO se reintenta: no es un fallo de red, y machacar el
  /// servidor tres veces para acabar diciéndole al alumno «revisa tu
  /// conexión» cuando lo que pasó es que se acabó el examen sería mentirle.
  /// Se cierra el intento, que es lo que el cronómetro iba a hacer igual.
  Future<void> _guardar(int preguntaId, Letra letra) async {
    setState(() => _estado[preguntaId] = _Guardado.guardando);

    for (var intento = 0; intento < 3; intento++) {
      try {
        await _repo.responder(
          intentoId: widget.intentoId,
          preguntaId: preguntaId,
          letra: letra,
        );
        if (!mounted) return;
        if (_ultimaLetra[preguntaId] == letra) {
          setState(() => _estado[preguntaId] = _Guardado.guardado);
        }
        return;
      } on TiempoAgotado {
        await _finalizar();
        return;
      } catch (_) {
        if (intento < 2) {
          await Future<void>.delayed(Duration(milliseconds: 800 * (intento + 1)));
        }
      }
    }

    if (!mounted) return;
    if (_ultimaLetra[preguntaId] == letra) {
      setState(() => _estado[preguntaId] = _Guardado.error);
    }
  }

  void _marcar(int preguntaId, Letra letra) {
    setState(() {
      _respuestas[preguntaId] = letra;
      _ultimaLetra[preguntaId] = letra;
    });
    _guardar(preguntaId, letra);
  }

  Future<void> _finalizar() async {
    if (_finalizando) return;
    _finalizando = true;
    _reloj?.cancel();

    try {
      await _repo.finalizar(widget.intentoId);
    } catch (_) {
      // Aunque el cierre explícito falle, se navega igual al resultado: si el
      // intento ya estaba cerrado (doble pulsación, o el cronómetro justo
      // después de un envío manual) `finalizar_intento` es idempotente y no
      // hay nada que reintentar.
    }
    if (mounted) _irAlResultado(widget.intentoId);
  }

  void _irAlResultado(int intentoId) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PantallaResultado(intentoId: intentoId),
      ),
    );
  }

  Future<void> _confirmarFin() async {
    final preguntas = _preguntas ?? const [];
    final sinResponder = preguntas.length - _respuestas.length;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text("¿Finalizar el simulacro?"),
        content: Text(
          sinResponder > 0
              ? "Te quedan $sinResponder preguntas sin responder. Al "
                    "finalizar no podrás volver atrás."
              : "Al finalizar no podrás volver atrás.",
        ),
        actions: [
          // La salida segura va primero y es la que recibe el foco por
          // defecto, como en el diálogo de la web: en algo irreversible, lo
          // fácil de pulsar por accidente tiene que ser lo que no rompe nada.
          TextButton(
            onPressed: () => Navigator.of(contexto).pop(false),
            child: const Text("Seguir respondiendo"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexto).pop(true),
            child: const Text("Finalizar"),
          ),
        ],
      ),
    );

    if (confirmado ?? false) await _finalizar();
  }

  @override
  Widget build(BuildContext context) {
    if (_errorCarga != null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Simulacro")),
        body: _Aviso(
          icono: Icons.error_outline,
          titulo: "No se pudo abrir el simulacro",
          detalle: _errorCarga!,
        ),
      );
    }

    final preguntas = _preguntas;
    if (preguntas == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Simulacro")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (preguntas.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("Simulacro")),
        body: const _Aviso(
          icono: Icons.inbox_outlined,
          titulo: "Este simulacro no tiene preguntas",
          detalle: "Ninguna de sus preguntas está en esta versión de la app.",
        ),
      );
    }

    final actual = preguntas[_indice];
    final marcada = _respuestas[actual.preguntaId];
    final pocoTiempo = _restante.inMinutes < 5;

    return PopScope(
      // Salir con el gesto de atrás dejaría el examen corriendo sin que se
      // note. Se intercepta y se ofrece finalizar, que es la decisión real.
      canPop: false,
      onPopInvokedWithResult: (hecho, _) {
        if (!hecho) _confirmarFin();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _simulacro?.nombre ?? "Simulacro",
            style: const TextStyle(fontSize: 15),
          ),
          actions: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: pocoTiempo ? Paleta.avisoSuave : Paleta.superficie,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: pocoTiempo ? Paleta.aviso : Paleta.borde,
                  ),
                ),
                child: Text(
                  _reloj == null ? "--:--" : formatearRestante(_restante),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: pocoTiempo ? Paleta.aviso : Paleta.texto,
                  ),
                ),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(
              value: _respuestas.length / preguntas.length,
              minHeight: 4,
              backgroundColor: Paleta.borde,
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "${_indice + 1} de ${preguntas.length}",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Paleta.textoTenue,
                  ),
                ),
                Text(
                  "${_respuestas.length} respondidas",
                  style: const TextStyle(fontSize: 12, color: Paleta.textoTenue),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextoConFormulas(actual.pregunta.enunciado),
            if (actual.pregunta.imagen case final f?) ...[
              const SizedBox(height: 14),
              FiguraPregunta(figura: f),
            ],
            const SizedBox(height: 18),

            for (final alt in actual.pregunta.alternativas)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _AlternativaSimulacro(
                  alternativa: alt,
                  marcada: marcada == alt.letra,
                  // Marcar guarda directo: no hay «Comprobar» porque no hay
                  // nada que revelar hasta que el examen se cierre.
                  alPulsar: () => _marcar(actual.preguntaId, alt.letra),
                ),
              ),

            const SizedBox(height: 6),
            _EstadoGuardado(estado: _estado[actual.preguntaId]),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            const Text(
              "Ir a una pregunta",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Paleta.textoSuave,
              ),
            ),
            const SizedBox(height: 10),
            _Indice(
              preguntas: preguntas,
              respuestas: _respuestas,
              estado: _estado,
              actual: _indice,
              alElegir: (i) => setState(() => _indice = i),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _indice > 0
                        ? () => setState(() => _indice--)
                        : null,
                    child: const Text("Anterior"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _indice < preguntas.length - 1
                      ? FilledButton(
                          onPressed: () => setState(() => _indice++),
                          child: const Text("Siguiente"),
                        )
                      : FilledButton(
                          onPressed: _finalizando ? null : _confirmarFin,
                          child: const Text("Finalizar"),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `mm:ss`, con los minutos totales aunque pasen de 60: un simulacro de 120
/// minutos arranca en `120:00`, no en `2:00:00`. Es la misma lectura que da la
/// web, y en un examen «cuántos minutos me quedan» se lee de un vistazo mejor
/// que un formato con horas.
///
/// Una duración negativa se muestra como `00:00` en vez de `-1:-3`: el reloj
/// puede tardar un tic en llegar a cero y el alumno no debe ver eso.
String formatearRestante(Duration d) {
  if (d.isNegative) return "00:00";
  final mm = d.inMinutes.toString().padLeft(2, "0");
  final ss = (d.inSeconds % 60).toString().padLeft(2, "0");
  return "$mm:$ss";
}

/// El estado de guardado va por pregunta, no compartido.
///
/// Con un solo indicador global, marcar la siguiente pregunta borraba el aviso
/// de que la anterior no se había guardado: un fallo real desaparecía de la
/// vista aunque siguiera sin guardarse. La web arregló exactamente esto.
class _EstadoGuardado extends StatelessWidget {
  final _Guardado? estado;
  const _EstadoGuardado({required this.estado});

  @override
  Widget build(BuildContext context) => switch (estado) {
    null => const SizedBox.shrink(),
    _Guardado.guardando => const _Linea(
      icono: Icons.sync,
      texto: "Guardando…",
      color: Paleta.textoTenue,
    ),
    _Guardado.guardado => const _Linea(
      icono: Icons.cloud_done_outlined,
      texto: "Guardada",
      color: Paleta.exito,
    ),
    _Guardado.error => const _Linea(
      icono: Icons.cloud_off_outlined,
      texto: "No se pudo guardar. Vuelve a marcarla.",
      color: Paleta.acento,
    ),
  };
}

class _Linea extends StatelessWidget {
  final IconData icono;
  final String texto;
  final Color color;
  const _Linea({
    required this.icono,
    required this.texto,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icono, size: 14, color: color),
      const SizedBox(width: 6),
      Text(texto, style: TextStyle(fontSize: 12, color: color)),
    ],
  );
}

/// La rejilla de navegación: de un vistazo, qué falta y qué no se guardó.
class _Indice extends StatelessWidget {
  final List<PreguntaSimulacro> preguntas;
  final Map<int, Letra> respuestas;
  final Map<int, _Guardado> estado;
  final int actual;
  final void Function(int) alElegir;

  const _Indice({
    required this.preguntas,
    required this.respuestas,
    required this.estado,
    required this.actual,
    required this.alElegir,
  });

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final (i, p) in preguntas.indexed)
        _Celda(
          numero: i + 1,
          esActual: i == actual,
          respondida: respuestas.containsKey(p.preguntaId),
          fallo: estado[p.preguntaId] == _Guardado.error,
          alPulsar: () => alElegir(i),
        ),
    ],
  );
}

class _Celda extends StatelessWidget {
  final int numero;
  final bool esActual;
  final bool respondida;
  final bool fallo;
  final VoidCallback alPulsar;

  const _Celda({
    required this.numero,
    required this.esActual,
    required this.respondida,
    required this.fallo,
    required this.alPulsar,
  });

  @override
  Widget build(BuildContext context) {
    final (fondo, texto, borde) = fallo
        ? (Paleta.acentoSuave, Paleta.acento, Paleta.acento)
        : respondida
        ? (Paleta.acento, Paleta.acentoContraste, Paleta.acento)
        : (Paleta.superficieAlta, Paleta.textoSuave, Paleta.borde);

    return SizedBox(
      width: 36,
      height: 36,
      child: Material(
        color: fondo,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: alPulsar,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: esActual ? Paleta.texto : borde,
                width: esActual ? 2 : 1,
              ),
            ),
            child: Text(
              "$numero",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: texto,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlternativaSimulacro extends StatelessWidget {
  final Alternativa alternativa;
  final bool marcada;
  final VoidCallback alPulsar;

  const _AlternativaSimulacro({
    required this.alternativa,
    required this.marcada,
    required this.alPulsar,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: marcada ? Paleta.acentoSuave : Paleta.superficieAlta,
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      onTap: alPulsar,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: marcada ? Paleta.acento : Paleta.borde,
            width: marcada ? 1.6 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: marcada ? Paleta.acento : Paleta.superficie,
                shape: BoxShape.circle,
              ),
              child: Text(
                alternativa.letra.etiqueta,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: marcada ? Paleta.acentoContraste : Paleta.textoSuave,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextoConFormulas(
                alternativa.texto,
                estilo: const TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: Paleta.texto,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// `/simulacros/resultado/[intentoId]`.
class PantallaResultado extends StatefulWidget {
  final int intentoId;
  const PantallaResultado({super.key, required this.intentoId});

  @override
  State<PantallaResultado> createState() => _PantallaResultadoState();
}

class _PantallaResultadoState extends State<PantallaResultado> {
  final _repo = RepositorioSimulacro();
  late final Future<(Intento, List<ResultadoPregunta>, PercentilSimulacro?)>
  _carga = _cargar();

  Future<(Intento, List<ResultadoPregunta>, PercentilSimulacro?)>
  _cargar() async {
    final intento = await _repo.intento(widget.intentoId);
    if (intento == null) throw "Este intento no existe o no es tuyo.";
    return (
      intento,
      await _repo.resultado(intento),
      await _repo.percentil(intento.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Resultado")),
      body: FutureBuilder<
        (Intento, List<ResultadoPregunta>, PercentilSimulacro?)
      >(
        future: _carga,
        builder: (context, snap) {
          if (snap.hasError) {
            return _Aviso(
              icono: Icons.error_outline,
              titulo: "No se pudo cargar el resultado",
              detalle: "${snap.error}",
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final (intento, detalle, percentil) = snap.data!;
          final sinResponder = detalle.where((r) => r.sinResponder).length;

          final porCurso = <String, List<ResultadoPregunta>>{};
          for (final r in detalle) {
            porCurso.putIfAbsent(r.cursoNombre, () => []).add(r);
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              Center(
                child: Column(
                  children: [
                    Text(
                      "${(intento.puntaje ?? 0).round()} %",
                      style: const TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.w800,
                        color: Paleta.acento,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "${intento.correctas ?? 0} de "
                      "${intento.totalPreguntas ?? detalle.length} correctas"
                      "${sinResponder > 0 ? " · $sinResponder sin responder" : ""}",
                      style: const TextStyle(
                        fontSize: 14,
                        color: Paleta.textoSuave,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              if (percentil != null) _Percentil(datos: percentil),
              const SizedBox(height: 24),
              const Text(
                "POR CURSO",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: Paleta.textoSuave,
                ),
              ),
              const SizedBox(height: 12),
              for (final e in porCurso.entries)
                _FilaCurso(curso: e.key, respuestas: e.value),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
                child: const Text("Volver a los simulacros"),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// El examen real es de cupo limitado: la pregunta que importa no es «¿cuánto
/// saqué?» sino «¿cómo voy frente a los demás?».
class _Percentil extends StatelessWidget {
  final PercentilSimulacro datos;
  const _Percentil({required this.datos});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Paleta.superficieAlta,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Paleta.borde),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "FRENTE A OTROS POSTULANTES",
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: Paleta.textoSuave,
          ),
        ),
        const SizedBox(height: 10),
        if (datos.percentil == null)
          Text(
            "Todavía no hay suficientes intentos de este simulacro para "
            "comparar sin que la cifra engañe."
            "${datos.totalIntentos > 0 ? " Van ${datos.totalIntentos} además del tuyo." : ""}",
            style: const TextStyle(
              fontSize: 13,
              color: Paleta.textoSuave,
              height: 1.5,
            ),
          )
        else ...[
          Text(
            "Estás por encima del ${datos.percentil} % de quienes lo rindieron.",
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: Paleta.texto,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            [
              "${datos.totalIntentos} intentos",
              if (datos.puntajeMediano != null)
                "mediana ${datos.puntajeMediano!.round()} %",
              if (datos.puntajeMaximo != null)
                "máximo ${datos.puntajeMaximo!.round()} %",
            ].join(" · "),
            style: const TextStyle(fontSize: 12.5, color: Paleta.textoTenue),
          ),
        ],
      ],
    ),
  );
}

class _FilaCurso extends StatelessWidget {
  final String curso;
  final List<ResultadoPregunta> respuestas;

  const _FilaCurso({required this.curso, required this.respuestas});

  @override
  Widget build(BuildContext context) {
    final aciertos = respuestas.where((r) => r.esCorrecta ?? false).length;
    final proporcion = respuestas.isEmpty ? 0.0 : aciertos / respuestas.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  curso,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Paleta.texto,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                "$aciertos/${respuestas.length}",
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Paleta.textoSuave,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: proporcion,
              minHeight: 6,
              backgroundColor: Paleta.borde,
              valueColor: AlwaysStoppedAnimation(
                proporcion >= 0.6 ? Paleta.exito : Paleta.acento,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String detalle;
  final (String, VoidCallback)? accion;

  const _Aviso({
    required this.icono,
    required this.titulo,
    required this.detalle,
    this.accion,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icono, size: 34, color: Paleta.textoTenue),
          const SizedBox(height: 14),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: Paleta.texto,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            detalle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Paleta.textoSuave,
              fontSize: 13,
              height: 1.55,
            ),
          ),
          if (accion case final a?) ...[
            const SizedBox(height: 20),
            OutlinedButton(onPressed: a.$2, child: Text(a.$1)),
          ],
        ],
      ),
    ),
  );
}
