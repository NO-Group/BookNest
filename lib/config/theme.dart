import 'package:flutter/material.dart';

import 'app_state.dart';

/// The one colour vocabulary used throughout BookNest.
/// Navy is the brand anchor; cyan is reserved for focus, progress and actions.
class BookNestColors {
  static const Color navy = Color(0xFF102A56);
  static const Color navyDeep = Color(0xFF071A3D);
  static const Color cyan = Color(0xFF00E5FF);
  static const Color cyanSoft = Color(0xFF8FF7FF);

  static const Color darkBackground = Color(0xFF03060D); // near-black, faint navy
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

  /// Bundled UI typeface (assets/fonts, SIL OFL). Scripts it does not cover
  /// (Arabic, CJK, emoji…) fall back to the platform font automatically.
  static const String fontFamily = 'PlusJakartaSans';

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final surface = dark ? BookNestColors.darkChatBackground : BookNestColors.lightSurface;
    final onSurface = dark ? BookNestColors.darkTextPrimary : BookNestColors.lightTextPrimary;
    final muted = dark ? BookNestColors.darkTextSecondary : BookNestColors.lightTextSecondary;
    final outline = dark ? BookNestColors.darkBorder : BookNestColors.lightBorder;
    // Primary action colour: navy on light backgrounds, cyan on dark ones
    // (navy on near-black has too little contrast).
    final action = dark ? BookNestColors.cyan : BookNestColors.navy;
    final onAction = dark ? BookNestColors.navyDeep : Colors.white;
    final accent = dark ? BookNestColors.cyan : const Color(0xFF0091A8);
    final scheme = ColorScheme.fromSeed(
      seedColor: BookNestColors.navy,
      brightness: brightness,
      primary: dark ? BookNestColors.cyan : BookNestColors.navy,
      onPrimary: onAction,
      secondary: BookNestColors.cyan,
      onSecondary: BookNestColors.navyDeep,
      surface: surface,
      onSurface: onSurface,
      onSurfaceVariant: muted,
      outline: outline,
      outlineVariant: outline.withValues(alpha: .6),
      surfaceContainerLowest: dark ? BookNestColors.darkBackground : Colors.white,
      surfaceContainerLow: dark ? const Color(0xFF0B1428) : const Color(0xFFF7FAFF),
      surfaceContainer: dark ? const Color(0xFF0E1830) : BookNestColors.lightSurface,
      surfaceContainerHigh: dark ? const Color(0xFF121E3A) : const Color(0xFFEDF3FD),
      surfaceContainerHighest: dark ? const Color(0xFF172544) : const Color(0xFFE5EDFA),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
    ).textTheme;
    TextStyle? t(TextStyle? s, {FontWeight? w, double? ls, double? h}) =>
        s?.copyWith(fontWeight: w, letterSpacing: ls, height: h, color: onSurface);
    final textTheme = base.copyWith(
      displayLarge: t(base.displayLarge, w: FontWeight.w800, ls: -1.2),
      displayMedium: t(base.displayMedium, w: FontWeight.w800, ls: -1),
      displaySmall: t(base.displaySmall, w: FontWeight.w800, ls: -.8),
      headlineLarge: t(base.headlineLarge, w: FontWeight.w800, ls: -.6),
      headlineMedium: t(base.headlineMedium, w: FontWeight.w800, ls: -.5),
      headlineSmall: t(base.headlineSmall, w: FontWeight.w700, ls: -.4),
      titleLarge: t(base.titleLarge, w: FontWeight.w700, ls: -.3),
      titleMedium: t(base.titleMedium, w: FontWeight.w700, ls: -.1),
      titleSmall: t(base.titleSmall, w: FontWeight.w600, ls: 0),
      bodyLarge: t(base.bodyLarge, h: 1.5, ls: 0),
      bodyMedium: t(base.bodyMedium, h: 1.45, ls: 0),
      bodySmall: base.bodySmall?.copyWith(height: 1.4, color: muted, letterSpacing: 0),
      labelLarge: t(base.labelLarge, w: FontWeight.w700, ls: .1),
      labelMedium: t(base.labelMedium, w: FontWeight.w600, ls: .2),
      labelSmall: base.labelSmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: .3, color: muted),
    );

    const pill = StadiumBorder();
    const buttonText = TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: .1);
    const buttonPadding = EdgeInsets.symmetric(horizontal: 22, vertical: 14);
    const buttonSize = Size(64, 50);
    final hairline = BorderSide(color: outline.withValues(alpha: dark ? .9 : 1));
    final radius16 = BorderRadius.circular(16);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
      colorScheme: scheme,
      textTheme: textTheme,
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: dark ? BookNestColors.darkBackground : BookNestColors.lightBackground,
      canvasColor: dark ? BookNestColors.darkBackground : BookNestColors.lightBackground,
      hintColor: muted,
      dividerColor: outline,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 21,
          fontWeight: FontWeight.w800,
          letterSpacing: -.4,
          color: onSurface,
        ),
        iconTheme: IconThemeData(color: onSurface, size: 24),
        actionsIconTheme: IconThemeData(color: onSurface, size: 24),
      ),
      iconTheme: IconThemeData(color: onSurface, size: 24),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: outline.withValues(alpha: dark ? .7 : .8)),
        ),
      ),
      dividerTheme: DividerThemeData(color: outline.withValues(alpha: .7), space: 1, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF0E1830) : BookNestColors.lightSurface,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        hintStyle: TextStyle(color: muted, fontWeight: FontWeight.w500),
        labelStyle: TextStyle(color: muted, fontWeight: FontWeight.w500),
        floatingLabelStyle: TextStyle(color: accent, fontWeight: FontWeight.w700),
        prefixIconColor: muted,
        suffixIconColor: muted,
        border: OutlineInputBorder(borderRadius: radius16, borderSide: BorderSide(color: outline)),
        enabledBorder: OutlineInputBorder(borderRadius: radius16, borderSide: BorderSide(color: outline.withValues(alpha: .7))),
        focusedBorder: OutlineInputBorder(borderRadius: radius16, borderSide: const BorderSide(color: BookNestColors.cyan, width: 1.6)),
        errorBorder: OutlineInputBorder(borderRadius: radius16, borderSide: BorderSide(color: scheme.error)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: radius16, borderSide: BorderSide(color: scheme.error, width: 1.6)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: action,
          foregroundColor: onAction,
          disabledBackgroundColor: outline.withValues(alpha: .5),
          elevation: 0,
          minimumSize: buttonSize,
          padding: buttonPadding,
          textStyle: buttonText,
          shape: pill,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: action,
          foregroundColor: onAction,
          minimumSize: buttonSize,
          padding: buttonPadding,
          textStyle: buttonText,
          shape: pill,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurface,
          minimumSize: buttonSize,
          padding: buttonPadding,
          textStyle: buttonText,
          shape: pill,
          side: hairline,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: buttonText.copyWith(fontSize: 14.5),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: pill,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: onSurface),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: BookNestColors.cyan,
        foregroundColor: BookNestColors.navyDeep,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 4,
        highlightElevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
        extendedTextStyle: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w700, fontSize: 15),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? const Color(0xFF172544) : BookNestColors.navyDeep,
        contentTextStyle: const TextStyle(
            fontFamily: fontFamily, color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14, height: 1.35),
        actionTextColor: BookNestColors.cyan,
        closeIconColor: Colors.white70,
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        // Responsive pop-ups: roomier on small phones (Flutter's default
        // 40 px side gutters squeezed content), never a stretched slab on
        // tablets / PC.
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 560),
        titleTextStyle: TextStyle(
            fontFamily: fontFamily, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.3, color: onSurface),
        contentTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 14.5, height: 1.45, color: muted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        modalBackgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        dragHandleColor: muted.withValues(alpha: .5),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        // Sheets stay phone-width and centred on big screens.
        constraints: const BoxConstraints(maxWidth: 640),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: .25),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: outline.withValues(alpha: .6))),
        textStyle: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w600, fontSize: 14.5, color: onSurface),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF172544) : BookNestColors.navyDeep,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: const TextStyle(fontFamily: fontFamily, color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        textColor: onSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        minVerticalPadding: 10,
        horizontalTitleGap: 14,
        shape: RoundedRectangleBorder(borderRadius: radius16),
        titleTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 15.5, fontWeight: FontWeight.w600, color: onSurface),
        subtitleTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 13, height: 1.35, color: muted),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? BookNestColors.navyDeep
            : (dark ? BookNestColors.darkTextSecondary : Colors.white)),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? BookNestColors.cyan
            : (dark ? const Color(0xFF172544) : const Color(0xFFCBD7EA))),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? BookNestColors.cyan : Colors.transparent),
        checkColor: const WidgetStatePropertyAll(BookNestColors.navyDeep),
        side: BorderSide(color: muted, width: 1.6),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? BookNestColors.cyan : muted),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: outline),
        backgroundColor: Colors.transparent,
        selectedColor: BookNestColors.cyan,
        secondarySelectedColor: BookNestColors.cyan,
        checkmarkColor: BookNestColors.navyDeep,
        labelStyle: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w600, fontSize: 13, color: onSurface),
        secondaryLabelStyle: const TextStyle(
            fontFamily: fontFamily, fontWeight: FontWeight.w700, fontSize: 13, color: BookNestColors.navyDeep),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          side: WidgetStatePropertyAll(BorderSide(color: outline)),
          textStyle: const WidgetStatePropertyAll(
              TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w700, fontSize: 13.5)),
          backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? BookNestColors.cyan : Colors.transparent),
          foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? BookNestColors.navyDeep : onSurface),
          iconColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? BookNestColors.navyDeep : muted),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: onSurface,
        unselectedLabelColor: muted,
        dividerColor: Colors.transparent,
        indicatorColor: BookNestColors.cyan,
        indicatorSize: TabBarIndicatorSize.label,
        indicator: const UnderlineTabIndicator(
          borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
          borderSide: BorderSide(color: BookNestColors.cyan, width: 3),
        ),
        labelStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w700, fontSize: 14.5),
        unselectedLabelStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w600, fontSize: 14.5),
        overlayColor: WidgetStatePropertyAll(BookNestColors.cyan.withValues(alpha: .08)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: BookNestColors.cyan.withValues(alpha: .18),
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w600, fontSize: 12, color: onSurface)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: BookNestColors.cyan,
        linearTrackColor: outline.withValues(alpha: .5),
        circularTrackColor: Colors.transparent,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: BookNestColors.cyan,
        thumbColor: BookNestColors.cyan,
        inactiveTrackColor: outline,
        overlayColor: BookNestColors.cyan.withValues(alpha: .12),
      ),
      badgeTheme: const BadgeThemeData(
        backgroundColor: BookNestColors.cyan,
        textColor: BookNestColors.navyDeep,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: BookNestColors.cyan,
        selectionColor: BookNestColors.cyan.withValues(alpha: .3),
        selectionHandleColor: BookNestColors.cyan,
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
