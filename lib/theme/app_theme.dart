import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF0EA5E9);
  static const primaryDark = Color(0xFF0369A1);
  static const accent = Color(0xFFF97316);
  static const success = Color(0xFF22C55E);
  static const error = Color(0xFFEF4444);

  static const bgDark = Color(0xFF17171F);
  static const surfaceDark = Color(0xFF2A2A2A);
  static const cardDark = Color(0xFF252525);
  static const textDark = Color(0xFFF5F5FA);
  static const textMuted = Color(0xFF9CA3AF);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.dark,
    primary: AppColors.primary,
    secondary: AppColors.accent,
    surface: AppColors.surfaceDark,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bgDark,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bgDark,
      elevation: 0,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.cardDark,
      elevation: 0,
      margin: EdgeInsets.all(8),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceDark,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
