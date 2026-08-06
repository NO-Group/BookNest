import 'package:flutter/material.dart';

import '../chat/chat_list_screen.dart';

/// Backwards-compatible route target for the Messages tab.
class DMListScreen extends StatelessWidget {
  const DMListScreen({super.key});
  @override
  Widget build(BuildContext context) => const ChatListScreen();
}
