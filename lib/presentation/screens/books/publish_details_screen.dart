import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../config/app_state.dart';
import '../../../config/theme.dart';
import '../../../core/utils/auth_guard.dart';
import '../../../services/backend_api.dart';
import '../../../services/supabase_service.dart';
import '../../components/booknest_ui.dart';
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
  List<Map<String, dynamic>> _chapters = [];
  int _chapterIndex = 0;
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
      final res = await BackendApi.instance.fetchBook(widget.bookId);
      final bookResponse = res?['book'];
      final chaptersResponse = ((res?['chapters'] as List?) ?? const [])
          .map((c) => {
                'chapter_number': (c as Map)['chapterNumber'],
                'title': c['title'],
                'content': null,
              })
          .toList();

      if (!mounted) return;

      setState(() {
        _book = bookResponse == null
            ? null
            : Map<String, dynamic>.from(bookResponse);
        _chapters = chaptersResponse.isEmpty
            ? []
            : chaptersResponse
                .map((row) => Map<String, dynamic>.from(row as Map))
                .toList();
        _chapterIndex = 0;
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
        actions: [
          IconButton(
            tooltip: 'Table of contents',
            icon: const Icon(Icons.format_list_bulleted_rounded),
            onPressed: _chapters.isEmpty ? null : _openTableOfContents,
          ),
          IconButton(
            tooltip: 'Reader settings',
            icon: const Icon(Icons.text_format_rounded),
            onPressed: _openReaderSettings,
          ),
        ],
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
    final current = _chapters.isEmpty ? null : _chapters[_chapterIndex];
    final chapterTitle = (current?['title'] as String?) ?? 'Chapter';
    final content = (current?['content'] as String?) ?? '';
    final hasNext = _chapterIndex < _chapters.length - 1;
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
        ListenableBuilder(
          listenable: Listenable.merge([
            AppSettings.readerFontScale,
            AppSettings.readerLineHeight,
            AppSettings.readerSerif,
          ]),
          builder: (context, _) {
            final scale = AppSettings.readerFontScale.value;
            final lineHeight = AppSettings.readerLineHeight.value;
            final fontFamily =
                AppSettings.readerSerif.value ? 'Georgia' : null;
            return Markdown(
              data:
                  content.isEmpty ? '*(No content published yet.)*' : content,
              selectable: true,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              styleSheet: MarkdownStyleSheet(
                h1: TextStyle(
                  color: onSurface,
                  fontSize: 24 * scale,
                  fontWeight: FontWeight.bold,
                  fontFamily: fontFamily,
                ),
                h2: TextStyle(
                  color: onSurface,
                  fontSize: 20 * scale,
                  fontWeight: FontWeight.bold,
                  fontFamily: fontFamily,
                ),
                p: TextStyle(
                  color: onSurface.withOpacity(.85),
                  fontSize: 16 * scale,
                  height: lineHeight,
                  fontFamily: fontFamily,
                ),
                listBullet: TextStyle(
                    color: BookNestColors.cyan,
                    fontSize: 16 * scale,
                    height: lineHeight),
                blockquoteDecoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: const Border(
                      left: BorderSide(color: BookNestColors.cyan, width: 3)),
                ),
                blockquote: TextStyle(
                    color: onSurface.withOpacity(.85),
                    fontSize: 15 * scale,
                    height: lineHeight),
                horizontalRuleDecoration: BoxDecoration(
                  border:
                      Border(top: BorderSide(color: theme.dividerColor)),
                ),
                code: TextStyle(
                  color: BookNestColors.cyan,
                  backgroundColor: theme.colorScheme.surface,
                ),
              ),
            );
          },
        ),
        if (hasNext)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _chapterIndex += 1),
              style: OutlinedButton.styleFrom(
                foregroundColor: BookNestColors.cyan,
                side: const BorderSide(color: BookNestColors.cyan),
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.auto_stories_rounded, size: 18),
              label: Text(
                  'Next: ${_chapters[_chapterIndex + 1]['title'] ?? 'Chapter'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
      ],
    );
  }

  void _openTableOfContents() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => GlassSheet(
        heightFactor: .7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Table of contents',
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: _chapters.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final chapter = _chapters[index];
                  final number =
                      (chapter['chapter_number'] as num?)?.toInt() ?? index + 1;
                  final selected = index == _chapterIndex;
                  return ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    selected: selected,
                    selectedTileColor: BookNestColors.cyan.withOpacity(.1),
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: selected
                          ? BookNestColors.cyan
                          : BookNestColors.cyan.withOpacity(.15),
                      child: Text('$number',
                          style: TextStyle(
                              color: selected
                                  ? BookNestColors.navyDeep
                                  : BookNestColors.cyan,
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5)),
                    ),
                    title: Text(
                        chapter['title']?.toString() ?? 'Chapter $number',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    onTap: () {
                      setState(() => _chapterIndex = index);
                      Navigator.pop(sheetContext);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openReaderSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, MediaQuery.viewInsetsOf(sheetContext).bottom + 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reader settings',
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 18),
            ValueListenableBuilder<double>(
              valueListenable: AppSettings.readerFontScale,
              builder: (context, scale, _) => _SliderRow(
                label: 'Text size',
                value: scale,
                min: .85,
                max: 1.4,
                display: '${(scale * 100).round()}%',
                onChanged: (v) => AppSettings.readerFontScale.value = v,
              ),
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<double>(
              valueListenable: AppSettings.readerLineHeight,
              builder: (context, height, _) => _SliderRow(
                label: 'Line spacing',
                value: height,
                min: 1.4,
                max: 2.0,
                display: height.toStringAsFixed(1),
                onChanged: (v) => AppSettings.readerLineHeight.value = v,
              ),
            ),
            const SizedBox(height: 6),
            ValueListenableBuilder<bool>(
              valueListenable: AppSettings.readerSerif,
              builder: (sheetContext, serif, _) => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: BookNestColors.cyan,
                title: const Text('Serif font',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: Text('Classic book feel',
                    style: TextStyle(
                        color: Theme.of(sheetContext).hintColor,
                        fontSize: 12)),
                value: serif,
                onChanged: (v) => AppSettings.readerSerif.value = v,
              ),
            ),
          ],
        ),
      ),
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

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13.5)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            activeColor: BookNestColors.cyan,
            divisions: 10,
            label: display,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(display,
              textAlign: TextAlign.end,
              style: TextStyle(
                  color: Theme.of(context).hintColor, fontSize: 12.5)),
        ),
      ],
    );
  }
}
