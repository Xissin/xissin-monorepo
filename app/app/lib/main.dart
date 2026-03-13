import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:provider/provider.dart';

import 'theme/app_theme.dart';
import 'services/theme_service.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load saved theme BEFORE running the app so there's no flash of wrong theme
  final themeService = ThemeService();
  await themeService.init();

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(XissinApp(themeService: themeService));
}

class XissinApp extends StatefulWidget {
  final ThemeService themeService;
  const XissinApp({super.key, required this.themeService});

  @override
  State<XissinApp> createState() => _XissinAppState();
}

class _XissinAppState extends State<XissinApp> {
  bool _isOffline = false;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySub;

  @override
  void initState() {
    super.initState();
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.every((r) => r == ConnectivityResult.none);
      if (offline != _isOffline) {
        setState(() => _isOffline = offline);
      }
    });
  }

  @override
  void dispose() {
    _connectivitySub.cancel();
    super.dispose();
  }

  /// Update the system UI bars to match the current theme.
  void _applySystemUI(bool isDark) {
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor:
            isDark ? const Color(0xFF0B1020) : const Color(0xFFF0F4FF),
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ChangeNotifierProvider makes ThemeService available to the whole tree
    return ChangeNotifierProvider<ThemeService>.value(
      value: widget.themeService,
      // Consumer rebuilds MaterialApp whenever isDark changes
      child: Consumer<ThemeService>(
        builder: (_, themeService, __) {
          // Keep system bars in sync with the active theme
          _applySystemUI(themeService.isDark);

          return MaterialApp(
            title: 'Xissin',
            debugShowCheckedModeBanner: false,

            // ── THE FIX: wire both themes + themeMode ───────────────────────
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeService.isDark ? ThemeMode.dark : ThemeMode.light,
            // ────────────────────────────────────────────────────────────────

            home: const SplashScreen(),
            builder: (context, child) {
              return Column(
                children: [
                  // Offline banner
                  AnimatedContainer(
                    duration: AppDurations.normal,
                    height: _isOffline ? 36 : 0,
                    color: const Color(0xFFFF6B6B),
                    child: _isOffline
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.wifi_off_rounded,
                                  color: Colors.white, size: 14),
                              SizedBox(width: 6),
                              Text(
                                'No internet connection',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                  Expanded(child: child!),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
