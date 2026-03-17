import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'payment_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdService — Live AdMob + Remove Ads (premium) support
//
// • Banner      : ca-app-pub-7516216593424837/7804365873
// • Interstitial: ca-app-pub-7516216593424837/9918305586
//
// Premium status is cached locally in SharedPreferences and verified
// against the backend on every app start.
// ─────────────────────────────────────────────────────────────────────────────

class AdService extends ChangeNotifier {
  static final AdService instance = AdService._();
  AdService._();

  // ── Ad Unit IDs ─────────────────────────────────────────────────────────────
  static const String _bannerAdUnitId =
      'ca-app-pub-7516216593424837/7804365873';
  static const String _interstitialAdUnitId =
      'ca-app-pub-7516216593424837/9918305586';

  static const String _prefKeyPremium = 'xissin_is_premium';

  // ── Internal state ───────────────────────────────────────────────────────────
  BannerAd?       _bannerAd;
  InterstitialAd? _interstitialAd;

  bool _bannerReady       = false;
  bool _interstitialReady = false;
  bool _initialized       = false;
  bool _adsRemoved        = false;   // true = user paid, hide all ads

  // ── Public getters ───────────────────────────────────────────────────────────
  bool       get adsRemoved    => _adsRemoved;
  bool       get bannerReady   => _bannerReady && !_adsRemoved;
  BannerAd?  get bannerAd      => _adsRemoved ? null : _bannerAd;
  bool       get purchasing    => false;
  String?    get purchaseError => null;

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  Future<void> init({String? userId}) async {
    if (_initialized) return;
    _initialized = true;

    // 1. Load cached premium state immediately (no network wait)
    await _loadCachedPremium();

    // 2. Verify with backend in background
    if (userId != null) {
      _verifyPremiumInBackground(userId);
    }

    if (_adsRemoved) return; // Don't load ads if premium

    await MobileAds.instance.initialize();

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

  // ── Premium state management ──────────────────────────────────────────────

  Future<void> _loadCachedPremium() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getBool(_prefKeyPremium) ?? false;
      if (cached != _adsRemoved) {
        _adsRemoved = cached;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _saveCachedPremium(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyPremium, value);
    } catch (_) {}
  }

  void _verifyPremiumInBackground(String userId) {
    Future.microtask(() async {
      try {
        final isPremium = await PaymentService.isPremium(userId);
        if (isPremium != _adsRemoved) {
          _adsRemoved = isPremium;
          await _saveCachedPremium(isPremium);
          if (isPremium) {
            // User is premium — dispose ads immediately
            _bannerAd?.dispose();
            _bannerAd        = null;
            _bannerReady     = false;
            _interstitialAd?.dispose();
            _interstitialAd  = null;
            _interstitialReady = false;
          }
          notifyListeners();
        }
      } catch (_) {}
    });
  }

  /// Called after a successful payment to immediately remove ads.
  Future<void> onPurchaseComplete(String userId) async {
    _adsRemoved = true;
    await _saveCachedPremium(true);

    _bannerAd?.dispose();
    _bannerAd        = null;
    _bannerReady     = false;
    _interstitialAd?.dispose();
    _interstitialAd  = null;
    _interstitialReady = false;

    notifyListeners();
  }

  // ── Banner ───────────────────────────────────────────────────────────────────

  void loadBanner() {
    if (_adsRemoved) return;

    _bannerAd?.dispose();
    _bannerAd    = null;
    _bannerReady = false;

    _bannerAd = BannerAd(
      adUnitId: _bannerAdUnitId,
      size:     AdSize.banner,
      request:  const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (_adsRemoved) {
            _bannerAd?.dispose();
            _bannerAd = null;
            return;
          }
          _bannerReady = true;
          notifyListeners();
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _bannerAd    = null;
          _bannerReady = false;
          notifyListeners();
          if (!_adsRemoved) {
            Future.delayed(const Duration(seconds: 30), loadBanner);
          }
        },
        onAdOpened:     (_) {},
        onAdClosed:     (_) {},
        onAdImpression: (_) {},
      ),
    )..load();
  }

  // ── Interstitial ─────────────────────────────────────────────────────────────

  void _loadInterstitial() {
    if (_adsRemoved) return;

    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request:  const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          if (_adsRemoved) {
            ad.dispose();
            return;
          }
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
              if (!_adsRemoved) _loadInterstitial();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _interstitialAd    = null;
              _interstitialReady = false;
              if (!_adsRemoved) _loadInterstitial();
            },
            onAdImpression: (_) {},
            onAdClicked:    (_) {},
          );
        },
        onAdFailedToLoad: (error) {
          _interstitialAd    = null;
          _interstitialReady = false;
          if (!_adsRemoved) {
            Future.delayed(const Duration(seconds: 30), _loadInterstitial);
          }
        },
      ),
    );
  }

  /// Shows the interstitial ad if one is ready AND user is not premium.
  /// Returns [true] if the ad was shown, [false] otherwise.
  bool showInterstitial() {
    if (_adsRemoved) return false;
    if (_interstitialReady && _interstitialAd != null) {
      _interstitialAd!.show();
      _interstitialReady = false;
      return true;
    }
    return false;
  }

  // ── Dispose ──────────────────────────────────────────────────────────────────
  @override
  void dispose() {
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    super.dispose();
  }
}
