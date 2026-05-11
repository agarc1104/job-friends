# Configuración de Supabase - JobFriends Mobile

La aplicación está configurada para usar Supabase con soporte para múltiples ambientes.

## 📋 Ambientes Configurados

- **Desarrollo (.env.dev)**: Para desarrollo local
- **QA (.env.qa)**: Para testing y QA
- **Producción (.env.prod)**: Para producción

## 🔑 Credenciales

Los 3 ambientes comparten las mismas credenciales de Supabase:

```
Project ID: <tu-project-id>
URL: https://<tu-proyecto>.supabase.co
ANON KEY: <tu-anon-key>
```

## 🚀 Cómo Cambiar de Ambiente

### Opción 1: Cambiar el archivo .env en main.dart

Edita `lib/main.dart` en la línea donde dice:
```dart
await AppConfig.initialize(envFile: '.env.dev');
```

Cambiar a:
- `.env.dev` para desarrollo
- `.env.qa` para QA
- `.env.prod` para producción

### Opción 2: Usar un Script para Cambiar Ambientes (Windows)

Crea `scripts/select-environment.ps1`:
```powershell
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
$mainDartPath = "lib/main.dart"

Write-Host "Cambiando a ambiente: $Environment ($envFile)"

# Reemplazar la línea en main.dart
(Get-Content $mainDartPath) -replace "await AppConfig\.initialize\(envFile: '[^']+'\);", "await AppConfig.initialize(envFile: '$envFile');" | Set-Content $mainDartPath

Write-Host "✓ Configuración actualizada a: $Environment"
```

Uso:
```powershell
# Cambiar a desarrollo
.\scripts\select-environment.ps1 -Environment dev

# Cambiar a QA
.\scripts\select-environment.ps1 -Environment qa

# Cambiar a producción
.\scripts\select-environment.ps1 -Environment prod
```

## 🔍 Verificar Configuración Actual

Para verificar qué ambiente está activo, puedes revisar en tu código:

```dart
if (AppConfig.isDevelopment) {
  print('Modo: Desarrollo');
}
if (AppConfig.isQA) {
  print('Modo: QA');
}
if (AppConfig.isProduction) {
  print('Modo: Producción');
}
```

## 📦 Dependencias Agregadas

- `flutter_dotenv: ^5.1.0` - Para cargar variables de entorno desde archivos `.env`

## 📝 Archivos Modificados

1. **pubspec.yaml** - Agregada dependencia `flutter_dotenv` y assets para archivos `.env`
2. **lib/config/app_config.dart** - Refactorizado para usar `flutter_dotenv`
3. **lib/main.dart** - Agregada llamada a `AppConfig.initialize()`
4. **Nuevos archivos .env**:
   - `.env` (desarrollo por defecto)
   - `.env.dev` (desarrollo)
   - `.env.qa` (QA)
   - `.env.prod` (producción)

## ✅ Pasos Siguientes

1. Ejecutar `flutter pub get` para descargar las nuevas dependencias
2. Seleccionar el ambiente deseado modificando `lib/main.dart`
3. Ejecutar la aplicación: `flutter run`

## 🚨 Notas de Seguridad

⚠️ **IMPORTANTE**: Los archivos `.env` contienen credenciales. 

- Asegúrate de que `.env*` NO esté en `.gitignore` durante desarrollo local (para que todos los desarrolladores tengan la configuración)
- Si en el futuro movemos a producción, considera usar un **secreto manager** externo (AWS Secrets Manager, Google Secret Manager, etc.)
- NUNCA commits credenciales reales en producción al repositorio

## 🔗 Recursos

- [Supabase Flutter Plugin](https://supabase.com/docs/reference/flutter/introduction)
- [flutter_dotenv Package](https://pub.dev/packages/flutter_dotenv)
