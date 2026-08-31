import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../config/theme.dart';
import '../../../services/backend_api.dart';

/// Fullscreen markdown chapter editor. Saves through the edge API
/// (chapters.save). Pre-deploy it warns honestly that saving needs the cloud.
class ChapterEditorScreen extends StatefulWidget {
  final String bookId;
  final int chapterNumber;
  final String initialTitle;

  const ChapterEditorScreen({
    super.key,
    required this.bookId,
    required this.chapterNumber,
    this.initialTitle = '',
  });

  @override
  State<ChapterEditorScreen> createState() => _ChapterEditorScreenState();
}

class _ChapterEditorScreenState extends State<ChapterEditorScreen> {
  late final TextEditingController _title =
      TextEditingController(text: widget.initialTitle);
  final TextEditingController _body = TextEditingController();
  bool _saving = false;
  bool _loadedExisting = false;

  @override
  void initState() {
    super.initState();
    _maybeLoadExisting();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _maybeLoadExisting() async {
    // Editing an existing chapter: pull its current content for pre-fill.
    final book = await BackendApi.instance.fetchBook(widget.bookId);
    if (!mounted || book == null) return;
    final chapters = book['chapters'] as List? ?? [];
    final match = chapters.cast<Map?>().firstWhere(
          (c) => c != null && (c['chapterNumber'] as num?)?.toInt() == widget.chapterNumber,
          orElse: () => null,
        );
    if (match == null) return;
    try {
      final chapter = await BackendApi.instance
          .call('books.chapter', <String, dynamic>{
        'bookId': widget.bookId,
        'chapterNumber': widget.chapterNumber,
      });
      if (!mounted || chapter == null) return;
      setState(() {
        _body.text = chapter['content']?.toString() ?? '';
        if (chapter['title']?.toString().isNotEmpty == true &&
            _title.text.isEmpty) {
          _title.text = chapter['title'].toString();
        }
        _loadedExisting = true;
      });
    } catch (_) {}
  }

  void _wrapSelection(String marker) {
    final selection = _body.selection;
    final text = _body.text;
    if (!selection.isValid || selection.isCollapsed) {
      final index = _body.selection.baseOffset;
      final safeIndex = index < 0 ? text.length : index;
      _body.value = TextEditingValue(
        text: '$text$marker$marker',
        selection:
            TextSelection.collapsed(offset: safeIndex + marker.length),
      );
      return;
    }
    final start = selection.start;
    final end = selection.end;
    final selected = text.substring(start, end);
    final newText = text.replaceRange(start, end, '$marker$selected$marker');
    _body.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
          offset: start + marker.length + selected.length + marker.length),
    );
  }

  Future<void> _save() async {
    final title = _title.text.trim().isEmpty
        ? 'Chapter ${widget.chapterNumber}'
        : _title.text.trim();
    if (_body.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The chapter is still empty.')));
      return;
    }
    setState(() => _saving = true);
    final res = await BackendApi.instance.saveChapter(
      bookId: widget.bookId,
      chapterNumber: widget.chapterNumber,
      title: title,
      content: _body.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Saving needs the BookNest cloud. Your text is still here — '
              'connect the cloud and save again.')));
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Chapter saved ✓')));
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        title: Text(
            _loadedExisting
                ? 'Edit chapter ${widget.chapterNumber}'
                : 'New chapter ${widget.chapterNumber}',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: BookNestColors.cyan))
                : const Text('Save',
                    style: TextStyle(
                        color: BookNestColors.cyan,
                        fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: TextField(
              controller: _title,
              decoration: InputDecoration(
                hintText: 'Chapter title',
                filled: true,
                fillColor: theme.colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                _MarkdownButton(label: 'H1', onTap: () => _wrapSelection('# ')),
                _MarkdownButton(label: 'B', onTap: () => _wrapSelection('**')),
                _MarkdownButton(label: 'I', onTap: () => _wrapSelection('*')),
                _MarkdownButton(label: '❝', onTap: () => _wrapSelection('> ')),
                _MarkdownButton(label: '•', onTap: () => _wrapSelection('- ')),
                const Spacer(),
                Text('Markdown',
                    style:
                        TextStyle(color: theme.hintColor, fontSize: 11.5)),
              ],
            ),
          ),
          Expanded(
            child: TextField(
              controller: _body,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                hintText: 'Once upon a chapter…',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                hintStyle: TextStyle(color: theme.hintColor),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(0),
                  borderSide: BorderSide.none,
                ),
              ),
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkdownButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _MarkdownButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: BookNestColors.cyan.withOpacity(.12),
            border: Border.all(color: BookNestColors.cyan.withOpacity(.3)),
          ),
          child: Text(label,
              style: const TextStyle(
                  color: BookNestColors.cyan,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5)),
        ),
      ),
    );
  }
}
