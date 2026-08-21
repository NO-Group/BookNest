import 'dart:ui';

import 'package:flutter/material.dart';

import 'theme_controller.dart';

/// N.O Group palette — the new BookNest scheme.
///
/// Phase 1 of the re-theme: these constants are the single source of truth for
/// the **deep blue** primary + **0.1% cyan** accent used on all NEW screens.
/// Phase 2 (next session) replaces the remaining hard-coded legacy hex values
/// across old screens with these + full glassmorphism.
class BookNestColors {
  // Brand blues
  static const Color deepBlue = Color(0xFF1E4FD6); // primary deep blue
  static const Color deepBlueBright = Color(0xFF3D6BFF); // dark-theme primary
  static const Color deepNavy = Color(0xFF0B1633); // dark background
  static const Color deepNavySurface = Color(0xFF111A30); // dark card/surface
  static const Color deepNavyElevated = Color(0xFF1A2747); // elevated surface

  // Accent: cyan used at ~0.1% for gradients / highlights only
  static const Color cyan = Color(0xFF00D4FF);
  static const Color amber = Color(0xFFFFC53D); // hot/trending accent

  // Light theme
  static const Color bgLight = Color(0xFFF4F6FB);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color borderLight = Color(0xFFDCE2F0);

  // Dark theme
  static const Color bgDark = Color(0xFF070B14);
  static const Color surfaceDark = Color(0xFF0E1524);
  static const Color borderDark = Color(0xFF1E2A45);

  // Text
  static const Color textLight = Color(0xFF0B1633);
  static const Color textMutedLight = Color(0xFF5A657F);
  static const Color textDark = Color(0xFFF2F5FB);
  static const Color textMutedDark = Color(0xFF8A94AD);

  // Success / danger
  static const Color success = Color(0xFF2FD07A);
  static const Color danger = Color(0xFFFF5C6C);

  // --- Legacy aliases (kept so old screens compile until Phase 2 removes
  //     their hard-coded hex values; they now point at the N.O palette) ---
  static const Color darkBackground = deepNavy;
  static const Color darkChatBackground = deepNavySurface;
  static const Color darkReceivedMessage = deepNavySurface;
  static const Color darkSentMessage = Color(0xFF16305F);
  static const Color darkBorder = borderDark;
  static const Color darkTextPrimary = textDark;
  static const Color darkTextSecondary = textMutedDark;
  static const Color yellow = amber;
  static const Color orange = Color(0xFFFF7A3D);
}

/// Theme-aware semantic colors for the N.O Group Black/White scheme.
///
/// Resolves from the global [themeController] + the platform brightness, so
/// any widget can use `NOC.bg` / `NOC.surface` / `NOC.accent` … without
/// needing a `BuildContext`, and the whole app re-renders correctly when the
/// user switches System / Light / Dark.
class NOC {
  static bool get _dark {
    switch (themeController.mode) {
      case AppThemeMode.dark:
        return true;
      case AppThemeMode.light:
        return false;
      case AppThemeMode.system:
        return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    }
  }

  // Surfaces
  static Color get bg => _dark ? BookNestColors.bgDark : BookNestColors.bgLight;
  static Color get surface =>
      _dark ? BookNestColors.surfaceDark : BookNestColors.surfaceLight;
  static Color get surfaceAlt =>
      _dark ? const Color(0xFF111A30) : const Color(0xFFEEF2FA);
  static Color get surfaceHigh =>
      _dark ? const Color(0xFF1A2747) : Colors.white;
  static Color get border =>
      _dark ? BookNestColors.borderDark : BookNestColors.borderLight;

  // Accents
  static Color get accent =>
      _dark ? BookNestColors.deepBlueBright : BookNestColors.deepBlue;
  static Color get accentSoft =>
      _dark ? const Color(0x333D6BFF) : const Color(0x1A1E4FD6);
  static Color get cyan => BookNestColors.cyan; // ~0.1% gradients/highlights
  static Color get hot => BookNestColors.amber;
  static Color get gold => BookNestColors.amber;
  static Color get danger => BookNestColors.danger;
  static Color get success => BookNestColors.success;

  // Text
  static Color get text =>
      _dark ? BookNestColors.textDark : BookNestColors.textLight;
  static Color get textMuted =>
      _dark ? BookNestColors.textMutedDark : BookNestColors.textMutedLight;
  static Color get textFaint =>
      _dark ? const Color(0xFF5A6580) : const Color(0xFF9AA3B8);
  static Color get onAccent => Colors.white;

  /// Elevated "glass" card decoration (surface + border + soft shadow).
  static BoxDecoration card({
    double radius = 16,
    double shadowBlur = 18,
    bool elevated = true,
  }) {
    return BoxDecoration(
      color: _dark
          ? Colors.white.withOpacity(0.05)
          : Colors.white.withOpacity(0.75),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border.withOpacity(0.7)),
      boxShadow: elevated
          ? [
              BoxShadow(
                color: Colors.black.withOpacity(_dark ? 0.35 : 0.08),
                blurRadius: shadowBlur,
                offset: const Offset(0, 8),
              ),
            ]
          : null,
    );
  }

  /// Frosted-glass wrapper (BackdropFilter) — use for the nav bar, FABs and
  /// floating panels.
  static Widget blur({
    required Widget child,
    double sigma = 14,
    BorderRadius radius = const BorderRadius.all(Radius.circular(24)),
  }) {
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: child,
      ),
    );
  }
}

/// Legacy glassmorphism helper — a frosted-glass container. Prefer the
/// theme-aware `NOC.card` / `NOC.blur` for new work; kept for compatibility.
class Glass {
  static BoxDecoration card({Color? tint, double radius = 20}) {
    return BoxDecoration(
      color: tint ?? Colors.white.withOpacity(0.06),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withOpacity(0.10)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.25),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  /// Frosted wrapper — applies the backdrop blur around [child].
  static Widget blur({
    required Widget child,
    double sigma = 14,
    BorderRadius radius = const BorderRadius.all(Radius.circular(20)),
  }) {
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: child,
      ),
    );
  }
}

class BookNestTheme {
  static ThemeData get darkTheme => _build(
        brightness: Brightness.dark,
        background: BookNestColors.bgDark,
        surface: BookNestColors.surfaceDark,
        border: BookNestColors.borderDark,
        primary: BookNestColors.deepBlueBright,
        onSurface: BookNestColors.textDark,
        muted: BookNestColors.textMutedDark,
      );

  static ThemeData get lightTheme => _build(
        brightness: Brightness.light,
        background: BookNestColors.bgLight,
        surface: BookNestColors.surfaceLight,
        border: BookNestColors.borderLight,
        primary: BookNestColors.deepBlue,
        onSurface: BookNestColors.textLight,
        muted: BookNestColors.textMutedLight,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color border,
    required Color primary,
    required Color onSurface,
    required Color muted,
  }) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primary,
        onPrimary: Colors.white,
        secondary: primary,
        onSecondary: Colors.white,
        error: BookNestColors.danger,
        onError: Colors.white,
        surface: surface,
        onSurface: onSurface,
        outline: border,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: onSurface,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: isDark ? BookNestColors.borderDark : primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? surface : BookNestColors.deepNavy,
        contentTextStyle: TextStyle(color: onSurface),
      ),
    );
  }
}
