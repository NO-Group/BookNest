import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../components/chat_kit.dart';
import '../../../services/backend_api.dart';
import '../../../services/supabase_service.dart';

/// Club / community / organization / school group chat — membership-gated
/// rooms on the BookNest watermark canvas. Everyone in the group sees the
/// conversation; sender names and avatars come from Supabase profiles.
class ChatScreen extends StatefulWidget {
  final String clubId;
  final String kind;
  final String title;

  /// Club detail already knows whether the viewer belongs to the group —
  /// passing it avoids a rejected server round-trip for non-members.
  final bool isMember;

  const ChatScreen({
    super.key,
    required this.clubId,
    this.kind = 'clubs',
    this.title = 'Group chat',
    this.isMember = true,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scroll = ScrollController();

  String? _conversationId;
  List<Map<String, dynamic>> _messages = [];
  Map<String, Map<String, dynamic>> _people = {};
  Timer? _poll;
  bool _loading = true;
  bool _offline = false;
  bool _notMember = false;
  int _lastCount = -1;

  String get _viewerId => SupabaseService().auth.currentUser?.id ?? '';

  bool _isMine(Map<String, dynamic> message) =>
      message['senderId']?.toString() == _viewerId;

  @override
  void initState() {
    super.initState();
    if (widget.isMember) {
      _openRoom();
    } else {
      setState(() {
        _notMember = true;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _openRoom() async {
    final res = await BackendApi.instance.ensureClubChat(widget.kind, widget.clubId);
    if (!mounted) return;
    if (res == null) {
      setState(() {
        _offline = true;
        _loading = false;
      });
      return;
    }
    final conversation = res['conversation'];
    if (conversation is! Map) {
      setState(() {
        _notMember = true;
        _loading = false;
      });
      return;
    }
    _conversationId = conversation['id']?.toString();
    await _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  Future<void> _load() async {
    final conversationId = _conversationId;
    if (conversationId == null) return;
    final res = await BackendApi.instance.listClubMessages(conversationId);
    if (!mounted) return;
    if (res == null) return;
    final messages = (res['messages'] as List? ?? [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();

    // Resolve sender names/avatars (cosmetic — never blocks the chat).
    final senderIds = messages
        .map((m) => m['senderId']?.toString() ?? '')
        .where((id) => id.isNotEmpty && !_people.containsKey(id))
        .toSet()
        .toList();
    if (senderIds.isNotEmpty) {
      try {
        final rows = await SupabaseService()
            .client
            .from('profiles')
            .select('id, username, display_name, avatar_url')
            .inFilter('id', senderIds);
        for (final row in rows as List) {
          final person = Map<String, dynamic>.from(row as Map);
          _people[person['id']?.toString() ?? ''] = person;
        }
      } catch (_) {}
    }

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

  Future<void> _sendText(String text) async {
    final conversationId = _conversationId;
    if (conversationId == null) return;
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
    final res = await BackendApi.instance.sendClubMessage(
      conversationId: conversationId,
      text: text,
    );
    if (!mounted) return;
    if (res == null) {
      final index = _messages.indexWhere((m) => m['id'] == localId);
      if (index != -1) {
        setState(() {
          _messages[index]['pending'] = false;
          _messages[index]['failed'] = true;
        });
      }
      return;
    }
    await _load();
  }

  Future<void> _sendImage(bytes, String extension) async {
    final conversationId = _conversationId;
    if (conversationId == null) return;
    final url = await uploadChatImage(bytes, extension);
    if (!mounted) return;
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('The photo could not be uploaded — please try again.'),
      ));
      return;
    }
    final res = await BackendApi.instance.sendClubMessage(
      conversationId: conversationId,
      type: 'image',
      mediaUrl: url,
    );
    if (!mounted) return;
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('The photo could not be delivered — please try again.'),
      ));
      return;
    }
    await _load();
  }

  String _senderName(String senderId) {
    final person = _people[senderId];
    final name = (person?['display_name'] ?? person?['username'])?.toString();
    return (name == null || name.trim().isEmpty) ? 'Reader' : name.trim();
  }

  String? _senderAvatar(String senderId) {
    final url = _people[senderId]?['avatar_url']?.toString();
    return url != null && url.startsWith('http') ? url : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = withDaySeparators(_messages);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded), onPressed: context.pop),
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: BookNestColors.navy,
              child: Text(
                widget.title.isEmpty ? '#' : widget.title.characters.first.toUpperCase(),
                style: const TextStyle(
                    color: BookNestColors.cyan,
                    fontWeight: FontWeight.w800,
                    fontSize: 14),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(
                    'Group chat · members only',
                    style: TextStyle(
                      fontSize: 11,
                      color: BookNestColors.cyan.withOpacity(.85),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: ChatCanvas(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: BookNestColors.cyan))
            : _offline
                ? _buildNotice(
                    icon: Icons.cloud_off_rounded,
                    title: 'Chat is getting ready',
                    body: 'The BookNest cloud will host this group\'s chat. '
                        'Please try again in a moment.',
                  )
                : _notMember
                    ? _buildNotice(
                        icon: Icons.lock_person_rounded,
                        title: 'Members only',
                        body: 'Join the group to read and send messages here.',
                      )
                    : Column(
                        children: [
                          Expanded(
                            child: _messages.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.forum_rounded,
                                            color:
                                                BookNestColors.cyan.withOpacity(.6),
                                            size: 42),
                                        const SizedBox(height: 10),
                                        Text('Start the conversation',
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                                    fontWeight:
                                                        FontWeight.w700)),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Everyone in ${widget.title} will see '
                                          'your messages.',
                                          textAlign: TextAlign.center,
                                          style:
                                              TextStyle(color: theme.hintColor),
                                        ),
                                      ],
                                    ),
                                  )
                                : GestureDetector(
                                    onTap: () =>
                                        FocusScope.of(context).unfocus(),
                                    child: ListView.builder(
                                      controller: _scroll,
                                      padding: const EdgeInsets.fromLTRB(
                                          14, 12, 14, 8),
                                      itemCount: rows.length,
                                      itemBuilder: (context, index) {
                                        final row = rows[index];
                                        if (row is String) {
                                          return ChatDayChip(label: row);
                                        }
                                        final message =
                                            row as Map<String, dynamic>;
                                        final mine = _isMine(message);
                                        return ChatBubble(
                                          message: message,
                                          mine: mine,
                                          senderName: mine
                                              ? null
                                              : _senderName(message['senderId']
                                                      ?.toString() ??
                                                  ''),
                                          onOpenImage: () => showChatPhoto(
                                            context,
                                            message['mediaUrl']?.toString() ??
                                                '',
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                          ),
                          ChatComposer(
                            onSendText: _sendText,
                            onSendImage: _sendImage,
                            hint: 'Message ${widget.title}…',
                          ),
                        ],
                      ),
      ),
    );
  }

  Widget _buildNotice({
    required IconData icon,
    required String title,
    required String body,
  }) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: BookNestColors.cyan.withOpacity(.7), size: 46),
            const SizedBox(height: 12),
            Text(title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.hintColor, height: 1.4)),
          ],
        ),
      ),
    );
  }
}
