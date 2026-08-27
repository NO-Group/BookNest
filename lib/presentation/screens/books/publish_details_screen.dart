import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../config/theme.dart';
import '../../../core/utils/auth_guard.dart';
import '../../../services/backend_api.dart';
import '../../../services/supabase_service.dart';
import 'book_details_screen.dart' show BookShareSheet;

/// Chapter reader view for a single book.
///
/// Pulls the book metadata from `club_books` and its chapters from
/// `book_chapters` by [bookId], then renders the first chapter's raw Markdown.
/// Like / Save persist through the booknest-api edge function with optimistic
/// UI; Share opens the in-app contact picker (never the clipboard).
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
  bool _liked = false;
  bool _saved = false;
  String? _error;

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

  /// Optimistic toggles — flip instantly, persist in the background.
  void _toggleLike() {
    setState(() => _liked = !_liked);
    BackendApi.instance.setLike(widget.bookId, _liked);
  }

  void _toggleBookmark() {
    setState(() => _saved = !_saved);
    BackendApi.instance.setBookmark(widget.bookId, _saved);
  }

  void _openShareSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BookShareSheet(
        bookId: widget.bookId,
        bookTitle: _book?['title']?.toString() ?? 'this book',
      ),
    );
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
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Reading',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
      body: _buildBody(),
      bottomNavigationBar: _book == null ? null : _buildActionBar(),
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: BookNestColors.cyan),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 56, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.hintColor, fontSize: 15),
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
    final onSurface = theme.colorScheme.onSurface;
    final muted = theme.hintColor;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: onSurface,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'by $author',
                style: const TextStyle(
                    color: BookNestColors.cyan,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (chapterTitle.isNotEmpty) chapterTitle,
                  if (_formatDate(book['created_at']).isNotEmpty)
                    'Published ${_formatDate(book['created_at'])}',
                ].join(' · '),
                style: TextStyle(color: muted, fontSize: 12),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  description,
                  style: TextStyle(
                    color: muted,
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
            h1: TextStyle(
              color: onSurface,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            h2: TextStyle(
              color: onSurface,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            p: TextStyle(
              color: onSurface.withOpacity(.85),
              fontSize: 16,
              height: 1.7,
            ),
            listBullet: const TextStyle(color: BookNestColors.cyan),
            blockquoteDecoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: const Border(
                  left: BorderSide(color: BookNestColors.cyan, width: 3)),
            ),
            blockquote: TextStyle(
                color: onSurface.withOpacity(.85), fontSize: 15, height: 1.6),
            horizontalRuleDecoration: BoxDecoration(
              border: Border(top: BorderSide(color: theme.dividerColor)),
            ),
            code: TextStyle(
              color: BookNestColors.cyan,
              backgroundColor: theme.colorScheme.surface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionBar() {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
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
            icon: _liked ? Icons.favorite : Icons.favorite_border,
            label: 'Like',
            active: _liked,
            onPressed: () => _guard(_toggleLike),
          ),
          _ActionButton(
            icon: Icons.comment_outlined,
            label: 'Comment',
            onPressed: () => _guard(() =>
                _toast('Comments arrive with the community update.')),
          ),
          _ActionButton(
            icon: _saved ? Icons.bookmark : Icons.bookmark_border,
            label: 'Save',
            active: _saved,
            onPressed: () => _guard(_toggleBookmark),
          ),
          _ActionButton(
            icon: Icons.ios_share_outlined,
            label: 'Share',
            onPressed: () => _guard(_openShareSheet),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: BookNestColors.navy,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

typedef ActionHandler = void Function();

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        active ? BookNestColors.cyan : Theme.of(context).colorScheme.onSurface;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
