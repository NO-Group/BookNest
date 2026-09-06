import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:go_router/go_router.dart';
import '../../../config/theme.dart';
import '../../components/manuscript_embeds.dart';
import '../../../services/backend_api.dart';

/// Fullscreen rich-text chapter editor — the same word processor as the
/// Manuscript Studio: formatted text, lists, headings, pictures and
/// dividers, no markdown syntax anywhere. Saves the document as a Quill
/// Delta through the edge API.
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
  final quill.QuillController _body = quill.QuillController.basic();
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
      final content = chapter['content']?.toString() ?? '';
      if (isQuillDelta(content)) {
        _body.document = quill.Document.fromJson(
            jsonDecode(content) as List<dynamic>);
      } else if (content.trim().isNotEmpty) {
        // Legacy chapter written before the word processor: keep every
        // word — it loads as plain text ready to be styled.
        _body.document = quill.Document()..insert(0, content);
      }
      if (!mounted) return;
      setState(() {
        if (chapter['title']?.toString().isNotEmpty == true &&
            _title.text.isEmpty) {
          _title.text = chapter['title'].toString();
        }
        _loadedExisting = true;
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    final title = _title.text.trim().isEmpty
        ? 'Chapter ${widget.chapterNumber}'
        : _title.text.trim();
    if (_body.document.isEmpty()) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The chapter is still empty.')));
      return;
    }
    setState(() => _saving = true);
    final res = await BackendApi.instance.saveChapter(
      bookId: widget.bookId,
      chapterNumber: widget.chapterNumber,
      title: title,
      content: jsonEncode(_body.document.toDelta().toJson()),
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
          Container(
            constraints: const BoxConstraints(maxHeight: 132),
            child: SingleChildScrollView(
              child: quill.QuillSimpleToolbar(
                controller: _body,
                config: quill.QuillSimpleToolbarConfig(
                  multiRowsDisplay: true,
                  showDividers: true,
                  showFontFamily: true,
                  showFontSize: true,
                  showBoldButton: true,
                  showItalicButton: true,
                  showSmallButton: true,
                  showUnderLineButton: true,
                  showStrikeThrough: true,
                  showInlineCode: true,
                  showColorButton: true,
                  showBackgroundColorButton: true,
                  showClearFormat: true,
                  showAlignmentButtons: true,
                  showHeaderStyle: true,
                  showListNumbers: true,
                  showListBullets: true,
                  showListCheck: true,
                  showCodeBlock: true,
                  showQuote: true,
                  showIndent: true,
                  showLink: true,
                  showUndo: true,
                  showRedo: true,
                  showSearchButton: true,
                  showSubscript: true,
                  showSuperscript: true,
                  showLineHeightButton: true,
                ),
              ),
            ),
          ),
          Expanded(
            child: quill.QuillEditor.basic(
              controller: _body,
              config: const quill.QuillEditorConfig(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                placeholder: 'Once upon a chapter…',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
