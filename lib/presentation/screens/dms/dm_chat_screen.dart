import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../components/chat_kit.dart';
import '../../../services/chat_store.dart';
import '../../../services/dm_crypto.dart';
import '../../components/report_sheet.dart';
import '../chat/media_viewer_screen.dart';
import '../../components/booknest_emojis.dart';
import '../../../services/reader_profile.dart';
import '../../../services/backend_api.dart';
import '../../../services/call_service.dart';
import '../calls/call_screen.dart';
import '../../../services/inbox_watcher.dart';
import '../../../services/typing_broadcaster.dart';
import '../../../services/supabase_service.dart';

/// 1:1 chat on the BookNest watermark canvas — glass bubbles, delivery
/// ticks, day separators, photos via Cloudinary and rich book-share cards.
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
  final ScrollController _scroll = ScrollController();

  String? _conversationId;
  Map<String, dynamic>? _peer;
  List<Map<String, dynamic>> _messages = [];
  bool _searching = false;
  final TextEditingController _searchController = TextEditingController();
  Map<String, dynamic>? _replyTo;
  String _themeId = 'classic';
  double _themeDim = 0;
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
    _loadTheme();
    // Sealed messaging: identity + the peer's public key, silently.
    if ((widget.peerId ?? '').isNotEmpty) {
      DmCrypto.instance.ensureIdentity();
    }
    ReaderProfile.ensureLoaded();
    _loadPeerBadges();
    _conversationId = widget.conversationId;
    final openConv = _conversationId;
    if (openConv != null) InboxWatcher.instance.enter(openConv);
    if (openConv != null) {
      TypingBroadcaster.instance.enter(openConv, myId: _viewerId ?? '');
    }
    _loadPeer();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  @override
  void dispose() {
    final openConv = _conversationId;
    if (openConv != null) InboxWatcher.instance.leave(openConv);
    TypingBroadcaster.instance.leave();
    _poll?.cancel();
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
          .select('id, username, display_name, avatar_url')
          .eq('id', id)
          .maybeSingle();
      if (!mounted || row == null) return;
      setState(() => _peer = Map<String, dynamic>.from(row));
    } catch (_) {
      // Peer profile is cosmetic — the chat still works without it.
    }
  }

  String get _conversationKey =>
      'dm:${_conversationId ?? widget.conversationId ?? widget.peerId}';

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

  Future<void> _startCall({required bool video}) async {
    final peer = widget.peerId;
    if (peer == null || peer.isEmpty) return;
    final service = CallService.instance;
    if (service.status != CallStatus.idle) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Already in a call.')));
      return;
    }
    await service.startCall(
        peerId: peer, peerName: _peerName, video: video);
    if (!mounted) return;
    CallScreen.open(context);
  }

  Future<void> _editTheme() async {
    await showChatThemePicker(context, conversationKey: _conversationKey);
    _loadTheme();
  }

  /// This conversation's key in the on-device vault.
  String get _vaultKey {
    final conversationId = _conversationId;
    return (conversationId == null || conversationId.isEmpty)
        ? 'peer:${widget.peerId}'
        : 'dm:$conversationId';
  }

  Future<void> _rememberInVault(List<Map<String, dynamic>> messages) async {
    try {
      await ChatStore.instance.setMeta(_vaultKey, {
        'type': 'dm',
        'peerId': widget.peerId,
        'title': _peerName,
      });
      await ChatStore.instance.replace(_vaultKey, messages);
      // The conversation earned its real id after the first send — move
      // any peer-keyed history over.
      if (_conversationId != null && _vaultKey.startsWith('dm:')) {
        await ChatStore.instance.rename('peer:${widget.peerId}', _vaultKey);
      }
    } catch (_) {}
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
    var messages = (res['messages'] as List? ?? [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    // Open sealed envelopes — the words never existed on our servers.
    for (var i = 0; i < messages.length; i++) {
      final raw = messages[i]['text']?.toString() ?? '';
      if (DmCrypto.isEnvelope(raw)) {
        final opened = DmCrypto.instance.open(raw);
        messages[i] = {
          ...messages[i],
          'text': opened ?? '🔒 Sealed message',
          'sealed': opened != null,
        };
      }
    }
    final serverCount = messages.length;
    // Merge the on-device vault: restored or older history appears above
    // the server's sync window — WhatsApp-style.
    try {
      final stored = await ChatStore.instance.load(_vaultKey);
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
    final grew = serverCount > _lastCount && _lastCount >= 0;
    _lastCount = serverCount;
    // Real read receipts: everything from the peer is marked read while
    // this chat is open.
    if (conversationId != null) BackendApi.instance.markDmRead(conversationId);
    if (mounted) {
      setState(() {
        _messages = messages;
        _loading = false;
      });
    }
    _rememberInVault(messages);
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

  Future<void> _sendText(String text) async {
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
    // Seal when both sides support it — otherwise send plainly (never a
    // fake lock).
    var wireText = text;
    String? previewText;
    final sealPeer = widget.peerId;
    if (sealPeer != null && sealPeer.isNotEmpty) {
      try {
        final sealed = await DmCrypto.instance.seal(sealPeer, text);
        if (sealed != null) {
          wireText = sealed;
          previewText = '🔒 Encrypted message';
        }
      } catch (_) {}
    }
    final res = await BackendApi.instance.sendMessage(
      conversationId: _conversationId,
      peerId: widget.peerId,
      type: 'text',
      text: wireText,
      previewText: previewText,
      replyToId:
          replying != null && !replying['id'].toString().startsWith('local-')
              ? replying['id'].toString()
              : null,
    );
    if (mounted) setState(() => _replyTo = null);
    if (!mounted) return;
    if (res == null) {
      _markLocal(localId, failed: true);
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

  Future<void> _sendImage(bytes, String extension) async {
    final localId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    setState(() => _messages.add({
          'id': localId,
          'senderId': _viewerId,
          'type': 'image',
          'text': '',
          'createdAt': DateTime.now().toIso8601String(),
          'pending': true,
        }));
    _jumpToBottom();

    final url = await uploadChatImage(bytes, extension);
    if (!mounted) return;
    if (url == null) {
      _markLocal(localId, failed: true);
      _notice('The photo could not be uploaded — please try again.');
      return;
    }
    final res = await BackendApi.instance.sendMessage(
      conversationId: _conversationId,
      peerId: widget.peerId,
      type: 'image',
      text: '',
      mediaUrl: url,
    );
    if (!mounted) return;
    if (res == null) {
      _markLocal(localId, failed: true);
      _notice('The photo could not be delivered — please try again.');
      return;
    }
    _conversationId ??=
        res['conversationId']?.toString() ?? widget.conversationId;
    await _load();
  }

  Future<void> _sendFile(String filename, bytes) async {
    final localId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    setState(() => _messages.add({
          'id': localId,
          'senderId': _viewerId,
          'type': 'file',
          'text': filename,
          'createdAt': DateTime.now().toIso8601String(),
          'pending': true,
        }));
    _jumpToBottom();

    final url = await uploadChatFile(filename, bytes);
    if (!mounted) return;
    if (url == null) {
      _markLocal(localId, failed: true);
      _notice('The file could not be uploaded — please try again.');
      return;
    }
    final res = await BackendApi.instance.sendMessage(
      conversationId: _conversationId,
      peerId: widget.peerId,
      type: 'file',
      text: filename,
      mediaUrl: url,
      fileName: filename,
      fileSize: bytes.length,
    );
    if (!mounted) return;
    if (res == null) {
      _markLocal(localId, failed: true);
      _notice('The file could not be delivered — please try again.');
      return;
    }
    _conversationId ??=
        res['conversationId']?.toString() ?? widget.conversationId;
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

  /// Records stay local until the upload answers — honest states only.
  Future<void> _sendVideo(String videoPath, int seconds) async {
    final localId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    final file = File(videoPath);
    final size = await file.length();
    setState(() => _messages.add({
          'id': localId,
          'senderId': _viewerId,
          'type': 'video',
          'text': '',
          'mediaUrl': videoPath,
          'fileName': 'clip.mp4',
          'fileSize': size,
          'createdAt': DateTime.now().toIso8601String(),
          'pending': true,
        }));
    _jumpToBottom();
    final bytes = await file.readAsBytes();
    final url = await uploadChatFile('clip-${DateTime.now().millisecondsSinceEpoch}.mp4', bytes);
    if (!mounted) return;
    if (url == null) {
      _markLocal(localId, failed: true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'The video could not be uploaded — press the message to retry '
              'once your connection is back.')));
      return;
    }
    final replying = _replyTo;
    final res = await BackendApi.instance.sendMessage(
      conversationId: _conversationId,
      peerId: widget.peerId,
      type: 'video',
      text: '',
      mediaUrl: url,
      fileName: 'clip.mp4',
      fileSize: size,
      replyToId:
          replying != null && !replying['id'].toString().startsWith('local-')
              ? replying['id'].toString()
              : null,
    );
    if (mounted) setState(() => _replyTo = null);
    if (!mounted) return;
    if (res == null) {
      _markLocal(localId, failed: true);
      return;
    }
    _conversationId ??= res['conversationId']?.toString() ?? widget.conversationId;
    await _load();
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
    final res = await BackendApi.instance.reactDmMessage(messageId, code);
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
        .deleteDmMessage(messageId, forEveryone: forEveryone);
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

  Future<void> _sendEmote(EmojiDef emote) async {
    final res = await BackendApi.instance.sendMessage(
      conversationId: _conversationId,
      peerId: widget.peerId,
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
    _conversationId ??= res['conversationId']?.toString() ?? widget.conversationId;
    await _load();
  }

  String? _peerCountry;
  String? _peerGender;

  Future<void> _loadPeerBadges() async {
    final peer = widget.peerId;
    if (peer == null || peer.isEmpty) return;
    final res = await BackendApi.instance.fetchUserProfile(userId: peer);
    final profile = res?['profile'];
    if (!mounted || profile is! Map) return;
    setState(() {
      _peerCountry = profile['countryCode']?.toString();
      if ((_peerCountry ?? '').isEmpty) _peerCountry = null;
      _peerGender = profile['gender']?.toString();
      if ((_peerGender ?? '').isEmpty) _peerGender = null;
    });
  }

  String _nameOfReader(String uid) =>
      uid == widget.peerId ? _peerName : 'You';

  void _markLocal(String localId, {required bool failed}) {
    final index = _messages.indexWhere((m) => m['id'] == localId);
    if (index == -1) return;
    setState(() {
      _messages[index]['pending'] = false;
      _messages[index]['failed'] = failed;
    });
  }

  void _openBook(String? bookId) {
    if (bookId == null || bookId.isEmpty) return;
    context.push('/book/$bookId');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final query = _searching ? _searchController.text : '';
    final visible =
        filterChatMessages(_messages, query);
    final rows = withDaySeparators(visible);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded), onPressed: context.pop),
        actions: [
          IconButton(
            tooltip: 'Shared media',
            icon: const Icon(Icons.photo_library_outlined, size: 21),
            onPressed: _photoAlbum().isEmpty
                ? null
                : () => openChatPhoto(
                      context,
                      _photoAlbum().first.url,
                      album: _photoAlbum(),
                      initialIndex: 0,
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
                  : _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: BookNestColors.cyan))
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
                                  final album = _photoAlbum();
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
              onSendEmote: _sendEmote,
              replyTo: _replyTo,
              onCancelReply: () => setState(() => _replyTo = null),
            ),
          ],
        ),
      ),
    
            onTyping: () => TypingBroadcaster.instance
                .iAmTyping(_peerName),);
  }
}
