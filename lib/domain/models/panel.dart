import "package:matr_u/domain/models/preguntas.dart";

/// Puerto de `src/lib/panel.ts` + `src/app/panel/acciones.ts`.
///
/// **El control de acceso real vive en la base, no aquí.** Las seis
/// funciones del panel comprueban `es_staff()`/`es_admin()` por dentro, así
/// que un alumno que llame al RPC a mano recibe una excepción o un conjunto
/// vacío aunque se salte esta pantalla — igual que en la web, donde
/// `exigirStaff()` es «conveniencia, no el control de acceso». Lo que evita
/// esta capa es enseñar un panel roto a quien no le toca, nada más.
enum Rol { alumno, docente, admin }

/// Con nombre, y no anonima: una extension sin nombre solo la ve su propia
/// biblioteca, y `RepositorioPanel` vive en otro archivo desde que los
/// modelos y los repositorios se separaron.
extension NombreDeRol on Rol {
  String get nombre => switch (this) {
    Rol.alumno => "alumno",
    Rol.docente => "docente",
    Rol.admin => "admin",
  };
}

bool esStaff(Rol? rol) => rol == Rol.docente || rol == Rol.admin;

class ResumenPanel {
  final int sinAuditar;
  final int publicadas;
  final int enAuditoria;
  final int borradores;
  final int retiradas;
  final int reportesAbiertos;
  final int personas;

  const ResumenPanel({
    required this.sinAuditar,
    required this.publicadas,
    required this.enAuditoria,
    required this.borradores,
    required this.retiradas,
    required this.reportesAbiertos,
    required this.personas,
  });
}

class AlternativaRevision {
  final Letra letra;
  final String textoMd;
  final String? imagenUrl;
  final String? imagenAlt;

  const AlternativaRevision({
    required this.letra,
    required this.textoMd,
    required this.imagenUrl,
    required this.imagenAlt,
  });
}

class PreguntaRevision {
  final int id;
  final String? codigo;
  final String enunciadoMd;
  final String? imagenUrl;
  final String? imagenAlt;

  /// `null` cuando el RPC no devolvió una letra legible.
  ///
  /// Es nullable a propósito, y antes no lo era: el valor por defecto era
  /// `Letra.a`, así que una clave ausente o ilegible se le presentaba al
  /// docente como «la respuesta correcta es A», en verde y con su etiqueta.
  /// De todos los sitios donde inventar un valor sale mal, este es el peor:
  /// la pantalla existe para que alguien audite precisamente esa letra, y una
  /// clave falsa auditada se publica con el visto bueno de un profesor. Sin
  /// letra no se marca ninguna alternativa y la ficha lo dice.
  final Letra? clave;

  final String? explicacionMd;
  final String estado;
  final String dificultad;
  final bool auditada;
  final String curso;
  final String subtema;
  final List<AlternativaRevision> alternativas;
  final int reportesAbiertos;

  const PreguntaRevision({
    required this.id,
    required this.codigo,
    required this.enunciadoMd,
    required this.imagenUrl,
    required this.imagenAlt,
    required this.clave,
    required this.explicacionMd,
    required this.estado,
    required this.dificultad,
    required this.auditada,
    required this.curso,
    required this.subtema,
    required this.alternativas,
    required this.reportesAbiertos,
  });
}

class ReporteStaff {
  final int id;
  final String motivo;
  final String? detalle;
  final String estado;
  final DateTime creadoEn;
  final int preguntaId;
  final String? preguntaCodigo;
  final String? preguntaEnunciado;

  const ReporteStaff({
    required this.id,
    required this.motivo,
    required this.detalle,
    required this.estado,
    required this.creadoEn,
    required this.preguntaId,
    required this.preguntaCodigo,
    required this.preguntaEnunciado,
  });
}

class Persona {
  final String id;
  final String nombre;
  final String correo;
  final Rol rol;
  final String plan;

  const Persona({
    required this.id,
    required this.nombre,
    required this.correo,
    required this.rol,
    required this.plan,
  });
}
