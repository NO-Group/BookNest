import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../../services/supabase_service.dart';

/// Telegram-style 1:1 chat. Handles text and rich book_share cards.
///
/// Opened either with a [conversationId] (existing chat) or a [peerId]
/// (starts a chat — the edge function creates/reuses the 1:1 conversation).
/// Messages live in MongoDB via the edge function; the reader's profile
/// (name/avatar) comes from Supabase.
class DMChatScreen extends StatefulWidget {
  final String? conversationId;
  final String? peerId;

  const DMChatScreen({super.key, this.conversationId, this.peerId});

  @override
  State<DMChatScreen> createState() => _DMChatScreenState();
}

class _DMChatScreenState extends State<DMChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final GlobalKey _listKey = GlobalKey();

  String? _conversationId;
  Map<String, dynamic>? _peer;
  List<Map<String, dynamic>> _messages = [];
  Timer? _poll;
  bool _loading = true;
  bool _cloudOfflineAnnounced = false;
  int _lastCount = -1;

  String get _viewerId => SupabaseService().auth.currentUser?.id ?? '';

  bool _isMine(Map<String, dynamic> message) =>
      message['senderId']?.toString() == _viewerId;

  String get _peerName {
    final person = _peer;
    final name =
        (person?['display_name'] ?? person?['username'])?.toString();
    return (name == null || name.trim().isEmpty) ? 'BookNest reader' : name.trim();
  }

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId;
    _loadPeer();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadPeer() async {
    final id = widget.peerId;
    if (id == null || id.isEmpty) return;
    try {
      final row = await SupabaseService()
          .client
          .from('profiles')
          .select('id, username, display_name, avatar_url')
          .eq('id', id)
          .maybeSingle();
      if (!mounted || row == null) return;
      setState(() => _peer = Map<String, dynamic>.from(row));
    } catch (_) {
      // Peer profile is cosmetic — the chat still works without it.
    }
  }

  Future<void> _load() async {
    final conversationId = _conversationId;
    if (conversationId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final res = await BackendApi.instance.listMessages(conversationId);
    if (!mounted) return;
    if (res == null) {
      if (!_cloudOfflineAnnounced) {
        _cloudOfflineAnnounced = true;
        setState(() => _loading = false);
      }
      return;
    }
    final messages = (res['messages'] as List? ?? [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    final grew = messages.length > _lastCount && _lastCount >= 0;
    _lastCount = messages.length;
    setState(() {
      _messages = messages;
      _loading = false;
    });
    if (grew || _scroll.hasClients) _jumpToBottom();
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();

    // Optimistic echo (per the blueprint): the bubble appears instantly.
    final localId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    setState(() => _messages.add({
          'id': localId,
          'senderId': _viewerId,
          'type': 'text',
          'text': text,
          'createdAt': DateTime.now().toIso8601String(),
          'pending': true,
        }));
    _jumpToBottom();

    final res = await BackendApi.instance.sendMessage(
      conversationId: _conversationId,
      peerId: widget.peerId,
      type: 'text',
      text: text,
    );
    if (!mounted) return;
    if (res == null) {
      if (!_cloudOfflineAnnounced) {
        _cloudOfflineAnnounced = true;
        _notice('Message kept on this device — it syncs once the '
            'BookNest cloud is connected.');
      }
      return;
    }
    _conversationId ??=
        res['conversationId']?.toString() ?? widget.conversationId;
    await _load();
  }

  void _openBook(String? bookId) {
    if (bookId == null || bookId.isEmpty) return;
    context.push('/book/$bookId');
  }

  String _timeLabel(dynamic timestamp) {
    if (timestamp is! DateTime) return '';
    return DateFormat('HH:mm').format(timestamp.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final background = dark
        ? BookNestColors.darkChatBackground
        : BookNestColors.lightSurface;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: context.pop),
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: BookNestColors.navy,
              backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
              child: _avatarUrl == null
                  ? Text(
                      _peerName.characters.isEmpty
                          ? '?'
                          : _peerName.characters.first.toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_peerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: BookNestColors.cyan))
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.waving_hand_rounded,
                                color: BookNestColors.cyan.withOpacity(.6),
                                size: 42),
                            const SizedBox(height: 10),
                            Text('Say hello to $_peerName 👋',
                                style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text('Share a book from any book page ✨',
                                style: TextStyle(color: theme.hintColor)),
                          ],
                        ),
                      )
                    : GestureDetector(
                        onTap: () => FocusScope.of(context).unfocus(),
                        child: ListView.builder(
                          key: _listKey,
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            return _Bubble(
                              message: message,
                              mine: _isMine(message),
                              timeLabel: _timeLabel(message['createdAt']),
                              onOpenBook: () =>
                                  _openBook(message['bookId']?.toString()),
                            );
                          },
                        ),
                      ),
          ),
          _buildComposer(theme, dark),
        ],
      ),
    );
  }

  String? get _avatarUrl {
    final url = _peer?['avatar_url']?.toString();
    return url != null && url.startsWith('http') ? url : null;
  }

  Widget _buildComposer(ThemeData theme, bool dark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: (dark ? BookNestColors.darkChatBackground : Colors.white)
            .withOpacity(.96),
        border: Border(
          top: BorderSide(color: theme.dividerColor.withOpacity(.6)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Message…',
                  prefixIcon:
                      const Icon(Icons.auto_awesome_outlined, size: 20),
                  filled: true,
                  fillColor: dark
                      ? BookNestColors.darkReceivedMessage
                      : BookNestColors.lightSurface,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _send,
              icon: const Icon(Icons.send_rounded, size: 20),
              style: IconButton.styleFrom(
                backgroundColor: BookNestColors.cyan,
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool mine;
  final String timeLabel;
  final VoidCallback onOpenBook;

  const _Bubble({
    required this.message,
    required this.mine,
    required this.timeLabel,
    required this.onOpenBook,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final pending = message['pending'] == true;
    final type = message['type']?.toString() ?? 'text';
    final text = message['text']?.toString() ?? '';

    final bubbleColor = mine
        ? const LinearGradient(
            colors: [BookNestColors.navy, BookNestColors.navyDeep],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight)
        : const LinearGradient(
            colors: [BookNestColors.darkReceivedMessage, BookNestColors.darkReceivedMessage],
          );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: type == 'book_share'
            ? const EdgeInsets.all(12)
            : const EdgeInsets.fromLTRB(14, 9, 14, 7),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * .76),
        decoration: BoxDecoration(
          gradient: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
          border: mine
              ? null
              : Border.all(color: BookNestColors.cyan.withOpacity(.18)),
          boxShadow: [
            BoxShadow(
              color: BookNestColors.navyDeep.withOpacity(.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (type == 'book_share')
              _BookShareCard(
                title: text,
                onOpen: onOpenBook,
                dark: dark,
              )
            else
              Text(
                text,
                style: TextStyle(
                  color: mine
                      ? Colors.white
                      : BookNestColors.darkTextPrimary,
                  height: 1.35,
                ),
              ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeLabel,
                  style: TextStyle(
                    fontSize: 10,
                    color: mine
                        ? Colors.white.withOpacity(.7)
                        : theme.hintColor,
                  ),
                ),
                if (pending) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.schedule,
                      size: 11,
                      color: Colors.white.withOpacity(.7)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BookShareCard extends StatelessWidget {
  final String title;
  final VoidCallback onOpen;
  final bool dark;

  const _BookShareCard({
    required this.title,
    required this.onOpen,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: dark ? Colors.white.withOpacity(.06) : Colors.white,
          border: Border.all(color: BookNestColors.cyan.withOpacity(.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: const LinearGradient(
                  colors: [BookNestColors.navy, BookNestColors.navyDeep],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Icon(Icons.auto_stories_rounded,
                  color: BookNestColors.cyan, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Shared a book',
                      style: TextStyle(
                        fontSize: 11,
                        color: BookNestColors.cyan,
                        fontWeight: FontWeight.w700,
                      )),
                  const SizedBox(height: 2),
                  Text(
                    title.isEmpty ? 'Open in BookNest' : title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: dark
                          ? BookNestColors.darkTextPrimary
                          : BookNestColors.navyDeep,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: BookNestColors.cyan),
          ],
        ),
      ),
    );
  }
}
