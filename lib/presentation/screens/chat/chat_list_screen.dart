import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import 'chat_models.dart';
import 'chat_repository.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _repository = ChatRepository();
  late Future<List<BookNestChat>> _chats;
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _chats = _repository.loadChats();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BookNestColors.darkBackground,
      appBar: AppBar(
        title: const Text('Messages', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [IconButton(onPressed: () => setState(_reload), icon: const Icon(Icons.refresh))],
      ),
      body: FutureBuilder<List<BookNestChat>>(
        future: _chats,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: BookNestColors.cyan));
          if (snapshot.hasError) return _ErrorState(message: 'Could not load your conversations.', onRetry: () => setState(_reload));
          final chats = (snapshot.data ?? []).where((chat) => _filter == 'All' || chat.type.label == _filter).toList();
          return RefreshIndicator(
            color: BookNestColors.cyan,
            backgroundColor: BookNestColors.darkChatBackground,
            onRefresh: () async => setState(_reload),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                _buildFilters(),
                if (chats.isEmpty) const SizedBox(height: 220, child: Center(child: Text('Your conversations will appear here.', style: TextStyle(color: BookNestColors.darkTextSecondary))))
                else ...chats.map((chat) => _ChatTile(chat: chat)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilters() {
    final values = ['All', 'Direct message', 'Club chat', 'Organization', 'School channel', 'Community announcements', 'The Nexus'];
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final selected = _filter == values[index];
          return ChoiceChip(
            label: Text(values[index]),
            selected: selected,
            onSelected: (_) => setState(() => _filter = values[index]),
            labelStyle: TextStyle(color: selected ? Colors.black : BookNestColors.darkTextSecondary, fontSize: 12),
            selectedColor: BookNestColors.cyan,
            backgroundColor: BookNestColors.darkChatBackground,
            side: BorderSide(color: selected ? BookNestColors.cyan : BookNestColors.darkBorder),
          );
        },
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final BookNestChat chat;
  const _ChatTile({required this.chat});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: BookNestColors.darkChatBackground,
      margin: const EdgeInsets.only(top: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: BookNestColors.darkBorder)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        onTap: () => context.push('/chat/${chat.id}', extra: chat),
        leading: CircleAvatar(backgroundColor: chat.type.color.withOpacity(.16), child: Icon(chat.type.icon, color: chat.type.color)),
        title: Row(children: [Expanded(child: Text(chat.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)), if (chat.type == BookNestChatType.nexus) const Icon(Icons.lock, size: 14, color: BookNestColors.yellow)]),
        subtitle: Text(chat.lastMessage ?? chat.type.label, style: const TextStyle(color: BookNestColors.darkTextSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Icon(Icons.chevron_right, color: chat.type.color),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(message, style: const TextStyle(color: BookNestColors.darkTextSecondary)), const SizedBox(height: 12), OutlinedButton(onPressed: onRetry, child: const Text('Retry'))]));
}
