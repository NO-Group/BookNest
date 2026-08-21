import 'dart:typed_data';

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
  StorageService get storage => client.storage;

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

  /// Ensures the signed-in user has a `profiles` row, creating one from their
  /// auth metadata if missing.
  ///
  /// This fixes a real gap: profiles were only created at sign-up, so users
  /// whose sign-up had no session yet (e.g. email confirmation required) or
  /// accounts created before the helper existed had no profile row, which
  /// broke profile screens and DM search.
  Future<void> ensureProfileForCurrentUser() async {
    final user = auth.currentUser;
    if (user == null) return;

    final existing = await client
        .from('profiles')
        .select('id')
        .eq('id', user.id)
        .maybeSingle();
    if (existing != null) return;

    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final username = (metadata['username'] as String?)?.trim();
    final phone = (metadata['phone'] as String?)?.trim();
    await createProfile(
      userId: user.id,
      username: username != null && username.isNotEmpty
          ? username
          : (user.email ?? 'reader').split('@').first,
      displayName: username,
      phoneNumber: phone,
    );
  }

  /// Uploads an image to a public bucket (upsert) and returns its public URL.
  Future<String> uploadPublicImage({
    required String bucket,
    required String path,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    await client.storage.from(bucket).upload(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );
    return client.storage.from(bucket).getPublicUrl(path);
  }
}