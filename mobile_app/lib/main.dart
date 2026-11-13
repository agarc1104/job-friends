import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/app_config.dart';
import 'services/job_search_reminder_service.dart';

const _trackingChannel = MethodChannel(
  'com.jobfriends.mobile/app_tracking_transparency',
);

Future<void> _requestAppTrackingAuthorization() async {
  if (defaultTargetPlatform != TargetPlatform.iOS) {
    return;
  }

  try {
    await _trackingChannel.invokeMethod<int>('requestAuthorization');
  } on PlatformException catch (error) {
    debugPrint('[ATT] Authorization request failed: ${error.message}');
  } on MissingPluginException {
    debugPrint('[ATT] Authorization channel is unavailable');
  }
}

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
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
      );
    } catch (error) {
      debugPrint('[ERROR] Supabase initialization failed: $error');
      rethrow;
    }
  } else {
    final errorMsg = 'FATAL: Supabase no configurado. Verifica que .env.${appEnv.toLowerCase()} tenga SUPABASE_URL y SUPABASE_ANON_KEY.';
    debugPrint('[FATAL] $errorMsg');
    throw Exception(errorMsg);
  }

  if (AppConfig.supportsMobileAds) {
    await _requestAppTrackingAuthorization();
    await MobileAds.instance.initialize();
  }

  await JobSearchReminderService.instance.initialize();

  runApp(const JobFriendsApp());
}