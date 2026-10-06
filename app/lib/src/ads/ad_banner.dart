import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../privacy/consent.dart';

/// AdMob ids. The defaults are Google's test ids, which always serve test
/// ads; real ones come from the AdMob console and are passed at build time:
/// `flutter build appbundle --dart-define=ADMOB_BANNER_ANDROID=ca-app-pub-…`.
/// The app id is in AndroidManifest.xml / Info.plist.
abstract final class AdsConfig {
  static const bannerAndroid = String.fromEnvironment(
    'ADMOB_BANNER_ANDROID',
    defaultValue: 'ca-app-pub-3940256099942544/9214589741',
  );
  static const bannerIos = String.fromEnvironment(
    'ADMOB_BANNER_IOS',
    defaultValue: 'ca-app-pub-3940256099942544/2435281174',
  );

  static String get bannerUnitId => Platform.isIOS ? bannerIos : bannerAndroid;
}

/// A banner ad across the bottom of a page, shown once consent allows ads
/// and an ad has loaded; takes no space otherwise. Only for pages that are
/// read rather than played on: AdMob doesn't allow banners next to
/// controls people tap a lot, like the boards.
class AdBanner extends ConsumerStatefulWidget {
  const AdBanner({super.key});

  @override
  ConsumerState<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends ConsumerState<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  int? _width;

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  Future<void> _load(int width) async {
    if (_width == width) return;
    _width = width;
    _ad?.dispose();
    _ad = null;
    _loaded = false;
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (!mounted || size == null) return;
    final ad = BannerAd(
      adUnitId: AdsConfig.bannerUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Banner failed: ${error.message}');
          ad.dispose();
          if (mounted && identical(ad, _ad)) setState(() => _ad = null);
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  Widget build(BuildContext context) {
    final canShowAds = ref.watch(privacyProvider.select((p) => p.canShowAds));
    if (!canShowAds || kIsWeb) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        _load(constraints.maxWidth.truncate());
        final ad = _ad;
        if (ad == null || !_loaded) return const SizedBox.shrink();
        // A gap and a rule keep the ad apart from the page's own content.
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: DecoratedBox(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).dividerColor))),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SizedBox(
                width: ad.size.width.toDouble(),
                height: ad.size.height.toDouble(),
                child: AdWidget(ad: ad),
              ),
            ),
          ),
        );
      },
    );
  }
}
