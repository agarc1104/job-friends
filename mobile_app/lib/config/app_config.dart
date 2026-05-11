import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static late String supabaseUrl;
  static late String _supabaseAnonKey;
  static late String _supabaseKey;
  static late String mobileApiBaseUrl;
  static late String environment;

  static const String _envSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _envSupabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String _envSupabaseKey = String.fromEnvironment('SUPABASE_KEY');
  static const String _envMobileApiBaseUrl = String.fromEnvironment('MOBILE_API_BASE_URL');
  static const String _envEnvironment = String.fromEnvironment('ENVIRONMENT');

  static Future<void> initialize({String envFile = '.env'}) async {
    await dotenv.load(fileName: envFile);

    supabaseUrl = _envSupabaseUrl.isNotEmpty
      ? _envSupabaseUrl
      : (dotenv.env['SUPABASE_URL'] ?? '');
    _supabaseAnonKey = _envSupabaseAnonKey.isNotEmpty
      ? _envSupabaseAnonKey
      : (dotenv.env['SUPABASE_ANON_KEY'] ?? '');
    _supabaseKey = _envSupabaseKey.isNotEmpty
      ? _envSupabaseKey
      : (dotenv.env['SUPABASE_KEY'] ?? '');
    final rawMobileApiBaseUrl = _envMobileApiBaseUrl.isNotEmpty
      ? _envMobileApiBaseUrl
      : (dotenv.env['MOBILE_API_BASE_URL'] ?? '');
    mobileApiBaseUrl = _normalizeMobileApiBaseUrl(rawMobileApiBaseUrl);
    environment = _envEnvironment.isNotEmpty
      ? _envEnvironment
      : (dotenv.env['ENVIRONMENT'] ?? 'development');
  }

  static String get supabaseAnonKey =>
      _supabaseAnonKey.isNotEmpty ? _supabaseAnonKey : _supabaseKey;

  static bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get hasMobileApiBaseUrl {
    if (mobileApiBaseUrl.isEmpty) {
      return false;
    }

    final uri = Uri.tryParse(mobileApiBaseUrl);
    if (uri == null) {
      return false;
    }

    final hasValidScheme = uri.scheme == 'http' || uri.scheme == 'https';
    return hasValidScheme && uri.host.isNotEmpty;
  }

  static String _normalizeMobileApiBaseUrl(String rawValue) {
    var value = rawValue.trim();

    if (value.isEmpty) {
      return '';
    }

    // Common typos: http_//host -> http://host, https_//host -> https://host
    value = value
        .replaceFirst(RegExp(r'^http_//', caseSensitive: false), 'http://')
        .replaceFirst(RegExp(r'^https_//', caseSensitive: false), 'https://');

    // Common typo: http//host -> http://host
    value = value
        .replaceFirst(RegExp(r'^http//', caseSensitive: false), 'http://')
        .replaceFirst(RegExp(r'^https//', caseSensitive: false), 'https://');

    // Common typo: http:192.168.1.10:8000 -> http://192.168.1.10:8000
    value = value.replaceFirstMapped(
      RegExp(r'^(https?):(\d+\.\d+\.\d+\.\d+(?::\d+)?)(/.*)?$', caseSensitive: false),
      (match) => '${match.group(1)}://${match.group(2)}${match.group(3) ?? ''}',
    );

    // Common typo: http:77192.168.2.8:8000 -> http://192.168.2.8:8000
    value = value.replaceFirstMapped(
      RegExp(r'^(https?):\d+(\d+\.\d+\.\d+\.\d+(?::\d+)?)(/.*)?$', caseSensitive: false),
      (match) => '${match.group(1)}://${match.group(2)}${match.group(3) ?? ''}',
    );

    // Common typo: http://10.0.2.2..8000 -> http://10.0.2.2:8000
    value = value.replaceFirstMapped(
      RegExp(r'^(https?://\d+\.\d+\.\d+\.\d+)\.\.(\d+)(/.*)?$'),
      (match) => '${match.group(1)}:${match.group(2)}${match.group(3) ?? ''}',
    );

    if (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }

    final uri = Uri.tryParse(value);
    if (uri == null) {
      return '';
    }
    final hasValidScheme = uri.scheme == 'http' || uri.scheme == 'https';
    if (!hasValidScheme || uri.host.isEmpty) {
      return '';
    }

    return value;
  }

  static bool get isDevelopment => environment == 'development';
  static bool get isQA => environment == 'qa';
  static bool get isProduction => environment == 'production';

  static bool get supportsMobileAds {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
}