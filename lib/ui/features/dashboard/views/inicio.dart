import "dart:async";

import "package:flutter/material.dart";
import "package:matr_u/data/models/horario.dart";
import "package:matr_u/data/models/progreso.dart";
import "package:matr_u/data/models/repaso.dart";
import "package:matr_u/data/models/sesion.dart";
import "package:matr_u/main.dart" show Armazon;
import "package:matr_u/ui/core/theme/tema.dart";
import "package:matr_u/ui/core/widgets/aviso.dart";
import "package:matr_u/ui/core/widgets/ios.dart";
import "package:matr_u/ui/features/auth/views/entrar.dart";
import "package:matr_u/ui/features/practice/views/practica_adaptativa.dart";
import "package:matr_u/ui/features/schedule/views/horario.dart";
import "package:matr_u/ui/features/study/views/buscar.dart";
import "package:supabase_flutter/supabase_flutter.dart" show AuthState;

/// `/` — la portada, que hace de panel del alumno.
///
/// Réplica de `src/app/page.tsx`. En la web tampoco vive en la barra móvil
/// —el header con el logo que llevaría ahí está oculto en pantallas
/// pequeñas—, así que en la práctica se ve al abrir la app por primera vez y
/// se vuelve por un enlace explícito después.
///
/// **Está montada como una pantalla de ajustes de iOS**: cabecera con *Large
/// Title* y, debajo, grupos de tarjeta blanca sobre fondo gris. No es
/// decoración — un panel es exactamente eso: bloques de cosas relacionadas que
/// hay que poder recorrer con el pulgar sin leerlo todo.
///
/// **Las cifras que enseña no son las de un expediente.** No hay «cursos
/// activos» ni «promedio» ni «próximas entregas»: esta app no es un aula
/// virtual, es preparación para un examen de admisión. Lo que mueve el estudio
/// aquí es el acierto por subtema, la constancia y qué toca repasar hoy, y eso
/// es lo que se pinta.
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
  StreamSubscription<AuthState>? _escucha;

  /// De quién es el panel que hay en pantalla, o `null` si no hay sesión.
  String? _duenoDelPanel;

  @override
  void initState() {
    super.initState();
    if (_sesion.hayCuenta) {
      _carga = _pedir();
      _duenoDelPanel = _sesion.usuario!.id;
    }

    // **Sin esto, entrar no cambiaba nada de esta pantalla.**
    //
    // La portada leia `hayCuenta` una sola vez, aqui, y `PantallaEntrar` se
    // abre ENCIMA de ella: al cerrarse tras un acceso correcto, esta seguia
    // pintando «Crear cuenta o entrar» con la sesion ya iniciada. Habia que
    // salir y volver para que se enterara.
    //
    // Escuchar el flujo de auth lo cubre entero —entrar, salir, y la sesion
    // temporal del enlace de recuperacion— y no solo el caso del boton, que es
    // lo que arreglaria un `await` sobre el `push`.
    _escucha = _sesion.cambios.listen((_) {
      if (!mounted) return;

      // Solo cuando cambia DE QUIEN es la sesion.
      //
      // El flujo emite mucho mas que entrar y salir: al suscribirse suelta ya
      // un `initialSession`, y despues un `tokenRefreshed` cada hora. Sin este
      // filtro, abrir la app con sesion pedia el panel dos veces —seis
      // peticiones por duplicado— y el `Future` que quedaba huerfano llegaba
      // con su error a nadie, que en depuracion es un error rojo.
      final ahora = _sesion.usuario?.id;
      if (ahora == _duenoDelPanel) return;
      _duenoDelPanel = ahora;

      // La peticion se arma FUERA de `setState` y el cuerpo va entre llaves:
      // con flecha, un `setState` que asigna un `Future` lo DEVUELVE, y
      // Flutter lo rechaza en tiempo de ejecucion.
      final nueva = ahora == null ? null : _pedir();
      setState(() {
        _carga = nueva;
      });
    });
  }

  @override
  void dispose() {
    _escucha?.cancel();
    super.dispose();
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

    // Las seis a la vez: ninguna depende de otra, y encadenarlas sumaba seis
    // latencias antes de que la portada enseñara nada. Ver la nota equivalente
    // en `progreso.dart`.
    final resultados = await Future.wait([
      progreso.diagnostico(),
      progreso.racha(),
      repasos.resumen(),
      horarioRepo.obtener(),
      progreso.cursosDesatendidos(),
      progreso.perfil(),
    ]);

    final diagnostico = resultados[0] as Diagnostico;
    final racha = resultados[1] as Racha?;
    final resumenRepasos = resultados[2] as ResumenRepasos?;
    final horario = resultados[3] as List<BloqueHorario>;
    final desatendidos = resultados[4] as List<CursoDesatendido>;
    final perfil = resultados[5] as Perfil?;

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
      perfil: perfil,
    );
  }

  void _irAPestana(int destino) => Navigator.of(context).pushReplacement(
    MaterialPageRoute(builder: (_) => Armazon(destinoInicial: destino)),
  );

  void _abrir(Widget pantalla) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => pantalla));

  /// Los seis accesos, como filas de una lista agrupada.
  ///
  /// **Eran una rejilla de baldosas y ahora son filas**, y se gana en dos
  /// cosas: cada una puede llevar una frase entera de explicación sin partirse
  /// en cuatro líneas —que era el desborde documentado de la rejilla con la
  /// letra del sistema al máximo—, y la lista crece sin que haya que decidir
  /// qué hacer con un número impar de elementos. El icono en pastilla de color
  /// es lo que permite distinguirlas de un vistazo sin leer.
  Widget _accesos(BuildContext context) => GrupoInset(
    titulo: "Ir a",
    sangriaSeparador: 58,
    filas: [
      FilaInset(
        icono: Icons.edit_outlined,
        colorIcono: context.esquema.primary,
        titulo: "Practicar",
        subtitulo: "Preguntas resueltas y verificadas",
        onTap: () => _irAPestana(2),
      ),
      FilaInset(
        icono: Icons.replay_outlined,
        colorIcono: context.colores.exito,
        titulo: "Repaso",
        subtitulo: "Lo que toca hoy",
        onTap: () => _irAPestana(0),
      ),
      FilaInset(
        icono: Icons.adjust_outlined,
        colorIcono: context.colores.aviso,
        titulo: "Adaptativa",
        subtitulo: "Tus puntos flojos, elegidos por ti",
        onTap: () => _abrir(const AdaptativaConBarra()),
      ),
      FilaInset(
        icono: Icons.menu_book_outlined,
        colorIcono: context.esquema.primary,
        titulo: "Teoría",
        subtitulo: "Curso por curso, y sin conexión",
        onTap: () => _irAPestana(1),
      ),
      FilaInset(
        icono: Icons.timer_outlined,
        colorIcono: context.esquema.error,
        titulo: "Simulacros",
        subtitulo: "Cronometrados, como el de verdad",
        onTap: () => _irAPestana(3),
      ),
      FilaInset(
        icono: Icons.search,
        colorIcono: context.colores.grisSutil,
        titulo: "Buscar",
        subtitulo: "Por nombre o código de subtema",
        onTap: () => _abrir(const PantallaBuscar()),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final hayCuenta = _sesion.hayCuenta;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const SizedBox(height: 8),

            // ---- Cabecera -------------------------------------------------
            if (!hayCuenta)
              const TituloGrande(
                texto: "Matrix U",
                subtitulo: "El examen de la UNSA, entero y ordenado.",
              )
            else
              FutureBuilder<_PanelPersonal>(
                future: _carga,
                builder: (context, snap) {
                  // Si el panel falla, la cabecera NO falla con el: se queda
                  // sin nombre y ya. El aviso de que algo no cargo lo da el
                  // bloque de abajo, una vez, y no dos.
                  if (snap.hasError) return const _Saludo(perfil: null);
                  return _Saludo(perfil: snap.data?.perfil);
                },
              ),

            const SizedBox(height: 8),

            if (!hayCuenta) ...[
              _SinCuenta(
                onEntrar: () => _abrir(
                  Scaffold(
                    appBar: AppBar(title: const Text("Acceso")),
                    body: Builder(
                      builder: (ctx) => PantallaEntrar(
                        alEntrar: () => Navigator.of(ctx).pop(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ] else ...[
              FutureBuilder<_PanelPersonal>(
                future: _carga,
                builder: (context, snap) {
                  // Callarse aquí sería lo peor: el alumno con sesión sabe que
                  // su panel existe —lo vio ayer— y verlo desaparecer sin una
                  // palabra se lee como que perdió la racha, no como que el
                  // servidor no contestó.
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Aviso(
                        icono: Icons.cloud_off_outlined,
                        titulo: "No se pudo cargar tu panel",
                        detalle:
                            "Tu racha, tus repasos y tu diagnóstico se "
                            "calculan en el servidor, y ahora mismo no "
                            "responde.",
                        accion: ("Reintentar", _recargarPanel),
                        compacto: true,
                      ),
                    );
                  }
                  // Mientras carga no va un spinner: el panel entra debajo de
                  // la cabecera, que ya es contenido, y un giro ahí solo hace
                  // saltar todo lo de abajo cuando resuelve.
                  if (!snap.hasData) return const SizedBox(height: 8);
                  return _PanelPersonalVista(
                    datos: snap.data!,
                    alAbrirHorario: () => _abrir(const HorarioConBarra()),
                    alAbrirAdaptativa: () => _abrir(const AdaptativaConBarra()),
                  );
                },
              ),
              const SizedBox(height: 24),
            ],

            _accesos(context),
          ],
        ),
      ),
    );
  }
}

/// La cabecera con sesión: saludo, nombre e iniciales.
///
/// El saludo cambia con la hora porque una app de estudio se abre a las siete
/// de la mañana y a las once de la noche, y decir «buenos días» a medianoche
/// es de las cosas que delatan que nadie lo miró.
class _Saludo extends StatelessWidget {
  final Perfil? perfil;
  const _Saludo({required this.perfil});

  String get _momento {
    final h = DateTime.now().hour;
    if (h < 6) return "Buenas noches";
    if (h < 13) return "Buenos días";
    if (h < 20) return "Buenas tardes";
    return "Buenas noches";
  }

  @override
  Widget build(BuildContext context) {
    final nombre = perfil?.nombre?.trim();
    final primero = (nombre == null || nombre.isEmpty)
        ? null
        : nombre.split(RegExp(r"\s+")).first;

    return TituloGrande(
      texto: primero == null ? "Matrix U" : "$_momento,\n$primero",
      subtitulo: primero == null
          ? "El examen de la UNSA, entero y ordenado."
          : null,
      alFinal: AvatarIniciales(nombre: nombre, tamano: 44),
    );
  }
}

/// La invitación a registrarse, para quien llega sin cuenta.
class _SinCuenta extends StatelessWidget {
  final VoidCallback onEntrar;
  const _SinCuenta({required this.onEntrar});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.esquema.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(radioTarjeta),
        boxShadow: sombraTarjeta(Theme.of(context).brightness),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Con una cuenta gratis guardas tu progreso por subtema y puedes "
              "programar un horario de estudio que te avisa cuando toca.",
              style: context.textos.bodyLarge,
            ),
            const SizedBox(height: 16),
            BotonPrincipal(
              texto: "Crear cuenta o entrar →",
              onPressed: onEntrar,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Lo que ve solo quien tiene sesión.
class _PanelPersonal {
  final Diagnostico diagnostico;
  final Racha? racha;
  final ResumenRepasos? repasos;
  final ({BloqueHorario bloque, DateTime cuando})? proximo;
  final CursoDesatendido? descuidado;
  final Perfil? perfil;

  const _PanelPersonal({
    required this.diagnostico,
    required this.racha,
    required this.repasos,
    required this.proximo,
    required this.descuidado,
    required this.perfil,
  });
}

class _PanelPersonalVista extends StatelessWidget {
  final _PanelPersonal datos;
  final VoidCallback alAbrirHorario;
  final VoidCallback alAbrirAdaptativa;

  const _PanelPersonalVista({
    required this.datos,
    required this.alAbrirHorario,
    required this.alAbrirAdaptativa,
  });

  @override
  Widget build(BuildContext context) {
    final racha = datos.racha;
    final repasos = datos.repasos;
    final diag = datos.diagnostico;
    final pendientes = repasos?.pendientesHoy ?? 0;
    final dias = racha?.diasActual ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---- Las tres cifras ---------------------------------------------
        //
        // Acierto, constancia y lo pendiente de hoy. El acierto sale como «—»
        // y no como «0 %» cuando no hay respuestas: un cero medido y un
        // «todavía nada» son cosas distintas, y esta app no rellena huecos.
        //
        // **Con las tres a cero no se pinta nada.** A quien abre la app por
        // primera vez, tres ceros en fila no le informan: le dicen que va mal
        // antes de haber empezado. Cuando haya algo que contar, aparecen.
        if (!diag.vacio || dias > 0 || pendientes > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // `IntrinsicHeight` para que las tres midan lo mismo: «repasos
            // para hoy» parte en dos lineas y sin esto la tercera cuelga por
            // debajo. Tres cifras del mismo rango tienen que verse del mismo
            // peso.
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _Cifra(
                      valor: diag.vacio ? "—" : "${diag.aciertoGlobal} %",
                      etiqueta: "Acierto",
                      color: context.esquema.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Cifra(
                      valor: "$dias",
                      etiqueta: dias == 1 ? "día seguido" : "días seguidos",
                      color: context.colores.exito,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Cifra(
                      valor: "$pendientes",
                      etiqueta: pendientes == 1
                          ? "repaso para hoy"
                          : "repasos para hoy",
                      color: context.colores.aviso,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ---- Lo que toca --------------------------------------------------
        const SizedBox(height: 20),
        GrupoInset(
          titulo: "Lo que toca",
          sangriaSeparador: 58,
          filas: [
            if (racha != null && racha.arrancada && !racha.estudiadoHoy)
              FilaInset(
                icono: Icons.local_fire_department_outlined,
                colorIcono: context.colores.aviso,
                titulo: "Te falta hoy",
                subtitulo:
                    "Llevas ${racha.diasActual} días seguidos: responde algo "
                    "para no cortarla.",
                onTap: alAbrirAdaptativa,
              ),
            if (datos.descuidado case final c?)
              FilaInset(
                icono: Icons.trending_down,
                colorIcono: context.esquema.error,
                titulo: c.nombre,
                subtitulo:
                    "${c.porcentaje} % de acierto y ${c.diasSinPracticar} "
                    "días sin tocarlo.",
                onTap: alAbrirAdaptativa,
              ),
            if (datos.proximo case final p?)
              FilaInset(
                icono: Icons.schedule,
                colorIcono: context.esquema.primary,
                titulo: p.bloque.cursoNombre,
                subtitulo:
                    "${diasSemana[p.bloque.diaSemana]} a las "
                    "${formatearHora(p.bloque.horaInicio)}",
                onTap: alAbrirHorario,
              )
            else
              FilaInset(
                icono: Icons.schedule,
                colorIcono: context.esquema.primary,
                titulo: "Programa un horario",
                subtitulo: "Te avisamos cuando toque estudiar.",
                onTap: alAbrirHorario,
              ),
          ],
        ),
      ],
    );
  }
}

/// Una cifra grande con su etiqueta debajo, dentro de una tarjeta.
///
/// Es la pieza de resumen de iOS: el número manda y la palabra solo lo
/// clasifica. Por eso la etiqueta va en gris pequeño y no compite.
class _Cifra extends StatelessWidget {
  final String valor;
  final String etiqueta;
  final Color color;

  const _Cifra({
    required this.valor,
    required this.etiqueta,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.esquema.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(radioTarjeta),
      boxShadow: sombraTarjeta(Theme.of(context).brightness),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      child: Column(
        children: [
          FittedBox(
            child: Text(
              valor,
              maxLines: 1,
              style: context.textos.displaySmall?.copyWith(color: color),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            etiqueta,
            textAlign: TextAlign.center,
            style: context.textos.bodySmall,
          ),
        ],
      ),
    ),
  );
}
