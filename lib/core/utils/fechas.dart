/// Las fechas que la app escribe, en un solo sitio.
///
/// **Había cuatro listas de meses repartidas por `pantallas/`** —
/// `_mesesCortos` en progreso y en simulacro, `_mesesCortosPanel` en panel y
/// `_meses` con los nombres largos en repaso— y cuatro formateadores a mano
/// alrededor. Es el mismo rastro de copiar y pegar que dejó ocho copias de
/// `_Aviso` antes de que se reunieran en `widgets/aviso.dart`: nadie decidió
/// que el panel escribiera «14 sep» y el simulacro «14 sep 2026», simplemente
/// cada pantalla resolvió lo suyo sin mirar a las demás.
///
/// Se formatea a mano y no con `intl` por la razón que ya estaba escrita en
/// repaso: son cuatro formatos fijos en español, y añadir la dependencia con
/// su inicialización de locales no se paga. Lo que sí hacía falta era que los
/// cuatro salieran del mismo sitio.
library;

const _cortos = [
  "ene",
  "feb",
  "mar",
  "abr",
  "may",
  "jun",
  "jul",
  "ago",
  "sep",
  "oct",
  "nov",
  "dic",
];

const _largos = [
  "enero",
  "febrero",
  "marzo",
  "abril",
  "mayo",
  "junio",
  "julio",
  "agosto",
  "septiembre",
  "octubre",
  "noviembre",
  "diciembre",
];

/// **Todo se pasa a hora local antes de mirarle el día o el mes**, y esa es
/// la única línea de este archivo que arregla algo en vez de ordenarlo.
///
/// Postgres guarda `timestamptz` y PostgREST lo manda con offset, así que
/// `DateTime.parse` devuelve un instante **en UTC**. Leerle `.day` a ese
/// instante es leer el día que era en Londres, no en Arequipa: en Perú
/// (UTC-5) todo lo que ocurre entre las 19:00 y la medianoche cae ya en el
/// día siguiente en UTC. Un reporte enviado anoche a las 21:00 se le
/// mostraba al docente con la fecha de hoy, y el perfil de quien se registró
/// un 31 de agosto por la noche decía «desde sep».
///
/// Se convierte aquí y no en cada pantalla por el mismo motivo por el que
/// existe el archivo: había cuatro formateadores y solo uno
/// —`simulacro.dart`— se acordaba de llamar a `.toLocal()`. Con la conversión
/// dentro, el que se olvide ya no puede equivocarse, y un `DateTime` que ya
/// era local pasa por `toLocal()` sin cambiar nada.
DateTime _local(DateTime d) => d.toLocal();

/// `sep`
String mesCorto(DateTime d) => _cortos[_local(d).month - 1];

/// `septiembre`
String mesLargo(DateTime d) => _largos[_local(d).month - 1];

/// `14 sep` — para una fecha reciente, donde el año se da por supuesto.
String fechaDiaMes(DateTime d) => "${_local(d).day} ${mesCorto(d)}";

/// `14 sep 2026` — cuando la fecha puede ser de hace meses.
String fechaDiaMesAno(DateTime d) {
  final l = _local(d);
  return "${l.day} ${mesCorto(l)} ${l.year}";
}

/// `14 de septiembre` — para leerla dentro de una frase.
String fechaLarga(DateTime d) => "${_local(d).day} de ${mesLargo(d)}";

/// `sep 2026` — para «miembro desde».
String mesAno(DateTime d) => "${mesCorto(d)} ${_local(d).year}";
