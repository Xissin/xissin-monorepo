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
// ⚠️  IMPORTANT — Banner Ad Architecture:
//   Each screen creates its OWN BannerAd instance via [createBannerAd()].
//   AdService intentionally does NOT hold a shared BannerAd because placing
//   the same AdWidget in multiple screens simultaneously causes:
//   "This AdWidget is already in the Widget tree" crash.
//
// ⚠️  TEST DEVICE SETUP (required to see ads on your Infinix during dev):
//   1. Run the app with USB/wireless debug.
//   2. Open logcat and search for: "Use RequestConfiguration.Builder"
//   3. Copy the device ID shown (e.g. "33BE2250B43FA69")
//   4. Paste it in _testDeviceIds below.
//   5. Re-run. Ads will now fill properly on your device.
//   Remove or leave empty for production builds.
//
// Premium status is cached locally in SharedPreferences and verified
// against the backend on every app start.
// ─────────────────────────────────────────────────────────────────────────────

class AdService extends ChangeNotifier {
  static final AdService instance = AdService._();
  AdService._();

  // ── Ad Unit IDs (public so screens can use them directly) ────────────────────
  static const String bannerAdUnitId       = 'ca-app-pub-7516216593424837/7804365873';
  static const String interstitialAdUnitId = 'ca-app-pub-7516216593424837/9918305586';

  // ── TEST DEVICE IDs ──────────────────────────────────────────────────────────
  // Add your Infinix device ID here (see instructions above).
  // Get it from logcat after first run. Leave empty list for production.
  // Example: static const List<String> _testDeviceIds = ['33BE2250B43FA69'];
  static const List<String> _testDeviceIds = [];

  static const String _prefKeyPremium = 'xissin_is_premium';

  // ── Internal state ───────────────────────────────────────────────────────────
  InterstitialAd? _interstitialAd;

  bool _interstitialReady = false;
  bool _initialized       = false;
  bool _sdkReady          = false; // true once MobileAds.instance.initialize() completes
  bool _adsRemoved        = false; // true = user paid, hide all ads

  // ── Public getters ───────────────────────────────────────────────────────────
  bool get adsRemoved   => _adsRemoved;
  bool get purchasing   => false;
  String? get purchaseError => null;

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  /// Step 1 — called from main(), no userId needed yet.
  /// FIX: SDK is ALWAYS initialized regardless of premium status.
  /// Premium only controls whether we load/show ads — not SDK init.
  Future<void> initSdkOnly() async {
    if (_initialized) return;
    _initialized = true;

    // Load cached premium state FIRST so UI knows immediately
    await _loadCachedPremium();

    // ── ALWAYS initialize the AdMob SDK ──────────────────────────────────────
    // Previously, we returned early if _adsRemoved was true, which meant
    // MobileAds.instance.initialize() was never called. This caused ads to
    // silently fail even if premium was incorrectly cached. Fixed here.
    try {
      await MobileAds.instance.initialize();
      _sdkReady = true;
    } catch (e) {
      debugPrint('[AdService] SDK init error: $e');
      return;
    }

    // ── Configure ad request settings ────────────────────────────────────────
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(
        tagForChildDirectedTreatment: TagForChildDirectedTreatment.unspecified,
        tagForUnderAgeOfConsent:      TagForUnderAgeOfConsent.unspecified,
        maxAdContentRating:           MaxAdContentRating.t,
        // Register your test device so ads fill during development.
        // See _testDeviceIds comment at the top of this file.
        testDeviceIds: kDebugMode ? _testDeviceIds : [],
      ),
    );

    // If premium is already confirmed from cache, skip preloading ads
    if (_adsRemoved) return;
  }

  /// Step 2 — called from HomeScreen.initState() once userId is known.
  /// Safe to call multiple times.
  Future<void> init({String? userId}) async {
    if (!_initialized) await initSdkOnly();

    if (userId != null && !_adsRemoved) {
      _verifyPremiumInBackground(userId);
    }

    if (_sdkReady && !_adsRemoved && !_interstitialReady && _interstitialAd == null) {
      _loadInterstitial();
    }
  }

  // ── Premium state management ─────────────────────────────────────────────────

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

  /// Called after a successful payment to immediately remove ads.
  Future<void> onPurchaseComplete(String userId) async {
    _adsRemoved = true;
    await _saveCachedPremium(true);

    _interstitialAd?.dispose();
    _interstitialAd    = null;
    _interstitialReady = false;

    notifyListeners();
  }

  // ── Banner Factory ───────────────────────────────────────────────────────────
  //
  // Each screen calls createBannerAd() in initState() to get its OWN instance.
  // The screen is responsible for calling .load() and .dispose() on it.

  BannerAd? createBannerAd({
    required VoidCallback onLoaded,
    required VoidCallback onFailed,
  }) {
    // Guard: don't create banner if SDK isn't ready or user is premium
    if (!_sdkReady || _adsRemoved) return null;

    return BannerAd(
      adUnitId: bannerAdUnitId,
      size:     AdSize.banner,
      request:  const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded:        (_) => onLoaded(),
        onAdFailedToLoad:  (ad, error) {
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

  // ── Interstitial ─────────────────────────────────────────────────────────────

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

  /// Shows the interstitial ad if one is ready AND user is not premium.
  /// Returns [true] if the ad was shown, [false] otherwise.
  bool showInterstitial() {
    if (_adsRemoved || !_sdkReady) return false;
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
    _interstitialAd?.dispose();
    super.dispose();
  }
}