import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The reader's profile composition — their choice, right from Settings:
/// 'classic' (the centered card flow) or 'studio' (the hero-band look).
final ValueNotifier<String> profileLayout =
    ValueNotifier<String>('classic');

Future<void> loadProfileLayout() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    profileLayout.value = prefs.getString('bn_profile_layout') ?? 'classic';
  } catch (_) {
    profileLayout.value = 'classic';
  }
}

Future<void> setProfileLayout(String layout) async {
  profileLayout.value = layout == 'studio' ? 'studio' : 'classic';
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bn_profile_layout', profileLayout.value);
  } catch (_) {}
}
