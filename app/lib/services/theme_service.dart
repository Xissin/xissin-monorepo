import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  static const String _key = 'theme_dark_mode';
  
  bool _isDark = true;
  bool _initialized = false;

  bool get isDark => _isDark;
  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDark = prefs.getBool(_key) ?? true;
    } catch (_) {
      _isDark = true;
    }
    
    _initialized = true;
    notifyListeners();
  }

  Future<void> toggle() async {
    _isDark = !_isDark;
    notifyListeners();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, _isDark);
    } catch (_) {}
  }

  Future<void> setDarkMode(bool isDark) async {
    if (_isDark == isDark) return;
    
    _isDark = isDark;
    notifyListeners();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, _isDark);
    } catch (_) {}
  }
}
