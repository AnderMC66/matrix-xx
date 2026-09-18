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
  /// Sesión y repositorios inyectables, igual que en `PantallaHorario`.
  ///
  /// Todos resuelven `Supabase.instance.client` en su constructor, así que sin
  /// esta costura la portada no se puede montar fuera de una app con Supabase
  /// inicializado. En producción nadie los pasa.
  final Sesion? sesion;
  final RepositorioProgreso? progreso;
  final RepositorioRepaso? repasos;
  final RepositorioHorario? horario;

  const PantallaInicio({
    super.key,
    this.sesion,
    this.progreso,
    this.repasos,
    this.horario,
  });

  @override
  State<PantallaInicio> createState() => _PantallaInicioState();
}

class _PantallaInicioState extends State<PantallaInicio> {
  late final _sesion = widget.sesion ?? Sesion();
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
    final progreso = widget.progreso ?? RepositorioProgreso();
    final repasos = widget.repasos ?? RepositorioRepaso();
    final horarioRepo = widget.horario ?? RepositorioHorario();

    // Las cinco a la vez: ninguna depende de otra, y encadenarlas sumaba
    // cinco latencias antes de que la portada enseñara nada. Ver la nota
    // equivalente en `progreso.dart`.
    final resultados = await Future.wait([
      progreso.diagnostico(),
      progreso.racha(),
      repasos.resumen(),
      horarioRepo.obtener(),
      progreso.cursosDesatendidos(),
    ]);

    final diagnostico = resultados[0] as Diagnostico;
    final racha = resultados[1] as Racha?;
    final resumenRepasos = resultados[2] as ResumenRepasos?;
    final horario = resultados[3] as List<BloqueHorario>;
    final desatendidos = resultados[4] as List<CursoDesatendido>;

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
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const AdaptativaConBarra())),
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
                    color: context.esquema.primary,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    "M",
                    style: context.textos.headlineSmall!.copyWith(
                      color: context.esquema.onPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  "Matrix U",
                  style: context.textos.titleMedium!.copyWith(
                    fontWeight: FontWeight.w700,
                    color: context.esquema.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              "El examen de la UNSA,",
              style: context.textos.displaySmall!.copyWith(
                fontWeight: FontWeight.w800,
                color: context.esquema.onSurface,
              ),
            ),
            Text(
              "entero y ordenado.",
              style: context.textos.displaySmall!.copyWith(
                fontWeight: FontWeight.w800,
                color: context.esquema.primary,
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
            Text(
              "ACCESOS DIRECTOS",
              style: context.textos.labelSmall!.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: context.esquema.onSurfaceVariant,
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

class _AvisoSinCuenta extends StatelessWidget {
  final VoidCallback onEntrar;
  const _AvisoSinCuenta({required this.onEntrar});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.esquema.surfaceContainerLow,
      border: Border.all(color: context.esquema.outlineVariant),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Con una cuenta gratis guardas tu progreso por subtema y puedes "
          "programar un horario de estudio que te avisa cuando toca.",
          style: context.textos.bodyMedium!.copyWith(
            color: context.esquema.onSurfaceVariant,
          ),
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
              color: context.esquema.surfaceContainerLowest,
              border: Border.all(color: context.esquema.outlineVariant),
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
                      style: context.textos.bodyMedium!.copyWith(
                        color: context.esquema.onSurfaceVariant,
                      ),
                      children: [
                        TextSpan(
                          text: "${racha.diasActual} ",
                          style: context.textos.headlineSmall!.copyWith(
                            fontWeight: FontWeight.w800,
                            color: context.esquema.onSurface,
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
                          TextSpan(
                            text: " · te falta hoy",
                            style: TextStyle(color: context.colores.aviso),
                          ),
                      ],
                    ),
                  ),
                if (repasos != null && repasos.pendientesHoy > 0)
                  Text(
                    "${repasos.pendientesHoy} ${repasos.pendientesHoy == 1 ? "repaso" : "repasos"} para hoy",
                    style: context.textos.labelLarge!.copyWith(
                      fontWeight: FontWeight.w600,
                      color: context.esquema.primary,
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
              color: context.colores.avisoContenedor,
              border: Border.all(
                color: context.colores.aviso.withValues(alpha: 0.4),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: context.textos.bodyMedium!.copyWith(
                      color: context.colores.aviso,
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
                    foregroundColor: context.colores.aviso,
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
      color: context.esquema.surfaceContainerLowest,
      border: Border.all(color: context.esquema.outlineVariant),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "TU PROGRESO",
          style: context.textos.labelSmall!.copyWith(
            fontWeight: FontWeight.w700,
            color: context.esquema.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (diagnostico.vacio)
          Text(
            "Responde algunas preguntas y aquí verás tu acierto.",
            style: context.textos.bodySmall!.copyWith(
              color: context.esquema.onSurfaceVariant,
            ),
          )
        else
          RichText(
            text: TextSpan(
              style: context.textos.bodySmall!.copyWith(
                color: context.esquema.onSurfaceVariant,
              ),
              children: [
                TextSpan(
                  text: "${diagnostico.aciertoGlobal} % ",
                  style: context.textos.headlineMedium!.copyWith(
                    fontWeight: FontWeight.w800,
                    color: context.esquema.onSurface,
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
        color: context.esquema.surfaceContainerLowest,
        border: Border.all(color: context.esquema.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "PRÓXIMO BLOQUE",
            style: context.textos.labelSmall!.copyWith(
              fontWeight: FontWeight.w700,
              color: context.esquema.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (p == null)
            Text(
              "No tienes ningún bloque programado todavía.",
              style: context.textos.bodySmall!.copyWith(
                color: context.esquema.onSurfaceVariant,
              ),
            )
          else
            Text(
              "${p.bloque.cursoNombre}\n"
              "${diasSemana[p.bloque.diaSemana]} ${formatearHora(p.bloque.horaInicio)}",
              style: context.textos.bodySmall!.copyWith(
                color: context.esquema.onSurface,
              ),
            ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const HorarioConBarra())),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(
              p != null ? "Editar horario →" : "Programar →",
              style: context.textos.bodySmall,
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
    color: context.esquema.surfaceContainerLowest,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: context.esquema.outlineVariant),
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
                color: context.esquema.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icono, size: 16, color: context.esquema.primary),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: context.textos.labelLarge!.copyWith(
                    fontWeight: FontWeight.w700,
                    color: context.esquema.onSurface,
                  ),
                ),
                Text(
                  descripcion,
                  style: context.textos.labelSmall!.copyWith(
                    color: context.esquema.onSurfaceVariant,
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
