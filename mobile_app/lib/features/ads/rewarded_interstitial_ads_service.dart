import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../config/admob_config.dart';
import '../../data/jobfriends_repository.dart';

class RewardedInterstitialAdsService {
  RewardedInterstitialAdsService._();

  static final RewardedInterstitialAdsService instance =
      RewardedInterstitialAdsService._();

  static const _loadTimeout = Duration(seconds: 8);
  static const _showTimeout = Duration(seconds: 20);

  final _repository = const JobFriendsRepository();

  RewardedInterstitialAd? _ad;
  bool _isLoading = false;
  bool _isShowing = false;
  Future<void>? _loadingFuture;

  Future<void> preload() async {
    await _ensureLoaded(userEmail: null, placement: 'preload');
  }

  Future<bool> maybeShow({
    required String placement,
    String? userEmail,
  }) async {
    if (!AdMobConfig.isSupportedPlatform) {
      return false;
    }

    final normalizedEmail = userEmail?.trim().toLowerCase() ?? '';
    if (normalizedEmail.isNotEmpty) {
      final adFreeActive = await _repository.isCurrentUserAdFree();
      if (adFreeActive) {
        return false;
      }
    }

    if (_isShowing) {
      return false;
    }

    await _ensureLoaded(userEmail: userEmail, placement: placement);
    final ad = _ad;
    if (ad == null) {
      return false;
    }

    final completer = Completer<bool>();
    _isShowing = true;
    _ad = null;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) {
        unawaited(
          _trackEvent(
            userEmail: userEmail,
            eventName: 'rewarded_interstitial_showed',
            placement: placement,
          ),
        );
      },
      onAdDismissedFullScreenContent: (dismissedAd) {
        dismissedAd.dispose();
        _isShowing = false;
        unawaited(_ensureLoaded(userEmail: userEmail, placement: placement));
        if (!completer.isCompleted) {
          completer.complete(true);
        }
      },
      onAdFailedToShowFullScreenContent: (failedAd, error) {
        failedAd.dispose();
        _isShowing = false;
        unawaited(
          _trackEvent(
            userEmail: userEmail,
            eventName: 'rewarded_interstitial_failed_show',
            placement: placement,
            metadata: {
              'code': error.code,
              'message': error.message,
            },
          ),
        );
        unawaited(_ensureLoaded(userEmail: userEmail, placement: placement));
        if (!completer.isCompleted) {
          completer.complete(false);
        }
      },
    );

    try {
      ad.show(
        onUserEarnedReward: (_, rewardItem) {
          unawaited(
            _trackEvent(
              userEmail: userEmail,
              eventName: 'rewarded_interstitial_rewarded',
              placement: placement,
              metadata: {
                'reward_amount': rewardItem.amount,
                'reward_type': rewardItem.type,
              },
            ),
          );
        },
      );
    } catch (error) {
      _isShowing = false;
      ad.dispose();
      unawaited(
        _trackEvent(
          userEmail: userEmail,
          eventName: 'rewarded_interstitial_failed_show',
          placement: placement,
          metadata: {
            'error': error.toString(),
          },
        ),
      );
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }

    try {
      return await completer.future.timeout(_showTimeout);
    } on TimeoutException {
      _isShowing = false;
      unawaited(
        _trackEvent(
          userEmail: userEmail,
          eventName: 'rewarded_interstitial_show_timeout',
          placement: placement,
        ),
      );
      return false;
    }
  }

  Future<void> _ensureLoaded({
    required String? userEmail,
    required String placement,
  }) async {
    if (_ad != null) {
      return;
    }

    if (_isLoading) {
      final loadingFuture = _loadingFuture;
      if (loadingFuture != null) {
        await loadingFuture;
      }
      return;
    }

    final adUnitId = AdMobConfig.rewardedInterstitialAdUnitId;
    if (adUnitId.isEmpty) {
      return;
    }

    _isLoading = true;
    final completer = Completer<void>();
    _loadingFuture = completer.future;

    RewardedInterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _isLoading = false;
          if (!completer.isCompleted) {
            completer.complete();
          }
          unawaited(
            _trackEvent(
              userEmail: userEmail,
              eventName: 'rewarded_interstitial_loaded',
              placement: placement,
            ),
          );
        },
        onAdFailedToLoad: (error) {
          _ad = null;
          _isLoading = false;
          if (!completer.isCompleted) {
            completer.complete();
          }
          unawaited(
            _trackEvent(
              userEmail: userEmail,
              eventName: 'rewarded_interstitial_failed_load',
              placement: placement,
              metadata: {
                'code': error.code,
                'message': error.message,
              },
            ),
          );
        },
      ),
    );

    try {
      await completer.future.timeout(_loadTimeout);
    } on TimeoutException {
      if (kDebugMode) {
        debugPrint('[RewardedInterstitialAdsService] Load timeout for placement=$placement');
      }
    }
  }

  Future<void> _trackEvent({
    required String? userEmail,
    required String eventName,
    required String placement,
    Map<String, dynamic> metadata = const {},
  }) async {
    final normalizedEmail = userEmail?.trim().toLowerCase();
    if (normalizedEmail == null || normalizedEmail.isEmpty) {
      return;
    }

    try {
      await _repository.registerMonetizationEvent(
        eventName: eventName,
        userEmail: normalizedEmail,
        metadata: {
          'placement': placement,
          'ad_unit_id': AdMobConfig.rewardedInterstitialAdUnitId,
          ...metadata,
        },
      );
    } catch (_) {
      // Monetization tracking should never block user actions.
    }
  }
}
