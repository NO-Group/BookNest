import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class ReadingSessionService {
  SupabaseClient get _client => SupabaseService().client;

  Future<String?> start(String bookId) async {
    final response = await _client.functions.invoke('reading-session', body: {'action': 'start', 'book_id': bookId});
    final data = Map<String, dynamic>.from(response.data as Map);
    return data['session_id']?.toString();
  }

  Future<void> heartbeat(String sessionId) async {
    await _client.functions.invoke('reading-session', body: {'action': 'heartbeat', 'session_id': sessionId});
  }

  Future<void> finish(String sessionId) async {
    await _client.functions.invoke('reading-session', body: {'action': 'finish', 'session_id': sessionId});
  }
}
