import "package:matr_u/domain/models/horario.dart";
import "package:supabase_flutter/supabase_flutter.dart";

class ErrorHorario implements Exception {
  final String mensaje;
  const ErrorHorario(this.mensaje);

  @override
  String toString() => mensaje;
}

class RepositorioHorario {
  final SupabaseClient _cliente;

  RepositorioHorario({SupabaseClient? cliente})
    : _cliente = cliente ?? Supabase.instance.client;

  /// `[]` sin sesión — igual que el resto de datos personales de la app,
  /// nunca un error: la ausencia de cuenta no es una falla.
  Future<List<BloqueHorario>> obtener() async {
    final usuario = _cliente.auth.currentUser;
    if (usuario == null) return const [];

    final filas = await _cliente
        .from("horarios_estudio")
        .select(
          "id, dia_semana, hora_inicio, duracion_minutos, cursos(codigo, nombre, slug)",
        )
        .eq("perfil_id", usuario.id)
        .order("dia_semana")
        .order("hora_inicio");

    return [
      for (final b in filas)
        if (b["cursos"] != null)
          BloqueHorario(
            id: b["id"] as int,
            cursoCodigo: (b["cursos"] as Map)["codigo"] as String,
            cursoNombre: (b["cursos"] as Map)["nombre"] as String,
            cursoSlug: (b["cursos"] as Map)["slug"] as String,
            diaSemana: b["dia_semana"] as int,
            horaInicio: b["hora_inicio"] as String,
            duracionMinutos: b["duracion_minutos"] as int,
          ),
    ];
  }

  /// [cursoCodigo] y no el slug porque es la columna `unique` real de la
  /// tabla `cursos`, y porque reutilizar el mismo campo que el resto de la
  /// app evita tener dos formas de nombrar el mismo curso en el código.
  /// Devuelve el id que le puso Postgres.
  ///
  /// **No es un extra: sin él la pantalla se inventaba uno.** Antes esto no
  /// devolvía nada y `PantallaHorario` metía el bloque nuevo en su lista con
  /// un id negativo «provisional hasta la próxima recarga» — recarga que no
  /// llega nunca, porque solo se carga en `initState`. Borrar ese bloque sin
  /// salir de la pantalla mandaba el `delete` contra un id inexistente:
  /// PostgREST no falla cuando no encuentra filas, así que la app lo quitaba
  /// de la lista y el bloque seguía en la base, esperando a reaparecer la
  /// próxima vez que se abriera el horario.
  Future<int> crear({
    required String cursoCodigo,
    required int diaSemana,
    required String horaInicio,
    required int duracionMinutos,
  }) async {
    if (diaSemana < 0 || diaSemana > 6) {
      throw const ErrorHorario("Día inválido");
    }
    if (duracionMinutos <= 0 || duracionMinutos > 480) {
      throw const ErrorHorario("La duración debe ser de hasta 8 horas");
    }

    final usuario = _cliente.auth.currentUser;
    if (usuario == null) {
      throw const ErrorHorario("No estás autenticado");
    }

    final curso = await _cliente
        .from("cursos")
        .select("id")
        .eq("codigo", cursoCodigo)
        .maybeSingle();
    if (curso == null) throw const ErrorHorario("Curso no encontrado");

    try {
      final fila = await _cliente
          .from("horarios_estudio")
          .insert({
            "perfil_id": usuario.id,
            "curso_id": curso["id"],
            "dia_semana": diaSemana,
            "hora_inicio": horaInicio,
            "duracion_minutos": duracionMinutos,
          })
          .select("id")
          .single();
      return fila["id"] as int;
    } on PostgrestException catch (e) {
      if (e.code == "23505") {
        throw const ErrorHorario(
          "Ya tienes un bloque de ese curso a esa hora ese día",
        );
      }
      throw ErrorHorario(e.message);
    }
  }

  /// La RLS ya restringe el `delete` a `perfil_id = auth.uid()`; el `.eq` de
  /// más abajo es cinturón y tirantes, no la única barrera.
  Future<void> eliminar(int id) async {
    final usuario = _cliente.auth.currentUser;
    if (usuario == null) throw const ErrorHorario("No estás autenticado");

    await _cliente
        .from("horarios_estudio")
        .delete()
        .eq("id", id)
        .eq("perfil_id", usuario.id);
  }
}
