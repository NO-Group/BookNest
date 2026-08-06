import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../../services/supabase_service.dart';
import 'chat_models.dart';
import 'chat_repository.dart';

class ChatDetailScreen extends StatefulWidget {
  final BookNestChat chat;
  const ChatDetailScreen({super.key, required this.chat});
  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _repository = ChatRepository();
  final _composer = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  @override
  void dispose() { _composer.dispose(); _scrollController.dispose(); super.dispose(); }

  Future<void> _send() async {
    final body = _composer.text.trim();
    if (body.isEmpty || _sending || !widget.chat.canPost) return;
    setState(() => _sending = true);
    try {
      await _repository.sendMessage(chatId: widget.chat.id, body: body);
      _composer.clear();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Message was not sent: $error')));
    } finally { if (mounted) setState(() => _sending = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BookNestColors.darkBackground,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [CircleAvatar(radius: 17, backgroundColor: widget.chat.type.color.withOpacity(.16), child: Icon(widget.chat.type.icon, size: 18, color: widget.chat.type.color)), const SizedBox(width: 10), Expanded(child: Text(widget.chat.title, overflow: TextOverflow.ellipsis))]),
        actions: [if (widget.chat.canLeave) PopupMenuButton<String>(onSelected: (value) async { if (value == 'leave') await _leave(); }, itemBuilder: (_) => const [PopupMenuItem(value: 'leave', child: Text('Leave chat'))])],
      ),
      body: Column(children: [
        if (widget.chat.type.isBroadcast) _announcementBanner(),
        Expanded(child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _repository.messageStream(widget.chat.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Center(child: Text('Unable to load messages.\n${snapshot.error}', textAlign: TextAlign.center, style: const TextStyle(color: BookNestColors.darkTextSecondary)));
            final messages = (snapshot.data ?? []).map((row) => ChatMessage.fromMap(row, _repositoryUserId)).toList();
            if (messages.isEmpty) return const Center(child: Text('No messages yet. Start the conversation.', style: TextStyle(color: BookNestColors.darkTextSecondary)));
            return ListView.builder(controller: _scrollController, padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), itemCount: messages.length, itemBuilder: (_, index) => _MessageBubble(message: messages[index], chat: widget.chat, onReact: _react, onVote: _vote));
          },
        )),
        if (widget.chat.canPost) _composerBar() else const _ReadOnlyComposer(),
      ]),
    );
  }

  String get _repositoryUserId => SupabaseService().auth.currentUser?.id ?? '';

  Widget _announcementBanner() => Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), color: widget.chat.type == BookNestChatType.nexus ? BookNestColors.yellow.withOpacity(.1) : BookNestColors.orange.withOpacity(.1), child: Row(children: [Icon(Icons.campaign_outlined, size: 18, color: widget.chat.type.color), const SizedBox(width: 8), const Expanded(child: Text('Only official announcements allowed', style: TextStyle(color: BookNestColors.darkTextSecondary, fontSize: 12)))]));
  Widget _composerBar() => SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 10), child: Row(children: [Expanded(child: TextField(controller: _composer, minLines: 1, maxLines: 4, textInputAction: TextInputAction.newline, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: 'Write a message…', hintStyle: const TextStyle(color: BookNestColors.darkTextSecondary), filled: true, fillColor: BookNestColors.darkChatBackground, border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10))), const SizedBox(width: 8), IconButton(onPressed: _sending ? null : _send, style: IconButton.styleFrom(backgroundColor: BookNestColors.cyan), icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Icon(Icons.send, color: Colors.black))])));
  Future<void> _react(ChatMessage message, String emoji) async { try { await _repository.toggleReaction(message.id, emoji); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reaction failed: $e'))); } }
  Future<void> _vote(String messageId, String optionId) async { try { await _repository.vote(messageId, optionId); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Vote failed: $e'))); } }
  Future<void> _leave() async { try { await _repository.leaveChat(widget.chat.id); if (mounted) Navigator.of(context).pop(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); } }
}

class _ReadOnlyComposer extends StatelessWidget { const _ReadOnlyComposer(); @override Widget build(BuildContext context) => const SafeArea(top: false, child: Padding(padding: EdgeInsets.all(16), child: SizedBox(height: 18))); }

class _MessageBubble extends StatelessWidget {
  final ChatMessage message; final BookNestChat chat; final Future<void> Function(ChatMessage, String) onReact; final Future<void> Function(String, String) onVote;
  const _MessageBubble({required this.message, required this.chat, required this.onReact, required this.onVote});
  @override
  Widget build(BuildContext context) {
    final align = message.isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Column(crossAxisAlignment: align, children: [GestureDetector(onLongPress: () => _reactionPicker(context), child: Container(margin: const EdgeInsets.only(bottom: 4), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), constraints: const BoxConstraints(maxWidth: 330), decoration: BoxDecoration(color: message.isMine ? BookNestColors.darkSentMessage : BookNestColors.darkReceivedMessage, borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [if (message.kind == 'poll') _Poll(message: message, onVote: onVote) else Text(message.body ?? '', style: const TextStyle(color: Colors.white, height: 1.35)), const SizedBox(height: 4), Text(_time(message.createdAt), style: const TextStyle(color: BookNestColors.darkTextSecondary, fontSize: 10))])), if (message.reactions.isNotEmpty) Row(mainAxisSize: MainAxisSize.min, children: message.reactions.entries.map((e) => Padding(padding: const EdgeInsets.only(right: 5), child: Text('${e.key} ${e.value}', style: const TextStyle(color: BookNestColors.darkTextSecondary, fontSize: 12)))).toList()), const SizedBox(height: 8)]);
  }
  void _reactionPicker(BuildContext context) { showModalBottomSheet(context: context, backgroundColor: BookNestColors.darkChatBackground, builder: (_) => Wrap(alignment: WrapAlignment.center, children: ['❤️', '😂', '👏', '🔥', '📚', '🙏'].map((emoji) => IconButton(onPressed: () { Navigator.pop(context); onReact(message, emoji); }, icon: Text(emoji, style: const TextStyle(fontSize: 24))).toList())); }
  String _time(DateTime date) => '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class _Poll extends StatelessWidget { final ChatMessage message; final Future<void> Function(String, String) onVote; const _Poll({required this.message, required this.onVote}); @override Widget build(BuildContext context) { final options = message.metadata['options'] as List? ?? const []; return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(message.body ?? 'Official poll', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), const SizedBox(height: 8), ...options.map((option) { final item = Map<String, dynamic>.from(option as Map); return Padding(padding: const EdgeInsets.only(bottom: 6), child: OutlinedButton(onPressed: () => onVote(message.id, item['id'].toString()), style: OutlinedButton.styleFrom(side: const BorderSide(color: BookNestColors.cyan), foregroundColor: BookNestColors.cyan), child: Align(alignment: Alignment.centerLeft, child: Text(item['label']?.toString() ?? 'Option')))); })]); } }
