import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../config/admob_config.dart';

class AdaptiveBannerSlot extends StatefulWidget {
  const AdaptiveBannerSlot({super.key});

  @override
  State<AdaptiveBannerSlot> createState() => _AdaptiveBannerSlotState();
}

class _AdaptiveBannerSlotState extends State<AdaptiveBannerSlot> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadBanner();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  void _loadBanner() {
    if (!AdMobConfig.isSupportedPlatform || AdMobConfig.bannerAdUnitId.isEmpty) {
      return;
    }

    BannerAd? banner;
    banner = BannerAd(
      adUnitId: AdMobConfig.bannerAdUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (_) {
          debugPrint('AdMob banner loaded');
          if (!mounted) {
            return;
          }
          setState(() {
            _bannerAd = banner;
            _isLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('AdMob banner failed: ${error.message}');
          ad.dispose();
        },
      ),
    );

    banner.load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _bannerAd == null) {
      return Container(
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: const Color(0xFFE8F0ED),
        ),
        alignment: Alignment.center,
        child: const Text('Espacio reservado para banner AdMob'),
      );
    }

    return SizedBox(
      height: _bannerAd!.size.height.toDouble(),
      width: _bannerAd!.size.width.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}