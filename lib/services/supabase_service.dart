import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  static const String _supabaseUrl = 'https://evxslesfixnkfgspbsvc.supabase.co';
  static const String _supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV2eHNsZXNmaXhua2Znc3Bic3ZjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY2MDg0MjUsImV4cCI6MjA5MjE4NDQyNX0.MweBzgqEENRnjYGvn9Hb9p85AmF9vwMvMNmjzc6pw2Y';

  late final SupabaseClient client;

  Future<void> initialize() async {
    await Supabase.initialize(
      url: _supabaseUrl,
      anonKey: _supabaseAnonKey,
      debug: true,
    );
    client = Supabase.instance.client;
  }

  SupabaseClient get supabase => client;
  GoTrueClient get auth => client.auth;

  /// Updates the authenticated user's public profile through a SECURITY
  /// DEFINER function. Private fields and wallet values never pass through
  /// the public `profiles` table from the client.
  Future<void> createProfile({
    required String userId,
    required String username,
    String? displayName,
    String? phoneNumber,
  }) async {
    if (auth.currentUser?.id != userId) {
      throw StateError('Cannot update another user profile.');
    }
    await client.rpc('update_my_profile', params: {
      'p_display_name': displayName ?? username,
      'p_phone_number': phoneNumber,
    });
  }
}