class ReferralStatus {
  const ReferralStatus({
    required this.referralCode,
    required this.adFreeActive,
    required this.adFreeUntil,
    required this.adFreeDaysRemaining,
    required this.referralsPending,
    required this.referralsQualified,
    required this.referralsRewarded,
    required this.hasAppliedReferral,
    required this.myReferralStatus,
  });

  final String referralCode;
  final bool adFreeActive;
  final DateTime? adFreeUntil;
  final int adFreeDaysRemaining;
  final int referralsPending;
  final int referralsQualified;
  final int referralsRewarded;
  final bool hasAppliedReferral;
  final String myReferralStatus;

  factory ReferralStatus.fromMap(Map<String, dynamic> data) {
    final statsRaw = data['referrals_sent'];
    final stats = statsRaw is Map
        ? statsRaw.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};

    final myReferralRaw = data['my_referral'];
    final myReferral = myReferralRaw is Map
        ? myReferralRaw.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};

    final adFreeUntilRaw = (data['ad_free_until'] ?? '').toString().trim();

    return ReferralStatus(
      referralCode: (data['referral_code'] ?? '').toString(),
      adFreeActive: data['ad_free_active'] == true,
      adFreeUntil: adFreeUntilRaw.isEmpty ? null : DateTime.tryParse(adFreeUntilRaw),
      adFreeDaysRemaining: _asInt(data['ad_free_days_remaining']),
      referralsPending: _asInt(stats['pending']),
      referralsQualified: _asInt(stats['qualified']),
      referralsRewarded: _asInt(stats['rewarded']),
      hasAppliedReferral: myReferral.isNotEmpty,
      myReferralStatus: (myReferral['status'] ?? '').toString(),
    );
  }

  static int _asInt(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.round();
    }
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }
}
