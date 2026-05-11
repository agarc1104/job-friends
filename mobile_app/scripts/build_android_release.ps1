param(
    [string]$SupabaseUrl,
    [string]$SupabaseAnonKey,
    [string]$MobileApiBaseUrl,
    [string]$AppEnv = "production",
    [string]$AdmobAndroidBannerId,
    [string]$AdmobAndroidInterstitialId,
    [switch]$SkipPubGet
)

$ErrorActionPreference = 'Stop'
# Avoid treating native stderr warnings as terminating errors in PowerShell 7+
if ($null -ne $PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$androidDir = Join-Path $projectRoot 'android'
$localPropertiesPath = Join-Path $androidDir 'local.properties'
$keyPropertiesPath = Join-Path $androidDir 'key.properties'

if (-not (Test-Path $localPropertiesPath)) {
    throw "No se encontró android/local.properties. Abre el proyecto Flutter una vez en Android Studio o corre flutter doctor."
}

if (-not (Test-Path $keyPropertiesPath)) {
    throw "No se encontró android/key.properties. Crea ese archivo a partir de android/key.properties.example antes de compilar para Play Store."
}

$flutterSdkLine = Select-String -Path $localPropertiesPath -Pattern '^flutter.sdk=' | Select-Object -First 1
if (-not $flutterSdkLine) {
    throw "No se encontró flutter.sdk en android/local.properties."
}

$flutterSdk = ($flutterSdkLine.Line -replace '^flutter.sdk=', '').Trim()
$flutterExe = Join-Path $flutterSdk 'bin\flutter.bat'

if (-not (Test-Path $flutterExe)) {
    throw "No se encontró Flutter en $flutterExe"
}

$dartDefines = @()

if ($AppEnv) {
    $dartDefines += "--dart-define=APP_ENV=$AppEnv"
}
if ($SupabaseUrl) {
    $dartDefines += "--dart-define=SUPABASE_URL=$SupabaseUrl"
}
if ($SupabaseAnonKey) {
    $dartDefines += "--dart-define=SUPABASE_ANON_KEY=$SupabaseAnonKey"
}
if ($MobileApiBaseUrl) {
    $dartDefines += "--dart-define=MOBILE_API_BASE_URL=$MobileApiBaseUrl"
}
if ($AdmobAndroidBannerId) {
    $dartDefines += "--dart-define=ADMOB_ANDROID_BANNER_ID=$AdmobAndroidBannerId"
}
if ($AdmobAndroidInterstitialId) {
    $dartDefines += "--dart-define=ADMOB_ANDROID_INTERSTITIAL_ID=$AdmobAndroidInterstitialId"
}

Push-Location $projectRoot
try {
    Write-Host "[Build] Project root: $projectRoot"
    Write-Host "[Build] Flutter executable: $flutterExe"

    if (-not $SkipPubGet) {
        Write-Host "[Build] Running: flutter pub get"
        & $flutterExe pub get
        if ($LASTEXITCODE -ne 0) {
            throw "flutter pub get falló con código $LASTEXITCODE"
        }
    }

    Write-Host "[Build] Running: flutter build apk --release"
    & $flutterExe build apk --release @dartDefines
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build apk --release falló con código $LASTEXITCODE"
    }

    Write-Host "[Build] Running: flutter build appbundle --release"
    & $flutterExe build appbundle --release @dartDefines
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build appbundle --release falló con código $LASTEXITCODE"
    }

    Write-Host ''
    Write-Host 'Build release completado.'
    Write-Host 'APK: build\app\outputs\flutter-apk\app-release.apk'
    Write-Host 'AAB: build\app\outputs\bundle\release\app-release.aab'
}
finally {
    Pop-Location
}