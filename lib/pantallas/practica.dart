import "package:flutter/material.dart";

import "../config.dart";
import "../datos/practica.dart";
import "../datos/preguntas.dart";
import "../datos/sesion.dart";
import "../matematicas/formula.dart";
import "../tema.dart";
import "figura_red.dart";
import "practica_adaptativa.dart";

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
          return _Aviso(
            icono: Icons.error_outline,
            titulo: "No se pudo cargar el banco",
            detalle: "${snap.error}\n\n¿Corriste `node tool/sincronizar-datos.mjs`?",
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
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Paleta.texto,
                  ),
                ),
                subtitle: Text(
                  "${curso.total} ${curso.total == 1 ? "pregunta" : "preguntas"}",
                  style: const TextStyle(color: Paleta.textoTenue),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Paleta.textoTenue,
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
    color: Paleta.acentoSuave,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const _AdaptativaConAppBar()),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Paleta.acento, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Práctica adaptativa",
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Paleta.acento,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    "Elegimos las preguntas por ti: primero donde peor vas",
                    style: TextStyle(fontSize: 12, color: Paleta.acento),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Paleta.acento),
          ],
        ),
      ),
    ),
  );
}

class _AdaptativaConAppBar extends StatelessWidget {
  const _AdaptativaConAppBar();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("Práctica adaptativa")),
    body: const PantallaPracticaAdaptativa(),
  );
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
          style: const TextStyle(
            fontSize: 13,
            color: Paleta.textoSuave,
            height: 1.5,
          ),
        ),
        if (banco.sonEjemplos)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              "Estás viendo el banco de ejemplo: no hay archivos reales "
              "sincronizados.",
              style: TextStyle(fontSize: 12.5, color: Paleta.aviso),
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

  const SesionPractica({
    super.key,
    required this.titulo,
    required this.preguntas,
    this.etiquetaSalida = "Volver a los cursos",
  });

  @override
  State<SesionPractica> createState() => _SesionPracticaState();
}

class _SesionPracticaState extends State<SesionPractica> {
  final _repo = RepositorioPractica();
  final _sesion = Sesion();

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
      if (mounted) setState(() => _error = "No se pudo enviar la respuesta. $e");
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
        body: const _Aviso(
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
        title: Text(widget.titulo, style: const TextStyle(fontSize: 16)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_indice + 1) / widget.preguntas.length,
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
                "${_indice + 1} de ${widget.preguntas.length}",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Paleta.textoTenue,
                ),
              ),
              Text(
                _pregunta.subtemaNombre,
                style: const TextStyle(fontSize: 12, color: Paleta.textoTenue),
                overflow: TextOverflow.ellipsis,
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
            _Nota(texto: _error!, color: Paleta.acento, fondo: Paleta.acentoSuave),
            if (!_sesion.hayCuenta) ...[
              const SizedBox(height: 8),
              Text(
                "La app no guarda las respuestas correctas a propósito: si "
                "viajaran en el binario, cualquiera podría extraer el banco "
                "resuelto.",
                style: const TextStyle(
                  fontSize: 12,
                  color: Paleta.textoSuave,
                  height: 1.45,
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
      (null, _, _) => marcada
          ? (Paleta.acento, Paleta.acentoSuave)
          : (Paleta.borde, Paleta.superficieAlta),
      (_, true, _) => (Paleta.exito, Paleta.exitoSuave),
      (_, _, true) => (Paleta.acento, Paleta.acentoSuave),
      _ => (Paleta.borde, Paleta.superficieAlta),
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
            border: Border.all(color: borde, width: marcada || esClave ? 1.6 : 1),
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
                  color: borde == Paleta.borde ? Paleta.superficie : borde,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  alternativa.letra.etiqueta,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: borde == Paleta.borde
                        ? Paleta.textoSuave
                        : Paleta.acentoContraste,
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
        color: bien ? Paleta.exitoSuave : Paleta.acentoSuave,
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
                color: bien ? Paleta.exito : Paleta.acento,
              ),
              const SizedBox(width: 8),
              Text(
                bien
                    ? "Correcta"
                    : "La respuesta era ${correccion.clave.etiqueta}",
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: bien ? Paleta.exito : Paleta.acento,
                ),
              ),
            ],
          ),
          if (correccion.explicacion case final texto?
              when texto.isNotEmpty) ...[
            const SizedBox(height: 12),
            TextoConFormulas(
              texto,
              estilo: const TextStyle(
                fontSize: 14.5,
                height: 1.55,
                color: Paleta.texto,
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
              style: const TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w800,
                color: Paleta.acento,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "$aciertos de $total correctas",
              style: const TextStyle(fontSize: 15, color: Paleta.textoSuave),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: alSalir,
              style: FilledButton.styleFrom(
                minimumSize: const Size(200, 46),
              ),
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

class _Nota extends StatelessWidget {
  final String texto;
  final Color color;
  final Color fondo;
  const _Nota({required this.texto, required this.color, required this.fondo});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: fondo,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      texto,
      style: TextStyle(fontSize: 13, height: 1.45, color: color),
    ),
  );
}

class _Aviso extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String detalle;

  const _Aviso({
    required this.icono,
    required this.titulo,
    required this.detalle,
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
              color: Paleta.texto,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            detalle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Paleta.textoSuave, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    ),
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
        () => _fase =
            yaExistia ? _FaseReporte.yaExistia : _FaseReporte.enviado,
      );
    } catch (_) {
      // Mismo mensaje que la web: al alumno no le sirve el detalle técnico,
      // le sirve saber que puede reintentar.
      if (mounted) {
        setState(() => _error = "No se pudo enviar el reporte. Inténtalo de nuevo.");
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
          foregroundColor: Paleta.textoTenue,
          textStyle: const TextStyle(fontSize: 12.5),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
    ),

    _FaseReporte.abierto => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Paleta.superficieAlta,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Paleta.borde),
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
              style: const TextStyle(fontSize: 12.5, color: Paleta.aviso),
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
        const Icon(Icons.check_circle_outline, size: 16, color: Paleta.exito),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _fase == _FaseReporte.yaExistia
                ? "Ya habías reportado esta pregunta: sigue en la cola."
                : "Reporte enviado. ¡Gracias por ayudar a mejorar!",
            style: const TextStyle(fontSize: 13, color: Paleta.exito),
          ),
        ),
      ],
    ),
  };
}
