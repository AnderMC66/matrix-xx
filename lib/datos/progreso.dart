import "package:supabase_flutter/supabase_flutter.dart";

/// Puerto de `src/app/cuenta/acciones.ts` + `src/components/diagnostico.tsx`.
///
/// En la barra inferior esta pestaña se llama **Progreso** y en la web apunta
/// a `/cuenta` — mismo destino, nombre distinto (`nav-mobile.tsx`). Aquí se
/// conserva el nombre de la pestaña, porque lo que domina la pantalla es el
/// diagnóstico y no los datos de la cuenta.
///
/// Todo son agregados que calcula Postgres. Ninguno se recalcula en el
/// dispositivo: el corte de día de la racha se hace en `America/Lima` dentro
/// del RPC, y hacerlo aquí con la zona del móvil daría rachas distintas según
/// dónde esté el alumno.

class Perfil {
  final String? nombre;
  final String rol;
  final String plan;
  final int creditos;
  final DateTime creadoEn;
  final String? areaNombre;

  const Perfil({
    required this.nombre,
    required this.rol,
    required this.plan,
    required this.creditos,
    required this.creadoEn,
    required this.areaNombre,
  });

  /// Mismo criterio que `esStaff()` en `src/lib/panel.ts`.
  bool get esStaff => rol == "admin" || rol == "docente";
}

/// Días seguidos estudiando.
///
/// Un día cuenta si el alumno **respondió** alguna pregunta, no si abrió la
/// app: mide estudio, no visitas.
class Racha {
  final int diasActual;
  final int diasMaxima;
  final bool estudiadoHoy;

  const Racha({
    required this.diasActual,
    required this.diasMaxima,
    required this.estudiadoHoy,
  });

  bool get arrancada => diasActual > 0;
}

class SubtemaDiagnostico {
  final int subtemaId;
  final String codigo;
  final String nombre;
  final String temaNombre;
  final String cursoNombre;
  final int respondidas;
  final int correctas;
  final double porcentaje;

  const SubtemaDiagnostico({
    required this.subtemaId,
    required this.codigo,
    required this.nombre,
    required this.temaNombre,
    required this.cursoNombre,
    required this.respondidas,
    required this.correctas,
    required this.porcentaje,
  });
}

/// Por debajo de `umbralFlojo` un subtema se considera flojo; por encima de
/// `umbralBien`, consolidado. Copiados de `diagnostico.tsx` para que las dos
/// plataformas cuenten «subtemas dominados» igual.
const umbralFlojo = 50;
const umbralBien = 70;

/// El diagnóstico ya agregado. Los totales se calculan una vez aquí y no en
/// cada `build`: la lista llega a tener cientos de subtemas.
class Diagnostico {
  final List<SubtemaDiagnostico> subtemas;

  const Diagnostico(this.subtemas);

  bool get vacio => subtemas.isEmpty;

  int get respondidas => subtemas.fold(0, (n, s) => n + s.respondidas);

  int get correctas => subtemas.fold(0, (n, s) => n + s.correctas);

  int get aciertoGlobal =>
      respondidas == 0 ? 0 : (correctas * 100 / respondidas).round();

  int get consolidados =>
      subtemas.where((s) => s.porcentaje >= umbralBien).length;

  /// Los cinco subtemas donde más puntos se pierden.
  ///
  /// Ordena por acierto y desempata por volumen, igual que la web: fallar 1 de
  /// 2 pesa menos que fallar 5 de 10, y sin el desempate una pregunta suelta
  /// mal respondida desplazaba a un subtema con daño real.
  List<SubtemaDiagnostico> get prioridades {
    final flojos = subtemas.where((s) => s.porcentaje < umbralBien).toList()
      ..sort((a, b) {
        final porAcierto = a.porcentaje.compareTo(b.porcentaje);
        return porAcierto != 0
            ? porAcierto
            : b.respondidas.compareTo(a.respondidas);
      });
    return flojos.take(5).toList();
  }

  /// Agrupado por curso, conservando el orden en que llegó del servidor.
  Map<String, List<SubtemaDiagnostico>> get porCurso {
    final mapa = <String, List<SubtemaDiagnostico>>{};
    for (final s in subtemas) {
      mapa.putIfAbsent(s.cursoNombre, () => []).add(s);
    }
    return mapa;
  }
}

/// Un curso ordenado por urgencia: peor porcentaje primero y, a igual
/// porcentaje, el que lleva más tiempo sin tocarse. Alimenta el aviso
/// dirigido de Práctica adaptativa.
class CursoDesatendido {
  final String codigo;
  final String nombre;
  final String slug;
  final int respondidas;

  /// `null` cuando todavía no hay ninguna respuesta con la que calcular un
  /// porcentaje — «desatendido» no siempre significa «flojo», a veces
  /// significa «nunca tocado».
  final int? porcentaje;
  final int diasSinPracticar;

  const CursoDesatendido({
    required this.codigo,
    required this.nombre,
    required this.slug,
    required this.respondidas,
    required this.porcentaje,
    required this.diasSinPracticar,
  });
}

/// Un reporte de error del alumno que el docente ya revisó y él no ha visto.
///
/// Existe para cerrar el ciclo: sin esto el reporte se manda y no vuelve nada.
class ReporteResuelto {
  final int id;
  final String motivo;
  final String estado;
  final String? preguntaCodigo;

  const ReporteResuelto({
    required this.id,
    required this.motivo,
    required this.estado,
    required this.preguntaCodigo,
  });

  bool get aceptado => estado == "aceptado";
}

class RepositorioProgreso {
  final SupabaseClient _cliente;

  RepositorioProgreso({SupabaseClient? cliente})
    : _cliente = cliente ?? Supabase.instance.client;

  User? get usuario => _cliente.auth.currentUser;

  bool get hayCuenta => usuario != null;

  /// Atraviesa la política `perfil_propio_lectura`: solo devuelve la fila si su
  /// id coincide con `auth.uid()`. Que llegue algo prueba a la vez que el
  /// disparador creó el perfil y que RLS deja verlo.
  Future<Perfil?> perfil() async {
    final u = usuario;
    if (u == null) return null;

    final f = await _cliente
        .from("perfiles")
        .select(
          "nombre, rol, plan, creditos, creado_en, areas_postulacion(nombre)",
        )
        .eq("id", u.id)
        .maybeSingle();
    if (f == null) return null;

    return Perfil(
      nombre: f["nombre"] as String?,
      rol: f["rol"] as String? ?? "alumno",
      plan: f["plan"] as String? ?? "—",
      creditos: f["creditos"] as int? ?? 0,
      creadoEn: DateTime.parse(f["creado_en"] as String),
      areaNombre: (f["areas_postulacion"] as Map?)?["nombre"] as String?,
    );
  }

  Future<Racha?> racha() async {
    if (!hayCuenta) return null;

    final fila = _primeraFila(await _cliente.rpc("racha_estudio"));
    if (fila == null) return null;

    return Racha(
      diasActual: fila["dias_actual"] as int? ?? 0,
      diasMaxima: fila["dias_maxima"] as int? ?? 0,
      estudiadoHoy: fila["estudiado_hoy"] as bool? ?? false,
    );
  }

  Future<Diagnostico> diagnostico() async {
    if (!hayCuenta) return const Diagnostico([]);

    final datos = await _cliente.rpc("diagnostico_por_subtema");
    if (datos is! List) return const Diagnostico([]);

    return Diagnostico([
      for (final f in datos.cast<Map<String, dynamic>>())
        SubtemaDiagnostico(
          subtemaId: f["subtema_id"] as int,
          codigo: f["subtema_codigo"] as String? ?? "",
          nombre: f["subtema_nombre"] as String? ?? "",
          temaNombre: f["tema_nombre"] as String? ?? "",
          cursoNombre: f["curso_nombre"] as String? ?? "",
          // `bigint` y `numeric` llegan como `num`, y a veces como texto según
          // el tamaño: se normalizan aquí en vez de confiar en el tipo.
          respondidas: _entero(f["respondidas"]),
          correctas: _entero(f["correctas"]),
          porcentaje: _decimal(f["porcentaje"]),
        ),
    ]);
  }

  Future<List<CursoDesatendido>> cursosDesatendidos() async {
    if (!hayCuenta) return const [];

    final datos = await _cliente.rpc("cursos_desatendidos");
    if (datos is! List) return const [];

    return [
      for (final f in datos.cast<Map<String, dynamic>>())
        CursoDesatendido(
          codigo: f["curso_codigo"] as String,
          nombre: f["curso_nombre"] as String,
          slug: f["curso_slug"] as String,
          respondidas: _entero(f["respondidas"]),
          porcentaje: f["porcentaje"] == null ? null : _entero(f["porcentaje"]),
          diasSinPracticar: f["dias_sin_practicar"] as int? ?? 0,
        ),
    ];
  }

  Future<List<ReporteResuelto>> reportesResueltos() async {
    final u = usuario;
    if (u == null) return const [];

    final filas = await _cliente
        .from("reportes_error")
        .select("id, motivo, estado, resuelto_en, preguntas(codigo_externo)")
        .eq("perfil_id", u.id)
        .neq("estado", "abierto")
        .isFilter("visto_por_autor_en", null)
        .order("resuelto_en", ascending: false);

    return [
      for (final r in filas)
        ReporteResuelto(
          id: r["id"] as int,
          motivo: r["motivo"] as String,
          estado: r["estado"] as String,
          preguntaCodigo:
              (r["preguntas"] as Map?)?["codigo_externo"] as String?,
        ),
    ];
  }

  /// Marca como vistos los reportes ya resueltos.
  ///
  /// Pasa por un RPC y no por un `update` directo porque la política
  /// `reportes_update` es solo para staff a propósito: si el autor pudiera
  /// escribir en su propia fila, podría marcarse el reporte como aceptado él
  /// mismo.
  Future<void> marcarReportesVistos() async {
    if (!hayCuenta) return;
    await _cliente.rpc("marcar_reportes_vistos");
  }
}

int _entero(dynamic v) => switch (v) {
  final int n => n,
  final num n => n.round(),
  final String s => int.tryParse(s) ?? 0,
  _ => 0,
};

double _decimal(dynamic v) => switch (v) {
  final num n => n.toDouble(),
  final String s => double.tryParse(s) ?? 0,
  _ => 0,
};

Map<String, dynamic>? _primeraFila(dynamic datos) {
  if (datos is List) {
    return datos.isEmpty ? null : datos.first as Map<String, dynamic>?;
  }
  return datos as Map<String, dynamic>?;
}
