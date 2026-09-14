import "package:flutter/material.dart";

import "../datos/horario.dart";
import "../datos/progreso.dart";
import "../datos/repaso.dart";
import "../datos/sesion.dart";
import "../fechas.dart";
import "../tema.dart";
import "../widgets/aviso.dart";
import "../widgets/nota.dart";
import "horario.dart";
import "panel.dart";
import "practica.dart";

/// `/cuenta` en la web, «Progreso» en la barra inferior.
///
/// Réplica de `src/app/cuenta/page.tsx` con el `<Diagnostico />` embebido, y
/// con el mismo orden de lectura, que no es casual: primero lo accionable
/// —racha, repasos pendientes, próximo bloque de estudio, dónde estás
/// perdiendo puntos— y solo después el desglose completo por curso. Lo que
/// decide el puntaje es saber qué repasar mañana, no el promedio.
class PantallaProgreso extends StatefulWidget {
  const PantallaProgreso({super.key});

  @override
  State<PantallaProgreso> createState() => _PantallaProgresoState();
}

typedef _Datos = (
  Perfil?,
  Racha?,
  ResumenRepasos?,
  List<BloqueHorario>,
  Diagnostico,
  List<ReporteResuelto>,
);

class _PantallaProgresoState extends State<PantallaProgreso> {
  final _repo = RepositorioProgreso();
  final _repasos = RepositorioRepaso();
  final _horario = RepositorioHorario();
  final _sesion = Sesion();

  Future<_Datos>? _carga;

  @override
  void initState() {
    super.initState();
    _recargar();
  }

  void _recargar() {
    if (!_sesion.hayCuenta) return;
    setState(() {
      _carga = _pedir();
    });
  }

  /// Las seis peticiones salen A LA VEZ, no una detrás de otra.
  ///
  /// Escrito como seis `await` seguidos, cada una esperaba a que terminara la
  /// anterior: seis viajes de ida y vuelta encadenados contra Supabase para
  /// pintar una pantalla cuyos seis datos no dependen entre sí. En el wifi de
  /// casa se nota poco; en los datos móviles con los que se estudia en el
  /// micro, son seis latencias sumadas cada vez que se abre Progreso.
  ///
  /// `Future.wait` las lanza juntas y espera a la más lenta, así que el coste
  /// pasa de la suma al máximo. Si alguna falla, `Future.wait` propaga el
  /// error igual que antes y el `FutureBuilder` enseña su aviso con
  /// «Reintentar».
  Future<_Datos> _pedir() async {
    final resultados = await Future.wait([
      _repo.perfil(),
      _repo.racha(),
      _repasos.resumen(),
      _horario.obtener(),
      _repo.diagnostico(),
      _repo.reportesResueltos(),
    ]);

    return (
      resultados[0] as Perfil?,
      resultados[1] as Racha?,
      resultados[2] as ResumenRepasos?,
      resultados[3] as List<BloqueHorario>,
      resultados[4] as Diagnostico,
      resultados[5] as List<ReporteResuelto>,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_sesion.hayCuenta) {
      return const Aviso(
        icono: Icons.lock_outline,
        titulo: "Tu progreso necesita tu cuenta",
        detalle:
            "La racha, el diagnóstico y los repasos se calculan sobre tu "
            "historial de respuestas.\n\n"
            "Usa el botón de entrar, arriba a la derecha.",
      );
    }

    return FutureBuilder<_Datos>(
      future: _carga,
      builder: (context, snap) {
        if (snap.hasError) {
          return Aviso(
            icono: Icons.cloud_off_outlined,
            titulo: "No se pudo cargar tu progreso",
            detalle: "${snap.error}",
            accion: ("Reintentar", _recargar),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final (perfil, racha, repasos, horario, diagnostico, reportes) =
            snap.data!;

        return RefreshIndicator(
          onRefresh: () async => _recargar(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              _Cabecera(perfil: perfil, correo: _repo.usuario?.email),
              if (perfil == null) ...[
                const SizedBox(height: 16),
                const Nota(
                  texto:
                      "Tu usuario existe pero no tiene perfil: el disparador "
                      "`al_crear_usuario` no se ejecutó.",
                ),
              ],
              if (perfil != null && perfil.esStaff) ...[
                const SizedBox(height: 16),
                _PanelStaff(rol: perfil.rol),
              ],
              if (reportes.isNotEmpty) ...[
                const SizedBox(height: 16),
                _Reportes(
                  reportes: reportes,
                  alMarcar: () async {
                    await _repo.marcarReportesVistos();
                    _recargar();
                  },
                ),
              ],
              const SizedBox(height: 22),
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _TarjetaRacha(racha: racha)),
                  const SizedBox(width: 10),
                  Expanded(child: _TarjetaRepasos(resumen: repasos)),
                ],
              ),
              const SizedBox(height: 16),
              _ProximoBloque(horario: horario),
              const SizedBox(height: 28),
              _SeccionDiagnostico(diagnostico: diagnostico),
              const SizedBox(height: 32),
              const Divider(),
              _EliminarCuenta(alEliminar: _recargar),
            ],
          ),
        );
      },
    );
  }
}

class _Cabecera extends StatelessWidget {
  final Perfil? perfil;
  final String? correo;

  const _Cabecera({required this.perfil, required this.correo});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        perfil?.nombre?.trim().isNotEmpty ?? false
            ? perfil!.nombre!
            : "Tu progreso",
        style: const TextStyle(
          fontSize: 23,
          fontWeight: FontWeight.w700,
          color: Paleta.texto,
        ),
      ),
      if (correo != null) ...[
        const SizedBox(height: 4),
        Text(
          correo!,
          style: const TextStyle(fontSize: 13, color: Paleta.textoTenue),
        ),
      ],
      if (perfil case final p?) ...[
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Etiqueta(clave: "Área", valor: p.areaNombre ?? "Sin elegir"),
            _Etiqueta(clave: "Plan", valor: p.plan),
            _Etiqueta(clave: "Créditos", valor: "${p.creditos}"),
            _Etiqueta(clave: "Desde", valor: mesAno(p.creadoEn)),
          ],
        ),
      ],
    ],
  );
}

class _Etiqueta extends StatelessWidget {
  final String clave;
  final String valor;
  const _Etiqueta({required this.clave, required this.valor});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: Paleta.superficieAlta,
      border: Border.all(color: Paleta.borde),
      borderRadius: BorderRadius.circular(9),
    ),
    child: RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12.5, color: Paleta.texto),
        children: [
          TextSpan(
            text: "$clave ",
            style: const TextStyle(color: Paleta.textoTenue),
          ),
          TextSpan(
            text: valor,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

/// Enlace real a `/panel`. Antes esta pantalla se limitaba a avisar que
/// existía; ahora abre el panel de verdad — `RepositorioPanel.rolActual()`
/// vuelve a comprobarlo ahí, así que este atajo no es la única puerta.
class _PanelStaff extends StatelessWidget {
  final String rol;
  const _PanelStaff({required this.rol});

  @override
  Widget build(BuildContext context) => Material(
    color: Paleta.acentoSuave,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () =>
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const PantallaPanel())),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Paleta.acento),
        ),
        child: Row(
          children: [
            const Icon(Icons.shield_outlined, size: 18, color: Paleta.acento),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Panel de $rol",
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Paleta.acento,
                  height: 1.45,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Paleta.acento),
          ],
        ),
      ),
    ),
  );
}

/// Cierra el ciclo del reporte de error: el alumno mandó uno, un docente lo
/// revisó, y aquí se entera. Al descartarlo se marcan como vistos.
class _Reportes extends StatelessWidget {
  final List<ReporteResuelto> reportes;
  final Future<void> Function() alMarcar;

  const _Reportes({required this.reportes, required this.alMarcar});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Paleta.superficieAlta,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Paleta.borde),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          reportes.length == 1
              ? "Revisaron tu reporte"
              : "Revisaron ${reportes.length} de tus reportes",
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: Paleta.texto,
          ),
        ),
        const SizedBox(height: 10),
        for (final r in reportes)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  r.aceptado ? Icons.check_circle_outline : Icons.info_outline,
                  size: 15,
                  color: r.aceptado ? Paleta.exito : Paleta.textoTenue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "${r.preguntaCodigo ?? "Pregunta"} · ${r.motivo} — "
                    "${r.aceptado ? "aceptado" : r.estado}",
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Paleta.textoSuave,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => alMarcar(),
            child: const Text("Entendido"),
          ),
        ),
      ],
    ),
  );
}

class _TarjetaRacha extends StatelessWidget {
  final Racha? racha;
  const _TarjetaRacha({required this.racha});

  @override
  Widget build(BuildContext context) {
    final r = racha;
    return _Panel(
      titulo: "RACHA DE ESTUDIO",
      child: r == null || !r.arrancada
          // `Racha.arrancada` es `diasActual > 0`: basta UN día respondiendo
          // para que esta tarjeta pase a mostrar el número. El texto decía
          // «dos días seguidos», que le pedía al alumno el doble de lo que
          // hace falta para ver su primer resultado — justo lo contrario de
          // lo que una racha intenta provocar.
          ? const Text(
              "Responde preguntas hoy y aquí arranca tu racha.",
              style: TextStyle(
                fontSize: 12.5,
                color: Paleta.textoSuave,
                height: 1.45,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      "${r.diasActual}",
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: Paleta.texto,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      r.diasActual == 1 ? "día" : "días",
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Paleta.textoTenue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  r.estudiadoHoy
                      ? "Ya estudiaste hoy."
                      : "Todavía no estudias hoy: responde algo para no "
                            "cortarla.",
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Paleta.textoTenue,
                    height: 1.4,
                  ),
                ),
                if (r.diasMaxima > r.diasActual)
                  Text(
                    "Tu mejor racha fue de ${r.diasMaxima} días.",
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Paleta.textoTenue,
                      height: 1.4,
                    ),
                  ),
              ],
            ),
    );
  }
}

class _TarjetaRepasos extends StatelessWidget {
  final ResumenRepasos? resumen;
  const _TarjetaRepasos({required this.resumen});

  @override
  Widget build(BuildContext context) {
    final r = resumen;
    return _Panel(
      titulo: "REPASOS",
      child: r == null || r.sinHistorial
          ? const Text(
              "Cada pregunta que respondes entra en el calendario de repaso.",
              style: TextStyle(
                fontSize: 12.5,
                color: Paleta.textoSuave,
                height: 1.45,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${r.pendientesHoy}",
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Paleta.texto,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "para hoy, de ${r.totalProgramados} programados",
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Paleta.textoTenue,
                    height: 1.4,
                  ),
                ),
              ],
            ),
    );
  }
}

/// Réplica de la sección «Próximo bloque de estudio» de `cuenta/page.tsx`,
/// que usa `proximoBloque()` sobre el mismo horario que gestiona
/// `PantallaHorario`.
class _ProximoBloque extends StatelessWidget {
  final List<BloqueHorario> horario;
  const _ProximoBloque({required this.horario});

  @override
  Widget build(BuildContext context) {
    final proximo = proximoBloque(horario, DateTime.now());

    return _Panel(
      titulo: "PRÓXIMO BLOQUE DE ESTUDIO",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (proximo == null)
            const Text(
              "No tienes ningún bloque programado todavía. Programa un "
              "horario semanal por curso y te avisamos cuando toca.",
              style: TextStyle(
                fontSize: 12.5,
                color: Paleta.textoSuave,
                height: 1.45,
              ),
            )
          else
            RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 13.5, color: Paleta.texto),
                children: [
                  TextSpan(
                    text: proximo.bloque.cursoNombre,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text:
                        " — ${diasSemana[proximo.bloque.diaSemana]} "
                        "${formatearHora(proximo.bloque.horaInicio)}",
                    style: const TextStyle(color: Paleta.textoSuave),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HorarioConBarra()),
              ),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: Text(
                proximo != null ? "Editar horario →" : "Programar un bloque →",
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String titulo;
  final Widget child;
  const _Panel({required this.titulo, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Paleta.superficieAlta,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Paleta.borde),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
            color: Paleta.textoSuave,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );
}

class _SeccionDiagnostico extends StatelessWidget {
  final Diagnostico diagnostico;
  const _SeccionDiagnostico({required this.diagnostico});

  @override
  Widget build(BuildContext context) {
    if (diagnostico.vacio) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 34),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Paleta.borde, style: BorderStyle.solid),
        ),
        child: const Column(
          children: [
            Text(
              "Tu diagnóstico está vacío",
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: Paleta.texto,
              ),
            ),
            SizedBox(height: 8),
            Text(
              "En cuanto respondas preguntas, aquí aparece en qué subtemas "
              "estás perdiendo puntos y cuáles ya dominas.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Paleta.textoSuave,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Tu diagnóstico",
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: Paleta.texto,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: Paleta.borde),
              bottom: BorderSide(color: Paleta.borde),
            ),
          ),
          child: Row(
            children: [
              _Metrica(
                valor: "${diagnostico.aciertoGlobal} %",
                etiqueta: "acierto global",
                destacado: true,
              ),
              _Metrica(
                valor: "${diagnostico.respondidas}",
                etiqueta: "respondidas",
              ),
              _Metrica(
                valor:
                    "${diagnostico.consolidados}/${diagnostico.subtemas.length}",
                etiqueta: "subtemas dominados",
              ),
            ],
          ),
        ),

        if (diagnostico.prioridades.isNotEmpty) ...[
          const SizedBox(height: 26),
          const _Rotulo("DÓNDE ESTÁS PERDIENDO PUNTOS"),
          const SizedBox(height: 10),
          for (final (i, s) in diagnostico.prioridades.indexed)
            _FilaPrioridad(puesto: i + 1, subtema: s),
        ],

        const SizedBox(height: 26),
        const _Rotulo("POR CURSO"),
        const SizedBox(height: 10),
        for (final e in diagnostico.porCurso.entries)
          _BloqueCurso(curso: e.key, subtemas: e.value),
      ],
    );
  }
}

class _Rotulo extends StatelessWidget {
  final String texto;
  const _Rotulo(this.texto);

  @override
  Widget build(BuildContext context) => Text(
    texto,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      color: Paleta.textoTenue,
    ),
  );
}

class _Metrica extends StatelessWidget {
  final String valor;
  final String etiqueta;
  final bool destacado;

  const _Metrica({
    required this.valor,
    required this.etiqueta,
    this.destacado = false,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          valor,
          style: TextStyle(
            fontSize: destacado ? 26 : 22,
            fontWeight: FontWeight.w800,
            color: destacado ? Paleta.acento : Paleta.texto,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          etiqueta,
          style: const TextStyle(
            fontSize: 11,
            color: Paleta.textoTenue,
            height: 1.3,
          ),
        ),
      ],
    ),
  );
}

/// Uno de los cinco subtemas donde más puntos se pierden.
///
/// **Ahora lleva a alguna parte.** Era un `Container` sin `onTap`: la app
/// calculaba con precisión dónde está flojo el alumno, lo pintaba, y ahí se
/// acababa — en las 900 líneas de esta pantalla no había una sola ruta a
/// practicar. Decirle a alguien dónde falla y no darle la puerta es la mitad
/// de un diagnóstico.
///
/// `PantallaPracticaSubtema` decide qué enseñar según cuántas preguntas haya,
/// incluido el caso de ninguna: el diagnóstico sale de las respuestas del
/// alumno y el banco del APK, que pueden no coincidir si la pregunta se
/// retiró.
class _FilaPrioridad extends StatelessWidget {
  final int puesto;
  final SubtemaDiagnostico subtema;

  const _FilaPrioridad({required this.puesto, required this.subtema});

  @override
  Widget build(BuildContext context) => Material(
    color: Paleta.superficieAlta,
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PantallaPracticaSubtema(
            codigo: subtema.codigo,
            nombre: subtema.nombre,
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Paleta.borde),
        ),
        child: Row(
          children: [
            Text(
              "$puesto",
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Paleta.textoTenue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subtema.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Paleta.texto,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    "${subtema.codigo} · ${subtema.cursoNombre}",
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Paleta.textoTenue,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _Marcador(subtema: subtema),
            const Icon(Icons.chevron_right, size: 16, color: Paleta.textoTenue),
          ],
        ),
      ),
    ),
  );
}

class _BloqueCurso extends StatelessWidget {
  final String curso;
  final List<SubtemaDiagnostico> subtemas;

  const _BloqueCurso({required this.curso, required this.subtemas});

  @override
  Widget build(BuildContext context) {
    final respondidas = subtemas.fold(0, (n, s) => n + s.respondidas);
    final correctas = subtemas.fold(0, (n, s) => n + s.correctas);
    final promedio = respondidas == 0
        ? 0
        : (correctas * 100 / respondidas).round();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Paleta.borde),
      ),
      child: Theme(
        // El divisor por defecto del `ExpansionTile` dibuja una línea encima
        // del borde de la tarjeta y se ve doble.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.only(bottom: 6),
          shape: const Border(),
          title: Text(
            curso,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: Paleta.texto,
            ),
          ),
          subtitle: Text(
            "$correctas de $respondidas · $promedio %",
            style: const TextStyle(fontSize: 12, color: Paleta.textoTenue),
          ),
          children: [
            for (final s in subtemas)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.nombre,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Paleta.texto,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "${s.codigo} · ${s.temaNombre}",
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Paleta.textoTenue,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _Marcador(subtema: s),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// El porcentaje con su color, y debajo el crudo del que sale.
///
/// El crudo importa: «50 %» de 2 preguntas y «50 %» de 40 son diagnósticos muy
/// distintos, y sin el denominador el alumno no puede distinguirlos.
class _Marcador extends StatelessWidget {
  final SubtemaDiagnostico subtema;
  const _Marcador({required this.subtema});

  @override
  Widget build(BuildContext context) {
    final pct = subtema.porcentaje;
    final color = pct >= umbralBien
        ? Paleta.exito
        : pct < umbralFlojo
        ? Paleta.acento
        : Paleta.aviso;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          "${pct.round()} %",
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          "${subtema.correctas}/${subtema.respondidas}",
          style: const TextStyle(fontSize: 11, color: Paleta.textoTenue),
        ),
      ],
    );
  }
}

/// «Eliminar mi cuenta».
///
/// **Existe porque Google Play lo exige**: toda app que deje crear una cuenta
/// tiene que dejar borrarla desde dentro. Sin esto la ficha se rechaza, así
/// que no es una preferencia de diseño ni algo aplazable.
///
/// Va al final de Progreso, después de todo lo demás, y en gris: tiene que
/// poder encontrarse sin buscar ayuda, y a la vez no competir con nada. Y
/// pide confirmación escribiendo, no solo pulsando —es lo único irreversible
/// de toda la app, y un diálogo de dos botones se acepta por inercia.
class _EliminarCuenta extends StatefulWidget {
  /// Se llama cuando la cuenta ya no existe, para que el armazón vuelva al
  /// estado de "sin sesión".
  final VoidCallback alEliminar;

  const _EliminarCuenta({required this.alEliminar});

  @override
  State<_EliminarCuenta> createState() => _EliminarCuentaState();
}

class _EliminarCuentaState extends State<_EliminarCuenta> {
  final _sesion = Sesion();
  bool _borrando = false;

  Future<void> _confirmar() async {
    final seguro = await showDialog<bool>(
      context: context,
      builder: (_) => const _DialogoEliminar(),
    );
    if (!(seguro ?? false) || !mounted) return;

    setState(() => _borrando = true);
    try {
      await _sesion.eliminarCuenta();
      if (mounted) widget.alEliminar();
    } catch (e) {
      if (!mounted) return;
      setState(() => _borrando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
    }
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: _borrando ? null : _confirmar,
      icon: const Icon(Icons.delete_outline, size: 16),
      label: Text(_borrando ? "Borrando…" : "Eliminar mi cuenta"),
      style: TextButton.styleFrom(
        foregroundColor: Paleta.textoTenue,
        textStyle: const TextStyle(fontSize: 12.5),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    ),
  );
}

/// El diálogo pide escribir BORRAR.
///
/// No es fricción por gusto: es la única acción de la app que no se puede
/// deshacer, y la lista de lo que se lleva por delante —racha, diagnóstico,
/// repasos programados, simulacros rendidos— es justo lo que a un alumno le
/// costó meses construir. Un «¿Seguro?» con dos botones se pulsa sin leer.
class _DialogoEliminar extends StatefulWidget {
  const _DialogoEliminar();

  @override
  State<_DialogoEliminar> createState() => _DialogoEliminarState();
}

class _DialogoEliminarState extends State<_DialogoEliminar> {
  static const _palabra = "BORRAR";
  final _campo = TextEditingController();

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final coincide = _campo.text.trim().toUpperCase() == _palabra;

    return AlertDialog(
      title: const Text("¿Eliminar tu cuenta?"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Se borra para siempre, y con ella:\n\n"
            "· tu racha y tu diagnóstico por subtema\n"
            "· los repasos que tenías programados\n"
            "· tus simulacros rendidos y sus puntajes\n"
            "· tu horario de estudio\n\n"
            "No se puede deshacer. Escribe $_palabra para confirmar.",
            style: TextStyle(fontSize: 13.5, height: 1.5),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _campo,
            autofocus: true,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              hintText: _palabra,
            ),
          ),
        ],
      ),
      actions: [
        // La salida segura va primero, igual que en el diálogo de finalizar
        // simulacro: en algo irreversible, lo fácil de pulsar por accidente
        // tiene que ser lo que no rompe nada.
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text("Cancelar"),
        ),
        FilledButton(
          onPressed: coincide ? () => Navigator.of(context).pop(true) : null,
          style: FilledButton.styleFrom(backgroundColor: Paleta.acento),
          child: const Text("Eliminar"),
        ),
      ],
    );
  }
}
