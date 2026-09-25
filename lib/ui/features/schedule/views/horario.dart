import "package:flutter/material.dart";
import "package:matr_u/domain/models/horario.dart";
import "package:matr_u/domain/models/temario.dart";
import "package:matr_u/ui/core/theme/tema.dart";
import "package:matr_u/ui/core/widgets/aviso.dart";
import "package:matr_u/ui/features/schedule/view_models/horario.dart";

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
  final ModeloHorario? modelo;

  const HorarioConBarra({super.key, this.modelo});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("Horario de estudio")),
    body: PantallaHorario(modelo: modelo),
  );
}

class PantallaHorario extends StatefulWidget {
  /// El modelo de vista, inyectable.
  ///
  /// **No es ceremonia: es lo unico que separa a esta pantalla de poder
  /// probarse.** Los repositorios que el modelo usa resuelven
  /// `Supabase.instance.client`, asi que construirlos fuera de una app con
  /// Supabase inicializado lanza «You must initialize the supabase instance»
  /// antes de pintar nada.
  ///
  /// En produccion nadie lo pasa y se construye aqui, igual que antes.
  final ModeloHorario? modelo;

  const PantallaHorario({super.key, this.modelo});

  @override
  State<PantallaHorario> createState() => _PantallaHorarioState();
}

class _PantallaHorarioState extends State<PantallaHorario> {
  late final ModeloHorario _modelo = widget.modelo ?? ModeloHorario();

  @override
  void initState() {
    super.initState();
    _modelo.cargar();
  }

  @override
  void dispose() {
    _modelo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _modelo,
    builder: (context, _) => _contenido(context),
  );

  Widget _contenido(BuildContext context) {
    if (!_modelo.hayCuenta) {
      return const Aviso(
        icono: Icons.lock_outline,
        titulo: "El horario necesita tu cuenta",
        detalle:
            "Se guarda en el servidor para que sobreviva a cambiar de "
            "dispositivo.\n\nUsa el botón de entrar, arriba a la derecha.",
      );
    }
    if (_modelo.errorCarga != null) {
      // Con «Reintentar», como el resto de la app: sin él, la única salida de
      // un fallo de red era salir de la pantalla y volver a entrar.
      return Aviso(
        icono: Icons.cloud_off_outlined,
        titulo: "No se pudo cargar el horario",
        detalle: _modelo.errorCarga!,
        accion: ("Reintentar", _modelo.cargar),
      );
    }
    if (_modelo.cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    final porDia = <int, List<BloqueHorario>>{};
    for (final b in _modelo.horario) {
      porDia.putIfAbsent(b.diaSemana, () => []).add(b);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text(
          "Cuándo estudias cada curso",
          style: context.textos.headlineSmall!.copyWith(
            fontWeight: FontWeight.w700,
            color: context.esquema.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "Programa un bloque semanal por curso. Mientras tengas la app "
          "abierta a esa hora, te avisamos.",
          style: context.textos.bodyMedium!.copyWith(
            color: context.esquema.onSurfaceVariant,
          ),
        ),
        if (_modelo.proximoAviso case final a?) ...[
          const SizedBox(height: 16),
          _AvisoProximo(bloque: a.bloque, faltan: a.faltan),
        ],
        const SizedBox(height: 20),
        _FormularioBloque(
          cursos: _modelo.cursos,
          cursoElegido: _modelo.cursoElegido,
          dia: _modelo.dia,
          hora: _modelo.hora,
          duracion: _modelo.duracion,
          guardando: _modelo.guardando,
          error: _modelo.error,
          onCurso: _modelo.elegirCurso,
          onDia: _modelo.elegirDia,
          onHora: _modelo.elegirHora,
          onDuracion: _modelo.elegirDuracion,
          onAgregar: _modelo.agregar,
        ),
        const SizedBox(height: 26),
        if (_modelo.horario.isEmpty)
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
                eliminandoId: _modelo.eliminandoId,
                onEliminar: _modelo.eliminar,
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
        color: context.esquema.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.notifications_active_outlined,
            color: context.esquema.primary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: context.esquema.primary,
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
      color: context.esquema.surfaceContainerLow,
      border: Border.all(color: context.esquema.outlineVariant),
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
          Text(
            e,
            style: context.textos.bodySmall!.copyWith(
              color: context.colores.aviso,
            ),
          ),
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
          style: context.textos.labelSmall!.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: context.esquema.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: context.esquema.outlineVariant),
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
                              style: context.textos.labelLarge!.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "${formatearHora(b.horaInicio)} · ${b.duracionMinutos} min",
                              style: context.textos.bodySmall!.copyWith(
                                color: context.esquema.onSurfaceVariant,
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
                          foregroundColor: context.colores.aviso,
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
