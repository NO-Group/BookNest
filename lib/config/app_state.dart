import 'package:flutter/material.dart';

/// App-wide UI settings that can change at runtime (no packages needed).
/// The theme switcher in Settings writes here; main.dart listens.
class AppSettings {
  AppSettings._();

  /// ThemeMode.system | light | dark — controlled from the Settings screen.
  static final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  /// Reader typography (Reader settings sheet writes these).
  static final ValueNotifier<double> readerFontScale =
      ValueNotifier<double>(1.0);
  static final ValueNotifier<double> readerLineHeight =
      ValueNotifier<double>(1.7);
  static final ValueNotifier<bool> readerSerif = ValueNotifier<bool>(false);
}
