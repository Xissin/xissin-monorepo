import 'package:flutter/material.dart';

// ── Static color tokens ──────────────────────────────────────────────────────

class AppColors {
  AppColors._();

  // Core dark palette
  static const Color background    = Color(0xFF060810);
  static const Color surface       = Color(0xFF0E1422);
  static const Color surfaceAlt    = Color(0xFF131928);
  static const Color primary       = Color(0xFF5B8CFF);
  static const Color secondary     = Color(0xFFA78BFA);
  static const Color accent        = Color(0xFF7EE7C1);
  static const Color textPrimary   = Color(0xFFF5F7FF);
  static const Color textSecondary = Color(0xFFAAB4D6);
  static const Color error         = Color(0xFFFF6B6B);
  static const Color border        = Color(0xFF1A2540);

  // Neon variants (for glow effects & badges)
  static const Color neonBlue   = Color(0xFF00BFFF);
  static const Color neonPurple = Color(0xFFBF5AF2);
  static const Color neonGreen  = Color(0xFF00FF7F);
  static const Color neonPink   = Color(0xFFFF2D78);
  static const Color neonOrange = Color(0xFFFF9500);
  static const Color gold       = Color(0xFFFFBF00);

  // Glass helpers (non-const — uses withOpacity)
  static Color glassWhite     = Colors.white.withOpacity(0.06);
  static Color glassBorder    = Colors.white.withOpacity(0.10);
  static Color glassHighlight = Colors.white.withOpacity(0.14);
  static Color glassDark      = Colors.black.withOpacity(0.30);

  // Gradients
  static const List<Color> primaryGradient = [primary, secondary];
  static const List<Color> accentGradient  = [accent, Color(0xFF4FD1C5)];
  static const List<Color> errorGradient   = [error, Color(0xFFFF8E8E)];
  static const List<Color> warningGradient = [Color(0xFFFFA726), Color(0xFFFF7043)];
  static const List<Color> goldGradient    = [Color(0xFFFFBF00), Color(0xFFFF8C00)];

  // Tool-specific card gradients
  static const List<Color> smsGradient    = [Color(0xFF5B8CFF), Color(0xFFA78BFA)];
  static const List<Color> nglGradient    = [Color(0xFFFF6EC7), Color(0xFFFF9A44)];
  static const List<Color> keyGradient    = [Color(0xFF00C9FF), Color(0xFF92FE9D)];
  static const List<Color> aboutGradient  = [Color(0xFFA78BFA), Color(0xFF7EE7C1)];
  static const List<Color> comingSoon     = [Color(0xFF2A3050), Color(0xFF1E2540)];

  // Animated background gradients
  static const List<Color> animatedGradient1 = [
    Color(0xFF10152A),
    Color(0xFF060810),
    Color(0xFF0C1124),
  ];
  static const List<Color> animatedGradient2 = [
    Color(0xFF0E1422),
    Color(0xFF12193A),
    Color(0xFF080D1C),
  ];
}

// ── Border radius tokens ─────────────────────────────────────────────────────

class AppRadius {
  AppRadius._();

  static const double xs   = 8.0;
  static const double sm   = 12.0;
  static const double md   = 16.0;
  static const double lg   = 20.0;
  static const double xl   = 24.0;
  static const double xxl  = 32.0;
  static const double full = 999.0;

  static BorderRadius get xsAll  => BorderRadius.circular(xs);
  static BorderRadius get smAll  => BorderRadius.circular(sm);
  static BorderRadius get mdAll  => BorderRadius.circular(md);
  static BorderRadius get lgAll  => BorderRadius.circular(lg);
  static BorderRadius get xlAll  => BorderRadius.circular(xl);
  static BorderRadius get xxlAll => BorderRadius.circular(xxl);
}

// ── Per-theme color set ──────────────────────────────────────────────────────

class XissinColors {
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color primary;
  final Color secondary;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final Color error;
  final Color border;
  final Color neonGreen;
  final Color gold;

  const XissinColors({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.error,
    required this.border,
    required this.neonGreen,
    required this.gold,
  });

  static const XissinColors dark = XissinColors(
    background:    AppColors.background,
    surface:       AppColors.surface,
    surfaceAlt:    AppColors.surfaceAlt,
    primary:       AppColors.primary,
    secondary:     AppColors.secondary,
    accent:        AppColors.accent,
    textPrimary:   AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    error:         AppColors.error,
    border:        AppColors.border,
    neonGreen:     AppColors.neonGreen,
    gold:          AppColors.gold,
  );

  static const XissinColors light = XissinColors(
    background:    Color(0xFFEEF2FF),
    surface:       Color(0xFFFFFFFF),
    surfaceAlt:    Color(0xFFF5F8FF),
    primary:       Color(0xFF3D70FF),
    secondary:     Color(0xFF7B5FF5),
    accent:        Color(0xFF3ECF8E),
    textPrimary:   Color(0xFF111827),
    textSecondary: Color(0xFF5B6880),
    error:         Color(0xFFE53E3E),
    border:        Color(0xFFDDE3F0),
    neonGreen:     Color(0xFF16A34A),
    gold:          Color(0xFFD97706),
  );
}

// ── BuildContext extensions ──────────────────────────────────────────────────

extension XissinColorsExtension on BuildContext {
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

  // ── Dark ────────────────────────────────────────────────────────────────────

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
          displayLarge:  TextStyle(color: AppColors.textPrimary,   fontWeight: FontWeight.bold),
          displayMedium: TextStyle(color: AppColors.textPrimary,   fontWeight: FontWeight.w700),
          titleLarge:    TextStyle(color: AppColors.textPrimary,   fontWeight: FontWeight.bold,   fontSize: 20),
          titleMedium:   TextStyle(color: AppColors.textPrimary,   fontWeight: FontWeight.w600,   fontSize: 16),
          bodyLarge:     TextStyle(color: AppColors.textPrimary,   fontSize: 16),
          bodyMedium:    TextStyle(color: AppColors.textSecondary, fontSize: 14),
          bodySmall:     TextStyle(color: AppColors.textSecondary, fontSize: 12),
          labelSmall:    TextStyle(color: AppColors.textSecondary, fontSize: 10, letterSpacing: 1.2),
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

  // ── Light ────────────────────────────────────────────────────────────────────

  static const _lightBg      = Color(0xFFEEF2FF);
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
          displayLarge:  TextStyle(color: _lightText, fontWeight: FontWeight.bold),
          displayMedium: TextStyle(color: _lightText, fontWeight: FontWeight.w700),
          titleLarge:    TextStyle(color: _lightText, fontWeight: FontWeight.bold, fontSize: 20),
          titleMedium:   TextStyle(color: _lightText, fontWeight: FontWeight.w600, fontSize: 16),
          bodyLarge:     TextStyle(color: _lightText, fontSize: 16),
          bodyMedium:    TextStyle(color: _lightSub,  fontSize: 14),
          bodySmall:     TextStyle(color: _lightSub,  fontSize: 12),
          labelSmall:    TextStyle(color: _lightSub,  fontSize: 10, letterSpacing: 1.2),
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

  // ── Shared helpers ────────────────────────────────────────────────────────────

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
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: focused, width: 1.5),
        ),
        hintStyle:      TextStyle(color: hint),
        labelStyle:     TextStyle(color: hint),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      );

  static ElevatedButtonThemeData _elevatedButton(Color bg) =>
      ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold),
          elevation: 0,
        ),
      );

  // Back-compat alias
  static ThemeData get theme => darkTheme;
}

// ── Duration constants ────────────────────────────────────────────────────────

class AppDurations {
  AppDurations._();
  static const Duration fast    = Duration(milliseconds: 150);
  static const Duration normal  = Duration(milliseconds: 300);
  static const Duration slow    = Duration(milliseconds: 500);
  static const Duration slower  = Duration(milliseconds: 700);
  static const Duration splash  = Duration(milliseconds: 1000);
  static const Duration stagger = Duration(milliseconds: 100);
}

// ── Shadow presets ────────────────────────────────────────────────────────────

class AppShadows {
  AppShadows._();

  static List<BoxShadow> get neumorphicLight => [
        BoxShadow(
          color: Colors.white.withOpacity(0.04),
          offset: const Offset(-4, -4),
          blurRadius: 8,
        ),
        BoxShadow(
          color: Colors.black.withOpacity(0.35),
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

  /// Single-layer glow shadow.
  static List<BoxShadow> glow(
    Color color, {
    double intensity = 0.35,
    double blur = 20,
    double spread = 2,
  }) =>
      [
        BoxShadow(
          color: color.withOpacity(intensity),
          blurRadius: blur,
          spreadRadius: spread,
        ),
      ];

  /// Double-layer glow for hero elements.
  static List<BoxShadow> doubleGlow(Color color) => [
        BoxShadow(
          color: color.withOpacity(0.40),
          blurRadius: 28,
          spreadRadius: 4,
        ),
        BoxShadow(
          color: color.withOpacity(0.15),
          blurRadius: 56,
          spreadRadius: 8,
        ),
      ];

  static List<BoxShadow> get card => [
        BoxShadow(
          color: Colors.black.withOpacity(0.30),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ];
}
