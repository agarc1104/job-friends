# Guia de QA y Produccion - JobFriends Mobile

Esta guia describe como ejecutar pruebas y builds sin exponer credenciales en el repositorio.

## Variables requeridas

Define estas variables en tu shell, CI o en Codemagic:

- SUPABASE_URL
- SUPABASE_ANON_KEY
- MOBILE_API_BASE_URL
- SERPAPI_API_KEY (si aplica a tu flujo)
- GEMINI_API_KEY (si aplica a tu flujo)
- ADMOB_ANDROID_BANNER_ID (opcional)
- ADMOB_ANDROID_INTERSTITIAL_ID (opcional)
- ADMOB_IOS_BANNER_ID (opcional)
- ADMOB_IOS_INTERSTITIAL_ID (opcional)

## QA local en Android

```powershell
cd mobile_app
flutter run -d emulator-5554 `
  --dart-define=APP_ENV=qa `
  --dart-define=SUPABASE_URL=$env:SUPABASE_URL `
  --dart-define=SUPABASE_ANON_KEY=$env:SUPABASE_ANON_KEY `
  --dart-define=MOBILE_API_BASE_URL=$env:MOBILE_API_BASE_URL
```

## Smoke tests

```powershell
cd mobile_app
flutter analyze
flutter test
flutter test integration_test/app_smoke_test.dart -d emulator-5554 `
  --dart-define=APP_ENV=qa `
  --dart-define=SUPABASE_URL=$env:SUPABASE_URL `
  --dart-define=SUPABASE_ANON_KEY=$env:SUPABASE_ANON_KEY `
  --dart-define=MOBILE_API_BASE_URL=$env:MOBILE_API_BASE_URL
```

## Build Android release

```powershell
cd mobile_app
./scripts/build_android_release.ps1 `
  -AppEnv "production" `
  -SupabaseUrl $env:SUPABASE_URL `
  -SupabaseAnonKey $env:SUPABASE_ANON_KEY `
  -MobileApiBaseUrl $env:MOBILE_API_BASE_URL `
  -SerpapiApiKey $env:SERPAPI_API_KEY `
  -GeminiApiKey $env:GEMINI_API_KEY
```

## Build iOS en Codemagic

- El archivo codemagic.yaml en la raiz incluye workflow ios-testflight.
- Configura el grupo jobfriends_mobile_secrets en Codemagic con las variables requeridas.
- Conecta App Store Connect Integration para firma y publicacion.

## Checklist de seguridad antes de publicar

- No subir claves reales en .env ni markdown.
- Usar variables secretas en Codemagic/GitHub Actions.
- Rotar claves si ya estuvieron expuestas en commits previos.
- Verificar que los valores de produccion apunten a dominios HTTPS reales.
