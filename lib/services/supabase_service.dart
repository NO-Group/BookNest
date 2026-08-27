import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  late final SupabaseClient client;

  Future<void> initialize() async {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
      // Only log auth/network debug output in debug builds — never in release.
      debug: kDebugMode,
    );
    client = Supabase.instance.client;
  }

  SupabaseClient get supabase => client;
  GoTrueClient get auth => client.auth;

  // Create profile after signup
  Future<void> createProfile({
    required String userId,
    required String username,
    String? displayName,
    String? phoneNumber,
  }) async {
    await client.from('profiles').insert({
      'id': userId,
      'username': username,
      'display_name': displayName ?? username,
      'phone_number': phoneNumber,
      'gems': 77, // Welcome bonus
    });
  }
}