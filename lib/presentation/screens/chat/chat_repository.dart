import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/supabase_service.dart';
import 'chat_models.dart';

class ChatRepository {
  SupabaseClient get _client => SupabaseService().client;
  String get _userId => _client.auth.currentUser!.id;

  Future<List<BookNestChat>> loadChats() async {
    final rows = await _client
        .from('chat_participants')
        .select('chat_id, can_post, chats(*)')
        .eq('user_id', _userId)
        .order('joined_at', ascending: false);
    return (rows as List).map((row) {
      final chat = Map<String, dynamic>.from(row['chats'] as Map);
      return BookNestChat.fromMap(chat, canPost: row['can_post'] == true);
    }).toList();
  }

  Stream<List<Map<String, dynamic>>> messageStream(String chatId) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('chat_id', chatId)
        .order('created_at');
  }

  Future<void> sendMessage({
    required String chatId,
    required String body,
    String messageType = 'text',
    Map<String, dynamic> metadata = const {},
    String? replyTo,
  }) async {
    await _client.from('messages').insert({
      'chat_id': chatId,
      'sender_id': _userId,
      'message_type': messageType,
      'body': body.trim(),
      'metadata': metadata,
      'reply_to': replyTo,
    });
  }

  Future<void> markRead(String chatId, String messageId) async {
    await _client.rpc('mark_chat_read', params: {
      'target_chat': chatId,
      'target_message': messageId,
    });
  }

  Future<void> toggleReaction(String messageId, String emoji) async {
    final existing = await _client.from('message_reactions').select('id').eq('message_id', messageId).eq('user_id', _userId).eq('emoji', emoji).maybeSingle();
    if (existing != null) {
      await _client.from('message_reactions').delete().eq('id', existing['id']);
    } else {
      await _client.from('message_reactions').insert({'message_id': messageId, 'user_id': _userId, 'emoji': emoji});
    }
  }

  Future<void> vote(String messageId, String optionId) async {
    await _client.from('poll_votes').upsert({
      'message_id': messageId,
      'user_id': _userId,
      'option_id': optionId,
    }, onConflict: 'message_id,user_id');
  }

  Future<void> leaveChat(String chatId) async {
    final chat = await _client.from('chats').select('chat_type').eq('id', chatId).single();
    if (chat['chat_type'] == 'nexus') throw StateError('The Nexus is mandatory and cannot be left.');
    await _client.from('chat_participants').delete().eq('chat_id', chatId).eq('user_id', _userId);
  }
}
