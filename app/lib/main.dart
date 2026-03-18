import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:provider/provider.dart';

import 'theme/app_theme.dart';
import 'services/theme_service.dart';
import 'services/crash_reporter.dart';
import 'services/ad_service.dart';
import 'screens/splash_screen.dart';

void main() {
  runZonedGuarded(
    () async {
      // ── 1. Binding (FIRST, inside the zone) ───────────────────────────────
      WidgetsFlutterBinding.ensureInitialized();

      // ── 2. Crash reporter ─────────────────────────────────────────────────
      CrashReporter.initialize();

      // ── 3. Theme ──────────────────────────────────────────────────────────
      final themeService = ThemeService();
      await themeService.init();

      // ── 4. AdMob ──────────────────────────────────────────────────────────
      await AdService.instance.init();

      // ── 5. Orientation lock ───────────────────────────────────────────────
      await SystemChrome.setPreferredOrientations(
          [DeviceOrientation.portraitUp]);

      // ── 6. Launch ─────────────────────────────────────────────────────────
      runApp(XissinApp(themeService: themeService));
    },
    (error, stack) {
      CrashReporter.reportCrash(
        error: error,
        stack: stack,
        type: 'ZONE ERROR',
      );
    },
  );
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
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.every((r) => r == ConnectivityResult.none);
      if (offline != _isOffline) setState(() => _isOffline = offline);
    });
  }

  @override
  void dispose() {
    _connectivitySub.cancel();
    super.dispose();
  }

  void _applySystemUI(bool isDark) {
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor:
            isDark ? AppColors.background : const Color(0xFFEEF2FF),
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeService>.value(value: widget.themeService),
        ChangeNotifierProvider<AdService>.value(value: AdService.instance),
      ],
      child: Consumer<ThemeService>(
        builder: (_, themeService, __) {
          _applySystemUI(themeService.isDark);
          return MaterialApp(
            title: 'Xissin',
            debugShowCheckedModeBanner: false,
            theme:     AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode:
                themeService.isDark ? ThemeMode.dark : ThemeMode.light,
            home: const SplashScreen(),
            builder: (context, child) {
              return Column(
                children: [
                  AnimatedContainer(
                    duration: AppDurations.normal,
                    curve: Curves.easeInOut,
                    height: _isOffline ? 40 : 0,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFFF3B3B), Color(0xFFFF6B6B)],
                      ),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: _isOffline
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.wifi_off_rounded,
                                  color: Colors.white, size: 15),
                              SizedBox(width: 8),
                              Text(
                                'No internet connection',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
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