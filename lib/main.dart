import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

class XissinApp extends StatelessWidget {
  const XissinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Xissin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const SplashScreen(),
    );
  }
}
