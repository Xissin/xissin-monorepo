import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/shimmer_skeleton.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _ctrl;
  late AnimationController _pulseController;
  late Animation<double> _fade;
  late Animation<double> _scale;
  late Animation<double> _pulse;

  String _status = 'Initializing...';
  int _retryCount = 0;
  static const int _maxAutoRetries = 3;
  bool _showRetryButton = false;
  String? _errorMessage;

  // ── Links ──────────────────────────────────────────────────────────────────
  static const String _telegramUrl = 'https://t.me/Xissin_0';
  static const String _driveUrl =
      'https://drive.google.com/file/d/1ONwQUQiD8IRGA2ganJpaZ5brALtcOWMF/view?usp=sharing';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000));

    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _pulse = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _ctrl.forward();
    _pulseController.repeat(reverse: true);
    _initApp();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ── Open URL ───────────────────────────────────────────────────────────────
  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── User ID ────────────────────────────────────────────────────────────────
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

  // ── Rich Device Info Collection ────────────────────────────────────────────
  /// Collects full hardware details + emulator/VM detection.
  /// Sent to the backend on EVERY app launch so admin always has fresh data.
  Future<Map<String, dynamic>> _collectDeviceInfo() async {
    final info    = DeviceInfoPlugin();
    final pkgInfo = await PackageInfo.fromPlatform();

    try {
      if (Platform.isAndroid) {
        final a = await info.androidInfo;

        // Emulator / VM detection heuristics
        final brandLower = a.brand.toLowerCase();
        final modelLower = a.model.toLowerCase();
        final productLower = a.product.toLowerCase();
        final hardwareLower = a.hardware.toLowerCase();

        final isEmulator = !a.isPhysicalDevice ||
            brandLower == 'google' && modelLower.contains('sdk') ||
            productLower.contains('sdk') ||
            productLower.contains('emulator') ||
            productLower.contains('vbox') ||
            hardwareLower == 'goldfish' ||
            hardwareLower == 'ranchu' ||
            modelLower.contains('emulator') ||
            modelLower == 'android sdk built for x86' ||
            brandLower.contains('genymotion') ||
            productLower.contains('nox') ||
            productLower.contains('bluestacks') ||
            productLower.contains('ldmicro') ||
            productLower.contains('memu');

        return {
          'platform':          'android',
          'brand':             a.brand,
          'model':             a.model,
          'manufacturer':      a.manufacturer,
          'product':           a.product,
          'board':             a.board,
          'hardware':          a.hardware,
          'android_version':   a.version.release,
          'sdk_int':           a.version.sdkInt,
          'is_physical_device': a.isPhysicalDevice,
          'is_emulator':       isEmulator,
          'fingerprint':       a.fingerprint,
          'app_version':       pkgInfo.version,
          'build_number':      pkgInfo.buildNumber,
        };
      } else if (Platform.isIOS) {
        final i          = await info.iosInfo;
        final isEmulator = !i.isPhysicalDevice;
        return {
          'platform':           'ios',
          'model':              i.model,
          'name':               i.name,
          'system_name':        i.systemName,
          'system_version':     i.systemVersion,
          'machine':            i.utsname.machine,
          'is_physical_device': i.isPhysicalDevice,
          'is_emulator':        isEmulator,
          'app_version':        pkgInfo.version,
          'build_number':       pkgInfo.buildNumber,
        };
      }
    } catch (_) {}

    // Fallback
    return {
      'platform':           Platform.operatingSystem,
      'is_physical_device': true,
      'is_emulator':        false,
      'app_version':        pkgInfo.version,
      'build_number':       pkgInfo.buildNumber,
    };
  }

  // ── Main Init ──────────────────────────────────────────────────────────────
  Future<void> _initApp() async {
    setState(() {
      _showRetryButton = false;
      _errorMessage    = null;
    });

    await Future.delayed(const Duration(milliseconds: 800));

    try {
      _setStatus('Checking server status...');
      try {
        final status = await ApiService.getStatus();

        // Maintenance check
        if (status['maintenance'] == true) {
          final msg = status['maintenance_message'] as String? ??
              'Xissin is under maintenance. Please check back later.';
          _showMaintenanceDialog(msg);
          return;
        }

        // Version check
        final packageInfo    = await PackageInfo.fromPlatform();
        final currentVersion = packageInfo.version;
        final minVersion     = status['min_app_version']    as String? ?? '1.0.0';
        final latestVersion  = status['latest_app_version'] as String? ?? '1.0.0';

        if (_isVersionOutdated(currentVersion, minVersion)) {
          _showForceUpdateDialog(currentVersion, minVersion);
          return;
        }
        if (_isVersionOutdated(currentVersion, latestVersion)) {
          final shouldContinue =
              await _showSoftUpdateDialog(currentVersion, latestVersion);
          if (!shouldContinue) return;
        }
      } catch (_) {}

      // ── Collect full device info ──────────────────────────────────────────
      _setStatus('Collecting device info...');
      final deviceDetails = await _collectDeviceInfo();

      _setStatus('Getting device info...');
      final userId = await _getOrCreateUserId();

      _setStatus('Connecting to server...');
      final registerResponse = await ApiService.registerUser(
        userId:        userId,
        deviceDetails: deviceDetails,
      );

      if (registerResponse['banned'] == true) {
        _showBannedDialog();
        return;
      }

      _setStatus('Ready!');
      await Future.delayed(const Duration(milliseconds: 600));

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
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

  // ── Error Handler ──────────────────────────────────────────────────────────
  void _handleError(String message) {
    _retryCount++;
    if (_retryCount < _maxAutoRetries) {
      _setStatus('$message Retrying...');
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _initApp();
      });
    } else {
      setState(() {
        _errorMessage    = message;
        _showRetryButton = true;
        _status          = message;
      });
    }
  }

  void _manualRetry() {
    _retryCount = 0;
    _initApp();
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────
  void _showBannedDialog() {
    setState(() => _status = 'Account restricted.');
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('🚫 Account Banned',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'Your account has been restricted.\nContact admin on Telegram.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => _openUrl(_telegramUrl),
            child: const Text('Open Telegram',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _showMaintenanceDialog(String msg) {
    setState(() => _status = 'Under maintenance.');
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('🔧 Maintenance',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(msg,
            style: const TextStyle(
                color: AppColors.textSecondary, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => _openUrl(_telegramUrl),
            child: const Text('Check Updates',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _showForceUpdateDialog(String current, String minimum) {
    setState(() => _status = 'Update required.');
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('⚡ Update Required',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'v$current is no longer supported.\n'
          'Minimum version: v$minimum\n\n'
          'Please update to continue.',
          style: const TextStyle(
              color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => _openUrl(_driveUrl),
            child: const Text('Download Update',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Future<bool> _showSoftUpdateDialog(
      String current, String latest) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('✨ Update Available',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'v$latest is available (you have v$current).\n'
          'Update for the latest features and fixes.',
          style: const TextStyle(
              color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Later',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => _openUrl(_telegramUrl),
                child: const Text('Telegram',
                    style: TextStyle(color: AppColors.secondary, fontSize: 12)),
              ),
              TextButton(
                onPressed: () => _openUrl(_driveUrl),
                child: const Text('Drive',
                    style: TextStyle(
                        color: Color(0xFF4285F4), fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
    return result ?? true;
  }

  // ── Version Compare ────────────────────────────────────────────────────────
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

  // ── Build ──────────────────────────────────────────────────────────────────
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
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, child) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Transform.scale(
                          scale: _pulse.value,
                          child: Container(
                            width: 160,
                            height: 160,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.primary.withOpacity(0.2),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                        Transform.scale(
                          scale: _pulse.value * 0.9,
                          child: Container(
                            width: 130,
                            height: 130,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.secondary.withOpacity(0.25),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
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
                      ],
                    );
                  },
                )
                    .animate()
                    .fadeIn(duration: 600.ms)
                    .scale(begin: const Offset(0.8, 0.8), duration: 600.ms),
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
                )
                    .animate(delay: 200.ms)
                    .fadeIn(duration: 500.ms)
                    .slideY(begin: 0.3, end: 0, duration: 500.ms),
                const SizedBox(height: 6),
                const Text(
                  'MULTI-TOOL',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 5,
                  ),
                )
                    .animate(delay: 300.ms)
                    .fadeIn(duration: 500.ms)
                    .slideY(begin: 0.3, end: 0, duration: 500.ms),
                const SizedBox(height: 70),
                if (!_showRetryButton) ...[
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 2.5,
                    ),
                  ).animate(delay: 400.ms).fadeIn(duration: 400.ms),
                  const SizedBox(height: 14),
                  Text(
                    _status,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  )
                      .animate(delay: 500.ms)
                      .fadeIn(duration: 400.ms)
                      .shimmer(
                        duration: 1500.ms,
                        delay: 800.ms,
                        color: AppColors.textSecondary.withOpacity(0.3),
                      ),
                ] else ...[
                  const Icon(Icons.wifi_off_rounded,
                          color: AppColors.error, size: 32)
                      .animate()
                      .fadeIn(duration: 400.ms)
                      .shake(delay: 200.ms, duration: 400.ms),
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
                  )
                      .animate(delay: 200.ms)
                      .fadeIn(duration: 400.ms)
                      .slideY(begin: 0.2, end: 0, duration: 400.ms),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
