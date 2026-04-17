import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF1877F2);
  static const Color accent = Color(0xFF42B72A);
  static const Color darkBg = Color(0xFF18191A);
  static const Color darkCard = Color(0xFF242526);
  static const Color darkSurface = Color(0xFF3A3B3C);
  static const Color textPrimary = Color(0xFFE4E6EB);
  static const Color textSecondary = Color(0xFFB0B3B8);

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
        scaffoldBackgroundColor: const Color(0xFFF0F2F5),
        primaryColor: primary,
        colorScheme: const ColorScheme.light(
          primary: primary,
          secondary: accent,
        ),
      );
}
