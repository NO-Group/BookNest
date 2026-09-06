import 'package:flutter/material.dart';

import 'app_state.dart';

/// The one colour vocabulary used throughout BookNest.
/// Navy is the brand anchor; cyan is reserved for focus, progress and actions.
class BookNestColors {
  static const Color navy = Color(0xFF102A56);
  static const Color navyDeep = Color(0xFF071A3D);
  static const Color cyan = Color(0xFF00E5FF);
  static const Color cyanSoft = Color(0xFF8FF7FF);

  static const Color darkBackground = Color(0xFF000000);
  static const Color darkChatBackground = Color(0xFF0A1224);
  static const Color darkReceivedMessage = Color(0xFF111E38);
  static const Color darkSentMessage = Color(0xFF102A56);
  static const Color darkBorder = Color(0xFF20355B);
  static const Color darkTextPrimary = Color(0xFFF7FAFF);
  static const Color darkTextSecondary = Color(0xFFAAB9D3);

  static const Color lightBackground = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFF4F8FF);
  static const Color lightBorder = Color(0xFFD7E2F4);
  static const Color lightTextPrimary = navyDeep;
  static const Color lightTextSecondary = Color(0xFF526785);
}

class BookNestTheme {
  static ThemeData get darkTheme => _theme(Brightness.dark);
  static ThemeData get lightTheme => _theme(Brightness.light);

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final surface = dark ? BookNestColors.darkChatBackground : BookNestColors.lightSurface;
    final onSurface = dark ? BookNestColors.darkTextPrimary : BookNestColors.lightTextPrimary;
    final outline = dark ? BookNestColors.darkBorder : BookNestColors.lightBorder;
    final scheme = ColorScheme.fromSeed(
      seedColor: BookNestColors.navy,
      brightness: brightness,
      primary: BookNestColors.navy,
      secondary: BookNestColors.cyan,
      surface: surface,
      onSurface: onSurface,
      outline: outline,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? BookNestColors.darkBackground : BookNestColors.lightBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      dividerTheme: DividerThemeData(color: outline, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: TextStyle(color: dark ? BookNestColors.darkTextSecondary : BookNestColors.lightTextSecondary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: outline)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: outline)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: BookNestColors.cyan, width: 1.5)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: BookNestColors.navy,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: BookNestFadeSlideBuilder(),
        TargetPlatform.iOS: BookNestFadeSlideBuilder(),
        TargetPlatform.macOS: BookNestFadeSlideBuilder(),
        TargetPlatform.linux: BookNestFadeSlideBuilder(),
        TargetPlatform.windows: BookNestFadeSlideBuilder(),
      }),
    );
  }
}


/// BookNest's signature page transition: fade with a gentle rise.
/// Honors the "Reduce motion" accessibility setting at navigation time.
class BookNestFadeSlideBuilder extends PageTransitionsBuilder {
  const BookNestFadeSlideBuilder();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context,
      Animation<double> animation, Animation<double> secondaryAnimation,
      Widget child) {
    final curved =
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    if (AppSettings.reduceMotion.value) {
      return FadeTransition(opacity: curved, child: child);
    }
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
                begin: const Offset(0, .035), end: Offset.zero)
            .animate(curved),
        child: child,
      ),
    );
  }
}
