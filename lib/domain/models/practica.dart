import "package:matr_u/domain/models/preguntas.dart";

/// Puerto de `src/app/practica/acciones.ts`.
///
/// La lógica de calificar no se reimplementa: vive en el RPC
/// `responder_pregunta` de Postgres y `supabase_flutter` lo llama igual que lo
/// llamaba la Server Action. Eso es lo que abarata esta migración — el backend
/// no se toca — y también lo que la hace correcta, porque la clave sigue
/// estando solo donde estaba.
///
/// Se conserva la decisión de cuándo nace el intento: **en la primera
/// respuesta, no al abrir la pantalla**. La web lo cambió a propósito porque
/// cada visita a `/practica/[curso]` —recarga, prefetch de `<Link>`, bot—
/// insertaba una fila en `intentos` sin que el alumno respondiera nada. En una
/// app el motivo es aún más claro: entrar a una pantalla y volver atrás es un
/// gesto barato que la gente hace todo el rato.
class Correccion {
  final bool esCorrecta;
  final Letra clave;
  final String? explicacion;

  const Correccion({
    required this.esCorrecta,
    required this.clave,
    required this.explicacion,
  });
}
