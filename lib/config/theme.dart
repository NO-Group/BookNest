import 'package:flutter/material.dart';

class BookNestColors {
  static const Color darkBackground = Color(0xFF0A0A0A);
  static const Color darkChatBackground = Color(0xFF0F0F0F);
  static const Color darkReceivedMessage = Color(0xFF1F1F1F);
  static const Color darkSentMessage = Color(0xFF2A2A2A);
  static const Color darkBorder = Color(0xFF222222);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFF888888);
  static const Color cyan = Color(0xFF00D4FF);
  static const Color cyanDark = Color(0xFF00A8CC);
  static const Color yellow = Color(0xFFFFD000);
  static const Color orange = Color(0xFFFF6A00);
}

class BookNestTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: BookNestColors.darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: BookNestColors.cyan,
        secondary: BookNestColors.cyanDark,
        surface: BookNestColors.darkChatBackground,
        onPrimary: BookNestColors.darkTextPrimary,
        onSecondary: BookNestColors.darkTextPrimary,
        onSurface: BookNestColors.darkTextPrimary,
        outline: BookNestColors.darkBorder,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: BookNestColors.darkBackground,
        foregroundColor: BookNestColors.darkTextPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: BookNestColors.cyan,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}