import 'dart:async';
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

  /// Edit an existing book: preloads details and every chapter.
  final Map<String, dynamic>? editBook;

  const BookEditorScreen({super.key, this.clubId, this.editBook});

  const BookEditorScreen.edit({super.key, required Map<String, dynamic> book})
      : clubId = null,
        editBook = book;

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
  final _bookCodeController = TextEditingController();
  String _unitType = 'chapter';
  String? _genre;
  String? _coverUrl;
  String? _bannerUrl;
  bool _uploadingCover = false;
  bool _uploadingBanner = false;

  // ── Edit mode ────────────────────────────────────────────────────────
  String? _editBookId;
  String? _editStatus;
  int _editChapterCount = 0;
  final List<String?> _editChapterIds = [];

  // ── Manuscript ───────────────────────────────────────────────────────
  final List<_Chapter> _chapters = [_Chapter()];
  int _currentChapter = 0;

  // ── Publish ──────────────────────────────────────────────────────────
  bool _publishing = false;
  String? _publishedBookId;
  int _publishedChapters = 0;
  bool _insertingPicture = false;

  // Live word total without rebuilding the studio on every keystroke —
  // counts refresh at most twice a second on their own ticker.
  final ValueNotifier<int> _words = ValueNotifier<int>(0);
  Timer? _wordTimer;

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
    _words.value = 0;
    _maybeLoadExistingBook();
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
    // Debounced: typing stays butter-smooth even in long chapters.
    _wordTimer ??= Timer(const Duration(milliseconds: 500), () {
      _wordTimer = null;
      if (mounted) _words.value = _totalWords;
    });
  }

  @override
  void dispose() {
    _wordTimer?.cancel();
    _words.dispose();
    _bookCodeController.dispose();
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

  /// Edit mode: pull the book's details and chapters into the studio.
  Future<void> _maybeLoadExistingBook() async {
    final book = widget.editBook;
    if (book == null) return;
    final bookId = book['id']?.toString() ?? '';
    if (bookId.isEmpty) return;
    _editBookId = bookId;
    _publishedBookId = bookId;
    _editStatus = book['status']?.toString() ?? 'published';
    _titleController.text = book['title']?.toString() ?? '';
    _descriptionController.text = book['description']?.toString() ?? '';
    _genre = book['genre']?.toString();
    _coverUrl = book['cover_url']?.toString();
    if ((_coverUrl ?? '').isEmpty) _coverUrl = null;
    _bannerUrl = book['banner_url']?.toString();
    if ((_bannerUrl ?? '').isEmpty) _bannerUrl = null;
    _unitType = book['unit_type']?.toString() ?? 'chapter';
    final code = book['book_code']?.toString() ?? '';
    _bookCodeController.text = code;
    try {
      final res = await BackendApi.instance.call('books.chapters',
          {'bookId': bookId});
      final chapters = res is Map ? res['chapters'] : null;
      if (chapters is List) {
        _chapters.clear();
        for (final raw in chapters) {
          if (raw is! Map) continue;
          final c = _Chapter();
          c.title.text = raw['title']?.toString() ?? '';
          final content = raw['content']?.toString() ?? '';
          try {
            if (isQuillDelta(content)) {
              c.controller.document = quill.Document.fromJson(
                  (jsonDecode(content) as List).toList());
            } else if (content.trim().isNotEmpty) {
              c.controller.document = quill.Document()..insert(0, content);
            }
          } catch (_) {}
          _chapters.add(c);
          _editChapterIds.add(raw['chapterNumber']?.toString());
        }
        _editChapterCount = _chapters.length;
        _publishedChapters = _chapters.length;
        if (_chapters.isEmpty) _chapters.add(_Chapter());
        _listenForCounts();
        _words.value = _totalWords;
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _publish({bool asDraft = false}) async {
    if (_publishing) return;
    final title = _titleController.text.trim();
    if (title.length < 2) {
      _notice('Give your book a title first — at least 2 characters.');
      return;
    }
    final bookCode = _bookCodeController.text.trim();
    if (bookCode.length < 3) {
      _notice('A Book ID is required — 3+ letters, numbers or dashes. It is '
          'yours alone, and adding a new book with the same ID + title makes '
          'the next part automatically.');
      return;
    }
    final penName = _penNameController.text.trim();
    if (penName.contains('@')) {
      _notice(
          'Pen names can\'t be email addresses — how will readers know you?');
      return;
    }
    final readyChapters = <_Chapter>[];
    for (final c in _chapters) {
      if (!c.isEmpty) readyChapters.add(c);
    }
    if (!asDraft && readyChapters.isEmpty && _editBookId == null) {
      _notice('Write at least one chapter before publishing — or save a draft.');
      return;
    }

    setState(() => _publishing = true);
    try {
      if (_editBookId != null) {
        // ── Editing an existing book ──
        await BackendApi.instance.call('books.update', {
          'bookId': _editBookId,
          'title': title,
          'description': _descriptionController.text.trim(),
          if (_genre != null) 'genre': _genre,
          if (_coverUrl != null) 'coverUrl': _coverUrl,
          if (_bannerUrl != null) 'bannerUrl': _bannerUrl,
          'unitType': _unitType,
          if (!asDraft) 'status': 'published',
        });
        for (var i = 0; i < readyChapters.length; i++) {
          final c = readyChapters[i];
          final payload = {
            'bookId': _editBookId,
            'chapterNumber': i + 1,
            'title': c.title.text.trim().isNotEmpty
                ? c.title.text.trim()
                : 'Unit ${i + 1}',
            'content': jsonEncode(c.controller.document.toDelta().toJson()),
          };
          if (i < _editChapterCount) {
            await BackendApi.instance.call('books.updateChapter', payload);
          } else {
            await BackendApi.instance.call('books.addChapter', payload);
          }
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Saved unit ${i + 1} of ${readyChapters.length}…'),
              duration: const Duration(seconds: 1),
            ));
          }
        }
        if (_bannerUrl != null) {
          await BackendApi.instance.call('books.update', {
            'bookId': _editBookId,
            'bannerUrl': _bannerUrl,
          });
        }
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Saved ✓'),
            content: Text(
                '"$title" now carries every change — readers see it instantly.'),
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
        return;
      }

      // ── New book: one call carries everything ──
      final chapters = [
        for (var i = 0; i < readyChapters.length; i++)
          {
            'chapterNumber': i + 1,
            'title': readyChapters[i].title.text.trim().isNotEmpty
                ? readyChapters[i].title.text.trim()
                : 'Unit ${i + 1}',
            'content':
                jsonEncode(readyChapters[i].controller.document.toDelta().toJson()),
          },
      ];
      final res = await BackendApi.instance.call('books.publish', {
        'title': title,
        if (penName.isNotEmpty) 'authorName': penName,
        'description': _descriptionController.text.trim(),
        if (_genre != null) 'genre': _genre,
        if (_coverUrl != null) 'coverUrl': _coverUrl,
        if (_bannerUrl != null) 'bannerUrl': _bannerUrl,
        'bookCode': bookCode,
        'unitType': _unitType,
        'asDraft': asDraft,
        'chapters': chapters,
      });
      if (res == null) {
        throw Exception('Publishing hit a snag — check your connection and try again.');
      }
      final part = (res['partNumber'] as num?)?.toInt() ?? 1;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(asDraft
              ? 'Draft saved 🌱'
              : (part > 1 ? 'Part $part is live 🎉' : 'Your book is live 🎉')),
          content: Text(asDraft
              ? '"$title" is saved as a draft. Finish it any time from your '
                  'writer dashboard — readers don\'t see drafts.'
              : (part > 1
                  ? '"$title" was added as Part $part of your "$bookCode" '
                      'story — readers can jump straight in. You also earned '
                      '25 gems!'
                  : '"$title" is published with ${chapters.length} '
                      'unit${chapters.length == 1 ? '' : 's'} and '
                      '$_totalWords words. You also earned 25 gems!')),
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
      final raw = error.toString().replaceFirst('Exception: ', '');
      final message = raw.contains('Book ID') || raw.contains('already')
          ? raw
          : 'Publishing hit a snag — please try again.';
      _notice(message);
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
                ValueListenableBuilder<int>(
                  valueListenable: _words,
                  builder: (context, words, _) => Text(
                    '$words words in the book',
                    style: TextStyle(
                        fontSize: 12,
                        color: BookNestColors.cyan,
                        fontWeight: FontWeight.w700),
                  ),
                ),
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
