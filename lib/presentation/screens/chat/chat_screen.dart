import 'package:flutter/material.dart';
import '../../../config/theme.dart';

class ChatScreen extends StatelessWidget {
  final String clubId;
  
  const ChatScreen({super.key, required this.clubId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NOC.bg,
      appBar: AppBar(
        backgroundColor: NOC.bg,
        title: Text('Chat $clubId', style:  TextStyle(color: NOC.text)),
      ),
      body:  Center(
        child: Text(
          'Chat',
          style: TextStyle(color: NOC.text),
        ),
      ),
    );
  }
}