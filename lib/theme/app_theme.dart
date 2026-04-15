import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF1877F2);
  static const Color accent = Color(0xFF42B72A);
  static const Color darkBg = Color(0xFF18191A);
  static const Color darkCard = Color(0xFF242526);
  static const Color darkSurface = Color(0xFF3A3B3C);
  static const Color textPrimary = Color(0xFFE4E6EB);
  static const Color textSecondary = Color(0xFFB0B3B8);

  static const String fontFamily = 'FSMagistral';

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      fontFamily: fontFamily, // Áp dụng toàn app
      scaffoldBackgroundColor: darkBg,
      primaryColor: primary,
      dividerColor: darkSurface,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: accent,
        surface: darkCard,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkCard,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700, // Sẽ lấy file Bold.ttf
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      cardTheme: const CardThemeData(
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
        hintStyle: const TextStyle(
          fontFamily: fontFamily,
          color: textSecondary,
          fontWeight: FontWeight.w400, // Sẽ lấy Book.ttf
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      textTheme: const TextTheme(
        // Flutter tự map weight -> đúng file ttf bạn khai báo
        displayLarge: TextStyle(fontFamily: fontFamily),
        displayMedium: TextStyle(fontFamily: fontFamily),
        displaySmall: TextStyle(fontFamily: fontFamily),
        headlineLarge: TextStyle(fontFamily: fontFamily),
        headlineMedium: TextStyle(fontFamily: fontFamily),
        headlineSmall: TextStyle(fontFamily: fontFamily),
        titleLarge: TextStyle(fontFamily: fontFamily),
        titleMedium: TextStyle(fontFamily: fontFamily),
        titleSmall: TextStyle(fontFamily: fontFamily),
        bodyLarge: TextStyle(fontFamily: fontFamily, color: textPrimary),
        bodyMedium: TextStyle(fontFamily: fontFamily, color: textPrimary),
        bodySmall: TextStyle(fontFamily: fontFamily, color: textSecondary),
        labelLarge: TextStyle(fontFamily: fontFamily),
        labelMedium: TextStyle(fontFamily: fontFamily),
        labelSmall: TextStyle(fontFamily: fontFamily),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: const Color(0xFFF0F2F5),
      primaryColor: primary,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: accent,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: Colors.black87,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: Colors.black87),
      ),
    );
  }
}
