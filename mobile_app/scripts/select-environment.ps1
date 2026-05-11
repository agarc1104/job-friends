param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('dev', 'qa', 'prod')]
    [string]$Environment
)

$envFileMap = @{
    'dev'  = '.env.dev'
    'qa'   = '.env.qa'
    'prod' = '.env.prod'
}

$envFile = $envFileMap[$Environment]
$mainDartPath = "lib\main.dart"

Write-Host "🔄 Cambiando a ambiente: $Environment ($envFile)" -ForegroundColor Cyan

# Verificar que el archivo existe
if (-not (Test-Path $mainDartPath)) {
    Write-Host "❌ Error: No se encontró $mainDartPath" -ForegroundColor Red
    exit 1
}

# Leer el contenido del archivo
$content = Get-Content $mainDartPath -Raw

# Reemplazar la línea de configuración del ambiente
$updatedContent = $content -replace "await AppConfig\.initialize\(envFile: '[^']+'\);", "await AppConfig.initialize(envFile: '$envFile');"

# Si el contenido cambió, escribirlo de vuelta
if ($content -ne $updatedContent) {
    Set-Content $mainDartPath $updatedContent
    Write-Host "✅ Configuración actualizada a: $Environment" -ForegroundColor Green
    Write-Host "   Archivo: $mainDartPath" -ForegroundColor Green
    Write-Host "   Archivo .env: $envFile" -ForegroundColor Yellow
} else {
    Write-Host "ℹ️  Ya está configurado con: $envFile" -ForegroundColor Yellow
}
