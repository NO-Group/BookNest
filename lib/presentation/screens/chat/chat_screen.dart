import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../components/chat_kit.dart';
import '../chat/voice_recorder_sheet.dart';
import '../chat/media_viewer_screen.dart';
import '../../components/booknest_emojis.dart';
import '../../../services/chat_store.dart';
import '../../components/booknest_ui.dart';
import '../../components/report_sheet.dart';
import '../../../services/reader_profile.dart';
import '../../../services/chat_repository.dart';
import '../../../services/typing_broadcaster.dart';
import '../../../services/supabase_service.dart';
import '../../../state/chat_providers.dart';

/// Club / community / organization / school group chat — membership-gated
/// rooms on the BookNest watermark canvas. Everyone in the group sees the
/// conversation; sender names and avatars come from Supabase profiles.
///
/// The engine (room entry, messages, sends, reactions, pins, receipts,
/// the live poll) lives in [chatControllerProvider] — this widget is
/// only the face.
class ChatScreen extends ConsumerStatefulWidget {
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
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  bool _searching = false;
  final TextEditingController _searchController = TextEditingController();
  Map<String, dynamic>? _replyTo;
  bool _pinBusy = false;
  String _themeId = 'classic';
  double _themeDim = 0;

  final ScrollController _scroll = ScrollController();

  ChatSource get _source => ChatSource.room(
        roomId: widget.clubId,
        roomKind: widget.kind,
        unitId: widget.unitId,
        channelName: widget.channelName,
        isMember: widget.isMember,
        title: widget.title,
      );

  ChatController get _engine =>
      ref.read(chatControllerProvider(_source).notifier);

  String get _viewerId => SupabaseService().auth.currentUser?.id ?? '';

  bool _isMine(Map<String, dynamic> message) =>
      message['senderId']?.toString() == _viewerId;

  @override
  void initState() {
    super.initState();
    ReaderProfile.ensureLoaded();
    _loadTheme();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchController.dispose();
    ChatStore.instance.flush();
    super.dispose();
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
    final notice = await _engine.togglePin(message);
    _pinBusy = false;
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(notice)));
  }

  /// Every photo and video in this conversation, in order — the media
  /// viewer's album.
  List<MediaItem> _photoAlbum(List<Map<String, dynamic>> messages) {
    final photos = <MediaItem>[];
    for (final m in messages) {
      final url = m['mediaUrl']?.toString() ?? '';
      final type = m['type']?.toString() ?? '';
      if ((type == 'image' || type == 'video') && url.startsWith('http')) {
        photos.add(MediaItem(url: url,
            name: m['fileName']?.toString() ??
                (type == 'video' ? 'Video' : 'Photo'),
            fileSize: (m['fileSize'] as num?)?.toInt()));
      }
    }
    return photos;
  }

  Future<void> _reactToMessage(String messageId, String code) async {
    final ok = await _engine.react(messageId, code);
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('The reaction could not be saved — please try again.')));
  }

  Future<void> _deleteMessage(String messageId,
      {required bool forEveryone}) async {
    final notice = await _engine.delete(messageId, forEveryone: forEveryone);
    if (!mounted || notice == null) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(notice)));
  }

  void _forwardMessage(Map<String, dynamic> message) {
    showForwardPicker(context, onDeliver: (target) async {
      final res = await ChatRepository.instance.send(
        const ChatSource(flavor: ChatFlavor.room),
        target.conversationId,
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

  String _senderName(String senderId, Map<String, Map<String, dynamic>> people) {
    final person = people[senderId];
    final name = (person?['display_name'] ?? person?['username'])?.toString();
    return (name == null || name.trim().isEmpty) ? 'Reader' : name.trim();
  }

  String _typingLabel(Map<String, String> typing) {
    final names = typing.values.take(2).toList();
    if (names.isEmpty) return '';
    if (names.length == 1) return names.first;
    return '${names.first} and ${names.last}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final chat = ref.watch(chatControllerProvider(_source));
    ref.listen(
        chatControllerProvider(_source).select((state) => state.revision),
        (previous, next) {
      if (previous != next) _jumpToBottom();
    });
    final query = _searching ? _searchController.text : '';
    final visible = filterChatMessages(chat.messages, query);
    final rows = withDaySeparators(visible);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded), onPressed: context.pop),
        actions: [
          IconButton(
            tooltip: 'Shared media & files',
            icon: const Icon(Icons.folder_shared_outlined, size: 21),
            onPressed: (chat.conversationId ?? '').isEmpty
                ? null
                : () => context.push(
                      '/shared/${chat.conversationId}'
                      '?title=${Uri.encodeComponent(widget.title)}',
                    ),
          ),
          IconButton(
            tooltip: 'Search messages',
            icon: const Icon(Icons.search_rounded, size: 21),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _searchController.clear();
            }),
          ),
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
                  ValueListenableBuilder<Map<String, String>>(
                    valueListenable: TypingBroadcaster.instance.typingPeers,
                    builder: (context, typing, _) => Text(
                      typing.isEmpty
                          ? 'Group chat · members only'
                          : '${_typingLabel(typing)} typing…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: typing.isEmpty
                            ? FontStyle.normal
                            : FontStyle.italic,
                        color: BookNestColors.cyan.withOpacity(.85),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: ChatCanvas(
        child: chat.loading
            ? const Center(
                child: BookNestLoader(size: 44))
            : chat.cloudOffline
                ? _buildNotice(
                    icon: Icons.cloud_off_rounded,
                    title: 'Chat is getting ready',
                    body: 'The BookNest cloud will host this group\'s chat. '
                        'Please try again in a moment.',
                  )
                : chat.notMember
                    ? _buildNotice(
                        icon: Icons.lock_person_rounded,
                        title: 'Members only',
                        body: 'Join the group to read and send messages here.',
                      )
                    : Column(
                        children: [
                          if (_searching)
                            ChatSearchBar(
                              controller: _searchController,
                              resultCount: visible.length,
                              hasQuery: _searchController.text.trim().isNotEmpty,
                              onChanged: (_) => setState(() {}),
                              onClose: () => setState(() {
                                _searching = false;
                                _searchController.clear();
                              }),
                            ),
                          _pinnedBanner(chat),
                          Expanded(
                            child: _searching &&
                                    _searchController.text.trim().isNotEmpty &&
                                    visible.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.search_off_rounded,
                                            size: 40,
                                            color: BookNestColors.cyan
                                                .withOpacity(.5)),
                                        const SizedBox(height: 10),
                                        Text('No matches in this chat',
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                                    fontWeight:
                                                        FontWeight.w700)),
                                      ],
                                    ),
                                  )
                                : chat.messages.isEmpty
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
                                                  '',
                                                  chat.people),
                                          senderId:
                                              message['senderId']?.toString(),
                                          onOpenImage: () {
                                            final album =
                                                _photoAlbum(chat.messages);
                                            final tapped = message['mediaUrl']
                                                    ?.toString() ??
                                                '';
                                            var at = album.indexWhere((m) =>
                                                m.url == tapped);
                                            if (at == -1) at = 0;
                                            openChatPhoto(context, tapped,
                                                album: album,
                                                initialIndex: at);
                                          },
                                          onOpenVideo: () {
                                            final album =
                                                _photoAlbum(chat.messages);
                                            final tapped = message['mediaUrl']
                                                    ?.toString() ??
                                                '';
                                            var at = album.indexWhere((m) =>
                                                m.url == tapped);
                                            if (at == -1) at = 0;
                                            openChatPhoto(context, tapped,
                                                album: album,
                                                initialIndex: at);
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
                                              nameOf: (id) => _senderName(
                                                  id, chat.people)),
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
                                          onPin: chat.canPin
                                              ? () => _togglePin(message)
                                              : null,
                                          isPinned:
                                              chat.pinned?['id']?.toString() ==
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
                            onSendVoice: _sendVoiceNote,
                            onSendEmote: _sendEmote,
                            hint: 'Message ${widget.title}…',
                            onSendVideo: _sendVideo,
                            replyTo: _replyTo,
                            onCancelReply: () => setState(() => _replyTo = null),
                            onTyping: () =>
                                TypingBroadcaster.instance.iAmTyping('Member'),
                          ),
                        ],
                      ),
      ),
    );
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
    final replying = _replyTo;
    if (mounted) setState(() => _replyTo = null);
    await _engine.sendText(
      text,
      replyToId:
          replying != null && !replying['id'].toString().startsWith('local-')
              ? replying['id'].toString()
              : null,
    );
  }

  Future<void> _sendVoiceNote(VoiceNoteResult voice) async {
    final notice = await _engine.sendVoice(voice);
    if (!mounted || notice == null) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(notice)));
  }

  Future<void> _sendImage(bytes, String extension) async {
    final notice = await _engine.sendImage(bytes, extension);
    if (!mounted || notice == null) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(notice)));
  }

  Future<void> _sendFile(String filename, bytes) async {
    final notice = await _engine.sendFile(filename, bytes);
    if (!mounted || notice == null) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(notice)));
  }

  Future<void> _sendVideo(String videoPath, int seconds) async {
    final replying = _replyTo;
    if (mounted) setState(() => _replyTo = null);
    final notice = await _engine.sendVideo(
      videoPath,
      replyToId:
          replying != null && !replying['id'].toString().startsWith('local-')
              ? replying['id'].toString()
              : null,
    );
    if (!mounted || notice == null) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(notice)));
  }

  Future<void> _sendEmote(EmojiDef emote) async {
    final notice =
        await _engine.sendEmote(emote.code, animated: emote.isAnimated);
    if (!mounted || notice == null) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(notice)));
  }

  /// The slim banner under the app bar: the room's pinned message.
  Widget _pinnedBanner(ChatState chat) {
    final pinned = chat.pinned;
    if (pinned == null) return const SizedBox.shrink();
    final text = pinned['text']?.toString() ?? '';
    final author =
        _senderName(pinned['senderId']?.toString() ?? '', chat.people);
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
            if (chat.canPin)
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
