# JobFriends Mobile

Base inicial del cliente movil Flutter para Android e iOS con soporte de AdMob.

## Estado actual

- Proyecto hidratado con runners `android/` e `ios/`.
- Flujos conectados:
	- Login/registro sobre tabla `Aplicants`.
	- Interes de empresas sobre tabla `company_interest_leads`.
	- Vacantes desde endpoint backend real `POST /jobs/search`.
	- Aplicaciones sobre tabla `Applications`.
	- CV Prep IA desde `POST /cv/assist`.
	- Generacion + guardado de CV final DOCX/PDF desde `POST /cv/generate-store`.
	- Interview Prep IA desde `POST /interview/reply`.

## Migracion Supabase requerida (empresas interesadas)

Ejecuta en Supabase SQL Editor el script:

- `supabase/migrations/20260429_create_company_interest_leads.sql`

Eso crea la tabla `company_interest_leads`, validaciones SQL y politica RLS para permitir inserts desde la app Flutter con `SUPABASE_ANON_KEY`.
- AdMob Android configurado con app id real en `android/app/src/main/AndroidManifest.xml`.

## Variables esperadas

Pasa estas variables con `--dart-define` o inyectalas desde tu CI:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `MOBILE_API_BASE_URL` (Android emulador: `http://10.0.2.2:8000`)
- `ADMOB_ANDROID_BANNER_ID`
- `ADMOB_IOS_BANNER_ID`
- `ADMOB_ANDROID_INTERSTITIAL_ID`
- `ADMOB_IOS_INTERSTITIAL_ID`

## Backend API requerido

Desde la raiz del repo:

```powershell
c:/Users/HP/Documents/my-app/venv/Scripts/python.exe -m uvicorn mobile_api:app --host 0.0.0.0 --port 8000
```

Si tu `.env` no tiene credenciales de Supabase, exportalas antes de iniciar API para usar `POST /cv/generate-store`.

## Corrida Android (emulador)

```powershell
flutter run -d emulator-5554 \
	--dart-define=SUPABASE_URL=https://<tu-proyecto>.supabase.co \
	--dart-define=SUPABASE_ANON_KEY=<tu-anon-key> \
	--dart-define=MOBILE_API_BASE_URL=http://10.0.2.2:8000
```

## Build Android para Play Store

Play Store publica con AAB, no con APK. Aun así conviene generar ambos:

- `app-release.apk`: para instalar manualmente y validar anuncios/flujo release.
- `app-release.aab`: para subir a Play Console.

### 1) Crear tu keystore de subida

Ejecuta desde `mobile_app/`:

```powershell
keytool -genkeypair -v \
	-keystore upload-keystore.jks \
	-keyalg RSA \
	-keysize 2048 \
	-validity 10000 \
	-alias upload
```

Guarda ese archivo fuera de cualquier carpeta temporal y respáldalo. Si pierdes esa keystore, complicas futuras actualizaciones en Play Console.

### 2) Crear `android/key.properties`

Usa `android/key.properties.example` como base:

```properties
storeFile=../../upload-keystore.jks
storePassword=TU_PASSWORD
keyAlias=upload
keyPassword=TU_PASSWORD
```

`android/.gitignore` ya excluye `key.properties` y los archivos `.jks`.

### 3) Generar APK y AAB release

Si `flutter` no está en tu PATH, usa el script incluido:

```powershell
./scripts/build_android_release.ps1 \
	-SupabaseUrl "https://<tu-proyecto>.supabase.co" \
	-SupabaseAnonKey "<tu-anon-key>" \
	-MobileApiBaseUrl "https://<tu-api-produccion>" \
	-AdmobAndroidBannerId "ca-app-pub-xxxx/yyyy" \
	-AdmobAndroidInterstitialId "ca-app-pub-xxxx/zzzz"
```

Salidas esperadas:

- `build/app/outputs/flutter-apk/app-release.apk`
- `build/app/outputs/bundle/release/app-release.aab`

### 4) Antes de subir a Play Console

- El package Android actual queda en `com.jobfriends.mobile`; si quieres otro, cámbialo antes de subir la primera versión a Play Console.
- Sube el `.aab` a una pista `internal testing` primero.
- Prueba anuncios con el build instalado desde Play o desde APK release firmado.
- Mantén IDs de prueba o dispositivos de prueba mientras la app no esté aprobada del todo en AdMob.

### 5) Pruebas de anuncios a futuro

- El App ID de AdMob Android ya está declarado en `AndroidManifest.xml`.
- Los ad unit IDs pueden seguir entrando por `--dart-define`, así puedes usar IDs de prueba en QA y reales en producción.
- Para ver anuncios más parecidos al entorno real, prueba preferiblemente una build release y, si vas a monetizar en serio, una pista interna de Play Store.

## QA Script (manual + automatizado)

### 1) Smoke suite automatizada en emulador

```powershell
flutter test integration_test/app_smoke_test.dart -d emulator-5554 \
	--dart-define=SUPABASE_URL=https://<tu-proyecto>.supabase.co \
	--dart-define=SUPABASE_ANON_KEY=<tu-anon-key> \
	--dart-define=MOBILE_API_BASE_URL=http://10.0.2.2:8000
```

### 2) Script QA completo

Ejecuta desde `mobile_app/`:

```powershell
./scripts/qa_android.ps1 -SupabaseAnonKey "<tu-anon-key>"
```

Opciones utiles:

- `-SkipManualRun`: omite el `flutter run` final cuando necesitas un pipeline 100% no interactivo.
- `-AllowSmokeFallback`: si `integration_test` en Android falla por un problema del runner (ej. WebSocket), ejecuta `flutter test test/smoke_shell_test.dart` como fallback controlado.

Este script ejecuta:

1. `flutter analyze`
2. `flutter test`
3. `integration_test/app_smoke_test.dart` en el emulador
4. `flutter run` para validacion manual final (incluyendo anuncios)

### 3) Gate de preproduccion (QA + health API + build opcional)

Ejecuta desde `mobile_app/`:

```powershell
./scripts/preprod_gate.ps1 \
	-SupabaseUrl "https://<tu-proyecto>.supabase.co" \
	-SupabaseAnonKey "<tu-anon-key>" \
	-ApiBaseUrl "http://10.0.2.2:8000" \
	-AllowSmokeFallback \
	-SkipManualRun \
	-RunReleaseBuild
```

Este script valida:

1. `GET /health` del backend (si no usas `-SkipApiHealthCheck`)
2. QA Android completo (`qa_android.ps1`)
3. Build release opcional (`build_android_release.ps1` con `-RunReleaseBuild`)

## Notas iOS

- El runner iOS ya existe, con App ID de AdMob de prueba en `ios/Runner/Info.plist`.
- Compilar o correr iOS requiere macOS + Xcode y un simulador/dispositivo Apple.
- CI/CD iOS con Codemagic configurado en `../codemagic.yaml`.
- Guia operativa para GitHub + TestFlight en `docs/codemagic_ios_setup.md`.

## Siguiente paso recomendado

1. Definir y conectar un ad unit real de interstitial para Android/iOS (hoy solo banner Android esta con ID real).
2. Mover SerpAPI/Gemini a credenciales de produccion y activar logging de costo/cuota.
3. Añadir boton de descarga/apertura directa del archivo final desde URL publica dentro de CV Prep.