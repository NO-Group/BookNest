import 'backend_api.dart';

/// The signed-in reader's profile preferences — country, gender and the
/// language ladder whose strongest language is the preferred one (used
/// by the keyboard translator and message translation). Cached for the
/// session; refreshed after the profile is saved.
class ReaderProfile {
  String? country;
  String? countryCode;
  String? gender;
  List<Map<String, String>> languages = const [];
  String? preferredLanguage;

  static final ReaderProfile _instance = ReaderProfile._();
  ReaderProfile._();

  static ReaderProfile get instance => _instance;

  static bool _loaded = false;

  static Future<void> ensureLoaded({bool force = false}) async {
    if (_loaded && !force) return;
    final res = await BackendApi.instance.fetchUserProfile();
    if (res is Map && res['profile'] is Map) {
      final p = res['profile'] as Map;
      _instance.country = p['country']?.toString();
      _instance.countryCode = p['countryCode']?.toString();
      _instance.gender = p['gender']?.toString();
      _instance.preferredLanguage = p['preferredLanguage']?.toString();
      if (p['languages'] is List) {
        _instance.languages = [
          for (final l in (p['languages'] as List))
            if (l is Map)
              {
                'code': l['code']?.toString() ?? '',
                'level': l['level']?.toString() ?? 'basic',
              },
        ];
      }
      _loaded = true;
    }
  }

  static void applySaved({
    String? country,
    String? countryCode,
    String? gender,
    List<Map<String, String>>? languages,
    String? preferredLanguage,
  }) {
    _instance.country = country ?? _instance.country;
    _instance.countryCode = countryCode ?? _instance.countryCode;
    _instance.gender = gender ?? _instance.gender;
    _instance.languages = languages ?? _instance.languages;
    _instance.preferredLanguage = preferredLanguage ?? _instance.preferredLanguage;
    _loaded = true;
  }
}
