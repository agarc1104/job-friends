param(
    [string]$FlutterPath = "C:\Users\HP\flutter\3.41.4\bin\flutter.bat",
    [string]$DeviceId = "emulator-5554",
    [string]$SupabaseUrl = "https://lyrrspormffutxsvmnfz.supabase.co",
    [string]$SupabaseAnonKey = "",
    [string]$ApiBaseUrl = "http://10.0.2.2:8000",
    [switch]$SkipManualRun,
    [switch]$AllowSmokeFallback
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $FlutterPath)) {
    throw "No se encontro flutter.bat en: $FlutterPath"
}

if ([string]::IsNullOrWhiteSpace($SupabaseAnonKey)) {
    throw "Debes pasar -SupabaseAnonKey para ejecutar QA end-to-end."
}

Write-Host "[QA] Verificando dispositivos..."
& $FlutterPath devices

Write-Host "[QA] Ejecutando flutter analyze..."
& $FlutterPath analyze

Write-Host "[QA] Ejecutando flutter test..."
& $FlutterPath test

Write-Host "[QA] Ejecutando integration_test en emulador..."
$maxAttempts = 2
$attempt = 1
$integrationPassed = $false
while ($attempt -le $maxAttempts -and -not $integrationPassed) {
    Write-Host "[QA] integration_test intento $attempt de $maxAttempts"
    & $FlutterPath test integration_test\app_smoke_test.dart -d $DeviceId --dart-define=APP_ENV=qa --dart-define=SUPABASE_URL=$SupabaseUrl --dart-define=SUPABASE_ANON_KEY=$SupabaseAnonKey --dart-define=MOBILE_API_BASE_URL=$ApiBaseUrl
    if ($LASTEXITCODE -eq 0) {
        $integrationPassed = $true
    }
    else {
        if ($attempt -lt $maxAttempts) {
            Write-Host "[QA] fallo intermitente detectado, reintentando integration_test..."
        }
    }
    $attempt += 1
}

if (-not $integrationPassed) {
    if ($AllowSmokeFallback) {
        Write-Host "[QA] integration_test bloqueado. Ejecutando fallback smoke (flutter test test\\smoke_shell_test.dart)..."
        & $FlutterPath test test\smoke_shell_test.dart
        if ($LASTEXITCODE -ne 0) {
            throw "integration_test fallo tras $maxAttempts intentos y fallback smoke tambien fallo"
        }
        Write-Host "[QA] fallback smoke aprobado. Continuando pipeline con advertencia de runner Android."
    }
    else {
        throw "integration_test fallo tras $maxAttempts intentos"
    }
}

if (-not $SkipManualRun) {
    Write-Host "[QA] Ejecutando app en emulador para validacion manual de anuncios..."
    & $FlutterPath run -d $DeviceId --dart-define=APP_ENV=qa --dart-define=SUPABASE_URL=$SupabaseUrl --dart-define=SUPABASE_ANON_KEY=$SupabaseAnonKey --dart-define=MOBILE_API_BASE_URL=$ApiBaseUrl
}
else {
    Write-Host "[QA] Validacion manual omitida por parametro -SkipManualRun."
}
