import "package:flutter/material.dart";
import "package:matr_u/core/config/config.dart";
import "package:matr_u/data/repositories/practica.dart";
import "package:matr_u/data/repositories/preguntas.dart";
import "package:matr_u/data/repositories/sesion.dart";
import "package:matr_u/domain/models/practica.dart";
import "package:matr_u/domain/models/preguntas.dart";
import "package:matr_u/ui/core/theme/tema.dart";
import "package:matr_u/ui/core/widgets/aviso.dart";
import "package:matr_u/ui/core/widgets/formula.dart";
import "package:matr_u/ui/core/widgets/nota.dart";
import "package:matr_u/ui/features/practice/views/figura_red.dart";
import "package:matr_u/ui/features/practice/views/practica_adaptativa.dart";

/// `/practica` — los cursos con preguntas, ordenados por cuántas tienen.
class PantallaPractica extends StatefulWidget {
  const PantallaPractica({super.key});

  @override
  State<PantallaPractica> createState() => _PantallaPracticaState();
}

class _PantallaPracticaState extends State<PantallaPractica> {
  final _repo = RepositorioPreguntas();
  late final Future<Banco> _banco = _repo.cargar();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Banco>(
      future: _banco,
      builder: (context, snap) {
        if (snap.hasError) {
          return Aviso.contenidoLocal(
            titulo: "No se pudo cargar el banco",
            error: snap.error!,
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final banco = snap.data!;
        final cursos = banco.cursos();

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: cursos.length + 2,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            if (i == 0) return const _TarjetaAdaptativa();
            if (i == 1) return _Encabezado(banco: banco);
            final curso = cursos[i - 2];
            return Card(
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                title: Text(
                  curso.nombre,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: context.esquema.onSurface,
                  ),
                ),
                subtitle: Text(
                  "${curso.total} ${curso.total == 1 ? "pregunta" : "preguntas"}",
                  style: TextStyle(color: context.esquema.onSurfaceVariant),
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  color: context.esquema.onSurfaceVariant,
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SesionPractica(
                      titulo: curso.nombre,
                      preguntas: banco.deCurso(curso.slug),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Acceso a `/practica/adaptativa`: elige las preguntas por ti en vez de
/// exigir escoger un curso primero. Va antes de la lista de cursos, no
/// después, porque es la vía recomendada — la web la referencia desde
/// Repaso y desde el curso más flojo en Progreso, pero en el móvil no hay un
/// lugar único que agrupe ambos, así que aquí es donde nunca falta.
class _TarjetaAdaptativa extends StatelessWidget {
  const _TarjetaAdaptativa();

  @override
  Widget build(BuildContext context) => Material(
    color: context.esquema.secondaryContainer,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const AdaptativaConBarra())),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, color: context.esquema.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Práctica adaptativa",
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: context.esquema.primary,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    "Elegimos las preguntas por ti: primero donde peor vas",
                    style: context.textos.bodySmall!.copyWith(
                      color: context.esquema.primary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: context.esquema.primary),
          ],
        ),
      ),
    ),
  );
}

/// Practicar UN subtema, entrando por su código (`ALG-02-01`).
///
/// **Es el destino que le faltaba al diagnóstico.** Progreso calcula los cinco
/// subtemas donde el alumno pierde más puntos y los pintaba sin enlace: la app
/// decía exactamente dónde estás flojo y no ofrecía ninguna forma de ir. Lo
/// mismo en Curso, donde cada subtema muestra cuántas preguntas tiene y no se
/// podía pulsar. La web sí lo hace, con `?subtema=` resuelto en el cliente.
///
/// Carga el banco aquí y no en quien llama para que Progreso no tenga que
/// conocer los assets: desde allí basta con un código y un nombre.
///
/// **Dice cuántas preguntas hay antes de empezar.** No es un adorno: 128 de
/// los 206 subtemas con preguntas tienen exactamente una, así que prometer
/// «practica esto» y abrir una tanda de una pregunta sería engañar. Con el
/// número delante, el alumno decide.
class PantallaPracticaSubtema extends StatefulWidget {
  final String codigo;
  final String nombre;

  /// Se los pasa a la tanda que abre. No los usa ella —el banco sale de los
  /// assets—, pero `SesionPractica` sí, y sin poder atravesarla esta pantalla
  /// no se puede probar hasta el final. En producción nadie los pasa.
  final RepositorioPractica? repositorio;
  final Sesion? sesion;

  const PantallaPracticaSubtema({
    super.key,
    required this.codigo,
    required this.nombre,
    this.repositorio,
    this.sesion,
  });

  @override
  State<PantallaPracticaSubtema> createState() =>
      _PantallaPracticaSubtemaState();
}

class _PantallaPracticaSubtemaState extends State<PantallaPracticaSubtema> {
  late final Future<List<Pregunta>> _preguntas = RepositorioPreguntas()
      .cargar()
      .then((banco) => banco.deSubtema(widget.codigo));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.nombre, style: context.textos.bodyLarge)),
    body: FutureBuilder<List<Pregunta>>(
      future: _preguntas,
      builder: (context, snap) {
        if (snap.hasError) {
          return Aviso.contenidoLocal(
            titulo: "No se pudo cargar el banco",
            error: snap.error!,
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final preguntas = snap.data!;
        if (preguntas.isEmpty) {
          // Pasa a menudo y no es un fallo: 750 de los 956 subtemas del
          // sílabo no tienen ninguna pregunta todavía. Decirlo con el código
          // delante evita que se lea como un error de la app.
          return Aviso(
            icono: Icons.inbox_outlined,
            titulo: "Todavía no hay preguntas de este subtema",
            detalle:
                "${widget.codigo} está en el sílabo, pero el banco aún no lo "
                "cubre. La cobertura crece subtema a subtema.",
          );
        }

        return _PortadaSubtema(
          codigo: widget.codigo,
          nombre: widget.nombre,
          preguntas: preguntas,
          repositorio: widget.repositorio,
          sesion: widget.sesion,
        );
      },
    ),
  );
}

class _PortadaSubtema extends StatelessWidget {
  final String codigo;
  final String nombre;
  final List<Pregunta> preguntas;

  /// De paso hacia la tanda, igual que en [PantallaPracticaSubtema].
  final RepositorioPractica? repositorio;
  final Sesion? sesion;

  const _PortadaSubtema({
    required this.codigo,
    required this.nombre,
    required this.preguntas,
    required this.repositorio,
    required this.sesion,
  });

  @override
  Widget build(BuildContext context) {
    final n = preguntas.length;
    final curso = preguntas.first.cursoNombre;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        Text(
          nombre,
          style: context.textos.headlineSmall!.copyWith(
            fontWeight: FontWeight.w700,
            color: context.esquema.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "$codigo · $curso",
          style: context.textos.bodySmall!.copyWith(
            color: context.esquema.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          n == 1
              ? "Hay 1 pregunta de este subtema."
              : "Hay $n preguntas de este subtema.",
          style: context.textos.bodyMedium!.copyWith(
            color: context.esquema.onSurface,
          ),
        ),
        if (n < 3) ...[
          const SizedBox(height: 8),
          Text(
            "Son pocas: úsalas para comprobar si lo tienes, no para "
            "estudiarlo entero.",
            style: context.textos.bodySmall!.copyWith(
              color: context.esquema.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 22),
        FilledButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SesionPractica(
                titulo: nombre,
                preguntas: preguntas,
                etiquetaSalida: "Volver",
                repositorio: repositorio,
                sesion: sesion,
              ),
            ),
          ),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
          child: Text(n == 1 ? "Ver la pregunta" : "Empezar"),
        ),
      ],
    );
  }
}

class _Encabezado extends StatelessWidget {
  final Banco banco;
  const _Encabezado({required this.banco});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "${banco.total} preguntas resueltas y verificadas",
          style: context.textos.bodyMedium!.copyWith(
            color: context.esquema.onSurfaceVariant,
          ),
        ),
        if (banco.sonEjemplos)
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              "Estás viendo el banco de ejemplo: no hay archivos reales "
              "sincronizados.",
              style: context.textos.bodySmall!.copyWith(
                color: context.colores.aviso,
              ),
            ),
          ),
      ],
    ),
  );
}

/// La tanda: una pregunta a la vez, veredicto inmediato, resumen al final.
///
/// Réplica de `components/sesion-practica.tsx`. La diferencia que se nota es
/// que aquí **no hay modo anónimo**: en la web, un alumno sin cuenta practica
/// igual porque el servidor corrige con el banco completo. En el móvil la
/// clave no viaja (ver `datos/preguntas.dart`), así que el primer envío sin
/// sesión responde con el aviso de entrar en vez de una corrección inventada.
class SesionPractica extends StatefulWidget {
  final String titulo;
  final List<Pregunta> preguntas;

  /// Qué dice el botón del resumen. Cambia porque la misma tanda se abre desde
  /// Práctica (se vuelve a la lista de cursos) y desde Repaso (se vuelve al
  /// repaso, cuyo calendario acaba de moverse).
  final String etiquetaSalida;

  /// Repositorio y sesión inyectables, igual que en `PantallaHorario`.
  ///
  /// `RepositorioPractica()` y `Sesion()` resuelven `Supabase.instance.client`
  /// en su constructor, así que montar esta pantalla en un test lanzaba «You
  /// must initialize the supabase instance» antes de pintar nada. En
  /// producción nadie los pasa y se construyen aquí, igual que antes.
  final RepositorioPractica? repositorio;
  final Sesion? sesion;

  const SesionPractica({
    super.key,
    required this.titulo,
    required this.preguntas,
    this.etiquetaSalida = "Volver a los cursos",
    this.repositorio,
    this.sesion,
  });

  @override
  State<SesionPractica> createState() => _SesionPracticaState();
}

class _SesionPracticaState extends State<SesionPractica> {
  late final _repo = widget.repositorio ?? RepositorioPractica();
  late final _sesion = widget.sesion ?? Sesion();

  int _indice = 0;
  Letra? _marcada;
  Correccion? _correccion;
  bool _enviando = false;
  String? _error;

  int _aciertos = 0;
  bool _terminada = false;

  /// Cuándo se mostró la pregunta actual, para medir el tiempo que el RPC
  /// guarda en `respuestas.segundos`. Se reinicia en cada avance.
  DateTime _mostradaEn = DateTime.now();

  Pregunta get _pregunta => widget.preguntas[_indice];

  /// **Salir a mitad de tanda también la cierra.**
  ///
  /// `finalizar()` solo se llamaba al pasar de la última pregunta, y esa es la
  /// forma menos frecuente de terminar una práctica: lo normal es responder
  /// cinco de veinte y volver atrás. El intento quedaba abierto en `intentos`
  /// para siempre —nadie lo vuelve a tocar, porque la siguiente tanda
  /// construye un `RepositorioPractica` nuevo y abre otro—, así que sus
  /// totales nunca se consolidaban y la tabla acumulaba una fila huérfana por
  /// cada abandono. No era visible en ninguna pantalla, que es justo por lo
  /// que había durado.
  ///
  /// Va sin `await` porque `dispose` es síncrono, y sin `unawaited` porque el
  /// lint `unawaited_futures` solo mira dentro de funciones `async`. El fallo
  /// se traga a propósito: la pantalla ya no existe, no hay a quién avisar, y
  /// `finalizar_intento` es idempotente — la próxima vez que se cierre ese
  /// intento (o nunca) da igual. Lo que no puede es tirar una excepción sin
  /// capturar desde un `dispose`.
  @override
  void dispose() {
    _repo.finalizar().catchError((_) {});
    super.dispose();
  }

  Future<void> _responder() async {
    final marcada = _marcada;
    if (marcada == null || _correccion != null) return;

    setState(() {
      _enviando = true;
      _error = null;
    });

    try {
      final correccion = await _repo.responder(
        codigoPregunta: _pregunta.codigo,
        marcada: marcada,
        segundos: DateTime.now().difference(_mostradaEn).inSeconds,
      );
      if (!mounted) return;
      setState(() {
        _correccion = correccion;
        if (correccion.esCorrecta) _aciertos++;
      });
    } on ErrorPractica catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (e) {
      if (mounted) {
        setState(() => _error = "No se pudo enviar la respuesta. $e");
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _avanzar() async {
    if (_indice + 1 >= widget.preguntas.length) {
      // Cerrar el intento consolida el resumen del lado del servidor. Si falla
      // no se le arruina el resumen al alumno: ya respondió todo.
      try {
        await _repo.finalizar();
      } catch (_) {}
      if (mounted) setState(() => _terminada = true);
      return;
    }
    setState(() {
      _indice++;
      _marcada = null;
      _correccion = null;
      _error = null;
      _mostradaEn = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.preguntas.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.titulo)),
        body: const Aviso(
          icono: Icons.inbox_outlined,
          titulo: "Todavía no hay preguntas de este curso",
          detalle: "La cobertura del banco crece curso a curso.",
        ),
      );
    }

    if (_terminada) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.titulo)),
        body: _Resumen(
          aciertos: _aciertos,
          total: widget.preguntas.length,
          etiquetaSalida: widget.etiquetaSalida,
          alSalir: () => Navigator.of(context).pop(),
        ),
      );
    }

    final correccion = _correccion;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titulo, style: context.textos.bodyLarge),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_indice + 1) / widget.preguntas.length,
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
                "${_indice + 1} de ${widget.preguntas.length}",
                style: context.textos.labelMedium!.copyWith(
                  fontWeight: FontWeight.w600,
                  color: context.esquema.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              // `ellipsis` solo recorta si el `Text` tiene un ancho que
              // respetar. Suelto en un `Row` toma su ancho intrinseco y
              // desborda: los nombres largos de subtema —«Figuras literarias:
              // metafora, simil, hiperbole, anafora e hiperbaton»— sacaban la
              // franja amarilla en pantalla. `Expanded` le da el hueco que
              // sobra, y ahi si se recorta.
              Expanded(
                child: Text(
                  _pregunta.subtemaNombre,
                  textAlign: TextAlign.end,
                  style: context.textos.bodySmall!.copyWith(
                    color: context.esquema.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextoConFormulas(_pregunta.enunciado),
          if (_pregunta.imagen != null) ...[
            const SizedBox(height: 14),
            FiguraPregunta(figura: _pregunta.imagen!),
          ],
          const SizedBox(height: 18),

          for (final alt in _pregunta.alternativas)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _Alternativa(
                alternativa: alt,
                marcada: _marcada == alt.letra,
                correccion: correccion,
                alPulsar: correccion != null || _enviando
                    ? null
                    : () => setState(() => _marcada = alt.letra),
              ),
            ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Nota.error(texto: _error!),
            if (!_sesion.hayCuenta) ...[
              const SizedBox(height: 8),
              Text(
                "La app no guarda las respuestas correctas a propósito: si "
                "viajaran en el binario, cualquiera podría extraer el banco "
                "resuelto.",
                style: context.textos.bodySmall!.copyWith(
                  color: context.esquema.onSurfaceVariant,
                ),
              ),
            ],
          ],

          if (correccion != null) ...[
            const SizedBox(height: 16),
            _Veredicto(correccion: correccion),
            // El reporte solo aparece con un intento abierto, igual que en la
            // web: sin sesión no hay a quién atribuirlo, y la tabla exige
            // `perfil_id`.
            if (_repo.intentoId != null) ...[
              const SizedBox(height: 12),
              _Reporte(
                key: ValueKey(_pregunta.codigo),
                repositorio: _repo,
                codigoPregunta: _pregunta.codigo,
              ),
            ],
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: FilledButton(
            onPressed: _enviando
                ? null
                : correccion != null
                ? _avanzar
                : (_marcada == null ? null : _responder),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(
              _enviando
                  ? "Comprobando…"
                  : correccion != null
                  ? (_indice + 1 >= widget.preguntas.length
                        ? "Ver resumen"
                        : "Siguiente")
                  : "Comprobar",
            ),
          ),
        ),
      ),
    );
  }
}

class _Alternativa extends StatelessWidget {
  final Alternativa alternativa;
  final bool marcada;
  final Correccion? correccion;
  final VoidCallback? alPulsar;

  const _Alternativa({
    required this.alternativa,
    required this.marcada,
    required this.correccion,
    required this.alPulsar,
  });

  @override
  Widget build(BuildContext context) {
    final esClave = correccion?.clave == alternativa.letra;
    final falloAqui = correccion != null && marcada && !esClave;

    // Corregida la pregunta, el color deja de significar "lo que marqué" y
    // pasa a significar "cuál era". El verde marca siempre la clave, la marque
    // el alumno o no, para que aprenda algo aunque haya fallado.
    final (borde, fondo) = switch ((correccion, esClave, falloAqui)) {
      (null, _, _) =>
        marcada
            ? (context.esquema.primary, context.esquema.secondaryContainer)
            : (
                context.esquema.outlineVariant,
                context.esquema.surfaceContainerLowest,
              ),
      (_, true, _) => (context.colores.exito, context.colores.exitoContenedor),
      // `error`, no la marca. Con el granate eran el mismo color, así que la
      // alternativa fallada se pintaba con el color de la app: el alumno veía
      // su error del mismo tono que el botón de «Empezar».
      (_, _, true) => (context.esquema.error, context.esquema.errorContainer),
      _ => (
        context.esquema.outlineVariant,
        context.esquema.surfaceContainerLowest,
      ),
    };

    return Material(
      color: fondo,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: alPulsar,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(
              color: borde,
              width: marcada || esClave ? 1.6 : 1,
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
                  color: borde == context.esquema.outlineVariant
                      ? context.esquema.surfaceContainerLow
                      : borde,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  alternativa.letra.etiqueta,
                  style: context.textos.labelMedium!.copyWith(
                    fontWeight: FontWeight.w700,
                    color: borde == context.esquema.outlineVariant
                        ? context.esquema.onSurfaceVariant
                        : context.esquema.onPrimary,
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
}

class _Veredicto extends StatelessWidget {
  final Correccion correccion;
  const _Veredicto({required this.correccion});

  @override
  Widget build(BuildContext context) {
    final bien = correccion.esCorrecta;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        // Fallar tiene su propio color, y no es el de la marca.
        // `secondaryContainer` sale del mismo tono que la marca —lila con la
        // semilla indigo—, asi que la caja de «la respuesta era D» se veia
        // igual de amable que un acierto, con el titulo en rojo flotando
        // encima. Aciertos en verde, fallos en rojo: es la unica senal que el
        // alumno lee de un vistazo.
        color: bien
            ? context.colores.exitoContenedor
            : context.esquema.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                bien ? Icons.check_circle_outline : Icons.cancel_outlined,
                size: 20,
                color: bien ? context.colores.exito : context.esquema.error,
              ),
              const SizedBox(width: 8),
              Text(
                bien
                    ? "Correcta"
                    : "La respuesta era ${correccion.clave.etiqueta}",
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: bien ? context.colores.exito : context.esquema.error,
                ),
              ),
            ],
          ),
          if (correccion.explicacion case final texto?
              when texto.isNotEmpty) ...[
            const SizedBox(height: 12),
            TextoConFormulas(
              texto,
              // Negro en las dos cajas. El rojo es del veredicto —«La
              // respuesta era D»—, no de la explicacion: un parrafo entero en
              // rojo se lee como si todo lo que dice estuviera mal, que es
              // justo lo contrario de lo que hace ahi.
              estilo: context.textos.bodyMedium!.copyWith(
                color: context.esquema.onSurface,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Resumen extends StatelessWidget {
  final int aciertos;
  final int total;
  final String etiquetaSalida;
  final VoidCallback alSalir;

  const _Resumen({
    required this.aciertos,
    required this.total,
    required this.etiquetaSalida,
    required this.alSalir,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0 : (aciertos * 100 / total).round();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "$pct %",
              style: context.textos.displayMedium!.copyWith(
                fontWeight: FontWeight.w800,
                color: context.esquema.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "$aciertos de $total correctas",
              style: context.textos.bodyLarge!.copyWith(
                color: context.esquema.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: alSalir,
              style: FilledButton.styleFrom(minimumSize: const Size(200, 46)),
              child: Text(etiquetaSalida),
            ),
          ],
        ),
      ),
    );
  }
}

/// Una figura de pregunta: pocas en el banco (1 de 395 hoy), pero cada una
/// puede ser la diferencia entre poder resolver el ejercicio o no.
///
/// Carga de verdad desde `Config.urlFiguraPregunta` — ver `figura_red.dart`
/// para qué pasa si la imagen no llega.
class FiguraPregunta extends StatelessWidget {
  final Figura figura;
  const FiguraPregunta({super.key, required this.figura});

  @override
  Widget build(BuildContext context) => FiguraRed(
    url: Config.urlFiguraPregunta(figura.src),
    alt: figura.alt,
    proporcion: figura.proporcion,
    grande: true,
  );
}

/// «Reportar un error en esta pregunta».
///
/// Puerto del bloque de reporte de `components/sesion-practica.tsx`, con sus
/// mismas tres fases: enlace discreto → formulario → acuse. Va debajo del
/// veredicto y no junto al enunciado a propósito: se reporta una pregunta
/// cuando algo no cuadra al ver la respuesta, no antes de intentarla.
///
/// La `Key` por código de pregunta lo reinicia al avanzar; sin ella, el
/// formulario abierto en la pregunta 3 seguiría abierto en la 4, con el
/// detalle ya escrito apuntando a otra pregunta.
class _Reporte extends StatefulWidget {
  final RepositorioPractica repositorio;
  final String codigoPregunta;

  const _Reporte({
    super.key,
    required this.repositorio,
    required this.codigoPregunta,
  });

  @override
  State<_Reporte> createState() => _ReporteState();
}

enum _FaseReporte { cerrado, abierto, enviado, yaExistia }

class _ReporteState extends State<_Reporte> {
  _FaseReporte _fase = _FaseReporte.cerrado;
  String _motivo = RepositorioPractica.motivosReporte.first;
  final _detalle = TextEditingController();
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _detalle.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final yaExistia = await widget.repositorio.reportar(
        codigoPregunta: widget.codigoPregunta,
        motivo: _motivo,
        detalle: _detalle.text,
      );
      if (!mounted) return;
      setState(
        () => _fase = yaExistia ? _FaseReporte.yaExistia : _FaseReporte.enviado,
      );
    } catch (_) {
      // Mismo mensaje que la web: al alumno no le sirve el detalle técnico,
      // le sirve saber que puede reintentar.
      if (mounted) {
        setState(
          () => _error = "No se pudo enviar el reporte. Inténtalo de nuevo.",
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) => switch (_fase) {
    _FaseReporte.cerrado => Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => setState(() => _fase = _FaseReporte.abierto),
        icon: const Icon(Icons.flag_outlined, size: 15),
        label: const Text("Reportar un error en esta pregunta"),
        style: TextButton.styleFrom(
          foregroundColor: context.esquema.onSurfaceVariant,
          textStyle: context.textos.bodySmall,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
    ),

    _FaseReporte.abierto => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.esquema.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.esquema.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _motivo,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: "Motivo",
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final m in RepositorioPractica.motivosReporte)
                DropdownMenuItem(value: m, child: Text(m)),
            ],
            onChanged: _enviando
                ? null
                : (v) => setState(() => _motivo = v ?? _motivo),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _detalle,
            enabled: !_enviando,
            minLines: 2,
            maxLines: 4,
            // Mismo tope que el `check` de la tabla. Sin él, el alumno
            // escribe 1 200 caracteres y el error solo aparece al enviar,
            // con el texto ya escrito.
            maxLength: 1000,
            decoration: const InputDecoration(
              labelText: "Detalles (opcional)",
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          if (_error case final e?) ...[
            const SizedBox(height: 4),
            Text(
              e,
              style: context.textos.bodySmall!.copyWith(
                color: context.colores.aviso,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton(
                onPressed: _enviando ? null : _enviar,
                child: Text(_enviando ? "Enviando…" : "Enviar reporte"),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _enviando
                    ? null
                    : () => setState(() => _fase = _FaseReporte.cerrado),
                child: const Text("Cancelar"),
              ),
            ],
          ),
        ],
      ),
    ),

    // Que ya hubiera un reporte abierto de esta pregunta no es un fallo: el
    // índice único parcial de la tabla lo impide a propósito, y el alumno
    // merece saber que su reporte sigue en la cola, no un error rojo.
    _FaseReporte.enviado || _FaseReporte.yaExistia => Row(
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 16,
          color: context.colores.exito,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _fase == _FaseReporte.yaExistia
                ? "Ya habías reportado esta pregunta: sigue en la cola."
                : "Reporte enviado. ¡Gracias por ayudar a mejorar!",
            style: context.textos.bodyMedium!.copyWith(
              color: context.colores.exito,
            ),
          ),
        ),
      ],
    ),
  };
}
