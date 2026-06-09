import 'package:flutter/foundation.dart';

class AdMobConfig {
  static const _androidBannerFallback =
    'ca-app-pub-2215764937379314/7320364697';
  static const _iosBannerFallback =
      'ca-app-pub-3940256099942544/2934735716';
  static const _androidInterstitialFallback =
    'ca-app-pub-2215764937379314/7918401545';
  static const _iosInterstitialFallback =
      'ca-app-pub-3940256099942544/4411468910';
  static const _androidRewardedInterstitialFallback =
    'ca-app-pub-6063446543539696/2378948027';
  static const _iosRewardedInterstitialFallback =
      'ca-app-pub-6063446543539696/7936881094';

  static const _androidBanner = String.fromEnvironment(
    'ADMOB_ANDROID_BANNER_ID',
    defaultValue: _androidBannerFallback,
  );
  static const _iosBanner = String.fromEnvironment(
    'ADMOB_IOS_BANNER_ID',
    defaultValue: _iosBannerFallback,
  );
  static const _androidInterstitial = String.fromEnvironment(
    'ADMOB_ANDROID_INTERSTITIAL_ID',
    defaultValue: _androidInterstitialFallback,
  );
  static const _iosInterstitial = String.fromEnvironment(
    'ADMOB_IOS_INTERSTITIAL_ID',
    defaultValue: _iosInterstitialFallback,
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

  static String get bannerAdUnitId {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _androidBanner;
      case TargetPlatform.iOS:
        return _iosBanner;
      default:
        return '';
    }
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