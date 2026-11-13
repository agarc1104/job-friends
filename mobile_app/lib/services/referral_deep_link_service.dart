import 'dart:async';

import 'package:app_links/app_links.dart';

class ReferralDeepLinkService {
  ReferralDeepLinkService._();

  static final ReferralDeepLinkService instance = ReferralDeepLinkService._();

  final AppLinks _appLinks = AppLinks();

  Stream<Uri> get uriStream => _appLinks.uriLinkStream;

  Future<Uri?> getInitialUri() => _appLinks.getInitialLink();

  static String? extractReferralCode(Uri? uri) {
    if (uri == null) {
      return null;
    }

    final scheme = uri.scheme.trim().toLowerCase();
    final host = uri.host.trim().toLowerCase();
    final normalizedPath = uri.path.trim().toLowerCase();

    final matchesCustomScheme = scheme == 'jobfriends' && host == 'invite';
    final matchesHttpsInvite =
        (scheme == 'https' || scheme == 'http') &&
        host.isNotEmpty &&
        (normalizedPath == '/invite' || normalizedPath.endsWith('/invite'));

    if (!matchesCustomScheme && !matchesHttpsInvite) {
      return null;
    }

    final rawCode = (uri.queryParameters['code'] ?? '').trim().toUpperCase();
    final normalized = rawCode.replaceAll(RegExp(r'[^A-Z0-9]'), '');

    if (!RegExp(r'^[A-Z0-9]{6,12}$').hasMatch(normalized)) {
      return null;
    }

    return normalized;
  }

  static String buildInviteDeepLink(String referralCode) {
    final sanitized = referralCode.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return 'jobfriends://invite?code=$sanitized';
  }
}
