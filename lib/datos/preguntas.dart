import "catalogo.dart";
import "temario.dart";

/// Puerto de `src/lib/preguntas.ts`: el banco de preguntas.
///
/// **La diferencia de fondo con la web, y por qué existe.** Allí el módulo
/// carga las preguntas COMPLETAS —clave y explicación incluidas— y expone dos
/// tipos: `PreguntaCompleta`, que nunca sale del servidor, y `PreguntaPublica`,
/// que es el único que cruza al navegador. `corregir()` vive del lado
/// servidor y por eso puede calificar a un alumno sin sesión.
///
/// Aquí no hay servidor: la app **es** el cliente. Un asset es un archivo
/// dentro del APK y un APK es un ZIP, así que `PreguntaCompleta` no tiene
/// dónde esconderse — repartirla es repartir el banco resuelto. Por eso
/// `tool/sincronizar-datos.mjs` borra `clave` y `explicacion` al copiar, y
/// aquí solo existe el equivalente de `PreguntaPublica`: **no hay tipo
/// completo, ni función `corregir`**. No es una omisión pendiente de portar;
/// es la invariante de la web sostenida en una plataforma que no tiene
/// servidor.
///
/// Consecuencia visible: sin sesión no se puede practicar. La corrección pasa
/// siempre por el RPC `responder_pregunta`, que es quien conoce la clave —
/// exactamente igual que para un alumno con sesión en la web, donde la columna
/// `clave` está revocada para el rol `authenticated`.

enum Letra { a, b, c, d, e }

const letras = Letra.values;

extension EtiquetaLetra on Letra {
  /// La forma en que la letra viaja al RPC y se pinta en pantalla: "A".."E".
  String get etiqueta => name.toUpperCase();
}

Letra? letraDesde(String texto) {
  final limpio = texto.trim().toLowerCase();
  for (final l in letras) {
    if (l.name == limpio) return l;
  }
  return null;
}

enum Dificultad { facil, medio, dificil }

Dificultad _dificultadDesde(String? texto) => switch (texto) {
  "facil" => Dificultad.facil,
  "dificil" => Dificultad.dificil,
  _ => Dificultad.medio,
};

/// Figura de una pregunta (diagramas de geometría, gráficos de física…).
///
/// `ancho` y `alto` se conservan por la misma razón que en la web —reservar el
/// hueco antes de que la imagen cargue, para que el enunciado no dé un salto
/// mientras el alumno lee— aunque aquí lo materializa un `AspectRatio` y no el
/// atributo de un `<img>`.
///
/// `src` es el nombre del archivo, no una ruta: las figuras no viajan en el
/// APK (ver `pubspec.yaml`), se resuelven contra Supabase Storage.
class Figura {
  final String src;
  final String alt;
  final int ancho;
  final int alto;

  const Figura({
    required this.src,
    required this.alt,
    required this.ancho,
    required this.alto,
  });

  double get proporcion => alto == 0 ? 1 : ancho / alto;

  static Figura? desde(Map<String, dynamic>? j) {
    final src = j?["src"] as String?;
    if (src == null || src.isEmpty || !_nombreValido(src)) return null;
    return Figura(
      src: src,
      alt: j!["alt"] as String? ?? "",
      ancho: j["ancho"] as int? ?? 0,
      alto: j["alto"] as int? ?? 0,
    );
  }
}

/// Mismo criterio que `nombreArchivoValido` en `src/lib/figuras.ts`: un nombre
/// llano, sin rutas ni saltos de directorio. Aquí no es que evite un
/// `path traversal` en un servidor, pero sí impide construir una URL de
/// Storage apuntando a otro sitio con un banco manipulado.
bool _nombreValido(String nombre) =>
    RegExp(r"^[a-zA-Z0-9._-]+$").hasMatch(nombre) &&
    !nombre.contains("..");

class Alternativa {
  final Letra letra;
  final String texto;

  /// Algunas preguntas ofrecen figuras como opciones («¿cuál gráfica…?»).
  final Figura? imagen;

  const Alternativa({
    required this.letra,
    required this.texto,
    required this.imagen,
  });
}

/// Una pregunta tal como puede verla el alumno. No existe otra versión.
///
/// El texto viaja en crudo con su LaTeX (`$…$`), no como HTML: en la web
/// `renderizarMatematicas` lo convertía a MathML porque el navegador lo dibuja
/// gratis, y aquí lo dibuja `TextoConFormulas` en tiempo de pintado. Es el
/// mismo contenido, un paso más tarde.
class Pregunta {
  final String codigo;
  final String enunciado;
  final Figura? imagen;
  final Dificultad dificultad;
  final List<Alternativa> alternativas;
  final String subtemaCodigo;
  final String subtemaNombre;
  final String temaNombre;
  final String cursoNombre;
  final String cursoSlug;

  const Pregunta({
    required this.codigo,
    required this.enunciado,
    required this.imagen,
    required this.dificultad,
    required this.alternativas,
    required this.subtemaCodigo,
    required this.subtemaNombre,
    required this.temaNombre,
    required this.cursoNombre,
    required this.cursoSlug,
  });
}

class CursoConPreguntas {
  final String slug;
  final String nombre;
  final int total;

  const CursoConPreguntas({
    required this.slug,
    required this.nombre,
    required this.total,
  });
}

/// El banco cargado y ya indexado.
class Banco {
  final List<Pregunta> preguntas;
  final Map<String, Pregunta> _porCodigo;

  /// El banco solo trae los ejemplos de desarrollo. Igual que en la web: si no
  /// hay ningún archivo real, se cargan los `_*.json` para que la pantalla no
  /// esté vacía, y se avisa.
  final bool sonEjemplos;

  const Banco._(this.preguntas, this._porCodigo, this.sonEjemplos);

  int get total => preguntas.length;

  /// Índice por código, no un `firstWhere` lineal: armar una tanda de repaso
  /// resuelve hasta 30 códigos seguidos, y el banco está pensado para crecer
  /// un orden de magnitud. Misma decisión que el `Map` de la web.
  Pregunta? porCodigo(String codigo) => _porCodigo[codigo];

  List<Pregunta> deCurso(String slug) =>
      preguntas.where((p) => p.cursoSlug == slug).toList();

  /// Los códigos que devuelve Postgres, resueltos contra el banco local.
  ///
  /// Un código puede no encontrarse —pregunta retirada del banco después de
  /// que el alumno la respondiera— y se descarta en silencio en vez de romper
  /// la pantalla, igual que hace `repaso/acciones.ts`.
  List<Pregunta> porCodigos(Iterable<String> codigos) => [
    for (final c in codigos) ?_porCodigo[c],
  ];

  List<CursoConPreguntas> cursos() {
    final porCurso = <String, ({String nombre, int total})>{};
    for (final p in preguntas) {
      final actual = porCurso[p.cursoSlug];
      porCurso[p.cursoSlug] = (
        nombre: p.cursoNombre,
        total: (actual?.total ?? 0) + 1,
      );
    }

    final lista = [
      for (final e in porCurso.entries)
        CursoConPreguntas(
          slug: e.key,
          nombre: e.value.nombre,
          total: e.value.total,
        ),
    ]..sort((a, b) => b.total.compareTo(a.total));
    return lista;
  }

  /// Cuántas preguntas hay por código de subtema. Un `null` significa cero.
  Map<String, int> conteoPorSubtema() {
    final conteo = <String, int>{};
    for (final p in preguntas) {
      conteo[p.subtemaCodigo] = (conteo[p.subtemaCodigo] ?? 0) + 1;
    }
    return conteo;
  }
}

class RepositorioPreguntas {
  final _catalogo = Catalogo.instancia;
  final RepositorioTemario _temario;

  RepositorioPreguntas({RepositorioTemario? temario})
    : _temario = temario ?? RepositorioTemario();

  Banco? _cargado;

  Future<Banco> cargar() async {
    final yaEsta = _cargado;
    if (yaEsta != null) return yaEsta;

    final temario = await _temario.cargar();
    final nombres = await _catalogo.indice("preguntas");

    // `_indice.json` es el índice mismo, no un archivo del banco; y los demás
    // `_*.json` son los ejemplos de desarrollo, que solo entran si no hay
    // ningún archivo real. Misma regla que `cargar()` en la web.
    final candidatos = nombres.where((n) => n != "_indice.json").toList();
    final reales = candidatos.where((n) => !n.startsWith("_")).toList();
    final sonEjemplos = reales.isEmpty;
    final archivos = (sonEjemplos ? candidatos : reales)..sort();

    final preguntas = <Pregunta>[];
    for (final archivo in archivos) {
      final doc =
          await _catalogo.archivo("preguntas", archivo) as Map<String, dynamic>;
      final prefijo = doc["prefijo"] as String;
      final ano = doc["anoExamen"] as int;

      for (final crudo in (doc["preguntas"] as List).cast<Map<String, dynamic>>()) {
        final subtema = crudo["subtema"] as String;
        final ubicacion = temario.ubicacion(subtema);
        // El generador del repo web ya reporta esto como error; aquí basta
        // con no inventar una ubicación.
        if (ubicacion == null) continue;

        final numero = (crudo["numero"] as int).toString().padLeft(3, "0");
        preguntas.add(
          Pregunta(
            codigo: "$prefijo-$ano-$numero",
            enunciado: crudo["enunciado"] as String? ?? "",
            imagen: Figura.desde(crudo["imagen"] as Map<String, dynamic>?),
            dificultad: _dificultadDesde(crudo["dificultad"] as String?),
            alternativas: _alternativas(
              (crudo["alternativas"] as Map?)?.cast<String, dynamic>() ?? const {},
            ),
            subtemaCodigo: subtema,
            subtemaNombre: ubicacion.subtema.nombre,
            temaNombre: ubicacion.tema.nombre,
            cursoNombre: ubicacion.curso.nombre,
            cursoSlug: ubicacion.curso.slug,
          ),
        );
      }
    }

    return _cargado = Banco._(
      preguntas,
      {for (final p in preguntas) p.codigo: p},
      sonEjemplos,
    );
  }

  /// Una alternativa admite dos formas en el JSON, como en la web:
  ///
  ///   "A": "18 g"                              → solo texto
  ///   "A": { "texto": "…", "imagen": { … } }   → con figura
  List<Alternativa> _alternativas(Map<String, dynamic> crudas) => [
    for (final letra in letras)
      if (crudas[letra.etiqueta] case final cruda)
        Alternativa(
          letra: letra,
          texto: cruda is String
              ? cruda
              : (cruda as Map<String, dynamic>?)?["texto"] as String? ?? "",
          imagen: cruda is String
              ? null
              : Figura.desde(
                  (cruda as Map<String, dynamic>?)?["imagen"]
                      as Map<String, dynamic>?,
                ),
        ),
  ];
}
