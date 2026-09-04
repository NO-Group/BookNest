import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'dictionary_service.dart';
import 'supabase_service.dart';

/// Keeps the five home-screen widgets fed with fresh content. Everything
/// is best-effort: widgets always show their last known content and can
/// never crash the app.
class HomeWidgetsService {
  HomeWidgetsService._();

  static const List<String> _providers = [
    'WordOfDayWidgetProvider',
    'StreakWidgetProvider',
    'GemsWidgetProvider',
    'QuickActionsWidgetProvider',
    'SearchWidgetProvider',
  ];

  static Future<void> pushAll() async {
    // Word of the Day — offline-safe (bundled edition).
    try {
      final wotd = await DictionaryService.instance.wordOfTheDay();
      await HomeWidget.saveWidgetData<String>('widget_word', wotd.word);
      await HomeWidget.saveWidgetData<String>(
          'widget_word_def', wotd.definition);
    } catch (e) {
      if (kDebugMode) debugPrint('widget word push skipped: $e');
    }
    // Gems balance — only when signed in and reachable.
    try {
      final client = SupabaseService().client;
      final user = client.auth.currentUser;
      if (user != null) {
        final row = await client
            .from('profiles')
            .select('gems')
            .eq('id', user.id)
            .maybeSingle();
        final gems = (row?['gems'] ?? 0).toString();
        await HomeWidget.saveWidgetData<String>('widget_gems', gems);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('widget gems push skipped: $e');
    }
    // Refresh every widget surface.
    for (final provider in _providers) {
      try {
        await HomeWidget.updateWidget(name: provider);
      } catch (_) {}
    }
  }

  /// Streaks screen calls this whenever it learns a fresh count.
  static Future<void> pushStreak(int days) async {
    try {
      await HomeWidget.saveWidgetData<String>('widget_streak', '$days');
      await HomeWidget.updateWidget(name: 'StreakWidgetProvider');
    } catch (_) {}
  }
}
