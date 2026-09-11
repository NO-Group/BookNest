import 'dart:async';
import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../components/booknest_ui.dart';
import '../../components/manuscript_embeds.dart';
import '../../components/reader_paginator.dart';
import '../../components/watermark_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../services/backend_api.dart';
import '../../../services/supabase_service.dart';

/// The BookNest Reader — a distraction-free, full-screen reading room for
/// published chapters. Typography controls, tap-to-reveal chrome, a
/// whisper of the watermark canvas under the text, chapter TOC, automatic
/// progress sync (resume exactly where you stopped on any device) and the
/// daily reading streak with gems, all in one place.
class ReaderScreen extends StatefulWidget {
  final String bookId;
  final int? initialChapter;

  const ReaderScreen({super.key, required this.bookId, this.initialChapter});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  final ScrollController _scroll = ScrollController();

  List<Map<String, dynamic>> _chapters = [];
  int _chapterNumber = 1;
  String _chapterTitle = '';
  String _content = '';

  /// Non-null when the chapter is a rich document (the word-processor
  /// format). Legacy markdown chapters render through the fallback path.
  quill.QuillController? _richController;
  String _bookTitle = '';
  String _author = '';
  bool _loading = true;
  bool _cloudOffline = false;
  bool _chromeVisible = true;
  bool _restoredScroll = false;

  double _scrollFraction = 0;
  double _fontScale = 1.0; // 0.85 – 1.35
  double _lineHeight = 1.75; // 1.5 / 1.75 / 2.0
  int _readerTheme = 0; // 0 Night(auto) · 1 Paper · 2 Sepia · 3 Ink
  String _unitType = 'chapter';

  // ── Reader Pro ──────────────────────────────────────────────────────────
  bool _paginated = false;                 // pages vs scroll
  bool _fontSerif = false;                 // Classic sans vs Book serif
  double _dim = 0.0;                       // page warmth / dim overlay
  List<Map<String, dynamic>> _bookmarks = [];
  List<List<Paragraph>> _pages = const [];
  int _pageIndex = 0;
  String _pagesKey = '';                   // invalidation key for pagination
  PageController? _pageController;
  int _wordCount = 0;

  Timer? _saveDebounce;
  Timer? _streakTimer;
  final Stopwatch _readingTime = Stopwatch();
  bool _streakCelebrated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadReaderPrefs();
    _loadBook();
    _readingTime.start();
    _streakTimer = Timer.periodic(const Duration(minutes: 5), (_) => _logStreak());
    // Reader Pro: the page stays awake and the chrome immerses.
    WakelockPlus.enable().catchError((_) {});
  }

  @override
  void dispose() {
    _flushProgress();
    _logStreak();
    _saveDebounce?.cancel();
    _streakTimer?.cancel();
    _richController?.dispose();
    _scroll.dispose();
    _pageController?.dispose();
    WakelockPlus.disable().catchError((_) {});
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge).catchError((_) {});
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _flushProgress();
      _logStreak();
    }
  }

  Future<void> _loadBook() async {
    final bookRes = await BackendApi.instance
        .call('books.get', {'bookId': widget.bookId});
    if (!mounted) return;
    if (bookRes == null) {
      setState(() {
        _cloudOffline = true;
        _loading = false;
      });
      return;
    }
    final book = bookRes['book'];
    if (book is! Map) {
      setState(() {
        _cloudOffline = true;
        _loading = false;
      });
      return;
    }
    final chapters = ((book['chapters'] as List?) ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList()
      ..sort((a, b) => (a['chapterNumber'] as num).compareTo(b['chapterNumber'] as num));

    var startChapter = widget.initialChapter ?? 1;
    double startScroll = 0;
    if (widget.initialChapter == null) {
      final progressRes =
          await BackendApi.instance.call('reader.progress.get', {
        'bookId': widget.bookId,
      });
      if (!mounted) return;
      final progress = progressRes?['progress'];
      if (progress is Map) {
        startChapter = (progress['chapterNumber'] as num?)?.toInt() ?? 1;
        startScroll = (progress['scroll'] as num?)?.toDouble() ?? 0;
        final marks = (progress as Map)['bookmarks'];
        if (marks is List) {
          _bookmarks = marks
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
        }
      }
    }
    if (chapters.isNotEmpty &&
        !chapters.any((c) => (c['chapterNumber'] as num).toInt() == startChapter)) {
      startChapter = (chapters.first['chapterNumber'] as num).toInt();
    }

    setState(() {
      _bookTitle = book['title']?.toString() ?? 'Untitled';
      _author = book['author']?.toString() ?? 'Unknown';
      _unitType = book['unit_type']?.toString() ?? 'chapter';
      _chapters = chapters;
      _chapterNumber = startChapter;
    });
    await _loadChapter(startChapter, resumeScroll: startScroll);
  }

  Future<void> _loadChapter(int chapterNumber, {double resumeScroll = 0}) async {
    setState(() {
      _loading = true;
      _restoredScroll = false;
      _scrollFraction = 0;
    });
    final res = await BackendApi.instance.call('books.chapter', {
      'bookId': widget.bookId,
      'chapterNumber': chapterNumber,
    });
    if (!mounted) return;
    if (res == null) {
      setState(() => _cloudOffline = true);
      return;
    }
    _chapterNumber = (res['chapterNumber'] as num?)?.toInt() ?? chapterNumber;
    final content = res['content']?.toString() ?? '';
    quill.QuillController? rich;
    if (isQuillDelta(content)) {
      try {
        final deltaList = jsonDecode(content);
        rich = deltaList is List && deltaList.isNotEmpty
            ? quill.QuillController(
                document: quill.Document.fromJson(deltaList),
                selection: const TextSelection.collapsed(offset: 0),
                readOnly: true,
              )
            : null;
      } catch (_) {
        rich = null;
      }
    }
    setState(() {
      _chapterTitle = res['title']?.toString() ?? 'Chapter $_chapterNumber';
      _content = content;
      _richController?.dispose();
      _richController = rich;
      _pages = const [];
      _pagesKey = '';
      _pageIndex = 0;
      _wordCount = ReaderPaginator.words(
          rich != null ? '' : content);
      _loading = false;
    });
    if (_paginated && rich == null) {
      _restorePage(resumeScroll);
    } else if (resumeScroll > 0) {
      _restoreScroll(resumeScroll);
    }
    _scheduleProgressSave();
  }

  /// Jump to the page matching [fraction] once pages exist.
  void _restorePage(double fraction) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        if (!mounted) return;
        if (_pages.isNotEmpty) break;
      }
      if (!mounted || _pages.isEmpty) return;
      final target = (fraction * _pages.length).floor().clamp(0, _pages.length - 1);
      _pageController ??= PageController(initialPage: target);
      setState(() {
        _pageIndex = target;
        _restoredScroll = true;
        _scrollFraction = _pages.length <= 1 ? 1 : (target + 1) / _pages.length;
      });
    });
  }

  /// Re-pagination runs when the (content, type, viewport) key changes.
  void _maybePaginate(Size viewport, TextStyle body, TextStyle heading,
      TextStyle sub, double lineHeight) {
    if (_richController != null || _content.trim().isEmpty) return;
    final key = '$_content|$_fontScale|$_lineHeight|${viewport.width.round()}'
        '|${viewport.height.round()}|$_fontSerif';
    if (key == _pagesKey) return;
    _pagesKey = key;
    final pages = ReaderPaginator.paginate(
      paragraphs: ReaderPaginator.parse(_content),
      viewport: viewport,
      body: body,
      heading: heading,
      subheading: sub,
      lineHeight: lineHeight,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _pages = pages);
    });
  }

  List<Map<String, dynamic>> get _bookmarkMaps => _bookmarks
      .map((b) => <String, dynamic>{
            'id': b['id']?.toString() ??
                'bm${DateTime.now().millisecondsSinceEpoch}',
            'chapterNumber': (b['chapterNumber'] as num?)?.toInt() ?? _chapterNumber,
            'scroll': (b['scroll'] as num?)?.toDouble() ?? _scrollFraction,
            'label': b['label']?.toString() ?? 'Chapter $_chapterNumber',
            if (b['at'] != null) 'at': b['at'],
          })
      .toList();

  Future<void> _toggleBookmark() async {
    final existing = _bookmarks
        .where((b) => (b['chapterNumber'] as num?)?.toInt() == _chapterNumber)
        .toList();
    if (existing.isNotEmpty) {
      setState(() => _bookmarks = _bookmarks
          .where((b) => (b['chapterNumber'] as num?)?.toInt() != _chapterNumber)
          .toList());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bookmark removed.')));
    } else {
      setState(() {
        _bookmarks = [
          ..._bookmarks,
          {
            'id': 'bm${DateTime.now().millisecondsSinceEpoch}',
            'chapterNumber': _chapterNumber,
            'scroll': _scrollFraction,
            'label': _chapterTitle.isEmpty
                ? 'Chapter $_chapterNumber'
                : _chapterTitle,
            'at': DateTime.now().toIso8601String(),
          }
        ];
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bookmarked — find it in the contents.')));
    }
    BackendApi.instance.call('reader.progress.save', {
      'bookId': widget.bookId,
      'chapterNumber': _chapterNumber,
      'scroll': _scrollFraction,
      'bookmarks': _bookmarkMaps,
    });
  }

  void _restoreScroll(double fraction) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Wait until the text has actually laid out.
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        if (!mounted || !_scroll.hasClients) continue;
        final target = fraction * _scroll.position.maxScrollExtent;
        if (target > 0) {
          _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
        }
        setState(() => _restoredScroll = true);
        return;
      }
      if (mounted) setState(() => _restoredScroll = true);
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_paginated && _pages.isNotEmpty) return;
    final max = _scroll.position.maxScrollExtent;
    setState(() {
      _scrollFraction = max <= 0 ? 0 : (_scroll.offset / max).clamp(0, 1);
    });
    _scheduleProgressSave();
  }

  void _scheduleProgressSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 1600), _flushProgress);
  }

  void _flushProgress() {
    if (_cloudOffline || _content.isEmpty) return;
    BackendApi.instance.call('reader.progress.save', {
      'bookId': widget.bookId,
      'chapterNumber': _chapterNumber,
      'scroll': _scrollFraction,
    });
  }

  /// Feeds the daily reading streak (+2 gems on the first read of the day).
  Future<void> _logStreak() async {
    final minutes = _readingTime.elapsedMilliseconds ~/ 60000;
    if (minutes < 1 && !_readingTime.isRunning) return;
    if (minutes < 1) return;
    final res = await BackendApi.instance.call('streak.log', {'minutes': minutes});
    if (!mounted || res == null) return;
    final awarded = (res['gemsAwarded'] as num?)?.toInt() ?? 0;
    if (awarded > 0 && !_streakCelebrated) {
      _streakCelebrated = true;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 3),
        content: Text('+$awarded gems — your daily reading streak grows!'),
      ));
    }
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
    // True immersion: the system bars sink away with the chrome.
    SystemChrome.setEnabledSystemUIMode(
      _chromeVisible
          ? SystemUiMode.edgeToEdge
          : SystemUiMode.immersiveSticky,
    ).catchError((_) {});
  }

  /// The manuscript's reading typography, themed for light and dark and
  /// scaled by the reader's comfort settings.
  quill.DefaultStyles _manuscriptStyles(bool dark, {Color? ink}) {
    final color = ink ??
        (dark ? BookNestColors.darkTextPrimary : BookNestColors.navyDeep);
    final base = TextStyle(
      color: color,
      fontSize: 16 * _fontScale,
      height: _lineHeight,
    );
    quill.DefaultTextBlockStyle block(TextStyle style,
            {BoxDecoration? deco}) =>
        quill.DefaultTextBlockStyle(
          style,
          const quill.HorizontalSpacing(0, 0),
          const quill.VerticalSpacing(6, 0),
          const quill.VerticalSpacing(0, 0),
          deco,
        );
    return quill.DefaultStyles(
      color: color,
      paragraph: block(base),
      h1: block(base.copyWith(
          fontSize: 26 * _fontScale, fontWeight: FontWeight.w800)),
      h2: block(base.copyWith(
          fontSize: 21 * _fontScale, fontWeight: FontWeight.w800)),
      h3: block(base.copyWith(
          fontSize: 18 * _fontScale, fontWeight: FontWeight.w700)),
      bold: base.copyWith(fontWeight: FontWeight.w700),
      italic: base.copyWith(fontStyle: FontStyle.italic),
      underline: base.copyWith(decoration: TextDecoration.underline),
      strikeThrough: base.copyWith(decoration: TextDecoration.lineThrough),
      link: base.copyWith(
          color: BookNestColors.cyan,
          decoration: TextDecoration.underline),
      quote: block(
        base.copyWith(
            fontStyle: FontStyle.italic, color: color.withOpacity(.85)),
        deco: BoxDecoration(
          border: Border(
            left: BorderSide(
                color: BookNestColors.cyan.withOpacity(.6), width: 3),
          ),
        ),
      ),
      lists: quill.DefaultListBlockStyle(
        base,
        const quill.HorizontalSpacing(0, 0),
        const quill.VerticalSpacing(6, 0),
        const quill.VerticalSpacing(0, 0),
        null,
        null,
      ),
      sizeSmall: base.copyWith(fontSize: 13 * _fontScale),
      sizeLarge: base.copyWith(fontSize: 18 * _fontScale),
      sizeHuge: base.copyWith(fontSize: 24 * _fontScale),
    );
  }

  /// ── Premium reading comfort: preferences live on this device. ──────
  Future<void> _loadReaderPrefs() async {
    try {
      final raw =
          (await SharedPreferences.getInstance()).getString('reader.prefs');
      if (raw == null) return;
      final map = jsonDecode(raw);
      if (map is! Map) return;
      if (mounted) {
        setState(() {
          _fontScale = ((map['fs'] as num?)?.toDouble() ?? 1.0)
              .clamp(0.85, 1.35);
          _lineHeight = ((map['lh'] as num?)?.toDouble() ?? 1.75)
              .clamp(1.5, 2.0);
          _readerTheme = (map['theme'] as num?)?.toInt() ?? 0;
          _paginated = map['pd'] == true;
          _fontSerif = map['ff'] == true;
          _dim = ((map['dm'] as num?)?.toDouble() ?? 0).clamp(0.0, 0.45);
        });
      }
    } catch (_) {}
  }

  Future<void> _saveReaderPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'reader.prefs',
        jsonEncode({
          'fs': _fontScale,
          'lh': _lineHeight,
          'theme': _readerTheme,
          'pd': _paginated,
          'ff': _fontSerif,
          'dm': _dim,
        }),
      );
    } catch (_) {}
  }

  /// Whether the paper itself is dark — driven by the chosen reading theme.
  bool _pageIsDark(bool systemDark) {
    switch (_readerTheme) {
      case 1:
        return false; // Paper
      case 2:
        return false; // Sepia
      case 3:
        return true; // Ink
      default:
        return systemDark; // Night follows the app
    }
  }

  Color _pageBackground(bool systemDark) {
    switch (_readerTheme) {
      case 1:
        return const Color(0xFFFBFBF8);
      case 2:
        return const Color(0xFFF4E9D8);
      case 3:
        return const Color(0xFF0B1626);
      default:
        return systemDark
            ? BookNestColors.darkChatBackground
            : Colors.white;
    }
  }

  Color _pageForeground(bool systemDark) {
    switch (_readerTheme) {
      case 1:
        return BookNestColors.navyDeep;
      case 2:
        return const Color(0xFF3E3427);
      case 3:
        return const Color(0xFFE8EDF5);
      default:
        return systemDark
            ? BookNestColors.darkTextPrimary
            : BookNestColors.navyDeep;
    }
  }

  String get _unitLabel {
    switch (_unitType) {
      case 'part':
        return 'parts';
      case 'act':
        return 'acts';
      case 'episode':
        return 'episodes';
      case 'volume':
        return 'volumes';
      default:
        return 'chapters';
    }
  }

  void _openToc() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .7,
          ),
          decoration: BoxDecoration(
            color: Theme.of(sheetContext).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: BookNestColors.cyan.withOpacity(.22)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(sheetContext).dividerColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _bookTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text('$_author · ${_chapters.length} $_unitLabel',
                  style: TextStyle(color: BookNestColors.cyan, fontSize: 13)),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _chapters.length,
                  itemBuilder: (context, index) {
                    final chapter = _chapters[index];
                    final n = (chapter['chapterNumber'] as num).toInt();
                    final current = n == _chapterNumber;
                    return ListTile(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      leading: Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: current
                              ? BookNestColors.cyan
                              : BookNestColors.cyan.withOpacity(.12),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          '$n',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: current ? Colors.black : BookNestColors.cyan,
                          ),
                        ),
                      ),
                      title: Text(
                        chapter['title']?.toString() ?? 'Chapter $n',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: current ? FontWeight.w800 : FontWeight.w500,
                          color: current ? BookNestColors.cyan : null,
                        ),
                      ),
                      trailing: current
                          ? const Icon(Icons.auto_stories_rounded,
                              color: BookNestColors.cyan, size: 18)
                          : null,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        if (!current) _loadChapter(n);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The paginated reading surface: real pages, swipe or tap to turn.
  Widget _buildPages(BuildContext context, TextStyle baseStyle) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pageText = _pageForeground(dark);
    final pageCount = _pages.length;
    final totalPages = pageCount + 1; // + the chapter-end card
    _pageController ??= PageController();
    return PageView.builder(
      controller: _pageController,
      itemCount: totalPages,
      onPageChanged: (index) {
        setState(() {
          _pageIndex = math.min(index, math.max(0, pageCount - 1));
          _scrollFraction =
              (index + 1) / totalPages;
        });
        _scheduleProgressSave();
      },
      itemBuilder: (context, index) {
        if (index >= pageCount) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 120),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.auto_stories_rounded,
                    size: 44, color: BookNestColors.cyan.withOpacity(.7)),
                const SizedBox(height: 14),
                Text('End of chapter $_chapterNumber',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: pageText)),
                const SizedBox(height: 6),
                Text(_chapterTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        color: pageText.withOpacity(.65))),
              ],
            ),
          );
        }
        final page = _pages[index];
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 56),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final paragraph in page) ...[
                Text(
                  paragraph.text,
                  textAlign: paragraph.isHeading ? TextAlign.left : null,
                  style: paragraph.isHeading
                      ? baseStyle.copyWith(
                          fontSize: 24 * _fontScale,
                          fontWeight: FontWeight.w800,
                          height: 1.25)
                      : paragraph.isSubheading
                          ? baseStyle.copyWith(
                              fontSize: 15 * _fontScale,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: BookNestColors.cyan)
                          : baseStyle,
                ),
                const SizedBox(height: 10),
              ],
              const Spacer(),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'page ${index + 1} of $totalPages',
                  style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 1.1,
                      color: pageText.withOpacity(.4)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openTypography() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
          decoration: BoxDecoration(
            color: Theme.of(sheetContext).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: BookNestColors.cyan.withOpacity(.22)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(sheetContext).dividerColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Reading comfort',
                  style: Theme.of(sheetContext)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 18),
              if (_richController == null) ...[
                Text('Page layout',
                    style: TextStyle(
                        color: Theme.of(sheetContext).hintColor,
                        fontSize: 13)),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                        value: false,
                        icon: Icon(Icons.swap_vert_rounded, size: 17),
                        label: Text('Scroll')),
                    ButtonSegment(
                        value: true,
                        icon: Icon(Icons.menu_book_rounded, size: 17),
                        label: Text('Pages')),
                  ],
                  selected: {_paginated},
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor:
                        BookNestColors.cyan.withOpacity(.18),
                    selectedForegroundColor: BookNestColors.cyan,
                  ),
                  onSelectionChanged: (selection) {
                    setState(() {
                      _paginated = selection.first;
                      _pagesKey = '';
                      _pages = const [];
                      _pageController?.dispose();
                      _pageController = null;
                      _pageIndex = 0;
                    });
                    _saveReaderPrefs();
                    Navigator.pop(sheetContext);
                  },
                ),
                const SizedBox(height: 14),
                Text('Typeface',
                    style: TextStyle(
                        color: Theme.of(sheetContext).hintColor,
                        fontSize: 13)),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                        value: false, label: Text('Classic')),
                    ButtonSegment(
                        value: true, label: Text('Book serif')),
                  ],
                  selected: {_fontSerif},
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor:
                        BookNestColors.cyan.withOpacity(.18),
                    selectedForegroundColor: BookNestColors.cyan,
                  ),
                  onSelectionChanged: (selection) {
                    setState(() {
                      _fontSerif = selection.first;
                      _pagesKey = '';
                    });
                    _saveReaderPrefs();
                  },
                ),
                const SizedBox(height: 14),
                Text('Page warmth',
                    style: TextStyle(
                        color: Theme.of(sheetContext).hintColor,
                        fontSize: 13)),
                Slider(
                  value: _dim,
                  min: 0,
                  max: 0.45,
                  divisions: 9,
                  activeColor: BookNestColors.cyan,
                  label: _dim < 0.03
                      ? 'Off'
                      : '${(_dim / 0.45 * 100).round()}%',
                  onChanged: (value) {
                    setState(() => _dim = value);
                    _saveReaderPrefs();
                  },
                ),
                const SizedBox(height: 6),
              ],
              Text('Reading theme',
                  style: TextStyle(
                      color: Theme.of(sheetContext).hintColor, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (var i = 0; i < 4; i++)
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _readerTheme = i);
                          _saveReaderPrefs();
                        },
                        child: Container(
                          margin: EdgeInsets.only(right: i < 3 ? 8 : 0),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: [
                              Colors.black87,
                              const Color(0xFFFBFBF8),
                              const Color(0xFFF4E9D8),
                              const Color(0xFF0B1626),
                            ][i],
                            border: Border.all(
                              width: _readerTheme == i ? 2.2 : 1,
                              color: _readerTheme == i
                                  ? BookNestColors.cyan
                                  : Theme.of(sheetContext).dividerColor,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text('Ag',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: [
                                        Colors.white,
                                        BookNestColors.navyDeep,
                                        const Color(0xFF3E3427),
                                        const Color(0xFFE8EDF5),
                                      ][i])),
                              const SizedBox(height: 3),
                              Text(
                                ['Night', 'Paper', 'Sepia', 'Ink'][i],
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: _readerTheme == i
                                        ? (Theme.of(sheetContext).brightness ==
                                                Brightness.dark
                                            ? Colors.white
                                            : BookNestColors.navyDeep)
                                        : Colors.white54),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text('Text size',
                  style: TextStyle(
                      color: Theme.of(sheetContext).hintColor, fontSize: 13)),
              Slider(
                value: _fontScale,
                min: 0.85,
                max: 1.35,
                divisions: 5,
                activeColor: BookNestColors.cyan,
                label: '${(16 * _fontScale).round()} pt',
                onChanged: (value) {
                  setState(() => _fontScale = value);
                  _saveReaderPrefs();
                },
              ),
              Text('Line spacing',
                  style: TextStyle(
                      color: Theme.of(sheetContext).hintColor, fontSize: 13)),
              const SizedBox(height: 6),
              SegmentedButton<double>(
                segments: const [
                  ButtonSegment(value: 1.5, label: Text('Snug')),
                  ButtonSegment(value: 1.75, label: Text('Comfy')),
                  ButtonSegment(value: 2.0, label: Text('Airy')),
                ],
                selected: {_lineHeight},
                selectedIcon: const Icon(Icons.check_rounded),
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor:
                      BookNestColors.cyan.withOpacity(.18),
                  selectedForegroundColor: BookNestColors.cyan,
                ),
                onSelectionChanged: (selection) {
                  setState(() => _lineHeight = selection.first);
                  _saveReaderPrefs();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _prevChapter() {
    if (_chapterNumber > 1) _loadChapter(_chapterNumber - 1);
  }

  void _nextChapter() {
    if (_chapters.isEmpty) return;
    final maxChapter =
        (_chapters.last['chapterNumber'] as num).toInt();
    if (_chapterNumber < maxChapter) _loadChapter(_chapterNumber + 1);
  }

  bool get _hasNext {
    if (_chapters.isEmpty) return false;
    return _chapterNumber <
        (_chapters.last['chapterNumber'] as num).toInt();
  }

  /// The last page: pin progress to 100%, claim the one-time +5 gem finish
  /// bonus, and celebrate properly.
  Future<void> _celebrateFinish() async {
    if (!_atLastChapter) return;
    _scrollFraction = 1;
    _flushProgress();
    final res =
        await BackendApi.instance.call('reader.finish', {
      'bookId': widget.bookId,
    });
    if (!mounted) return;
    final gems = (res?['gemsAwarded'] as num?)?.toInt() ?? 0;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FinishSheet(
        bookTitle: _bookTitle,
        gems: gems,
        claimed: res != null,
      ),
    );
  }

  bool get _atLastChapter =>
      _chapters.isNotEmpty &&
      _chapterNumber >= (_chapters.last['chapterNumber'] as num).toInt();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // The chosen reading theme paints the paper; chrome follows the app.
    final pageDark = _pageIsDark(dark);
    final pageText = _pageForeground(dark);
    final pageBg = _pageBackground(dark);
    final baseStyle = TextStyle(
      fontSize: 16 * _fontScale,
      height: _lineHeight,
      fontFamily: _fontSerif ? 'Georgia' : null,
      color: pageText,
    );

    final markdownSheet = MarkdownStyleSheet.fromTheme(Theme.of(context))
        .copyWith(
          p: baseStyle,
          h1: baseStyle.copyWith(
              fontSize: 24 * _fontScale, fontWeight: FontWeight.w800),
          h2: baseStyle.copyWith(
              fontSize: 20 * _fontScale, fontWeight: FontWeight.w800),
          h3: baseStyle.copyWith(
              fontSize: 18 * _fontScale, fontWeight: FontWeight.w700),
          blockquote: baseStyle.copyWith(
              fontStyle: FontStyle.italic,
              color: dark
                  ? BookNestColors.darkTextPrimary.withOpacity(.85)
                  : BookNestColors.navyDeep.withOpacity(.85)),
          blockquoteDecoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: BookNestColors.cyan.withOpacity(.6), width: 3),
            ),
          ),
          blockquotePadding: const EdgeInsets.only(left: 14),
          horizontalRuleDecoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: BookNestColors.cyan.withOpacity(.35)),
            ),
          ),
          strong: baseStyle.copyWith(fontWeight: FontWeight.w800),
          em: baseStyle.copyWith(fontStyle: FontStyle.italic),
          listBullet: baseStyle,
        );

    return Scaffold(
      body: Stack(
        children: [
          // Reading surface with the watermark whisper.
          Container(
            color: pageBg,
            child: WatermarkBackground(
              opacity: dark ? 0.03 : 0.04,
              spacing: 168,
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    // Progress hairline.
                    LinearProgressIndicator(
                      value: _scrollFraction <= 0 ? null : _scrollFraction,
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                      color: BookNestColors.cyan.withOpacity(.75),
                    ),
                    Expanded(
                      child: _loading
                          ? const Center(
                              child: CircularProgressIndicator(
                                  color: BookNestColors.cyan))
                          : _cloudOffline
                              ? EmptyState(
                                  icon: Icons.cloud_off_rounded,
                                  title: 'The chapter is still in the cloud',
                                  subtitle:
                                      'BookNest could not reach its data store '
                                          'just now. Please try again shortly.',
                                  action: GradientButton(
                                    label: 'Retry',
                                    icon: Icons.refresh_rounded,
                                    onPressed: () {
                                      setState(() {
                                        _cloudOffline = false;
                                        _loading = true;
                                      });
                                      _loadBook();
                                    },
                                  ),
                                )
                              : NotificationListener<ScrollNotification>(
                                  onNotification: (notification) {
                                    if (notification
                                        is ScrollUpdateNotification) {
                                      _onScroll();
                                    }
                                    return false;
                                  },
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      _maybePaginate(
                                        constraints.biggest,
                                        baseStyle,
                                        baseStyle.copyWith(
                                            fontSize: 24 * _fontScale,
                                            fontWeight: FontWeight.w800),
                                        baseStyle.copyWith(
                                            fontSize: 15 * _fontScale,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.2,
                                            color: BookNestColors.cyan),
                                        _lineHeight,
                                      );
                                      final paginated = _paginated &&
                                          _richController == null;
                                      return GestureDetector(
                                    onTap: _toggleChrome,
                                    child: _richController != null
                                        ? quill.QuillEditor.basic(
                                            controller: _richController!,
                                            scrollController: _scroll,
                                            config: quill.QuillEditorConfig(
                                              customStyles:
                                                  _manuscriptStyles(dark,
                                                      ink: pageText),
                                              embedBuilders:
                                                  manuscriptEmbedBuilders,
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                      24, 20, 24, 120),
                                            ),
                                          )
                                        : paginated && _pages.isEmpty
                                            ? const Center(
                                                child:
                                                    CircularProgressIndicator(
                                                        color: BookNestColors
                                                            .cyan))
                                            : paginated
                                                ? _buildPages(
                                                    context, baseStyle)
                                                : ListView(
                                      controller: _scroll,
                                      padding: const EdgeInsets.fromLTRB(
                                          24, 20, 24, 120),
                                      children: [
                                        Text(
                                          'Chapter $_chapterNumber',
                                          style: TextStyle(
                                            fontSize: 12,
                                            letterSpacing: 2.2,
                                            fontWeight: FontWeight.w800,
                                            color: BookNestColors.cyan,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _chapterTitle,
                                          style: TextStyle(
                                            fontSize: 23 * _fontScale,
                                            height: 1.25,
                                            fontWeight: FontWeight.w800,
                                            color: dark
                                                ? BookNestColors.darkTextPrimary
                                                : BookNestColors.navyDeep,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _bookTitle,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Theme.of(context).hintColor,
                                          ),
                                        ),
                                        const SizedBox(height: 18),
                                        if (_content.trim().isEmpty)
                                          Text(
                                            'This chapter is still being written '
                                                'by its author.',
                                            style: baseStyle.copyWith(
                                                fontStyle: FontStyle.italic,
                                                color:
                                                    Theme.of(context).hintColor),
                                          )
                                        else
                                          MarkdownBody(
                                            data: _content,
                                            selectable: true,
                                            styleSheet: markdownSheet,
                                          ),
                                      ],
                                    ),
                                    );
                                    },
                                  ),
                                ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Page warmth: a candlelight dim over the paper, under the chrome.
          if (_dim > 0.005)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                    color: const Color(0xFF3A2A14)
                        .withOpacity(_dim)),
              ),
            ),

          // ── Revealable chrome ──────────────────────────────────────────
          AnimatedSlide(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            offset: _chromeVisible ? Offset.zero : const Offset(0, -1.2),
            child: SafeArea(
              bottom: false,
              child: Container(
                height: kToolbarHeight,
                decoration: BoxDecoration(
                  color: (dark ? BookNestColors.darkChatBackground : Colors.white)
                      .withOpacity(.96),
                  border: Border(
                    bottom: BorderSide(
                        color: Theme.of(context).dividerColor.withOpacity(.4)),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => context.pop(),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _bookTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                          Text(
                            '$_author · Chapter $_chapterNumber of '
                                '${_chapters.isEmpty ? '?' : (_chapters.last['chapterNumber'] as num).toInt()}'
                                '${_wordCount > 0 ? ' · ${ReaderPaginator.minutesLabel(_wordCount)}' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: BookNestColors.cyan,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _bookmarks.any((b) =>
                            (b['chapterNumber'] as num?)?.toInt() ==
                                _chapterNumber)
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        color: BookNestColors.cyan,
                      ),
                      tooltip: 'Bookmark this spot',
                      onPressed: _toggleBookmark,
                    ),
                    IconButton(
                      icon: const Icon(Icons.format_list_bulleted_rounded),
                      tooltip: 'Contents',
                      onPressed: _chapters.isEmpty ? null : _openToc,
                    ),
                    IconButton(
                      icon: const Icon(Icons.text_fields_rounded),
                      tooltip: 'Reading comfort',
                      onPressed: _openTypography,
                    ),
                  ],
                ),
              ),
            ),
          ),

          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            bottom: _chromeVisible ? 0 : -90,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              decoration: BoxDecoration(
                color: (dark ? BookNestColors.darkChatBackground : Colors.white)
                    .withOpacity(.97),
                border: Border(
                  top: BorderSide(
                      color: Theme.of(context).dividerColor.withOpacity(.4)),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            _chapterNumber > 1 ? _prevChapter : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                        label: const Text('Previous'),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        '${((_scrollFraction) * 100).round()}%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: BookNestColors.cyan,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _hasNext
                          ? ElevatedButton.icon(
                              onPressed: _nextChapter,
                              icon: const Icon(Icons.chevron_right_rounded),
                              label: const Text('Next chapter'),
                            )
                          : ElevatedButton.icon(
                              onPressed: _celebrateFinish,
                              icon: const Icon(Icons.emoji_events_rounded),
                              label: const Text('Finish the book'),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Finish celebration ───────────────────────────────────────────────────────

class _FinishSheet extends StatefulWidget {
  final String bookTitle;
  final int gems;
  final bool claimed;

  const _FinishSheet({
    required this.bookTitle,
    required this.gems,
    required this.claimed,
  });

  @override
  State<_FinishSheet> createState() => _FinishSheetState();
}

class _FinishSheetState extends State<_FinishSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fall = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _fall.dispose();
    super.dispose();
  }

  String get _gemsLine {
    if (!widget.claimed) {
      return 'Your +5 gems will land as soon as the cloud reconnects.';
    }
    if (widget.gems > 0) {
      return '+${widget.gems} gems added to your wallet';
    }
    return 'Finish bonus already claimed — this one is yours forever.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        child: Stack(
          children: [
            // Confetti canvas behind the card.
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _fall,
                builder: (context, _) => CustomPaint(
                  painter: _ConfettiPainter(_fall.value),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(28),
                border:
                    Border.all(color: BookNestColors.cyan.withOpacity(.35)),
                boxShadow: [
                  BoxShadow(
                    color: BookNestColors.navyDeep.withOpacity(.35),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [
                        BookNestColors.cyan.withOpacity(.3),
                        BookNestColors.cyanSoft.withOpacity(.15),
                      ]),
                      border: Border.all(
                          color: BookNestColors.cyan.withOpacity(.6), width: 2),
                    ),
                    child: const Icon(Icons.emoji_events_rounded,
                        color: BookNestColors.cyan, size: 38),
                  ),
                  const SizedBox(height: 16),
                  Text('You finished it!',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                    '“${widget.bookTitle}”',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: BookNestColors.cyan,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Every page. The whole story. Not many readers make it '
                    'this far — well done.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.hintColor, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: BookNestColors.cyan.withOpacity(.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: BookNestColors.cyan.withOpacity(.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.diamond_rounded,
                            color: BookNestColors.cyan, size: 18),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _gemsLine,
                            style: const TextStyle(
                              color: BookNestColors.cyan,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Keep reading'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            context.go('/library');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: BookNestColors.cyan,
                            foregroundColor: Colors.black,
                          ),
                          child: const Text('Choose the next one'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final double t;
  _ConfettiPainter(this.t);

  static const _colors = [
    BookNestColors.cyan,
    BookNestColors.navy,
    Color(0xFF7FD8E8),
    Color(0xFFB3C7F2),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    final paint = Paint();
    for (var i = 0; i < 46; i++) {
      final speed = 0.55 + rnd.nextDouble() * 0.75;
      final y = ((t * speed) % 1.15) * (size.height + 60) - 50;
      final x = rnd.nextDouble() * size.width +
          math.sin(t * 2 * math.pi + i * 1.3) * 14;
      final w = 5 + rnd.nextDouble() * 5;
      paint.color = _colors[i % _colors.length].withOpacity(.8);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(t * 4 * math.pi + i);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: w, height: w * .6),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) => oldDelegate.t != t;
}
