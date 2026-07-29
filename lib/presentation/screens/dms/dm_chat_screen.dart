import 'package:flutter/material.dart';

class DMChatScreen extends StatelessWidget {
  final String conversationId;
  
  const DMChatScreen({super.key, required this.conversationId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: Text('DM $conversationId', style: const TextStyle(color: Colors.white)),
      ),
      body: const Center(
        child: Text(
          'DM Chat',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}