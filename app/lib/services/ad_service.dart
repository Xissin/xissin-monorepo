import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'payment_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdService — Live AdMob + Premium key support
//
// • Banner      : ca-app-pub-7516216593424837/7804365873
// • Interstitial: ca-app-pub-7516216593424837/9918305586
//
// Part 2 addition: showGatedInterstitial()
//   Used by SMS Bomber, NGL Bomber, IP Tracker, Username Tracker to gate
//   tool access for free users. Shows interstitial, then calls onGranted
//   when dismissed (or immediately if premium or no ad ready).
// ─────────────────────────────────────────────────────────────────────────────

class AdService extends ChangeNotifier {
  static final AdService instance = AdService._();
  AdService._();

  static const String bannerAdUnitId       = 'ca-app-pub-7516216593424837/7804365873';
  static const String interstitialAdUnitId = 'ca-app-pub-7516216593424837/9918305586';

  static const List<String> _testDeviceIds = [];

  static const String _prefKeyPremium = 'xissin_is_premium';

  InterstitialAd? _interstitialAd;
  bool _interstitialReady = false;
  bool _initialized       = false;
  bool _sdkReady          = false;
  bool _adsRemoved        = false;

  bool get adsRemoved   => _adsRemoved;
  bool get purchasing   => false;
  String? get purchaseError => null;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> initSdkOnly() async {
    if (_initialized) return;
    _initialized = true;

    await _loadCachedPremium();

    try {
      await MobileAds.instance.initialize();
      _sdkReady = true;
    } catch (e) {
      debugPrint('[AdService] SDK init error: $e');
      return;
    }

    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(
        tagForChildDirectedTreatment: TagForChildDirectedTreatment.unspecified,
        tagForUnderAgeOfConsent:      TagForUnderAgeOfConsent.unspecified,
        maxAdContentRating:           MaxAdContentRating.t,
        testDeviceIds: kDebugMode ? _testDeviceIds : [],
      ),
    );

    if (_adsRemoved) return;
  }

  Future<void> init({String? userId}) async {
    if (!_initialized) await initSdkOnly();

    if (userId != null && !_adsRemoved) {
      _verifyPremiumInBackground(userId);
    }

    if (_sdkReady && !_adsRemoved && !_interstitialReady && _interstitialAd == null) {
      _loadInterstitial();
    }
  }

  // ── Premium state ─────────────────────────────────────────────────────────

  Future<void> _loadCachedPremium() async {
    try {
      final prefs  = await SharedPreferences.getInstance();
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
            _interstitialAd?.dispose();
            _interstitialAd    = null;
            _interstitialReady = false;
          }
          notifyListeners();
        }
      } catch (_) {}
    });
  }

  Future<void> onPurchaseComplete(String userId) async {
    _adsRemoved = true;
    await _saveCachedPremium(true);

    _interstitialAd?.dispose();
    _interstitialAd    = null;
    _interstitialReady = false;

    notifyListeners();
  }

  // ── Banner Factory ─────────────────────────────────────────────────────────

  BannerAd? createBannerAd({
    required VoidCallback onLoaded,
    required VoidCallback onFailed,
  }) {
    if (!_sdkReady || _adsRemoved) return null;

    return BannerAd(
      adUnitId: bannerAdUnitId,
      size:     AdSize.banner,
      request:  const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded:       (_) => onLoaded(),
        onAdFailedToLoad: (ad, error) {
          debugPrint('[AdService] Banner failed: ${error.message}');
          ad.dispose();
          onFailed();
        },
        onAdOpened:     (_) {},
        onAdClosed:     (_) {},
        onAdImpression: (_) {},
      ),
    );
  }

  // ── Interstitial ──────────────────────────────────────────────────────────

  void _loadInterstitial() {
    if (_adsRemoved || !_sdkReady) return;

    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
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
            onAdShowedFullScreenContent:    (_) {},
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitialAd    = null;
              _interstitialReady = false;
              if (!_adsRemoved) _loadInterstitial();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              debugPrint('[AdService] Interstitial show error: ${error.message}');
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
          debugPrint('[AdService] Interstitial load failed: ${error.message}');
          _interstitialAd    = null;
          _interstitialReady = false;
          if (!_adsRemoved) {
            Future.delayed(const Duration(seconds: 30), _loadInterstitial);
          }
        },
      ),
    );
  }

  /// Shows interstitial normally (no grant callback).
  bool showInterstitial() {
    if (_adsRemoved || !_sdkReady) return false;
    if (_interstitialReady && _interstitialAd != null) {
      _interstitialAd!.show();
      _interstitialReady = false;
      return true;
    }
    return false;
  }

  // ── PART 2: Gated Interstitial ─────────────────────────────────────────────
  //
  // Used by: SMS Bomber, NGL Bomber, IP Tracker, Username Tracker
  //
  // Shows an interstitial as a "reward gate":
  //   • If premium  → calls onGranted() immediately (no ad shown)
  //   • If ad ready → shows ad, calls onGranted() when dismissed
  //   • If no ad    → calls onGranted() immediately (fail open — never block user)
  //
  // The screen is responsible for tracking the granted state and enforcing
  // cooldowns. AdService only handles the ad show/dismiss lifecycle.

  void showGatedInterstitial({required VoidCallback onGranted}) {
    // Premium users bypass the gate entirely
    if (_adsRemoved) {
      onGranted();
      return;
    }

    if (_interstitialReady && _interstitialAd != null) {
      // Override the fullscreen callback to notify caller on dismiss
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdShowedFullScreenContent: (_) {},
        onAdImpression:              (_) {},
        onAdClicked:                 (_) {},
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _interstitialAd    = null;
          _interstitialReady = false;
          if (!_adsRemoved) _loadInterstitial(); // preload for next time
          onGranted();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          debugPrint('[AdService] Gated ad show error: ${error.message}');
          ad.dispose();
          _interstitialAd    = null;
          _interstitialReady = false;
          if (!_adsRemoved) _loadInterstitial();
          onGranted(); // fail open — never block user because of ad failure
        },
      );
      _interstitialAd!.show();
      _interstitialReady = false;
    } else {
      // No ad ready — fail open, preload for next time
      if (!_adsRemoved) _loadInterstitial();
      onGranted();
    }
  }

  // ── Dispose ───────────────────────────────────────────────────────────────
  @override
  void dispose() {
    _interstitialAd?.dispose();
    super.dispose();
  }
}
