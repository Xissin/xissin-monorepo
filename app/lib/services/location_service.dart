import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// LocationService — silently collects GPS and pushes to backend.
/// The user enables it via the location toggle in Settings.
/// No UI is shown here; it runs quietly in the background.
class LocationService {
  static const _prefKey = 'xissin_loc_enabled';

  // ── Preference helpers ───────────────────────────────────────────────────

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
  }

  // ── Permission check (no-throw) ──────────────────────────────────────────

  static Future<bool> hasPermission() async {
    try {
      final perm = await Geolocator.checkPermission();
      return perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  /// Asks for location permission silently.
  /// Returns true if granted.
  static Future<bool> requestPermission() async {
    try {
      bool svcEnabled = await Geolocator.isLocationServiceEnabled();
      if (!svcEnabled) return false;

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      return perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  // ── Main entry point ─────────────────────────────────────────────────────

  /// Call this once on app launch (after userId is known).
  /// It is completely silent — never throws, never shows UI.
  static Future<void> tryCollectAndSend(String userId) async {
    try {
      if (!await isEnabled()) return;
      if (!await hasPermission()) {
        final granted = await requestPermission();
        if (!granted) return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );

      await ApiService.sendLocation(
        userId:   userId,
        latitude:  pos.latitude,
        longitude: pos.longitude,
        accuracy:  pos.accuracy,
      );
    } catch (_) {
      // Silently ignored — location is best-effort.
    }
  }
}
