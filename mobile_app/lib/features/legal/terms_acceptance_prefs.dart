import 'package:shared_preferences/shared_preferences.dart';

abstract final class TermsAcceptancePrefs {
  static const String currentTermsVersion = '2026-06-21-ai';
  static const String currentPrivacyVersion = '2026-06-21-ai';
  static const String _acceptedTermsVersionKey = 'legal.terms.accepted.version';
  static const String _acceptedPrivacyVersionKey = 'legal.privacy.accepted.version';
  static const String _acceptedAtKey = 'legal.accepted.at';

  static Future<bool> isAcceptedCurrentVersion() async {
    return isAcceptedCurrentPolicies();
  }

  static Future<bool> isAcceptedCurrentPolicies() async {
    final prefs = await SharedPreferences.getInstance();
    final acceptedTermsVersion = prefs.getString(_acceptedTermsVersionKey);
    final acceptedPrivacyVersion = prefs.getString(_acceptedPrivacyVersionKey);
    return acceptedTermsVersion == currentTermsVersion &&
        acceptedPrivacyVersion == currentPrivacyVersion;
  }

  static Future<void> markAcceptedCurrentVersion() async {
    await markAcceptedCurrentPolicies();
  }

  static Future<void> markAcceptedCurrentPolicies() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_acceptedTermsVersionKey, currentTermsVersion);
    await prefs.setString(_acceptedPrivacyVersionKey, currentPrivacyVersion);
    await prefs.setString(
      _acceptedAtKey,
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  static Future<DateTime?> acceptedAtUtc() async {
    final prefs = await SharedPreferences.getInstance();
    final rawAcceptedAt = prefs.getString(_acceptedAtKey);
    if (rawAcceptedAt == null || rawAcceptedAt.trim().isEmpty) {
      return null;
    }

    return DateTime.tryParse(rawAcceptedAt)?.toUtc();
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_acceptedTermsVersionKey);
    await prefs.remove(_acceptedPrivacyVersionKey);
    await prefs.remove(_acceptedAtKey);
  }
}
