import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../components/chat_kit.dart';
import '../chat/media_viewer_screen.dart';
import '../../components/booknest_emojis.dart';
import '../../../services/chat_store.dart';
import '../../components/booknest_ui.dart';
import '../../components/report_sheet.dart';
import '../../../services/reader_profile.dart';
import '../../../services/backend_api.dart';
import '../../../services/inbox_watcher.dart';
import '../../../services/supabase_service.dart';

/// Club / community / organization / school group chat — membership-gated
/// rooms on the BookNest watermark canvas. Everyone in the group sees the
/// conversation; sender names and avatars come from Supabase profiles.
class ChatScreen extends StatefulWidget {
  final String clubId;
  final String kind;
  final String title;

  /// Sub-room scoping: a department chat (unitId) or a named channel.
  final String unitId;
  final String channelName;

  /// Club detail already knows whether the viewer belongs to the group —
  /// passing it avoids a rejected server round-trip for non-members.
  final bool isMember;

  const ChatScreen({
    super.key,
    required this.clubId,
    this.kind = 'clubs',
    this.title = 'Group chat',
    this.unitId = '',
    this.channelName = '',
    this.isMember = true,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  Map<String, dynamic>? _replyTo;
  Map<String, dynamic>? _pinned;   // the room's pinned message, if any
  bool _canPin = false;            // viewer is owner / deputy
  bool _pinBusy = false;
  String _themeId = 'classic';
  double _themeDim = 0;

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
    ReaderProfile.ensureLoaded();
    if (widget.isMember) {
    _loadTheme();
      _openRoom();
    } else {
      setState(() {
        _notMember = true;
        _loading = false;
      });
    }
  }

  @override
  @override
  void dispose() {
    final openConv = _conversationId;
    if (openConv != null) InboxWatcher.instance.leave(openConv);
    _poll?.cancel();
    _scroll.dispose();
    ChatStore.instance.flush();
    super.dispose();
  }

  Future<void> _openRoom() async {
    final res = await BackendApi.instance.ensureClubChat(
        widget.kind, widget.clubId,
        unitId: widget.unitId, name: widget.channelName);
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
    final pinned = res['pinnedMessage'];
    _pinned = pinned is Map ? Map<String, dynamic>.from(pinned) : null;
    _canPin = res['canPin'] == true;
    final openConv = _conversationId;
    if (openConv != null) InboxWatcher.instance.enter(openConv);
    await _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  String get _conversationKey => 'club:${widget.clubId}:${widget.kind}';

  Future<void> _loadTheme() async {
    final id = await ChatThemePrefs.forConversation(_conversationKey);
    final dim = await ChatThemePrefs.dim();
    if (mounted) {
      setState(() {
        _themeId = id;
        _themeDim = dim;
      });
    }
  }

  Future<void> _editTheme() async {
    await showChatThemePicker(context, conversationKey: _conversationKey);
    _loadTheme();
  }

  Future<void> _togglePin(Map<String, dynamic> message) async {
    if (_pinBusy) return;
    _pinBusy = true;
    final id = message['id']?.toString() ?? '';
    final wasPinned = _pinned?['id']?.toString() == id;
    final res = await BackendApi.instance
        .call('chat.pin', {'messageId': id, 'pinned': !wasPinned});
    _pinBusy = false;
    if (!mounted) return;
    if (res != null) {
      setState(() =>
          _pinned = !wasPinned ? Map<String, dynamic>.from(message) : null);
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res == null
            ? 'Could not update the pin — try again.'
            : (wasPinned ? 'Message unpinned.' : 'Message pinned 📌'))));
  }

  /// The slim banner under the app bar: the room's pinned message.
  Widget _pinnedBanner() {
    final pinned = _pinned;
    if (pinned == null) return const SizedBox.shrink();
    final text = pinned['text']?.toString() ?? '';
    final author = _senderName(pinned['senderId']?.toString() ?? '');
    return Material(
      color: BookNestColors.cyan.withOpacity(.10),
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          shape: const RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24))),
          builder: (sheetContext) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
              child: Column(mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.push_pin_rounded,
                      size: 18, color: BookNestColors.cyan),
                  SizedBox(width: 8),
                  Text('Pinned message',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: BookNestColors.cyan)),
                ]),
                const SizedBox(height: 10),
                if (author.isNotEmpty) ...[
                  Text(author,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(height: 4),
                ],
                Text(text.isEmpty ? '（media message）' : text,
                    style: const TextStyle(fontSize: 14.5, height: 1.4)),
              ]),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(children: [
            const Icon(Icons.push_pin_rounded,
                size: 15, color: BookNestColors.cyan),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                  '${author.isNotEmpty ? '$author: ' : ''}'
                  '${text.isEmpty ? 'Pinned message' : text}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5)),
            ),
            if (_canPin)
              GestureDetector(
                onTap: () => _togglePin(pinned),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded,
                      size: 15, color: BookNestColors.cyan),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Future<void> _load() async {
    final conversationId = _conversationId;
    if (conversationId == null) return;
    final res = await BackendApi.instance.listClubMessages(conversationId);
    if (!mounted) return;
    if (res == null) return;
    var messages = (res['messages'] as List? ?? [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();

    // Merge restored/older history from the on-device vault.
    final vaultKey = 'club:$conversationId';
    try {
      final stored = await ChatStore.instance.load(vaultKey);
      final serverIds =
          messages.map((m) => m['id']?.toString() ?? '').toSet();
      final older = stored
          .where((m) => !serverIds.contains(m['id']?.toString() ?? ''))
          .toList();
      if (older.isNotEmpty) {
        messages = [...older, ...messages]..sort((a, b) {
            final at = DateTime.tryParse(a['createdAt']?.toString() ?? '');
            final bt = DateTime.tryParse(b['createdAt']?.toString() ?? '');
            if (at == null || bt == null) return 0;
            return at.compareTo(bt);
          });
      }
    } catch (_) {}

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

    // Vault: keep the club's history encrypted on this device.
    try {
      await ChatStore.instance.setMeta(vaultKey, {
        'type': 'club',
        'title': widget.title,
      });
      await ChatStore.instance.replace(vaultKey, messages);
    } catch (_) {}

    // Real read receipts: everything from others is marked read while
    // this chat is open.
    BackendApi.instance.markClubRead(conversationId);
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
    final replying = _replyTo;
    if (mounted) setState(() => _replyTo = null);
    final res = await BackendApi.instance.sendClubMessage(
      conversationId: conversationId,
      text: text,
      replyToId:
          replying != null && !replying['id'].toString().startsWith('local-')
              ? replying['id'].toString()
              : null,
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

  Future<void> _sendFile(String filename, bytes) async {
    final conversationId = _conversationId;
    if (conversationId == null) return;
    final url = await uploadChatFile(filename, bytes);
    if (!mounted) return;
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('The file could not be uploaded — please try again.'),
      ));
      return;
    }
    final res = await BackendApi.instance.sendClubMessage(
      conversationId: conversationId,
      type: 'file',
      text: filename,
      mediaUrl: url,
      fileName: filename,
      fileSize: bytes.length,
    );
    if (!mounted) return;
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('The file could not be delivered — please try again.'),
      ));
      return;
    }
    await _load();
  }

  Future<void> _sendVideo(String videoPath, int seconds) async {
    final conversationId = _conversationId;
    if (conversationId == null) return;
    final file = File(videoPath);
    final size = await file.length();
    final url = await uploadChatFile(
        'clip-${DateTime.now().millisecondsSinceEpoch}.mp4',
        await file.readAsBytes());
    if (!mounted) return;
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'The video could not be uploaded — please try again.')));
      return;
    }
    final res = await BackendApi.instance.sendClubMessage(
      conversationId: conversationId,
      type: 'video',
      mediaUrl: url,
      fileName: 'clip.mp4',
      fileSize: size,
    );
    if (!mounted) return;
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'The video could not be delivered — please try again.')));
      return;
    }
    await _load();
  }

  /// Every photo in this conversation, in order — the media viewer's
  /// album so readers can swipe through the whole gallery in-app.
  List<MediaItem> _photoAlbum() {
    final photos = <MediaItem>[];
    for (final m in _messages) {
      final url = m['mediaUrl']?.toString() ?? '';
      if ((m['type']?.toString() ?? '') == 'image' && url.startsWith('http')) {
        photos.add(MediaItem(url: url,
            name: m['fileName']?.toString() ?? 'Photo',
            fileSize: (m['fileSize'] as num?)?.toInt()));
      }
    }
    return photos;
  }

  Future<void> _reactToMessage(String messageId, String code) async {
    if (messageId.isEmpty || messageId.startsWith('local-')) return;
    // Optimistic: the reaction lands instantly, like every modern chat.
    final idx = _messages.indexWhere((m) => m['id'] == messageId);
    if (idx == -1) return;
    final before = Map<String, dynamic>.from(_messages[idx]);
    final reactions = Map<String, String>.from(
        (_messages[idx]['reactions'] as Map? ?? {}).map(
            (k, v) => MapEntry(k.toString(), v.toString())));
    if (_viewerId.isEmpty) return;
    setState(() {
      if (reactions[_viewerId] == code) {
        reactions.remove(_viewerId);
      } else {
        reactions[_viewerId] = code;
      }
      _messages[idx]['reactions'] = reactions;
    });
    final res = await BackendApi.instance.reactClubMessage(messageId, code);
    if (!mounted) return;
    if (res == null) {
      // Roll back only on failure.
      final at = _messages.indexWhere((m) => m['id'] == messageId);
      if (at != -1) {
        setState(() => _messages[at] = before);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('The reaction could not be saved — please try again.')));
      }
    } else {
      // Reconcile with the server's truth.
      final at = _messages.indexWhere((m) => m['id'] == messageId);
      if (at != -1) {
        final ok = res['reacted'];
        final merged = Map<String, String>.from(
            (_messages[at]['reactions'] as Map? ?? {}).map(
                (k, v) => MapEntry(k.toString(), v.toString())));
        if (ok == false) {
          merged.remove(_viewerId);
        } else if (ok == true) {
          merged[_viewerId] = code;
        }
        setState(() => _messages[at]['reactions'] = merged);
      }
    }
  }

  Future<void> _deleteMessage(String messageId, {required bool forEveryone}) async {
    if (messageId.isEmpty || messageId.startsWith('local-')) return;
    final res = await BackendApi.instance
        .deleteClubMessage(messageId, forEveryone: forEveryone);
    if (!mounted) return;
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('The message could not be deleted — please try again.')));
      return;
    }
    _load();
  }

  void _forwardMessage(Map<String, dynamic> message) {
    showForwardPicker(context, onDeliver: (target) async {
      final res = await BackendApi.instance.sendClubMessage(
        conversationId: target.conversationId,
        type: message['type']?.toString() ?? 'text',
        text: message['text']?.toString() ?? '',
        mediaUrl: message['mediaUrl']?.toString(),
        fileName: message['fileName']?.toString(),
        fileSize: (message['fileSize'] as num?)?.toInt(),
        forwarded: true,
        animated: message['animated'] == true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res == null
              ? 'Could not forward — please try again.'
              : 'Forwarded to ${target.title}')));
    });
  }

  Future<void> _translateMessage(Map<String, dynamic> message) async {
    await ReaderProfile.ensureLoaded();
    final target = ReaderProfile.instance.preferredLanguage ?? 'en';
    if (!mounted) return;
    await showMessageTranslation(context, message, target: target);
  }

  Future<void> _sendEmote(EmojiDef emote) async {
    final conversationId = _conversationId;
    if (conversationId == null) return;
    final res = await BackendApi.instance.sendClubMessage(
      conversationId: conversationId,
      type: 'emoji',
      text: emote.code,
      animated: emote.isAnimated,
    );
    if (!mounted) return;
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('The emote could not be sent — please try again.')));
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
    final dark = theme.brightness == Brightness.dark;
    final rows = withDaySeparators(_messages);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded), onPressed: context.pop),
        actions: [
          IconButton(
            tooltip: 'Chat theme',
            icon: const Icon(Icons.palette_outlined, size: 21),
            onPressed: _editTheme,
          ),
        ],
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
                child: BookNestLoader(size: 44))
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
                          _pinnedBanner(),
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
                                : Stack(
                                    children: [
                                      Positioned.fill(
                                        child: ChatWallpaper(
                                            themeId: _themeId,
                                            dark: dark,
                                            dim: _themeDim),
                                      ),
                                      GestureDetector(
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
                                          senderId:
                                              message['senderId']?.toString(),
                                          onOpenImage: () {
                                            final album = _photoAlbum();
                                            final tapped = message['mediaUrl']
                                                    ?.toString() ??
                                                '';
                                            var at = album.indexWhere((m) =>
                                                m.url == tapped);
                                            if (at == -1) at = 0;
                                            openChatPhoto(context, tapped,
                                                album: album, initialIndex: at);
                                          },
                                          onOpenFile: () => openChatFile(
                                            context,
                                            message['mediaUrl']?.toString() ?? '',
                                            name:
                                                (message['fileName']?.toString().isNotEmpty == true)
                                                    ? message['fileName'].toString()
                                                    : (message['text']?.toString() ?? ''),
                                            fileSize:
                                                (message['fileSize'] as num?)?.toInt(),
                                          ),
                                          viewerId: _viewerId,
                                          onReact: (code) =>
                                              _reactToMessage(
                                                  message['id']?.toString() ?? '',
                                                  code),
                                          onReply: () => setState(
                                              () => _replyTo = message),
                                          onReport: () => showReportSheet(
                                              context,
                                              kind: ReportTargetKind.message,
                                              targetId:
                                                  message['id']?.toString() ??
                                                      ''),
                                          onForward: () =>
                                              _forwardMessage(message),
                                          onInfo: () => showMessageInfo(
                                              context, message,
                                              viewerId: _viewerId,
                                              nameOf: _senderName),
                                          onDeleteForMe: () =>
                                              _deleteMessage(
                                                  message['id']?.toString() ?? '',
                                                  forEveryone: false),
                                          onDeleteForEveryone: () =>
                                              _deleteMessage(
                                                  message['id']?.toString() ?? '',
                                                  forEveryone: true),
                                          onTranslate: () =>
                                              _translateMessage(message),
                                          onPin: _canPin
                                              ? () => _togglePin(message)
                                              : null,
                                          isPinned:
                                              _pinned?['id']?.toString() ==
                                                  (message['id']?.toString() ??
                                                      ''),
                                        );
                                      },
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          ChatComposer(
                            onSendText: _sendText,
                            onSendImage: _sendImage,
                            onSendFile: _sendFile,
                            onSendEmote: _sendEmote,
                            hint: 'Message ${widget.title}…',
                            onSendVideo: _sendVideo,
                            replyTo: _replyTo,
                            onCancelReply: () => setState(() => _replyTo = null),
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
