import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/app_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Permite seleccionar entorno con --dart-define=APP_ENV=development|qa|production
  const appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'development');
  final envFile = switch (appEnv.toLowerCase()) {
    'qa' => '.env.qa',
    'production' => '.env.prod',
    _ => '.env.dev',
  };

  await AppConfig.initialize(envFile: envFile);

  if (AppConfig.hasSupabaseConfig) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
  }

  if (AppConfig.supportsMobileAds) {
    await MobileAds.instance.initialize();
  }

  runApp(const JobFriendsApp());
}