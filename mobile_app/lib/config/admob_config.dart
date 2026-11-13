import 'package:flutter/foundation.dart';

class AdMobConfig {
  static const _androidInterstitialFallback =
    'ca-app-pub-6063446543539696/2378948027';
  static const _iosInterstitialFallback =
      'ca-app-pub-6063446543539696/7936881094';
  static const _androidRewardedFallback =
    'ca-app-pub-6063446543539696/8014246644';
  static const _iosRewardedFallback =
      'ca-app-pub-6063446543539696/7936881094';
  static const _androidRewardedInterstitialFallback =
    'ca-app-pub-6063446543539696/2378948027';
  static const _iosRewardedInterstitialFallback =
      'ca-app-pub-6063446543539696/7936881094';

  static const _androidInterstitial = String.fromEnvironment(
    'ADMOB_ANDROID_INTERSTITIAL_ID',
    defaultValue: _androidInterstitialFallback,
  );
  static const _iosInterstitial = String.fromEnvironment(
    'ADMOB_IOS_INTERSTITIAL_ID',
    defaultValue: _iosInterstitialFallback,
  );
  static const _androidRewarded = String.fromEnvironment(
    'ADMOB_ANDROID_REWARDED_ID',
    defaultValue: _androidRewardedFallback,
  );
  static const _iosRewarded = String.fromEnvironment(
    'ADMOB_IOS_REWARDED_ID',
    defaultValue: _iosRewardedFallback,
  );
  static const _androidRewardedInterstitial = String.fromEnvironment(
    'ADMOB_ANDROID_REWARDED_INTERSTITIAL_ID',
    defaultValue: _androidRewardedInterstitialFallback,
  );
  static const _iosRewardedInterstitial = String.fromEnvironment(
    'ADMOB_IOS_REWARDED_INTERSTITIAL_ID',
    defaultValue: _iosRewardedInterstitialFallback,
  );

  static bool get isSupportedPlatform {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  static String get interstitialAdUnitId {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _androidInterstitial;
      case TargetPlatform.iOS:
        return _iosInterstitial;
      default:
        return '';
    }
  }

  static String get rewardedAdUnitId {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _androidRewarded;
      case TargetPlatform.iOS:
        return _iosRewarded;
      default:
        return '';
    }
  }

  static String get rewardedInterstitialAdUnitId {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _androidRewardedInterstitial;
      case TargetPlatform.iOS:
        return _iosRewardedInterstitial;
      default:
        return '';
    }
  }
}