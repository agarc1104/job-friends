import 'package:shared_preferences/shared_preferences.dart';

class SavedCredentials {
  const SavedCredentials({
    required this.email,
    required this.password,
  });

  final String email;
  final String password;
}

class SavedCredentialsStore {
  static const _emailKey = 'saved_credentials_email';
  static const _passwordKey = 'saved_credentials_password';

  const SavedCredentialsStore();

  Future<SavedCredentials?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_emailKey)?.trim() ?? '';
    final password = prefs.getString(_passwordKey) ?? '';
    if (email.isEmpty || password.isEmpty) {
      return null;
    }
    return SavedCredentials(email: email, password: password);
  }

  Future<void> save({required String email, required String password}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_emailKey, email.trim().toLowerCase());
    await prefs.setString(_passwordKey, password);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_emailKey);
    await prefs.remove(_passwordKey);
  }
}
