import 'package:flutter_test/flutter_test.dart';
import 'package:jobfriends_mobile/services/referral_deep_link_service.dart';

void main() {
  group('ReferralDeepLinkService', () {
    test('extracts referral code from valid invite uri', () {
      final uri = Uri.parse('jobfriends://invite?code=AB12CD34');
      expect(ReferralDeepLinkService.extractReferralCode(uri), 'AB12CD34');
    });

    test('normalizes lowercase and separators', () {
      final uri = Uri.parse('jobfriends://invite?code=ab-12_cd');
      expect(ReferralDeepLinkService.extractReferralCode(uri), 'AB12CD');
    });

    test('returns null for unsupported host', () {
      final uri = Uri.parse('jobfriends://auth/recover?code=AB12CD34');
      expect(ReferralDeepLinkService.extractReferralCode(uri), isNull);
    });

    test('extracts referral code from https invite link', () {
      final uri = Uri.parse('https://jobfriends.app/invite?code=xy12-z9');
      expect(ReferralDeepLinkService.extractReferralCode(uri), 'XY12Z9');
    });

    test('builds invite deep link from code', () {
      expect(
        ReferralDeepLinkService.buildInviteDeepLink('ab12-cd34'),
        'jobfriends://invite?code=AB12CD34',
      );
    });
  });
}
