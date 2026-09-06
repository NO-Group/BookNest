import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../components/chat_kit.dart';
import '../chat/media_viewer_screen.dart';
import '../../components/booknest_emojis.dart';
import '../../../services/reader_profile.dart';
import '../../../services/backend_api.dart';
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
    ReaderProfile.ensureLoaded();
    _loadPeerBadges();
    _conversationId = widget.conversationId;
    _loadPeer();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
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
    // Real read receipts: everything from the peer is marked read while
    // this chat is open.
    if (conversationId != null) BackendApi.instance.markDmRead(conversationId);
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

    final res = await BackendApi.instance.sendMessage(
      conversationId: _conversationId,
      peerId: widget.peerId,
      type: 'text',
      text: text,
    );
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

  Future<void> _reactToMessage(String messageId, String code) async {
    if (messageId.isEmpty || messageId.startsWith('local-')) return;
    final res = await BackendApi.instance.reactDmMessage(messageId, code);
    if (res != null) _load();
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
    if (!mounted || res is! Map || res['profile'] is! Map) return;
    final profile = res['profile'] as Map;
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
    final rows = withDaySeparators(_messages);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded), onPressed: context.pop),
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
                  if (_avatarUrl.isNotEmpty) {
                    openChatPhoto(context, _avatarUrl,
                        album: [
                          MediaItem(url: _avatarUrl, name: _peerName)
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
                    Text(
                      'View profile',
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
      ),
      body: ChatCanvas(
        child: Column(
          children: [
            Expanded(
              child: _loading
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
                      : GestureDetector(
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
                              );
                            },
                          ),
                        ),
            ),
            ChatComposer(
              onSendText: _sendText,
              onSendImage: _sendImage,
              onSendFile: _sendFile,
              onSendEmote: _sendEmote,
            ),
          ],
        ),
      ),
    );
  }
}
