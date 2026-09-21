import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/theme.dart';
import '../../components/manuscript_embeds.dart';
import '../../../services/backend_api.dart';

/// The BookNest chapter studio — a pocket IDE for writing. Rich text via
/// the word-processor toolbar, real typeset MATH (tap ƒ to insert a
/// formula with a live preview), split-screen PREVIEW that renders the
/// chapter exactly as readers will see it, live word/reading-time stats,
/// find & replace from the toolbar, and silent LOCAL DRAFTS that survive
/// a lost connection and are cleared on save.
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

  // ── studio state ──
  bool _showPreview = false;
  int _words = 0;
  int _chars = 0;
  bool _hasDraft = false;
  Timer? _draftDebounce;
  String? _serverContent; // what the cloud has, for draft comparison

  String get _draftKey =>
      'draft_chapter_${widget.bookId}_${widget.chapterNumber}';

  @override
  void initState() {
    super.initState();
    _body.addListener(_onDocChanged);
    _maybeLoadExisting();
  }

  @override
  void dispose() {
    _draftDebounce?.cancel();
    _body.removeListener(_onDocChanged);
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  // ── stats + drafts ──────────────────────────────────────────────────

  void _onDocChanged() {
    final text = _body.document.toPlainText();
    final words = text.trim().isEmpty
        ? 0
        : text.trim().split(RegExp(r'\s+')).length;
    if (words != _words || text.length != _chars) {
      setState(() {
        _words = words;
        _chars = text.length;
      });
    }
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 2500), _saveDraft);
  }

  Future<void> _saveDraft() async {
    try {
      if (_body.document.isEmpty()) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_draftKey, jsonEncode({
        'title': _title.text,
        'delta': _body.document.toDelta().toJson(),
        'at': DateTime.now().toIso8601String(),
      }));
      if (mounted && !_hasDraft) setState(() => _hasDraft = true);
    } catch (_) {}
  }

  Future<void> _restoreDraftIfAny() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftKey);
      if (raw == null || raw == _serverContent) return;
      final saved = jsonDecode(raw) as Map;
      final delta = saved['delta'];
      if (delta is! List) return;
      final draftText =
          quill.Document.fromJson(delta).toPlainText().trim();
      final serverText = _body.document.toPlainText().trim();
      if (draftText == serverText && draftText.isNotEmpty) {
        // Same words — the draft adds nothing; drop it quietly.
        await prefs.remove(_draftKey);
        return;
      }
      _body.document = quill.Document.fromJson(delta);
      final savedTitle = saved['title']?.toString() ?? '';
      if (savedTitle.isNotEmpty) _title.text = savedTitle;
      if (mounted) {
        setState(() => _hasDraft = true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Unsaved draft restored — it was kept safe '
                'on this device.')));
      }
    } catch (_) {}
  }

  Future<void> _discardDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
    } catch (_) {}
    if (mounted) {
      setState(() => _hasDraft = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Draft marker cleared.')));
    }
  }

  // ── cloud load / save ───────────────────────────────────────────────

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
      _serverContent = content;
      if (!mounted) return;
      setState(() {
        if (chapter['title']?.toString().isNotEmpty == true &&
            _title.text.isEmpty) {
          _title.text = chapter['title'].toString();
        }
        _loadedExisting = true;
      });
      await _restoreDraftIfAny();
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
      // The draft is already kept locally — say so and stay.
      _saveDraft();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Saving needs the BookNest cloud. Your words are safe as a '
              'draft on this device — connect and save again.')));
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
    } catch (_) {}
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Chapter saved ✓')));
    context.pop();
  }

  Future<void> _insertFormula() async {
    final tex = await askFormula(context);
    if (tex == null || mounted == false) return;
    if (tex.isEmpty) return;
    final index = _body.selection.extentOffset;
    _body.document.insert(index, MathBlockEmbed(tex));
    _body.updateSelection(
        TextSelection.collapsed(offset: index + 1), ChangeSource.local);
  }

  String get _readingTime {
    final minutes = (_words / 220).ceil();
    if (_words == 0) return '';
    return ' · ~${minutes < 1 ? 1 : minutes} min read';
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
          if (_hasDraft)
            IconButton(
              tooltip: 'Discard draft marker',
              onPressed: _discardDraft,
              icon: const Icon(Icons.delete_sweep_outlined,
                  color: BookNestColors.cyan),
            ),
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
              onChanged: (_) => _onDocChanged(),
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
          // ── studio strip: formula, preview toggle, live stats ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: _insertFormula,
                  icon: const Icon(Icons.functions_rounded,
                      size: 18, color: BookNestColors.cyan),
                  label: const Text('Formula',
                      style: TextStyle(
                          color: BookNestColors.cyan,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5)),
                ),
                const SizedBox(width: 2),
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _showPreview = !_showPreview),
                  icon: Icon(
                      _showPreview
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                      color: BookNestColors.cyan),
                  label: Text(_showPreview ? 'Hide preview' : 'Preview',
                      style: TextStyle(
                          color: BookNestColors.cyan,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5)),
                ),
                const Spacer(),
                Text(
                  _words == 0
                      ? ''
                      : '$_words words$_readingTime',
                  style: TextStyle(
                      fontSize: 11.5, color: theme.hintColor),
                ),
              ],
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
            flex: _showPreview ? 1 : 1,
            child: quill.QuillEditor.basic(
              controller: _body,
              config: quill.QuillEditorConfig(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                placeholder: 'Once upon a chapter…',
                embedBuilders: manuscriptEmbedBuilders,
              ),
            ),
          ),
          if (_showPreview)
            const Divider(height: 1, color: BookNestColors.cyan),
          if (_showPreview)
            Expanded(
              child: Container(
                color: theme.colorScheme.surface.withOpacity(.45),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                            'HOW READERS SEE IT${_title.text.trim().isEmpty ? '' : ' · ${_title.text.trim()}'}',
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                                color: BookNestColors.cyan)),
                      ),
                    ),
                    Expanded(
                      child: quill.QuillEditor.basic(
                        controller: _body,
                        config: quill.QuillEditorConfig(
                          readOnly: true,
                          padding:
                              const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          embedBuilders: manuscriptEmbedBuilders,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
