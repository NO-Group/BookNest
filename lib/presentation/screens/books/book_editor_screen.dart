import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../services/supabase_service.dart';
import '../../../config/theme.dart';

/// Native Markdown writing screen, reused everywhere a book is created:
/// - Feed "Article" / Books library "Write" → no context (personal book).
/// - Community library "Write" → `communityId` set; drafts land in the
///   community library, published books stay linked to the community.
/// - Drafts resume via `bookId` (from Profile "My Drafts" or a community
///   library draft) — the title/chapter are loaded and can be saved again or
///   published.
///
/// Toolbar applies formatting with Dart's native selection APIs
/// (replaceRange / TextSelection); publishing writes `club_books` (pending)
/// plus its first `book_chapters` row. **Save draft** writes/updates a
/// `club_books` row with `moderation_status = 'draft'`.
class BookEditorScreen extends StatefulWidget {
  final String? clubId;
  final String? communityId;
  final String? bookId;

  const BookEditorScreen({
    super.key,
    this.clubId,
    this.communityId,
    this.bookId,
  });

  @override
  State<BookEditorScreen> createState() => _BookEditorScreenState();
}

class _BookEditorScreenState extends State<BookEditorScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final FocusNode _contentFocusNode = FocusNode();
  bool _isSaving = false;
  bool _loadedDraft = false;

  @override
  void initState() {
    super.initState();
    if (widget.bookId != null) {
      _loadDraft();
    }
  }

  Future<void> _loadDraft() async {
    final bookId = widget.bookId!;
    try {
      final supabase = SupabaseService().client;
      final book = await supabase
          .from('club_books')
          .select('id, title, description')
          .eq('id', bookId)
          .maybeSingle();
      final chapters = await supabase
          .from('book_chapters')
          .select('title, content')
          .eq('club_book_id', bookId)
          .order('chapter_number', ascending: true)
          .limit(1);
      if (!mounted) return;
      if (book != null) {
        _titleController.text = book['title']?.toString() ?? '';
      }
      if (chapters.isNotEmpty) {
        final chapter = Map<String, dynamic>.from(chapters.first as Map);
        _contentController.text = chapter['content']?.toString() ?? '';
      }
      _loadedDraft = true;
    } catch (_) {
      // Non-fatal: open an empty editor if the draft could not load.
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }

  /// Wraps the selected text with an inline [marker] (e.g. `**` or `*`).
  void _applyInlineStyle(String marker) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    final start = selection.start;
    final end = selection.end;

    if (!selection.isValid || start > end) return;

    if (end == start) {
      // No selection: insert empty markers and place the cursor between them.
      final value = '$marker$marker';
      final newText = text.replaceRange(start, end, value);
      _contentController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start + marker.length),
      );
      return;
    }

    final selected = text.substring(start, end);
    final replacement = '$marker$selected$marker';
    final newText = text.replaceRange(start, end, replacement);
    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: start,
        extentOffset: start + replacement.length,
      ),
    );
    _contentFocusNode.requestFocus();
  }

  /// Prepends a line-level [prefix] (e.g. `# `, `> ` or `- `) to the line(s)
  /// covered by the current selection.
  void _applyLinePrefix(String prefix) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    final start = selection.start;
    final end = selection.end;

    if (!selection.isValid || start > end) return;

    final lineStart = start == 0
        ? 0
        : (text.lastIndexOf('\n', start - 1) + 1);
    final rawLineEnd = text.indexOf('\n', end);
    final lineEnd = rawLineEnd == -1 ? text.length : rawLineEnd;

    final line = text.substring(lineStart, lineEnd);
    final newLine = '$prefix$line';
    final newText = text.replaceRange(lineStart, lineEnd, newLine);
    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: lineStart + prefix.length,
        extentOffset: lineStart + prefix.length + line.length,
      ),
    );
    _contentFocusNode.requestFocus();
  }

  String _descriptionFromContent(String content) {
    if (content.isEmpty) return '';
    return content.length > 200 ? '${content.substring(0, 200)}…' : content;
  }

  /// Persists the current book row + first chapter with the given status.
  Future<void> _persist(String status, {required bool isDraft}) async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a book title.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }
    final content = _contentController.text.trim();
    if (!isDraft && content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please write at least one chapter.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final supabase = SupabaseService().client;
      final user = supabase.auth.currentUser;
      if (user == null) {
        throw Exception('You must be signed in to publish.');
      }

      final description = _descriptionFromContent(content);
      final bookId = widget.bookId;

      if (bookId != null) {
        // Update the existing draft/book row.
        await supabase
            .from('club_books')
            .update({
              'title': title,
              'description': description,
              'moderation_status': status,
            })
            .eq('id', bookId);

        final chapter = await supabase
            .from('book_chapters')
            .select('id')
            .eq('club_book_id', bookId)
            .eq('chapter_number', 1)
            .maybeSingle();
        if (chapter != null) {
          await supabase
              .from('book_chapters')
              .update({'title': 'Chapter 1', 'content': content})
              .eq('id', chapter['id']);
        } else {
          await supabase.from('book_chapters').insert({
            'club_book_id': bookId,
            'chapter_number': 1,
            'title': 'Chapter 1',
            'content': content,
          });
        }
      } else {
        final bookResponse = await supabase.from('club_books').insert({
          'club_id': widget.clubId,
          'community_id': widget.communityId,
          'title': title,
          'author': user.email ?? user.userMetadata?['username'] ?? 'Anonymous',
          'description': description,
          'content_format': 'markdown',
          'moderation_status': status,
          'added_by': user.id,
        }).select();

        if (bookResponse.isEmpty) {
          throw Exception('Failed to create the book record.');
        }

        final newBookId = bookResponse.first['id'];

        await supabase.from('book_chapters').insert({
          'club_book_id': newBookId,
          'chapter_number': 1,
          'title': 'Chapter 1',
          'content': _contentController.text,
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isDraft ? 'Draft saved.' : 'Book submitted for review.',
          ),
          backgroundColor: NOC.accent,
        ),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not ${isDraft ? 'save draft' : 'publish'}: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: IconButton(
        icon: Icon(icon, color: NOC.textMuted),
        tooltip: tooltip,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
      ),
    );
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
        title: Text(
          _loadedDraft ? 'Edit Book' : 'Write Book',
          style:  TextStyle(color: NOC.text, fontSize: 18),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: TextButton.icon(
              onPressed: _isSaving ? null : () => _persist('draft', isDraft: true),
              icon:  Icon(Icons.save_outlined, size: 18, color: NOC.accent),
              label:  Text(
                'Save',
                style: TextStyle(color: NOC.accent, fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: _isSaving ? null : () => _persist('pending', isDraft: false),
              icon: _isSaving
                  ?  SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: NOC.accent,
                      ),
                    )
                  : const Icon(Icons.rocket_launch, size: 18),
              label:  Text(
                'Publish',
                style: TextStyle(
                  color: NOC.accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _titleController,
                style:  TextStyle(
                  color: NOC.text,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                decoration:  InputDecoration(
                  hintText: 'Book Title',
                  hintStyle: TextStyle(color: NOC.textFaint),
                  border: InputBorder.none,
                ),
              ),
            ),
             Divider(color: NOC.border, height: 1),
            Container(
              color: NOC.surfaceAlt,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    _buildToolbarButton(
                      icon: Icons.format_bold,
                      tooltip: 'Bold (**text**)',
                      onPressed: () => _applyInlineStyle('**'),
                    ),
                    _buildToolbarButton(
                      icon: Icons.format_italic,
                      tooltip: 'Italic (*text*)',
                      onPressed: () => _applyInlineStyle('*'),
                    ),
                    _buildToolbarButton(
                      icon: Icons.title,
                      tooltip: 'Heading 1 (# text)',
                      onPressed: () => _applyLinePrefix('# '),
                    ),
                    _buildToolbarButton(
                      icon: Icons.format_size,
                      tooltip: 'Heading 2 (## text)',
                      onPressed: () => _applyLinePrefix('## '),
                    ),
                    _buildToolbarButton(
                      icon: Icons.format_quote,
                      tooltip: 'Quote (> text)',
                      onPressed: () => _applyLinePrefix('> '),
                    ),
                    _buildToolbarButton(
                      icon: Icons.format_list_bulleted,
                      tooltip: 'List (- item)',
                      onPressed: () => _applyLinePrefix('- '),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
             Divider(color: NOC.border, height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: TextField(
                  controller: _contentController,
                  focusNode: _contentFocusNode,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  style:  TextStyle(color: NOC.text, fontSize: 16, height: 1.7),
                  decoration:  InputDecoration(
                    hintText: 'Write your story... Use the toolbar to format, or type Markdown directly.',
                    hintStyle: TextStyle(color: NOC.textFaint),
                    border: InputBorder.none,
                  ),
                  onTapOutside: (_) => _contentFocusNode.unfocus(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
