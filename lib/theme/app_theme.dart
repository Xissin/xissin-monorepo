import 'package:flutter/material.dart';

class AppColors {
  static const background   = Color(0xFF0B1020);
  static const surface      = Color(0xFF12182B);
  static const primary      = Color(0xFF5B8CFF);
  static const secondary    = Color(0xFFA78BFA);
  static const accent       = Color(0xFF7EE7C1);
  static const textPrimary  = Color(0xFFF5F7FF);
  static const textSecondary= Color(0xFFAAB4D6);
  static const error        = Color(0xFFFF6B6B);
  static const border       = Color(0xFF1E2A45);
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
