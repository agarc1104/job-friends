/// Configuración automática de entornos
/// Se selecciona basado en APP_ENV en tiempo de compilación
class EnvironmentConfig {
  // Estas se establecen en tiempo de compilación via --dart-define
  static const String appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  // MOBILE_API_BASE_URL solo se usa para addManualApplication y uploadCvFile (backend local).
  // Las llamadas a SerpAPI y Gemini van a través de Supabase Edge Functions.
  static const String mobileApiBaseUrl = String.fromEnvironment(
    'MOBILE_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000', // Emulador por defecto
  );

  // Propiedades derivadas
  static bool get isDevelopment => appEnv == 'development';
  static bool get isQA => appEnv == 'qa';
  static bool get isProduction => appEnv == 'production';

  static String get displayName {
    switch (appEnv) {
      case 'qa':
        return 'QA';
      case 'production':
        return 'Producción';
      default:
        return 'Desarrollo';
    }
  }
}
