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

  // ✅ Encrypted storage — replaces SharedPreferences
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
    // ✅ Read from encrypted storage
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

    // ✅ Write to encrypted storage
    await _storage.write(key: 'xissin_user_id', value: id);
    return id;
  }

  Future<void> _initApp() async {
    await Future.delayed(const Duration(milliseconds: 700));

    try {
      _setStatus('Getting device info...');
      final userId = await _getOrCreateUserId();

      _setStatus('Connecting to server...');
      await ApiService.registerUser(
        userId: userId,
        deviceInfo: Platform.isAndroid ? 'android' : 'ios',
      );

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
      _setStatus(e.userMessage);
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) _initApp();
    } catch (e) {
      _setStatus('Connection error. Retrying...');
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) _initApp();
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}