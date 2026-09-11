import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../config/locales.dart';
import '../../../services/backend_api.dart';
import '../../../services/reader_profile.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// Reader profile setup — part of the authentication flow. Country,
/// gender, and the reader's languages with fluency levels; the
/// strongest language becomes the preferred one (used by the keyboard
/// translator and message translation). Everything is editable later in
/// Settings → Language & country.
/// ─────────────────────────────────────────────────────────────────────────────

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  CountryChoice? _country;
  String? _gender;
  int? _birthYear;
  List<Map<String, String>> _languages = [];
  LanguageChoice _pickLanguage = bookNestLanguages.first;
  LanguageLevel _pickLevel = bookNestLanguageLevels[2]; // fluent
  String? _preferredOverride; // defaults to the strongest language
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    await ReaderProfile.ensureLoaded();
    if (!mounted) return;
    final p = ReaderProfile.instance;
    CountryChoice? country;
    for (final c in bookNestCountries) {
      if (c.code == p.countryCode) country = c;
    }
    setState(() {
      _country = country;
      _gender = p.gender;
      _birthYear = p.birthYear;
      _languages = [
        for (final l in p.languages)
          if (l['code']!.isNotEmpty) Map<String, String>.from(l),
      ];
      _preferredOverride = p.preferredLanguage;
    });
  }

  String? get _computedPreferred {
    if (_preferredOverride != null) return _preferredOverride;
    const rank = {
      'native': 3,
      'fluent': 2,
      'intermediate': 1,
      'basic': 0,
    };
    Map<String, String>? best;
    for (final l in _languages) {
      if (best == null ||
          (rank[l['level']] ?? 0) > (rank[best['level']] ?? 0)) {
        best = l;
      }
    }
    return best?['code'];
  }

  bool get _canSave =>
      _country != null &&
        _gender != null &&
        _birthYear != null &&
        _languages.isNotEmpty &&
        !_saving;

  Future<void> _addLanguage() async {
    final code = _pickLanguage.code;
    if (_languages.any((l) => l['code'] == code)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${_pickLanguage.name} is already in your list — adjust its level there.')));
      return;
    }
    setState(() {
      _languages.add({'code': code, 'level': _pickLevel.id});
      _preferredOverride = null; // recompute from the strongest
    });
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final res = await BackendApi.instance.saveUserProfile(
      country: _country!.name,
      countryCode: _country!.code,
      gender: _gender,
      birthYear: _birthYear,
      languages: _languages,
      preferredLanguage: _computedPreferred,
    );
    if (!mounted) return;
    if (res == null) {
      setState(() {
        _saving = false;
        _error = 'Could not save right now — please try again.';
      });
      return;
    }
    ReaderProfile.applySaved(
      country: _country!.name,
      countryCode: _country!.code,
      gender: _gender,
      birthYear: _birthYear,
      languages: _languages,
      preferredLanguage: res['preferredLanguage']?.toString() ??
          _computedPreferred,
    );
    final preferred = ReaderProfile.instance.preferredLanguage ?? 'en';
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop<Map<String, String>>({'preferredLanguage': preferred});
    } else {
      context.go('/onboarding');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = dark ? Colors.white.withOpacity(.05) : Colors.white;
    final ink = dark ? Colors.white : BookNestColors.navyDeep;
    return Scaffold(
      backgroundColor: dark ? BookNestColors.navyDeep : BookNestColors.lightSurface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Your reader profile',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'This personalises BookNest — translations, your flag and badges. '
            'You can change any of it later in Settings.',
            style: TextStyle(
                fontSize: 13, height: 1.5, color: ink.withOpacity(.75)),
          ),
          const SizedBox(height: 18),

          // ── country ──
          _sectionLabel('Country', Icons.public_rounded, dark),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: BookNestColors.cyan.withOpacity(.3)),
            ),
            child: DropdownButton<CountryChoice>(
              value: _country,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              hint: const Text('Choose your country'),
              dropdownColor: dark ? BookNestColors.navy : Colors.white,
              icon: const Icon(Icons.expand_more_rounded,
                  color: BookNestColors.cyan),
              items: [
                for (final c in bookNestCountries)
                  DropdownMenuItem(
                    value: c,
                    child: Text('${c.flag}  ${c.name}',
                        style: TextStyle(color: ink, fontSize: 14.5)),
                  ),
              ],
              onChanged: (c) => setState(() => _country = c),
            ),
          ),
          const SizedBox(height: 18),

          // ── gender ──
          _sectionLabel('Gender', Icons.badge_rounded, dark),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final g in const [
                ('female', 'Female', Icons.female_rounded),
                ('male', 'Male', Icons.male_rounded),
                ('nonbinary', 'Non-binary', Icons.transgender_rounded),
                ('prefer_not_to_say', 'Prefer not to say', Icons.person_rounded),
              ])
                ChoiceChip(
                  label: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(g.$3,
                        size: 15,
                        color: _gender == g.$1
                            ? BookNestColors.navyDeep
                            : (dark ? Colors.white70 : BookNestColors.navyDeep)),
                    const SizedBox(width: 6),
                    Text(g.$2),
                  ]),
                  selected: _gender == g.$1,
                  onSelected: (_) => setState(() => _gender = g.$1),
                  selectedColor: BookNestColors.cyan,
                  backgroundColor: cardColor,
                  labelStyle: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _gender == g.$1
                          ? BookNestColors.navyDeep
                          : ink),
                  side: BorderSide(color: BookNestColors.cyan.withOpacity(.4)),
                ),
            ],
          ),
          const SizedBox(height: 18),

          // ── birth year (compulsory — powers the age chart) ──
          _sectionLabel('Birth year', Icons.cake_outlined, dark),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            value: _birthYear,
            dropdownColor: dark ? BookNestColors.navyDeep : Colors.white,
            style: TextStyle(fontSize: 14, color: dark ? Colors.white : BookNestColors.navyDeep),
            decoration: InputDecoration(
              hintText: 'Select your birth year',
              filled: true,
              fillColor: cardColor,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
            ),
            items: [
              for (var y = DateTime.now().year - 13;
                  y >= 1950;
                  y--)
                DropdownMenuItem(value: y, child: Text('$y')),
            ],
            onChanged: (v) => setState(() => _birthYear = v),
          ),
          const SizedBox(height: 18),

          // ── languages ──
          _sectionLabel('Languages', Icons.translate_rounded, dark),
          Text(
            'Add every language you read or speak, with how well. '
            'Your strongest becomes your preferred language.',
            style: TextStyle(fontSize: 12.5, height: 1.45, color: ink.withOpacity(.65)),
          ),
          const SizedBox(height: 10),
          for (final l in _languages)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: _computedPreferred == l['code']
                        ? BookNestColors.cyan
                        : BookNestColors.cyan.withOpacity(.25)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(languageNameFor(l['code']!) ?? l['code']!,
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, color: ink)),
                          if (_computedPreferred == l['code']) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: BookNestColors.cyan.withOpacity(.18),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('PREFERRED',
                                  style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: .5,
                                      color: dark
                                          ? BookNestColors.cyan
                                          : BookNestColors.navyDeep)),
                            ),
                          ],
                        ]),
                        Text(languageLevelLabel(l['level'] ?? 'basic'),
                            style: TextStyle(
                                fontSize: 12, color: ink.withOpacity(.6))),
                      ],
                    ),
                  ),
                  // level stepper
                  DropdownButton<String>(
                    value: l['level'],
                    underline: const SizedBox.shrink(),
                    isDense: true,
                    dropdownColor: dark ? BookNestColors.navy : Colors.white,
                    items: [
                      for (final lv in bookNestLanguageLevels)
                        DropdownMenuItem(
                            value: lv.id, child: Text(lv.label, style: TextStyle(fontSize: 12.5, color: ink))),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        l['level'] = v;
                        _preferredOverride = null;
                      });
                    },
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close_rounded,
                        size: 18, color: ink.withOpacity(.5)),
                    onPressed: () {
                      setState(() {
                        _languages.remove(l);
                        _preferredOverride = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: BookNestColors.cyan.withOpacity(.3)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButton<LanguageChoice>(
                        value: _pickLanguage,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        dropdownColor: dark ? BookNestColors.navy : Colors.white,
                        items: [
                          for (final l in bookNestLanguages)
                            DropdownMenuItem(
                                value: l,
                                child: Text(l.name,
                                    style:
                                        TextStyle(color: ink, fontSize: 14))),
                        ],
                        onChanged: (l) => setState(() => _pickLanguage = l!),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButton<LanguageLevel>(
                        value: _pickLevel,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        dropdownColor: dark ? BookNestColors.navy : Colors.white,
                        items: [
                          for (final lv in bookNestLanguageLevels)
                            DropdownMenuItem(
                                value: lv,
                                child: Text(lv.label,
                                    style:
                                        TextStyle(color: ink, fontSize: 13))),
                        ],
                        onChanged: (lv) => setState(() => _pickLevel = lv!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: _addLanguage,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add language'),
                    style: TextButton.styleFrom(
                        foregroundColor: BookNestColors.cyan,
                        textStyle: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
          if (_languages.length >= 2) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text('Preferred language',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: ink.withOpacity(.75))),
                const Spacer(),
                DropdownButton<String>(
                  value: _computedPreferred,
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  dropdownColor: dark ? BookNestColors.navy : Colors.white,
                  items: [
                    for (final l in _languages)
                      DropdownMenuItem(
                          value: l['code'],
                          child: Text(languageNameFor(l['code']!) ?? l['code']!,
                              style: TextStyle(color: ink, fontSize: 13))),
                  ],
                  onChanged: (v) => setState(() => _preferredOverride = v),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          if (_error != null) ...[
            Text(_error!,
                style: const TextStyle(color: Color(0xFFFF8A8A), fontSize: 13)),
            const SizedBox(height: 10),
          ],
          SizedBox(
            height: 52,
            child: TextButton(
              onPressed: _canSave ? _save : null,
              style: TextButton.styleFrom(
                backgroundColor:
                    _canSave ? BookNestColors.cyan : BookNestColors.cyan.withOpacity(.3),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: BookNestColors.navyDeep))
                  : const Text('Save & continue',
                      style: TextStyle(
                          color: BookNestColors.navyDeep,
                          fontWeight: FontWeight.w800,
                          fontSize: 15.5)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, IconData icon, bool dark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: BookNestColors.cyan),
          const SizedBox(width: 8),
          Text(text.toUpperCase(),
              style: TextStyle(
                  fontSize: 11.5,
                  letterSpacing: .9,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).hintColor)),
        ],
      ),
    );
  }
}
