import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Real local notifications: a daily Word of the Day nudge and an evening
/// streak reminder. Fully on-device — nothing external is involved, and
/// everything keeps working offline.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const String _keyDailyWord = 'notify_daily_word';
  static const String _keyStreak = 'notify_streak';

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_notification'),
    ));
    _ready = true;
  }

  Future<bool> dailyWordEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDailyWord) ?? false;
  }

  Future<bool> streakReminderEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyStreak) ?? false;
  }

  Future<void> setDailyWord(bool on) async {
    await init();
    if (on && !await _ensurePermission()) return;
    if (on) {
      await _scheduleDaily(
        id: 1,
        channelId: 'wordnest_daily',
        channelName: 'Word of the day',
        title: "Today's word is waiting 📖",
        body: 'Open Word Nest and give it a home.',
        hour: 9,
        minute: 0,
      );
    } else {
      await _plugin.cancel(1);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDailyWord, on);
  }

  Future<void> setStreakReminder(bool on) async {
    await init();
    if (on && !await _ensurePermission()) return;
    if (on) {
      await _scheduleDaily(
        id: 2,
        channelId: 'booknest_streaks',
        channelName: 'Streak reminders',
        title: 'Your streak is waiting 🔥',
        body: 'A few pages tonight keeps the flame alive.',
        hour: 20,
        minute: 0,
      );
    } else {
      await _plugin.cancel(2);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyStreak, on);
  }

  Future<bool> _ensurePermission() async {
    final impl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await impl?.requestNotificationsPermission();
    return granted ?? false;
  }

  tz.TZDateTime _nextAt(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, hour, minute);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    return next;
  }

  Future<void> _scheduleDaily({
    required int id,
    required String channelId,
    required String channelName,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      _nextAt(hour, minute),
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: 'BookNest reminders',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
          color: const Color(0xFF00E5FF),
          colorized: true,
        ),
      ),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}
