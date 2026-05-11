<#
.SYNOPSIS
    Valida que todos los requisitos previos al build de release esten configurados.
    Ejecutar antes de build_android_release.ps1.

.EXAMPLE
    .\scripts\pre-release-check.ps1
    .\scripts\pre-release-check.ps1 -EnvFile ".env.prod"
#>
param(
    [string]$EnvFile = ".env.prod"
)

$ErrorActionPreference = 'Continue'
$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$androidDir  = Join-Path $projectRoot 'android'

$passed = 0
$failed = 0
$warnings = 0

function Pass($msg)    { Write-Host "  [OK]  $msg" -ForegroundColor Green;   $script:passed++ }
function Fail($msg)    { Write-Host "  [ERR] $msg" -ForegroundColor Red;     $script:failed++ }
function Warn($msg)    { Write-Host "  [WARN] $msg" -ForegroundColor Yellow; $script:warnings++ }
function Section($msg) { Write-Host "`n--- $msg ---" -ForegroundColor Cyan }

function Get-MatchValue($matchResult, $groupIndex) {
    if ($matchResult -and $matchResult.Matches.Count -gt 0 -and $matchResult.Matches[0].Groups.Count -gt $groupIndex) {
        return $matchResult.Matches[0].Groups[$groupIndex].Value
    }
    return $null
}

# --- 1. Package identity ---
Section "1. Package identity"
$gradleFile = Join-Path $androidDir 'app\build.gradle.kts'
if (Test-Path $gradleFile) {
    $pkgLine = Select-String -Path $gradleFile -Pattern 'applicationId\s*=\s*"([^"]+)"' | Select-Object -First 1
    if ($pkgLine -and $pkgLine.Line -match '"([^"]+)"') {
        $pkg = $Matches[1]
        if ($pkg -eq 'com.jobfriends.mobile') { Pass "applicationId = $pkg" }
        else { Warn "applicationId = $pkg  (esperado: com.jobfriends.mobile)" }
    } else { Warn "No se pudo leer applicationId de build.gradle.kts" }
} else { Fail "No se encontro $gradleFile" }

# --- 2. Version ---
Section "2. versionCode / versionName"
$localProps = Join-Path $androidDir 'local.properties'
if (Test-Path $localProps) {
    $vcMatch = Select-String -Path $localProps -Pattern '^flutter\.versionCode=(\d+)' | Select-Object -First 1
    $vnMatch = Select-String -Path $localProps -Pattern '^flutter\.versionName=(.+)' | Select-Object -First 1
    $vc = Get-MatchValue $vcMatch 1
    $vn = Get-MatchValue $vnMatch 1
    if ($vc) {
        if ([int]$vc -ge 2) { Pass "versionCode = $vc" }
        else { Warn "versionCode = $vc  (debe ser >= 2 para Play Store si ya se publico la 1)" }
    } else { Fail "flutter.versionCode no encontrado en local.properties" }
    if ($vn) { Pass "versionName = $vn" }
    else { Fail "flutter.versionName no encontrado en local.properties" }
} else { Fail "No se encontro $localProps" }

# --- 3. Keystore ---
Section "3. Keystore y key.properties"
$keyPropsPath = Join-Path $androidDir 'key.properties'
if (Test-Path $keyPropsPath) {
    Pass "key.properties existe"
    $kp = Get-Content $keyPropsPath
    $sfLine = ($kp | Where-Object { $_ -match '^storeFile=' }) -replace '^storeFile=',''
    if ($sfLine) {
        if ([System.IO.Path]::IsPathRooted($sfLine)) {
            $jksPath = $sfLine
        } else {
            $jksPath = [System.IO.Path]::GetFullPath((Join-Path $androidDir $sfLine))
        }
        if (Test-Path $jksPath) { Pass "Keystore JKS encontrado: $jksPath" }
        else { Fail "Keystore JKS NO encontrado: $jksPath" }
    } else { Fail "storeFile no definido en key.properties" }

    if ($kp -match 'FILL_IN') { Fail "key.properties aun tiene valores FILL_IN sin completar" }
    else { Pass "key.properties sin valores placeholder" }
} else {
    Fail "key.properties NO existe -- crealo a partir de android/key.properties.example"
}

# --- 4. Flutter SDK ---
Section "4. Flutter SDK en local.properties"
if (Test-Path $localProps) {
    $sdkMatch = Select-String -Path $localProps -Pattern '^flutter\.sdk=(.+)' | Select-Object -First 1
    $sdkLine = Get-MatchValue $sdkMatch 1
    if ($sdkLine) {
        $sdkPath = $sdkLine.Trim()
        if (Test-Path $sdkPath) {
            $flutter = Join-Path $sdkPath 'bin\flutter.bat'
            if (Test-Path $flutter) { Pass "Flutter SDK: $sdkPath" }
            else { Fail "flutter.bat no encontrado en $flutter" }
        } else { Fail "flutter.sdk ruta no existe: $sdkPath" }
    } else { Fail "flutter.sdk no definido en local.properties" }
}

# --- 5. Archivo de entorno ---
Section "5. Archivo de entorno: $EnvFile"
$envFilePath = Join-Path $projectRoot $EnvFile
if (Test-Path $envFilePath) {
    Pass "$EnvFile existe"
    $envContent = Get-Content $envFilePath -Raw

    if ($envContent -match 'SUPABASE_URL=https://[a-z0-9]+\.supabase\.co') { Pass "SUPABASE_URL configurado" }
    else { Fail "SUPABASE_URL falta o no tiene formato valido en $EnvFile" }

    if ($envContent -match 'SUPABASE_ANON_KEY=ey') { Pass "SUPABASE_ANON_KEY configurado (JWT)" }
    else { Fail "SUPABASE_ANON_KEY falta o no parece un JWT en $EnvFile" }

    if ($envContent -match 'MOBILE_API_BASE_URL=') {
        $apiMatch = Select-String -InputObject $envContent -Pattern 'MOBILE_API_BASE_URL=([^\r\n]+)'
        $apiUrl = Get-MatchValue $apiMatch 1
        if ($apiUrl -match 'FILL_IN') { Warn "MOBILE_API_BASE_URL tiene valor placeholder: $apiUrl" }
        else { Pass "MOBILE_API_BASE_URL configurado (opcional): $apiUrl" }
    } else {
        Pass "MOBILE_API_BASE_URL no definido -- OK, la app usa fallbacks de Supabase en produccion"
    }

    if ($envContent -match 'ENVIRONMENT=production') { Pass "ENVIRONMENT=production" }
    else { Warn "ENVIRONMENT no es 'production' en $EnvFile" }

    if ($envContent -match 'FILL_IN') { Fail "$EnvFile aun contiene valores FILL_IN sin completar" }

} else {
    Fail "$EnvFile NO existe en $projectRoot"
}

# --- 7. AdMob App ID ---
Section "7. AdMob App ID"
$manifestPath = Join-Path $androidDir 'app\src\main\AndroidManifest.xml'
if (Test-Path $manifestPath) {
    $admobValueLine = Select-String -Path $manifestPath -Pattern 'ca-app-pub-' | Select-Object -First 1
    if ($admobValueLine) {
        $appIdMatch = Select-String -InputObject $admobValueLine.Line -Pattern 'ca-app-pub-[\d~]+'
        $appId = Get-MatchValue $appIdMatch 0
        if ($appId -match 'ca-app-pub-3940256099') { Warn "AdMob App ID parece ser TEST: $appId" }
        else { Pass "AdMob App ID configurado: $appId" }
    } else { Warn "No se encontro ca-app-pub- en AndroidManifest.xml" }
} else { Fail "AndroidManifest.xml no encontrado: $manifestPath" }

# --- Resumen ---
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  RESUMEN PRE-RELEASE CHECK" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Pasados  : $passed" -ForegroundColor Green
Write-Host "  Warnings : $warnings" -ForegroundColor Yellow
Write-Host "  Errores  : $failed" -ForegroundColor Red
Write-Host "========================================"

if ($failed -gt 0) {
    Write-Host ""
    Write-Host "  CORRIJA LOS ERRORES ANTES DE EJECUTAR build_android_release.ps1" -ForegroundColor Red
    exit 1
} elseif ($warnings -gt 0) {
    Write-Host ""
    Write-Host "  Hay warnings -- revisa antes de publicar en produccion" -ForegroundColor Yellow
    exit 0
} else {
    Write-Host ""
    Write-Host "  LISTO PARA BUILD RELEASE" -ForegroundColor Green
    exit 0
}
