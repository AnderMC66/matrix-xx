import "package:flutter/material.dart";

import "../datos/panel.dart";
import "../datos/preguntas.dart" show EtiquetaLetra;
import "../datos/sesion.dart";
import "../matematicas/formula.dart";
import "../tema.dart";
import "../widgets/aviso.dart";
import "figura_red.dart";

/// `/panel` — portada del panel de docente/admin.
///
/// Réplica de `src/app/panel/page.tsx`. La cifra que manda es «sin auditar»,
/// no «publicadas»: ESTADO.md § 3.3 deja escrito que en la mayoría de
/// materias la clave la determinó quien programó la aplicación resolviendo,
/// no un profesor, y que conviene revisarlas antes de cobrar.
class PantallaPanel extends StatefulWidget {
  const PantallaPanel({super.key});

  @override
  State<PantallaPanel> createState() => _PantallaPanelState();
}

class _PantallaPanelState extends State<PantallaPanel> {
  final _repo = RepositorioPanel();
  Future<(Rol?, ResumenPanel?)>? _carga;

  @override
  void initState() {
    super.initState();
    _recargar();
  }

  void _recargar() => setState(() => _carga = _pedir());

  Future<(Rol?, ResumenPanel?)> _pedir() async {
    final rol = await _repo.rolActual();
    if (!esStaff(rol)) return (rol, null);
    return (rol, await _repo.resumen());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Panel")),
      body: FutureBuilder<(Rol?, ResumenPanel?)>(
        future: _carga,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (rol, resumen) = snap.data!;

          if (!esStaff(rol)) {
            // Igual que `exigirStaff()`: sin sesión o sin rol de staff, no
            // hay panel que enseñar.
            return const Aviso(
              icono: Icons.block,
              titulo: "No tienes acceso al panel",
              detalle: "Esta sección es solo para docentes y administradores.",
            );
          }
          if (resumen == null) {
            return Aviso(
              icono: Icons.cloud_off_outlined,
              titulo: "No se pudo leer el resumen",
              accion: ("Reintentar", _recargar),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _recargar(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                const Text(
                  "Revisión y soporte",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Paleta.texto,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  "Lo que hace falta mirar antes de que lo vea un alumno.",
                  style: TextStyle(fontSize: 13, color: Paleta.textoSuave),
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
                        builder: (_) => const PantallaPanelUsuarios(),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _abrirRevision(BuildContext context, String filtro) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PantallaPanelRevision(filtroInicial: filtro),
        ),
      );

  void _abrirReportes(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const PantallaPanelReportes()));
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
  Widget build(BuildContext context) => Material(
    color: destacada ? Paleta.acentoSuave : Paleta.superficie,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: destacada ? Paleta.acento : Paleta.borde),
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
                    style: const TextStyle(
                      fontSize: 13,
                      color: Paleta.textoSuave,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "$cifra",
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: Paleta.texto,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detalle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Paleta.textoTenue,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Paleta.textoTenue),
          ],
        ),
      ),
    ),
  );
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
  const PantallaPanelRevision({super.key, this.filtroInicial = "sin_auditar"});

  @override
  State<PantallaPanelRevision> createState() => _PantallaPanelRevisionState();
}

class _PantallaPanelRevisionState extends State<PantallaPanelRevision> {
  final _repo = RepositorioPanel();
  late String _filtro = widget.filtroInicial;
  Future<List<PreguntaRevision>>? _carga;

  @override
  void initState() {
    super.initState();
    _recargar();
  }

  void _recargar() =>
      setState(() => _carga = _repo.paraRevision(filtro: _filtro));

  @override
  Widget build(BuildContext context) => Scaffold(
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
                      selected: _filtro == valor,
                      onSelected: (_) {
                        if (_filtro == valor) return;
                        _filtro = valor;
                        _recargar();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<PreguntaRevision>>(
            future: _carga,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final preguntas = snap.data!;
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
                itemBuilder: (context, i) => _FichaPregunta(
                  pregunta: preguntas[i],
                  onDictaminada: _recargar,
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _FichaPregunta extends StatefulWidget {
  final PreguntaRevision pregunta;
  final VoidCallback onDictaminada;
  const _FichaPregunta({required this.pregunta, required this.onDictaminada});

  @override
  State<_FichaPregunta> createState() => _FichaPreguntaState();
}

class _FichaPreguntaState extends State<_FichaPregunta> {
  final _repo = RepositorioPanel();
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
        color: Paleta.superficie,
        border: Border.all(color: Paleta.borde),
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
                      style: const TextStyle(
                        fontSize: 11,
                        color: Paleta.textoTenue,
                      ),
                    ),
                    Text(
                      "${p.codigo ?? "#${p.id}"} · ${p.dificultad} · ${p.estado}"
                      "${p.auditada ? " · ya auditada" : ""}",
                      style: const TextStyle(
                        fontSize: 11,
                        color: Paleta.textoTenue,
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
                    color: Paleta.avisoSuave,
                    border: Border.all(color: Paleta.aviso),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "${p.reportesAbiertos} ${p.reportesAbiertos == 1 ? "reporte" : "reportes"}",
                    style: const TextStyle(fontSize: 10.5, color: Paleta.aviso),
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
          for (final a in p.alternativas)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: a.letra == p.clave
                      ? Paleta.exitoSuave
                      : Paleta.superficieAlta,
                  border: Border.all(
                    color: a.letra == p.clave ? Paleta.exito : Paleta.borde,
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
                            ? Paleta.exito
                            : Paleta.textoTenue,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextoConFormulas(
                        a.textoMd,
                        conMarcado: true,
                        estilo: const TextStyle(
                          fontSize: 13.5,
                          color: Paleta.texto,
                          height: 1.4,
                        ),
                      ),
                    ),
                    if (a.letra == p.clave)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Text(
                          "clave",
                          style: TextStyle(fontSize: 10.5, color: Paleta.exito),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (p.explicacionMd case final exp? when exp.isNotEmpty) ...[
            const SizedBox(height: 6),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(
                "Explicación",
                style: TextStyle(fontSize: 13, color: Paleta.textoSuave),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextoConFormulas(
                    exp,
                    conMarcado: true,
                    estilo: const TextStyle(
                      fontSize: 13,
                      color: Paleta.texto,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _BotonEstado(
                texto: "Correcta, publicar",
                color: Paleta.exito,
                activo: p.estado == "publicada",
                deshabilitado: _enviando,
                onPressed: () => _dictaminar("publicada"),
              ),
              _BotonEstado(
                texto: "Dudosa, sacar de circulación",
                color: Paleta.aviso,
                activo: p.estado == "en_auditoria",
                deshabilitado: _enviando,
                onPressed: () => _dictaminar("en_auditoria"),
              ),
              _BotonEstado(
                texto: "Retirar",
                color: Paleta.textoSuave,
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
              style: const TextStyle(fontSize: 11.5, color: Paleta.textoSuave),
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
      textStyle: const TextStyle(fontSize: 12),
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
  const PantallaPanelReportes({super.key});

  @override
  State<PantallaPanelReportes> createState() => _PantallaPanelReportesState();
}

class _PantallaPanelReportesState extends State<PantallaPanelReportes> {
  final _repo = RepositorioPanel();
  String _filtro = "abierto";
  Future<List<ReporteStaff>>? _carga;

  @override
  void initState() {
    super.initState();
    _recargar();
  }

  void _recargar() => setState(() => _carga = _repo.reportes(_filtro));

  @override
  Widget build(BuildContext context) => Scaffold(
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
                      selected: _filtro == valor,
                      onSelected: (_) {
                        if (_filtro == valor) return;
                        _filtro = valor;
                        _recargar();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<ReporteStaff>>(
            future: _carga,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final reportes = snap.data!;
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
                  reporte: reportes[i],
                  onDictaminado: _recargar,
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

const _mesesCortosPanel = [
  "ene",
  "feb",
  "mar",
  "abr",
  "may",
  "jun",
  "jul",
  "ago",
  "sep",
  "oct",
  "nov",
  "dic",
];

class _FichaReporte extends StatefulWidget {
  final ReporteStaff reporte;
  final VoidCallback onDictaminado;
  const _FichaReporte({required this.reporte, required this.onDictaminado});

  @override
  State<_FichaReporte> createState() => _FichaReporteState();
}

class _FichaReporteState extends State<_FichaReporte> {
  final _repo = RepositorioPanel();
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
        color: Paleta.superficie,
        border: Border.all(color: Paleta.borde),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "${r.preguntaCodigo ?? "pregunta #${r.preguntaId}"} · "
            "${r.creadoEn.day} ${_mesesCortosPanel[r.creadoEn.month - 1]} · ${r.estado}",
            style: const TextStyle(fontSize: 11, color: Paleta.textoTenue),
          ),
          const SizedBox(height: 4),
          Text(
            r.motivo,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          if (r.detalle case final d? when d.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              d,
              style: const TextStyle(fontSize: 13, color: Paleta.textoSuave),
            ),
          ],
          if (r.preguntaEnunciado case final e? when e.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Paleta.superficieAlta,
                border: Border.all(color: Paleta.borde),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                e,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Paleta.textoSuave,
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
                color: Paleta.textoSuave,
                activo: r.estado == "en_revision",
                deshabilitado: _enviando,
                onPressed: () => _dictaminar("en_revision"),
              ),
              _BotonEstado(
                texto: "Tenía razón",
                color: Paleta.exito,
                activo: r.estado == "aceptado",
                deshabilitado: _enviando,
                onPressed: () => _dictaminar("aceptado"),
              ),
              _BotonEstado(
                texto: "Sin error",
                color: Paleta.textoSuave,
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
              style: const TextStyle(fontSize: 11.5, color: Paleta.textoSuave),
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
  const PantallaPanelUsuarios({super.key});

  @override
  State<PantallaPanelUsuarios> createState() => _PantallaPanelUsuariosState();
}

class _PantallaPanelUsuariosState extends State<PantallaPanelUsuarios> {
  final _repo = RepositorioPanel();
  final _sesion = Sesion();
  late final Future<List<Persona>> _carga = _repo.personas();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("Personas")),
    body: FutureBuilder<List<Persona>>(
      future: _carga,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final personas = snap.data!;
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
              return const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  "Un docente puede revisar preguntas y resolver reportes. Un "
                  "admin puede además cambiar roles. El último administrador "
                  "no se puede degradar.",
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Paleta.textoSuave,
                    height: 1.5,
                  ),
                ),
              );
            }
            final p = personas[i - 1];
            return _FilaPersona(
              persona: p,
              esUnoMismo: p.id == _sesion.usuario?.id,
            );
          },
        );
      },
    ),
  );
}

class _FilaPersona extends StatefulWidget {
  final Persona persona;
  final bool esUnoMismo;
  const _FilaPersona({required this.persona, required this.esUnoMismo});

  @override
  State<_FilaPersona> createState() => _FilaPersonaState();
}

class _FilaPersonaState extends State<_FilaPersona> {
  final _repo = RepositorioPanel();
  late Rol _rol = widget.persona.rol;
  bool _guardando = false;
  String? _mensaje;

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
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  p.correo,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Paleta.textoSuave,
                  ),
                ),
                Text(
                  p.plan,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Paleta.textoTenue,
                  ),
                ),
                if (_mensaje case final m?)
                  Text(
                    m,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Paleta.textoSuave,
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
                const Text(
                  "(eres tú)",
                  style: TextStyle(fontSize: 10.5, color: Paleta.textoTenue),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
