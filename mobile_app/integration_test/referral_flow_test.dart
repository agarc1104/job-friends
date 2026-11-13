import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jobfriends_mobile/config/app_config.dart';
import 'package:jobfriends_mobile/data/jobfriends_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const repository = JobFriendsRepository();
  var supabaseInitialized = false;

  setUpAll(() async {
    await AppConfig.initialize(envFile: '.env.dev');
    if (!supabaseInitialized) {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
      );
      supabaseInitialized = true;
    }
  });

  testWidgets('referral full flow grants ad-free to referred and referrer', (tester) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final referrerEmail = 'referrer.$stamp@jobfriends.local';
    final referredEmail = 'referred.$stamp@jobfriends.local';
    const password = 'Referral!Pass123';

    try {
      await repository.register(
        email: referrerEmail,
        password: password,
        firstName: 'Referrer',
        lastName: 'Test',
        phone: '11111111',
      );

      final referralCode = await repository.getOrCreateReferralCode();
      expect(referralCode.isNotEmpty, isTrue);

      await repository.logout();

      await repository.register(
        email: referredEmail,
        password: password,
        firstName: 'Referred',
        lastName: 'Test',
        phone: '22222222',
      );

      await repository.applyReferralCode(referralCode);

      final pendingStatus = await repository.fetchReferralStatus();
      expect(pendingStatus.hasAppliedReferral, isTrue);

      await repository.searchJobs(
        keywords: 'qa tester remote',
        userEmail: referredEmail,
      );

      final referredStatus = await repository.fetchReferralStatus();
      expect(referredStatus.adFreeActive, isTrue);
      expect(referredStatus.adFreeDaysRemaining > 0, isTrue);

      await repository.logout();
      await repository.login(email: referrerEmail, password: password);

      final referrerStatus = await repository.fetchReferralStatus();
      expect(referrerStatus.adFreeActive, isTrue);
      expect(referrerStatus.adFreeDaysRemaining > 0, isTrue);
    } finally {
      try {
        await repository.logout();
      } catch (_) {}
    }
  });
}
