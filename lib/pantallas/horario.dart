import "dart:async";

import "package:flutter/material.dart";

import "../datos/horario.dart";
import "../datos/sesion.dart";
import "../datos/temario.dart";
import "../tema.dart";
import "../widgets/aviso.dart";

const _duraciones = [30, 45, 60, 90, 120];

/// `/horario` — cuándo estudias cada curso.
///
/// Réplica de `src/app/horario/page.tsx` + `gestor-horario.tsx`. Lo que se
/// deja fuera a propósito es la notificación del sistema
/// (`notificador-horario.tsx` pide permiso de `Notification` del navegador):
/// en la web «solo funciona con la pestaña abierta: no hay Service Worker ni
/// Push» — el mismo límite exacto que tiene esta pantalla, que avisa
/// mientras está abierta y nada más. Portar el aviso persistente exigiría
/// notificaciones locales del sistema (un plugin nuevo, permisos nuevos), y
/// el alcance de la web no lo pide: ni ahí sobrevive a cerrar la pestaña.
/// La misma pantalla, con su propia barra, para cuando se empuja como ruta.
///
/// Estaba duplicado palabra por palabra en `inicio.dart` y en `progreso.dart`,
/// que son los dos sitios desde donde se llega al horario.
class HorarioConBarra extends StatelessWidget {
  const HorarioConBarra({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("Horario de estudio")),
    body: const PantallaHorario(),
  );
}

class PantallaHorario extends StatefulWidget {
  const PantallaHorario({super.key});

  @override
  State<PantallaHorario> createState() => _PantallaHorarioState();
}

class _PantallaHorarioState extends State<PantallaHorario> {
  final _repo = RepositorioHorario();
  final _sesion = Sesion();

  List<Curso> _cursos = const [];
  List<BloqueHorario> _horario = const [];
  bool _cargando = true;
  String? _errorCarga;

  String? _cursoElegido;
  int _dia = 1;
  TimeOfDay _hora = const TimeOfDay(hour: 17, minute: 0);
  int _duracion = 60;

  bool _guardando = false;
  int? _eliminandoId;
  String? _error;

  Timer? _reloj;
  ({BloqueHorario bloque, Duration faltan})? _proximoAviso;

  @override
  void initState() {
    super.initState();
    if (_sesion.hayCuenta) _cargar();
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final temario = await RepositorioTemario().cargar();
      final horario = await _repo.obtener();
      if (!mounted) return;
      setState(() {
        _cursos = temario.cursos;
        _cursoElegido = _cursos.firstOrNull?.codigo;
        _horario = horario;
        _cargando = false;
      });
      _arrancarReloj();
    } catch (e) {
      if (mounted) setState(() => _errorCarga = "$e");
    }
  }

  /// Revisa cada 30 segundos si algún bloque empieza dentro de los próximos
  /// 5 minutos, mientras esta pantalla esté abierta — exactamente lo que
  /// hacía el temporizador de `notificador-horario.tsx` en el navegador.
  void _arrancarReloj() {
    void revisar() {
      final proximo = proximoBloque(_horario, DateTime.now());
      if (proximo == null) {
        if (mounted) setState(() => _proximoAviso = null);
        return;
      }
      final faltan = proximo.cuando.difference(DateTime.now());
      if (mounted) {
        setState(
          () => _proximoAviso = faltan <= const Duration(minutes: 5)
              ? (bloque: proximo.bloque, faltan: faltan)
              : null,
        );
      }
    }

    revisar();
    _reloj = Timer.periodic(const Duration(seconds: 30), (_) => revisar());
  }

  Future<void> _agregar() async {
    final codigo = _cursoElegido;
    if (codigo == null) return;

    setState(() {
      _guardando = true;
      _error = null;
    });

    final horaTexto =
        "${_hora.hour.toString().padLeft(2, "0")}:${_hora.minute.toString().padLeft(2, "0")}:00";

    try {
      final id = await _repo.crear(
        cursoCodigo: codigo,
        diaSemana: _dia,
        horaInicio: horaTexto,
        duracionMinutos: _duracion,
      );
      final curso = _cursos.firstWhere((c) => c.codigo == codigo);
      if (!mounted) return;
      setState(() {
        _horario =
            [
              ..._horario,
              BloqueHorario(
                // El id REAL que devolvió Postgres. Antes aquí iba uno
                // negativo «provisional hasta la próxima recarga», y esa
                // recarga no existe: el horario solo se carga en `initState`.
                // Con el id inventado, borrar un bloque recién creado mandaba
                // el `delete` contra una fila que no existe —PostgREST no se
                // queja— así que desaparecía de la pantalla y seguía en la
                // base hasta la siguiente visita.
                id: id,
                cursoCodigo: curso.codigo,
                cursoNombre: curso.nombre,
                cursoSlug: curso.slug,
                diaSemana: _dia,
                horaInicio: horaTexto,
                duracionMinutos: _duracion,
              ),
            ]..sort(
              (a, b) => a.diaSemana != b.diaSemana
                  ? a.diaSemana.compareTo(b.diaSemana)
                  : a.horaInicio.compareTo(b.horaInicio),
            );
      });
    } on ErrorHorario catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (e) {
      if (mounted) setState(() => _error = "No se pudo guardar el bloque. $e");
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _eliminar(BloqueHorario b) async {
    setState(() {
      _error = null;
      _eliminandoId = b.id;
    });
    try {
      await _repo.eliminar(b.id);
      if (mounted) {
        setState(() => _horario = _horario.where((x) => x.id != b.id).toList());
      }
    } catch (e) {
      if (mounted) setState(() => _error = "No se pudo eliminar el bloque. $e");
    } finally {
      if (mounted) setState(() => _eliminandoId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_sesion.hayCuenta) {
      return const Aviso(
        icono: Icons.lock_outline,
        titulo: "El horario necesita tu cuenta",
        detalle:
            "Se guarda en el servidor para que sobreviva a cambiar de "
            "dispositivo.\n\nUsa el botón de entrar, arriba a la derecha.",
      );
    }
    if (_errorCarga != null) {
      return Aviso(
        icono: Icons.cloud_off_outlined,
        titulo: "No se pudo cargar el horario",
        detalle: _errorCarga!,
      );
    }
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    final porDia = <int, List<BloqueHorario>>{};
    for (final b in _horario) {
      porDia.putIfAbsent(b.diaSemana, () => []).add(b);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        const Text(
          "Cuándo estudias cada curso",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Paleta.texto,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          "Programa un bloque semanal por curso. Mientras tengas la app "
          "abierta a esa hora, te avisamos.",
          style: TextStyle(fontSize: 13, color: Paleta.textoSuave, height: 1.5),
        ),
        if (_proximoAviso case final a?) ...[
          const SizedBox(height: 16),
          _AvisoProximo(bloque: a.bloque, faltan: a.faltan),
        ],
        const SizedBox(height: 20),
        _FormularioBloque(
          cursos: _cursos,
          cursoElegido: _cursoElegido,
          dia: _dia,
          hora: _hora,
          duracion: _duracion,
          guardando: _guardando,
          error: _error,
          onCurso: (v) => setState(() => _cursoElegido = v),
          onDia: (v) => setState(() => _dia = v),
          onHora: (v) => setState(() => _hora = v),
          onDuracion: (v) => setState(() => _duracion = v),
          onAgregar: _agregar,
        ),
        const SizedBox(height: 26),
        if (_horario.isEmpty)
          const Aviso(
            icono: Icons.calendar_month_outlined,
            titulo: "Todavía no programaste ningún bloque",
            compacto: true,
          )
        else
          for (final (dia, nombre) in diasSemana.indexed)
            if (porDia[dia] case final bloques? when bloques.isNotEmpty)
              _BloqueDia(
                nombre: nombre,
                bloques: bloques,
                eliminandoId: _eliminandoId,
                onEliminar: _eliminar,
              ),
      ],
    );
  }
}

class _AvisoProximo extends StatelessWidget {
  final BloqueHorario bloque;
  final Duration faltan;
  const _AvisoProximo({required this.bloque, required this.faltan});

  @override
  Widget build(BuildContext context) {
    final minutos = faltan.inMinutes.clamp(0, 5);
    final texto = minutos <= 0
        ? "Toca estudiar ${bloque.cursoNombre} ahora."
        : "Toca estudiar ${bloque.cursoNombre} en $minutos "
              "${minutos == 1 ? "minuto" : "minutos"}.";

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Paleta.acentoSuave,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.notifications_active_outlined,
            color: Paleta.acento,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Paleta.acento,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormularioBloque extends StatelessWidget {
  final List<Curso> cursos;
  final String? cursoElegido;
  final int dia;
  final TimeOfDay hora;
  final int duracion;
  final bool guardando;
  final String? error;
  final ValueChanged<String?> onCurso;
  final ValueChanged<int> onDia;
  final ValueChanged<TimeOfDay> onHora;
  final ValueChanged<int> onDuracion;
  final VoidCallback onAgregar;

  const _FormularioBloque({
    required this.cursos,
    required this.cursoElegido,
    required this.dia,
    required this.hora,
    required this.duracion,
    required this.guardando,
    required this.error,
    required this.onCurso,
    required this.onDia,
    required this.onHora,
    required this.onDuracion,
    required this.onAgregar,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Paleta.superficie,
      border: Border.all(color: Paleta.borde),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Agregar bloque",
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: cursoElegido,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: "Curso",
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final c in cursos)
              DropdownMenuItem(
                value: c.codigo,
                child: Text(c.nombre, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onCurso,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: dia,
                decoration: const InputDecoration(
                  labelText: "Día",
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final (i, nombre) in diasSemana.indexed)
                    DropdownMenuItem(value: i, child: Text(nombre)),
                ],
                onChanged: (v) => onDia(v ?? dia),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: () async {
                  final elegida = await showTimePicker(
                    context: context,
                    initialTime: hora,
                  );
                  if (elegida != null) onHora(elegida);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: "Hora",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  child: Text(hora.format(context)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          initialValue: duracion,
          decoration: const InputDecoration(
            labelText: "Duración",
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final min in _duraciones)
              DropdownMenuItem(value: min, child: Text("$min min")),
          ],
          onChanged: (v) => onDuracion(v ?? duracion),
        ),
        if (error case final e?) ...[
          const SizedBox(height: 10),
          Text(e, style: const TextStyle(color: Paleta.aviso, fontSize: 12.5)),
        ],
        const SizedBox(height: 14),
        FilledButton(
          onPressed: guardando || cursos.isEmpty ? null : onAgregar,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
          child: Text(guardando ? "Guardando…" : "Agregar al horario"),
        ),
      ],
    ),
  );
}

class _BloqueDia extends StatelessWidget {
  final String nombre;
  final List<BloqueHorario> bloques;
  final int? eliminandoId;
  final void Function(BloqueHorario) onEliminar;

  const _BloqueDia({
    required this.nombre,
    required this.bloques,
    required this.eliminandoId,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          nombre.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: Paleta.textoSuave,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Paleta.borde),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              for (final (i, b) in bloques.indexed) ...[
                if (i > 0) const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              b.cursoNombre,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "${formatearHora(b.horaInicio)} · ${b.duracionMinutos} min",
                              style: const TextStyle(
                                fontSize: 12,
                                color: Paleta.textoTenue,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: eliminandoId == b.id
                            ? null
                            : () => onEliminar(b),
                        style: TextButton.styleFrom(
                          foregroundColor: Paleta.aviso,
                        ),
                        child: Text(
                          eliminandoId == b.id ? "Quitando…" : "Quitar",
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}
