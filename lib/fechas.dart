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

/// `sep`
String mesCorto(DateTime d) => _cortos[d.month - 1];

/// `septiembre`
String mesLargo(DateTime d) => _largos[d.month - 1];

/// `14 sep` — para una fecha reciente, donde el año se da por supuesto.
String fechaDiaMes(DateTime d) => "${d.day} ${mesCorto(d)}";

/// `14 sep 2026` — cuando la fecha puede ser de hace meses.
String fechaDiaMesAno(DateTime d) => "${d.day} ${mesCorto(d)} ${d.year}";

/// `14 de septiembre` — para leerla dentro de una frase.
String fechaLarga(DateTime d) => "${d.day} de ${mesLargo(d)}";

/// `sep 2026` — para «miembro desde».
String mesAno(DateTime d) => "${mesCorto(d)} ${d.year}";
