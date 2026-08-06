import 'dart:async';

import 'package:flutter/material.dart;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/auth_guard.dart';
import '../../../services/supabase_service.dart';
import '../../../services/reading_session_service.dart';

/// Chapter reader view for a single book.
///
/// Pulls the book metadata from `club_books` and its chapters from
/// `book_chapters` by [bookId], then renders the first chapter's raw Markdown.
/// The bottom action bar (Like, Comment, Share, Bookmark) is strictly guarded
/// by [AuthGuard].
class PublishDetailsScreen extends StatefulWidget {
  final String bookId;

  const PublishDetailsScreen({super.key, required this.bookId});

  @override
  State<PublishDetailsScreen> createState() => _PublishDetailsScreenState();
}

class _PublishDetailsScreenState extends State<PublishDetailsScreen> {
  Map<String, dynamic>? _book;
  Map<String, dynamic>? _chapter;
  bool _isLoading = true;
  String? _error;
  String? _readingSessionId;
  Timer? _readingHeartbeat;
  final _readingSessions = ReadingSessionService();

  @override
  void initState() {
    super.initState();
    _loadBook();
  }

  Future<void> _loadBook() async {
    try {
      final supabase = SupabaseService().client;

      final bookResponse = await supabase
          .from('club_books')
          .select()
          .eq('id', widget.bookId)
          .maybeSingle();

      final chaptersResponse = await supabase
          .from('book_chapters')
          .select()
          .eq('club_book_id', widget.bookId)
          .order('chapter_number', ascending: true);

      if (!mounted) return;

      setState(() {
        _book = bookResponse == null
            ? null
            : Map<String, dynamic>.from(bookResponse);
        _chapter = chaptersResponse.isEmpty
            ? null
            : Map<String, dynamic>.from(chaptersResponse.first as Map);
        _isLoading = false;
        if (_book == null) _error = 'This book could not be found.';
      });
      if (_book != null) unawaited(_startReadingSession());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Could not load this book: $e';
      });
    }
  }

  Future<void> _startReadingSession() async {
    try {
      final sessionId = await _readingSessions.start(widget.bookId);
      if (!mounted || sessionId == null) return;
      setState(() => _readingSessionId = sessionId);
      _readingHeartbeat = Timer.periodic(const Duration(minutes: 2), (_) {
        final active = _readingSessionId;
        if (active != null) unawaited(_readingSessions.heartbeat(active));
      });
    } catch (_) {
      // Reading analytics must never prevent a user from reading a book.
    }
  }

  Future<void> _finishReadingSession() async {
    final sessionId = _readingSessionId;
    if (sessionId == null) return;
    _readingSessionId = null;
    _readingHeartbeat?.cancel();
    try { await _readingSessions.finish(sessionId); } catch (_) {}
  }

  void _guard(ActionHandler action) {
    AuthGuard.run(context, action);
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '';
    try {
      final date = DateTime.parse(raw.toString()).toLocal();
      return DateFormat('MMM d, yyyy').format(date);
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Reading',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
      body: _buildBody(),
      bottomNavigationBar: _book == null ? null : _buildActionBar(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00D4FF)),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 56, color: Color(0xFF444444)),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _loadBook,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final book = _book!;
    final title = (book['title'] as String?) ?? 'Untitled';
    final author = (book['author'] as String?) ?? 'Unknown author';
    final description = (book['description'] as String?) ?? '';
    final chapterTitle = (_chapter?['title'] as String?) ?? 'Chapter';
    final content = (_chapter?['content'] as String?) ?? '';

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF222222))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'by $author',
                style: const TextStyle(color: Color(0xFF888888), fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (chapterTitle.isNotEmpty) chapterTitle,
                  if (_formatDate(book['created_at']).isNotEmpty)
                    'Published ${_formatDate(book['created_at'])}',
                ].join(' · '),
                style: const TextStyle(color: Color(0xFF666666), fontSize: 12),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  description,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.6,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
        Markdown(
      data: content.isEmpty ? '*(No content published yet.)*' : content,
      selectable: true,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      styleSheet: MarkdownStyleSheet(
        h1: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
        h2: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        p: const TextStyle(
          color: Colors.white70,
          fontSize: 16,
          height: 1.7,
        ),
        listBullet: const TextStyle(color: Color(0xFF00D4FF)),
        blockquoteDecoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(8),
          border: const Border(left: BorderSide(color: Color(0xFF00D4FF), width: 3)),
        ),
        blockquote: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.6),
        horizontalRuleDecoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF222222))),
        ),
        code: const TextStyle(color: Color(0xFF00D4FF), backgroundColor: Color(0xFF141414)),
      ),
      ),
      ],
    );
  }

  Widget _buildActionBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        border: const Border(top: BorderSide(color: Color(0xFF222222))),
      ),
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _ActionButton(
            icon: Icons.favorite_border,
            label: 'Like',
            onPressed: () =>
                _guard(() => _toast('Thanks for the like!')),
          ),
          _ActionButton(
            icon: Icons.comment_outlined,
            label: 'Comment',
            onPressed: () => _guard(() => _toast('Comments coming soon.')),
          ),
          _ActionButton(
            icon: Icons.bookmark_border,
            label: 'Bookmark',
            onPressed: () => _guard(() => _toast('Bookmarked this book.')),
          ),
          _ActionButton(
            icon: Icons.share_outlined,
            label: 'Share',
            onPressed: () => _guard(() => _toast('Share link copied.')),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _readingHeartbeat?.cancel();
    unawaited(_finishReadingSession());
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF00D4FF),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

typedef ActionHandler = void Function();

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF00D4FF), size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
