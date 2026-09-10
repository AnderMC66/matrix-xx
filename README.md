# Matrix U — app móvil

Porte a Flutter de la plataforma de preparación para el examen de admisión de
la UNSA. La documentación está en **[LEEME.md](LEEME.md)**.

```bash
node tool/sincronizar-datos.mjs                      # traer el catálogo
flutter run --dart-define-from-file=config/dev.json  # correr
flutter test                                         # 98 tests (más 6 de integración, saltados sin credenciales)
node tool/cobertura.mjs                              # cuánto del sílabo tiene preguntas
```
