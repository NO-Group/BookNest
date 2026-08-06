import 'package:flutter/material.dart';

import 'chat_detail_screen.dart';
import 'chat_models.dart';

/// Club-chat entry point retained for existing club routes.
class ChatScreen extends StatelessWidget {
  final String clubId;
  const ChatScreen({super.key, required this.clubId});
  @override
  Widget build(BuildContext context) => ChatDetailScreen(chat: BookNestChat(id: clubId, type: BookNestChatType.club, title: 'Club chat', canPost: true, canLeave: true));
}
