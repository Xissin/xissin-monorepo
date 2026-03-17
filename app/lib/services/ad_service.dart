import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdService — Live AdMob implementation
//
// • Banner    : ca-app-pub-7516216593424837/7804365873
// • Interstitial: ca-app-pub-7516216593424837/9918305586
//
// Usage:
//   await AdService.instance.init();          ← call once in main()
//   AdService.instance.showInterstitial();    ← before navigating to a tool
//   Consumer<AdService>(builder: ...) + BannerAdWidget ← in HomeScreen
// ─────────────────────────────────────────────────────────────────────────────

class AdService extends ChangeNotifier {
  static final AdService instance = AdService._();
  AdService._();

  // ── Ad Unit IDs ─────────────────────────────────────────────────────────────
  static const String _bannerAdUnitId =
      'ca-app-pub-7516216593424837/7804365873';
  static const String _interstitialAdUnitId =
      'ca-app-pub-7516216593424837/9918305586';

  // ── Internal state ───────────────────────────────────────────────────────────
  BannerAd?       _bannerAd;
  InterstitialAd? _interstitialAd;

  bool _bannerReady       = false;
  bool _interstitialReady = false;
  bool _initialized       = false;

  // ── Public getters ───────────────────────────────────────────────────────────
  bool       get adsRemoved   => false;
  bool       get bannerReady  => _bannerReady;
  BannerAd?  get bannerAd     => _bannerAd;
  bool       get purchasing   => false;
  String?    get purchaseError => null;

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await MobileAds.instance.initialize();

    // Optional: request configuration (non-personalised ads for PH)
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(
        tagForChildDirectedTreatment: TagForChildDirectedTreatment.unspecified,
        tagForUnderAgeOfConsent:      TagForUnderAgeOfConsent.unspecified,
        maxAdContentRating:           MaxAdContentRating.t,
      ),
    );

    loadBanner();
    _loadInterstitial();
  }

  // ── Banner ───────────────────────────────────────────────────────────────────

  void loadBanner() {
    _bannerAd?.dispose();
    _bannerAd    = null;
    _bannerReady = false;

    _bannerAd = BannerAd(
      adUnitId: _bannerAdUnitId,
      size:     AdSize.banner,
      request:  const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          _bannerReady = true;
          notifyListeners();
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _bannerAd    = null;
          _bannerReady = false;
          notifyListeners();
          // Auto-retry after 30 seconds
          Future.delayed(const Duration(seconds: 30), loadBanner);
        },
        onAdOpened:  (_) {},
        onAdClosed:  (_) {},
        onAdImpression: (_) {},
      ),
    )..load();
  }

  // ── Interstitial ─────────────────────────────────────────────────────────────

  void _loadInterstitial() {
    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request:  const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd    = ad;
          _interstitialReady = true;

          _interstitialAd!.setImmersiveMode(true);
          _interstitialAd!.fullScreenContentCallback =
              FullScreenContentCallback(
            onAdShowedFullScreenContent: (_) {},
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitialAd    = null;
              _interstitialReady = false;
              _loadInterstitial(); // preload next immediately
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _interstitialAd    = null;
              _interstitialReady = false;
              _loadInterstitial();
            },
            onAdImpression:     (_) {},
            onAdClicked:        (_) {},
          );
        },
        onAdFailedToLoad: (error) {
          _interstitialAd    = null;
          _interstitialReady = false;
          // Retry after 30 seconds
          Future.delayed(const Duration(seconds: 30), _loadInterstitial);
        },
      ),
    );
  }

  /// Shows the interstitial ad if one is ready.
  /// Returns [true] if the ad was shown, [false] otherwise.
  bool showInterstitial() {
    if (_interstitialReady && _interstitialAd != null) {
      _interstitialAd!.show();
      _interstitialReady = false;
      return true;
    }
    return false;
  }

  // ── IAP stubs (kept for interface compatibility) ─────────────────────────────
  Future<void> purchaseRemoveAds() async {}
  Future<void> restorePurchases()  async {}

  // ── Dispose ──────────────────────────────────────────────────────────────────
  @override
  void dispose() {
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    super.dispose();
  }
}
