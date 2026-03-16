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
  // ── Animation controllers ──────────────────────────────────────────────────
  late AnimationController _entranceCtrl;   // Fade + scale entrance
  late AnimationController _pulseCtrl;      // Ring 1 & 2 pulse (slow)
  late AnimationController _fastPulseCtrl;  // Ring 3 pulse (fast inner)
  late AnimationController _dotCtrl;        // Bouncing loading dots

  late Animation<double> _fade;
  late Animation<double> _scale;
  late Animation<double> _ring1;  // Outermost ring
  late Animation<double> _ring2;  // Middle ring
  late Animation<double> _ring3;  // Inner ring (fast)
  late Animation<double> _dot1;
  late Animation<double> _dot2;
  late Animation<double> _dot3;

  // ── State ──────────────────────────────────────────────────────────────────
  String _status         = 'Initializing...';
  int    _retryCount     = 0;
  static const int _maxAutoRetries = 3;
  bool  _showRetryButton = false;
  String? _errorMessage;
  String _appVersion = '';

  // ── Links ──────────────────────────────────────────────────────────────────
  static const String _telegramUrl = 'https://t.me/Xissin_0';
  static const String _driveUrl =
      'https://drive.google.com/file/d/1ONwQUQiD8IRGA2ganJpaZ5brALtcOWMF/view?usp=sharing';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // ── Init ───────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    // Entrance (fade + scale)
    _entranceCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _fade = CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeIn);
    _scale = Tween<double>(begin: 0.65, end: 1.0).animate(
        CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOutBack));

    // Slow outer rings (2.2s)
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200));
    _ring1 = Tween<double>(begin: 0.88, end: 1.12).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _ring2 = Tween<double>(begin: 0.92, end: 1.08).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // Fast inner ring (1.3s)
    _fastPulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1300));
    _ring3 = Tween<double>(begin: 0.95, end: 1.05).animate(
        CurvedAnimation(parent: _fastPulseCtrl, curve: Curves.easeInOut));

    // Bouncing dots (800ms per dot, offset)
    _dotCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _dot1 = Tween<double>(begin: 0, end: -10).animate(
        CurvedAnimation(parent: _dotCtrl, curve: const Interval(0.0, 0.4, curve: Curves.easeInOut)));
    _dot2 = Tween<double>(begin: 0, end: -10).animate(
        CurvedAnimation(parent: _dotCtrl, curve: const Interval(0.2, 0.6, curve: Curves.easeInOut)));
    _dot3 = Tween<double>(begin: 0, end: -10).animate(
        CurvedAnimation(parent: _dotCtrl, curve: const Interval(0.4, 0.8, curve: Curves.easeInOut)));

    _entranceCtrl.forward();
    _pulseCtrl.repeat(reverse: true);
    _fastPulseCtrl.repeat(reverse: true);
    _dotCtrl.repeat(reverse: true);

    _loadVersionAndInit();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _pulseCtrl.dispose();
    _fastPulseCtrl.dispose();
    _dotCtrl.dispose();
    super.dispose();
  }

  // ── Load version then init ─────────────────────────────────────────────────
  Future<void> _loadVersionAndInit() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = 'v${pkg.version}');
    } catch (_) {}
    _initApp();
  }

  // ── URL opener ─────────────────────────────────────────────────────────────
  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── User ID (persisted) ────────────────────────────────────────────────────
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

  // ── Device info collection ─────────────────────────────────────────────────
  Future<Map<String, dynamic>> _collectDeviceInfo() async {
    final info    = DeviceInfoPlugin();
    final pkgInfo = await PackageInfo.fromPlatform();

    try {
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        final brandLower    = a.brand.toLowerCase();
        final modelLower    = a.model.toLowerCase();
        final productLower  = a.product.toLowerCase();
        final hardwareLower = a.hardware.toLowerCase();

        final isEmulator = !a.isPhysicalDevice ||
            brandLower == 'google' && modelLower.contains('sdk') ||
            productLower.contains('sdk')        ||
            productLower.contains('emulator')   ||
            productLower.contains('vbox')       ||
            hardwareLower == 'goldfish'         ||
            hardwareLower == 'ranchu'           ||
            modelLower.contains('emulator')     ||
            modelLower == 'android sdk built for x86' ||
            brandLower.contains('genymotion')   ||
            productLower.contains('nox')        ||
            productLower.contains('bluestacks') ||
            productLower.contains('ldmicro')    ||
            productLower.contains('memu');

        return {
          'platform':           'android',
          'brand':              a.brand,
          'model':              a.model,
          'manufacturer':       a.manufacturer,
          'product':            a.product,
          'board':              a.board,
          'hardware':           a.hardware,
          'android_version':    a.version.release,
          'sdk_int':            a.version.sdkInt,
          'is_physical_device': a.isPhysicalDevice,
          'is_emulator':        isEmulator,
          'fingerprint':        a.fingerprint,
          'app_version':        pkgInfo.version,
          'build_number':       pkgInfo.buildNumber,
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

    return {
      'platform':           Platform.operatingSystem,
      'is_physical_device': true,
      'is_emulator':        false,
      'app_version':        pkgInfo.version,
      'build_number':       pkgInfo.buildNumber,
    };
  }

  // ── Main init flow ─────────────────────────────────────────────────────────
  Future<void> _initApp() async {
    setState(() {
      _showRetryButton = false;
      _errorMessage    = null;
    });

    await Future.delayed(const Duration(milliseconds: 800));

    try {
      // ── 1. Server status check ─────────────────────────────────────────────
      _setStatus('Checking server...');
      try {
        final status = await ApiService.getStatus();

        // Maintenance mode
        if (status['maintenance'] == true) {
          final msg = status['maintenance_message'] as String? ??
              'Xissin is under maintenance. Please check back later.';
          _showMaintenanceDialog(msg);
          return;
        }

        // Version checks
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
              await _showOptionalUpdateDialog(currentVersion, latestVersion);
          if (!shouldContinue) return;
        }
      } catch (e) {
        _retryCount++;
        if (_retryCount < _maxAutoRetries) {
          _setStatus('Retrying... ($_retryCount/$_maxAutoRetries)');
          await Future.delayed(const Duration(seconds: 2));
          return _initApp();
        }
        // All retries exhausted
        if (!mounted) return;
        setState(() {
          _showRetryButton = true;
          _errorMessage    =
              'Cannot reach the server.\nCheck your internet connection.';
        });
        return;
      }

      // ── 2. User identity ───────────────────────────────────────────────────
      _setStatus('Setting up your profile...');
      final userId = await _getOrCreateUserId();
      ApiService.cacheUserId(userId); // cache so all subsequent requests use it

      // ── 3. Device registration (non-blocking) ──────────────────────────────
      _setStatus('Loading...');
      try {
        final deviceInfo = await _collectDeviceInfo();
        await ApiService.registerUser(
          userId:        userId,
          deviceDetails: deviceInfo,
        );
      } catch (_) {
        // Registration failure is non-blocking — app continues regardless
      }

      // ── 4. Navigate to HomeScreen ──────────────────────────────────────────
      _setStatus('Welcome to Xissin!');
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 700),
          pageBuilder: (_, __, ___) => HomeScreen(userId: userId),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeIn),
            child: child,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _showRetryButton = true;
        _errorMessage    = 'An unexpected error occurred.\nPlease tap Retry.';
      });
    }
  }

  // ── Manual retry (resets counter) ─────────────────────────────────────────
  Future<void> _manualRetry() async {
    _retryCount = 0;
    await _initApp();
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────

  void _showMaintenanceDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(children: [
          Icon(Icons.build_circle_outlined,
              color: AppColors.secondary, size: 22),
          SizedBox(width: 8),
          Text(
            'Under Maintenance',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16),
          ),
        ]),
        content: Text(
          message,
          style: const TextStyle(
              color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => _openUrl(_telegramUrl),
            child: const Text('Telegram',
                style: TextStyle(
                    color: AppColors.secondary, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  void _showForceUpdateDialog(String current, String required) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(children: [
          Icon(Icons.system_update_rounded,
              color: AppColors.error, size: 22),
          SizedBox(width: 8),
          Text(
            'Update Required',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16),
          ),
        ]),
        content: Text(
          'Your version ($current) is outdated.\n'
          'Please update to continue using Xissin.',
          style: const TextStyle(
              color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => _openUrl(_telegramUrl),
            child: const Text('Telegram',
                style: TextStyle(
                    color: AppColors.secondary, fontSize: 12)),
          ),
          TextButton(
            onPressed: () => _openUrl(_driveUrl),
            child: const Text('Drive',
                style:
                    TextStyle(color: Color(0xFF4285F4), fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Future<bool> _showOptionalUpdateDialog(
      String current, String latest) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(children: [
          Icon(Icons.new_releases_rounded,
              color: AppColors.primary, size: 22),
          SizedBox(width: 8),
          Text(
            'Update Available',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16),
          ),
        ]),
        content: Text(
          'Version $latest is available (you have $current).\n'
          'Would you like to update?',
          style: const TextStyle(
              color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Later',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ),
          TextButton(
            onPressed: () => _openUrl(_telegramUrl),
            child: const Text('Telegram',
                style: TextStyle(
                    color: AppColors.secondary, fontSize: 12)),
          ),
          TextButton(
            onPressed: () => _openUrl(_driveUrl),
            child: const Text('Drive',
                style:
                    TextStyle(color: Color(0xFF4285F4), fontSize: 12)),
          ),
        ],
      ),
    );
    return result ?? true;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor:           Colors.transparent,
        statusBarIconBrightness:  Brightness.light,
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            // ── Ambient background glow ──────────────────────────────────────
            Positioned(
              top: -80,
              left: -60,
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -60,
              right: -40,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.secondary.withOpacity(0.07),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // ── Main content ─────────────────────────────────────────────────
            Center(
              child: FadeTransition(
                opacity: _fade,
                child: ScaleTransition(
                  scale: _scale,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // ── Logo with 3-ring pulse ─────────────────────────────
                      AnimatedBuilder(
                        animation: Listenable.merge(
                            [_pulseCtrl, _fastPulseCtrl]),
                        builder: (context, child) {
                          return SizedBox(
                            width: 200,
                            height: 200,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Ring 1 — outermost (slowest)
                                Transform.scale(
                                  scale: _ring1.value,
                                  child: Container(
                                    width: 192,
                                    height: 192,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppColors.primary
                                            .withOpacity(0.12),
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                                // Ring 2 — middle
                                Transform.scale(
                                  scale: _ring2.value,
                                  child: Container(
                                    width: 158,
                                    height: 158,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppColors.secondary
                                            .withOpacity(0.18),
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                                // Ring 3 — inner (fast)
                                Transform.scale(
                                  scale: _ring3.value,
                                  child: Container(
                                    width: 130,
                                    height: 130,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppColors.accent
                                            .withOpacity(0.15),
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                ),
                                // Outer glow layer
                                Container(
                                  width: 112,
                                  height: 112,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: AppShadows.doubleGlow(
                                        AppColors.primary),
                                  ),
                                ),
                                // Logo core
                                Container(
                                  width: 106,
                                  height: 106,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const LinearGradient(
                                      colors: AppColors.primaryGradient,
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.1),
                                      width: 1,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.bolt_rounded,
                                    size: 54,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      )
                          .animate()
                          .fadeIn(duration: 600.ms)
                          .scale(
                              begin: const Offset(0.8, 0.8),
                              duration: 600.ms,
                              curve: Curves.easeOutBack),

                      const SizedBox(height: 36),

                      // ── XISSIN title ──────────────────────────────────────
                      ShaderMask(
                        shaderCallback: (b) => const LinearGradient(
                          colors: AppColors.primaryGradient,
                        ).createShader(b),
                        child: const Text(
                          'XISSIN',
                          style: TextStyle(
                            color:       Colors.white,
                            fontSize:    42,
                            fontWeight:  FontWeight.w900,
                            letterSpacing: 12,
                          ),
                        ),
                      )
                          .animate(delay: 200.ms)
                          .fadeIn(duration: 500.ms)
                          .slideY(
                              begin: 0.3,
                              end:   0,
                              duration: 500.ms,
                              curve: Curves.easeOutCubic),

                      const SizedBox(height: 6),

                      // ── MULTI-TOOL subtitle ───────────────────────────────
                      const Text(
                        'M U L T I - T O O L',
                        style: TextStyle(
                          color:         AppColors.textSecondary,
                          fontSize:      11,
                          fontWeight:    FontWeight.w600,
                          letterSpacing: 5,
                        ),
                      )
                          .animate(delay: 320.ms)
                          .fadeIn(duration: 500.ms)
                          .slideY(
                              begin: 0.3,
                              end:   0,
                              duration: 500.ms,
                              curve: Curves.easeOutCubic),

                      const SizedBox(height: 68),

                      // ── Loading state ─────────────────────────────────────
                      if (!_showRetryButton) ...[
                        // Bouncing dots
                        AnimatedBuilder(
                          animation: _dotCtrl,
                          builder: (context, _) {
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildDot(_dot1.value),
                                const SizedBox(width: 10),
                                _buildDot(_dot2.value),
                                const SizedBox(width: 10),
                                _buildDot(_dot3.value),
                              ],
                            );
                          },
                        ).animate(delay: 400.ms).fadeIn(duration: 400.ms),

                        const SizedBox(height: 18),

                        // Status text
                        Text(
                          _status,
                          style: const TextStyle(
                            color:    AppColors.textSecondary,
                            fontSize: 13,
                            letterSpacing: 0.2,
                          ),
                        )
                            .animate(delay: 500.ms)
                            .fadeIn(duration: 400.ms)
                            .shimmer(
                              duration: 1800.ms,
                              delay:    900.ms,
                              color: AppColors.textSecondary
                                  .withOpacity(0.35),
                            ),
                      ] else ...[
                        // ── Error state ────────────────────────────────────
                        const Icon(Icons.wifi_off_rounded,
                                color: AppColors.error, size: 34)
                            .animate()
                            .fadeIn(duration: 400.ms)
                            .shake(delay: 200.ms, duration: 500.ms),

                        const SizedBox(height: 14),

                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 44),
                          child: Text(
                            _errorMessage ?? 'Connection failed.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color:  AppColors.textSecondary,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        ElevatedButton.icon(
                          onPressed: _manualRetry,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 32, vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.lg)),
                            textStyle: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold),
                          ),
                        )
                            .animate(delay: 200.ms)
                            .fadeIn(duration: 400.ms)
                            .slideY(
                                begin: 0.2,
                                end:   0,
                                duration: 400.ms),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // ── Version badge (bottom) ───────────────────────────────────────
            if (_appVersion.isNotEmpty)
              Positioned(
                bottom: 28,
                left:   0,
                right:  0,
                child: Text(
                  _appVersion,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color:    AppColors.textSecondary.withOpacity(0.5),
                    fontSize: 11,
                    letterSpacing: 1.0,
                  ),
                )
                    .animate(delay: 800.ms)
                    .fadeIn(duration: 500.ms),
              ),
          ],
        ),
      ),
    );
  }

  // ── Dot widget for loader ──────────────────────────────────────────────────
  Widget _buildDot(double offsetY) {
    return Transform.translate(
      offset: Offset(0, offsetY),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: AppColors.primaryGradient,
          ),
          boxShadow: AppShadows.glow(AppColors.primary,
              intensity: 0.5, blur: 8, spread: 0),
        ),
      ),
    );
  }
}
