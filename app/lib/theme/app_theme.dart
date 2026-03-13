import 'package:flutter/material.dart';

// ── Static color tokens ─────────────────────────────────────────────────────

class AppColors {
  AppColors._(); // prevent instantiation

  // Dark palette
  static const Color background    = Color(0xFF0B1020);
  static const Color surface       = Color(0xFF12182B);
  static const Color primary       = Color(0xFF5B8CFF);
  static const Color secondary     = Color(0xFFA78BFA);
  static const Color accent        = Color(0xFF7EE7C1);
  static const Color textPrimary   = Color(0xFFF5F7FF);
  static const Color textSecondary = Color(0xFFAAB4D6);
  static const Color error         = Color(0xFFFF6B6B);
  static const Color border        = Color(0xFF1E2A45);

  // Glassmorphism helpers (non-const because withOpacity isn't const)
  static Color glassWhite     = Colors.white.withOpacity(0.07);
  static Color glassBorder    = Colors.white.withOpacity(0.12);
  static Color glassHighlight = Colors.white.withOpacity(0.15);

  // Gradients
  static const List<Color> primaryGradient = [primary, secondary];
  static const List<Color> accentGradient  = [accent, Color(0xFF4FD1C5)];
  static const List<Color> errorGradient   = [error, Color(0xFFFF8E8E)];
  static const List<Color> warningGradient = [Color(0xFFFFA726), Color(0xFFFF7043)];

  // Animated background gradients
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

// ── Per-theme color set ──────────────────────────────────────────────────────

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
    background:    AppColors.background,
    surface:       AppColors.surface,
    primary:       AppColors.primary,
    secondary:     AppColors.secondary,
    accent:        AppColors.accent,
    textPrimary:   AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    error:         AppColors.error,
    border:        AppColors.border,
  );

  static const XissinColors light = XissinColors(
    background:    Color(0xFFF0F4FF),
    surface:       Color(0xFFFFFFFF),
    primary:       Color(0xFF3D70FF),
    secondary:     Color(0xFF7B5FF5),
    accent:        Color(0xFF3ECF8E),
    textPrimary:   Color(0xFF111827),
    textSecondary: Color(0xFF5B6880),
    error:         Color(0xFFE53E3E),
    border:        Color(0xFFDDE3F0),
  );
}

// ── BuildContext extensions ──────────────────────────────────────────────────

extension XissinColorsExtension on BuildContext {
  /// Returns the correct color set for the current theme brightness.
  XissinColors get c {
    final brightness = Theme.of(this).brightness;
    return brightness == Brightness.dark ? XissinColors.dark : XissinColors.light;
  }

  // Alias kept for any existing usages
  XissinColors get themeColors => c;
}

// ── Theme definitions ────────────────────────────────────────────────────────

class AppTheme {
  AppTheme._();

  // ── Dark ────────────────────────────────────────────────────────────────

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          surface:   AppColors.surface,
          primary:   AppColors.primary,
          secondary: AppColors.secondary,
          error:     AppColors.error,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(color: AppColors.textPrimary,   fontWeight: FontWeight.bold),
          bodyLarge:    TextStyle(color: AppColors.textPrimary),
          bodyMedium:   TextStyle(color: AppColors.textSecondary),
        ),
        inputDecorationTheme: _inputDecoration(
          fill:    AppColors.surface,
          border:  AppColors.border,
          focused: AppColors.primary,
          hint:    AppColors.textSecondary,
        ),
        elevatedButtonTheme: _elevatedButton(AppColors.primary),
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
        dividerColor: AppColors.border,
        cardColor:    AppColors.surface,
      );

  // ── Light ───────────────────────────────────────────────────────────────

  static const _lightBg      = Color(0xFFF0F4FF);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightPrimary = Color(0xFF3D70FF);
  static const _lightSecond  = Color(0xFF7B5FF5);
  static const _lightText    = Color(0xFF111827);
  static const _lightSub     = Color(0xFF5B6880);
  static const _lightBorder  = Color(0xFFDDE3F0);
  static const _lightError   = Color(0xFFE53E3E);

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: _lightBg,
        colorScheme: const ColorScheme.light(
          surface:   _lightSurface,
          primary:   _lightPrimary,
          secondary: _lightSecond,
          error:     _lightError,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(color: _lightText,  fontWeight: FontWeight.bold),
          bodyLarge:    TextStyle(color: _lightText),
          bodyMedium:   TextStyle(color: _lightSub),
        ),
        inputDecorationTheme: _inputDecoration(
          fill:    _lightSurface,
          border:  _lightBorder,
          focused: _lightPrimary,
          hint:    _lightSub,
        ),
        elevatedButtonTheme: _elevatedButton(_lightPrimary),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: _lightText,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: IconThemeData(color: _lightText),
        ),
        dividerColor: _lightBorder,
        cardColor:    _lightSurface,
      );

  // ── Shared helpers ──────────────────────────────────────────────────────

  static InputDecorationTheme _inputDecoration({
    required Color fill,
    required Color border,
    required Color focused,
    required Color hint,
  }) =>
      InputDecorationTheme(
        filled: true,
        fillColor: fill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: focused, width: 1.5),
        ),
        hintStyle:  TextStyle(color: hint),
        labelStyle: TextStyle(color: hint),
      );

  static ElevatedButtonThemeData _elevatedButton(Color bg) =>
      ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold),
          elevation: 0,
        ),
      );

  // Back-compat alias (keep old code from breaking)
  static ThemeData get theme => darkTheme;
}

// ── Duration constants ───────────────────────────────────────────────────────

class AppDurations {
  AppDurations._();
  static const Duration fast   = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration slow   = Duration(milliseconds: 500);
  static const Duration splash = Duration(milliseconds: 1000);
  static const Duration stagger = Duration(milliseconds: 100);
}

// ── Shadow presets ───────────────────────────────────────────────────────────

class AppShadows {
  AppShadows._();

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
