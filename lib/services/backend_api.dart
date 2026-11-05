import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import 'chapter_cache.dart';
import 'profile_cache.dart';
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

  bool _available = false;

  /// The server's own words for the most recent refused call (e.g.
  /// "Already on the reading list"), so screens can say what went wrong
  /// instead of a generic "try again". Null after a successful call.
  String? lastError;

  /// [lastError] or [fallback] — for snackbars.
  String errorOr(String fallback) {
    final e = lastError?.trim() ?? '';
    return e.isEmpty ? fallback : e;
  }

  /// Set only when the server could not be reached AT ALL (no answer).
  /// Calls then fail fast for a short cool-down — never for the rest of
  /// the session. (Before 2.33 one refused or timed-out call, e.g. "Sign
  /// in required" while the session was still restoring, switched the
  /// backend off until restart, and screens showed "Something went
  /// wrong".)
  DateTime? _downSince;
  static const Duration _downCooldown = Duration(seconds: 12);

  /// Read-only actions are safe to retry once after a transient failure
  /// (cold start, flaky network). Writes are never retried — a lost
  /// response must not send a message twice.
  static final RegExp _readOnly = RegExp(
      r'^ping$|\.(list|get|chapter|chapters|search|mine|stats|status|queue|lookup|trending|feed|me|profile|messages|rooms|ice|preview|summary|history|catalog|leaderboard|allowance|reminders)$');

  /// Edge-runtime "try again" statuses (boot error, gateway, worker limit).
  static bool _transient(int status) =>
      status == 502 || status == 503 || status == 504 || status == 546;

  void _markUp() {
    _available = true;
    _downSince = null;
  }

  // ── Response cache: memory + disk, stale-while-revalidate, rev-checked ──
  // A seen answer is shown instantly — also right after a cold start,
  // because cacheable answers are kept on disk per account. Fresh entries
  // (60 s) skip the network entirely; older ones answer instantly and a
  // quiet background refresh follows. Refreshes send the answer's
  // fingerprint (rev), so when nothing changed the server replies with a
  // few bytes instead of the whole list — that is what keeps egress low.
  // Writes drop the related entries so fresh data is never hidden.
  static const Duration _cacheTtl = Duration(seconds: 60);
  static const Duration _staleTtl = Duration(days: 7);
  static const int _diskMaxEntries = 250;
  static const int _diskMaxEntryChars = 400000;
  final Set<String> _revalidating = {};
  static const Set<String> _cacheable = {
    'posts.list',
    'books.list',
    'books.get',
    'dm.list',
    'chats.list',
    'chat.rooms',
    'notifications.list',
    'reviews.list',
    'groups.list',
    'groups.get',
    'groups.units.list',
    'groups.announcements.list',
    'brainstorm.list',
    'social.list',
    'wallet.catalog',
    'profile.mode.get',
  };
  static const Map<String, String> _cacheDomain = {
    'posts.list': 'posts',
    'posts.reshare': 'posts',
    'posts.comments.create': 'posts',
    'books.list': 'books',
    'books.get': 'books',
    'books.publish': 'books',
    'books.update': 'books',
    'books.remix': 'books',
    'books.updateChapter': 'books',
    'books.addChapter': 'books',
    'dm.list': 'chats',
    'dm.send': 'chats',
    'dm.react': 'chats',
    'dm.deleteMessage': 'chats',
    'dm.read': 'chats',
    'dm.ensure': 'chats',
    'dm.block': 'chats',
    'dm.unblock': 'chats',
    'chat.send': 'chats',
    'chat.react': 'chats',
    'chat.deleteMessage': 'chats',
    'chat.read': 'chats',
    'chat.ensure': 'chats',
    'chat.pin': 'chats',
    'chat.rooms': 'chats',
    'chats.list': 'chats',
    'notifications.list': 'notifications',
    'reviews.list': 'books',
    'reviews.create': 'books',
  };

  /// Frequent writes that change nothing a cached list shows.
  static const Set<String> _quietWrites = {
    'books.view',
    'posts.view',
    'streak.log',
    'reader.progress.save',
    'me.heartbeat',
    'me.syncPhone',
    'push.register',
    'push.unregister',
  };

  final Map<String, _CacheEntry> _cache = {};
  final StreamController<String> _updates = StreamController<String>.broadcast();

  /// Emits the action name whenever a background refresh brought NEW
  /// data for it — screens listen and repaint from the (now fresh) cache.
  Stream<String> get cacheUpdates => _updates.stream;

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
    } else {
      _cache.removeWhere(
          (key, _) => _cacheDomain[key.split('?')[0]] == domain);
    }
    _scheduleSave();
  }

  void _bustFor(String action) {
    if (_quietWrites.contains(action)) return;
    final domain = _cacheDomain[action];
    final prefix = action.split('.').first;
    final before = _cache.length;
    _cache.removeWhere((key, _) {
      final cachedAction = key.split('?')[0];
      return (domain != null && _cacheDomain[cachedAction] == domain) ||
          cachedAction.split('.').first == prefix;
    });
    if (_cache.length != before) _scheduleSave();
  }

  void _store(String key, Map<String, dynamic> data, String? rev) {
    _cache[key] = _CacheEntry(data, DateTime.now(), rev);
    _scheduleSave();
  }

  // ── disk side (one JSON file per account, app-private storage) ──────
  String? _diskOwner;
  Future<void>? _diskLoading;
  Timer? _saveTimer;
  StreamSubscription<AuthState>? _authSub;

  Future<void> _ensureDisk() async {
    _authSub ??= _client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedOut) {
        unawaited(clearCache());
      }
    });
    final uid = _client.auth.currentUser?.id ?? '';
    if (uid != _diskOwner) {
      _cache.clear();
      _diskOwner = uid;
      _diskLoading = uid.isEmpty ? Future<void>.value() : _loadDisk(uid);
    }
    await _diskLoading;
  }

  Future<File> _diskFile(String uid) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/api_cache');
    await dir.create(recursive: true);
    final safe = uid.replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '_');
    return File('${dir.path}/$safe.json');
  }

  Future<void> _loadDisk(String uid) async {
    try {
      final file = await _diskFile(uid);
      if (!await file.exists()) return;
      final decoded = await compute(_decodeJson, await file.readAsString());
      if (decoded is! Map || decoded['v'] != 1) return;
      final entries = decoded['entries'];
      if (entries is! Map || _diskOwner != uid) return;
      entries.forEach((key, value) {
        if (value is! Map || value['data'] is! Map) return;
        final k = key.toString();
        if (_cache.containsKey(k)) return;
        _cache[k] = _CacheEntry(
          Map<String, dynamic>.from(value['data'] as Map),
          DateTime.fromMillisecondsSinceEpoch(
              (value['at'] as num?)?.toInt() ?? 0),
          value['rev']?.toString(),
        );
      });
    } catch (_) {
      // A damaged cache file is simply ignored (and rewritten later).
    }
  }

  void _scheduleSave() {
    final uid = _diskOwner;
    if (uid == null || uid.isEmpty) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 3), () => _saveDisk(uid));
  }

  Future<void> _saveDisk(String uid) async {
    if (uid != _diskOwner) return;
    try {
      final rows = _cache.entries
          .where((e) => _cacheable.contains(e.key.split('?')[0]))
          .toList()
        ..sort((a, b) => b.value.at.compareTo(a.value.at));
      final entries = <String, dynamic>{};
      for (final row in rows.take(_diskMaxEntries)) {
        entries[row.key] = {
          'data': row.value.data,
          'at': row.value.at.millisecondsSinceEpoch,
          if (row.value.rev != null) 'rev': row.value.rev,
        };
      }
      final text = await compute(_encodeCache, entries);
      final file = await _diskFile(uid);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      // Disk full or read-only — the memory cache still works.
    }
  }

  /// Forgets every cached answer (memory and disk) — on sign-out.
  Future<void> clearCache() async {
    _saveTimer?.cancel();
    _cache.clear();
    unawaited(ProfileCache.instance.clear());
    unawaited(ChapterCache.instance.clear());
    _diskOwner = null;
    _diskLoading = null;
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/api_cache');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  /// Network read that bypasses the fresh window (pull-to-refresh, the
  /// inbox sweep). Still rev-checked: an unchanged answer costs a few bytes.
  Future<Map<String, dynamic>?> callFresh(String action,
      [Map<String, dynamic> payload = const <String, dynamic>{}]) async {
    final cacheable = _cacheable.contains(action);
    if (!cacheable) return call(action, payload);
    await _ensureDisk();
    final key = _cacheKey(action, payload);
    final cached = _cache[key];
    final answer = await _invoke(action, payload,
        wantRev: true, ifRev: cached?.rev);
    if (answer == null) return null;
    return _absorb(action, key, cached, answer);
  }

  /// Folds a network answer into the cache; returns the data to show.
  Map<String, dynamic>? _absorb(
      String action, String key, _CacheEntry? cached, _Answer answer) {
    if (answer.unchanged) {
      if (cached == null) return null;
      cached.at = DateTime.now();
      _scheduleSave();
      return cached.data;
    }
    final changed = cached == null || cached.rev == null || cached.rev != answer.rev;
    _store(key, answer.data, answer.rev);
    if (changed && cached != null) _updates.add(action);
    return answer.data;
  }

  /// Polling helper (open chats): sends the last fingerprint and reports
  /// `unchanged` instead of downloading the same page again. Null = failed.
  Future<({Map<String, dynamic>? data, bool unchanged, String? rev})?>
      callIfChanged(String action, Map<String, dynamic> payload,
          {String? ifRev}) async {
    final down = _downSince;
    if (down != null && DateTime.now().difference(down) < _downCooldown) {
      return null;
    }
    final answer = await _invoke(action, payload, wantRev: true, ifRev: ifRev);
    if (answer == null) return null;
    return (
      data: answer.unchanged ? null : answer.data,
      unchanged: answer.unchanged,
      rev: answer.rev,
    );
  }

  /// Quietly refreshes a stale cache entry in the background. Failures
  /// are silent — the reader simply keeps seeing the last good answer.
  void _revalidate(
      String action, Map<String, dynamic> payload, String key) {
    if (_revalidating.contains(key)) return;
    _revalidating.add(key);
    () async {
      try {
        final cached = _cache[key];
        final answer = await _invoke(action, payload,
            wantRev: true, ifRev: cached?.rev, quiet: true);
        if (answer != null) _absorb(action, key, cached, answer);
      } catch (_) {
        // Keep the stale answer; try again next call.
      } finally {
        _revalidating.remove(key);
      }
    }();
  }

  /// True once the edge function has answered successfully at least once
  /// during this app session.
  bool get available => _available;

  /// Actively re-checks whether the edge backend is live right now
  /// (ignores the cached fail-fast state). Used by the profile screen's
  /// "cloud status" chip so deployment success is visible in the app.
  Future<bool> probe() async {
    _available = false;
    _downSince = null;
    final res = await call('ping');
    return res != null;
  }

  /// Deployment check: is the server reachable AND does the deployed edge
  /// speak this app's contract? New servers declare `server` in `ping`;
  /// an old deployment answers without it — which is exactly the "you
  /// pasted an older index.ts" tell the maintenance banner needs.
  Future<({bool reachable, bool upToDate})> serverStatus() async {
    _available = false;
    _downSince = null;
    final res = await call('ping');
    if (res == null) return (reachable: false, upToDate: false);
    // Any server at or above the contract this app needs is current
    // (was an exact '2.24' match, so newer servers looked "outdated").
    return (
      reachable: true,
      upToDate: _versionAtLeast(res['server']?.toString() ?? '', '2.24'),
    );
  }

  static bool _versionAtLeast(String have, String need) {
    List<int> parts(String v) =>
        v.split('.').map((x) => int.tryParse(x) ?? 0).toList();
    final a = parts(have), b = parts(need);
    if (have.isEmpty) return false;
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return true;
  }

  SupabaseClient get _client => SupabaseService().client;

  /// Calls an action on the edge function. Returns the `data` map on success,
  /// or null on ANY failure (offline, not deployed, backend error).
  Future<Map<String, dynamic>?> call(
    String action, [
    Map<String, dynamic> payload = const <String, dynamic>{},
  ]) async {
    final cacheable = _cacheable.contains(action);
    final key = _cacheKey(action, payload);
    _CacheEntry? cached;
    if (cacheable) {
      await _ensureDisk();
      cached = _cache[key];
      if (cached != null) {
        final age = DateTime.now().difference(cached.at);
        if (age < _cacheTtl) return cached.data;
        if (age < _staleTtl) {
          // Stale-while-revalidate: instant answer, quiet refresh behind it.
          _revalidate(action, payload, key);
          return cached.data;
        }
      }
    }
    // Fail fast only during the short cool-down after the server could
    // not be reached at all.
    final down = _downSince;
    if (down != null && DateTime.now().difference(down) < _downCooldown) {
      return cached?.data;
    }
    final answer = await _invoke(action, payload,
        wantRev: cacheable, ifRev: cached?.rev);
    if (answer == null) return cached?.data; // offline: very old beats nothing
    if (cacheable) return _absorb(action, key, cached, answer);
    if (!_readOnly.hasMatch(action)) _bustFor(action);
    return answer.data;
  }

  /// One request to the edge function, with a single retry for reads.
  Future<_Answer?> _invoke(
    String action,
    Map<String, dynamic> payload, {
    bool wantRev = false,
    String? ifRev,
    bool quiet = false,
  }) async {
    final retryable = _readOnly.hasMatch(action);
    final body = <String, dynamic>{
      'action': action,
      'payload': payload,
      if (wantRev) 'wantRev': true,
      if (wantRev && ifRev != null && ifRev.isNotEmpty) 'ifRev': ifRev,
    };
    for (var attempt = 0;; attempt++) {
      try {
        final response = await _client.functions.invoke(
          AppConfig.edgeFunctionName,
          body: body,
        );
        final data = response.data;
        _markUp();
        lastError = data is Map && data['ok'] != true
            ? data['error']?.toString()
            : null;
        if (data is Map && data['ok'] == true) {
          final result = data['data'];
          final value = result is Map
              ? Map<String, dynamic>.from(result)
              : <String, dynamic>{};
          final rev = data['rev']?.toString();
          final unchanged = value['unchanged'] == true && ifRev != null && rev == ifRev;
          return _Answer(value, rev, unchanged);
        }
        if (kDebugMode) {
          debugPrint('booknest-api($action) rejected: '
              '${data is Map ? data['error'] : 'malformed response'}');
        }
        return null;
      } on FunctionException catch (error) {
        // The server ANSWERED (4xx/5xx): it is reachable — only this
        // request was refused. Never switch the backend off for that.
        _markUp();
        final details = error.details;
        lastError = details is Map
            ? details['error']?.toString()
            : (details is String && details.length < 200 ? details : null);
        if (retryable && attempt == 0 && _transient(error.status)) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
          continue;
        }
        if (kDebugMode) {
          debugPrint('booknest-api($action) refused '
              '(${error.status}): ${error.details}');
        }
        return null;
      } catch (error) {
        // No answer at all (offline, DNS, timeout).
        lastError = 'BookNest could not be reached — check your connection.';
        if (retryable && attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 800));
          continue;
        }
        if (!quiet) {
          _available = false;
          _downSince = DateTime.now();
        }
        if (kDebugMode) debugPrint('booknest-api($action) unavailable: $error');
        return null;
      }
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
    String? previewText,
  }) =>
      call('dm.send', <String, dynamic>{
        if (conversationId != null) 'conversationId': conversationId,
        if (peerId != null) 'peerId': peerId,
        'type': type,
        'text': text,
        if (replyToId != null) 'replyToId': replyToId,
        if (previewText != null) 'previewText': previewText,
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
  Future<Map<String, dynamic>?> heartbeat() =>
      call('me.heartbeat', <String, dynamic>{});

  Future<Map<String, dynamic>?> myStatus() =>
      call('me.status', <String, dynamic>{});

  Future<Map<String, dynamic>?> syncPhone(String phone) =>
      call('me.syncPhone', <String, dynamic>{'phone': phone});

  Future<Map<String, dynamic>?> adminInsights() =>
      call('admin.insights', <String, dynamic>{});

  Future<Map<String, dynamic>?> adminUsersList({int page = 1}) =>
      call('admin.users.list', <String, dynamic>{'page': page});

  Future<Map<String, dynamic>?> adminMassMessage({
    required String title,
    required String body,
  }) =>
      call('admin.massMessage', <String, dynamic>{
        'title': title,
        'body': body,
      });

  Future<Map<String, dynamic>?> massLatest() =>
      call('mass.latest', <String, dynamic>{});

  Future<Map<String, dynamic>?> chatShared(String conversationId) =>
      call('chat.shared', <String, dynamic>{'conversationId': conversationId});

  Future<Map<String, dynamic>?> ensureClubChat(String kind, String clubId,
          {String unitId = '', String name = ''}) =>
      call('chat.ensure', <String, dynamic>{
        'kind': kind,
        'clubId': clubId,
        if (unitId.isNotEmpty) 'unitId': unitId,
        if (name.isNotEmpty) 'name': name,
      });

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

  // ── random chat: FIFO pair-up ────────────────────────────────────────────
  Future<Map<String, dynamic>?> randomJoin() => call('random.join');

  Future<Map<String, dynamic>?> randomStatus() => call('random.status');

  Future<Map<String, dynamic>?> randomLeave() => call('random.leave');

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
    int? birthYear,
    List<Map<String, String>>? languages,
    String? preferredLanguage,
  }) =>
      call('users.profile.save', <String, dynamic>{
        if (country != null) 'country': country,
        if (countryCode != null) 'countryCode': countryCode,
        if (gender != null) 'gender': gender,
        if (birthYear != null) 'birthYear': birthYear,
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

class _CacheEntry {
  final Map<String, dynamic> data;
  DateTime at;
  final String? rev;
  _CacheEntry(this.data, this.at, this.rev);
}

class _Answer {
  final Map<String, dynamic> data;
  final String? rev;
  final bool unchanged;
  const _Answer(this.data, this.rev, this.unchanged);
}

Object? _decodeJson(String text) => jsonDecode(text);

String _encodeCache(Map<String, dynamic> entries) =>
    jsonEncode(<String, dynamic>{'v': 1, 'entries': entries});
