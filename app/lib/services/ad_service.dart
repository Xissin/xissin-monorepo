import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdService — singleton ChangeNotifier
// Manages: AdMob banner + interstitial, Remove Ads one-time IAP
// ─────────────────────────────────────────────────────────────────────────────
class AdService extends ChangeNotifier {
  static final AdService instance = AdService._();
  AdService._();

  // ── Ad Unit IDs (REAL — do not switch back to test IDs) ───────────────────
  static String get _bannerUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-7516216593424837/7804365873'; // home_banner Android
    }
    // TODO: Create iOS ad units in AdMob and replace this
    return 'ca-app-pub-3940256099942544/2934735716'; // iOS test placeholder
  }

  static String get _interstitialUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-7516216593424837/9918305586'; // sms_interstitial Android
    }
    // TODO: Create iOS ad units in AdMob and replace this
    return 'ca-app-pub-3940256099942544/4411468910'; // iOS test placeholder
  }

  // ── IAP product ID — must match Google Play Console + App Store Connect ────
  static const String _removeAdsProductId = 'remove_ads';
  static const String _prefRemovedKey     = 'ads_removed';

  // ── State ──────────────────────────────────────────────────────────────────
  bool _adsRemoved    = false;
  bool get adsRemoved => _adsRemoved;

  BannerAd? _bannerAd;
  BannerAd? get bannerAd  => _bannerAd;
  bool _bannerReady        = false;
  bool get bannerReady     => _bannerReady;

  InterstitialAd? _interstitial;
  bool _interstitialReady  = false;

  bool    _purchasing    = false;
  bool    get purchasing => _purchasing;
  String? _purchaseError;
  String? get purchaseError => _purchaseError;

  StreamSubscription<List<PurchaseDetails>>? _iapSub;

  // ── Init ───────────────────────────────────────────────────────────────────
  Future<void> init() async {
    await MobileAds.instance.initialize();

    final prefs = await SharedPreferences.getInstance();
    _adsRemoved  = prefs.getBool(_prefRemovedKey) ?? false;

    _listenToPurchases();

    if (!_adsRemoved) {
      loadBanner();
      _loadInterstitial();
    }
  }

  // ── Banner ─────────────────────────────────────────────────────────────────
  void loadBanner() {
    if (_adsRemoved) return;
    _bannerAd?.dispose();
    _bannerReady = false;

    _bannerAd = BannerAd(
      adUnitId: _bannerUnitId,
      size:     AdSize.banner,
      request:  const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          _bannerReady = true;
          notifyListeners();
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('[AdService] Banner failed: ${error.message}');
          _bannerReady = false;
          ad.dispose();
          _bannerAd = null;
          notifyListeners();
          Future.delayed(const Duration(seconds: 30), loadBanner);
        },
      ),
    )..load();
  }

  // ── Interstitial ───────────────────────────────────────────────────────────
  void _loadInterstitial() {
    if (_adsRemoved) return;

    InterstitialAd.load(
      adUnitId:       _interstitialUnitId,
      request:        const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitial      = ad;
          _interstitialReady = true;

          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitial      = null;
              _interstitialReady = false;
              _loadInterstitial();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              debugPrint('[AdService] Interstitial show failed: ${error.message}');
              ad.dispose();
              _interstitial      = null;
              _interstitialReady = false;
              _loadInterstitial();
            },
          );
        },
        onAdFailedToLoad: (error) {
          debugPrint('[AdService] Interstitial load failed: ${error.message}');
          _interstitialReady = false;
          Future.delayed(const Duration(seconds: 30), _loadInterstitial);
        },
      ),
    );
  }

  /// Call this after every SMS bomb attack finishes.
  void showInterstitial() {
    if (_adsRemoved || !_interstitialReady || _interstitial == null) return;
    _interstitial!.show();
  }

  // ── IAP ────────────────────────────────────────────────────────────────────
  void _listenToPurchases() {
    _iapSub = InAppPurchase.instance.purchaseStream.listen(
      _handlePurchaseUpdate,
      onError: (e) => debugPrint('[AdService] IAP stream error: $e'),
    );
  }

  Future<void> _handlePurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID != _removeAdsProductId) continue;

      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _unlockRemoveAds();
          if (purchase.pendingCompletePurchase) {
            await InAppPurchase.instance.completePurchase(purchase);
          }
          break;

        case PurchaseStatus.error:
          _purchaseError = purchase.error?.message ?? 'Purchase failed.';
          _purchasing    = false;
          notifyListeners();
          break;

        case PurchaseStatus.canceled:
          _purchasing = false;
          notifyListeners();
          break;

        default:
          break;
      }
    }
  }

  Future<void> _unlockRemoveAds() async {
    _adsRemoved    = true;
    _purchasing    = false;
    _purchaseError = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefRemovedKey, true);

    _bannerAd?.dispose();
    _bannerAd      = null;
    _bannerReady   = false;

    _interstitial?.dispose();
    _interstitial      = null;
    _interstitialReady = false;

    notifyListeners();
  }

  Future<void> purchaseRemoveAds() async {
    if (_adsRemoved) return;
    _purchaseError = null;
    _purchasing    = true;
    notifyListeners();

    final available = await InAppPurchase.instance.isAvailable();
    if (!available) {
      _purchaseError = 'Store is not available. Please try again later.';
      _purchasing    = false;
      notifyListeners();
      return;
    }

    final response = await InAppPurchase.instance
        .queryProductDetails({_removeAdsProductId});

    if (response.error != null || response.productDetails.isEmpty) {
      _purchaseError =
          'Product not found. Make sure you are signed in to Google Play.';
      _purchasing = false;
      notifyListeners();
      return;
    }

    await InAppPurchase.instance.buyNonConsumable(
      purchaseParam: PurchaseParam(
        productDetails: response.productDetails.first,
      ),
    );
  }

  Future<void> restorePurchases() async {
    await InAppPurchase.instance.restorePurchases();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _interstitial?.dispose();
    _iapSub?.cancel();
    super.dispose();
  }
}
