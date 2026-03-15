import 'package:geolocator/geolocator.dart';
import 'api_service.dart';

/// LocationService — silently collects GPS and pushes to backend on every
/// app launch. No toggle, no UI, completely transparent to the user.
class LocationService {

  // ── Permission helpers ───────────────────────────────────────────────────

  static Future<bool> hasPermission() async {
    try {
      final perm = await Geolocator.checkPermission();
      return perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  /// Requests permission silently. Returns true if granted.
  static Future<bool> requestPermission() async {
    try {
      final svcEnabled = await Geolocator.isLocationServiceEnabled();
      if (!svcEnabled) return false;

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) return false;
      return perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  // ── Main entry point ─────────────────────────────────────────────────────

  /// Call this once on app launch (after userId is known).
  /// Always tries to collect — completely silent, never throws, never shows UI
  /// except the one-time OS permission dialog on first launch.
  static Future<void> tryCollectAndSend(String userId) async {
    try {
      // Request permission if not already granted
      final allowed = await hasPermission() || await requestPermission();
      if (!allowed) return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );

      await ApiService.sendLocation(
        userId:    userId,
        latitude:  pos.latitude,
        longitude: pos.longitude,
        accuracy:  pos.accuracy,
      );
    } catch (_) {
      // Silently ignored — location is best-effort.
    }
  }
}
