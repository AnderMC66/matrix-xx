import "dart:async";

import "package:flutter/material.dart" show TimeOfDay;

import "package:matr_u/data/repositories/horario.dart";
import "package:matr_u/data/repositories/sesion.dart";
import "package:matr_u/data/repositories/temario.dart";
import "package:matr_u/domain/models/horario.dart";
import "package:matr_u/domain/models/temario.dart";
import "package:matr_u/ui/core/vista_modelo.dart";

/// El modelo de `/horario`.
///
/// Es el que más estado lleva de la app, y por eso el que más se nota al
/// sacarlo de la vista: dieciocho `setState` repartidos entre la carga, el
/// formulario, el guardado, el borrado y el reloj de avisos.
///
/// **No usa [Estado] para todo.** El bloque de carga inicial sí —o hay cursos
/// y horario, o hay un fallo, o se está esperando—, pero el formulario y los
/// dos indicadores de «guardando» y «eliminando» son estado plano: no tienen
/// ni fallo ni espera propios que la vista deba distinguir, solo un `bool`.
class ModeloHorario extends VistaModelo {
  // Perezosos: resuelven `Supabase.instance.client`. Ver la nota en
  // `ModeloInicio`.
  late final RepositorioHorario _repo = _repoDado ?? RepositorioHorario();
  late final RepositorioTemario _temario = _temarioDado ?? RepositorioTemario();
  late final Sesion _sesion = _sesionDada ?? Sesion();

  final RepositorioHorario? _repoDado;
  final RepositorioTemario? _temarioDado;
  final Sesion? _sesionDada;

  ModeloHorario({
    RepositorioHorario? repositorio,
    RepositorioTemario? temario,
    Sesion? sesion,
  }) : _repoDado = repositorio,
       _temarioDado = temario,
       _sesionDada = sesion;

  bool get hayCuenta => _sesion.hayCuenta;

  // ── La carga ─────────────────────────────────────────────────────────────

  List<Curso> _cursos = const [];
  List<Curso> get cursos => _cursos;

  List<BloqueHorario> _horario = const [];
  List<BloqueHorario> get horario => _horario;

  bool _cargando = true;
  bool get cargando => _cargando;

  String? _errorCarga;
  String? get errorCarga => _errorCarga;

  // ── El formulario ────────────────────────────────────────────────────────

  String? _cursoElegido;
  String? get cursoElegido => _cursoElegido;

  int _dia = 1;
  int get dia => _dia;

  TimeOfDay _hora = const TimeOfDay(hour: 17, minute: 0);
  TimeOfDay get hora => _hora;

  int _duracion = 60;
  int get duracion => _duracion;

  // ── Lo que está en vuelo ─────────────────────────────────────────────────

  bool _guardando = false;
  bool get guardando => _guardando;

  int? _eliminandoId;
  int? get eliminandoId => _eliminandoId;

  String? _error;
  String? get error => _error;

  // ── El aviso de que toca estudiar ────────────────────────────────────────

  Timer? _reloj;
  ({BloqueHorario bloque, Duration faltan})? _proximoAviso;
  ({BloqueHorario bloque, Duration faltan})? get proximoAviso => _proximoAviso;

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  Future<void> cargar() async {
    if (!hayCuenta) return;
    // Limpiar el fallo anterior es parte de recargar, no un detalle: sin esto,
    // «Reintentar» pedia bien el horario y seguia enseñando el aviso de error
    // encima. Lo hacia el `setState` del boton, que ya no existe.
    _errorCarga = null;
    _cargando = true;
    avisar();
    try {
      final temario = await _temario.cargar();
      final horario = await _repo.obtener();
      _cursos = temario.cursos;
      _cursoElegido = _cursos.firstOrNull?.codigo;
      _horario = horario;
      _cargando = false;
      avisar();
      _arrancarReloj();
    } on Object catch (e) {
      _errorCarga = "$e";
      avisar();
    }
  }

  /// Revisa cada 30 segundos si algún bloque empieza dentro de los próximos
  /// 5 minutos, mientras esta pantalla esté abierta — exactamente lo que
  /// hacía el temporizador de `notificador-horario.tsx` en el navegador.
  void _arrancarReloj() {
    void revisar() {
      final proximo = proximoBloque(_horario, DateTime.now());
      if (proximo == null) {
        _proximoAviso = null;
        avisar();
        return;
      }
      final faltan = proximo.cuando.difference(DateTime.now());
      _proximoAviso = faltan <= const Duration(minutes: 5)
          ? (bloque: proximo.bloque, faltan: faltan)
          : null;
      avisar();
    }

    revisar();
    _reloj = Timer.periodic(const Duration(seconds: 30), (_) => revisar());
  }

  void elegirCurso(String? codigo) {
    _cursoElegido = codigo;
    avisar();
  }

  void elegirDia(int valor) {
    _dia = valor;
    avisar();
  }

  void elegirHora(TimeOfDay valor) {
    _hora = valor;
    avisar();
  }

  void elegirDuracion(int minutos) {
    _duracion = minutos;
    avisar();
  }

  Future<void> agregar() async {
    final codigo = _cursoElegido;
    if (codigo == null) return;

    _guardando = true;
    _error = null;
    avisar();

    final horaTexto =
        "${_hora.hour.toString().padLeft(2, "0")}:"
        "${_hora.minute.toString().padLeft(2, "0")}:00";

    try {
      final id = await _repo.crear(
        cursoCodigo: codigo,
        diaSemana: _dia,
        horaInicio: horaTexto,
        duracionMinutos: _duracion,
      );
      final curso = _cursos.firstWhere((c) => c.codigo == codigo);
      _horario =
          [
            ..._horario,
            BloqueHorario(
              // El id REAL que devolvió Postgres. Antes aquí iba uno negativo
              // «provisional hasta la próxima recarga», y esa recarga no
              // existe. Con el id inventado, borrar un bloque recién creado
              // mandaba el `delete` contra una fila que no existe —PostgREST
              // no se queja— así que desaparecía de la pantalla y seguía en la
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
    } on ErrorHorario catch (e) {
      _error = e.mensaje;
    } on Object catch (e) {
      _error = "No se pudo guardar el bloque. $e";
    } finally {
      _guardando = false;
      avisar();
    }
  }

  Future<void> eliminar(BloqueHorario b) async {
    _error = null;
    _eliminandoId = b.id;
    avisar();
    try {
      await _repo.eliminar(b.id);
      _horario = _horario.where((x) => x.id != b.id).toList();
    } on Object catch (e) {
      _error = "No se pudo eliminar el bloque. $e";
    } finally {
      _eliminandoId = null;
      avisar();
    }
  }
}
