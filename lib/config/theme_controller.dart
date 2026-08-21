import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide theme controller instance. Load it once before `runApp`
/// (`await themeController.load()`) and pass `themeController.mode` to the
/// `MaterialApp.themeMode`.
final ThemeController themeController = ThemeController();

/// Theme preference for the N.O Group Black/White scheme.
///
/// Follows the system by default; the user can pin Light or Dark from the
/// Profile screen. Persisted locally with `shared_preferences`.
enum AppThemeMode {
  system,
  light,
  dark;

  String get label {
    switch (this) {
      case AppThemeMode.system:
        return 'System';
      case AppThemeMode.light:
        return 'Light';
      case AppThemeMode.dark:
        return 'Dark';
    }
  }
}

class ThemeController extends ChangeNotifier {
  static const String _prefKey = 'booknest_theme_mode';

  AppThemeMode _mode = AppThemeMode.system;
  AppThemeMode get mode => _mode;

  /// Loads the persisted preference (call once before `runApp`).
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefKey);
      if (stored != null) {
        _mode = AppThemeMode.values.firstWhere(
          (m) => m.name == stored,
          orElse: () => AppThemeMode.system,
        );
        notifyListeners();
      }
    } catch (_) {
      // Non-fatal: fall back to system.
    }
  }

  Future<void> setMode(AppThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, mode.name);
    } catch (_) {
      // Persistence is best-effort.
    }
  }
}
