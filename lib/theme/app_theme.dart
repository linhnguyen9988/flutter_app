import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF1877F2);
  static const Color accent = Color(0xFF42B72A);

  static const Color darkBg = Color(0xFF18191A);
  static const Color darkCard = Color(0xFF242526);
  static const Color darkSurface = Color(0xFF3A3B3C);
  static const Color textPrimary = Color(0xFFE4E6EB);
  static const Color textSecondary = Color(0xFFB0B3B8);

  static const Color lightBg = Color(0xFFF0F2F5);
  static const Color lightCard = Colors.white;
  static const Color lightSurface = Color(0xFFE4E6EB);
  static const Color lightTextPrimary = Color(0xFF050505);
  static const Color lightTextSecondary = Color(0xFF65676B);

  static Color bgColor(bool isDark) => isDark ? darkBg : lightBg;

  static Color cardColor(bool isDark) => isDark ? darkCard : Colors.white;

  static Color surfaceColor(bool isDark) => isDark ? darkSurface : lightSurface;

  static Color textColor(bool isDark) =>
      isDark ? textPrimary : lightTextPrimary;

  static Color textSubColor(bool isDark) =>
      isDark ? textSecondary : lightTextSecondary;

  static Color dividerColor(bool isDark) =>
      isDark ? const Color(0xFF3A3B3C) : const Color(0xFFCBCDD1);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBg,
      primaryColor: primary,
      dividerColor: darkSurface,
      colorScheme: ColorScheme.dark(
        primary: primary,
        secondary: accent,
        surface: darkCard,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: darkCard,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        hintStyle: TextStyle(color: textSecondary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    );
  }

  static ThemeData get lightTheme => ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: lightBg,
        primaryColor: primary,
        dividerColor: const Color(0xFFDDDFE3),
        colorScheme: const ColorScheme.light(
          primary: primary,
          secondary: accent,
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Color(0xFF050505),
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          iconTheme: IconThemeData(color: Color(0xFF050505)),
        ),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFE4E6EB),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          hintStyle: const TextStyle(color: Color(0xFF8A8D91)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      );

  static ThemeMode themeByTime() {
    final hour = DateTime.now().hour;
    return (hour >= 6 && hour < 18) ? ThemeMode.light : ThemeMode.dark;
  }
}

extension AppThemeContext on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get bgColor => AppTheme.bgColor(isDark);
  Color get cardColor => AppTheme.cardColor(isDark);
  Color get surfaceColor => AppTheme.surfaceColor(isDark);
  Color get textColor => AppTheme.textColor(isDark);
  Color get textSubColor => AppTheme.textSubColor(isDark);
}
