# Checklist de Publicacion en Play Console

## 1) Cuenta y acceso

- [ ] Cuenta de desarrollador de Google Play activa.
- [ ] App creada en Play Console con package `com.jobfriends.mobile`.
- [ ] Acceso de propietario/administrador confirmado.

## 2) Ficha principal de tienda

- [ ] Nombre de app definido (max 30).
- [ ] Descripcion corta (max 80).
- [ ] Descripcion completa (max 4000).  ← Ver `docs/play-store/ficha_play_store_es-419.md`
- [ ] Categoria y etiquetas seleccionadas.
- [ ] Correo de soporte cargado.
- [ ] Sitio web (opcional pero recomendado).

## 3) Recursos graficos obligatorios

- [ ] Icono app: 512 x 512 PNG (32 bits, fondo transparente permitido).
- [ ] Feature graphic: 1024 x 500 PNG/JPG.
- [ ] Minimo 2 capturas de pantalla de telefono.

Recomendado adicional:

- [ ] Capturas para 7" y 10" (si aplica).
- [ ] Video promocional de YouTube.

## 4) Politicas y formularios

- [ ] Politica de privacidad publica y accesible por URL.
- [ ] Seccion "Seguridad de los datos" completada.
- [ ] Declaracion de anuncios completada (usa AdMob).
- [ ] Clasificacion de contenido completada.
- [ ] Publico objetivo y contenido definidos.
- [ ] Declaracion de permisos sensibles revisada (AD_ID presente).

## 5) Calidad tecnica

- [x] Release build firmado generado: `build/app/outputs/bundle/release/app-release.aab` ← Script: `scripts/build_android_release.ps1`
- [x] Keystore en `C:\Users\HP\Documents\upload-keystore.jks` (alias: upload).
- [x] `flutter analyze`: sin errores.
- [x] Smoke tests: `flutter test test\smoke_shell_test.dart` — PASS (2 tests).
- [x] Preprod gate: `scripts/preprod_gate.ps1` — PASS.
- [ ] Probar en pista interna antes de produccion.
- [ ] Probar login, busqueda de vacantes, aplicaciones, CV Prep e Interview Prep.
- [ ] Probar anuncios en release.
- [ ] Revisar cierres/crashes en Android Vitals tras lanzamiento.
- [x] `/readiness` endpoint valida credenciales de produccion en tiempo real.
- [x] `/metrics` endpoint disponible para monitoreo en vivo.

## 6) Versionado y rollout

- [ ] `versionCode` incrementado para cada nueva subida.  ← Editar `android/app/build.gradle.kts`
- [ ] Notas de version en es-419 preparadas.
- [ ] Lanzamiento inicial en Internal testing.
- [ ] Luego pasar a Closed/Open testing y finalmente Produccion.

## 7) Verificacion final antes de enviar a revision

- [ ] No hay texto de placeholder en ficha (emails/URLs ficticias).
- [ ] Las capturas muestran UI real de la version actual.
- [ ] Politica de privacidad coincide con el manejo real de datos.
- [ ] Todas las secciones en Play Console aparecen como "Completadas".

## 8) Procedimiento de rollback (si aplica)

- Ver `docs/runbook_rollback.md` para instrucciones completas.
- Rollback rapido: Play Console → Production → Edit release → Rollout 0 %.
