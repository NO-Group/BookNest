/// Countries and languages for the reader profile, the keyboard
/// translator and message translation. Flags are standard Unicode
/// regional-indicator pairs (rendered by the platform font).
library;

class CountryChoice {
  final String name;
  final String code; // ISO 3166-1 alpha-2
  final String flag;
  const CountryChoice(this.name, this.code, this.flag);
}

const List<CountryChoice> bookNestCountries = [
  CountryChoice('Nigeria', 'NG', '🇳🇬'),
  CountryChoice('Ghana', 'GH', '🇬🇭'),
  CountryChoice('Kenya', 'KE', '🇰🇪'),
  CountryChoice('South Africa', 'ZA', '🇿🇦'),
  CountryChoice('Egypt', 'EG', '🇪🇬'),
  CountryChoice('Morocco', 'MA', '🇲🇦'),
  CountryChoice('Ethiopia', 'ET', '🇪🇹'),
  CountryChoice('Tanzania', 'TZ', '🇹🇿'),
  CountryChoice('Uganda', 'UG', '🇺🇬'),
  CountryChoice('Senegal', 'SN', '🇸🇳'),
  CountryChoice('Cameroon', 'CM', '🇨🇲'),
  CountryChoice('Ivory Coast', 'CI', '🇨🇮'),
  CountryChoice('United Kingdom', 'GB', '🇬🇧'),
  CountryChoice('United States', 'US', '🇺🇸'),
  CountryChoice('Canada', 'CA', '🇨🇦'),
  CountryChoice('Jamaica', 'JM', '🇯🇲'),
  CountryChoice('Brazil', 'BR', '🇧🇷'),
  CountryChoice('Mexico', 'MX', '🇲🇽'),
  CountryChoice('France', 'FR', '🇫🇷'),
  CountryChoice('Germany', 'DE', '🇩🇪'),
  CountryChoice('Spain', 'ES', '🇪🇸'),
  CountryChoice('Italy', 'IT', '🇮🇹'),
  CountryChoice('Netherlands', 'NL', '🇳🇱'),
  CountryChoice('Sweden', 'SE', '🇸🇪'),
  CountryChoice('Poland', 'PL', '🇵🇱'),
  CountryChoice('Turkey', 'TR', '🇹🇷'),
  CountryChoice('Saudi Arabia', 'SA', '🇸🇦'),
  CountryChoice('United Arab Emirates', 'AE', '🇦🇪'),
  CountryChoice('India', 'IN', '🇮🇳'),
  CountryChoice('Pakistan', 'PK', '🇵🇰'),
  CountryChoice('Bangladesh', 'BD', '🇧🇩'),
  CountryChoice('China', 'CN', '🇨🇳'),
  CountryChoice('Japan', 'JP', '🇯🇵'),
  CountryChoice('South Korea', 'KR', '🇰🇷'),
  CountryChoice('Indonesia', 'ID', '🇮🇩'),
  CountryChoice('Philippines', 'PH', '🇵🇭'),
  CountryChoice('Malaysia', 'MY', '🇲🇾'),
  CountryChoice('Australia', 'AU', '🇦🇺'),
  CountryChoice('New Zealand', 'NZ', '🇳🇿'),
  CountryChoice('Other', 'OT', '🌍'),
];

String? flagForCountry(String code) {
  for (final c in bookNestCountries) {
    if (c.code == code) return c.flag;
  }
  return null;
}

String? countryNameFor(String code) {
  for (final c in bookNestCountries) {
    if (c.code == code) return c.name;
  }
  return null;
}

class LanguageChoice {
  final String name;
  final String code; // BCP-47 primary tag — also the translator target
  const LanguageChoice(this.name, this.code);
}

const List<LanguageChoice> bookNestLanguages = [
  LanguageChoice('English', 'en'),
  LanguageChoice('Hausa', 'ha'),
  LanguageChoice('Yoruba', 'yo'),
  LanguageChoice('Igbo', 'ig'),
  LanguageChoice('Nigerian Pidgin', 'pcm'),
  LanguageChoice('French', 'fr'),
  LanguageChoice('Arabic', 'ar'),
  LanguageChoice('Swahili', 'sw'),
  LanguageChoice('Amharic', 'am'),
  LanguageChoice('Zulu', 'zu'),
  LanguageChoice('Spanish', 'es'),
  LanguageChoice('Portuguese', 'pt'),
  LanguageChoice('German', 'de'),
  LanguageChoice('Italian', 'it'),
  LanguageChoice('Dutch', 'nl'),
  LanguageChoice('Turkish', 'tr'),
  LanguageChoice('Russian', 'ru'),
  LanguageChoice('Hindi', 'hi'),
  LanguageChoice('Bengali', 'bn'),
  LanguageChoice('Urdu', 'ur'),
  LanguageChoice('Persian', 'fa'),
  LanguageChoice('Indonesian', 'id'),
  LanguageChoice('Malay', 'ms'),
  LanguageChoice('Chinese', 'zh'),
  LanguageChoice('Japanese', 'ja'),
  LanguageChoice('Korean', 'ko'),
  LanguageChoice('Vietnamese', 'vi'),
  LanguageChoice('Thai', 'th'),
];

String? languageNameFor(String code) {
  final c = code.split('-').first.toLowerCase();
  for (final l in bookNestLanguages) {
    if (l.code == c) return l.name;
  }
  return null;
}

class LanguageLevel {
  final String id;
  final String label;
  final int rank;
  const LanguageLevel(this.id, this.label, this.rank);
}

const List<LanguageLevel> bookNestLanguageLevels = [
  LanguageLevel('basic', 'Basic understanding', 0),
  LanguageLevel('intermediate', 'Intermediate', 1),
  LanguageLevel('fluent', 'Fluent', 2),
  LanguageLevel('native', 'Native', 3),
];

String languageLevelLabel(String id) {
  for (final l in bookNestLanguageLevels) {
    if (l.id == id) return l.label;
  }
  return id;
}

/// Translatable language codes only (the translator covers more than
/// the profile list, but the pickers stay consistent).
bool isKnownLanguageCode(String code) {
  final c = code.split('-').first.toLowerCase();
  for (final l in bookNestLanguages) {
    if (l.code == c) return true;
  }
  return false;
}
