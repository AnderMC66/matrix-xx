/// La base del MVVM de esta app: el estado de una petición y el `ChangeNotifier`
/// que lo publica.
///
/// **Qué cambia respecto a lo que había.** Hasta ahora cada pantalla guardaba
/// un `Future<…>? _carga` en su `State` y lo pintaba con un `FutureBuilder`.
/// Funcionaba, pero ataba tres cosas que no tienen por qué ir juntas: cuándo se
/// pide, qué se hace con el resultado y cómo se dibuja. Mover las dos primeras
/// a un [VistaModelo] deja la vista tonta — que es justo lo que hace que se
/// pueda rediseñar entera sin tocar una línea de lógica.
///
/// **Qué NO cambia.** Los repositorios se siguen inyectando por constructor.
/// No hay contenedor de servicios ni `provider`: con un modelo de vista por
/// pantalla y cero estado compartido entre ellas, un localizador global sería
/// una indirección más sin nada que resolver. La inyección por constructor
/// también es inyección de dependencias, y además es la que un test puede usar
/// sin instalar nada.
library;

import "package:flutter/material.dart";

import "package:matr_u/ui/core/widgets/aviso.dart";

// ───────────────────────────────────────────────────────────────────────────
// El estado de una petición
// ───────────────────────────────────────────────────────────────────────────

/// En qué punto está una petición. Es lo que un [VistaModelo] expone y lo que
/// la vista pinta, sin tener que saber de `Future` ni de `snapshot`.
sealed class Estado<T> {
  const Estado();

  /// El valor, o `null` si todavía no hay o hubo fallo. Sirve para los sitios
  /// que quieren seguir enseñando lo anterior mientras recargan.
  T? get valor => switch (this) {
    Listo<T>(:final dato) => dato,
    _ => null,
  };
}

/// Nadie ha pedido nada todavía. No es lo mismo que «cargando»: sin sesión,
/// media app se queda aquí a propósito y no debe pintar un spinner eterno.
class Inactivo<T> extends Estado<T> {
  const Inactivo();
}

class Cargando<T> extends Estado<T> {
  const Cargando();
}

class Listo<T> extends Estado<T> {
  final T dato;
  const Listo(this.dato);
}

class Fallo<T> extends Estado<T> {
  final Object error;
  const Fallo(this.error);
}

// ───────────────────────────────────────────────────────────────────────────
// El modelo de vista
// ───────────────────────────────────────────────────────────────────────────

/// Base de todos los modelos de vista.
///
/// Aporta dos cosas que si no acaban copiadas y pegadas en cada uno:
///
///   - **avisar después de `dispose` no revienta.** Una petición en vuelo
///     cuando el usuario se va de la pantalla llega a un notificador ya
///     liberado, y `notifyListeners` lanza. Es el equivalente del
///     `if (!mounted) return` que había en los `State`.
///   - **una respuesta vieja no pisa a una nueva.** `FutureBuilder` lo hacía
///     solo: al cambiarle el `future`, ignoraba el resultado del anterior. Al
///     quitarlo había que reponerlo, o cambiar de chip dos veces seguidas en
///     Repaso podía dejar en pantalla la respuesta de la primera.
abstract class VistaModelo extends ChangeNotifier {
  bool _vivo = true;

  /// Cuántas veces se ha pedido cada cosa. La respuesta que no sea de la
  /// última petición de su clave se descarta.
  final _generacion = <Object, int>{};

  @override
  void dispose() {
    _vivo = false;
    super.dispose();
  }

  @protected
  void avisar() {
    if (_vivo) notifyListeners();
  }

  /// Corre [trabajo] y publica su estado a través de [asignar].
  ///
  /// [clave] identifica la petición: dos llamadas con la misma clave compiten,
  /// y gana la última en salir. Con claves distintas —un modelo que carga tres
  /// cosas en paralelo— no se estorban.
  @protected
  Future<void> pedir<T>(
    Object clave,
    Future<T> Function() trabajo,
    void Function(Estado<T>) asignar,
  ) async {
    final generacion = (_generacion[clave] ?? 0) + 1;
    _generacion[clave] = generacion;

    asignar(Cargando<T>());
    avisar();

    try {
      final dato = await trabajo();
      if (!_vivo || _generacion[clave] != generacion) return;
      asignar(Listo<T>(dato));
    } on Object catch (error) {
      if (!_vivo || _generacion[clave] != generacion) return;
      asignar(Fallo<T>(error));
    }
    avisar();
  }
}

// ───────────────────────────────────────────────────────────────────────────
// El puente con la vista
// ───────────────────────────────────────────────────────────────────────────

/// Pinta un [Estado] con las tres ramas de siempre: spinner, aviso de fallo, o
/// el contenido.
///
/// Existe para que esas tres ramas se decidan **en un solo sitio**. Antes cada
/// pantalla escribía su propio `if (snap.hasError) … if (!snap.hasData) …`, y
/// por ahí es por donde se cuela la deriva —el mismo camino que ya llevó a
/// tener ocho copias privadas de [Aviso]—.
class SegunEstado<T> extends StatelessWidget {
  final Estado<T> estado;

  /// Qué pintar cuando hay dato.
  final Widget Function(T dato) cuandoListo;

  /// Qué pintar mientras no se ha pedido nada. Por defecto, nada: es el estado
  /// de una pantalla sin sesión, y un spinner ahí sería un spinner eterno.
  final Widget Function()? cuandoInactivo;

  final String tituloDelFallo;
  final VoidCallback? alReintentar;

  const SegunEstado({
    super.key,
    required this.estado,
    required this.cuandoListo,
    required this.tituloDelFallo,
    this.cuandoInactivo,
    this.alReintentar,
  });

  @override
  Widget build(BuildContext context) => switch (estado) {
    Inactivo<T>() => cuandoInactivo?.call() ?? const SizedBox.shrink(),
    Cargando<T>() => const Center(child: CircularProgressIndicator()),
    Fallo<T>(:final error) => Aviso(
      icono: Icons.cloud_off_outlined,
      titulo: tituloDelFallo,
      detalle: "$error",
      accion: alReintentar == null ? null : ("Reintentar", alReintentar!),
    ),
    Listo<T>(:final dato) => cuandoListo(dato),
  };
}
