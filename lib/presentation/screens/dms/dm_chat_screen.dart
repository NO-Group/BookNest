import 'package:flutter/material.dart';

import '../chat/chat_detail_screen.dart';
import '../chat/chat_models.dart';

class DMChatScreen extends StatelessWidget {
  final String conversationId;
  const DMChatScreen({super.key, required this.conversationId});
  @override
  Widget build(BuildContext context) => ChatDetailScreen(chat: BookNestChat(id: conversationId, type: BookNestChatType.dm, title: 'Direct message', canPost: true, canLeave: true));
}
