param(
    [string]$FlutterPath = "C:\Users\HP\flutter\3.41.4\bin\flutter.bat",
    [string]$DeviceId = "emulator-5554",
    [string]$SupabaseUrl = "",
    [string]$SupabaseAnonKey = "",
    [string]$ApiBaseUrl = "http://10.0.2.2:8000",
    [switch]$RunReleaseBuild,
    [string]$AdmobAndroidBannerId = "",
    [string]$AdmobAndroidInterstitialId = "",
    [switch]$SkipManualRun,
    [switch]$AllowSmokeFallback,
    [switch]$SkipApiHealthCheck
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$qaScript = Join-Path $scriptDir "qa_android.ps1"
$buildScript = Join-Path $scriptDir "build_android_release.ps1"

function Test-ApiHealth {
    param(
        [string]$BaseUrl
    )

    $healthUrl = "$BaseUrl/health"
    Write-Host "[Preprod] Checking API health: $healthUrl"

    try {
        $response = Invoke-RestMethod -Uri $healthUrl -Method Get -TimeoutSec 8
    }
    catch {
        throw "API health check failed at $healthUrl. Ensure mobile_api.py is running and reachable. Error: $($_.Exception.Message)"
    }

    if (-not $response -or $response.status -ne "ok") {
        throw "API health check did not return expected payload { status: ok }."
    }

    Write-Host "[Preprod] API health ok."
}

if (-not (Test-Path $qaScript)) {
    throw "qa_android.ps1 not found at $qaScript"
}

if (-not (Test-Path $buildScript)) {
    throw "build_android_release.ps1 not found at $buildScript"
}

if (-not $SkipApiHealthCheck) {
    Test-ApiHealth -BaseUrl $ApiBaseUrl
}

Write-Host "[Preprod] Running QA pipeline..."

$qaParams = @{
    FlutterPath = $FlutterPath
    DeviceId = $DeviceId
    SupabaseUrl = $SupabaseUrl
    SupabaseAnonKey = $SupabaseAnonKey
    ApiBaseUrl = $ApiBaseUrl
}

if ($SkipManualRun) {
    $qaParams.SkipManualRun = $true
}

if ($AllowSmokeFallback) {
    $qaParams.AllowSmokeFallback = $true
}

& $qaScript @qaParams
if ($LASTEXITCODE -ne 0) {
    throw "QA pipeline failed with exit code $LASTEXITCODE"
}

if ($RunReleaseBuild) {
    Write-Host "[Preprod] Running Android release build..."

    if ([string]::IsNullOrWhiteSpace($SupabaseUrl) -or [string]::IsNullOrWhiteSpace($SupabaseAnonKey) -or [string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
        throw "RunReleaseBuild requires SupabaseUrl, SupabaseAnonKey and ApiBaseUrl."
    }

    $buildParams = @{
        SupabaseUrl = $SupabaseUrl
        SupabaseAnonKey = $SupabaseAnonKey
        MobileApiBaseUrl = $ApiBaseUrl
        AppEnv = "qa"
    }

    if (-not [string]::IsNullOrWhiteSpace($AdmobAndroidBannerId)) {
        $buildParams.AdmobAndroidBannerId = $AdmobAndroidBannerId
    }

    if (-not [string]::IsNullOrWhiteSpace($AdmobAndroidInterstitialId)) {
        $buildParams.AdmobAndroidInterstitialId = $AdmobAndroidInterstitialId
    }

    & $buildScript @buildParams
    if ($LASTEXITCODE -ne 0) {
        throw "Release build failed with exit code $LASTEXITCODE"
    }
}

Write-Host ""
Write-Host "[Preprod] Gate completed successfully."
Write-Host "- QA: passed"
if ($RunReleaseBuild) {
    Write-Host "- Release build: passed"
}
else {
    Write-Host "- Release build: skipped (use -RunReleaseBuild to enable)"
}
if ($SkipApiHealthCheck) {
    Write-Host "- API health: skipped"
}
else {
    Write-Host "- API health: passed"
}
