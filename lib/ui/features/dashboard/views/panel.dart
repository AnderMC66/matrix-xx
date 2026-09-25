import "package:flutter/material.dart";
import "package:matr_u/core/utils/fechas.dart";
import "package:matr_u/data/repositories/panel.dart";
import "package:matr_u/data/repositories/sesion.dart";
import "package:matr_u/domain/models/panel.dart";
import "package:matr_u/domain/models/preguntas.dart" show EtiquetaLetra;
import "package:matr_u/ui/core/theme/tema.dart";
import "package:matr_u/ui/core/vista_modelo.dart";
import "package:matr_u/ui/core/widgets/aviso.dart";
import "package:matr_u/ui/core/widgets/formula.dart";
import "package:matr_u/ui/features/dashboard/view_models/panel.dart";
import "package:matr_u/ui/features/practice/views/figura_red.dart";

/// `/panel` — portada del panel de docente/admin.
///
/// Réplica de `src/app/panel/page.tsx`. La cifra que manda es «sin auditar»,
/// no «publicadas»: ESTADO.md § 3.3 deja escrito que en la mayoría de
/// materias la clave la determinó quien programó la aplicación resolviendo,
/// no un profesor, y que conviene revisarlas antes de cobrar.
class PantallaPanel extends StatefulWidget {
  /// El modelo, inyectable. Su repositorio baja a las tres subpantallas.
  final ModeloPanel? modelo;

  const PantallaPanel({super.key, this.modelo});

  @override
  State<PantallaPanel> createState() => _PantallaPanelState();
}

class _PantallaPanelState extends State<PantallaPanel> {
  late final ModeloPanel _modelo = widget.modelo ?? ModeloPanel();

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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Panel")),
      body: ListenableBuilder(
        listenable: _modelo,
        builder: (context, _) => SegunEstado<DatosPanel>(
          estado: _modelo.datos,
          tituloDelFallo: "No se pudo abrir el panel",
          alReintentar: _modelo.cargar,
          cuandoListo: (datos) {
            final (rol, resumen) = datos;

            if (!esStaff(rol)) {
              // Igual que `exigirStaff()`: sin sesión o sin rol de staff, no
              // hay panel que enseñar.
              return const Aviso(
                icono: Icons.block,
                titulo: "No tienes acceso al panel",
                detalle:
                    "Esta sección es solo para docentes y administradores.",
              );
            }
            if (resumen == null) {
              return Aviso(
                icono: Icons.cloud_off_outlined,
                titulo: "No se pudo leer el resumen",
                accion: ("Reintentar", _modelo.cargar),
              );
            }

            return RefreshIndicator(
              onRefresh: _modelo.cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  Text(
                    "Revisión y soporte",
                    style: context.textos.headlineSmall!.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.esquema.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Lo que hace falta mirar antes de que lo vea un alumno.",
                    style: context.textos.bodyMedium!.copyWith(
                      color: context.esquema.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _TarjetaPanel(
                    titulo: "Sin auditar",
                    cifra: resumen.sinAuditar,
                    detalle: "Preguntas que ningún docente ha revisado todavía",
                    destacada: resumen.sinAuditar > 0,
                    onTap: () => _abrirRevision(context, "sin_auditar"),
                  ),
                  const SizedBox(height: 8),
                  _TarjetaPanel(
                    titulo: "Reportes abiertos",
                    cifra: resumen.reportesAbiertos,
                    detalle: "Errores que reportaron los alumnos",
                    destacada: resumen.reportesAbiertos > 0,
                    onTap: () => _abrirReportes(context),
                  ),
                  const SizedBox(height: 8),
                  _TarjetaPanel(
                    titulo: "En auditoría",
                    cifra: resumen.enAuditoria,
                    detalle: "Retiradas de circulación mientras se revisan",
                    onTap: () => _abrirRevision(context, "en_auditoria"),
                  ),
                  const SizedBox(height: 8),
                  _TarjetaPanel(
                    titulo: "Publicadas",
                    cifra: resumen.publicadas,
                    detalle: "Visibles para los alumnos ahora mismo",
                    onTap: () => _abrirRevision(context, "publicada"),
                  ),
                  const SizedBox(height: 8),
                  _TarjetaPanel(
                    titulo: "Retiradas",
                    cifra: resumen.retiradas,
                    detalle: "Fuera de circulación",
                    onTap: () => _abrirRevision(context, "retirada"),
                  ),
                  if (rol == Rol.admin) ...[
                    const SizedBox(height: 8),
                    _TarjetaPanel(
                      titulo: "Personas",
                      cifra: resumen.personas,
                      detalle: "Cuentas registradas y sus roles",
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PantallaPanelUsuarios(
                            repositorio: _modelo.repositorio,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _abrirRevision(BuildContext context, String filtro) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PantallaPanelRevision(
            filtroInicial: filtro,
            repositorio: _modelo.repositorio,
          ),
        ),
      );

  void _abrirReportes(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PantallaPanelReportes(repositorio: _modelo.repositorio),
    ),
  );
}

class _TarjetaPanel extends StatelessWidget {
  final String titulo;
  final int cifra;
  final String detalle;
  final bool destacada;
  final VoidCallback onTap;

  const _TarjetaPanel({
    required this.titulo,
    required this.cifra,
    required this.detalle,
    this.destacada = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // El relleno cambia con `destacada`, asi que el color del texto tiene que
    // cambiar con el: la tarjeta destacada se pintaba en `secondaryContainer`
    // —lila con la semilla indigo— y dejaba el titulo y el detalle en
    // `onSurfaceVariant`, un gris pensado para el fondo claro. Sobre el lila
    // se quedaba corto de contraste. Cada relleno con su pareja.
    final esquema = context.esquema;
    final fondo = destacada
        ? esquema.secondaryContainer
        : esquema.surfaceContainerLow;
    final encima = destacada ? esquema.onSecondaryContainer : esquema.onSurface;
    final encimaTenue = destacada
        ? esquema.onSecondaryContainer
        : esquema.onSurfaceVariant;

    return Material(
      color: fondo,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
              color: destacada ? esquema.primary : esquema.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: context.textos.bodyMedium!.copyWith(
                        color: encimaTenue,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "$cifra",
                      style: context.textos.displaySmall!.copyWith(
                        fontWeight: FontWeight.w700,
                        color: encima,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detalle,
                      style: context.textos.bodySmall!.copyWith(
                        color: encimaTenue,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: encimaTenue),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Revisión de preguntas
// ============================================================================

const _filtrosRevision = [
  ("sin_auditar", "Sin auditar"),
  ("en_auditoria", "En auditoría"),
  ("publicada", "Publicadas"),
  ("retirada", "Retiradas"),
  ("auditadas", "Ya revisadas"),
];

/// `/panel/revision` — la cola de preguntas.
///
/// La clave se muestra aquí y en ningún otro sitio de la app: para el resto
/// de pantallas está revocada por columna en Postgres.
class PantallaPanelRevision extends StatefulWidget {
  final String filtroInicial;

  /// Repositorio inyectable, igual que en [PantallaPanel]. Baja también a las
  /// fichas: si se quedara en la pantalla de arriba, la primera que
  /// construyera el suyo volvería a romper el montaje. En producción nadie lo
  /// pasa.
  final RepositorioPanel? repositorio;

  /// El modelo, inyectable.
  final ModeloPanelRevision? modelo;

  const PantallaPanelRevision({
    super.key,
    this.filtroInicial = "sin_auditar",
    this.repositorio,
    this.modelo,
  });

  @override
  State<PantallaPanelRevision> createState() => _PantallaPanelRevisionState();
}

class _PantallaPanelRevisionState extends State<PantallaPanelRevision> {
  late final ModeloPanelRevision _modelo =
      widget.modelo ??
      ModeloPanelRevision(
        filtroInicial: widget.filtroInicial,
        repositorio: widget.repositorio,
      );

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
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text("Revisión")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (valor, etiqueta) in _filtrosRevision)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(etiqueta),
                        selected: _modelo.filtro == valor,
                        onSelected: (_) => _modelo.cambiarFiltro(valor),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SegunEstado<List<PreguntaRevision>>(
              estado: _modelo.preguntas,
              tituloDelFallo: "No se pudieron cargar las preguntas",
              alReintentar: _modelo.cargar,
              cuandoListo: (preguntas) {
                if (preguntas.isEmpty) {
                  return const Aviso(
                    icono: Icons.check_circle_outline,
                    titulo: "Nada por aquí",
                    detalle: "No hay preguntas con este filtro.",
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: preguntas.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  // La `Key` por id es lo que impide que el estado de una
                  // ficha se quede pegado a la pregunta siguiente. Sin ella,
                  // Flutter reutiliza el `State` por posición: al dictaminar la
                  // primera, la lista se recarga, y el «Marcada como publicada»
                  // —y el `_enviando`— aparecían sobre la pregunta NUEVA que
                  // caía en ese hueco, que nadie había tocado. Es el mismo
                  // motivo por el que `_Reporte`, en practica.dart, lleva
                  // `ValueKey(_pregunta.codigo)`.
                  itemBuilder: (context, i) => _FichaPregunta(
                    key: ValueKey(preguntas[i].id),
                    pregunta: preguntas[i],
                    onDictaminada: _modelo.cargar,
                    repositorio: _modelo.repositorio,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _FichaPregunta extends StatefulWidget {
  final PreguntaRevision pregunta;
  final VoidCallback onDictaminada;
  final RepositorioPanel repositorio;

  const _FichaPregunta({
    super.key,
    required this.pregunta,
    required this.onDictaminada,
    required this.repositorio,
  });

  @override
  State<_FichaPregunta> createState() => _FichaPreguntaState();
}

class _FichaPreguntaState extends State<_FichaPregunta> {
  late final _repo = widget.repositorio;
  bool _enviando = false;
  String? _mensaje;

  Future<void> _dictaminar(String estado) async {
    setState(() {
      _enviando = true;
      _mensaje = null;
    });
    try {
      await _repo.dictaminarPregunta(
        preguntaId: widget.pregunta.id,
        estado: estado,
      );
      if (mounted) {
        setState(() => _mensaje = "Marcada como ${_etiquetaEstado(estado)}.");
      }
      widget.onDictaminada();
    } catch (e) {
      if (mounted) setState(() => _mensaje = "$e");
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pregunta;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.esquema.surfaceContainerLow,
        border: Border.all(color: context.esquema.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${p.curso} · ${p.subtema}",
                      style: context.textos.labelSmall!.copyWith(
                        color: context.esquema.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      "${p.codigo ?? "#${p.id}"} · ${p.dificultad} · ${p.estado}"
                      "${p.auditada ? " · ya auditada" : ""}",
                      style: context.textos.labelSmall!.copyWith(
                        color: context.esquema.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (p.reportesAbiertos > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: context.colores.avisoContenedor,
                    border: Border.all(color: context.colores.aviso),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "${p.reportesAbiertos} ${p.reportesAbiertos == 1 ? "reporte" : "reportes"}",
                    style: context.textos.labelSmall!.copyWith(
                      color: context.colores.aviso,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextoConFormulas(p.enunciadoMd, conMarcado: true),
          if (p.imagenUrl case final url?) ...[
            const SizedBox(height: 10),
            FiguraRed(url: url, alt: p.imagenAlt ?? "", grande: true),
          ],
          const SizedBox(height: 10),
          // Sin clave legible no se marca ninguna alternativa en verde, así que
          // sin este aviso la ficha se leería como una pregunta normal a la que
          // el docente no le encuentra la clave marcada. Decir que falta es lo
          // que evita que la audite a ciegas.
          if (p.clave == null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: context.colores.avisoContenedor,
                border: Border.all(color: context.colores.aviso),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "El servidor no devolvió la clave de esta pregunta. No la "
                "audites: no hay qué revisar.",
                style: context.textos.bodySmall!.copyWith(
                  color: context.colores.aviso,
                ),
              ),
            ),
          ],
          for (final a in p.alternativas)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: a.letra == p.clave
                      ? context.colores.exitoContenedor
                      : context.esquema.surfaceContainerLowest,
                  border: Border.all(
                    color: a.letra == p.clave
                        ? context.colores.exito
                        : context.esquema.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.letra.etiqueta,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: a.letra == p.clave
                            ? context.colores.exito
                            : context.esquema.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextoConFormulas(
                        a.textoMd,
                        conMarcado: true,
                        estilo: context.textos.bodyMedium!.copyWith(
                          color: context.esquema.onSurface,
                        ),
                      ),
                    ),
                    if (a.letra == p.clave)
                      Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Text(
                          "clave",
                          style: context.textos.labelSmall!.copyWith(
                            color: context.colores.exito,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (p.explicacionMd case final exp? when exp.isNotEmpty) ...[
            const SizedBox(height: 6),
            // **El `Material` no es decorativo: sin él la ficha no se pinta.**
            //
            // `ExpansionTile` lleva un `ListTile` dentro, y un `ListTile`
            // dibuja su fondo y sus ondas de pulsación sobre el `Material` más
            // cercano. Aquí el ancestro inmediato es el `Container` de la
            // ficha, que tiene color de fondo propio: Flutter lo detecta y
            // lanza una aserción en depuración —«ListTile background color or
            // ink splashes may be invisible»— que deja la ficha entera en una
            // caja roja.
            //
            // `MaterialType.transparency` es la salida que recomienda el
            // propio framework: da al `ListTile` un `Material` donde pintar sin
            // añadir ningún color, así que la ficha se ve igual que antes.
            //
            // Solo salta cuando la pregunta trae explicación, que es el caso
            // normal de una pregunta escrita. No lo vio nadie porque esta
            // pantalla no se podía montar en un test hasta la auditoría del
            // 2026-09-16: es el mismo patrón que escondía el desbordamiento de
            // Progreso.
            Material(
              type: MaterialType.transparency,
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  "Explicación",
                  style: context.textos.bodyMedium!.copyWith(
                    color: context.esquema.onSurfaceVariant,
                  ),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextoConFormulas(
                      exp,
                      conMarcado: true,
                      estilo: context.textos.bodyMedium!.copyWith(
                        color: context.esquema.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _BotonEstado(
                texto: "Correcta, publicar",
                color: context.colores.exito,
                activo: p.estado == "publicada",
                deshabilitado: _enviando,
                onPressed: () => _dictaminar("publicada"),
              ),
              _BotonEstado(
                texto: "Dudosa, sacar de circulación",
                color: context.colores.aviso,
                activo: p.estado == "en_auditoria",
                deshabilitado: _enviando,
                onPressed: () => _dictaminar("en_auditoria"),
              ),
              _BotonEstado(
                texto: "Retirar",
                color: context.esquema.onSurfaceVariant,
                activo: p.estado == "retirada",
                deshabilitado: _enviando,
                onPressed: () => _dictaminar("retirada"),
              ),
            ],
          ),
          if (_mensaje case final m?) ...[
            const SizedBox(height: 6),
            Text(
              m,
              style: context.textos.bodySmall!.copyWith(
                color: context.esquema.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _etiquetaEstado(String estado) => switch (estado) {
  "borrador" => "borrador",
  "en_auditoria" => "en auditoría",
  "publicada" => "publicada",
  "retirada" => "retirada",
  _ => estado,
};

class _BotonEstado extends StatelessWidget {
  final String texto;
  final Color color;
  final bool activo;
  final bool deshabilitado;
  final VoidCallback onPressed;

  const _BotonEstado({
    required this.texto,
    required this.color,
    required this.activo,
    required this.deshabilitado,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: deshabilitado || activo ? null : onPressed,
    style: OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide(color: color),
      visualDensity: VisualDensity.compact,
      textStyle: context.textos.bodySmall,
    ),
    child: Text(activo ? "$texto ·" : texto),
  );
}

// ============================================================================
// Reportes
// ============================================================================

const _filtrosReporte = [
  ("abierto", "Abiertos"),
  ("en_revision", "En revisión"),
  ("aceptado", "Aceptados"),
  ("rechazado", "Rechazados"),
  ("todos", "Todos"),
];

/// `/panel/reportes` — bandeja de errores reportados por los alumnos.
class PantallaPanelReportes extends StatefulWidget {
  /// Repositorio inyectable, igual que en [PantallaPanel]. Baja también a las
  /// fichas: si se quedara en la pantalla de arriba, la primera que
  /// construyera el suyo volvería a romper el montaje. En producción nadie lo
  /// pasa.
  final RepositorioPanel? repositorio;

  /// El modelo, inyectable.
  final ModeloPanelReportes? modelo;

  const PantallaPanelReportes({super.key, this.repositorio, this.modelo});

  @override
  State<PantallaPanelReportes> createState() => _PantallaPanelReportesState();
}

class _PantallaPanelReportesState extends State<PantallaPanelReportes> {
  late final ModeloPanelReportes _modelo =
      widget.modelo ?? ModeloPanelReportes(repositorio: widget.repositorio);

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
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text("Reportes")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (valor, etiqueta) in _filtrosReporte)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(etiqueta),
                        selected: _modelo.filtro == valor,
                        onSelected: (_) => _modelo.cambiarFiltro(valor),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SegunEstado<List<ReporteStaff>>(
              estado: _modelo.reportes,
              tituloDelFallo: "No se pudieron cargar los reportes",
              alReintentar: _modelo.cargar,
              cuandoListo: (reportes) {
                if (reportes.isEmpty) {
                  return const Aviso(
                    icono: Icons.inbox_outlined,
                    titulo: "Nada por aquí",
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: reportes.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _FichaReporte(
                    key: ValueKey(reportes[i].id),
                    reporte: reportes[i],
                    onDictaminado: _modelo.cargar,
                    repositorio: _modelo.repositorio,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _FichaReporte extends StatefulWidget {
  final ReporteStaff reporte;
  final VoidCallback onDictaminado;
  final RepositorioPanel repositorio;

  const _FichaReporte({
    super.key,
    required this.reporte,
    required this.onDictaminado,
    required this.repositorio,
  });

  @override
  State<_FichaReporte> createState() => _FichaReporteState();
}

class _FichaReporteState extends State<_FichaReporte> {
  late final _repo = widget.repositorio;
  bool _enviando = false;
  String? _mensaje;

  Future<void> _dictaminar(String estado) async {
    setState(() {
      _enviando = true;
      _mensaje = null;
    });
    try {
      await _repo.dictaminarReporte(
        reporteId: widget.reporte.id,
        estado: estado,
      );
      if (mounted) setState(() => _mensaje = "Reporte actualizado.");
      widget.onDictaminado();
    } catch (e) {
      if (mounted) setState(() => _mensaje = "$e");
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reporte;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.esquema.surfaceContainerLow,
        border: Border.all(color: context.esquema.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "${r.preguntaCodigo ?? "pregunta #${r.preguntaId}"} · "
            "${fechaDiaMes(r.creadoEn)} · ${r.estado}",
            style: context.textos.labelSmall!.copyWith(
              color: context.esquema.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            r.motivo,
            style: context.textos.labelLarge!.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (r.detalle case final d? when d.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              d,
              style: context.textos.bodyMedium!.copyWith(
                color: context.esquema.onSurfaceVariant,
              ),
            ),
          ],
          if (r.preguntaEnunciado case final e? when e.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.esquema.surfaceContainerLowest,
                border: Border.all(color: context.esquema.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                e,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: context.textos.bodySmall!.copyWith(
                  color: context.esquema.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _BotonEstado(
                texto: "Lo estoy mirando",
                color: context.esquema.onSurfaceVariant,
                activo: r.estado == "en_revision",
                deshabilitado: _enviando,
                onPressed: () => _dictaminar("en_revision"),
              ),
              _BotonEstado(
                texto: "Tenía razón",
                color: context.colores.exito,
                activo: r.estado == "aceptado",
                deshabilitado: _enviando,
                onPressed: () => _dictaminar("aceptado"),
              ),
              _BotonEstado(
                texto: "Sin error",
                color: context.esquema.onSurfaceVariant,
                activo: r.estado == "rechazado",
                deshabilitado: _enviando,
                onPressed: () => _dictaminar("rechazado"),
              ),
            ],
          ),
          if (_mensaje case final m?) ...[
            const SizedBox(height: 6),
            Text(
              m,
              style: context.textos.bodySmall!.copyWith(
                color: context.esquema.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// Personas / roles
// ============================================================================

/// `/panel/usuarios` — solo para admin: `personas_del_panel` comprueba
/// `es_admin()` por dentro y le devolvería una lista vacía a un docente.
class PantallaPanelUsuarios extends StatefulWidget {
  /// Repositorio inyectable, igual que en [PantallaPanel]. Baja también a las
  /// fichas: si se quedara en la pantalla de arriba, la primera que
  /// construyera el suyo volvería a romper el montaje. En producción nadie lo
  /// pasa.
  final RepositorioPanel? repositorio;
  final Sesion? sesion;

  /// El modelo, inyectable.
  final ModeloPanelUsuarios? modelo;

  const PantallaPanelUsuarios({
    super.key,
    this.repositorio,
    this.sesion,
    this.modelo,
  });

  @override
  State<PantallaPanelUsuarios> createState() => _PantallaPanelUsuariosState();
}

class _PantallaPanelUsuariosState extends State<PantallaPanelUsuarios> {
  late final ModeloPanelUsuarios _modelo =
      widget.modelo ??
      ModeloPanelUsuarios(
        repositorio: widget.repositorio,
        sesion: widget.sesion,
      );

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
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text("Personas")),
      body: SegunEstado<List<Persona>>(
        estado: _modelo.personas,
        tituloDelFallo: "No se pudieron cargar las personas",
        alReintentar: _modelo.cargar,
        cuandoListo: (personas) {
          if (personas.isEmpty) {
            return const Aviso(
              icono: Icons.people_outline,
              titulo: "No hay cuentas registradas",
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: personas.length + 1,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    "Un docente puede revisar preguntas y resolver reportes. Un "
                    "admin puede además cambiar roles. El último administrador "
                    "no se puede degradar.",
                    style: context.textos.bodySmall!.copyWith(
                      color: context.esquema.onSurfaceVariant,
                    ),
                  ),
                );
              }
              final p = personas[i - 1];
              return _FilaPersona(
                key: ValueKey(p.id),
                persona: p,
                esUnoMismo: p.id == _modelo.idPropio,
                repositorio: _modelo.repositorio,
              );
            },
          );
        },
      ),
    ),
  );
}

class _FilaPersona extends StatefulWidget {
  final Persona persona;
  final bool esUnoMismo;
  final RepositorioPanel repositorio;

  const _FilaPersona({
    super.key,
    required this.persona,
    required this.esUnoMismo,
    required this.repositorio,
  });

  @override
  State<_FilaPersona> createState() => _FilaPersonaState();
}

class _FilaPersonaState extends State<_FilaPersona> {
  late final _repo = widget.repositorio;

  /// Copia local del rol, para que el desplegable responda antes de que el
  /// RPC conteste. Al ser `late` se inicializa UNA vez, así que hay que
  /// resincronizarla en [didUpdateWidget]: con la `Key` por id esto no
  /// debería dispararse nunca, pero una copia que se desincroniza en silencio
  /// enseñaría el rol de una persona sobre el nombre de otra, y eso en la
  /// pantalla que reparte permisos no se puede dejar al aire.
  late Rol _rol = widget.persona.rol;

  bool _guardando = false;
  String? _mensaje;

  @override
  void didUpdateWidget(_FilaPersona anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.persona.id != widget.persona.id ||
        anterior.persona.rol != widget.persona.rol) {
      _rol = widget.persona.rol;
      _mensaje = null;
    }
  }

  Future<void> _cambiar(Rol nuevo) async {
    final anterior = _rol;
    setState(() {
      _rol = nuevo;
      _guardando = true;
      _mensaje = null;
    });
    try {
      await _repo.cambiarRol(perfilId: widget.persona.id, rol: nuevo);
      if (mounted) setState(() => _mensaje = "Rol cambiado.");
    } catch (e) {
      if (mounted) {
        setState(() {
          _rol = anterior; // el RPC lo rechazó (p. ej. último admin): revertir
          _mensaje = "$e";
        });
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.persona;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.nombre.isEmpty ? "—" : p.nombre,
                  style: context.textos.labelLarge!.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  p.correo,
                  style: context.textos.bodySmall!.copyWith(
                    color: context.esquema.onSurfaceVariant,
                  ),
                ),
                Text(
                  p.plan,
                  style: context.textos.bodySmall!.copyWith(
                    color: context.esquema.onSurfaceVariant,
                  ),
                ),
                if (_mensaje case final m?)
                  Text(
                    m,
                    style: context.textos.labelSmall!.copyWith(
                      color: context.esquema.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              DropdownButton<Rol>(
                value: _rol,
                underline: const SizedBox.shrink(),
                onChanged: _guardando
                    ? null
                    : (v) => v == null ? null : _cambiar(v),
                items: const [
                  DropdownMenuItem(value: Rol.alumno, child: Text("alumno")),
                  DropdownMenuItem(value: Rol.docente, child: Text("docente")),
                  DropdownMenuItem(value: Rol.admin, child: Text("admin")),
                ],
              ),
              if (widget.esUnoMismo)
                Text(
                  "(eres tú)",
                  style: context.textos.labelSmall!.copyWith(
                    color: context.esquema.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
