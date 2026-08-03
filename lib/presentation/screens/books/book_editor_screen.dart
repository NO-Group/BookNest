import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../services/supabase_service.dart';

/// Native Markdown writing screen.
///
/// Uses a plain [TextEditingController] and Dart's native selection APIs
/// (replaceRange / TextSelection) to apply formatting, with zero third-party
/// rich-text editor packages. Publishing writes the book row into `club_books`
/// and its first chapter into `book_chapters`.
class BookEditorScreen extends StatefulWidget {
  final String? clubId;

  const BookEditorScreen({super.key, this.clubId});

  @override
  State<BookEditorScreen> createState() => _BookEditorScreenState();
}

class _BookEditorScreenState extends State<BookEditorScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final FocusNode _contentFocusNode = FocusNode();
  bool _isPublishing = false;

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

  Future<void> _publishBook() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a book title.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please write at least one chapter.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    setState(() => _isPublishing = true);

    try {
      final supabase = SupabaseService().client;
      final user = supabase.auth.currentUser;
      if (user == null) {
        throw Exception('You must be signed in to publish.');
      }

      final description = content.length > 200
          ? '${content.substring(0, 200)}…'
          : content;

      final bookResponse = await supabase.from('club_books').insert({
        'club_id': widget.clubId,
        'title': title,
        'author': user.email ?? user.userMetadata?['username'] ?? 'Anonymous',
        'description': description,
        'content_format': 'markdown',
        'moderation_status': 'pending',
        'added_by': user.id,
      }).select();

      if (bookResponse.isEmpty) {
        throw Exception('Failed to create the book record.');
      }

      final bookId = bookResponse.first['id'];

      await supabase.from('book_chapters').insert({
        'club_book_id': bookId,
        'chapter_number': 1,
        'title': 'Chapter 1',
        'content': _contentController.text,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Book submitted for review.'),
          backgroundColor: Color(0xFF00D4FF),
        ),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not publish: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isPublishing = false);
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
        icon: Icon(icon, color: Colors.white70),
        tooltip: tooltip,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
      ),
    );
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
          'Write Book',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: _isPublishing ? null : _publishBook,
              icon: _isPublishing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF00D4FF),
                      ),
                    )
                  : const Icon(Icons.rocket_launch, size: 18),
              label: const Text(
                'Publish',
                style: TextStyle(
                  color: Color(0xFF00D4FF),
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
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                decoration: const InputDecoration(
                  hintText: 'Book Title',
                  hintStyle: TextStyle(color: Color(0xFF444444)),
                  border: InputBorder.none,
                ),
              ),
            ),
            const Divider(color: Color(0xFF222222), height: 1),
            Container(
              color: const Color(0xFF141414),
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
                      icon: Icons.format_header,
                      tooltip: 'Heading 1 (# text)',
                      onPressed: () => _applyLinePrefix('# '),
                    ),
                    _buildToolbarButton(
                      icon: Icons.format_header,
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
            const Divider(color: Color(0xFF222222), height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                child: TextField(
                  controller: _contentController,
                  focusNode: _contentFocusNode,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.7,
                  ),
                  decoration: const InputDecoration(
                    hintText:
                        'Start writing your story...\n\nUse the toolbar to format, or type Markdown directly.',
                    hintStyle: TextStyle(color: Color(0xFF555555)),
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
