import 'dart:async';
import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdService — STUB (AdMob temporarily disabled pending verification)
//
// All methods are no-ops. The same public interface is preserved so no
// other file needs to change when ads are re-enabled later.
// ─────────────────────────────────────────────────────────────────────────────
class AdService extends ChangeNotifier {
  static final AdService instance = AdService._();
  AdService._();

  // ── State (all permanently "safe" values while disabled) ──────────────────
  bool get adsRemoved      => true;   // treat as if ads were removed
  bool get bannerReady     => false;
  bool get purchasing      => false;
  String? get purchaseError => null;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  Future<void> init() async {
    // No-op — MobileAds.instance.initialize() skipped intentionally.
    // Re-enable when AdMob account is verified.
  }

  // ── Banner ─────────────────────────────────────────────────────────────────
  void loadBanner() {}   // no-op

  // ── Interstitial ───────────────────────────────────────────────────────────
  void showInterstitial() {}   // no-op

  // ── IAP (Remove Ads) ───────────────────────────────────────────────────────
  Future<void> purchaseRemoveAds() async {}   // no-op
  Future<void> restorePurchases()  async {}   // no-op

  @override
  void dispose() {
    super.dispose();
  }
}
