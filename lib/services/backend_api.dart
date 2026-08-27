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

  /// True once the edge function has answered successfully at least once
  /// during this app session.
  bool get available => _available;

  SupabaseClient get _client => SupabaseService().client;

  /// Calls an action on the edge function. Returns the `data` map on success,
  /// or null on ANY failure (offline, not deployed, backend error).
  Future<Map<String, dynamic>?> call(
    String action, [
    Map<String, dynamic> payload = const <String, dynamic>{},
  ]) async {
    // Fail fast once we know the backend is not reachable yet.
    if (_checked && !_available) return null;
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
        return result is Map ? Map<String, dynamic>.from(result) : <String, dynamic>{};
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

  // ── Direct messages / book sharing ───────────────────────────────────────
  Future<Map<String, dynamic>?> sendMessage({
    String? conversationId,
    String? peerId,
    String type = 'text',
    String text = '',
    String? bookId,
    String? bookTitle,
    String? mediaUrl,
  }) =>
      call('dm.send', <String, dynamic>{
        if (conversationId != null) 'conversationId': conversationId,
        if (peerId != null) 'peerId': peerId,
        'type': type,
        'text': text,
        if (bookId != null) 'bookId': bookId,
        if (bookTitle != null) 'bookTitle': bookTitle,
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
      });

  Future<Map<String, dynamic>?> listConversations() => call('dm.list');

  Future<Map<String, dynamic>?> listMessages(String conversationId) =>
      call('dm.messages', <String, dynamic>{'conversationId': conversationId});

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
