import 'dart:io';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../theme/app_theme.dart';
import '../services/api_service.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<double> _scale;

  String _status = 'Initializing...';

  // BUG 6 FIX — track retry count so we can show a manual retry button
  int _retryCount = 0;
  static const int _maxAutoRetries = 3;
  bool _showRetryButton = false;
  String? _errorMessage;

  // Encrypted storage — replaces SharedPreferences
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _ctrl.forward();
    _initApp();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<String> _getOrCreateUserId() async {
    final stored = await _storage.read(key: 'xissin_user_id');
    if (stored != null && stored.isNotEmpty) return stored;

    String id;
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        id = (await info.androidInfo).id;
      } else if (Platform.isIOS) {
        id = (await info.iosInfo).identifierForVendor ??
            DateTime.now().millisecondsSinceEpoch.toString();
      } else {
        id = DateTime.now().millisecondsSinceEpoch.toString();
      }
    } catch (_) {
      id = DateTime.now().millisecondsSinceEpoch.toString();
    }

    await _storage.write(key: 'xissin_user_id', value: id);
    return id;
  }

  Future<void> _initApp() async {
    // Reset UI state on each attempt
    setState(() {
      _showRetryButton = false;
      _errorMessage = null;
    });

    await Future.delayed(const Duration(milliseconds: 700));

    try {
      // ── BUG 2 FIX — Check maintenance mode & min version FIRST ─────────────
      _setStatus('Checking server status...');
      try {
        final status = await ApiService.getStatus();

        // Maintenance mode check
        if (status['maintenance'] == true) {
          final msg = status['maintenance_message'] as String? ??
              'Xissin is under maintenance. Please check back later.';
          _showMaintenanceDialog(msg);
          return;
        }

        // Minimum version check
        final minVersion = status['min_app_version'] as String? ?? '1.0.0';
        const currentVersion = '1.0.0'; // bump this with each release
        if (_isVersionOutdated(currentVersion, minVersion)) {
          _showUpdateDialog(minVersion);
          return;
        }
      } catch (_) {
        // If status check fails, we still proceed — don't hard-block the app
        // on a non-critical endpoint failure
      }

      // ── Get device ID ────────────────────────────────────────────────────────
      _setStatus('Getting device info...');
      final userId = await _getOrCreateUserId();

      // ── Register with backend ─────────────────────────────────────────────
      _setStatus('Connecting to server...');
      final registerResponse = await ApiService.registerUser(
        userId: userId,
        deviceInfo: Platform.isAndroid ? 'android' : 'ios',
      );

      // ── BUG 1 FIX — Check if user is banned ──────────────────────────────
      if (registerResponse['banned'] == true) {
        _showBannedDialog();
        return;
      }

      // ── All good — go to home ─────────────────────────────────────────────
      _setStatus('Ready!');
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 400),
          pageBuilder: (_, __, ___) => HomeScreen(userId: userId),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
    } on ApiException catch (e) {
      _handleError(e.userMessage);
    } catch (e) {
      _handleError('Connection error. Please check your internet.');
    }
  }

  // ── BUG 6 FIX — max retries + manual retry button ────────────────────────
  void _handleError(String message) {
    _retryCount++;
    if (_retryCount < _maxAutoRetries) {
      _setStatus('$message Retrying...');
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _initApp();
      });
    } else {
      // Max auto-retries hit — show manual retry button
      setState(() {
        _errorMessage = message;
        _showRetryButton = true;
        _status = message;
      });
    }
  }

  void _manualRetry() {
    _retryCount = 0;
    _initApp();
  }

  // ── BUG 1 FIX — banned dialog ────────────────────────────────────────────
  void _showBannedDialog() {
    setState(() => _status = 'Account restricted.');
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.block_rounded, color: AppColors.error, size: 22),
            SizedBox(width: 10),
            Text('Account Banned',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 17)),
          ],
        ),
        content: const Text(
          'Your account has been banned.\n\nIf you believe this is a mistake, contact the admin on Telegram: @Xissin_0',
          style: TextStyle(
              color: AppColors.textSecondary, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => exit(0),
            child: const Text('Close App',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  // ── BUG 2 FIX — maintenance dialog ───────────────────────────────────────
  void _showMaintenanceDialog(String message) {
    setState(() => _status = 'Under maintenance.');
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.build_circle_rounded,
                color: AppColors.secondary, size: 22),
            SizedBox(width: 10),
            Text('Maintenance',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 17)),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: _manualRetry,
            child: const Text('Try Again',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  // ── BUG 2 FIX — force update dialog ──────────────────────────────────────
  void _showUpdateDialog(String minVersion) {
    setState(() => _status = 'Update required.');
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.system_update_rounded,
                color: AppColors.primary, size: 22),
            SizedBox(width: 10),
            Text('Update Required',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 17)),
          ],
        ),
        content: Text(
          'This version of Xissin is outdated.\nMinimum required version: $minVersion\n\nPlease update the app from the Xissin Telegram channel.',
          style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => exit(0),
            child: const Text('Close',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  /// Compares semver strings. Returns true if current < minimum.
  bool _isVersionOutdated(String current, String minimum) {
    try {
      final cur = current.split('.').map(int.parse).toList();
      final min = minimum.split('.').map(int.parse).toList();
      for (int i = 0; i < 3; i++) {
        final c = i < cur.length ? cur[i] : 0;
        final m = i < min.length ? min[i] : 0;
        if (c < m) return true;
        if (c > m) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void _setStatus(String s) {
    if (mounted) setState(() => _status = s);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.secondary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.45),
                        blurRadius: 36,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.bolt_rounded,
                      size: 58, color: Colors.white),
                ),
                const SizedBox(height: 30),
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(
                    colors: [AppColors.primary, AppColors.secondary],
                  ).createShader(b),
                  child: const Text(
                    'XISSIN',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'MULTI-TOOL',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 5,
                  ),
                ),
                const SizedBox(height: 70),

                // BUG 6 FIX — show spinner OR retry button
                if (!_showRetryButton) ...[
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 2.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _status,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ] else ...[
                  const Icon(Icons.wifi_off_rounded,
                      color: AppColors.error, size: 32),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      _errorMessage ?? 'Connection failed.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _manualRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
