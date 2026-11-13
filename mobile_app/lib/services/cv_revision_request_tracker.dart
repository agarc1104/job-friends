import 'package:shared_preferences/shared_preferences.dart';

class CvRevisionRequestTracker {
  CvRevisionRequestTracker._();

  static final CvRevisionRequestTracker instance = CvRevisionRequestTracker._();

  static const int correctionRequestsPerAd = 3;
  static const String _prefPrefix = 'cv.correction_request_count.';

  Future<int> registerRequest(String userEmail) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyFor(userEmail);
    final currentCount = prefs.getInt(key) ?? 0;
    final updatedCount = currentCount + 1;
    await prefs.setInt(key, updatedCount);
    return updatedCount;
  }

  bool shouldShowAdForCount(int count) {
    return count > 0 && count % correctionRequestsPerAd == 0;
  }

  String _keyFor(String userEmail) {
    return '$_prefPrefix${userEmail.trim().toLowerCase()}';
  }
}