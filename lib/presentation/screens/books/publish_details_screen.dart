import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/auth_guard.dart';
import '../../../services/supabase_service.dart';
import '../../../config/theme.dart';

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

  @override
  void initState() {
    super.initState();
    _loadBook();
    // Fire-and-forget read tracking (powers the Hot 🔥 algorithm). Deduped
    // server-side to one read per user per book per day.
    SupabaseService().client.rpc(
      'record_book_read',
      params: {'book_id': widget.bookId},
    );
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Could not load this book: $e';
      });
    }
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
      backgroundColor: NOC.bg,
      appBar: AppBar(
        backgroundColor: NOC.surface,
        elevation: 1,
        leading: IconButton(
          icon:  Icon(Icons.arrow_back, color: NOC.text),
          onPressed: () => context.pop(),
        ),
        title:  Text(
          'Reading',
          style: TextStyle(color: NOC.text, fontSize: 18),
        ),
      ),
      body: _buildBody(),
      bottomNavigationBar: _book == null ? null : _buildActionBar(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return  Center(
        child: CircularProgressIndicator(color: NOC.accent),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
               Icon(Icons.error_outline, size: 56, color: NOC.textFaint),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style:  TextStyle(color: NOC.textMuted, fontSize: 15),
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
    final views = (book['views'] as num?)?.toInt() ?? 0;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration:  BoxDecoration(
            border: Border(bottom: BorderSide(color: NOC.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style:  TextStyle(
                  color: NOC.text,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'by $author',
                style:  TextStyle(color: NOC.textMuted, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (chapterTitle.isNotEmpty) chapterTitle,
                  if (_formatDate(book['created_at']).isNotEmpty)
                    'Published ${_formatDate(book['created_at'])}',
                  if (views > 0) '$views views',
                ].join(' · '),
                style:  TextStyle(color: NOC.textFaint, fontSize: 12),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  description,
                  style:  TextStyle(
                    color: NOC.textMuted,
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
        h1:  TextStyle(
          color: NOC.text,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
        h2:  TextStyle(
          color: NOC.text,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        p:  TextStyle(
          color: NOC.textMuted,
          fontSize: 16,
          height: 1.7,
        ),
        listBullet:  TextStyle(color: NOC.accent),
        blockquoteDecoration: BoxDecoration(
          color: NOC.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border:  Border(left: BorderSide(color: NOC.accent, width: 3)),
        ),
        blockquote:  TextStyle(color: NOC.textMuted, fontSize: 15, height: 1.6),
        horizontalRuleDecoration:  BoxDecoration(
          border: Border(top: BorderSide(color: NOC.border)),
        ),
        code:  TextStyle(color: NOC.accent, backgroundColor: NOC.surfaceAlt),
      ),
      ),
      ],
    );
  }

  Widget _buildActionBar() {
    return Container(
      decoration: BoxDecoration(
        color: NOC.surface,
        border:  Border(top: BorderSide(color: NOC.border)),
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

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: NOC.accent,
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
            Icon(icon, color: NOC.accent, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style:  TextStyle(color: NOC.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
