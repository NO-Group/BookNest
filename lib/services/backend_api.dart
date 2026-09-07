import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import 'supabase_service.dart';

/// Client for the `booknest-api` Supabase Edge Function — the single gateway
/// to MongoDB Atlas (books, chapters, likes, saves, views, reviews, follows,
/// direct messages, notifications).
///
/// GRACEFUL DEGRADATION — important design decision:
/// Until you deploy the edge function (backend/README.md), every call fails
/// fast and [available] stays false. Screens keep their local/session-only
/// behaviour with zero crashes and zero error popups. Once you deploy the
/// function, the exact same calls start persisting to MongoDB — no app
/// changes and no app release required.
///
/// OPTIMISTIC UI CONTRACT (per backend blueprint): callers update the UI
/// immediately, then fire-and-forget the network call here. Failures are
/// swallowed and logged — never surfaced as blocking dialogs.
class BackendApi {
  BackendApi._();
  static final BackendApi instance = BackendApi._();

  bool _checked = false;
  bool _available = false;

  // ── EphemCache: short-lived read-through cache for list reads. ──────
  // Feeds, shelves and inboxes answer from memory for 60 seconds, so
  // screens snap open instantly and the network breathes. Any write in
  // the same domain drops the cache so fresh data is never hidden.
  static const Duration _cacheTtl = Duration(seconds: 60);
  static const Set<String> _cacheable = {
    'posts.list',
    'books.list',
    'dm.list',
    'chat.rooms',
    'notifications.list',
    'reviews.list',
  };
  static const Map<String, String> _cacheDomain = {
    'posts.list': 'posts',
    'posts.view': 'posts',
    'posts.reshare': 'posts',
    'posts.comments.create': 'posts',
    'books.list': 'books',
    'books.publish': 'books',
    'books.update': 'books',
    'books.remix': 'books',
    'books.updateChapter': 'books',
    'books.addChapter': 'books',
    'dm.list': 'chats',
    'dm.send': 'chats',
    'dm.react': 'chats',
    'chat.send': 'chats',
    'chat.react': 'chats',
    'chat.rooms': 'chats',
    'notifications.list': 'notifications',
    'reviews.list': 'books',
    'reviews.create': 'books',
  };
  final Map<String, ({Map<String, dynamic> data, DateTime at})> _cache = {};

  String _cacheKey(String action, Map<String, dynamic> payload) {
    if (payload.isEmpty) return action;
    final flat = payload.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return '$action?' +
        flat
            .map((e) => '${e.key}=${e.value?.toString() ?? ''}')
            .join('&');
  }

  /// Drops cached reads — used after writes and by pull-to-refresh.
  void bustCache([String? domain]) {
    if (domain == null) {
      _cache.clear();
      return;
    }
    _cache.removeWhere(
        (key, _) => _cacheDomain[key.split('?')[0]] == domain);
  }

  /// Force-bypasses the cache for the next read (pull-to-refresh).
  Future<Map<String, dynamic>?> callFresh(String action,
          [Map<String, dynamic> payload = const <String, dynamic>{}]) {
    _cache.remove(_cacheKey(action, payload));
    return call(action, payload);
  }

  /// True once the edge function has answered successfully at least once
  /// during this app session.
  bool get available => _available;

  /// Actively re-checks whether the edge backend is live right now
  /// (ignores the cached fail-fast state). Used by the profile screen's
  /// "cloud status" chip so deployment success is visible in the app.
  Future<bool> probe() async {
    _checked = false;
    _available = false;
    final res = await call('ping');
    return res != null;
  }

  SupabaseClient get _client => SupabaseService().client;

  /// Calls an action on the edge function. Returns the `data` map on success,
  /// or null on ANY failure (offline, not deployed, backend error).
  Future<Map<String, dynamic>?> call(
    String action, [
    Map<String, dynamic> payload = const <String, dynamic>{},
  ]) async {
    // Fail fast once we know the backend is not reachable yet.
    if (_checked && !_available) return null;
    final key = _cacheKey(action, payload);
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.at) < _cacheTtl) {
      return cached.data;
    }
    try {
      final response = await _client.functions.invoke(
        AppConfig.edgeFunctionName,
        body: <String, dynamic>{'action': action, 'payload': payload},
      );
      final data = response.data;
      if (data is Map && data['ok'] == true) {
        _available = true;
        _checked = true;
        final result = data['data'];
        final value = result is Map
            ? Map<String, dynamic>.from(result)
            : <String, dynamic>{};
        if (_cacheable.contains(action)) {
          _cache[key] = (data: value, at: DateTime.now());
        }
        final domain = _cacheDomain[action];
        if (domain != null && !_cacheable.contains(action)) {
          _cache.removeWhere(
              (k, _) => _cacheDomain[k.split('?')[0]] == domain);
        }
        return value;
      }
      _checked = true;
      if (kDebugMode) {
        debugPrint('booknest-api($action) rejected: '
            '${data is Map ? data['error'] : 'malformed response'}');
      }
      return null;
    } catch (error) {
      _checked = true;
      if (kDebugMode) debugPrint('booknest-api($action) unavailable: $error');
      return null;
    }
  }

  // ── Books ─────────────────────────────────────────────────────────────────
  Future<void> setLike(String bookId, bool liked) =>
      call('books.like', <String, dynamic>{'bookId': bookId, 'liked': liked});

  Future<void> setBookmark(String bookId, bool saved) =>
      call('books.bookmark', <String, dynamic>{'bookId': bookId, 'saved': saved});

  /// Counts at most one view per user per day (enforced in MongoDB by a
  /// unique index — repeated calls are free).
  Future<void> recordView(String bookId) =>
      call('books.view', <String, dynamic>{'bookId': bookId});

  Future<Map<String, dynamic>?> fetchBook(String bookId) =>
      call('books.get', <String, dynamic>{'bookId': bookId});

  Future<Map<String, dynamic>?> fetchChapter(String bookId, int chapterNumber) =>
      call('books.chapter', <String, dynamic>{
        'bookId': bookId,
        'chapterNumber': chapterNumber,
      });

  // ── Reviews ───────────────────────────────────────────────────────────────
  /// One editable review per user per book (unique index server-side).
  Future<void> createReview(
    String bookId,
    int rating,
    String body, {
    String displayName = 'Reader',
  }) =>
      call('reviews.create', <String, dynamic>{
        'bookId': bookId,
        'rating': rating,
        'body': body,
        'displayName': displayName,
      });

  // ── Social graph ──────────────────────────────────────────────────────────
  Future<void> setFollowing(String userId, bool following) =>
      call('social.follow', <String, dynamic>{'userId': userId, 'following': following});

  Future<Map<String, dynamic>?> fetchUserStats(String userId) =>
      call('users.get', <String, dynamic>{'userId': userId});

  /// type: 'followers' | 'following' → { userIds: [...] }
  Future<Map<String, dynamic>?> listSocial(String userId, {required String type}) =>
      call('social.list', <String, dynamic>{'userId': userId, 'type': type});

  Future<void> savePreferences(List<String> genres) =>
      call('users.preferences', <String, dynamic>{'genres': genres});

  // ── Author tools ──────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> updateBook({
    required String bookId,
    String? title,
    String? description,
    String? genre,
    String? coverUrl,
  }) =>
      call('books.update', <String, dynamic>{
        'bookId': bookId,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (genre != null) 'genre': genre,
        if (coverUrl != null) 'coverUrl': coverUrl,
      });

  Future<Map<String, dynamic>?> bookStats(String bookId) =>
      call('books.stats', <String, dynamic>{'bookId': bookId});

  Future<Map<String, dynamic>?> bookmarkedBooks() => call('books.bookmarked');

  Future<Map<String, dynamic>?> saveChapter({
    required String bookId,
    required int chapterNumber,
    required String title,
    required String content,
  }) =>
      call('chapters.save', <String, dynamic>{
        'bookId': bookId,
        'chapterNumber': chapterNumber,
        'title': title,
        'content': content,
      });

  Future<void> deleteChapter({required String bookId, required int chapterNumber}) =>
      call('chapters.delete', <String, dynamic>{
        'bookId': bookId,
        'chapterNumber': chapterNumber,
      });

  Future<void> deleteReview(String bookId) =>
      call('reviews.delete', <String, dynamic>{'bookId': bookId});

  // ── Comments / discussions ────────────────────────────────────────────────
  Future<Map<String, dynamic>?> postComment({
    required String bookId,
    required String body,
    String displayName = 'Reader',
  }) =>
      call('comments.create', <String, dynamic>{
        'bookId': bookId,
        'body': body,
        'displayName': displayName,
      });

  Future<Map<String, dynamic>?> listComments(String bookId) =>
      call('comments.list', <String, dynamic>{'bookId': bookId});

  // ── Moderation ────────────────────────────────────────────────────────────
  Future<void> reportContent({
    required String targetType,
    required String targetId,
    required String reason,
    String details = '',
  }) =>
      call('moderation.report', <String, dynamic>{
        'targetType': targetType,
        'targetId': targetId,
        'reason': reason,
        'details': details,
      });

  // ── Direct messages / book sharing ───────────────────────────────────────
  Future<Map<String, dynamic>?> sendMessage({
    String? conversationId,
    String? peerId,
    String type = 'text',
    String text = '',
    String? bookId,
    String? bookTitle,
    String? mediaUrl,
    String? fileName,
    int? fileSize,
    bool forwarded = false,
    bool animated = false,
    String? replyToId,
  }) =>
      call('dm.send', <String, dynamic>{
        if (conversationId != null) 'conversationId': conversationId,
        if (peerId != null) 'peerId': peerId,
        'type': type,
        'text': text,
        if (replyToId != null) 'replyToId': replyToId,
        if (bookId != null) 'bookId': bookId,
        if (bookTitle != null) 'bookTitle': bookTitle,
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
        if (fileName != null) 'fileName': fileName,
        if (fileSize != null) 'fileSize': fileSize,
        if (forwarded) 'forwarded': true,
        if (animated) 'animated': true,
      });

  Future<Map<String, dynamic>?> listConversations() => call('dm.list');

  /// Creates (or reuses) the 1:1 conversation with [peerId].
  Future<Map<String, dynamic>?> ensureConversation(String peerId) =>
      call('dm.ensure', <String, dynamic>{'peerId': peerId});

  Future<Map<String, dynamic>?> listMessages(String conversationId) =>
      call('dm.messages', <String, dynamic>{'conversationId': conversationId});

  // ── Club group chat ─────────────────────────────────────────────────────
  /// Opens (or reuses) the membership-gated room for a group.
  Future<Map<String, dynamic>?> ensureClubChat(String kind, String clubId) =>
      call('chat.ensure', <String, dynamic>{'kind': kind, 'clubId': clubId});

  Future<Map<String, dynamic>?> sendClubMessage({
    required String conversationId,
    String type = 'text',
    String text = '',
    String? mediaUrl,
    String? fileName,
    int? fileSize,
    bool forwarded = false,
    bool animated = false,
    String? replyToId,
  }) =>
      call('chat.send', <String, dynamic>{
        'conversationId': conversationId,
        'type': type,
        'text': text,
        if (replyToId != null) 'replyToId': replyToId,
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
        if (fileName != null) 'fileName': fileName,
        if (fileSize != null) 'fileSize': fileSize,
        if (forwarded) 'forwarded': true,
        if (animated) 'animated': true,
      });

  Future<Map<String, dynamic>?> listClubMessages(String conversationId) =>
      call('chat.messages', <String, dynamic>{'conversationId': conversationId});

  // ── message toolkit: reactions, deletes, read receipts, forwarding ────────

  Future<Map<String, dynamic>?> reactDmMessage(String messageId, String emoji) =>
      call('dm.react', <String, dynamic>{'messageId': messageId, 'emoji': emoji});

  Future<Map<String, dynamic>?> reactClubMessage(String messageId, String emoji) =>
      call('chat.react', <String, dynamic>{'messageId': messageId, 'emoji': emoji});

  Future<Map<String, dynamic>?> deleteDmMessage(String messageId,
          {required bool forEveryone}) =>
      call('dm.deleteMessage',
          <String, dynamic>{'messageId': messageId, 'forEveryone': forEveryone});

  Future<Map<String, dynamic>?> deleteClubMessage(String messageId,
          {required bool forEveryone}) =>
      call('chat.deleteMessage',
          <String, dynamic>{'messageId': messageId, 'forEveryone': forEveryone});

  Future<Map<String, dynamic>?> markDmRead(String conversationId) =>
      call('dm.read', <String, dynamic>{'conversationId': conversationId});

  Future<Map<String, dynamic>?> markClubRead(String conversationId) =>
      call('chat.read', <String, dynamic>{'conversationId': conversationId});

  /// The reader's club/group rooms (forward targets).
  Future<Map<String, dynamic>?> listClubChatRooms() => call('chats.list');

  // ── reader profile: country, gender, languages ─────────────────────────────

  Future<Map<String, dynamic>?> saveUserProfile({
    String? country,
    String? countryCode,
    String? gender,
    List<Map<String, String>>? languages,
    String? preferredLanguage,
  }) =>
      call('users.profile.save', <String, dynamic>{
        if (country != null) 'country': country,
        if (countryCode != null) 'countryCode': countryCode,
        if (gender != null) 'gender': gender,
        if (languages != null)
          'languages': [for (final l in languages) {'code': l['code'], 'level': l['level']}],
        if (preferredLanguage != null) 'preferredLanguage': preferredLanguage,
      });

  /// Own profile when [userId] is null; otherwise the public part of
  /// another reader's profile (country + gender).
  Future<Map<String, dynamic>?> fetchUserProfile({String? userId}) =>
      call('users.profile.get', <String, dynamic>{
        if (userId != null) 'userId': userId,
      });

  Future<Map<String, dynamic>?> translateText(String text, String target) =>
      call('translate.text', <String, dynamic>{'text': text, 'target': target});

  Future<Map<String, dynamic>?> mediaStatus() => call('media.status');

  /// Shares a book profile card into the 1:1 conversation with [peerId]
  /// (creates or reuses the conversation server-side).
  Future<Map<String, dynamic>?> shareBook({
    required String bookId,
    required String bookTitle,
    required String peerId,
  }) =>
      sendMessage(
        peerId: peerId,
        type: 'book_share',
        text: bookTitle,
        bookId: bookId,
        bookTitle: bookTitle,
      );
}
