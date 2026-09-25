# Constitución

Las reglas que no se negocian, y el contexto que hace falta para entender por
qué existen. El **cómo** —arrancar, sincronizar datos, firmar el APK— está en
[`LEEME.md`](LEEME.md); aquí solo va lo que no se puede romper.

Última revisión: 2026-09-25.

---

## 1. Qué es esto

`matr_u` es la app móvil de **Matrix U**, preparación para el examen de
admisión de la UNSA. Es un **porte a Flutter de una app web** que ya existe
(`C:\source\MATRIX-U`, Next.js + Supabase).

Lo que eso implica, y es la restricción que más decisiones explica:

> **Este repo reescribe la interfaz. Nada más.**

| Pieza | Fuente de verdad | ¿Se toca aquí? |
|---|---|---|
| Esquema, RLS, 19 funciones RPC | `MATRIX-U/supabase/` | **No.** Se llaman las mismas |
| Catálogo (temario, teoría, preguntas) | `MATRIX-U/data/**/*.json` | **No.** Se copia con `tool/sincronizar-datos.mjs` |
| Figuras (83 MB) | CDN de la web | **No.** Se piden por red |
| Interfaz | este repo | **Todo** |

Si algo del backend está mal, se arregla en el repo web. Un parche aquí crea
dos verdades que se separan.

## 2. El idioma es el español

Comentarios, documentación, mensajes de commit, nombres de clases, variables y
archivos. `RepositorioProgreso`, no `ProgressRepository`; `ErrorHorario`, no
`ScheduleException`.

La única excepción son **los nombres de las carpetas de `lib/`** —`data`,
`domain`, `ui`, `repositories`—, porque ahí manda la guía de arquitectura de
Flutter y desviarse de sus nombres hace que deje de reconocerse la estructura.
El contenido de esos archivos sigue en español.

No es preferencia estética: quien mantiene esto lee español, y un repo mestizo
obliga a traducir mentalmente en cada archivo.

## 3. Secretos

**La clave secreta de Supabase vive en `android/app/.env` y no sale de ahí.**
Está en `.gitignore:60`, nunca ha estado trackeada y no aparece en ningún
commit. Salta RLS entera.

Prohibido, sin excepciones:

- commitearla;
- copiarla a `lib/core/config/config.dart` o a cualquier archivo de `lib/`;
- pasarla por `--dart-define` o `--dart-define-from-file`;
- imprimirla en una terminal, un log o una transcripción.

Cualquiera de las tres primeras la mete en el binario, y un APK es un ZIP.

`config/dev.json` (también en `.gitignore`) lleva solo la URL pública y la
clave *publishable* — esa sí es para el cliente. El keystore (`*.jks`) se
guarda **fuera del repo**: perderlo significa no poder volver a firmar la app.

## 4. Las claves de respuesta no viajan en el APK

Es la regla que más fácil se rompe sin querer, y por eso va tan arriba.

El tipo `Pregunta` **no tiene campo `clave` ni `explicacion`**. No es un
descuido que alguien pueda "completar": es la invariante que sostiene el
diseño del banco. En Postgres la columna `clave` está revocada para el rol
`authenticated`, y la única forma de saber la respuesta es responder y que el
RPC `responder_pregunta` la devuelva.

Aquí no hay servidor donde esconderla. `tool/sincronizar-datos.mjs` las borra
al copiar y `test/datos_test.dart` lo verifica contra el asset real en cada
`flutter test`. **Ese test no se salta ni se relaja.**

Hasta el 2026-09-07 se copiaban tal cual: 395 claves en texto plano para
cualquiera con `unzip`.

## 5. Arquitectura: lo que hay de verdad

`lib/` sigue la
[guía de arquitectura de Flutter](.agents/skills/flutter-apply-architecture-best-practices/SKILL.md),
instalada como skill del repo:

```
lib/
  core/config|utils/          ← no está en la guía: config y fechas, sueltas
  data/
    repositories/             ← los 11 RepositorioX, y Sesion
    services/                 ← Catalogo, que envuelve el bundle de assets
  domain/models/              ← los modelos y sus enums
  ui/core/theme|widgets/
  ui/core/vista_modelo.dart   ← Estado<T>, VistaModelo, SegunEstado
  ui/features/<f>/view_models/
  ui/features/<f>/views/
```

**No hay `data/models/`, y es a propósito.** La guía los separa de
`domain/models/` porque supone que el repositorio transforma el modelo crudo
de la API en uno limpio. Aquí no hay ese paso: el JSON de PostgREST y el de
los assets se parsea directo al modelo de dominio. Inventar una capa de
modelos de API que solo se copiaría a sí misma sería ceremonia, no diseño.

### El MVVM

`ui/core/vista_modelo.dart` tiene las tres piezas:

- **`Estado<T>`**, sellado: `Inactivo`, `Cargando`, `Listo`, `Fallo`.
  `Inactivo` no sobra: sin sesión media app se queda ahí, y con `Cargando` la
  pantalla pintaría un spinner que no termina nunca.
- **`VistaModelo`**, la base `ChangeNotifier`. Resuelve dos cosas que si no
  acaban copiadas en cada modelo: avisar después de `dispose` no revienta, y
  **una respuesta vieja no pisa a una nueva** —lo hacía `FutureBuilder` solo, y
  al quitarlo hubo que reponerlo con una guarda de generación—.
- **`SegunEstado<T>`**, que pinta spinner, aviso y contenido en **un** sitio.

Reglas al añadir una pantalla:

> **Un modelo por pantalla, en `view_models/`.** La vista no sabe de `Future`,
> ni de repositorios, ni de Supabase.
>
> **Los repositorios se inyectan por constructor**, con el patrón
> `progreso ?? RepositorioProgreso()`, y como campos **`late`**: cada uno
> resuelve `Supabase.instance.client`, así que armarlos en la lista de
> inicialización hace que crear el modelo reviente mientras `Arranque` todavía
> inicializa.
>
> **La pantalla libera el modelo siempre**, también el inyectado. La regla
> contraria dejó vivo el temporizador de Horario después de desmontar el árbol.
>
> **El modelo no navega.** Publica un dato —`irAlResultadoDe`— y la vista, que
> es quien tiene `BuildContext`, empuja la ruta.

Parece ceremonia y no lo es. Construir `RepositorioX()` o `Sesion()` como campo
de instancia de un `State` toca `Supabase.instance.client`, y entonces **la
pantalla no se puede montar en un widget test**. Ese fue exactamente el motivo
de que la cobertura estuviera en 34,9 %; hacerlos inyectables la subió a
**89,0 %** y sacó a la luz tres fallos de render que llevaban meses ahí.

**No hay `provider` ni contenedor de servicios**, y es una desviación
consciente de la guía: con un modelo por pantalla y cero estado compartido
entre ellas, un localizador global sería una indirección más sin nada que
resolver. La inyección por constructor también es inyección de dependencias, y
es la que un test usa sin instalar nada.

**Lo que se queda con `setState` son los widgets hoja** —una ficha del panel,
una fila de persona, un diálogo—: su `_enviando` es estado de ese elemento, no
de la pantalla. Un modelo por fila de lista sería el extremo contrario.

### La dirección de las dependencias se comprueba

Poner las capas en carpetas no separa nada: basta un `import` para que un
modelo empiece a saber de widgets, y el compilador no dice ni una palabra
porque importar «hacia fuera» es Dart válido.

`test/capas_test.dart` lo comprueba en cada `flutter test`:

| Capa | Puede importar | Nunca |
|---|---|---|
| `domain/` | nada del proyecto | `data/`, `ui/`, `core/` |
| `data/` | `domain/`, `core/` | `ui/` |
| `core/` | nada del proyecto | todo lo demás |
| `ui/` | lo que necesite | — |

Dentro de `ui/features/<f>/`, `views/` importa su `view_models/`, nunca al
revés: un modelo que importa su vista sabe de widgets.

Y dos reglas más, que son las que de verdad se rompen solas:

- **`Repositorio*` solo existe bajo `data/repositories/`.** El camino fácil es
  añadirlo al lado del modelo que devuelve, «que es donde se usa».
- **Solo `data/` toca `Supabase.instance` y `rootBundle`.** Son las dos
  fronteras externas de la app. Si `ui/` las cruza directamente, esa pantalla
  vuelve a ser imposible de montar en un test.

Esa comprobación ya encontró una: `formula.dart` vivía en `core/utils/` e
importaba el tema. No era una utilidad — es un `StatelessWidget`. Está en
`ui/core/widgets/`.

## 6. Tests

- `flutter analyze` **limpio**. Cero errores, cero avisos.
- `flutter test` **en verde** antes de cada commit. Hoy son 426, con 6
  saltados a propósito (los de `test/integracion/`, que piden credenciales
  reales, y el de desbordes si no encuentra Roboto).
- Un arreglo de fallo **llega con el test que falla sin él**, y se comprueba
  revirtiendo el arreglo. Un test que nunca ha estado en rojo no prueba nada.
- Los lints extra de `analysis_options.yaml` están cada uno porque encontró
  algo real. No se quitan para que pase un commit.

Dos trampas que ya costaron su tiempo y están documentadas donde tocan:

- **`test/desborde_test.dart` carga la Roboto real del SDK.** La fuente de
  prueba de `flutter_test` hace cada glifo un cuadro de un em completo: mide
  el doble y **inventa desbordes que no existen**. Si no encuentra la fuente,
  el archivo entero se salta — mejor eso que mentir.
- **Medir desbordes es a 320×568 con la letra hasta ×2.** Es el móvil barato
  con Accesibilidad subida, que es justo el de quien estudia dos horas al día
  en el teléfono.

## 7. Tema y accesibilidad

La semilla es **índigo `#4F46E5`** (`semillaMarca`), con
`DynamicSchemeVariant.fidelity`, sobre un lenguaje visual de iOS: superficies
del sistema, Large Titles, grupos inset, barra difuminada.

Dos reglas duras:

1. **El color de la marca nunca significa error.** Ni `primary`, ni
   `secondaryContainer`, ni ningún derivado de la semilla. Fallar es
   `error`/`errorContainer`; acertar es `exito`/`exitoContenedor`. Esto se ha
   roto ya tres veces —la última, la caja de «La respuesta era D» pintada de
   lila— porque con una semilla índigo el lila parece neutro y no lo es.
2. **Un relleno se pinta con su pareja `on*`.** Si el fondo cambia según un
   estado, el color del texto cambia con él.

El contraste **se comprueba, no se supone**: `test/tema_contraste_test.dart`
calcula los ratios WCAG reales en los dos modos y exige 4,5:1 en texto y 3:1
en lo que no es texto. Ya pilló un borde a 1,26:1.

Modo claro y modo oscuro son los dos obligatorios.

## 8. El hueco real no es código

**135 de las 392 preguntas del banco del APK no se pueden responder**: están
en los assets pero no en `public.preguntas`, así que el RPC las busca por
`codigo_externo` y contesta «Esa pregunta ya no está disponible».

| Curso | Sin responder |
|---|---|
| Biología | 53 de 67 |
| Inglés | **29 de 29** |
| Historia | 23 de 60 |
| Lenguaje | 15 de 24 |
| Química | 14 de 16 |
| Geografía | 1 de 5 |

Se arregla **resembrando la base desde el repo web**, no tocando la app. Para
probar práctica a mano, usar un curso con cobertura completa (Álgebra, Física,
Literatura…), nunca Inglés.

Comprobar con `node tool/cobertura.mjs`.

## 9. Plataformas

Solo `android/`, `ios/` y `web/`. `linux/`, `macos/` y `windows/` se quitaron:
no son destinos, y sus plugins exigen symlinks que este Windows no tiene
habilitados.

iOS necesita macOS — Xcode no existe en Windows. O hay un Mac, o se compila el
IPA en un runner `macos-latest`, más los 99 USD/año de Apple.

## 10. Cosas que solo puede hacer una persona

No son tareas de código y no se pueden cerrar desde este repo:

- registrar `matrixu://acceso` como Redirect URL en el panel de Supabase, o el
  enlace de recuperación de contraseña no vuelve a la app;
- resembrar `public.preguntas` con los 135 códigos que faltan;
- regenerar el ícono del lanzador, que sigue siendo granate del tema anterior;
- el registro desde la app está roto si se activa Turnstile en el proyecto:
  el widget es un iframe de Cloudflare y no hay equivalente nativo.
