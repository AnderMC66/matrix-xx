import "dart:async";

import "package:flutter/material.dart";
import "package:matr_u/core/utils/fechas.dart";
import "package:matr_u/data/repositories/sesion.dart";
import "package:matr_u/data/repositories/simulacro.dart";
import "package:matr_u/domain/models/preguntas.dart";
import "package:matr_u/domain/models/simulacro.dart";
import "package:matr_u/ui/core/theme/tema.dart";
import "package:matr_u/ui/core/widgets/aviso.dart";
import "package:matr_u/ui/core/widgets/formula.dart";
import "package:matr_u/ui/features/practice/views/practica.dart"
    show FiguraPregunta;

/// `/simulacros` — los simulacros publicados, y el intento a medias si lo hay.
class PantallaSimulacro extends StatefulWidget {
  /// Repositorio y sesión inyectables, igual que en `PantallaHorario`.
  ///
  /// Los dos resuelven `Supabase.instance.client` en su constructor, así que
  /// sin esta costura la pantalla no se puede montar en un test. Baja también
  /// a las tarjetas y a la sesión de examen: si se quedara aquí, el primer
  /// hijo que construyera el suyo volvería a romperlo. En producción nadie
  /// los pasa.
  final RepositorioSimulacro? repositorio;
  final Sesion? sesion;

  const PantallaSimulacro({super.key, this.repositorio, this.sesion});

  @override
  State<PantallaSimulacro> createState() => _PantallaSimulacroState();
}

class _PantallaSimulacroState extends State<PantallaSimulacro> {
  late final _repo = widget.repositorio ?? RepositorioSimulacro();
  late final _sesion = widget.sesion ?? Sesion();

  Future<(List<SimulacroResumen>, Intento?, List<Intento>)>? _carga;

  @override
  void initState() {
    super.initState();
    _recargar();
  }

  /// Las tres a la vez, como en Progreso y en Inicio.
  ///
  /// Un registro `(await a, await b, await c)` parece paralelo y no lo es: Dart
  /// evalúa los campos en orden, así que eran tres viajes encadenados contra
  /// Supabase para pintar una pantalla cuyos tres datos no dependen entre sí.
  /// Esta pestaña se rehace cada vez que se entra —es de las que leen del
  /// servidor, ver `main.dart`—, así que esas tres latencias se pagaban
  /// enteras en cada visita.
  Future<(List<SimulacroResumen>, Intento?, List<Intento>)> _pedir() async {
    final resultados = await Future.wait([
      _repo.publicados(),
      _repo.intentoEnCurso(),
      _repo.historial(),
    ]);
    return (
      resultados[0] as List<SimulacroResumen>,
      resultados[1] as Intento?,
      resultados[2] as List<Intento>,
    );
  }

  void _recargar() {
    if (!_sesion.hayCuenta) return;
    setState(() {
      _carga = _pedir();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_sesion.hayCuenta) {
      return const Aviso(
        icono: Icons.lock_outline,
        titulo: "El simulacro necesita tu cuenta",
        detalle:
            "El cronómetro, el puntaje y la comparación con otros "
            "postulantes se calculan en el servidor.\n\n"
            "Usa el botón de entrar, arriba a la derecha.",
      );
    }

    return FutureBuilder<(List<SimulacroResumen>, Intento?, List<Intento>)>(
      future: _carga,
      builder: (context, snap) {
        if (snap.hasError) {
          return Aviso(
            icono: Icons.cloud_off_outlined,
            titulo: "No se pudieron cargar los simulacros",
            detalle: "${snap.error}",
            accion: ("Reintentar", _recargar),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final (simulacros, enCurso, historial) = snap.data!;
        if (simulacros.isEmpty) {
          return const Aviso(
            icono: Icons.inbox_outlined,
            titulo: "Todavía no hay simulacros publicados",
            detalle: "Aparecerán aquí en cuanto se publiquen.",
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (enCurso != null) ...[
              _IntentoEnCurso(
                intento: enCurso,
                alVolver: _recargar,
                repositorio: _repo,
              ),
              const SizedBox(height: 16),
            ],
            for (final s in simulacros)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TarjetaSimulacro(
                  simulacro: s,
                  bloqueado: enCurso != null,
                  alVolver: _recargar,
                  repositorio: _repo,
                ),
              ),
            if (historial.isNotEmpty) ...[
              const SizedBox(height: 26),
              Text(
                "LO QUE YA RENDISTE",
                style: context.textos.labelSmall!.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: context.esquema.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              for (final intento in historial)
                _FilaHistorial(
                  intento: intento,
                  repositorio: _repo,
                  nombre: simulacros
                      .where((s) => s.id == intento.simulacroId)
                      .map((s) => s.nombre)
                      .firstOrNull,
                ),
            ],
          ],
        );
      },
    );
  }
}

/// Un simulacro ya rendido, que vuelve a abrir su resultado.
///
/// La pantalla de resultado ya existía y solo se alcanzaba una vez, justo al
/// terminar: el puntaje, el percentil y el desglose por curso quedaban en la
/// base sin nada que los leyera. Aquí no hace falta widget nuevo — basta con
/// volver a empujar `PantallaResultado` con el id del intento.
class _FilaHistorial extends StatelessWidget {
  final Intento intento;
  final RepositorioSimulacro repositorio;

  /// El nombre del simulacro, si sigue publicado. Puede faltar: un simulacro
  /// despublicado no desaparece de tu historial, solo pierde el rótulo.
  final String? nombre;

  const _FilaHistorial({
    required this.intento,
    required this.nombre,
    required this.repositorio,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (intento.puntaje ?? 0).round();
    // Sin `.toLocal()`: lo hace `fechaDiaMesAno` por dentro, para todas las
    // pantallas a la vez. Esta era la única que se acordaba.
    final fecha = intento.finalizadoEn;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: context.esquema.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PantallaResultado(
                intentoId: intento.id,
                repositorio: repositorio,
              ),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: context.esquema.outlineVariant),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                // El puntaje manda: es lo que se busca al mirar atrás.
                SizedBox(
                  width: 52,
                  child: Text(
                    "$pct %",
                    style: context.textos.headlineSmall!.copyWith(
                      fontWeight: FontWeight.w800,
                      color: pct >= 60
                          ? context.colores.exito
                          : context.esquema.error,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre ?? "Simulacro retirado",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textos.labelLarge!.copyWith(
                          fontWeight: FontWeight.w600,
                          color: context.esquema.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (fecha != null) fechaDiaMesAno(fecha),
                          if (intento.correctas != null &&
                              intento.totalPreguntas != null)
                            "${intento.correctas}/${intento.totalPreguntas} correctas",
                        ].join(" · "),
                        style: context.textos.bodySmall!.copyWith(
                          color: context.esquema.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: context.esquema.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
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
  final RepositorioSimulacro repositorio;

  const _IntentoEnCurso({
    required this.intento,
    required this.alVolver,
    required this.repositorio,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.colores.avisoContenedor,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.colores.aviso.withValues(alpha: 0.35)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.timer_outlined, size: 18, color: context.colores.aviso),
            SizedBox(width: 8),
            Text(
              "Tienes un simulacro a medias",
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: context.colores.aviso,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          "El cronómetro sigue corriendo desde que lo empezaste: el plazo lo "
          "lleva el servidor, no esta pantalla.",
          style: context.textos.bodySmall!.copyWith(
            color: context.colores.aviso,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => _abrirSesion(
            context,
            intento.id,
            alVolver,
            repositorio: repositorio,
          ),
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

  final RepositorioSimulacro repositorio;

  const _TarjetaSimulacro({
    required this.simulacro,
    required this.bloqueado,
    required this.alVolver,
    required this.repositorio,
  });

  @override
  State<_TarjetaSimulacro> createState() => _TarjetaSimulacroState();
}

class _TarjetaSimulacroState extends State<_TarjetaSimulacro> {
  late final _repo = widget.repositorio;
  bool _iniciando = false;

  Future<void> _empezar() async {
    setState(() => _iniciando = true);
    try {
      final intentoId = await _repo.iniciar(widget.simulacro.id);
      if (!mounted) return;
      await _abrirSesion(
        context,
        intentoId,
        widget.alVolver,
        repositorio: _repo,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("No se pudo empezar: $e")));
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
              style: context.textos.titleMedium!.copyWith(
                fontWeight: FontWeight.w700,
                color: context.esquema.onSurface,
              ),
            ),
            if (s.descripcion case final d? when d.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                d,
                style: context.textos.bodyMedium!.copyWith(
                  color: context.esquema.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 15,
                  color: context.esquema.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  "${s.duracionMinutos} minutos",
                  style: context.textos.bodySmall!.copyWith(
                    color: context.esquema.onSurfaceVariant,
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
  VoidCallback alVolver, {
  RepositorioSimulacro? repositorio,
}) async {
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          SesionSimulacro(intentoId: intentoId, repositorio: repositorio),
    ),
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

  /// Inyectable, por lo mismo que en [PantallaSimulacro].
  final RepositorioSimulacro? repositorio;

  const SesionSimulacro({super.key, required this.intentoId, this.repositorio});

  @override
  State<SesionSimulacro> createState() => _SesionSimulacroState();
}

enum _Guardado { guardando, guardado, error }

class _SesionSimulacroState extends State<SesionSimulacro> {
  late final _repo = widget.repositorio ?? RepositorioSimulacro();

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
      if (!mounted) return;
      if (intento == null) {
        setState(() => _errorCarga = "Este intento no existe o no es tuyo.");
        return;
      }
      // Ya cerrado: no hay sesión que retomar, al resultado.
      if (!intento.enCurso) {
        _irAlResultado(intento.id);
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
      setState(
        () => _restante = restante.isNegative ? Duration.zero : restante,
      );
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
          await Future<void>.delayed(
            Duration(milliseconds: 800 * (intento + 1)),
          );
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
        builder: (_) =>
            PantallaResultado(intentoId: intentoId, repositorio: _repo),
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
        body: Aviso(
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
        body: const Aviso(
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
            style: context.textos.bodyLarge,
          ),
          actions: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: pocoTiempo
                      ? context.colores.avisoContenedor
                      : context.esquema.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: pocoTiempo
                        ? context.colores.aviso
                        : context.esquema.outlineVariant,
                  ),
                ),
                child: Text(
                  _reloj == null ? "--:--" : formatearRestante(_restante),
                  style: context.textos.labelLarge!.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: pocoTiempo
                        ? context.colores.aviso
                        : context.esquema.onSurface,
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
              backgroundColor: context.esquema.outlineVariant,
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
                  style: context.textos.labelMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                    color: context.esquema.onSurfaceVariant,
                  ),
                ),
                Text(
                  "${_respuestas.length} respondidas",
                  style: context.textos.bodySmall!.copyWith(
                    color: context.esquema.onSurfaceVariant,
                  ),
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
            Text(
              "Ir a una pregunta",
              style: context.textos.labelMedium!.copyWith(
                fontWeight: FontWeight.w700,
                color: context.esquema.onSurfaceVariant,
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
    _Guardado.guardando => _Linea(
      icono: Icons.sync,
      texto: "Guardando…",
      color: context.esquema.onSurfaceVariant,
    ),
    _Guardado.guardado => _Linea(
      icono: Icons.cloud_done_outlined,
      texto: "Guardada",
      color: context.colores.exito,
    ),
    // `error`, no `primary`: esto es un fallo. Con el granate daban lo mismo
    // —la marca era el color del error— y al separarlos hay que decir cuál se
    // quería. Se quería este.
    _Guardado.error => _Linea(
      icono: Icons.cloud_off_outlined,
      texto: "No se pudo guardar. Vuelve a marcarla.",
      color: context.esquema.error,
    ),
  };
}

class _Linea extends StatelessWidget {
  final IconData icono;
  final String texto;
  final Color color;
  const _Linea({required this.icono, required this.texto, required this.color});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icono, size: 14, color: color),
      const SizedBox(width: 6),
      Text(texto, style: context.textos.bodySmall!.copyWith(color: color)),
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
        ? (
            context.esquema.errorContainer,
            context.esquema.onErrorContainer,
            context.esquema.error,
          )
        : respondida
        ? (
            context.esquema.primary,
            context.esquema.onPrimary,
            context.esquema.primary,
          )
        : (
            context.esquema.surfaceContainerLowest,
            context.esquema.onSurfaceVariant,
            context.esquema.outlineVariant,
          );

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
                color: esActual ? context.esquema.onSurface : borde,
                width: esActual ? 2 : 1,
              ),
            ),
            child: Text(
              "$numero",
              style: context.textos.labelMedium!.copyWith(
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
    color: marcada
        ? context.esquema.secondaryContainer
        : context.esquema.surfaceContainerLowest,
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      onTap: alPulsar,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: marcada
                ? context.esquema.primary
                : context.esquema.outlineVariant,
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
                color: marcada
                    ? context.esquema.primary
                    : context.esquema.surfaceContainerLow,
                shape: BoxShape.circle,
              ),
              child: Text(
                alternativa.letra.etiqueta,
                style: context.textos.labelMedium!.copyWith(
                  fontWeight: FontWeight.w700,
                  color: marcada
                      ? context.esquema.onPrimary
                      : context.esquema.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextoConFormulas(
                alternativa.texto,
                estilo: context.textos.bodyLarge!.copyWith(
                  color: context.esquema.onSurface,
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

  /// Inyectable, por lo mismo que en [PantallaSimulacro].
  final RepositorioSimulacro? repositorio;

  const PantallaResultado({
    super.key,
    required this.intentoId,
    this.repositorio,
  });

  @override
  State<PantallaResultado> createState() => _PantallaResultadoState();
}

class _PantallaResultadoState extends State<PantallaResultado> {
  late final _repo = widget.repositorio ?? RepositorioSimulacro();
  late final Future<(Intento, List<ResultadoPregunta>, PercentilSimulacro?)>
  _carga = _cargar();

  /// El intento primero —las otras dos lo necesitan—, y después las dos
  /// juntas.
  ///
  /// El desglose y el percentil no dependen entre sí, así que encadenarlos
  /// sumaba una latencia de más justo cuando el alumno acaba de terminar un
  /// examen de tres horas y quiere ver su nota. Misma corrección que ya
  /// recibieron Progreso, Inicio, Simulacro, Repaso y Adaptativa; esta era la
  /// última que quedaba en fila.
  Future<(Intento, List<ResultadoPregunta>, PercentilSimulacro?)>
  _cargar() async {
    final intento = await _repo.intento(widget.intentoId);
    // `ErrorSimulacro` y no una cadena suelta: lanzar un `String` deja fuera
    // a cualquier `on Exception catch`, y el tipo ya existe para esto.
    if (intento == null) {
      throw const ErrorSimulacro("Este intento no existe o no es tuyo.");
    }
    final resultados = await Future.wait([
      _repo.resultado(intento),
      _repo.percentil(intento.id),
    ]);
    return (
      intento,
      resultados[0] as List<ResultadoPregunta>,
      resultados[1] as PercentilSimulacro?,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Resultado")),
      body: FutureBuilder<(Intento, List<ResultadoPregunta>, PercentilSimulacro?)>(
        future: _carga,
        builder: (context, snap) {
          if (snap.hasError) {
            return Aviso(
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
                      style: context.textos.displayMedium!.copyWith(
                        fontWeight: FontWeight.w800,
                        color: context.esquema.primary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "${intento.correctas ?? 0} de "
                      "${intento.totalPreguntas ?? detalle.length} correctas"
                      "${sinResponder > 0 ? " · $sinResponder sin responder" : ""}",
                      style: context.textos.bodyMedium!.copyWith(
                        color: context.esquema.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              if (percentil != null) _Percentil(datos: percentil),
              const SizedBox(height: 24),
              Text(
                "POR CURSO",
                style: context.textos.labelSmall!.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: context.esquema.onSurfaceVariant,
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
      color: context.esquema.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.esquema.outlineVariant),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "FRENTE A OTROS POSTULANTES",
          style: context.textos.labelSmall!.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: context.esquema.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        if (datos.percentil == null)
          Text(
            "Todavía no hay suficientes intentos de este simulacro para "
            "comparar sin que la cifra engañe."
            "${datos.totalIntentos > 0 ? " Van ${datos.totalIntentos} además del tuyo." : ""}",
            style: context.textos.bodyMedium!.copyWith(
              color: context.esquema.onSurfaceVariant,
            ),
          )
        else ...[
          Text(
            "Estás por encima del ${datos.percentil} % de quienes lo rindieron.",
            style: context.textos.labelLarge!.copyWith(
              fontWeight: FontWeight.w600,
              color: context.esquema.onSurface,
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
            style: context.textos.bodySmall!.copyWith(
              color: context.esquema.onSurfaceVariant,
            ),
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
                  style: context.textos.labelLarge!.copyWith(
                    fontWeight: FontWeight.w600,
                    color: context.esquema.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                "$aciertos/${respuestas.length}",
                style: context.textos.bodySmall!.copyWith(
                  color: context.esquema.onSurfaceVariant,
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
              backgroundColor: context.esquema.outlineVariant,
              valueColor: AlwaysStoppedAnimation(
                proporcion >= 0.6
                    ? context.colores.exito
                    : context.esquema.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
