import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide UI settings that can change at runtime.
/// Every preference persists to SharedPreferences and restores at launch.
class AppSettings {
  AppSettings._();

  static SharedPreferences? _prefs;

  /// Call once from main() before runApp.
  static Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;
    void seedBool(ValueNotifier<bool> n, String key, {bool invert = false}) {
      if (p.containsKey(key)) n.value = p.getBool(key)! ^ invert;
    }
    void seedDouble(ValueNotifier<double> n, String key) {
      final v = p.getDouble(key);
      if (v != null) n.value = v;
    }
    final modeIndex = p.getInt('theme.mode');
    if (modeIndex != null && modeIndex >= 0 && modeIndex < ThemeMode.values.length) {
      themeMode.value = ThemeMode.values[modeIndex];
    }
    seedBool(reduceMotion, 'motion.reduced');
    seedBool(dataSaver, 'data.saver');
    seedBool(readerSerif, 'reader.serif');
    seedDouble(readerFontScale, 'reader.fontScale');
    seedDouble(readerLineHeight, 'reader.lineHeight');
    seedBool(notifyLikes, 'notify.likes');
    seedBool(notifyComments, 'notify.comments');
    seedBool(notifyFollows, 'notify.follows');
    seedBool(notifyMessages, 'notify.messages');
    seedBool(notifyEvents, 'notify.events');
    for (final n in _all) {
      n.addListener(() => _persist(n));
    }
  }

  static List<ValueNotifier<Object?>> get _all => [
        themeMode, reduceMotion, dataSaver, readerSerif, readerFontScale,
        readerLineHeight, notifyLikes, notifyComments, notifyFollows,
        notifyMessages, notifyEvents,
      ];

  static void _persist(ValueNotifier<Object?> n) {
    final p = _prefs;
    if (p == null) return;
    if (identical(n, themeMode)) {
      p.setInt('theme.mode', themeMode.value.index);
    } else if (identical(n, reduceMotion)) {
      p.setBool('motion.reduced', reduceMotion.value);
    } else if (identical(n, dataSaver)) {
      p.setBool('data.saver', dataSaver.value);
    } else if (identical(n, readerSerif)) {
      p.setBool('reader.serif', readerSerif.value);
    } else if (identical(n, readerFontScale)) {
      p.setDouble('reader.fontScale', readerFontScale.value);
    } else if (identical(n, readerLineHeight)) {
      p.setDouble('reader.lineHeight', readerLineHeight.value);
    } else if (identical(n, notifyLikes)) {
      p.setBool('notify.likes', notifyLikes.value);
    } else if (identical(n, notifyComments)) {
      p.setBool('notify.comments', notifyComments.value);
    } else if (identical(n, notifyFollows)) {
      p.setBool('notify.follows', notifyFollows.value);
    } else if (identical(n, notifyMessages)) {
      p.setBool('notify.messages', notifyMessages.value);
    } else if (identical(n, notifyEvents)) {
      p.setBool('notify.events', notifyEvents.value);
    }
  }
  /// ThemeMode.system | light | dark — controlled from the Settings screen.
  static final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  /// Accessibility: disables entrance/parallax animations app-wide.
  static final ValueNotifier<bool> reduceMotion = ValueNotifier<bool>(false);

  /// Loads lower-resolution images over slow connections.
  static final ValueNotifier<bool> dataSaver = ValueNotifier<bool>(false);

  /// Reader typography (Reader settings sheet + Settings screen write these).
  static final ValueNotifier<double> readerFontScale =
      ValueNotifier<double>(1.0);
  static final ValueNotifier<double> readerLineHeight =
      ValueNotifier<double>(1.7);
  static final ValueNotifier<bool> readerSerif = ValueNotifier<bool>(false);

  /// Notification channel preferences (the bell screen mutes unchecked ones).
  static final ValueNotifier<bool> notifyLikes = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> notifyComments = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> notifyFollows = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> notifyMessages = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> notifyEvents = ValueNotifier<bool>(true);

  /// Whether a notification of [type] should be shown, per user preferences.
  static bool allowsNotification(String type) {
    switch (type) {
      case 'like':
        return notifyLikes.value;
      case 'comment':
        return notifyComments.value;
      case 'follow':
        return notifyFollows.value;
      case 'message':
      case 'chat':
        return notifyMessages.value;
      case 'event':
        return notifyEvents.value;
      default:
        return true;
    }
  }
}
