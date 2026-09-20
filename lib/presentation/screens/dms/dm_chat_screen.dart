import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../components/chat_kit.dart';
import '../chat/voice_recorder_sheet.dart';
import '../../../services/chat_store.dart';
import '../../../services/dm_crypto.dart';
import '../../components/report_sheet.dart';
import '../chat/media_viewer_screen.dart';
import '../../components/booknest_emojis.dart';
import '../../../services/reader_profile.dart';
import '../../../services/call_service.dart';
import '../calls/call_screen.dart';
import '../../../services/typing_broadcaster.dart';
import '../../../services/supabase_service.dart';
import '../../../services/backend_api.dart';
import '../../../services/inbox_watcher.dart';
import '../../../state/chat_providers.dart';

/// 1:1 chat on the BookNest watermark canvas — glass bubbles, delivery
/// ticks, day separators, photos via Cloudinary and rich book-share cards.
///
/// The engine (messages, sends, reactions, receipts, the live poll)
/// lives in [chatControllerProvider] — this widget is only the face.
class DMChatScreen extends ConsumerStatefulWidget {
  final String? conversationId;
  final String? peerId;

  const DMChatScreen({super.key, this.conversationId, this.peerId});

  @override
  ConsumerState<DMChatScreen> createState() => _DMChatScreenState();
}

class _DMChatScreenState extends ConsumerState<DMChatScreen> {
  final ScrollController _scroll = ScrollController();

  /// Mirror of the live conversation id for leave-time housekeeping
  /// (dispose must not touch the provider).
  String? _convMirror;

  Map<String, dynamic>? _peer;
  bool _searching = false;
  final TextEditingController _searchController = TextEditingController();
  Map<String, dynamic>? _replyTo;
  String _themeId = 'classic';
  double _themeDim = 0;
  bool _cloudOfflineAnnounced = false;

  ChatSource get _source => ChatSource.dm(
      conversationId: widget.conversationId,
      peerId: widget.peerId,
      title: _peerName);

  ChatController get _engine =>
      ref.read(chatControllerProvider(_source).notifier);

  String get _viewerId => SupabaseService().auth.currentUser?.id ?? '';

  bool _isMine(Map<String, dynamic> message) =>
      message['senderId']?.toString() == _viewerId;

  String get _peerName {
    final person = _peer;
    final name =
        (person?['display_name'] ?? person?['username'])?.toString();
    return (name == null || name.trim().isEmpty)
        ? 'BookNest reader'
        : name.trim();
  }

  String? get _avatarUrl {
    final url = _peer?['avatar_url']?.toString();
    return url != null && url.startsWith('http') ? url : null;
  }

  @override
  void initState() {
    super.initState();
    _convMirror = widget.conversationId;
    _loadTheme();
    // Sealed messaging: identity + the peer's public key, silently.
    if ((widget.peerId ?? '').isNotEmpty) {
      DmCrypto.instance.ensureIdentity();
    }
    ReaderProfile.ensureLoaded();
    _loadPeerBadges();
    final openConv = widget.conversationId;
    if (openConv != null) InboxWatcher.instance.enter(openConv);
    if (openConv != null) {
      TypingBroadcaster.instance.enter(openConv, myId: _viewerId);
    }
    _loadPeer();
  }

  @override
  void dispose() {
    final openConv = _convMirror;
    if (openConv != null && openConv.isNotEmpty) {
      InboxWatcher.instance.leave(openConv);
    }
    TypingBroadcaster.instance.leave();
    _scroll.dispose();
    _searchController.dispose();
    ChatStore.instance.flush();
    super.dispose();
  }

  Future<void> _loadPeer() async {
    final id = widget.peerId;
    if (id == null || id.isEmpty) return;
    try {
      final row = await SupabaseService()
          .client
          .from('profiles')
          .select('username, display_name, avatar_url')
          .eq('id', id)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _peer = row == null ? null : Map<String, dynamic>.from(row as Map);
      });
    } catch (_) {
      // Peer profile is cosmetic — the chat still works without it.
    }
  }

  String get _conversationKey =>
      'dm:${_convMirror ?? widget.conversationId ?? widget.peerId}';

  Future<void> _loadTheme() async {
    final id =
        await ChatThemePrefs.forConversation(_conversationKey);
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

  String? _peerCountry;
  String? _peerGender;

  Future<void> _loadPeerBadges() async {
    final peer = widget.peerId;
    if (peer == null || peer.isEmpty) return;
    try {
      final res = await BackendApi.instance.fetchUserProfile(userId: peer);
      final profile = res?['profile'];
      if (!mounted || profile is! Map) return;
      setState(() {
        _peerCountry = profile['countryCode']?.toString();
        if ((_peerCountry ?? '').isEmpty) _peerCountry = null;
        _peerGender = profile['gender']?.toString();
        if ((_peerGender ?? '').isEmpty) _peerGender = null;
      });
    } catch (_) {}
  }

  String _nameOfReader(String uid) =>
      uid == widget.peerId ? _peerName : 'You';

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

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
    final notice = await _engine.sendText(
      text,
      replyToId:
          replying != null && !replying['id'].toString().startsWith('local-')
              ? replying['id'].toString()
              : null,
    );
    if (!mounted) return;
    if (notice != null && !_cloudOfflineAnnounced) {
      _cloudOfflineAnnounced = true;
      _notice(notice);
    }
  }

  Future<void> _sendImage(bytes, String extension) async {
    final notice = await _engine.sendImage(bytes, extension);
    if (!mounted || notice == null) return;
    _notice(notice);
  }

  Future<void> _sendFile(String filename, bytes) async {
    final notice = await _engine.sendFile(filename, bytes);
    if (!mounted || notice == null) return;
    _notice(notice);
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
    _notice(notice);
  }

  Future<void> _sendVoiceNote(VoiceNoteResult voice) async {
    final notice = await _engine.sendVoice(voice);
    if (!mounted || notice == null) return;
    _notice(notice);
  }

  Future<void> _sendEmote(EmojiDef emote) async {
    final notice = await _engine.sendEmote(emote.code, animated: emote.isAnimated);
    if (!mounted || notice == null) return;
    _notice(notice);
  }

  Future<void> _reactToMessage(String messageId, String code) =>
      _engine.react(messageId, code);

  Future<void> _deleteMessage(String messageId,
      {required bool forEveryone}) async {
    final notice = await _engine.delete(messageId, forEveryone: forEveryone);
    if (!mounted || notice == null) return;
    _notice(notice);
  }

  void _forwardMessage(Map<String, dynamic> message) {
    showForwardPicker(context, onDeliver: (target) async {
      final res = await BackendApi.instance.sendMessage(
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

  void _openBook(String? bookId) {
    if (bookId == null || bookId.isEmpty) return;
    context.push('/book/$bookId');
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final chat = ref.watch(chatControllerProvider(_source));
    final conversationId = chat.conversationId ?? _convMirror;
    if ((chat.conversationId ?? '').isNotEmpty &&
        chat.conversationId != _convMirror) {
      _convMirror = chat.conversationId;
    }
    // New messages arrive → glide to the newest (the engine bumps the
    // revision; the tree rebuilds only what watches it).
    ref.listen(chatControllerProvider(_source)
        .select((state) => state.revision), (previous, next) {
      if (previous != next) _jumpToBottom();
    });
    ref.listen(chatControllerProvider(_source)
        .select((state) => state.cloudOffline), (previous, next) {
      if (next && !_cloudOfflineAnnounced) {
        _cloudOfflineAnnounced = true;
      }
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
            onPressed: conversationId == null || conversationId.isEmpty
                ? null
                : () => context.push(
                      '/shared/$conversationId'
                      '?title=${Uri.encodeComponent(_peerName)}',
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
            tooltip: 'Voice call',
            icon: const Icon(Icons.call_outlined, size: 20),
            onPressed: widget.peerId == null || widget.peerId!.isEmpty
                ? null
                : () => _startCall(video: false),
          ),
          IconButton(
            tooltip: 'Video call',
            icon: const Icon(Icons.videocam_outlined, size: 21),
            onPressed: widget.peerId == null || widget.peerId!.isEmpty
                ? null
                : () => _startCall(video: true),
          ),
          IconButton(
            tooltip: 'Chat theme',
            icon: const Icon(Icons.palette_outlined, size: 21),
            onPressed: _editTheme,
          ),
        ],
        titleSpacing: 0,
        title: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: widget.peerId == null || widget.peerId!.isEmpty
              ? null
              : () => context.push('/user/${widget.peerId}'),
          child: Row(
            children: [
              BadgedAvatar(
                name: _peerName,
                imageUrl: _avatarUrl,
                countryCode: _peerCountry,
                gender: _peerGender,
                onTap: () {
                  final url = _avatarUrl;
                  if (url != null && url.isNotEmpty) {
                    openChatPhoto(context, url, album: [
                      MediaItem(url: url, name: _peerName)
                    ]);
                  }
                },
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_peerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    ValueListenableBuilder<Map<String, String>>(
                      valueListenable: TypingBroadcaster.instance.typingPeers,
                      builder: (context, typing, _) => Text(
                        typing.isEmpty ? 'View profile' : 'typing…',
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
      ),
      body: ChatCanvas(
        child: Column(
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
            Expanded(
              child: _searching &&
                      _searchController.text.trim().isNotEmpty &&
                      visible.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.search_off_rounded,
                            size: 40,
                            color: BookNestColors.cyan.withOpacity(.5)),
                        const SizedBox(height: 10),
                        Text('No matches in this chat',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                      ]),
                    )
                  : chat.loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: BookNestColors.cyan))
                  : chat.messages.isEmpty
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
                              Text(
                                'Messages are private to the two of you.',
                                style: TextStyle(color: theme.hintColor),
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
                              onTap: () => FocusScope.of(context).unfocus(),
                              child: ListView.builder(
                            controller: _scroll,
                            padding:
                                const EdgeInsets.fromLTRB(14, 12, 14, 8),
                            itemCount: rows.length,
                            itemBuilder: (context, index) {
                              final row = rows[index];
                              if (row is String) {
                                return ChatDayChip(label: row);
                              }
                              final message = row as Map<String, dynamic>;
                              return ChatBubble(
                                message: message,
                                mine: _isMine(message),
                                onOpenBook: () =>
                                    _openBook(message['bookId']?.toString()),
                                onOpenImage: () {
                                  final album = _photoAlbum(chat.messages);
                                  final tapped = message['mediaUrl']?.toString() ?? '';
                                  var at = album.indexWhere((m) => m.url == tapped);
                                  if (at == -1) at = 0;
                                  openChatPhoto(context, tapped,
                                      album: album, initialIndex: at);
                                },
                                onOpenVideo: () {
                                  final album = _photoAlbum(chat.messages);
                                  final tapped = message['mediaUrl']?.toString() ?? '';
                                  var at = album.indexWhere((m) => m.url == tapped);
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
                                  fileSize: (message['fileSize'] as num?)?.toInt(),
                                ),
                                viewerId: _viewerId,
                                onReact: (code) => _reactToMessage(
                                    message['id']?.toString() ?? '', code),
                                onForward: () => _forwardMessage(message),
                                onInfo: () => showMessageInfo(context, message,
                                    viewerId: _viewerId, nameOf: _nameOfReader),
                                onDeleteForMe: () => _deleteMessage(
                                    message['id']?.toString() ?? '',
                                    forEveryone: false),
                                onDeleteForEveryone: () => _deleteMessage(
                                    message['id']?.toString() ?? '',
                                    forEveryone: true),
                                onTranslate: () =>
                                    _translateMessage(message),
                                onReply: () =>
                                    setState(() => _replyTo = message),
                                onReport: () => showReportSheet(
                                  context,
                                  kind: ReportTargetKind.message,
                                  targetId: message['id']?.toString() ?? '',
                                ),
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
              onSendVideo: _sendVideo,
              onSendVoice: _sendVoiceNote,
              onSendEmote: _sendEmote,
              replyTo: _replyTo,
              onCancelReply: () => setState(() => _replyTo = null),
              onTyping: () =>
                  TypingBroadcaster.instance.iAmTyping(_peerName),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startCall({required bool video}) async {
    if (widget.peerId == null || widget.peerId!.isEmpty) return;
    final service = CallService.instance;
    if (service.status != CallStatus.idle) {
      _notice('Already in a call.');
      return;
    }
    await service.startCall(
        peerId: widget.peerId!, peerName: _peerName, video: video);
    if (!mounted) return;
    CallScreen.open(context);
  }
}
