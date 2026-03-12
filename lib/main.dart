import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Force portrait only
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Status bar — transparent, white icons
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0B1020),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const XissinApp());
}

class XissinApp extends StatefulWidget {
  const XissinApp({super.key});

  @override
  State<XissinApp> createState() => _XissinAppState();
}

class _XissinAppState extends State<XissinApp> {
  bool _isOffline = false;
  late StreamSubscription<List<ConnectivityResult>> _sub;

  @override
  void initState() {
    super.initState();

    // ✅ Bug 14 — listen for connectivity changes
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.every((r) => r == ConnectivityResult.none);
      if (offline != _isOffline) {
        setState(() => _isOffline = offline);
      }
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Xissin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const SplashScreen(),
      builder: (context, child) {
        return Column(
          children: [
            // ✅ Bug 14 — offline banner shown on top of every screen
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
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
  }
}
