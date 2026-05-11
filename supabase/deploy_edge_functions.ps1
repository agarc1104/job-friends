# deploy_edge_functions.ps1
# Instala Supabase CLI (via Scoop), configura secretos y despliega las Edge Functions.
# Ejecutar una sola vez desde la raiz del proyecto.

$ErrorActionPreference = "Stop"

$SUPABASE_PROJECT_REF = if ($env:SUPABASE_PROJECT_REF) { $env:SUPABASE_PROJECT_REF } else { "lyrrspormffutxsvmnfz" }

# ─── Claves que van en Supabase Secrets (NO en el APK) ──────────────────────
$SERPAPI_API_KEY     = $env:SERPAPI_API_KEY
$GEMINI_API_KEY      = $env:GEMINI_API_KEY
$GEMINI_MODEL        = if ($env:GEMINI_MODEL) { $env:GEMINI_MODEL } else { "gemini-2.5-flash" }
# ────────────────────────────────────────────────────────────────────────────

if ([string]::IsNullOrWhiteSpace($SERPAPI_API_KEY) -or [string]::IsNullOrWhiteSpace($GEMINI_API_KEY)) {
    Write-Error "Faltan variables de entorno: SERPAPI_API_KEY y/o GEMINI_API_KEY"
    exit 1
}

# 1. Instalar Scoop si no existe
if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Host "[1/5] Instalando Scoop..."
    # Bypass ya es mas permisivo que RemoteSigned; ignorar si falla
    try { Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force } catch { }
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
}
else {
    Write-Host "[1/5] Scoop ya instalado."
}

# 2. Instalar Supabase CLI via Scoop
if (-not (Get-Command supabase -ErrorAction SilentlyContinue)) {
    Write-Host "[2/5] Instalando Supabase CLI..."
    scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
    scoop install supabase
}
else {
    Write-Host "[2/5] Supabase CLI ya instalado: $(supabase --version)"
}

# 3. Login (abre el navegador para autenticacion)
Write-Host "[3/5] Autenticando en Supabase (se abrira el navegador)..."
supabase login

# 4. Configurar secretos en el proyecto
Write-Host "[4/5] Configurando Supabase Secrets..."
supabase secrets set `
    SERPAPI_API_KEY=$SERPAPI_API_KEY `
    GEMINI_API_KEY=$GEMINI_API_KEY `
    GEMINI_MODEL=$GEMINI_MODEL `
    --project-ref $SUPABASE_PROJECT_REF

Write-Host "  Secretos configurados:"
supabase secrets list --project-ref $SUPABASE_PROJECT_REF

# 5. Desplegar las 4 Edge Functions
Write-Host "[5/5] Desplegando Edge Functions..."
$functions = @("search-jobs", "cv-assist", "cv-generate-store", "interview-reply")

foreach ($fn in $functions) {
    Write-Host "  -> Desplegando $fn ..."
    supabase functions deploy $fn --project-ref $SUPABASE_PROJECT_REF
}

Write-Host ""
Write-Host "=============================================="
Write-Host " Despliegue completado exitosamente."
Write-Host " Las Edge Functions estan activas en:"
Write-Host " https://lyrrspormffutxsvmnfz.supabase.co/functions/v1/"
Write-Host ""
Write-Host " Funciones desplegadas:"
foreach ($fn in $functions) {
    Write-Host "   - $fn"
}
Write-Host "=============================================="
