import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'backend_api.dart';
import 'chat_relay_service.dart';
import 'media_storage.dart';
import 'chat_store.dart';
import 'cloudinary_service.dart';
import 'dm_crypto.dart';
import 'profile_cache.dart';
import 'supabase_service.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// The chat data layer — every conversation speaks through HERE, whether
/// it is a 1:1 DM or a club room. Screens and providers never touch the
/// API directly, which is what makes any surface (a mini preview, a new
/// screen) able to reuse the exact same engine in one line.
/// ─────────────────────────────────────────────────────────────────────────────

enum ChatFlavor { dm, room }

/// Identifies one conversation. [conversationId] may be null for a DM
/// that has not earned its id yet (the first send creates it).
class ChatSource {
  final ChatFlavor flavor;

  /// DM only: the conversation id (null until the first send creates it).
  final String? conversationId;

  /// DM only: who the chat is with.
  final String? peerId;

  /// Room only: the group's identity.
  final String roomId;
  final String roomKind;
  final String unitId;
  final String channelName;
  final bool isMember;

  /// Label for the on-device vault.
  final String title;

  const ChatSource({
    required this.flavor,
    this.conversationId,
    this.peerId,
    this.roomId = '',
    this.roomKind = 'clubs',
    this.unitId = '',
    this.channelName = '',
    this.isMember = true,
    this.title = '',
  });

  /// A 1:1 chat. [conversationId] may start null — the first send earns it.
  const ChatSource.dm({String? conversationId, String? peerId, String title = ''})
      : this(
            flavor: ChatFlavor.dm,
            conversationId: conversationId,
            peerId: peerId,
            title: title);

  /// A group room keyed by the group itself — entry (and its conversation
  /// id) is resolved by the controller through [ChatRepository.ensureRoom].
  const ChatSource.room({
    required String roomId,
    String roomKind = 'clubs',
    String unitId = '',
    String channelName = '',
    bool isMember = true,
    String title = '',
  }) : this(
            flavor: ChatFlavor.room,
            roomId: roomId,
            roomKind: roomKind,
            unitId: unitId,
            channelName: channelName,
            isMember: isMember,
            title: title);

  @override
  bool operator ==(Object other) =>
      other is ChatSource &&
      other.flavor == flavor &&
      other.conversationId == conversationId &&
      other.peerId == peerId &&
      other.roomId == roomId &&
      other.roomKind == roomKind &&
      other.unitId == unitId &&
      other.channelName == channelName &&
      other.isMember == isMember;

  @override
  int get hashCode => Object.hash(flavor, conversationId, peerId, roomId,
      roomKind, unitId, channelName, isMember);
}

/// The result of opening a room: its conversation id plus the pinned
/// message, if any. Null means the cloud could not be reached.
class RoomOpen {
  final String conversationId;
  final Map<String, dynamic>? pinned;
  final bool canPin;
  final bool notMember;

  const RoomOpen({
    required this.conversationId,
    this.pinned,
    this.canPin = false,
    this.notMember = false,
  });
}

/// One finished load of a conversation.
class ChatPage {
  final List<Map<String, dynamic>> messages;
  final Map<String, Map<String, dynamic>> people;
  final bool offline;
  final int serverCount;

  /// Fingerprint of the server page — sent back on the next poll.
  final String? rev;

  /// The server said nothing changed since [rev]: keep what is shown.
  final bool unchanged;

  const ChatPage({
    required this.messages,
    this.people = const {},
    this.offline = false,
    this.serverCount = 0,
    this.rev,
    this.unchanged = false,
  });

  static const empty = ChatPage(messages: []);
}

class ChatRepository {
  ChatRepository._();
  static final ChatRepository instance = ChatRepository._();

  String _vaultKey(ChatSource source, String? conversationId) {
    if (source.flavor == ChatFlavor.room) return 'club:${conversationId ?? ''}';
    return (conversationId == null || conversationId.isEmpty)
        ? 'peer:${source.peerId}'
        : 'dm:$conversationId';
  }

  String get viewerId => SupabaseService().auth.currentUser?.id ?? '';

  /// Loads a conversation: cloud list, sealed envelopes opened (DM),
  /// on-device vault history merged above it, receipts marked, vault
  /// refreshed. Null means the cloud could not be reached — the caller
  /// keeps whatever it already shows.
  ///
  /// [ifRev] is the fingerprint of the page already on screen: when the
  /// server's page still matches, it answers in a few bytes and the
  /// result has `unchanged: true` (no decrypting, no vault write).
  Future<ChatPage?> load(ChatSource source, String? conversationId,
      {String? ifRev}) async {
    if (source.flavor == ChatFlavor.dm) {
      return _loadDm(source, conversationId, ifRev);
    }
    return _loadRoom(source, conversationId, ifRev);
  }

  /// The conversation as this device last saw it — instant, no network.
  /// Shown while the first server answer is on its way.
  Future<ChatPage?> cached(ChatSource source, String? conversationId) async {
    if (source.flavor == ChatFlavor.room &&
        (conversationId == null || conversationId.isEmpty)) {
      return null;
    }
    try {
      final stored =
          await ChatStore.instance.load(_vaultKey(source, conversationId));
      if (stored.isEmpty) return null;
      final messages = [for (final m in stored) Map<String, dynamic>.from(m)];
      final people = source.flavor == ChatFlavor.room
          ? ProfileCache.instance.peek(
              messages.map((m) => m['senderId']?.toString() ?? ''))
          : const <String, Map<String, dynamic>>{};
      return ChatPage(messages: messages, people: people);
    } catch (_) {
      return null;
    }
  }

  // Opened sealed envelopes, so a poll never decrypts the same message twice.
  final Map<String, String?> _opened = {};

  String? _openEnvelope(String id, String raw) {
    final key = '$id:${raw.length}:${raw.hashCode}';
    if (_opened.containsKey(key)) return _opened[key];
    final opened = DmCrypto.instance.open(raw);
    if (_opened.length > 4000) _opened.clear();
    _opened[key] = opened;
    return opened;
  }

  // Newest message from someone else that we already marked read, per
  // conversation — receipts are sent only when something new arrived.
  final Map<String, String> _markedRead = {};

  bool _needsReadMark(String conversationId, List<Map<String, dynamic>> messages) {
    final me = viewerId;
    String newest = '';
    for (final m in messages) {
      final sender = m['senderId']?.toString() ?? '';
      if (sender.isNotEmpty && sender != me) newest = m['id']?.toString() ?? newest;
    }
    if (newest.isEmpty || _markedRead[conversationId] == newest) return false;
    _markedRead[conversationId] = newest;
    return true;
  }

  /// Opens a room: creates or reuses the group conversation and returns
  /// its id plus the pinned message. Null means offline.
  Future<RoomOpen?> ensureRoom(ChatSource source) async {
    final res = await BackendApi.instance
        .ensureClubChat(source.roomKind, source.roomId,
            unitId: source.unitId, name: source.channelName);
    if (res == null) return null;
    final conversation = res['conversation'];
    if (conversation is! Map) {
      return const RoomOpen(conversationId: '', notMember: true);
    }
    final pinned = res['pinnedMessage'];
    return RoomOpen(
      conversationId: conversation['id']?.toString() ?? '',
      pinned: pinned is Map ? Map<String, dynamic>.from(pinned) : null,
      canPin: res['canPin'] == true,
    );
  }

  /// Pins or unpins a room message. Null result means it failed.
  Future<Map<String, dynamic>?> togglePin(String messageId,
          {required bool pinned}) =>
      BackendApi.instance
          .call('chat.pin', {'messageId': messageId, 'pinned': pinned});

  Future<ChatPage?> _loadDm(
      ChatSource source, String? conversationId, String? ifRev) async {
    if (conversationId == null || conversationId.isEmpty) {
      return ChatPage.empty;
    }
    final answer = await BackendApi.instance.callIfChanged(
        'dm.messages', <String, dynamic>{'conversationId': conversationId},
        ifRev: ifRev);
    if (answer == null) return null;
    if (answer.unchanged) {
      return ChatPage(messages: const [], unchanged: true, rev: answer.rev);
    }
    final res = answer.data ?? const <String, dynamic>{};
    var messages = (res['messages'] as List? ?? [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    // Open sealed envelopes — the words never existed on our servers.
    for (var i = 0; i < messages.length; i++) {
      final raw = messages[i]['text']?.toString() ?? '';
      if (DmCrypto.isEnvelope(raw)) {
        final opened =
            _openEnvelope(messages[i]['id']?.toString() ?? '', raw);
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
      final key = _vaultKey(source, conversationId);
      final stored = await ChatStore.instance.load(key);
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
    // Real read receipts: everything from the peer is marked read while
    // this chat is open (sent once per new incoming message, not per poll).
    if (_needsReadMark(conversationId, messages)) {
      BackendApi.instance.markDmRead(conversationId);
    }
    try {
      final key = _vaultKey(source, conversationId);
      await ChatStore.instance.setMeta(key, {
        'type': 'dm',
        'peerId': source.peerId,
        'title': source.title,
      });
      await ChatStore.instance.replace(key, messages);
      // The conversation earned its real id after the first send — move
      // any peer-keyed history over.
      if (key.startsWith('dm:')) {
        await ChatStore.instance.rename('peer:${source.peerId}', key);
      }
    } catch (_) {}
    return ChatPage(
        messages: messages,
        offline: false,
        serverCount: serverCount,
        rev: answer.rev);
  }

  Future<ChatPage?> _loadRoom(
      ChatSource source, String? conversationId, String? ifRev) async {
    if (conversationId == null || conversationId.isEmpty) return null;
    final answer = await BackendApi.instance.callIfChanged(
        'chat.messages', <String, dynamic>{'conversationId': conversationId},
        ifRev: ifRev);
    if (answer == null) return null;
    if (answer.unchanged) {
      return ChatPage(messages: const [], unchanged: true, rev: answer.rev);
    }
    final res = answer.data ?? const <String, dynamic>{};
    var messages = (res['messages'] as List? ?? [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();

    // Merge restored/older history from the on-device vault.
    final vaultKey = _vaultKey(source, conversationId);
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

    // Resolve sender names/avatars from the device cache (only unknown or
    // old profiles are fetched — cosmetic, never blocks the chat).
    final senderIds = messages
        .map((m) => m['senderId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final people = senderIds.isEmpty
        ? <String, Map<String, dynamic>>{}
        : await ProfileCache.instance.lookup(senderIds);

    try {
      await ChatStore.instance.setMeta(vaultKey, {
        'type': 'club',
        'title': source.title,
      });
      await ChatStore.instance.replace(vaultKey, messages);
    } catch (_) {}

    // Real read receipts: everything from others is marked read while
    // this chat is open (once per new incoming message, not per poll).
    if (_needsReadMark('club:$conversationId', messages)) {
      BackendApi.instance.markClubRead(conversationId);
    }
    return ChatPage(
      messages: messages,
      people: people,
      offline: false,
      serverCount: messages.length,
      rev: answer.rev,
    );
  }

  /// Sends one message. For DMs the text is sealed end-to-end when both
  /// sides support it (otherwise it goes plainly — never a fake lock).
  /// Null result means the send failed.
  Future<Map<String, dynamic>?> send(
    ChatSource source,
    String? conversationId, {
    required String type,
    String text = '',
    String? previewText,
    String? mediaUrl,
    String? fileName,
    int? fileSize,
    String? replyToId,
    bool forwarded = false,
    bool animated = false,
  }) async {
    if (source.flavor == ChatFlavor.dm) {
      var wireText = text;
      if (type == 'text' && (source.peerId ?? '').isNotEmpty) {
        try {
          final sealed =
              await DmCrypto.instance.seal(source.peerId!, wireText);
          if (sealed != null) {
            wireText = sealed;
            previewText = '🔒 Encrypted message';
          }
        } catch (_) {}
      }
      return BackendApi.instance.sendMessage(
        conversationId: conversationId,
        peerId: source.peerId,
        type: type,
        text: wireText,
        previewText: previewText,
        mediaUrl: mediaUrl,
        fileName: fileName,
        fileSize: fileSize,
        replyToId: replyToId,
        forwarded: forwarded,
        animated: animated,
      );
    }
    if (conversationId == null || conversationId.isEmpty) return null;
    return BackendApi.instance.sendClubMessage(
      conversationId: conversationId,
      type: type,
      text: text,
      mediaUrl: mediaUrl,
      fileName: fileName,
      fileSize: fileSize,
      replyToId: replyToId,
      forwarded: forwarded,
      animated: animated,
    );
  }

  Future<Map<String, dynamic>?> react(
          ChatSource source, String messageId, String code) =>
      source.flavor == ChatFlavor.dm
          ? BackendApi.instance.reactDmMessage(messageId, code)
          : BackendApi.instance.reactClubMessage(messageId, code);

  Future<Map<String, dynamic>?> delete(
          ChatSource source, String messageId,
          {required bool forEveryone}) =>
      source.flavor == ChatFlavor.dm
          ? BackendApi.instance
              .deleteDmMessage(messageId, forEveryone: forEveryone)
          : BackendApi.instance
              .deleteClubMessage(messageId, forEveryone: forEveryone);

  /// Uploads a chat photo and returns the hosted URL (null on failure).
  Future<String?> uploadImage(Uint8List bytes, String extension) async {
    final url = await CloudinaryService.uploadImage(
        bytes: bytes, folder: 'chat', extension: extension);
    // The sender keeps the original in the BookNest media folder.
    if (url != null) await MediaStorage.keepSent(url, bytes);
    return url;
  }

  /// Uploads any chat attachment (documents, PDFs, videos, voice notes)
  /// through the private 3-day R2 relay — never Cloudinary — and returns
  /// its download link. [ChatRelay.lastError] explains a null.
  Future<String?> uploadFile(String filename, Uint8List bytes) =>
      ChatRelay.upload(bytes, filename);

  /// Reads a video file for upload. Kept here so screens never touch
  /// the filesystem.
  Future<Uint8List?> readVideoBytes(String path) async {
    try {
      return await File(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }
}
