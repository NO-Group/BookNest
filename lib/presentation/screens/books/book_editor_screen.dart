import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../config/theme.dart';
import '../../components/manuscript_embeds.dart';
import '../../../services/backend_api.dart';
import '../../../services/cloudinary_service.dart';
import '../../../services/supabase_service.dart';

/// The BookNest Manuscript Studio — a true word processor.
///
/// What you see is what readers get: select text and press Bold and the
/// text is bold — no `**`, no `#`, no markdown anywhere. Everything a
/// Google Docs manuscript needs: title/heading styles, font family and
/// size, bold, italic, underline, strikethrough, sub/superscript, small,
/// text color, highlight color, inline code, four alignments, line
/// height, bulleted/numbered/check lists, indent, quotes, code blocks,
/// links, clear formatting, undo & redo, find & replace, plus pictures
/// and dividers inserted right into the page. Chapters save as rich
/// documents; the reader renders exactly this.
class BookEditorScreen extends StatefulWidget {
  final String? clubId;

  const BookEditorScreen({super.key, this.clubId});

  @override
  State<BookEditorScreen> createState() => _BookEditorScreenState();
}

/// One chapter of the manuscript, held in memory until publish.
class _Chapter {
  quill.QuillController controller = quill.QuillController.basic();
  final TextEditingController title = TextEditingController();
  bool listening = false;

  bool get isEmpty => controller.document.isEmpty();

  int get wordCount {
    final text = controller.document.toPlainText().trim();
    if (text.isEmpty) return 0;
    return text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  void dispose() {
    controller.dispose();
    title.dispose();
  }
}

class _BookEditorScreenState extends State<BookEditorScreen> {
  // ── Details ──────────────────────────────────────────────────────────
  final _titleController = TextEditingController();
  final _penNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? _genre;
  String? _coverUrl;
  String? _bannerUrl;
  bool _uploadingCover = false;
  bool _uploadingBanner = false;

  // ── Manuscript ───────────────────────────────────────────────────────
  final List<_Chapter> _chapters = [_Chapter()];
  int _currentChapter = 0;

  // ── Publish ──────────────────────────────────────────────────────────
  bool _publishing = false;
  String? _publishedBookId;
  int _publishedChapters = 0;
  bool _insertingPicture = false;

  static const List<String> genres = [
    'Romance',
    'Science Fiction',
    'Thriller & Suspense',
    'Fantasy',
    'Mystery & Crime',
    'Horror',
    'Historical Fiction',
    'Literary Fiction',
    'Westerns',
    'Biographies & Memoirs',
    'True Crime',
    'Self-Help & Wellness',
    'History & Politics',
    'Young Adult (YA)',
    'STEM',
    'Humanities & Social Sciences',
    'Languages & Linguistics',
    'Finance & Economics',
    'Professional Certification',
    'Lexicons',
    'Research & Citation Tools',
    'Compendiums',
  ];

  _Chapter get chapter => _chapters[_currentChapter];

  @override
  void initState() {
    super.initState();
    _loadPenName();
    _listenForCounts();
  }

  void _listenForCounts() {
    for (final c in _chapters) {
      if (c.listening) continue;
      c.listening = true;
      c.controller.addListener(_onDocumentChanged);
    }
  }

  void _onDocumentChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _titleController.dispose();
    _penNameController.dispose();
    _descriptionController.dispose();
    for (final c in _chapters) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPenName() async {
    final user = SupabaseService().auth.currentUser;
    if (user == null) return;
    try {
      final row = await SupabaseService()
          .client
          .from('profiles')
          .select('display_name, username')
          .eq('id', user.id)
          .maybeSingle();
      if (!mounted || row == null) return;
      final name = (row['display_name'] ?? row['username'])?.toString();
      if (name != null && name.trim().isNotEmpty) {
        _penNameController.text = name.trim();
      }
    } catch (_) {
      // Cosmetic default — the studio works without it.
    }
  }

  // ── Chapter management ───────────────────────────────────────────────

  void _addChapter() {
    setState(() {
      _chapters.add(_Chapter());
      _currentChapter = _chapters.length - 1;
    });
    _listenForCounts();
  }

  void _removeChapter(int index) {
    if (_chapters.length == 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('A book needs at least one chapter — edit it instead.'),
      ));
      return;
    }
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this chapter?'),
        content: Text(
          '“${_chapters[index].title.text.trim().isNotEmpty ? _chapters[index].title.text.trim() : 'Chapter ${index + 1}'}” '
          'will be removed from this manuscript before publishing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              setState(() {
                _chapters[index].dispose();
                _chapters.removeAt(index);
                if (_currentChapter >= _chapters.length) {
                  _currentChapter = _chapters.length - 1;
                }
              });
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  // ── Inserts (real content, not syntax) ───────────────────────────────

  Future<void> _insertPicture() async {
    if (_insertingPicture) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1800,
      );
      if (picked == null || !mounted) return;
      setState(() => _insertingPicture = true);
      final bytes = await picked.readAsBytes();
      final extension = picked.name.contains('.')
          ? picked.name.split('.').last.toLowerCase()
          : 'jpg';
      final url = await CloudinaryService.uploadImage(
        bytes: bytes,
        folder: 'manuscripts',
        extension:
            (extension == 'jpg' || extension == 'jpeg' || extension == 'png' || extension == 'webp')
                ? extension
                : 'jpg',
      );
      if (!mounted) return;
      if (url == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('That picture could not be uploaded — please try again.'),
        ));
        return;
      }
      final controller = chapter.controller;
      final index = controller.selection.baseOffset;
      final safeIndex = index < 0 ? 0 : index;
      controller.replaceText(
        safeIndex,
        0,
        quill.BlockEmbed.custom(ImageBlockEmbed(url)),
        TextSelection.collapsed(offset: safeIndex),
      );
      // Move the caret to a fresh line after the picture.
      final after = controller.selection.baseOffset + 1;
      controller.replaceText(
        after,
        0,
        '\n',
        TextSelection.collapsed(offset: after + 1),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('That picture could not be inserted — please try again.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _insertingPicture = false);
    }
  }

  void _insertDivider() {
    final controller = chapter.controller;
    final index = controller.selection.baseOffset;
    final safeIndex = index < 0 ? 0 : index;
    controller.replaceText(
      safeIndex,
      0,
      quill.BlockEmbed.custom(const DividerBlockEmbed()),
      TextSelection.collapsed(offset: safeIndex + 1),
    );
  }

  // ── Cover & banner ───────────────────────────────────────────────────

  Future<void> _pickImage({required bool banner}) async {
    if ((banner && _uploadingBanner) || (!banner && _uploadingCover)) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 86,
        maxWidth: 1600,
      );
      if (picked == null || !mounted) return;
      setState(() {
        if (banner) {
          _uploadingBanner = true;
        } else {
          _uploadingCover = true;
        }
      });
      final bytes = await picked.readAsBytes();
      final extension = picked.name.contains('.')
          ? picked.name.split('.').last.toLowerCase()
          : 'jpg';
      final url = await CloudinaryService.uploadImage(
        bytes: bytes,
        folder: 'covers',
        extension:
            (extension == 'jpg' || extension == 'jpeg' || extension == 'png' || extension == 'webp')
                ? extension
                : 'jpg',
      );
      if (!mounted) return;
      if (url == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('That image could not be uploaded — please try again.'),
        ));
        return;
      }
      setState(() {
        if (banner) {
          _bannerUrl = url;
          _uploadingBanner = false;
        } else {
          _coverUrl = url;
          _uploadingCover = false;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _uploadingCover = false;
          _uploadingBanner = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('That image could not be attached — please try again.'),
        ));
      }
    }
  }

  // ── Publish pipeline ─────────────────────────────────────────────────

  int get _totalWords {
    var words = 0;
    for (final c in _chapters) {
      words += c.wordCount;
    }
    return words;
  }

  Future<void> _publish() async {
    if (_publishing) return;
    final title = _titleController.text.trim();
    if (title.length < 2) {
      _notice('Give your book a title first — at least 2 characters.');
      return;
    }
    final readyChapters = <_Chapter>[];
    for (final c in _chapters) {
      if (!c.isEmpty) readyChapters.add(c);
    }
    if (readyChapters.isEmpty) {
      _notice('Write at least one chapter before publishing.');
      return;
    }
    final penName = _penNameController.text.trim();
    if (penName.contains('@')) {
      _notice(
          'Pen names can\'t be email addresses — how will readers know you?');
      return;
    }

    setState(() => _publishing = true);

    try {
      // 1. The book record (or resume the one already created).
      if (_publishedBookId == null) {
        final created = await SupabaseService().writeRow('club_books', {
          'club_id': widget.clubId,
          'title': title,
          if (penName.isNotEmpty) 'author': penName,
          'description': _descriptionController.text.trim(),
          'genre': _genre,
          'cover_url': _coverUrl,
        });
        final id = created?['id']?.toString();
        if (id == null || id.isEmpty) {
          throw Exception(
              'The book could not be created — please try again.');
        }
        _publishedBookId = id;
      } else {
        // Refresh the details in case the author polished them meanwhile.
        await BackendApi.instance.call('books.update', {
          'bookId': _publishedBookId,
          'title': title,
          'description': _descriptionController.text.trim(),
          if (_genre != null) 'genre': _genre,
          if (_coverUrl != null) 'coverUrl': _coverUrl,
          if (_bannerUrl != null) 'bannerUrl': _bannerUrl,
        });
      }

      // 2. Every remaining chapter, in order, as a rich document.
      while (_publishedChapters < readyChapters.length) {
        final c = readyChapters[_publishedChapters];
        final res = await SupabaseService().writeRow('book_chapters', {
          'club_book_id': _publishedBookId,
          'chapter_number': _publishedChapters + 1,
          'title': c.title.text.trim().isNotEmpty
              ? c.title.text.trim()
              : 'Chapter ${_publishedChapters + 1}',
          'content':
              jsonEncode(c.controller.document.toDelta().toJson()),
        });
        if (res == null) {
          throw Exception(
              'Chapter ${_publishedChapters + 1} could not be saved — press publish to resume.');
        }
        _publishedChapters += 1;
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Published chapter $_publishedChapters of ${readyChapters.length}…'),
            duration: const Duration(seconds: 1),
          ));
        }
      }

      // 3. Banner is applied after creation (createDraft carries the cover;
      //    the banner arrives via the update path).
      if (_bannerUrl != null) {
        await BackendApi.instance.call('books.update', {
          'bookId': _publishedBookId,
          'bannerUrl': _bannerUrl,
        });
      }

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Your book is live 🎉'),
          content: Text(
            '“$title” is published with ${readyChapters.length} '
            'chapter${readyChapters.length == 1 ? '' : 's'} and '
            '${_totalWords == 0 ? 'zero' : '$_totalWords'} words. '
            'Readers can open it right now.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                context.pop();
              },
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is Exception
          ? error.toString().replaceFirst('Exception: ', '')
          : 'Publishing hit a snag — please try again.';
      _notice(_publishedBookId == null
          ? message
          : 'Saved so far — press Publish again to finish.');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ── UI ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          elevation: 1,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.pop(),
          ),
          title: const Text('Manuscript studio',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          bottom: TabBar(
            indicatorColor: BookNestColors.cyan,
            labelColor: theme.colorScheme.onSurface,
            unselectedLabelColor: theme.hintColor,
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(
                  icon: Icon(Icons.menu_book_rounded, size: 18),
                  text: 'Book details'),
              Tab(
                  icon: Icon(Icons.edit_note_rounded, size: 18),
                  text: 'Write'),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                onPressed: _publishing ? null : _publish,
                icon: _publishing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: BookNestColors.cyan))
                    : const Icon(Icons.rocket_launch_rounded, size: 18),
                label: Text(
                  _publishedBookId == null ? 'Publish' : 'Finish',
                  style: const TextStyle(
                      color: BookNestColors.cyan,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              _buildDetailsView(theme),
              _buildWriteView(theme),
            ],
          ),
        ),
      ),
    );
  }

  // ── Details view ─────────────────────────────────────────────────────

  Widget _buildDetailsView(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 48),
      children: [
        Text(
          'Everything here appears on your book\'s profile page.',
          style: TextStyle(color: theme.hintColor, fontSize: 13),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _titleController,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          decoration: const InputDecoration(
            labelText: 'Book title',
            hintText: 'The name readers will fall for',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _penNameController,
          decoration: const InputDecoration(
            labelText: 'Pen name',
            hintText: 'How you\'ll appear as the author',
            prefixIcon: Icon(Icons.badge_rounded, size: 20),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _descriptionController,
          maxLines: 5,
          maxLength: 5000,
          decoration: const InputDecoration(
            labelText: 'Description',
            hintText: 'The hook — what is this book about?',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 18),
        Text('Genre', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _genre,
          hint: const Text('Choose the shelf this book lives on'),
          isExpanded: true,
          items: genres
              .map((g) => DropdownMenuItem<String>(
                    value: g,
                    child: Text(g, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (value) => setState(() => _genre = value),
        ),
        const SizedBox(height: 22),
        _ImagePickerCard(
          label: 'Cover art',
          hint: 'The portrait cover on the book page (recommended ~2:3)',
          icon: Icons.auto_awesome_motion_rounded,
          url: _coverUrl,
          uploading: _uploadingCover,
          aspect: 2 / 3,
          onPick: () => _pickImage(banner: false),
          onRemove: () => setState(() => _coverUrl = null),
        ),
        const SizedBox(height: 14),
        _ImagePickerCard(
          label: 'Book picture (banner)',
          hint: 'A wide picture at the top of the book page (~3:1)',
          icon: Icons.panorama_wide_angle_outlined,
          url: _bannerUrl,
          uploading: _uploadingBanner,
          aspect: 3,
          onPick: () => _pickImage(banner: true),
          onRemove: () => setState(() => _bannerUrl = null),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () =>
                DefaultTabController.of(context)?.animateTo(1),
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('Next: write the chapters'),
          ),
        ),
      ],
    );
  }

  // ── Write view ───────────────────────────────────────────────────────

  Widget _buildWriteView(ThemeData theme) {
    final words = chapter.wordCount;
    final minutes = (words / 220).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Chapter chips
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            children: [
              for (var i = 0; i < _chapters.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onLongPress: () => _removeChapter(i),
                    child: ChoiceChip(
                      label: Text('Chapter ${i + 1}'),
                      selected: i == _currentChapter,
                      onSelected: (_) =>
                          setState(() => _currentChapter = i),
                      labelStyle: TextStyle(
                        fontWeight: i == _currentChapter
                            ? FontWeight.w800
                            : FontWeight.w500,
                        fontSize: 12.5,
                      ),
                      selectedColor: BookNestColors.cyan.withOpacity(.22),
                      labelPadding:
                          const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                ),
              ActionChip(
                avatar: const Icon(Icons.add_rounded,
                    size: 18, color: BookNestColors.cyan),
                label: const Text('Add chapter',
                    style: TextStyle(
                        color: BookNestColors.cyan,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5)),
                onPressed: _addChapter,
              ),
            ],
          ),
        ),
        Divider(color: theme.dividerColor, height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: chapter.title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: 'Chapter ${_currentChapter + 1} title',
              border: InputBorder.none,
              hintStyle: TextStyle(color: theme.hintColor),
            ),
          ),
        ),
        Divider(color: theme.dividerColor, height: 1),
        // Insert row — real content, zero syntax.
        Container(
          color: theme.colorScheme.surface,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _insertingPicture ? null : _insertPicture,
                icon: _insertingPicture
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: BookNestColors.cyan))
                    : const Icon(Icons.image_outlined, size: 18),
                label: const Text('Picture',
                    style:
                        TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                style: TextButton.styleFrom(
                    foregroundColor: BookNestColors.cyan,
                    visualDensity: VisualDensity.compact),
              ),
              TextButton.icon(
                onPressed: _insertDivider,
                icon: const Icon(Icons.horizontal_rule_rounded, size: 18),
                label: const Text('Divider',
                    style:
                        TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                style: TextButton.styleFrom(
                    foregroundColor: BookNestColors.cyan,
                    visualDensity: VisualDensity.compact),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '$words words · ${minutes <= 0 ? '<1' : minutes} min',
                  style: TextStyle(
                      fontSize: 12,
                      color: theme.hintColor,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        // The Google-Docs toolbar — every tool, zero syntax.
        Container(
          color: theme.colorScheme.surface,
          constraints: const BoxConstraints(maxHeight: 148),
          child: SingleChildScrollView(
            child: quill.QuillSimpleToolbar(
              controller: chapter.controller,
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
                showLeftAlignment: true,
                showCenterAlignment: true,
                showRightAlignment: true,
                showJustifyAlignment: true,
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
                showDirection: false,
              ),
            ),
          ),
        ),
        Divider(color: theme.dividerColor, height: 1),
        Expanded(
          child: quill.QuillEditor.basic(
            key: ValueKey('chapter-editor-$_currentChapter'),
            controller: chapter.controller,
            config: quill.QuillEditorConfig(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
              placeholder: 'Once upon a time…',
            ),
          ),
        ),
        // Status strip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(color: theme.dividerColor.withOpacity(.6)),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.notes_rounded,
                  size: 15, color: BookNestColors.cyan),
              const SizedBox(width: 6),
              Text(
                'Chapter ${_currentChapter + 1} of ${_chapters.length}',
                style: TextStyle(
                    fontSize: 12,
                    color: theme.hintColor,
                    fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '${_totalWords} words in the book',
                style: TextStyle(
                    fontSize: 12,
                    color: BookNestColors.cyan,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Image picker card ────────────────────────────────────────────────────────

class _ImagePickerCard extends StatelessWidget {
  final String label;
  final String hint;
  final IconData icon;
  final String? url;
  final bool uploading;
  final double aspect;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _ImagePickerCard({
    required this.label,
    required this.hint,
    required this.icon,
    required this.url,
    required this.uploading,
    required this.aspect,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withOpacity(.04) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: url != null
                ? BookNestColors.cyan.withOpacity(.45)
                : theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: BookNestColors.cyan),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14)),
              ),
              if (url != null)
                TextButton(onPressed: onRemove, child: const Text('Remove'))
              else
                TextButton(onPressed: onPick, child: const Text('Choose'))
            ],
          ),
          const SizedBox(height: 4),
          Text(hint, style: TextStyle(color: theme.hintColor, fontSize: 12)),
          const SizedBox(height: 12),
          if (uploading)
            Container(
              height: 120,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: BookNestColors.cyan.withOpacity(.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const CircularProgressIndicator(
                  color: BookNestColors.cyan, strokeWidth: 2),
            )
          else if (url != null)
            GestureDetector(
              onTap: onPick,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: aspect,
                  child: Image.network(url!, fit: BoxFit.cover),
                ),
              ),
            )
          else
            GestureDetector(
              onTap: onPick,
              child: Container(
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: BookNestColors.cyan.withOpacity(.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: BookNestColors.cyan.withOpacity(.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_photo_alternate_outlined,
                        color: BookNestColors.cyan.withOpacity(.8)),
                    const SizedBox(width: 8),
                    Text('Upload from your gallery',
                        style: TextStyle(color: theme.hintColor)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
