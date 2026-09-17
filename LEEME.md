# Matrix U — app móvil

Porte a Flutter de la app web (`C:\source\MATRIX-U`). Mismo backend, misma
base de datos, misma paleta; interfaz reescrita.

## Arrancar

```bash
# 1. Traer el catálogo del repo web (temario, teoría, preguntas → assets/)
node tool/sincronizar-datos.mjs

# 2. Configurar Supabase
cp config/dev.ejemplo.json config/dev.json   # y rellenar los dos valores

# 3. Correr
flutter run --dart-define-from-file=config/dev.json
```

Sin el paso 1 la app arranca pero no encuentra contenido, y las cuatro
pantallas que leen el catálogo —Teoría, Práctica, Curso y Temario— lo dicen
con el nombre del archivo que faltó y la herramienta que lo trae, en vez de
quedarse girando (`Aviso.contenidoLocal`). Sin el 2 arranca sin sesión y avisa
por pantalla.

Para saber cuánto del sílabo tiene preguntas con las que practicar:

```bash
node tool/cobertura.mjs
```

## Cómo se reparte el trabajo con la web

| Pieza | Dónde vive | Se toca aquí |
|---|---|---|
| Esquema, RLS, 19 funciones RPC | `MATRIX-U/supabase/` | **No.** `supabase_flutter` llama las mismas funciones |
| Catálogo (temario, teoría, preguntas) | `MATRIX-U/data/**/*.json` | **No.** Se copia a `assets/datos/` con `sincronizar-datos` |
| 3 590 figuras de teoría + 1 de preguntas (83 MB) | `MATRIX-U/public/{teoria-figuras,preguntas}/` | **No.** Se piden por red al CDN de la web — ver «Las figuras» |
| Interfaz | — | **Todo.** Es lo único que se reescribe |

`assets/datos/` está en `.gitignore` a propósito: su fuente de verdad es el
repo web, y versionarlo aquí sería una segunda copia que se acabaría separando.
Lo mismo con `assets/formulas_banco.json`.

## Las claves de respuesta NO viajan en el APK

Es la regla que más fácil se rompe sin darse cuenta, así que va antes que nada.

`src/lib/preguntas.ts` declara como REGLA CENTRAL que el tipo que cruza al
cliente no lleva `clave` ni `explicacion`: el banco completo se queda en el
servidor, y en Postgres la columna `clave` está revocada para el rol
`authenticated`. La única forma de saber la respuesta es responder y que el RPC
`responder_pregunta` te la diga.

**Aquí no hay servidor donde esconderla.** Un asset de Flutter es un archivo
dentro del APK, y un APK es un ZIP. Copiar `data/preguntas/*.json` tal cual
—que es lo que se hacía hasta el 2026-09-07— publicaba **395 claves en texto
plano** a cualquiera con `unzip`.

Hoy `tool/sincronizar-datos.mjs` las borra al copiar (`despublicar()`), y
`test/datos_test.dart` lo verifica contra el asset real en cada `flutter test`.
Para comprobarlo sobre el binario:

```bash
unzip -p build/app/outputs/flutter-apk/app-debug.apk \
  'assets/flutter_assets/assets/datos/preguntas/*' | grep -c '"clave"'   # → 0
```

**Consecuencia de producto, no accidente:** la app **no puede corregir sola**,
así que **no hay práctica anónima**. La web sí la ofrece —`corregir()` califica
al alumno sin cuenta desde el servidor—; en el móvil eso exigiría repartir el
banco resuelto. Sin sesión, la pantalla de práctica lo dice y ofrece entrar.

## Las fórmulas: qué se sabe

La web emite MathML y lo dibuja el navegador. Flutter no tiene motor de MathML,
así que `lib/matematicas/formula.dart` pasa el LaTeX por `flutter_math_fork`,
que cubre menos que KaTeX. Cuánto menos, medido sobre el banco real:

```bash
node tool/extraer-formulas.mjs
flutter test test/medir_formulas_test.dart
```

Ese `assets/formulas_banco.json` (1,4 MB) **no viaja en el APK**: lo declaraba
`pubspec.yaml` hasta el 2026-09-10, pero nadie en `lib/` lo abre — solo el
test, y con `File(...)` del disco, no con `rootBundle`. Se iba entero en cada
instalación sin que ninguna pantalla lo tocara, y de paso rompía una copia
recién clonada, porque el archivo está en `.gitignore` y `sincronizar-datos`
no lo genera: Flutter fallaba con «unable to find asset» hasta que alguien
corriera esta herramienta.

Resultado del 2026-09-07, sobre 13 720 fórmulas únicas:

```
compilan   12 662
fallan      1 058   (7,7 %)
```

**Ninguna de `data/preguntas/`.** Las 1 058 son todas de `data/teoria/`, y 972
de ellas son fórmulas partidas por la extracción del PDF (`u}`, `2aacos60}`).

Y lo que cierra la pregunta: se pasaron **las mismas 13 720 fórmulas por
KaTeX**, el motor de la web. Falla 1 056. Los dos conjuntos están anidados —
`flutter_math_fork` falla todo lo que KaTeX ya falla, **más exactamente 2**:

```
\frac{verdadera}{✔️ Argumento}
\frac{verdaderas}{Premisas} \frac{válido}{✔️ Argumento}
```

Las dos llevan un emoji dentro de la fórmula; es contenido roto en el origen,
no un hueco del motor. **Cambiar de motor cuesta 2 fórmulas de 13 720
(0,015 %).** Las otras 1 056 ya están rotas hoy en producción (ESTADO.md § 8,
«Fórmulas rotas») y se arreglan en el repo web, que es donde viven.

Esto responde el riesgo que ESTADO.md dejaba abierto («el riesgo mayor no es el
volumen sino las fórmulas»): no lo es. Reproducir la comparación:

```bash
node -e "const k=require('katex'),f=require('./assets/formulas_banco.json');
let n=0; for(const x of f){try{k.renderToString(x.tex,{throwOnError:true,strict:false})}catch{n++}}
console.log(n)"   # desde el repo web, que tiene katex instalado
```

Vuelve a correr la medición cuando cambies de versión de `flutter_math_fork` o
cuando entre contenido nuevo.

## Estado del porte

| Pantalla | Estado |
|---|---|
| Teoría — cursos, índice, sección, anterior/siguiente | Funciona con contenido real |
| Práctica — cursos, tanda, corrección por RPC, resumen | Funciona; exige sesión |
| Repaso — programadas hoy / falladas, tanda | Funciona; exige sesión |
| Simulacro — lista, sesión cronometrada, resultado con percentil | Funciona; exige sesión |
| Progreso — perfil, racha, diagnóstico por subtema, reportes | Funciona; exige sesión |
| Acceso — entrar, registro, recuperar contraseña | Funciona |
| Buscar — subtema por nombre o código, con debounce | Funciona con contenido real |
| Temario — cifras, áreas, cursos | Funciona con contenido real |
| Curso — cabecera, botones a Teoría/Práctica, temas con progreso | Funciona con contenido real |
| Inicio — portada, panel personal, accesos directos | Funciona; el panel exige sesión |
| Práctica adaptativa — prioriza subtemas flojos, acota por curso | Funciona; exige sesión |
| Horario — bloques semanales, próximo bloque, aviso en pantalla | Funciona; exige sesión |
| Panel (staff) — resumen, revisión, reportes, personas/roles | Funciona; exige rol de staff |

**22 de 22 rutas de producto portadas.** Solo quedan fuera `/autoria`
(herramienta de autoría de contenido, uso interno de quien mantiene el banco,
no de un alumno ni de un docente) y `/offline` (página de respaldo de un PWA
sin conexión; una app nativa no la necesita — el manejo de "sin red" ya está
en cada pantalla).

**Los 18 RPC del esquema que un cliente puede llamar están en uso.** El
esquema declara 19; la que falta es `inscritos_confirmados`, que cuenta
inscritos pagados de una clase para la vitrina de matrículas — una parte del
producto que no existe ni aquí ni en la web (`limpieza_permisos.sql` le
revocó el acceso anónimo justamente por eso). No es un hueco del porte.
Aparte quedan `manejar_nuevo_usuario` y `private.programar_repaso`, que las
invoca Postgres desde un disparador y tienen el `execute` revocado a todo el
mundo.

Buscar y Temario no tienen hueco en la barra de 5 pestañas —la barra ya tiene
sus cinco, igual que en la web, que tampoco las pone en el nav móvil
(`layout.tsx`: ese header solo es visible en escritorio)— así que se llega por
el ícono de lupa del `AppBar`; el estado vacío de Buscar ofrece "Ver el
temario completo" para la otra mitad del camino. Inicio tampoco tiene hueco
—en la web, igual: sin el header de escritorio, no hay forma de volver salvo
un enlace explícito— así que `Arranque` la muestra primero y el ícono de casa
del `AppBar` es el enlace explícito de vuelta.

`Curso` (`lib/pantallas/curso.dart`) no estaba pedida por su nombre, pero es
el destino al que enlazan un resultado de Buscar y una tarjeta de Temario en
la web (`/curso/[slug]`): sin ella, las dos pantallas serían un callejón sin
salida — exactamente lo que el propio código de la web señala que ERA antes
de escribirse esa página. `lib/datos/vinculos.dart` porta el mapeo curso
oficial → curso de teoría (`TEORIA_POR_CURSO` en `vinculos.ts`), la única
pieza que conecta las dos taxonomías del proyecto y que no se puede derivar
de los datos mismos — es una tabla escrita a mano, y tiene test dedicado
(`vinculos_test.dart`) porque una desincronización ahí no da error: el curso
simplemente deja de ofrecer "Estudiar la teoría".

Los datos están portados enteros (`lib/datos/`): `temario.dart` y
`preguntas.dart` reproducen `src/lib/{temario,preguntas}.ts` y
`test/fidelidad_test.dart` fija que dan las mismas cifras — 19 cursos, 207
temas, 956 subtemas, 392 preguntas.

### Dos cosas que el simulacro hace y la web no

No son adornos: sin ellas el examen se rompe en un móvil.

- **Retomar un intento a medias.** En la web se vuelve por el historial del
  navegador. Una app no tiene barra de direcciones, así que cerrarla a mitad
  de examen dejaría el intento abierto e inalcanzable, con el cronómetro
  corriendo hasta agotarse solo. `intentoEnCurso()` lo recupera, y mientras
  haya uno abierto no se deja empezar otro.
- **El gesto de atrás no abandona el examen.** Se intercepta con `PopScope` y
  ofrece finalizar, que es la decisión real.

El plazo lo hace cumplir Postgres (`20260827120000_cronometro_en_servidor.sql`),
no el cronómetro de pantalla: este solo dibuja. Cuando el servidor rechaza una
respuesta por plazo vencido llega como `TiempoAgotado`, que **no se reintenta**
—no es un fallo de red— y cierra el intento.

`instanteUtc()` normaliza `iniciado_en` a UTC pase lo que pase. Es defensivo a
propósito: si un `timestamptz` llegara sin offset, `DateTime.parse` lo leería
como hora local y en Perú (UTC-5) el plazo se correría cinco horas. Hay test.

### Progreso: qué lleva dentro

«Progreso» apunta a `/cuenta` en la web (`nav-mobile.tsx`); aquí se conserva el
nombre de la pestaña porque lo que domina la pantalla es el diagnóstico.

Esta sección decía, hasta la auditoría del 2026-09-16, que faltaban dos cosas
que para entonces ya estaban hechas — y lo decía tres párrafos después de la
tabla de «Estado del porte», que las daba por funcionando. Se corrige aquí
porque en este repo el comentario ES la documentación, y una que se
contradice consigo misma vale menos que ninguna:

- El bloque de **horario** sí está: `_ProximoBloque` lee el mismo horario que
  gestiona `PantallaHorario` y enlaza a ella (`HorarioConBarra`).
- El **panel de docente/admin** sí está: `_PanelStaff` abre `PantallaPanel`
  de verdad, no un aviso de que el panel sigue en la web.

Las seis peticiones de la pantalla salen a la vez con `Future.wait`, no
encadenadas — ver la nota en `_pedir()`.

Los umbrales del diagnóstico (`umbralFlojo` 50, `umbralBien` 70) están copiados
de `diagnostico.tsx` para que las dos plataformas cuenten «subtemas dominados»
igual. El acierto global sale del crudo (correctas/respondidas), nunca del
promedio de porcentajes — con volúmenes distintos eso daría otra cifra, y hay
test que lo fija.

### Turnstile no está

La web protege el registro con un widget de Cloudflare; es un iframe y no
tiene equivalente nativo. Importa menos de lo que parece —quien valida el token
es el servidor de auth de Supabase, y un bot nunca necesitó pasar por el
formulario, porque la clave publishable es pública— pero **si activas el
CAPTCHA en el panel de Supabase, el registro desde el móvil dejará de
funcionar** hasta que se le ponga un widget. `traducir()` en
`lib/datos/sesion.dart` detecta ese caso y lo dice en español.

### El markdown de teoría, y por qué el orden de los pasos no es negociable

`lib/datos/markdown_teoria.dart` porta `src/lib/markdown-teoria.ts`. El
extractor de PDF deja una línea del documento original por línea de texto,
unidas por `\n` simples, así que hay que separarlas en bloques — pero **antes**
hay que sacar las fórmulas de en medio:

1. Se sustituyen las fórmulas por centinelas (`\uE000n\uE001`). En la web lo
   consigue `renderizarMatematicas`, que emite MathML en una sola línea; aquí
   el renderizado ocurre al pintar, así que hace falta el centinela.
2. Cada línea pasa a ser su propio bloque.
3. Se clasifica: título, figura, ítem de lista o párrafo.

Saltarse el paso 1 no da un error: parte en dos las fórmulas `$$…$$` que ocupan
varias líneas, y **el 27 % de las secciones tiene alguna**. Los dos trozos
parecen contenido, que es lo que lo hace peligroso. `test/teoria_corpus_test.dart`
cuenta las fórmulas antes y después sobre las 1 829 secciones reales y exige
que cuadren: **17 680 = 17 680**.

Medido sobre ese mismo corpus, lo que el porte arregla:

| | Antes | Ahora |
|---|---|---|
| Secciones con `**asteriscos**` a la vista | 984 (54 %) | 0 |
| Secciones con `![figura](assets/…)` literal | 865 (47 %) | 0 |

El parser cubre exactamente lo que hay en el corpus (negrita, línea entera en
negrita, figura, listas, encabezados, cursiva). Tablas, citas, código y enlaces
aparecen en menos del 1 % y pasan como texto llano a propósito: un motor de
markdown completo para cinco casos sería más superficie de la que se gana.

## Las figuras: de dónde salen de verdad, y por qué hoy no se ven

**No van a Supabase Storage.** Esa era la intención que dejó `ESTADO.md`
(«van a Supabase Storage, no caben en un APK») y nunca se implementó del lado
web: `src/lib/figuras.ts` documenta la decisión real, que es la contraria —las
3 590 figuras de teoría y la de preguntas viven como estáticos versionados en
`public/`, servidos por el CDN de Vercel, precisamente para no depender de un
bucket con CORS o CSP propios.

Eso es una ventaja para el móvil: no hace falta Storage ni una cuenta nueva,
basta con pedir la misma URL que ya sirve la web. `Config.urlFiguraTeoria()` y
`Config.urlFiguraPregunta()` (`lib/config.dart`) arman esa URL contra
`Config.urlSitio` (por defecto `https://matrix-u.vercel.app`, con
`--dart-define=URL_SITIO=…` para apuntar a otro despliegue), y `FiguraRed`
(`lib/pantallas/figura_red.dart`) hace el `Image.network` con manejo de error:
si no llega —sin conexión, un `.svg` (Flutter no lo pinta sin una librería
aparte; hoy es 1 figura de 395 y no compensa sumarla), o un 404—, cae al mismo
aviso «no disponible» de siempre. Nunca un hueco roto.

**Estado al 2026-09-08: ya se ven.** Hasta ese día caían casi todas en 404 —el
despliegue de producción al que apuntaba `matrix-u.vercel.app` era de antes de
que se subieran las figuras al repo web (`421eab0`)— y se resolvió con un
`vercel --prod` manual desde `MATRIX-U`, verificado contra el sitio real:

```
teoria-figuras/8fc119d04b59a8e6.webp   → HTTP 200  image/webp
preguntas/geo-2027-004-trapecio.svg    → HTTP 200  image/svg+xml
```

**Ese despliegue casi no sale por otro motivo, y vale la pena dejarlo
anotado.** Sin un `.vercelignore`, el CLI de Vercel no respetó las exclusiones
de `.gitignore` para `base de datos matrix/` —una carpeta con espacios en el
nombre, 959 MB y 7 878 archivos, sobre todo el entorno virtual de Python de
las herramientas de documentación— e intentó subirla entera junto al sitio.
Eso agotó la cuota de subidas del plan gratuito de Vercel («more than 5000
archivos», código `api-upload-free`) antes de llegar siquiera a las figuras
reales. `MATRIX-U/.vercelignore` la excluye ahora explícitamente; sin él,
cualquier despliegue futuro puede volver a fallar por lo mismo.

Si el sitio vuelve a quedarse atrás de las figuras del repo —una nueva
sincronización de contenido sin desplegar—, repetir es
`vercel --prod --archive=tgz` desde `MATRIX-U` (el `--archive` importa: sin
él, Vercel sube archivo por archivo y el límite de la cuenta se alcanza antes
con solo las ~3 700 figuras). O esperar a que el CI lo haga cuando se
restaure (ESTADO.md § 1, el workflow que se cayó por falta de scope).

### 149 de esas figuras son un rectángulo negro, y no es un problema de red

Verificado bajando las 3 590 contra el sitio real: **las 3 590 responden HTTP
200 con una imagen válida.** Ninguna está rota en el sentido de un enlace
muerto. (3 498 son `.webp` y 92 siguen siendo `.png` — el lote que
`optimizar-figuras.mjs` no convirtió. Existen las dos en `public/`, las dos se
piden igual y `Image.network` decodifica las dos, así que la mezcla no es un
problema; pero el `image/webp` que decía aquí antes no valía para las 92.)

Pero 149 (4,2 %) decodifican correctamente a un solo color —siempre negro
puro, `stdev` 0.00 en los tres canales, medido con `sharp`— y eso mostrado en
pantalla es peor que un aviso: un rectángulo negro sin ningún texto que diga
qué falta.

**Tampoco es una regresión de la conversión a WebP.** Se comprobó el PNG
original de una de ellas en
`base de datos matrix/markdown/assets/020d3622f04d7e76.png` —antes de que
`optimizar-figuras.mjs` tocara nada— y ya era negro. El defecto viene de la
extracción del PDF de origen, el mismo lote que `ESTADO.md` documenta para
las «fórmulas rotas» (§ 8). Estaba ahí desde siempre; lo que cambió el
2026-09-08 es que antes ninguna figura llegaba a mostrarse (404), así que
tampoco se veía esto.

`tool/detectar-figuras-rotas.mjs` mide la lista completa (requiere `sharp`,
que no es dependencia del proyecto —se instala aparte, solo para correr esta
auditoría puntual— y escribe `assets/figuras_rotas.json`, versionado, que
`lib/datos/figuras_rotas.dart` precarga en `Arranque` junto a Supabase.
`FiguraRed` consulta esa lista antes de pedir la imagen por red: si el
archivo está ahí, muestra «sin contenido en el original» en vez de
intentarlo y dejar ver un rectángulo negro. `test/figuras_rotas_test.dart`
fija tres nombres verificados a mano viendo el píxel.

Vuelve a correr la herramienta si el banco trae figuras nuevas —una figura
nueva no entra sola en la lista— o si quieres confirmar que la cifra sigue
en 149.

### El SVG de pregunta se veía sin figura, y ya no

Hasta el 2026-09-10, `FiguraRed` detectaba un `.svg` por la extensión y caía
directo al aviso «no disponible» — `Image.network` no decodifica SVG, es un
formato vectorial, no una imagen rasterizada, y dárselo igual habría gastado
un viaje de red para terminar en el mismo error que un 404. Con una sola
figura de pregunta usando ese formato (`geo-2027-004-trapecio.svg`, en
`GEO-06-01`), esa pregunta se resolvía sin ver el trapecio que describe.

Se sumó `flutter_svg` y ahora esa rama pinta con `SvgPicture.network` en vez
de degradarse. No es una dependencia por un caso de hoy: la herramienta de
autoría del repo web (`/autoria`, la que no se portó — ver «Estado del
porte») emite figuras nuevas en SVG, así que cada trapecio, círculo o gráfico
vectorial que se dibuje ahí de ahora en más llega en ese formato. Comprobado
contra el archivo real (no solo que compile): pasado por
`SvgPicture.string`, produce un lienzo de 420×260 sin excepciones.

## El APK de release no tenía permiso de internet

Existió hasta el 2026-09-08 y no se detectó antes porque cada build de prueba
fue `--debug`. `android/app/src/debug/AndroidManifest.xml` —que solo se
empaqueta en debug— declara `android.permission.INTERNET` para que el hot
reload funcione; el manifiesto principal nunca lo declaraba. En un APK de
release, comprobado extrayendo el manifiesto fusionado
(`build/app/intermediates/packaged_manifests/release/…/AndroidManifest.xml`):

```
debug     INTERNET: 1
release   INTERNET: 0    ← toda la capa Supabase moría en silencio
```

Teoría seguía funcionando —vive en los assets—, lo que lo hacía peor: la app
parecía medio viva. Está en `android/app/src/main/AndroidManifest.xml` ahora;
si algún día se reordena el manifiesto, que el permiso siga estando ahí y no
solo en el de debug es lo que hay que no romper.

## «You must initialize the supabase instance» al hacer hot restart

No pasa en un APK instalado normalmente —eso arranca siempre en frío—; pasa
en `flutter run` al pedir un *hot restart* (la R mayúscula, o lo que dispara
un cambio de código que un hot reload no puede aplicar). El motor de Flutter
puede disparar un primer «warm up frame» apenas reinicia el isolate, sin
esperar a que el `await Supabase.initialize()` de `main()` termine. Ese frame
reconstruía `Armazon` —que construye `Sesion()` como campo de instancia, y
`Sesion()` toca `Supabase.instance.client` en su propio constructor— contra
un singleton que el isolate nuevo acababa de resetear.

De paso, el mismo patrón escondía un segundo bug real, sin relación con el
hot restart: correr la app sin `config/dev.json` en absoluto —`main.dart`
nunca llamaba a `Supabase.initialize()` en ese caso, pero `Armazon` construía
`Sesion()` igual, sin condición— también reventaba con la misma aserción, en
vez de mostrar `Config.ayuda`, que existía pero nadie llegaba a ver.

`lib/main.dart` ya no espera la inicialización en `main()`: `runApp()` monta
`Arranque` de inmediato, y es su `initState()` —que el framework garantiza
posterior al primer build, warm-up-frame incluido— quien la dispara. El
primer build de `Arranque` nunca toca `Supabase.instance`: solo decide entre
el aviso de `_SinConfigurar`, un spinner mientras `_inicializacion` resuelve,
o `Armazon`. `test/arranque_test.dart` fija el caso sin configurar (antes
crasheaba, ahora muestra la ayuda) y que el primer build por sí solo —sin que
nada más corra— no lanza ninguna excepción.

## Nombre e ícono

El nombre que ve el alumno en el launcher es `android:label` en
`AndroidManifest.xml` — no el `name:` de `pubspec.yaml`, que es un identificador
interno del paquete y nunca sale en pantalla. Estaba en `matr_u`; ahora dice
`Matrix U`.

El ícono sale de `assets/marca/icono.png` (copiado del `ICONO.png` del repo
web — 1024×1024, el lockup de marca completo: la M sobre el arco, "Matrix U"
debajo) vía `flutter_launcher_icons`:

```bash
dart run flutter_launcher_icons   # regenera android/app/src/main/res/mipmap-*/
```

Es el lockup completo, no un glifo aislado, porque no existe una versión
solo-glifo en el repo de origen —los tres archivos que hay (`ICONO.png`,
`src/app/icon.png`, `src/app/apple-icon.png`) llevan todos el wordmark— y
recortar uno no es una decisión de diseño que corresponda tomar aquí. A 48dp
(el tamaño real del launcher) el texto se lee como textura, no como palabra;
al tamaño grande de la lista de apps o de ajustes se lee entero. Mismo trato
que ya recibe en la pestaña del navegador de la web.

Sin capas de foreground/background separadas no se generó ícono adaptativo
(Android 8+): es el ícono clásico, con su fondo cuadrado-redondeado propio
dentro de la máscara que aplique cada launcher — no una regresión frente a lo
que había, que era el mismo trato.

## Horario: lo único que se dejó fuera a propósito

`notificador-horario.tsx` pide permiso de `Notification` del navegador — y en
su propio comentario admite el límite: «solo funciona con la pestaña abierta:
no hay Service Worker ni Push». `PantallaHorario` reproduce exactamente ese
mismo límite con un `Timer` mientras la pantalla está abierta, sin sumar un
plugin de notificaciones locales ni permisos nuevos de Android — el alcance de
la web no lo pedía tampoco: ni ahí sobrevive a cerrar la pestaña.

## Lo que falta, y por qué no está en la lista de código

**Ya verificado.** El arnés en `test/integracion/supabase_real_test.dart`
corrió contra Supabase real con una cuenta de prueba (creada por Admin API,
confirmada sin correo) en modo lectura: los RPC de alumno llegan con
exactamente los tipos que cada repositorio espera — cero discrepancias.
Habría fallado con `flutter_test`: ese binding intercepta todo `HttpClient`
y fuerza 400 en cada petición, protección deliberada contra que un widget
test dispare red por accidente. Tampoco sirve `Supabase.initialize()` de
`supabase_flutter` fuera de una app real, porque usa `shared_preferences`
para persistir sesión y eso necesita un canal de plataforma que no existe
en un proceso de test. Por eso el archivo usa `package:test` (Dart puro)
más el paquete base `supabase`, construyendo el `SupabaseClient` a mano sin
el wrapper de Flutter — los repositorios ya aceptaban ese cliente inyectado,
mismo tipo en los dos paquetes, así que no hubo que tocarlos.

Único hallazgo: `preguntas_recomendadas` devuelve `motivo` y
`porcentaje_subtema`, dos campos que `RepositorioRepaso` no usa todavía —
no es un error, es una mejora futura posible si se quiere explicar al
alumno por qué se le recomendó cada pregunta.

Los tests de escritura del arnés (`grupo "lo que ESCRIBE en la base"`)
quedan aparte, con `skip` salvo que se pase `--dart-define=ESCRITURA=1`:
no se corrieron, porque escribir en la base de un alumno de prueba real
es una decisión que le toca al usuario, no algo que valga la pena hacer
sin pedirlo explícitamente cada vez.

La recuperación de contraseña y el deep link, que salían en esta lista, se
hicieron en la auditoría del 2026-09-16 — ver «Volver del correo a la app», más
abajo. Quedan dos cosas, y las dos son decisiones o acciones del usuario, no
código:

**Dar de alta `matrixu://acceso`** como «Redirect URL» en el panel de Supabase.
Sin eso, el deep link está puesto en la app pero el servidor de auth lo ignora
en silencio y manda los correos a la web. Ver la sección de abajo.

**El CAPTCHA**, que sigue sin activarse en el panel de Supabase — y si se
activa, el registro desde la app se rompe porque no hay widget de Turnstile
nativo (ver «Turnstile no está», arriba). Es una decisión y una acción del
usuario, no algo que el código pueda resolver solo.

## Volver del correo a la app

Los dos correos que manda la app —confirmar la cuenta y recuperar la
contraseña— vuelven por `matrixu://acceso`, declarado como `intent-filter` en
`AndroidManifest.xml`. `supabase_flutter` ya trae `app_links` y recoge el URI
solo: no hace falta código de plataforma.

**Hasta el 2026-09-16 ese `intent-filter` no existía**, aunque el comentario de
`lib/datos/sesion.dart` daba por hecho que sí («el enlace de confirmación
vuelve por un deep link, que se declara en el manifiesto»). El correo abría la
web y había que volver a la app a mano. Para confirmar la cuenta era un paso de
más; para recuperar la contraseña era imposible, porque el token es de un solo
uso y solo vale dentro de la app que lo pidió — así que **no había ninguna
forma de recuperar una contraseña olvidada**, y quien la olvidaba perdía su
progreso, su racha y sus simulacros para siempre.

El esquema es `matrixu` y no el `applicationId` al revés (`com.ander_u.matr_u`)
porque un esquema de URI no admite guiones bajos (RFC 3986): Android aceptaría
el manifiesto igual y el enlace no abriría nunca.

**Falta un paso que no es código.** `matrixu://acceso` tiene que estar dado de
alta como «Redirect URL» en el panel de Supabase (Authentication → URL
Configuration). Si no está en esa lista, el servidor de auth **ignora en
silencio** lo que se le mande y usa la «Site URL» —la web— sin devolver ningún
error: el correo llega, el enlace abre el navegador y parece que la app no
tiene deep link. Es el fallo más difícil de diagnosticar de todo este tramo.

La escucha vive en `Arranque` (`lib/main.dart`) y no en `Armazon` ni en
`PantallaEntrar` porque el enlace puede llegar con la app cerrada: Android la
arranca de cero con el `VIEW` del `intent-filter`, y en ese arranque lo único
montado es `Arranque`.

El acuse de «te mandamos el correo» es **el mismo exista la cuenta o no**. El
servidor de auth responde igual en los dos casos a propósito; si la pantalla
distinguiera «no hay cuenta con ese correo», sería un comprobador de quién está
registrado aquí que cualquiera podría usar sin tener cuenta.

## Las pantallas también tienen tests

Hasta la auditoría del 2026-09-16, `datos/` estaba al 95 % y `pantallas/` al
1 %. No era por difícil: era por cómo estaban escritas. `RepositorioX()` y
`Sesion()` resuelven `Supabase.instance.client` **en su constructor**, así que
una pantalla que los construye como campo de instancia no se puede montar en un
widget test — lanza «You must initialize the supabase instance» antes de pintar
nada. Ese patrón era exactamente la frontera entre las dos cifras.

Hoy las once pantallas que hablan con el servidor aceptan sus repositorios
inyectados (`repositorio:`, `sesion:`, `progreso:`…). En producción nadie los
pasa y se construyen igual que antes; en un test se les da un `SupabaseClient`
con un `http.Client` espía, que es el mismo arnés que ya usaba `datos/`.

Cobertura: **34,9 % → 89,0 %**, con 396 tests. Ningún archivo de `lib/` queda
a cero, y el más bajo está en el 64,9 %.

### Los tres fallos que aparecieron al poder mirar

Ninguno de los tres se escondía. Los tres vivían en pantallas que no se podían
montar en un test, y los tres los encontró el primer test que las montó.

**Progreso no dibujaba las tarjetas de racha y repasos.** El
`Row(crossAxisAlignment: stretch)` colgaba directo de un `ListView`, que ofrece
altura ilimitada; `RenderFlex` lo traduce a `tightFor(height: Infinity)` y salta
la aserción de constraints. Caja roja en depuración. `inicio.dart` ya lo hacía
bien con un `IntrinsicHeight`; Progreso se había quedado sin la envoltura, y
`desborde_test.dart` —que existe justo para cazar esto— no podía alcanzarla.

**La ficha de revisión del panel tampoco.** El `ExpansionTile` de
«Explicación» lleva un `ListTile` dentro, y un `ListTile` pinta su fondo y sus
ondas sobre el `Material` más cercano; aquí el ancestro era el `Container` de la
ficha, con color propio. Flutter lo detecta y lanza «ListTile background color
or ink splashes may be invisible», que deja la ficha entera en rojo. Salta
siempre que la pregunta trae explicación — el caso normal de una pregunta
escrita, y la pantalla donde un docente decide qué se publica. Se arregla con
`Material(type: MaterialType.transparency)`, que es lo que recomienda el propio
framework y no cambia cómo se ve.

**Práctica dejaba el intento abierto** al salir a mitad de tanda. Está contado
en su propio commit.

### Lo que queda fuera, dicho por su nombre

`figura_red.dart` llega al 64,9 %, y el resto no es pereza: la rama de «la
descarga falló» no se puede ejercitar en un widget test porque
`cached_network_image` guarda en disco a través de `path_provider`, que necesita
un canal de plataforma inexistente en un proceso de test — la carga ni progresa
ni falla, se queda en el marcador. La rama del `.svg` queda fuera por lo mismo
y algo peor: el parser lanza «Invalid SVG data» DESPUÉS de que el test termine,
así que no hay forma de consumir esa excepción sin un arnés de red, y un test
que falla por el reloj en vez de por el código es peor que no tenerlo.

Lo que sí está cubierto de ese archivo es lo que decide ANTES de tocar la red,
que es donde vive el criterio: qué figura no se pide siquiera —las 149 rotas—,
qué `alt` se anuncia y cuál es ruido, qué forma reserva el hueco, y que «sin
contenido en el original» y «no disponible todavía» sean avisos distintos.

`practica_adaptativa.dart` (70,8 %) y `main.dart` (77,9 %) son los dos
siguientes, y lo que les falta es ramas de pintado sobre datos que ya están
probados en su repositorio.

### Una cosa que el servidor ya manda y la app tira

`preguntas_recomendadas` devuelve también `motivo` y `porcentaje_subtema`, dos
campos que `RepositorioRepaso` descarta. Con ellos, la práctica adaptativa
podría explicar **por qué** le pone delante cada pregunta —«nunca la has
visto», «la fallaste», «vas al 40 % en este subtema»— en vez de pedir fe.

No está hecho, y la razón es deliberada: **los valores de `motivo` viven en el
repo web**, no aquí, y no se pueden deducir desde este lado. Inventar etiquetas
en español para valores que nadie ha visto es exactamente el error que produjo
la clave ausente convertida en «A». Cuando se tengan a mano, es un cambio
pequeño: añadir los dos campos al modelo y una línea bajo cada pregunta.

## Lo que de verdad falta no es código: es banco de preguntas

El porte está completo y los tests pasan, y eso hace fácil leer «terminado»
donde solo dice «funciona». La app está terminada; **el contenido no**:

```bash
node tool/cobertura.mjs                    # el cuadro completo
node tool/cobertura.mjs --subtemas ALG     # los huecos de un curso, uno a uno
```

Medido el 2026-09-10 sobre el catálogo sincronizado:

```
Banco: 392 preguntas
Sílabo: 206 de 956 subtemas tienen al menos una (21,5 %)
```

Y el reparto es lo que importa, más que el total:

| Curso | Preguntas | Subtemas cubiertos |
|---|---|---|
| Historia | 60 | 26/36 (72 %) |
| Biología | 67 | 54/88 (61 %) |
| Lenguaje | 24 | 18/39 (46 %) |
| … | | |
| Geometría | 5 | 4/54 (7 %) |
| Educación Cívica | 26 | 3/46 (7 %) |
| Álgebra | 6 | 3/60 (5 %) |

Un postulante al área de Ingenierías abre Práctica y encuentra **6 preguntas
de Álgebra y 5 de Geometría** — los dos cursos que más pesan en su examen.
Ninguna pantalla miente sobre esto (Curso dice «N de M subtemas tienen
preguntas», Práctica ordena los cursos por cuántas tienen), pero tampoco lo
resuelve: las preguntas se escriben en el repo web, `data/preguntas/*.json`,
y de ahí llegan aquí con `sincronizar-datos`.

Consecuencias en la app, ninguna de ellas un fallo del código:

- **La práctica adaptativa se queda sin qué recomendar** en un curso flojo
  mucho antes de que el alumno deje de estar flojo: no hay preguntas nuevas
  que servirle.
- **El repaso espaciado** solo puede reprogramar lo que ya se respondió, así
  que en esos cursos se agota en una tanda.
- **El diagnóstico por subtema** deja en blanco 750 de los 956 subtemas: no
  es que el alumno no los domine, es que no hay con qué medirlo.

Los cursos de arriba de la lista (Historia, Biología) muestran cómo se ve la
app llena; los de abajo, cuánto queda. Es el trabajo pendiente más grande del
proyecto y no se arregla programando.

## Firmar el APK de release

Hasta el 2026-09-10 el build de release iba firmado con la **clave de
depuración** —lo que dejó el `flutter create`, con su `TODO` intacto—. Un APK
así se instala y se ve idéntico al bueno, así que el problema no aparece hasta
que se intenta publicar: Play lo rechaza, y aunque no lo hiciera, la clave de
debug es la misma en todas las máquinas del mundo, así que cualquiera podría
firmar una «actualización» de esta app.

Ahora `android/app/build.gradle.kts` lee `android/key.properties`:

```bash
cp android/key.ejemplo.properties android/key.properties   # y rellenar

# El almacén se crea UNA vez y se guarda fuera del repo. Si se pierde, no hay
# forma de actualizar la app publicada: hay que empezar con otro
# applicationId y los ya instalados se quedan atrás.
keytool -genkey -v -keystore ~/matrix-u-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias matrix-u
```

Sin ese archivo el build **sigue funcionando** —firma con la de debug, para
que `flutter run --release` no exija montar un keystore— y Gradle emite un
aviso diciendo que ese APK no es publicable. Comprobado que el aviso sale, con
la salvedad de que el `flutter` CLI filtra los avisos de Gradle: se ve con
`flutter build apk --release --verbose`, o llamando a `gradlew` directamente,
no en la salida normal. `key.properties`, `*.jks` y `*.keystore` están en
`.gitignore`.

Para publicar conviene además `--split-per-abi`. El APK único pesa 58,2 MB
porque lleva las tres ABI, y `x86_64` solo la usan los emuladores. Medido el
2026-09-10:

```
app-release.apk             58,2 MB   ← las tres juntas
app-arm64-v8a-release.apk   21,6 MB   ← casi cualquier teléfono de hoy
app-armeabi-v7a-release.apk 19,3 MB
app-x86_64-release.apk      23,1 MB   ← emuladores
```

## Plataformas

Solo `android/`, `ios/` y `web/`. Se quitaron `linux/`, `macos/` y `windows/`:
no son destinos y sus plugins exigen symlinks que este Windows no tiene
habilitados (Developer Mode).

Para iOS hace falta macOS — Xcode no existe en Windows. O hay un Mac, o se
compila el IPA en un runner `macos-latest`, más los 99 USD/año de Apple.
