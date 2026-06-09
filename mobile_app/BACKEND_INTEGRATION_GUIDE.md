# Backend Integration Guide: Supabase Edge Functions

## Arquitectura General

La aplicación Job-Friends **NO expone credenciales** en el cliente Flutter. En su lugar, utiliza una arquitectura segura basada en Supabase Edge Functions:

```
┌─────────────────────┐
│   Flutter Mobile    │
│   (Job-Friends)     │
└──────────┬──────────┘
           │ (llamadas públicas - sin credenciales)
           ▼
┌─────────────────────────────────────────────────────────┐
│       Supabase Edge Functions (Deno)                     │
│  - search-jobs (→ SerpAPI)                              │
│  - cv-assist (→ Gemini)                                 │
│  - cv-generate-store (→ Gemini + PDF/DOCX generation)  │
│  - interview-reply (→ Gemini)                           │
└──────┬──────────────────┬──────────────────┬────────────┘
       │                  │                  │
       ▼                  ▼                  ▼
    SerpAPI            Gemini API      Supabase Storage
    (búsqueda)       (IA assistant)    (CV files)
```

## Configuración en el Cliente (Flutter)

### 1. Archivo `.env` (NO contiene credenciales de terceros)

Los archivos `.env.dev`, `.env.qa`, `.env.prod` contienen **solo**:

```env
# Supabase pública (segura de exponer)
SUPABASE_URL=https://lyrrspormffutxsvmnfz.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...

# Clave para compatibilidad con APIs antiguas
SUPABASE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...

# Entorno
ENVIRONMENT=development|qa|production

# URL del API local (solo para desarrollo)
MOBILE_API_BASE_URL=http://192.168.2.8:8000
```

**Importante**: SUPABASE_ANON_KEY es **pública** y está diseñada para ser expuesta (Row Level Security en Supabase la protege).

### 2. Compilar la App

```bash
# Desarrollo (usa .env.dev)
flutter run --dart-define=APP_ENV=development

# QA (usa .env.qa)
flutter run --dart-define=APP_ENV=qa

# Production (usa .env.prod)
flutter run --dart-define=APP_ENV=production
```

## Configuración en Supabase (Credenciales Secretas)

Las credenciales de **SerpAPI** y **Gemini** están configuradas en **Supabase Secrets** (no en el cliente):

### Dashboard: Settings → Edge Functions → Secrets

```
GEMINI_API_KEY = tu_clave_de_gemini
GEMINI_MODEL = gemini-2.5-flash
GEMINI_FALLBACK_MODELS = gemini-2.5-flash-lite,gemini-2.0-flash

SERPAPI_API_KEY = tu_clave_de_serpapi
```

**Los Secrets son seguros**: No se exponen al cliente. Solo las Edge Functions pueden leerlas.

## Flujos de Cada Feature

### 🔍 Búsqueda de Empleos (search-jobs)

```
Flutter App
    ↓
searchJobs() en jobfriends_repository.dart
    ↓
_invokeFunction('search-jobs', {...})
    ↓
_client.functions.invoke() — llamada segura a Supabase Edge Function
    ↓
Supabase Edge Function: functions/search-jobs/index.ts
    ├─ Lee SERPAPI_API_KEY de los Secrets
    ├─ Llama SerpAPI con credenciales reales
    └─ Devuelve resultados al cliente
    ↓
Flutter → muestra empleos
```

### 📝 Generar CV (cv-generate-store)

```
Flutter App
    ↓
generateAndStoreCv() con datos del usuario
    ↓
_invokeFunction('cv-generate-store', {...})
    ↓
Supabase Edge Function: functions/cv-generate-store/index.ts
    ├─ Lee GEMINI_API_KEY de los Secrets
    ├─ Llama Gemini para generar LaTeX/HTML
    ├─ Convierte a PDF/DOCX
    ├─ Guarda en Supabase Storage
    └─ Devuelve URL pública y metadata
    ↓
Flutter → descarga o visualiza CV
```

### 🤖 Práctica de Entrevista (interview-reply)

```
Flutter App (con historial de chat)
    ↓
requestInterviewReply({jobTitle, description, userMessage, history})
    ↓
_invokeFunction('interview-reply', {...})
    ↓
Supabase Edge Function: functions/interview-reply/index.ts
    ├─ Lee GEMINI_API_KEY de los Secrets
    ├─ Procesa contexto y pregunta
    ├─ Genera respuesta con Gemini
    └─ Devuelve respuesta
    ↓
Flutter → muestra respuesta en chat
```

### 💡 Asistencia de CV (cv-assist)

```
Flutter App (con formulario de CV)
    ↓
requestCvAssist({fullName, targetRoles, experience, skills, summary})
    ↓
_invokeFunction('cv-assist', {...})
    ↓
Supabase Edge Function: functions/cv-assist/index.ts
    ├─ Lee GEMINI_API_KEY de los Secrets
    ├─ Genera recomendaciones personalizadas
    └─ Devuelve sugerencias
    ↓
Flutter → muestra sugerencias de mejora
```

## Verificar Conectividad

### 1. Desde Flutter (Debug)

Mira los logs en la consola:

```
I/flutter [JobFriendsRepository] invokeFunction start name=search-jobs body={...}
I/flutter [JobFriendsRepository] invokeFunction success name=search-jobs keys=[jobs, nextPageToken]
```

### 2. Desde Supabase Dashboard

Dashboard → Logs → Edge Functions → Ver logs de cada función

Los logs mostrarán si los Secrets se leen correctamente, errores de API, etc.

## Troubleshooting

### ❌ Error: "SUPABASE_URL y SUPABASE_ANON_KEY no configuradas"

```
SOLUCIÓN:
1. Verifica que el archivo .env.{dev|qa|prod} existe
2. Compila con: flutter run --dart-define=APP_ENV=development
3. No uses: flutter run (sin APP_ENV)
```

### ❌ Error: "timeout en search-jobs"

```
POSIBLES CAUSAS:
1. SERPAPI_API_KEY no configurada en Supabase Secrets
2. SerpAPI quota agotada
3. Conexión lenta

VERIFICA:
- Dashboard → Settings → Edge Functions → Secrets → SERPAPI_API_KEY existe
- Tu cuenta en SerpAPI tiene creditos
```

### ❌ Error: "Error en cv-generate-store: GEMINI_API_KEY no configurada"

```
SOLUCIÓN:
- Dashboard → Settings → Edge Functions → Secrets
- Agrega: GEMINI_API_KEY = tu_clave_de_google
```

### ❌ Error: "Faltan credenciales en Edge Functions"

```
SOLUCIÓN:
1. Ir a Supabase Dashboard
2. Settings → Edge Functions → Secrets
3. Agregar todos los Secrets necesarios:
   - GEMINI_API_KEY
   - GEMINI_MODEL
   - GEMINI_FALLBACK_MODELS
   - SERPAPI_API_KEY
```

## Security Best Practices

✅ **Lo que está bien (seguro):**
- Exponer SUPABASE_URL en .env (es pública)
- Exponer SUPABASE_ANON_KEY en .env (Supabase la protege con RLS)
- Guardar credenciales de terceros EN Supabase Secrets

❌ **Nunca hacer:**
- Guardar SERPAPI_API_KEY en .env
- Guardar GEMINI_API_KEY en .env
- Compilar con credenciales en --dart-define
- Commitear archivos .env con credenciales reales a git

## Deployment a Producción

1. **Actualizar .env.prod** con URLs de producción
2. **Configurar Secrets en Supabase Production**:
   ```bash
   supabase secrets set GEMINI_API_KEY=... --project-id=...
   supabase secrets set SERPAPI_API_KEY=... --project-id=...
   ```
3. **Deploy Edge Functions**:
   ```bash
   supabase functions deploy
   ```
4. **Compilar App**:
   ```bash
   flutter run --dart-define=APP_ENV=production
   ```

## Referencias

- [Supabase Edge Functions](https://supabase.com/docs/guides/functions)
- [Supabase Secrets](https://supabase.com/docs/guides/functions/secrets)
- [SerpAPI Documentation](https://serpapi.com/docs)
- [Gemini API Documentation](https://ai.google.dev/docs)
