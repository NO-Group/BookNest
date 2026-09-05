import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../components/booknest_ui.dart';
import '../../components/watermark_background.dart';
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
  String _bookTitle = '';
  String _author = '';
  bool _loading = true;
  bool _cloudOffline = false;
  bool _chromeVisible = true;
  bool _restoredScroll = false;

  double _scrollFraction = 0;
  double _fontScale = 1.0; // 0.85 – 1.35
  double _lineHeight = 1.75; // 1.5 / 1.75 / 2.0

  Timer? _saveDebounce;
  Timer? _streakTimer;
  final Stopwatch _readingTime = Stopwatch();
  bool _streakCelebrated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBook();
    _readingTime.start();
    _streakTimer = Timer.periodic(const Duration(minutes: 5), (_) => _logStreak());
  }

  @override
  void dispose() {
    _flushProgress();
    _logStreak();
    _saveDebounce?.cancel();
    _streakTimer?.cancel();
    _scroll.dispose();
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
      }
    }
    if (chapters.isNotEmpty &&
        !chapters.any((c) => (c['chapterNumber'] as num).toInt() == startChapter)) {
      startChapter = (chapters.first['chapterNumber'] as num).toInt();
    }

    setState(() {
      _bookTitle = book['title']?.toString() ?? 'Untitled';
      _author = book['author']?.toString() ?? 'Unknown';
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
    setState(() {
      _chapterTitle = res['title']?.toString() ?? 'Chapter $_chapterNumber';
      _content = res['content']?.toString() ?? '';
      _loading = false;
    });
    if (resumeScroll > 0) _restoreScroll(resumeScroll);
    _scheduleProgressSave();
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

  void _toggleChrome() => setState(() => _chromeVisible = !_chromeVisible);

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
              Text('$_author · ${_chapters.length} chapters',
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
                onChanged: (value) => setState(() => _fontScale = value),
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
                onSelectionChanged: (selection) =>
                    setState(() => _lineHeight = selection.first),
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
    final baseStyle = TextStyle(
      fontSize: 16 * _fontScale,
      height: _lineHeight,
      color: dark ? BookNestColors.darkTextPrimary : BookNestColors.navyDeep,
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
            color: dark
                ? BookNestColors.darkChatBackground
                : Colors.white,
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
                                  child: GestureDetector(
                                    onTap: _toggleChrome,
                                    child: ListView(
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
                                  ),
                                ),
                    ),
                  ],
                ),
              ),
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
                                '${_chapters.isEmpty ? '?' : (_chapters.last['chapterNumber'] as num).toInt()}',
                            style: TextStyle(
                              fontSize: 11,
                              color: BookNestColors.cyan,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.format_list_bulleted_rounded),
                      tooltip: 'Chapters',
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
