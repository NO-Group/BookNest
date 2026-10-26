import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/backend_api.dart';
import '../services/chat_repository.dart';
import '../services/inbox_watcher.dart';
import '../services/profile_cache.dart';
import '../services/typing_broadcaster.dart';
import '../services/chat_store.dart';
import '../services/chat_relay_service.dart';
import '../services/media_storage.dart';
import '../presentation/screens/chat/voice_recorder_sheet.dart'
    show VoiceNoteResult;

/// ─────────────────────────────────────────────────────────────────────────────
/// The real-time chat engine, packaged as independent Riverpod providers.
/// Nothing here knows what a widget is: streams of messages, optimistic
/// sends, reactions, receipts and the live poll all live OUTSIDE the UI,
/// so any surface — DMs, club rooms, a future mini-preview — hooks the
/// same engine with one watch. New messages rebuild only what watches
/// them, never the whole screen tree.
/// ─────────────────────────────────────────────────────────────────────────────

class ChatState {
  final bool loading;
  final List<Map<String, dynamic>> messages;
  final Map<String, Map<String, dynamic>> people;
  final bool uploading;
  final bool cloudOffline;
  final bool notMember;

  /// The live conversation id (a DM earns it on first send; a room gets
  /// it when the room opens).
  final String? conversationId;

  /// Room only: the pinned message and whether the viewer may pin.
  final Map<String, dynamic>? pinned;
  final bool canPin;

  /// Bumps whenever the list first loads or grows — the one thing a
  /// scrolling surface needs to react to (jump to the newest message).
  final int revision;

  const ChatState({
    this.loading = true,
    this.messages = const [],
    this.people = const {},
    this.uploading = false,
    this.cloudOffline = false,
    this.notMember = false,
    this.conversationId,
    this.pinned,
    this.canPin = false,
    this.revision = 0,
  });

  ChatState copyWith({
    bool? loading,
    List<Map<String, dynamic>>? messages,
    Map<String, Map<String, dynamic>>? people,
    bool? uploading,
    bool? cloudOffline,
    bool? notMember,
    String? conversationId,
    bool clearConversation = false,
    Map<String, dynamic>? pinned,
    bool clearPinned = false,
    bool? canPin,
    int? revision,
  }) {
    return ChatState(
      loading: loading ?? this.loading,
      messages: messages ?? this.messages,
      people: people ?? this.people,
      uploading: uploading ?? this.uploading,
      cloudOffline: cloudOffline ?? this.cloudOffline,
      notMember: notMember ?? this.notMember,
      conversationId:
          clearConversation ? null : (conversationId ?? this.conversationId),
      pinned: clearPinned ? null : (pinned ?? this.pinned),
      canPin: canPin ?? this.canPin,
      revision: revision ?? this.revision,
    );
  }
}

/// One live conversation. Auto-disposed when the last watcher leaves the
/// screen — the poll timer dies with it, nothing leaks.
class ChatController extends AutoDisposeFamilyNotifier<ChatState, ChatSource> {
  Timer? _poll;
  String? _conversationId;
  int _lastCount = -1;
  String? _watching;
  bool _disposed = false;

  /// Fingerprint of the page on screen; polls send it so an unchanged
  /// conversation costs a few bytes instead of the whole page.
  String? _rev;

  /// Polls in a row that found nothing new — the poll slows down while a
  /// chat is quiet and snaps back to 3 s on any activity.
  int _quietPolls = 0;
  bool _polling = false;

  String? get conversationId => _conversationId;

  @override
  ChatState build(ChatSource arg) {
    _conversationId = arg.conversationId;
    _lastCount = -1;
    _rev = null;
    _quietPolls = 0;
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _poll?.cancel();
      _poll = null;
      final watching = _watching;
      if (watching != null) {
        InboxWatcher.instance.leave(watching);
        TypingBroadcaster.instance.leave();
      }
    });
    // The heartbeat lives HERE, not in a widget, so the screen tree never
    // has to rebuild itself to stay current. It is rev-checked (unchanged
    // = a few bytes), adaptive (3 s while active, up to 15 s when quiet)
    // and paused while the app is in the background.
    _schedulePoll();
    Future.microtask(() => _open());
    return const ChatState();
  }

  Duration get _pollDelay {
    if (_quietPolls < 10) return const Duration(seconds: 3); // ~30 s
    if (_quietPolls < 30) return const Duration(seconds: 6); // ~2 min
    return const Duration(seconds: 15);
  }

  void _schedulePoll() {
    _poll?.cancel();
    if (_disposed) return;
    _poll = Timer(_pollDelay, () async {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      final foreground =
          lifecycle == null || lifecycle == AppLifecycleState.resumed;
      if (foreground && !_polling) {
        _polling = true;
        try {
          await _pull(fromTimer: true);
        } catch (_) {
        } finally {
          _polling = false;
        }
      }
      _schedulePoll();
    });
  }

  ChatSource get _source => arg;

  /// DMs start loading straight away; rooms open first (the server
  /// creates or reuses the group conversation and answers with its id).
  Future<void> _open() async {
    if (_source.flavor == ChatFlavor.room) {
      if (!_source.isMember) {
        state = state.copyWith(loading: false, notMember: true);
        return;
      }
      final open = await ChatRepository.instance.ensureRoom(_source);
      if (open == null) {
        state = state.copyWith(loading: false, cloudOffline: true);
        return;
      }
      if (open.notMember) {
        state = state.copyWith(loading: false, notMember: true);
        return;
      }
      _conversationId = open.conversationId;
      state = state.copyWith(
        conversationId: open.conversationId,
        pinned: open.pinned,
        canPin: open.canPin,
      );
    }
    // Paint the conversation as this device last saw it — instantly —
    // then let the first server answer replace it.
    final cached = await ChatRepository.instance.cached(_source, _conversationId);
    if (cached != null && state.messages.isEmpty && !_disposed) {
      state = state.copyWith(
        loading: false,
        messages: cached.messages,
        people: cached.people,
        conversationId: _conversationId,
        revision: state.revision + 1,
      );
    }
    await refresh();
  }

  /// Receipt/typing watchers follow the live conversation id — in here,
  /// so any surface using the engine gets them for free.
  void _syncWatchers() {
    final id = _conversationId;
    if (id == null || id.isEmpty || id == _watching) return;
    final previous = _watching;
    _watching = id;
    if (previous != null) InboxWatcher.instance.leave(previous);
    InboxWatcher.instance.enter(id);
    TypingBroadcaster.instance.enter(id, myId: ChatRepository.instance.viewerId);
  }

  /// Pulls the conversation through the repository and publishes it.
  Future<void> refresh({bool quiet = false}) => _pull(fromTimer: false);

  Future<void> _pull({required bool fromTimer}) async {
    if (_source.flavor == ChatFlavor.room &&
        (_conversationId ?? '').isEmpty) {
      return; // the room is still opening — the open flow will load it
    }
    // Anything but the timer (a send, a reaction, pull-to-refresh) is
    // activity: the poll goes back to its fastest pace.
    if (!fromTimer) _quietPolls = 0;
    final page = await ChatRepository.instance
        .load(_source, _conversationId, ifRev: _rev);
    if (_disposed) return;
    if (page == null) {
      // Cloud unreachable — keep whatever we already show.
      state = state.copyWith(loading: false, cloudOffline: true);
      return;
    }
    if (page.unchanged) {
      _quietPolls++;
      if (state.loading || state.cloudOffline) {
        state = state.copyWith(loading: false, cloudOffline: false);
      }
      return;
    }
    _rev = page.rev;
    _quietPolls = fromTimer ? 0 : _quietPolls;
    final grew = page.serverCount > _lastCount && _lastCount >= 0;
    _lastCount = page.serverCount;
    state = state.copyWith(
      loading: false,
      messages: page.messages,
      people: page.people,
      cloudOffline: false,
      conversationId: _conversationId,
      revision: (grew || state.revision == 0) ? state.revision + 1 : state.revision,
    );
    // Every photo, video, voice note and file is saved to the BookNest
    // media folder on this device (servers keep them 30 days / 3 days).
    MediaStorage.autoSaveFrom(page.messages);
    _syncWatchers();
  }

  void _appendLocal(Map<String, dynamic> message) {
    state = state.copyWith(messages: [...state.messages, message]);
  }

  void _patchLocal(String localId, {required bool failed}) {
    final messages = [
      for (final m in state.messages)
        if (m['id']?.toString() == localId)
          {...m, 'pending': false, 'failed': failed}
        else
          m,
    ];
    state = state.copyWith(messages: messages);
  }

  String get _viewerId => ChatRepository.instance.viewerId;

  Map<String, dynamic> _localDraft({
    required String type,
    String text = '',
    String? mediaUrl,
    String? fileName,
    int? fileSize,
  }) {
    return {
      'id': 'local-${DateTime.now().microsecondsSinceEpoch}',
      'senderId': _viewerId,
      'type': type,
      'text': text,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (fileName != null) 'fileName': fileName,
      if (fileSize != null) 'fileSize': fileSize,
      'createdAt': DateTime.now().toIso8601String(),
      'pending': true,
    };
  }

  /// Sends text. Returns a user-facing notice when the cloud could not
  /// be reached (the message stays, marked failed) — null on success.
  Future<String?> sendText(String text, {String? replyToId}) async {
    if (_source.flavor == ChatFlavor.room &&
        (_conversationId ?? '').isEmpty) {
      return null;
    }
    final draft = _localDraft(type: 'text', text: text);
    _appendLocal(draft);
    final res = await ChatRepository.instance.send(
      _source,
      _conversationId,
      type: 'text',
      text: text,
      replyToId: replyToId,
    );
    if (res == null) {
      _patchLocal(draft['id'].toString(), failed: true);
      return 'Message kept on this device — it syncs once the '
          'BookNest cloud is connected.';
    }
    _conversationId ??= res['conversationId']?.toString() ?? _source.conversationId;
    await refresh(quiet: true);
    return null;
  }

  /// Sends a photo. Returns an error notice, or null on success.
  Future<String?> sendImage(Uint8List bytes, String extension,
      {String? replyToId}) async {
    if (_source.flavor == ChatFlavor.room) return _sendRoomImage(bytes, extension);
    final draft = _localDraft(type: 'image');
    _appendLocal(draft);
    final url = await ChatRepository.instance.uploadImage(bytes, extension);
    if (url == null) {
      _patchLocal(draft['id'].toString(), failed: true);
      return 'The photo could not be uploaded — please try again.';
    }
    final res = await ChatRepository.instance.send(
      _source,
      _conversationId,
      type: 'image',
      mediaUrl: url,
      replyToId: replyToId,
    );
    if (res == null) {
      _patchLocal(draft['id'].toString(), failed: true);
      return 'The photo could not be delivered — please try again.';
    }
    _conversationId ??= res['conversationId']?.toString() ?? _source.conversationId;
    await refresh(quiet: true);
    return null;
  }

  Future<String?> _sendRoomImage(Uint8List bytes, String extension) async {
    if ((_conversationId ?? '').isEmpty) {
      return 'The room is still opening — try again in a moment.';
    }
    state = state.copyWith(uploading: true);
    try {
      final url = await ChatRepository.instance.uploadImage(bytes, extension);
      if (url == null) {
        return 'The photo could not be uploaded — please try again.';
      }
      final res = await ChatRepository.instance.send(
        _source, _conversationId, type: 'image', mediaUrl: url);
      if (res == null) {
        return 'The photo could not be delivered — please try again.';
      }
      await refresh(quiet: true);
      return null;
    } finally {
      state = state.copyWith(uploading: false);
    }
  }

  /// Sends any file. Returns an error notice, or null on success.
  Future<String?> sendFile(String filename, Uint8List bytes,
      {String? replyToId}) async {
    if (_source.flavor == ChatFlavor.room) {
      return _sendRoomFile(filename, bytes);
    }
    final draft = _localDraft(type: 'file', text: filename);
    _appendLocal(draft);
    final url = await ChatRepository.instance.uploadFile(filename, bytes);
    if (url == null) {
      _patchLocal(draft['id'].toString(), failed: true);
      return ChatRelay.lastError ??
          'The file could not be uploaded — please try again.';
    }
    final res = await ChatRepository.instance.send(
      _source,
      _conversationId,
      type: 'file',
      text: filename,
      mediaUrl: url,
      fileName: filename,
      fileSize: bytes.length,
      replyToId: replyToId,
    );
    if (res == null) {
      _patchLocal(draft['id'].toString(), failed: true);
      return 'The file could not be delivered — please try again.';
    }
    _conversationId ??= res['conversationId']?.toString() ?? _source.conversationId;
    await refresh(quiet: true);
    return null;
  }

  Future<String?> _sendRoomFile(String filename, Uint8List bytes) async {
    if ((_conversationId ?? '').isEmpty) {
      return 'The room is still opening — try again in a moment.';
    }
    state = state.copyWith(uploading: true);
    try {
      final url = await ChatRepository.instance.uploadFile(filename, bytes);
      if (url == null) {
        return ChatRelay.lastError ??
          'The file could not be uploaded — please try again.';
      }
      final res = await ChatRepository.instance.send(
        _source,
        _conversationId,
        type: 'file',
        text: filename,
        mediaUrl: url,
        fileName: filename,
        fileSize: bytes.length,
      );
      if (res == null) {
        return 'The file could not be delivered — please try again.';
      }
      await refresh(quiet: true);
      return null;
    } finally {
      state = state.copyWith(uploading: false);
    }
  }

  /// Sends a video from a local path. Returns an error notice, or null.
  Future<String?> sendVideo(String videoPath, {String? replyToId}) async {
    if (_source.flavor == ChatFlavor.room) return _sendRoomVideo(videoPath);
    final size = await _fileSize(videoPath);
    // The draft keeps the local path — the bubble falls back to text
    // styling until the hosted URL replaces it.
    final draft = _localDraft(
        type: 'video', mediaUrl: videoPath, fileName: 'clip.mp4', fileSize: size);
    _appendLocal(draft);
    final bytes = await ChatRepository.instance.readVideoBytes(videoPath);
    if (bytes == null) {
      _patchLocal(draft['id'].toString(), failed: true);
      return 'The video could not be read — please try again.';
    }
    final url = await ChatRepository.instance.uploadFile(
        'clip-${DateTime.now().millisecondsSinceEpoch}.mp4', bytes);
    if (url == null) {
      _patchLocal(draft['id'].toString(), failed: true);
      return ChatRelay.lastError ?? 'The video could not be uploaded — press the message to retry '
          'once your connection is back.';
    }
    final res = await ChatRepository.instance.send(
      _source,
      _conversationId,
      type: 'video',
      mediaUrl: url,
      fileName: 'clip.mp4',
      fileSize: size,
      replyToId: replyToId,
    );
    if (res == null) {
      _patchLocal(draft['id'].toString(), failed: true);
      return null;
    }
    _conversationId ??= res['conversationId']?.toString() ?? _source.conversationId;
    await refresh(quiet: true);
    return null;
  }

  Future<String?> _sendRoomVideo(String videoPath) async {
    if ((_conversationId ?? '').isEmpty) {
      return 'The room is still opening — try again in a moment.';
    }
    state = state.copyWith(uploading: true);
    try {
      final size = await _fileSize(videoPath);
      final bytes = await ChatRepository.instance.readVideoBytes(videoPath);
      if (bytes == null) {
        return 'The video could not be read — please try again.';
      }
      final url = await ChatRepository.instance.uploadFile(
          'clip-${DateTime.now().millisecondsSinceEpoch}.mp4', bytes);
      if (url == null) {
        return ChatRelay.lastError ??
            'The video could not be uploaded — please try again.';
      }
      final res = await ChatRepository.instance.send(
        _source,
        _conversationId,
        type: 'video',
        mediaUrl: url,
        fileName: 'clip.mp4',
        fileSize: size,
      );
      if (res == null) {
        return 'The video could not be delivered — please try again.';
      }
      await refresh(quiet: true);
      return null;
    } finally {
      state = state.copyWith(uploading: false);
    }
  }

  Future<int?> _fileSize(String path) async {
    try {
      return await File(path).length();
    } catch (_) {
      return null;
    }
  }

  /// Sends a voice note. Returns an error notice, or null on success.
  Future<String?> sendVoice(VoiceNoteResult voice, {String? replyToId}) async {
    if (_source.flavor == ChatFlavor.room &&
        (_conversationId ?? '').isEmpty) {
      return null;
    }
    final draft = _localDraft(
        type: 'voice', text: voice.durationLabel, mediaUrl: voice.url);
    _appendLocal(draft);
    final res = await ChatRepository.instance.send(
      _source,
      _conversationId,
      type: 'voice',
      text: voice.durationLabel,
      mediaUrl: voice.url,
      replyToId: replyToId,
    );
    if (res == null) {
      _patchLocal(draft['id'].toString(), failed: true);
      return 'The voice message could not be delivered — please try again.';
    }
    _conversationId ??= res['conversationId']?.toString() ?? _source.conversationId;
    await refresh(quiet: true);
    return null;
  }

  Future<String?> sendEmote(String code, {required bool animated}) async {
    if (_source.flavor == ChatFlavor.room &&
        (_conversationId ?? '').isEmpty) {
      return null;
    }
    final res = await ChatRepository.instance.send(
      _source,
      _conversationId,
      type: 'emoji',
      text: code,
      animated: animated,
    );
    if (res == null) {
      return 'The emote could not be sent — please try again.';
    }
    _conversationId ??= res['conversationId']?.toString() ?? _source.conversationId;
    await refresh(quiet: true);
    return null;
  }

  /// Optimistic reaction with rollback on failure, reconciled with the
  /// server's answer — identical behaviour on both surfaces. Returns
  /// false when the reaction could not be saved.
  Future<bool> react(String messageId, String code) async {
    if (messageId.isEmpty || messageId.startsWith('local-')) return true;
    final viewer = _viewerId;
    if (viewer.isEmpty) return true;
    final idx =
        state.messages.indexWhere((m) => m['id']?.toString() == messageId);
    if (idx == -1) return true;
    final before = Map<String, dynamic>.from(state.messages[idx]);
    final reactions = Map<String, String>.from(
        (state.messages[idx]['reactions'] as Map? ?? {})
            .map((k, v) => MapEntry(k.toString(), v.toString())));
    if (reactions[viewer] == code) {
      reactions.remove(viewer);
    } else {
      reactions[viewer] = code;
    }
    _replaceAt(idx, {...before, 'reactions': reactions});
    final res = await ChatRepository.instance.react(_source, messageId, code);
    if (res == null) {
      _replaceAt(idx, before);
      return false;
    }
    final at =
        state.messages.indexWhere((m) => m['id']?.toString() == messageId);
    if (at == -1) return true;
    final ok = res['reacted'];
    final merged = Map<String, String>.from(
        (state.messages[at]['reactions'] as Map? ?? {})
            .map((k, v) => MapEntry(k.toString(), v.toString())));
    if (ok == false) {
      merged.remove(viewer);
    } else if (ok == true) {
      merged[viewer] = code;
    }
    _replaceAt(at, {...state.messages[at], 'reactions': merged});
    return true;
  }

  void _replaceAt(int index, Map<String, dynamic> message) {
    final messages = [...state.messages];
    messages[index] = message;
    state = state.copyWith(messages: messages);
  }

  /// Pins or unpins a room message. Returns the user-facing result.
  Future<String> togglePin(Map<String, dynamic> message) async {
    final id = message['id']?.toString() ?? '';
    final wasPinned = state.pinned?['id']?.toString() == id;
    final res = await ChatRepository.instance
        .togglePin(id, pinned: !wasPinned);
    if (res == null) return 'Could not update the pin — try again.';
    state = state.copyWith(
      pinned: !wasPinned ? Map<String, dynamic>.from(message) : null,
      clearPinned: wasPinned,
    );
    return wasPinned ? 'Message unpinned.' : 'Message pinned 📌';
  }

  /// Deletes a message. Returns an error notice, or null on success.
  Future<String?> delete(String messageId,
      {required bool forEveryone}) async {
    if (messageId.isEmpty || messageId.startsWith('local-')) return null;
    final res = await ChatRepository.instance
        .delete(_source, messageId, forEveryone: forEveryone);
    if (res == null) {
      return 'The message could not be deleted — please try again.';
    }
    await refresh(quiet: true);
    return null;
  }
}

final chatControllerProvider = NotifierProvider.autoDispose
    .family<ChatController, ChatState, ChatSource>(ChatController.new);

// ── The conversation list (DM inbox) ─────────────────────────────────────────

class ConversationsState {
  final bool loading;
  final bool cloudReady;
  final List<Map<String, dynamic>> conversations;
  final Map<String, Map<String, dynamic>> people;
  final List<Map<String, dynamic>> restored;

  const ConversationsState({
    this.loading = true,
    this.cloudReady = true,
    this.conversations = const [],
    this.people = const {},
    this.restored = const [],
  });

  ConversationsState copyWith({
    bool? loading,
    bool? cloudReady,
    List<Map<String, dynamic>>? conversations,
    Map<String, Map<String, dynamic>>? people,
    List<Map<String, dynamic>>? restored,
  }) {
    return ConversationsState(
      loading: loading ?? this.loading,
      cloudReady: cloudReady ?? this.cloudReady,
      conversations: conversations ?? this.conversations,
      people: people ?? this.people,
      restored: restored ?? this.restored,
    );
  }
}

/// The DM inbox, outside any widget — the list every chat entry point
/// can reuse.
class ConversationsController extends AutoDisposeNotifier<ConversationsState> {
  @override
  ConversationsState build() {
    Future.microtask(() => refresh(fresh: false));
    // The inbox sweep (every 30 s) or a background refresh found a change
    // — repaint from the cache, no extra request.
    final sub = BackendApi.instance.cacheUpdates
        .where((action) => action == 'dm.list')
        .listen((_) => refresh(fresh: false));
    ref.onDispose(sub.cancel);
    return const ConversationsState();
  }

  /// [fresh] (pull-to-refresh) asks the server; otherwise the device cache
  /// answers instantly and a rev-checked refresh follows behind it.
  Future<void> refresh({bool fresh = true}) async {
    final res = fresh
        ? await BackendApi.instance.callFresh('dm.list')
        : await BackendApi.instance.listConversations();
    if (res == null) {
      state = state.copyWith(loading: false, cloudReady: false);
      return;
    }
    final conversations = (res['conversations'] as List? ?? [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    final peerIds = conversations
        .map((c) => c['peerId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    // Fold in conversations that live only in this device's vault (they
    // are older than the server's sync window — restored from backup).
    final serverIds = conversations
        .map((c) => c['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final restoredOnly = <Map<String, dynamic>>[];
    for (final key in ChatStore.instance.conversationIds) {
      if (!key.startsWith('dm:')) continue;
      final id = key.substring(3);
      if (serverIds.contains(id)) continue;
      final meta = ChatStore.instance.meta(key) ?? const {};
      final peerId = meta['peerId']?.toString() ?? '';
      final last = ChatStore.instance.lastMessage(key);
      if (last == null) continue;
      restoredOnly.add({
        'id': id,
        'peerId': peerId,
        'restored': true,
        'lastMessage': {
          'senderId': last['senderId']?.toString() ?? '',
          'type': last['type']?.toString() ?? 'text',
          'text': last['text']?.toString() ?? '',
          'createdAt': last['createdAt']?.toString() ?? '',
        },
        'updatedAt': last['createdAt']?.toString() ?? '',
      });
      if (peerId.isNotEmpty) peerIds.add(peerId);
    }
    restoredOnly.sort((a, b) {
      final at = DateTime.tryParse(a['updatedAt'] ?? '');
      final bt = DateTime.tryParse(b['updatedAt'] ?? '');
      if (at == null || bt == null) return 0;
      return bt.compareTo(at);
    });
    // Paint now with the names we already know; fill in the rest after.
    final known = ProfileCache.instance.peek(peerIds);
    state = state.copyWith(
      loading: false,
      cloudReady: true,
      conversations: conversations,
      people: known,
      restored: restoredOnly,
    );
    if (known.length < peerIds.length || fresh) {
      final people = await ProfileCache.instance.lookup(peerIds);
      state = state.copyWith(people: people);
    }
  }
}

final conversationsProvider = NotifierProvider.autoDispose<
        ConversationsController, ConversationsState>(
    ConversationsController.new);
