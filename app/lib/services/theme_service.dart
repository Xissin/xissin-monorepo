import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  static const String _key = 'theme_dark_mode';

  bool _isDark = true; // default: dark
  bool _initialized = false;

  bool get isDark => _isDark;
  bool get isInitialized => _initialized;

  /// Call this once at app start and **await** it so the saved theme is loaded
  /// before the first frame is painted (avoids a flash of the wrong theme).
  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDark = prefs.getBool(_key) ?? true; // default dark
    } catch (_) {
      _isDark = true;
    }
    _initialized = true;
    notifyListeners();
  }

  /// Toggle between dark and light and persist the choice.
  Future<void> toggle() async {
    _isDark = !_isDark;
    notifyListeners();
    await _persist();
  }

  /// Explicitly set the theme mode and persist.
  Future<void> setDark(bool value) async {
    if (_isDark == value) return;
    _isDark = value;
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, _isDark);
    } catch (_) {
      // Silently ignore — user preference is already applied in memory.
    }
  }
}
