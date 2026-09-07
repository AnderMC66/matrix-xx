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

Sin el paso 1 la app arranca pero no encuentra contenido. Sin el 2 arranca sin
sesión y avisa por pantalla.

## Cómo se reparte el trabajo con la web

| Pieza | Dónde vive | Se toca aquí |
|---|---|---|
| Esquema, RLS, 28 funciones RPC | `MATRIX-U/supabase/` | **No.** `supabase_flutter` llama las mismas funciones |
| Catálogo (temario, teoría, preguntas) | `MATRIX-U/data/**/*.json` | **No.** Se copia a `assets/datos/` con `sincronizar-datos` |
| 3 590 figuras de teoría (83 MB) | `MATRIX-U/public/teoria-figuras/` | Pendiente: van a Supabase Storage, no caben en un APK |
| Interfaz | — | **Todo.** Es lo único que se reescribe |

`assets/datos/` está en `.gitignore` a propósito: su fuente de verdad es el
repo web, y versionarlo aquí sería una segunda copia que se acabaría separando.
Lo mismo con `assets/formulas_banco.json`.

## Las fórmulas: qué se sabe

La web emite MathML y lo dibuja el navegador. Flutter no tiene motor de MathML,
así que `lib/matematicas/formula.dart` pasa el LaTeX por `flutter_math_fork`,
que cubre menos que KaTeX. Cuánto menos, medido sobre el banco real:

```bash
node tool/extraer-formulas.mjs
flutter test test/medir_formulas_test.dart
```

Resultado del 2026-09-07, sobre 13 720 fórmulas únicas:

```
compilan   12 662
fallan      1 058   (7,7 %)
```

**Ninguna de `data/preguntas/`.** Las 1 058 son todas de `data/teoria/`, y 972
de ellas son fórmulas partidas por la extracción del PDF (`u}`, `2aacos60}`) —
las mismas que KaTeX ya falla hoy en la web (ESTADO.md § 8, «Fórmulas rotas»).
El motor no es el cuello de botella.

Vuelve a correr la medición cuando cambies de versión de `flutter_math_fork` o
cuando entre contenido nuevo.

## Estado del porte

| Pantalla | Estado |
|---|---|
| Teoría — cursos, índice, sección, anterior/siguiente | Funciona con contenido real |
| Repaso, Práctica, Simulacro, Progreso | Marcador «por portar» |
| Auth | Cliente inicializado, sin pantalla |

### Lo que falta en Teoría

- **El markdown va crudo.** Se ven los `**asteriscos**` del original. Falta
  portar `src/lib/markdown-teoria.ts`: separar líneas (el extractor deja una
  línea del PDF por línea de texto), destacar como título el párrafo que es
  todo negrita, y sustituir los marcadores `![figura]`.
- **Las figuras no se muestran**, porque todavía no están en Storage.

## Plataformas

Solo `android/`, `ios/` y `web/`. Se quitaron `linux/`, `macos/` y `windows/`:
no son destinos y sus plugins exigen symlinks que este Windows no tiene
habilitados (Developer Mode).

Para iOS hace falta macOS — Xcode no existe en Windows. O hay un Mac, o se
compila el IPA en un runner `macos-latest`, más los 99 USD/año de Apple.
