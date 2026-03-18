import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/update_service.dart';
import '../widgets/shimmer_skeleton.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  // ── Controllers ────────────────────────────────────────────────────────────
  late AnimationController _entranceCtrl;   // logo entrance
  late AnimationController _orbitCtrl;      // slow orbit ring
  late AnimationController _pulseCtrl;      // icon glow pulse
  late AnimationController _rotateCtrl;     // outer ring slow rotation
  late AnimationController _dotCtrl;        // loading dots

  // Entrance
  late Animation<double> _logoFade;
  late Animation<double> _logoScale;
  late Animation<double> _titleSlide;

  // Orbit ring scale pulse
  late Animation<double> _orbit1;
  late Animation<double> _orbit2;

  // Glow pulse
  late Animation<double> _glow;

  // Dot bounces
  late Animation<double> _dot1;
  late Animation<double> _dot2;
  late Animation<double> _dot3;

  // ── State ──────────────────────────────────────────────────────────────────
  String  _status          = 'Initializing...';
  int     _retryCount      = 0;
  static const int _maxAutoRetries = 3;
  bool    _showRetryButton = false;
  String? _errorMessage;
  String  _appVersion      = '';

  static const String _telegramUrl = 'https://t.me/Xissin_0';
  // _driveUrl removed — APK URL now comes dynamically from /api/status

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  @override
  void initState() {
    super.initState();

    // ── Entrance (logo fades + scales in) ────────────────────────────────────
    _entranceCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _logoFade = CurvedAnimation(parent: _entranceCtrl, curve: const Interval(0.0, 0.6, curve: Curves.easeOut));
    _logoScale = Tween<double>(begin: 0.5, end: 1.0).animate(
        CurvedAnimation(parent: _entranceCtrl, curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack)));
    _titleSlide = CurvedAnimation(parent: _entranceCtrl,
        curve: const Interval(0.4, 1.0, curve: Curves.easeOut));

    // ── Orbit rings scale-pulse (2.8s) ────────────────────────────────────────
    _orbitCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2800));
    _orbit1 = Tween<double>(begin: 0.90, end: 1.10).animate(
        CurvedAnimation(parent: _orbitCtrl, curve: Curves.easeInOut));
    _orbit2 = Tween<double>(begin: 0.95, end: 1.05).animate(
        CurvedAnimation(parent: _orbitCtrl, curve: Curves.easeInOut));

    // ── Glow pulse (1.6s) ────────────────────────────────────────────────────
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600));
    _glow = Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // ── Outer ring rotation (10s full) ───────────────────────────────────────
    _rotateCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 10));

    // ── Dot bounce (900ms) ───────────────────────────────────────────────────
    _dotCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _dot1 = Tween<double>(begin: 0, end: -10).animate(
        CurvedAnimation(parent: _dotCtrl,
            curve: const Interval(0.0, 0.4, curve: Curves.easeInOut)));
    _dot2 = Tween<double>(begin: 0, end: -10).animate(
        CurvedAnimation(parent: _dotCtrl,
            curve: const Interval(0.2, 0.6, curve: Curves.easeInOut)));
    _dot3 = Tween<double>(begin: 0, end: -10).animate(
        CurvedAnimation(parent: _dotCtrl,
            curve: const Interval(0.4, 0.8, curve: Curves.easeInOut)));

    _entranceCtrl.forward();
    _orbitCtrl.repeat(reverse: true);
    _pulseCtrl.repeat(reverse: true);
    _rotateCtrl.repeat();
    _dotCtrl.repeat(reverse: true);

    _loadVersionAndInit();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _orbitCtrl.dispose();
    _pulseCtrl.dispose();
    _rotateCtrl.dispose();
    _dotCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadVersionAndInit() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = 'v${pkg.version}');
    } catch (_) {}
    _initApp();
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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

  Future<Map<String, dynamic>> _collectDeviceInfo() async {
    final info    = DeviceInfoPlugin();
    final pkgInfo = await PackageInfo.fromPlatform();

    int? batteryLevel;
    String? batteryState;
    try {
      final battery = Battery();
      batteryLevel  = await battery.batteryLevel;
      final state   = await battery.batteryState;
      batteryState  = state.toString().split('.').last;
    } catch (_) {}

    String? networkType;
    try {
      final conn  = await Connectivity().checkConnectivity();
      networkType = conn.toString().split('.').last;
    } catch (_) {}

    String? screenResolution;
    String? screenDensity;
    try {
      final view       = WidgetsBinding.instance.platformDispatcher.views.first;
      final size       = view.physicalSize;
      final dpr        = view.devicePixelRatio;
      screenResolution = '${size.width.toInt()}x${size.height.toInt()}';
      screenDensity    = '${dpr.toStringAsFixed(1)}x';
    } catch (_) {}

    String? locale;
    String? timezone;
    try {
      locale   = Platform.localeName;
      timezone = DateTime.now().timeZoneName;
    } catch (_) {}

    try {
      if (Platform.isAndroid) {
        final a            = await info.androidInfo;
        final brandLower   = a.brand.toLowerCase();
        final modelLower   = a.model.toLowerCase();
        final productLower = a.product.toLowerCase();
        final hwLower      = a.hardware.toLowerCase();
        final isEmulator   = !a.isPhysicalDevice ||
            (brandLower == 'google' && modelLower.contains('sdk')) ||
            productLower.contains('sdk')      || productLower.contains('emulator') ||
            productLower.contains('vbox')     || hwLower == 'goldfish' ||
            hwLower == 'ranchu'               || modelLower.contains('emulator') ||
            modelLower == 'android sdk built for x86' ||
            brandLower.contains('genymotion') || productLower.contains('nox') ||
            productLower.contains('bluestacks')|| productLower.contains('ldmicro') ||
            productLower.contains('memu');

        return {
          'platform': 'android', 'brand': a.brand, 'model': a.model,
          'manufacturer': a.manufacturer, 'product': a.product,
          'device': a.device, 'board': a.board, 'hardware': a.hardware,
          'display': a.display, 'fingerprint': a.fingerprint,
          'bootloader': a.bootloader, 'host': a.host, 'type': a.type,
          'tags': a.tags, 'android_version': a.version.release,
          'sdk_int': a.version.sdkInt, 'security_patch': a.version.securityPatch ?? '',
          'base_os': a.version.baseOS ?? '', 'codename': a.version.codename,
          'incremental': a.version.incremental,
          'supported_abis': a.supportedAbis,
          'supported_32bit_abis': a.supported32BitAbis,
          'supported_64bit_abis': a.supported64BitAbis,
          'app_version': pkgInfo.version, 'app_build_number': pkgInfo.buildNumber,
          'package_name': pkgInfo.packageName,
          'is_physical_device': a.isPhysicalDevice, 'is_emulator': isEmulator,
          'screen_resolution': screenResolution ?? '',
          'screen_density': screenDensity ?? '',
          'battery_level': batteryLevel, 'battery_state': batteryState ?? '',
          'network_type': networkType ?? '', 'locale': locale ?? '',
          'timezone': timezone ?? '',
        };
      } else if (Platform.isIOS) {
        final i = await info.iosInfo;
        return {
          'platform': 'ios', 'model': i.model, 'name': i.name,
          'machine': i.utsname.machine, 'sysname': i.utsname.sysname,
          'system_name': i.systemName, 'system_version': i.systemVersion,
          'identifier_for_vendor': i.identifierForVendor ?? '',
          'app_version': pkgInfo.version, 'app_build_number': pkgInfo.buildNumber,
          'package_name': pkgInfo.packageName,
          'is_physical_device': i.isPhysicalDevice, 'is_emulator': !i.isPhysicalDevice,
          'screen_resolution': screenResolution ?? '',
          'screen_density': screenDensity ?? '',
          'battery_level': batteryLevel, 'battery_state': batteryState ?? '',
          'network_type': networkType ?? '', 'locale': locale ?? '',
          'timezone': timezone ?? '',
        };
      }
    } catch (_) {}

    return {
      'platform': Platform.operatingSystem, 'is_physical_device': true,
      'is_emulator': false, 'app_version': pkgInfo.version,
      'app_build_number': pkgInfo.buildNumber,
      'screen_resolution': screenResolution ?? '',
      'screen_density': screenDensity ?? '',
      'battery_level': batteryLevel, 'battery_state': batteryState ?? '',
      'network_type': networkType ?? '', 'locale': locale ?? '',
      'timezone': timezone ?? '',
    };
  }

  Future<void> _initApp() async {
    setState(() { _showRetryButton = false; _errorMessage = null; });
    await Future.delayed(const Duration(milliseconds: 900));

    try {
      _setStatus('Checking server...');
      try {
        final status = await ApiService.getStatus();
        if (status['maintenance'] == true) {
          _showMaintenanceDialog(
              status['maintenance_message'] as String? ??
              'Xissin is under maintenance. Please check back later.');
          return;
        }
        final packageInfo    = await PackageInfo.fromPlatform();
        final currentVersion = packageInfo.version;
        final minVersion     = status['min_app_version']    as String? ?? '1.0.0';
        final latestVersion  = status['latest_app_version'] as String? ?? '1.0.0';
        final apkUrl         = status['apk_download_url']   as String? ?? '';
        final apkSha256      = status['apk_sha256']         as String?;
        final apkNotes       = status['apk_version_notes']  as String?;

        if (_isVersionOutdated(currentVersion, minVersion)) {
          _showForceUpdateDialog(currentVersion, minVersion, apkUrl, apkSha256); return;
        }
        if (_isVersionOutdated(currentVersion, latestVersion)) {
          final ok = await _showOptionalUpdateDialog(
            currentVersion, latestVersion, apkUrl, apkSha256, apkNotes);
          if (!ok) return;
        }
      } catch (e) {
        _retryCount++;
        if (_retryCount < _maxAutoRetries) {
          _setStatus('Retrying... ($_retryCount/$_maxAutoRetries)');
          await Future.delayed(const Duration(seconds: 2));
          return _initApp();
        }
        if (!mounted) return;
        setState(() {
          _showRetryButton = true;
          _errorMessage    = 'Cannot reach the server.\nCheck your internet connection.';
        });
        return;
      }

      _setStatus('Setting up your profile...');
      final userId = await _getOrCreateUserId();
      ApiService.cacheUserId(userId);

      _setStatus('Loading...');
      try {
        final deviceInfo = await _collectDeviceInfo();
        await ApiService.registerUser(userId: userId, deviceDetails: deviceInfo);
      } catch (_) {}

      _setStatus('Welcome to Xissin!');
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 800),
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

  Future<void> _manualRetry() async {
    _retryCount = 0;
    await _initApp();
  }

  void _setStatus(String s) {
    if (mounted) setState(() => _status = s);
  }

  bool _isVersionOutdated(String current, String required) {
    try {
      final c = current.split('.').map(int.parse).toList();
      final r = required.split('.').map(int.parse).toList();
      for (int i = 0; i < 3; i++) {
        final cv = i < c.length ? c[i] : 0;
        final rv = i < r.length ? r[i] : 0;
        if (cv < rv) return true;
        if (cv > rv) return false;
      }
      return false;
    } catch (_) { return false; }
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────
  void _showMaintenanceDialog(String message) {
    showDialog(
      context: context, barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(children: [
          Icon(Icons.build_circle_outlined, color: AppColors.secondary, size: 22),
          SizedBox(width: 8),
          Text('Under Maintenance',
              style: TextStyle(color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
        content: Text(message,
            style: const TextStyle(color: AppColors.textSecondary, height: 1.5)),
        actions: [
          TextButton(onPressed: () => _openUrl(_telegramUrl),
              child: const Text('Telegram',
                  style: TextStyle(color: AppColors.secondary, fontSize: 12))),
        ],
      ),
    );
  }

  void _showForceUpdateDialog(
    String current, String required, String apkUrl, String? apkSha256) {
    showDialog(
      context: context, barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(children: [
          Icon(Icons.system_update_rounded, color: AppColors.error, size: 22),
          SizedBox(width: 8),
          Text('Update Required',
              style: TextStyle(color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
        content: Text(
          'Your version ($current) is outdated.\nPlease update to continue.',
          style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => _openUrl(_telegramUrl),
              child: const Text('Telegram',
                  style: TextStyle(color: AppColors.secondary, fontSize: 12))),
          TextButton(
            onPressed: () {
              if (apkUrl.isNotEmpty) {
                UpdateService.downloadAndInstall(
                  context:        context,
                  apkUrl:         apkUrl,
                  latestVersion:  required,
                  expectedSha256: apkSha256,
                );
              } else {
                _openUrl(_telegramUrl);
              }
            },
            child: const Text('Download',
                style: TextStyle(color: AppColors.primary,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<bool> _showOptionalUpdateDialog(
    String current, String latest,
    String apkUrl, String? apkSha256, String? notes,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(children: [
          Icon(Icons.new_releases_rounded, color: AppColors.primary, size: 22),
          SizedBox(width: 8),
          Text('Update Available',
              style: TextStyle(color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'v$latest is available. You have v$current.',
              style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
            ),
            if (notes != null && notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(notes,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12, height: 1.5)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Later',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context, false);
              if (apkUrl.isNotEmpty) {
                UpdateService.downloadAndInstall(
                  context:        context,
                  apkUrl:         apkUrl,
                  latestVersion:  latest,
                  expectedSha256: apkSha256,
                  versionNotes:   notes,
                );
              } else {
                _openUrl(_telegramUrl);
              }
            },
            child: const Text('Download & Install',
                style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return result ?? true;
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // ── Ambient background glow ───────────────────────────────────────
          Positioned(
            top: size.height * 0.15,
            left: size.width * 0.5 - 150,
            child: AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, __) => Container(
                width: 300, height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.07 * _glow.value),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Main content ──────────────────────────────────────────────────
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [

                  // ── Logo section ───────────────────────────────────────────
                  FadeTransition(
                    opacity: _logoFade,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: SizedBox(
                        width: 160, height: 160,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [

                            // Outer slow-rotating dashed ring
                            AnimatedBuilder(
                              animation: _rotateCtrl,
                              builder: (_, __) => Transform.rotate(
                                angle: _rotateCtrl.value * 2 * math.pi,
                                child: CustomPaint(
                                  size: const Size(150, 150),
                                  painter: _DashedRingPainter(
                                    color: AppColors.primary.withOpacity(0.20),
                                    strokeWidth: 1.5,
                                    dashCount: 20,
                                  ),
                                ),
                              ),
                            ),

                            // Orbit ring 1 (pulsing)
                            AnimatedBuilder(
                              animation: _orbitCtrl,
                              builder: (_, __) => Transform.scale(
                                scale: _orbit1.value,
                                child: Container(
                                  width: 120, height: 120,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.primary.withOpacity(0.18),
                                      width: 1,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Orbit ring 2 (pulsing, faster)
                            AnimatedBuilder(
                              animation: _orbitCtrl,
                              builder: (_, __) => Transform.scale(
                                scale: _orbit2.value,
                                child: Container(
                                  width: 96, height: 96,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.primary.withOpacity(0.30),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Glow halo behind icon
                            AnimatedBuilder(
                              animation: _pulseCtrl,
                              builder: (_, __) => Container(
                                width: 80, height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withOpacity(0.35 * _glow.value),
                                      blurRadius: 28,
                                      spreadRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // ── Real app icon ──────────────────────────────
                            Container(
                              width: 72, height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: AppColors.primaryGradient,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.45),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/icon/icon.png',
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.bolt_rounded,
                                    size: 36,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),

                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // ── Title ──────────────────────────────────────────────────
                  FadeTransition(
                    opacity: _titleSlide,
                    child: Column(
                      children: [
                        ShaderMask(
                          shaderCallback: (b) => const LinearGradient(
                            colors: AppColors.primaryGradient,
                          ).createShader(b),
                          child: const Text(
                            'XISSIN',
                            style: TextStyle(
                              color:         Colors.white,
                              fontSize:      44,
                              fontWeight:    FontWeight.w900,
                              letterSpacing: 14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'M U L T I - T O O L',
                          style: TextStyle(
                            color:         AppColors.textSecondary.withOpacity(0.8),
                            fontSize:      11,
                            fontWeight:    FontWeight.w600,
                            letterSpacing: 5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 72),

                  // ── Loading / Error state ──────────────────────────────────
                  if (!_showRetryButton) ...[
                    // Bouncing dots
                    AnimatedBuilder(
                      animation: _dotCtrl,
                      builder: (_, __) => Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildDot(_dot1.value, 0),
                          const SizedBox(width: 10),
                          _buildDot(_dot2.value, 1),
                          const SizedBox(width: 10),
                          _buildDot(_dot3.value, 2),
                        ],
                      ),
                    ).animate(delay: 600.ms).fadeIn(duration: 400.ms),

                    const SizedBox(height: 20),

                    // Status text with shimmer
                    Text(
                      _status,
                      style: TextStyle(
                        color:         AppColors.textSecondary.withOpacity(0.75),
                        fontSize:      13,
                        letterSpacing: 0.3,
                      ),
                    ).animate(delay: 700.ms)
                      .fadeIn(duration: 400.ms)
                      .shimmer(
                        duration: 2000.ms,
                        delay:    1200.ms,
                        color:    AppColors.primary.withOpacity(0.3),
                      ),
                  ] else ...[
                    // Error state
                    const Icon(Icons.wifi_off_rounded,
                            color: AppColors.error, size: 36)
                        .animate().fadeIn(duration: 400.ms)
                        .shake(delay: 200.ms, duration: 500.ms),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        _errorMessage ?? 'Connection failed.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary.withOpacity(0.8),
                          fontSize: 13, height: 1.55,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    ElevatedButton.icon(
                      onPressed: _manualRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 36, vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.lg)),
                        textStyle: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ).animate(delay: 200.ms)
                      .fadeIn(duration: 400.ms)
                      .slideY(begin: 0.2, end: 0, duration: 400.ms),
                  ],
                ],
              ),
            ),
          ),

          // ── Version badge ─────────────────────────────────────────────────
          if (_appVersion.isNotEmpty)
            Positioned(
              bottom: 28, left: 0, right: 0,
              child: Text(
                _appVersion,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color:         AppColors.textSecondary.withOpacity(0.4),
                  fontSize:      11,
                  letterSpacing: 1.2,
                ),
              ).animate(delay: 900.ms).fadeIn(duration: 600.ms),
            ),
        ],
      ),
    );
  }

  // ── Gradient dot ──────────────────────────────────────────────────────────
  Widget _buildDot(double offsetY, int index) {
    final colors = [AppColors.primary, AppColors.secondary, AppColors.primary];
    return Transform.translate(
      offset: Offset(0, offsetY),
      child: Container(
        width: 9, height: 9,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors[index % colors.length],
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.5),
              blurRadius: 8,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Dashed ring painter ───────────────────────────────────────────────────────
class _DashedRingPainter extends CustomPainter {
  final Color  color;
  final double strokeWidth;
  final int    dashCount;

  const _DashedRingPainter({
    required this.color,
    required this.strokeWidth,
    required this.dashCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color       = color
      ..strokeWidth = strokeWidth
      ..style       = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - strokeWidth;
    const gap    = 0.3; // radians gap between dashes

    final step = (2 * math.pi) / dashCount;
    for (int i = 0; i < dashCount; i++) {
      final start = i * step;
      final end   = start + step - gap;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start, end - start, false, paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter old) =>
      old.color != color || old.dashCount != dashCount;
}
