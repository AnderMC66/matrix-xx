// `ModeloRepaso`: el primer modelo de vista, probado **sin montar un widget**.
//
// Es el motivo de fondo para pasar a MVVM, y conviene que se vea en el primero:
// hasta ahora, comprobar que cambiar de chip no deja en pantalla la respuesta
// equivocada exigía levantar un `MaterialApp`, un tema, una vista de 1000×2400
// y ocho `pump`. Aquí son tres líneas y no hay árbol de widgets.
//
// Lo que se fija:
//
//   - **Sin cuenta no se pide nada** y el estado se queda en `Inactivo`, que
//     no es lo mismo que `Cargando`. La diferencia importa: con `Cargando` la
//     pantalla pintaría un spinner que no va a terminar nunca.
//   - **Una respuesta vieja no pisa a una nueva.** `FutureBuilder` lo hacía
//     solo —al cambiarle el `future` ignoraba el anterior—, y al quitarlo hubo
//     que reponerlo a mano en `VistaModelo.pedir`. Sin esa guarda, cambiar de
//     chip dos veces seguidas puede dejar lo que devolvió la primera.
//   - **Un fallo se publica como fallo**, no como una lista vacía: vacío y
//     roto se leen distinto, y en esta pantalla vacío es incluso el objetivo.
import "dart:async";

import "package:flutter_test/flutter_test.dart";
import "package:matr_u/data/repositories/repaso.dart";
import "package:matr_u/data/repositories/sesion.dart";
import "package:matr_u/domain/models/preguntas.dart";
import "package:matr_u/domain/models/repaso.dart";
import "package:matr_u/ui/core/vista_modelo.dart";
import "package:matr_u/ui/features/practice/view_models/repaso.dart";
import "package:supabase/supabase.dart";

/// Un repositorio que responde cuando el test quiere, y no antes.
///
/// Hereda del de verdad para que la firma no pueda separarse de la real sin
/// que esto deje de compilar. El cliente que le pasa al padre no llega a
/// usarse: los tres métodos están sobrescritos.
class _RepoFalso extends RepositorioRepaso {
  _RepoFalso(SupabaseClient cliente) : super(cliente: cliente);

  final pendientesEnCola = <Completer<List<Pregunta>>>[];
  final falladasEnCola = <Completer<List<Pregunta>>>[];

  @override
  Future<List<Pregunta>> pendientes({int limite = 30}) {
    final c = Completer<List<Pregunta>>();
    pendientesEnCola.add(c);
    return c.future;
  }

  @override
  Future<List<Pregunta>> falladas() {
    final c = Completer<List<Pregunta>>();
    falladasEnCola.add(c);
    return c.future;
  }

  @override
  Future<ResumenRepasos?> resumen() async => null;
}

/// Una sesión que dice lo que el test le pida, sin tocar la red.
class _SesionFalsa extends Sesion {
  final bool entrada;
  _SesionFalsa(SupabaseClient cliente, {required this.entrada})
    : super(cliente: cliente);

  @override
  bool get hayCuenta => entrada;
}

Pregunta _pregunta(String codigo) => Pregunta(
  codigo: codigo,
  enunciado: codigo,
  imagen: null,
  dificultad: Dificultad.medio,
  alternativas: const [],
  subtemaCodigo: "LIT-01-01",
  subtemaNombre: "Subtema",
  temaNombre: "Tema",
  cursoNombre: "Literatura",
  cursoSlug: "literatura",
);

void main() {
  late SupabaseClient cliente;

  setUp(() {
    cliente = SupabaseClient(
      "https://proyecto.supabase.co",
      "sb_publishable_de_mentira",
    );
  });

  tearDown(() async => cliente.dispose());

  ModeloRepaso construir({required bool entrada, _RepoFalso? repo}) =>
      ModeloRepaso(
        repositorio: repo ?? _RepoFalso(cliente),
        sesion: _SesionFalsa(cliente, entrada: entrada),
      );

  test("sin cuenta no pide nada y se queda inactivo, no cargando", () async {
    final repo = _RepoFalso(cliente);
    final modelo = construir(entrada: false, repo: repo);

    await modelo.cargar();

    expect(modelo.datos, isA<Inactivo<DatosRepaso>>());
    expect(repo.pendientesEnCola, isEmpty);
    expect(
      modelo.datos,
      isNot(isA<Cargando<DatosRepaso>>()),
      reason: "un spinner aquí no terminaría nunca: no hay nada en vuelo",
    );
  });

  test("con cuenta pasa por cargando y acaba en listo", () async {
    final repo = _RepoFalso(cliente);
    final modelo = construir(entrada: true, repo: repo);

    final enVuelo = modelo.cargar();
    expect(modelo.datos, isA<Cargando<DatosRepaso>>());

    repo.pendientesEnCola.single.complete([_pregunta("LIT-2026-001")]);
    await enVuelo;

    final estado = modelo.datos;
    expect(estado, isA<Listo<DatosRepaso>>());
    expect((estado as Listo<DatosRepaso>).dato.$1, hasLength(1));
  });

  test("un fallo se publica como fallo, no como lista vacía", () async {
    final repo = _RepoFalso(cliente);
    final modelo = construir(entrada: true, repo: repo);

    final enVuelo = modelo.cargar();
    repo.pendientesEnCola.single.completeError(StateError("sin conexión"));
    await enVuelo;

    expect(modelo.datos, isA<Fallo<DatosRepaso>>());
  });

  test("la respuesta de la petición vieja no pisa a la nueva", () async {
    // Es la guarda de `VistaModelo.pedir`. Sin ella, esto deja en pantalla las
    // programadas mientras el chip dice «Falladas».
    final repo = _RepoFalso(cliente);
    final modelo = construir(entrada: true, repo: repo);

    // Sin `await` a propósito: lo que se prueba es justo que las dos estén
    // en vuelo a la vez.
    unawaited(modelo.cargar()); // programadas
    modelo.cambiarModo(ModoRepaso.falladas); // y enseguida, falladas

    expect(repo.pendientesEnCola, hasLength(1));
    expect(repo.falladasEnCola, hasLength(1));

    // Responden al revés: primero la nueva, después la vieja.
    repo.falladasEnCola.single.complete([_pregunta("LIT-2026-002")]);
    await Future<void>.delayed(Duration.zero);
    repo.pendientesEnCola.single.complete([
      _pregunta("LIT-2026-003"),
      _pregunta("LIT-2026-004"),
    ]);
    await Future<void>.delayed(Duration.zero);

    final estado = modelo.datos as Listo<DatosRepaso>;
    expect(
      estado.dato.$1.map((p) => p.codigo),
      ["LIT-2026-002"],
      reason: "gana la última que se pidió, no la última que contestó",
    );
    expect(modelo.modo, ModoRepaso.falladas);
  });

  test("cambiar al modo que ya está puesto no vuelve a pedir", () async {
    final repo = _RepoFalso(cliente);
    final modelo = construir(entrada: true, repo: repo);

    unawaited(modelo.cargar());
    modelo.cambiarModo(ModoRepaso.programadas);

    expect(repo.pendientesEnCola, hasLength(1));
  });
}
