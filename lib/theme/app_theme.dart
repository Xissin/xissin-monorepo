import 'package:flutter/material.dart';

class AppColors {
  // Base colors
  static const background   = Color(0xFF0B1020);
  static const surface      = Color(0xFF12182B);
  static const primary      = Color(0xFF5B8CFF);
  static const secondary    = Color(0xFFA78BFA);
  static const accent       = Color(0xFF7EE7C1);
  static const textPrimary  = Color(0xFFF5F7FF);
  static const textSecondary= Color(0xFFAAB4D6);
  static const error        = Color(0xFFFF6B6B);
  static const border       = Color(0xFF1E2A45);
  
  // Glassmorphism overlay colors
  static Color glassWhite = Colors.white.withOpacity(0.07);
  static Color glassBorder = Colors.white.withOpacity(0.12);
  static Color glassHighlight = Colors.white.withOpacity(0.15);
  
  // Gradient definitions
  static const primaryGradient = [primary, secondary];
  static const accentGradient = [accent, Color(0xFF4FD1C5)];
  static const errorGradient = [error, Color(0xFFFF8E8E)];
  static const warningGradient = [Color(0xFFFFA726), Color(0xFFFF7043)];
  
  // Animated gradient backgrounds
  static const List<Color> animatedGradient1 = [
    Color(0xFF1A1F3A),
    Color(0xFF0B1020),
    Color(0xFF151A2E),
  ];
  
  static const List<Color> animatedGradient2 = [
    Color(0xFF12182B),
    Color(0xFF1A2240),
    Color(0xFF0F1528),
  ];
}

class XissinColors {
  final Color background;
  final Color surface;
  final Color primary;
  final Color secondary;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final Color error;
  final Color border;

  const XissinColors({
    required this.background,
    required this.surface,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.error,
    required this.border,
  });

  static const XissinColors dark = XissinColors(
    background: AppColors.background,
    surface: AppColors.surface,
    primary: AppColors.primary,
    secondary: AppColors.secondary,
    accent: AppColors.accent,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    error: AppColors.error,
    border: AppColors.border,
  );

  static const XissinColors light = XissinColors(
    background: Color(0xFFF5F7FF),
    surface: Colors.white,
    primary: Color(0xFF4A7CFF),
    secondary: Color(0xFF8B6FFF),
    accent: Color(0xFF3ECF8E),
    textPrimary: Color(0xFF1A1F3A),
    textSecondary: Color(0xFF6B7590),
    error: Color(0xFFFF5B5B),
    border: Color(0xFFE2E8F0),
  );
}

extension AppColorsExtension on BuildContext {
  XissinColors get themeColors {
    final brightness = Theme.of(this).brightness;
    return brightness == Brightness.dark ? XissinColors.dark : XissinColors.light;
  }
  
  AppColors get appColors => AppColors();
  
  // Backwards compatibility - use themeColors instead
  XissinColors get c => themeColors;
}

class AppTheme {
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      surface: AppColors.surface,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      error: AppColors.error,
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
      bodyLarge:    TextStyle(color: AppColors.textPrimary),
      bodyMedium:   TextStyle(color: AppColors.textSecondary),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.border, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      hintStyle:  const TextStyle(color: AppColors.textSecondary),
      labelStyle: const TextStyle(color: AppColors.textSecondary),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        elevation: 0,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      iconTheme: IconThemeData(color: AppColors.textPrimary),
    ),
  );
}

// Animation duration constants
class AppDurations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);
  static const Duration splash = Duration(milliseconds: 1000);
  static const Duration stagger = Duration(milliseconds: 100);
}

// Neumorphism shadow presets (light source top-left)
class AppShadows {
  static List<BoxShadow> get neumorphicLight => [
    BoxShadow(
      color: Colors.white.withOpacity(0.05),
      offset: const Offset(-4, -4),
      blurRadius: 8,
    ),
    BoxShadow(
      color: Colors.black.withOpacity(0.25),
      offset: const Offset(4, 4),
      blurRadius: 12,
    ),
  ];

  static List<BoxShadow> get neumorphicPressed => [
    BoxShadow(
      color: Colors.black.withOpacity(0.3),
      offset: const Offset(2, 2),
      blurRadius: 4,
    ),
  ];

  static List<BoxShadow> glow(Color color, {double intensity = 0.3}) => [
    BoxShadow(
      color: color.withOpacity(intensity),
      blurRadius: 20,
      spreadRadius: 2,
    ),
  ];
}
