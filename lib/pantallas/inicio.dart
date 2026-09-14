import "package:flutter/material.dart";

import "../datos/horario.dart";
import "../datos/progreso.dart";
import "../datos/repaso.dart";
import "../datos/sesion.dart";
import "../main.dart" show Armazon;
import "../tema.dart";
import "../widgets/aviso.dart";
import "buscar.dart";
import "entrar.dart";
import "horario.dart";
import "practica_adaptativa.dart";

/// `/` — la portada.
///
/// Réplica de `src/app/page.tsx`. En la web tampoco vive en la barra móvil
/// —el header con el logo que llevaría ahí está oculto en pantallas
/// pequeñas—, así que en la práctica se ve al abrir la app por primera vez y
/// se vuelve por un enlace explícito después. Aquí es igual: `Arranque` la
/// muestra primero, y el ícono de casa en el `AppBar` del resto de la app es
/// el enlace explícito de vuelta.
class PantallaInicio extends StatefulWidget {
  const PantallaInicio({super.key});

  @override
  State<PantallaInicio> createState() => _PantallaInicioState();
}

class _PantallaInicioState extends State<PantallaInicio> {
  final _sesion = Sesion();
  Future<_PanelPersonal>? _carga;

  @override
  void initState() {
    super.initState();
    if (_sesion.hayCuenta) _carga = _pedir();
  }

  void _recargarPanel() {
    setState(() {
      _carga = _pedir();
    });
  }

  Future<_PanelPersonal> _pedir() async {
    final progreso = RepositorioProgreso();
    final repasos = RepositorioRepaso();
    final horarioRepo = RepositorioHorario();

    final diagnostico = await progreso.diagnostico();
    final racha = await progreso.racha();
    final resumenRepasos = await repasos.resumen();
    final horario = await horarioRepo.obtener();
    final desatendidos = await progreso.cursosDesatendidos();

    // Aviso dirigido: el curso más flojo que además lleva días sin tocarse.
    // El umbral de 2 días evita regañar a quien practicó ayer; el de 70 %
    // evita llamar «flojo» a un curso que va bien. Mismos números que la web.
    CursoDesatendido? descuidado;
    for (final c in desatendidos) {
      if (c.porcentaje != null &&
          c.porcentaje! < 70 &&
          c.diasSinPracticar >= 2) {
        descuidado = c;
        break;
      }
    }

    return _PanelPersonal(
      diagnostico: diagnostico,
      racha: racha,
      repasos: resumenRepasos,
      proximo: proximoBloque(horario, DateTime.now()),
      descuidado: descuidado,
    );
  }

  void _irAPestana(int destino) => Navigator.of(context).pushReplacement(
    MaterialPageRoute(builder: (_) => Armazon(destinoInicial: destino)),
  );

  /// Los seis accesos de la portada, en el orden en que se leen.
  List<Widget> _accesos() => [
    _AccesoDirecto(
      icono: Icons.edit_outlined,
      titulo: "Practicar",
      descripcion: "Preguntas resueltas",
      onTap: () => _irAPestana(2),
    ),
    _AccesoDirecto(
      icono: Icons.replay_outlined,
      titulo: "Repaso",
      descripcion: "Lo que toca hoy",
      onTap: () => _irAPestana(0),
    ),
    _AccesoDirecto(
      icono: Icons.adjust_outlined,
      titulo: "Adaptativa",
      descripcion: "Tus puntos flojos",
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const _AdaptativaConAppBar())),
    ),
    _AccesoDirecto(
      icono: Icons.menu_book_outlined,
      titulo: "Teoría",
      descripcion: "Curso por curso",
      onTap: () => _irAPestana(1),
    ),
    _AccesoDirecto(
      icono: Icons.timer_outlined,
      titulo: "Simulacros",
      descripcion: "Cronometrados",
      onTap: () => _irAPestana(3),
    ),
    _AccesoDirecto(
      icono: Icons.search,
      titulo: "Buscar",
      descripcion: "Por nombre o código",
      onTap: () =>
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const PantallaBuscar())),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final accesos = _accesos();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Paleta.acento,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Text(
                    "M",
                    style: TextStyle(
                      color: Paleta.acentoContraste,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  "Matrix U",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Paleta.texto,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const Text(
              "El examen de la UNSA,",
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w800,
                height: 1.15,
                color: Paleta.texto,
              ),
            ),
            const Text(
              "entero y ordenado.",
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w800,
                height: 1.15,
                color: Paleta.acento,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton(
                  onPressed: () => _irAPestana(2),
                  child: const Text("Empezar a practicar"),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PantallaBuscar()),
                  ),
                  child: const Text("Buscar un subtema"),
                ),
              ],
            ),
            const SizedBox(height: 22),
            if (!_sesion.hayCuenta)
              _AvisoSinCuenta(
                onEntrar: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (contextoRuta) => Scaffold(
                      appBar: AppBar(title: const Text("Acceso")),
                      body: PantallaEntrar(
                        alEntrar: () => Navigator.of(contextoRuta).pop(),
                      ),
                    ),
                  ),
                ),
              )
            else
              FutureBuilder<_PanelPersonal>(
                future: _carga,
                builder: (context, snap) {
                  // Callarse aquí sería lo peor: el alumno con sesión sabe que
                  // su panel existe —lo vio ayer— y verlo desaparecer sin una
                  // palabra se lee como que perdió la racha, no como que el
                  // servidor no contestó. Con Reintentar, además, no hace falta
                  // salir de Inicio y volver a entrar.
                  if (snap.hasError) {
                    return Aviso(
                      icono: Icons.cloud_off_outlined,
                      titulo: "No se pudo cargar tu panel",
                      detalle:
                          "Tu racha, tus repasos y tu diagnóstico se calculan "
                          "en el servidor, y ahora mismo no responde.",
                      accion: ("Reintentar", _recargarPanel),
                      compacto: true,
                    );
                  }
                  // Mientras carga no va un spinner: el panel entra debajo de
                  // la portada, que ya es contenido, y un giro de dos líneas
                  // ahí solo hace saltar todo lo de abajo cuando resuelve.
                  if (!snap.hasData) return const SizedBox.shrink();
                  return _PanelPersonalVista(datos: snap.data!);
                },
              ),
            const SizedBox(height: 26),
            const Text(
              "ACCESOS DIRECTOS",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: Paleta.textoTenue,
              ),
            ),
            const SizedBox(height: 10),
            // Dos por fila, y **sin fijar la altura**.
            //
            // Esto era un `GridView.count(childAspectRatio: 1.35)`, y ese número
            // decide la ALTURA de cada baldosa a partir de su ancho: unos 101 px
            // a 320 px de pantalla, pasara lo que pasara. Dentro crece un cuadro
            // de icono de 32 px fijos más dos líneas de texto que SÍ escalan con
            // el tipo de letra del sistema. Con la letra normal sobraban 11 px;
            // desde ×1,3 —muy por debajo del ×2 que ofrece Accesibilidad en
            // Android— el texto ya no cabía y las seis baldosas desbordaban a la
            // vez.
            //
            // Dividir la proporción por la escala tapaba el caso hasta ×1,5 y
            // volvía a desbordar 29 px en ×2: el ancho de la baldosa no cambia,
            // así que a letra muy grande la descripción se parte en más líneas
            // de las que cualquier proporción fija prevé. La única forma de que
            // no vuelva es no fijar la altura: cada fila mide lo que mida su
            // contenido, y el `IntrinsicHeight` iguala las dos baldosas de la
            // fila para que sigan pareciendo una rejilla.
            for (var i = 0; i < accesos.length; i += 2)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: accesos[i]),
                      const SizedBox(width: 8),
                      // Con un número impar de accesos, el hueco mantiene la
                      // última baldosa a su ancho en vez de estirarla al doble.
                      Expanded(
                        child: i + 1 < accesos.length
                            ? accesos[i + 1]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AdaptativaConAppBar extends StatelessWidget {
  const _AdaptativaConAppBar();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("Práctica adaptativa")),
    body: const PantallaPracticaAdaptativa(),
  );
}

class _HorarioConAppBar extends StatelessWidget {
  const _HorarioConAppBar();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("Horario de estudio")),
    body: const PantallaHorario(),
  );
}

class _AvisoSinCuenta extends StatelessWidget {
  final VoidCallback onEntrar;
  const _AvisoSinCuenta({required this.onEntrar});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Paleta.superficie,
      border: Border.all(color: Paleta.borde),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Con una cuenta gratis guardas tu progreso por subtema y puedes "
          "programar un horario de estudio que te avisa cuando toca.",
          style: TextStyle(fontSize: 13, color: Paleta.textoSuave, height: 1.5),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: onEntrar,
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          child: const Text("Crear cuenta o entrar →"),
        ),
      ],
    ),
  );
}

/// Lo que ve solo quien tiene sesión: acierto global (misma fuente que el
/// diagnóstico de Progreso, resumida a una cifra), constancia, un aviso
/// dirigido si hay un curso flojo desatendido, y el próximo bloque de
/// horario. Ninguna de estas cifras se inventa si no hay datos reales.
class _PanelPersonal {
  final Diagnostico diagnostico;
  final Racha? racha;
  final ResumenRepasos? repasos;
  final ({BloqueHorario bloque, DateTime cuando})? proximo;
  final CursoDesatendido? descuidado;

  const _PanelPersonal({
    required this.diagnostico,
    required this.racha,
    required this.repasos,
    required this.proximo,
    required this.descuidado,
  });
}

class _PanelPersonalVista extends StatelessWidget {
  final _PanelPersonal datos;
  const _PanelPersonalVista({required this.datos});

  @override
  Widget build(BuildContext context) {
    final racha = datos.racha;
    final repasos = datos.repasos;
    final mostrarConstancia =
        (racha?.diasActual ?? 0) > 0 || (repasos?.pendientesHoy ?? 0) > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (mostrarConstancia) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Paleta.superficieAlta,
              border: Border.all(color: Paleta.borde),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Wrap(
              spacing: 18,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (racha != null && racha.diasActual > 0)
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: Paleta.textoSuave,
                      ),
                      children: [
                        TextSpan(
                          text: "${racha.diasActual} ",
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: Paleta.texto,
                          ),
                        ),
                        TextSpan(
                          text: racha.diasActual == 1
                              ? "día seguido"
                              : "días seguidos",
                        ),
                        // Sin esto la racha parece ya asegurada y no invita a
                        // estudiar hoy también.
                        if (!racha.estudiadoHoy)
                          const TextSpan(
                            text: " · te falta hoy",
                            style: TextStyle(color: Paleta.aviso),
                          ),
                      ],
                    ),
                  ),
                if (repasos != null && repasos.pendientesHoy > 0)
                  Text(
                    "${repasos.pendientesHoy} ${repasos.pendientesHoy == 1 ? "repaso" : "repasos"} para hoy",
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Paleta.acento,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (datos.descuidado case final d?) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Paleta.avisoSuave,
              border: Border.all(color: Paleta.aviso.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 13,
                      color: Paleta.aviso,
                      height: 1.45,
                    ),
                    children: [
                      const TextSpan(text: "Llevas "),
                      TextSpan(
                        text: "${d.diasSinPracticar} días",
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const TextSpan(text: " sin practicar "),
                      TextSpan(
                        text: d.nombre,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text: ", tu curso más flojo (${d.porcentaje} %).",
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(
                          title: const Text("Práctica adaptativa"),
                        ),
                        body: PantallaPracticaAdaptativa(cursoSlug: d.slug),
                      ),
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: Paleta.aviso,
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text("Practicarlo ahora"),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _TarjetaProgreso(diagnostico: datos.diagnostico)),
            const SizedBox(width: 10),
            Expanded(child: _TarjetaProximoBloque(proximo: datos.proximo)),
          ],
        ),
      ],
    );
  }
}

class _TarjetaProgreso extends StatelessWidget {
  final Diagnostico diagnostico;
  const _TarjetaProgreso({required this.diagnostico});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Paleta.superficieAlta,
      border: Border.all(color: Paleta.borde),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "TU PROGRESO",
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Paleta.textoSuave,
          ),
        ),
        const SizedBox(height: 8),
        if (diagnostico.vacio)
          const Text(
            "Responde algunas preguntas y aquí verás tu acierto.",
            style: TextStyle(
              fontSize: 11.5,
              color: Paleta.textoSuave,
              height: 1.4,
            ),
          )
        else
          RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 11.5, color: Paleta.textoTenue),
              children: [
                TextSpan(
                  text: "${diagnostico.aciertoGlobal} % ",
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Paleta.texto,
                  ),
                ),
                TextSpan(
                  text: "de acierto en ${diagnostico.respondidas} preguntas",
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _TarjetaProximoBloque extends StatelessWidget {
  final ({BloqueHorario bloque, DateTime cuando})? proximo;
  const _TarjetaProximoBloque({required this.proximo});

  @override
  Widget build(BuildContext context) {
    final p = proximo;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Paleta.superficieAlta,
        border: Border.all(color: Paleta.borde),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "PRÓXIMO BLOQUE",
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Paleta.textoSuave,
            ),
          ),
          const SizedBox(height: 8),
          if (p == null)
            const Text(
              "No tienes ningún bloque programado todavía.",
              style: TextStyle(
                fontSize: 11.5,
                color: Paleta.textoSuave,
                height: 1.4,
              ),
            )
          else
            Text(
              "${p.bloque.cursoNombre}\n"
              "${diasSemana[p.bloque.diaSemana]} ${formatearHora(p.bloque.horaInicio)}",
              style: const TextStyle(
                fontSize: 12,
                color: Paleta.texto,
                height: 1.4,
              ),
            ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const _HorarioConAppBar()),
            ),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(
              p != null ? "Editar horario →" : "Programar →",
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccesoDirecto extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String descripcion;
  final VoidCallback onTap;

  const _AccesoDirecto({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Paleta.superficieAlta,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: Paleta.borde),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Paleta.acentoSuave,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icono, size: 16, color: Paleta.acento),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: Paleta.texto,
                  ),
                ),
                Text(
                  descripcion,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Paleta.textoTenue,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
