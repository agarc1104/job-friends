# Codemagic iOS Setup (GitHub + TestFlight)

Esta guia deja el proyecto listo para compilar iOS en Codemagic y publicar en TestFlight.

## 1) Pre requisitos

- Cuenta de Apple Developer activa.
- App creada en App Store Connect con el bundle id `com.jobfriends.mobile`.
- Repositorio en GitHub conectado a Codemagic.
- Integracion de App Store Connect creada en Codemagic.

## 2) Archivo de CI listo

El repositorio ya incluye `codemagic.yaml` en la raiz con dos workflows:

- `ios-pr-check`: corre `flutter analyze` y `flutter test` en PR.
- `ios-testflight`: firma iOS y sube IPA a TestFlight en push a `main`.

## 3) Variables en Codemagic

Crea un Environment Group en Codemagic llamado `jobfriends_mobile_secrets` y define:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `MOBILE_API_BASE_URL`
- `ADMOB_IOS_BANNER_ID` (opcional)
- `ADMOB_IOS_INTERSTITIAL_ID` (opcional)

Notas:

- Si no defines IDs de AdMob iOS, el workflow usa IDs de prueba.
- No guardes estas variables en el repo.

## 4) Configuracion de firma iOS en Codemagic

En la app de Codemagic:

1. Ve a Team settings > Integrations y conecta App Store Connect.
2. En el workflow `ios-testflight`, verifica que use `auth: integration`.
3. Deja activado `distribution_type: app_store`.

## 5) Antes del primer push a main

- Verifica que el bundle id sea `com.jobfriends.mobile` en iOS.
- Revisa que no haya secretos reales en `.env*` ni en markdowns.
- Ejecuta localmente:

```powershell
cd mobile_app
flutter pub get
flutter analyze
flutter test
```

## 6) Flujo esperado

1. Push o merge a `main`.
2. Codemagic ejecuta `ios-testflight`.
3. Se genera IPA firmada.
4. Se publica automaticamente en TestFlight.

## 7) Seguridad recomendada

- Usa solo secretos en variables de Codemagic.
- Rota claves comprometidas antes de distribuir builds.
- Si en algun momento usaste claves reales en commits previos, reescribe historial antes de abrir el repo al publico.
