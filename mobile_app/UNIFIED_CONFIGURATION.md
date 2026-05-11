# Arquitectura de Configuración Unificada - JobFriends Mobile

Este documento explica cómo la aplicación funciona de forma unificada en **desarrollo**, **QA** y **producción** sin cambios de código.

---

## 🎯 Principio: Configuración en Tiempo de Compilación

La app **NO** cambia código entre entornos. En su lugar:

1. **Desarrollo/QA**: Pasas credenciales y URLs via `--dart-define`
2. **Producción**: APK/AAB compilado ya tiene URLs y credenciales baked-in
3. El archivo [lib/config/environment.dart](lib/config/environment.dart) lee estas variables en tiempo de compilación

---

## 📊 Flujo por Entorno

### 1️⃣ **Desarrollo Local** (Tu PC + Emulador)

```powershell
flutter run \
  --dart-define=APP_ENV=development \
  --dart-define=MOBILE_API_BASE_URL=http://10.0.2.2:8000
```

**Resultado:**
- App apunta a backend en `http://10.0.2.2:8000`
- Usa credenciales Supabase/SerpApi/Gemini por defecto
- Pantalla muestra: "Entorno: development | API: http://10.0.2.2:8000"

---

### 2️⃣ **Desarrollo con Dispositivo Físico**

```powershell
flutter run \
  --dart-define=APP_ENV=development \
  --dart-define=MOBILE_API_BASE_URL=http://192.168.2.8:8000
```

**Resultado:**
- App apunta a backend en tu PC (IP local)
- Pantalla muestra: "Entorno: development | API: http://192.168.2.8:8000"

---

### 3️⃣ **QA en Emulador**

```powershell
flutter run \
  --dart-define=APP_ENV=qa
  # MOBILE_API_BASE_URL por defecto a http://10.0.2.2:8000
```

**Resultado:**
- Carga `.env.qa` internamente
- Usa credenciales QA
- Pantalla muestra: "Entorno: qa | API: http://10.0.2.2:8000"

Alternativamente, usando script:
```powershell
./scripts/qa_android.ps1 -SupabaseAnonKey "..." -SerpapiApiKey "..."
```

---

### 4️⃣ **Compilar para Play Store (Producción)**

```powershell
# 1. Compilar APK/AAB con configuración de producción
./scripts/build_android_release.ps1 `
  -AppEnv "production" \
  -SupabaseUrl "https://jobfriends.supabase.co" \
  -SupabaseAnonKey "<clave-real>" \
  -MobileApiBaseUrl "https://api.jobfriends.com" \
  -SerpapiApiKey "<clave-real>" \
  -GeminiApiKey "<clave-real>"

# 2. El APK/AAB resultante ya tiene TODAS las URLs baked-in
# Los usuarios descargan y funciona automáticamente
```

**Resultado:**
- APK/AAB contiene URLs de producción compiladas
- Descargado desde Play Store: `flutter run` = ✅ Funciona sin parámetros
- Pantalla muestra: "Entorno: production | API: https://api.jobfriends.com"

---

## 🔄 Diagrama de Flujo

```
┌─────────────────────────────────────────────────────────┐
│  flutter run / APK descargado                           │
└──────────────┬──────────────────────────────────────────┘
               │
        ¿APP_ENV definido?
               │
      ┌────────┼────────┐
      │        │        │
   (dev)    (qa)    (production)
      │        │        │
      ├────────┼────────┤
      │        │        │
   .env      .env.qa   Baked-in en
   local     + envs    APK/AAB
      │        │        │
      └────────┼────────┘
               │
     EnvironmentConfig carga
     todas las variables
               │
      JobsScreen muestra
     "Entorno: X | API: Y"
               │
      ¡Funciona automáticamente!
```

---

## 📝 Cómo Funciona en Usuario Final (Producción)

### Escenario: Usuario descarga app de Play Store

1. **Download**: Usuario descarga `jobfriends_mobile.apk` desde Play Store
2. **Instalación**: Sistema Android instala app
3. **Primera ejecución**: Usuario abre app
4. ✅ **App funciona automáticamente**:
   - Ya conoce URL de Supabase real
   - Ya conoce URL de backend de producción
   - Ya conoce APIs de SerpApi y Gemini
   - **Sin necesidad de parámetros, configuración, o IP local**

---

## 🔧 Configuración de URLs Reales (Pre-Play Store)

Antes de compilar para Play Store, **ACTUALIZA ESTOS ARCHIVOS** con tus URLs reales:

### `.env.prod` - Producción
```env
SUPABASE_URL=https://jobfriends.supabase.co        # Tu proyecto Supabase real
SUPABASE_ANON_KEY=<tu-clave-anon-real>
MOBILE_API_BASE_URL=https://api.jobfriends.com     # Tu backend en producción
SERPAPI_API_KEY=<tu-clave-real>
GEMINI_API_KEY=<tu-clave-real>
```

O pasarlas directamente en el build:
```powershell
./scripts/build_android_release.ps1 `
  -AppEnv "production" \
  -SupabaseUrl "https://jobfriends.supabase.co" \
  -MobileApiBaseUrl "https://api.jobfriends.com" \
  -SerpapiApiKey "<clave>" \
  -GeminiApiKey "<clave>"
```

---

## 📋 Comparativa: Dev vs QA vs Producción

| Aspecto | Desarrollo | QA | Producción |
|---------|-----------|-----|------------|
| **Backend URL** | `http://10.0.2.2:8000` (emulador) | `http://10.0.2.2:8000` | `https://api.jobfriends.com` |
| **Supabase** | Dev | Dev | Real |
| **SerpApi** | Test key | Test key | API key real |
| **Gemini** | Test key | Test key | API key real |
| **¿Parámetros?** | `--dart-define=...` | `--dart-define=...` o script | ❌ NO - Baked-in |
| **Usuarios finales** | ❌ No | ❌ No | ✅ Sí (Play Store) |
| **Comando** | `flutter run -d ...` | `flutter run -d ...` o script | ✅ App descargada |

---

## ✅ Casos de Uso

### "Quiero probar búsqueda en mi teléfono ahora"
```powershell
flutter run -d <phone-id> \
  --dart-define=MOBILE_API_BASE_URL=http://192.168.2.8:8000
```
→ App funciona sin más cambios

### "Quiero compilar QA para testing interno"
```powershell
./scripts/build_android_release.ps1 \
  -AppEnv qa \
  -MobileApiBaseUrl http://10.0.2.2:8000
```
→ APK listo para distribuir a testers (URLs compiladas)

### "Quiero compilar para Play Store"
```powershell
./scripts/build_android_release.ps1 \
  -AppEnv production \
  -SupabaseUrl https://jobfriends.supabase.co \
  -MobileApiBaseUrl https://api.jobfriends.com \
  -SerpapiApiKey <clave> \
  -GeminiApiKey <clave>
```
→ APK/AAB listo para Play Store (usuarios descargan y ¡funciona!)

---

## 🚀 Ventajas de Esta Arquitectura

✅ **Sin hardcoding en código** - URLs en variables de entorno  
✅ **Mismo código para todos los entornos** - No hay `if (isDev)` por todo  
✅ **Fácil de debuggear** - La pantalla siempre muestra entorno/API activos  
✅ **Escalable** - Agregar nuevos entornos es trivial  
✅ **Seguro en producción** - Credenciales compiladas, no en git  
✅ **CI/CD compatible** - Scripts listos para automatizar builds  

---

## 📝 Notas Importantes

1. **`.env` files no se compilan en APK** - Son solo para `flutter run` con dotenv
   - En builds release, necesitas `--dart-define`

2. **Credenciales sensibles** - En CI/CD:
   - Usa variables de entorno secretas
   - Pass via `--dart-define` en scripts de build

3. **URLs en producción** - Deben ser HTTPS
   - Android requiere TLS 1.2+
   - Certificados válidos

4. **Rotación de credenciales** - En producción:
   - Nuevo build = nuevas credenciales compiladas
   - No hay "actualizar claves a distancia"
   - Plan de rotación es importante

