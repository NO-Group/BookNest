import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../components/adaptive.dart';
import '../../components/booknest_ui.dart';
import 'school_cbt_common.dart';

/// Saved (bookmarked) practice questions live on the device, so they work
/// offline and never cost server storage.
class _Bookmarks {
  static String _key(String schoolId) => 'cbt_bookmarks_$schoolId';

  static Future<List<Map<String, dynamic>>> load(String schoolId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(schoolId));
    if (raw == null) return [];
    try {
      return cbtList(jsonDecode(raw));
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(
      String schoolId, List<Map<String, dynamic>> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(schoolId), jsonEncode(list.take(500).toList()));
  }
}

/// ── Practice hub ───────────────────────────────────────────────────────
class CbtPracticeScreen extends StatefulWidget {
  const CbtPracticeScreen(
      {super.key, required this.schoolId, this.staff = false});

  final String schoolId;
  final bool staff;

  @override
  State<CbtPracticeScreen> createState() => _CbtPracticeScreenState();
}

class _CbtPracticeScreenState extends State<CbtPracticeScreen> {
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _saved = [];
  Map<String, dynamic> _history = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final subjects = await BackendApi.instance.call('cbt.bank.subjects',
        {'schoolId': widget.schoolId, 'practiceOnly': true});
    final history = await BackendApi.instance
        .call('cbt.practice.history', {'schoolId': widget.schoolId});
    final saved = await _Bookmarks.load(widget.schoolId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _subjects = cbtList(subjects?['subjects']);
      _history = history ?? {};
      _saved = saved;
    });
  }

  Future<void> _open(List<Map<String, dynamic>> questions,
      {required String subject, required bool mock, int minutes = 0}) async {
    if (questions.isEmpty) {
      cbtToast(context, 'No questions match — try another year or topic.');
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CbtPracticeSessionScreen(
        schoolId: widget.schoolId,
        subject: subject,
        questions: questions,
        mock: mock,
        minutes: minutes,
      ),
    ));
    _load();
  }

  Future<void> _search() async {
    final ctrl = TextEditingController();
    final term = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Search past questions'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: 'e.g. photosynthesis, quadratic, Lord Lugard'),
          onSubmitted: (v) => Navigator.pop(dialogContext, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, ctrl.text),
              child: const Text('Search')),
        ],
      ),
    );
    if (term == null || term.trim().isEmpty || !mounted) return;
    final res = await cbtCall(context, 'cbt.practice.questions', {
      'schoolId': widget.schoolId,
      'search': term.trim(),
      'count': 100,
    });
    if (res == null || !mounted) return;
    _open(cbtList(res['questions']), subject: '"${term.trim()}"', mock: false);
  }

  Future<void> _setup(Map<String, dynamic> subject) async {
    final topics = ((subject['topics'] as List?) ?? const []).map((e) => '$e').toList();
    final years = ((subject['years'] as List?) ?? const []).map((e) => '$e').toList();
    final available = (subject['count'] as num?)?.toInt() ?? 0;
    var mock = true;
    var topic = '';
    var year = '';
    var count = available < 20 ? (available < 1 ? 1 : available) : 20;
    var minutes = 20;
    final go = await showAdaptiveSheet<bool>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setLocal) => SheetBody(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(subject['subject'].toString(),
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w800)),
                  Text('$available question(s)'),
                  const SizedBox(height: 14),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                          value: true,
                          label: Text('Mock exam'),
                          icon: Icon(Icons.timer_outlined)),
                      ButtonSegment(
                          value: false,
                          label: Text('Study'),
                          icon: Icon(Icons.menu_book_rounded)),
                    ],
                    selected: {mock},
                    onSelectionChanged: (s) => setLocal(() => mock = s.first),
                  ),
                  const SizedBox(height: 6),
                  Text(
                      mock
                          ? 'Timed like the real thing. Answers and explanations at the end.'
                          : 'See the answer and explanation after each question.',
                      style: const TextStyle(fontSize: 12.5)),
                  const SizedBox(height: 14),
                  if (years.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: year,
                      decoration: const InputDecoration(
                          labelText: 'Year', border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('All years (mixed)')),
                        for (final y in years)
                          DropdownMenuItem(value: y, child: Text(y)),
                      ],
                      onChanged: (v) => setLocal(() => year = v ?? ''),
                    ),
                  if (topics.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: topic,
                      decoration: const InputDecoration(
                          labelText: 'Topic', border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('All topics')),
                        for (final t in topics)
                          DropdownMenuItem(value: t, child: Text(t)),
                      ],
                      onChanged: (v) => setLocal(() => topic = v ?? ''),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text('Questions: $count'),
                  if (available > 1)
                    Slider(
                      value: count.clamp(1, available > 200 ? 200 : available).toDouble(),
                      min: 1,
                      max: (available > 200 ? 200 : available).toDouble(),
                      divisions: (available > 200 ? 200 : available) - 1,
                      activeColor: BookNestColors.cyan,
                      onChanged: (v) => setLocal(() => count = v.round()),
                    ),
                  if (mock) ...[
                    Text('Time: $minutes min'),
                    Slider(
                      value: minutes.toDouble(),
                      min: 1,
                      max: 180,
                      divisions: 179,
                      activeColor: BookNestColors.cyan,
                      onChanged: (v) => setLocal(() => minutes = v.round()),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: available == 0
                          ? null
                          : () => Navigator.pop(sheetContext, true),
                      child: Text(mock ? 'Start mock exam' : 'Start studying'),
                    ),
                  ),
                ]),
          ),
        ),
      ),
    );
    if (go != true || !mounted) return;
    final res = await cbtCall(context, 'cbt.practice.questions', {
      'schoolId': widget.schoolId,
      'subject': subject['subject'],
      if (topic.isNotEmpty) 'topic': topic,
      if (year.isNotEmpty) 'year': year,
      'count': count,
      'ordered': year.isNotEmpty && !mock,
    }, fallback: 'Could not load questions — check your connection.');
    if (res == null || !mounted) return;
    _open(cbtList(res['questions']),
        subject: subject['subject'].toString(), mock: mock, minutes: minutes);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Practice'),
          actions: [
            IconButton(
                tooltip: 'Search past questions',
                onPressed: _search,
                icon: const Icon(Icons.search_rounded)),
          ],
          bottom: const TabBar(
            indicatorColor: BookNestColors.cyan,
            tabs: [
              Tab(text: 'Subjects'),
              Tab(text: 'Saved'),
              Tab(text: 'Progress'),
            ],
          ),
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: BookNestColors.cyan))
            : TabBarView(children: [
                _subjectsTab(),
                _savedTab(),
                _historyTab(),
              ]),
      ),
    );
  }

  Widget _empty(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .6))),
        ),
      );

  Widget _subjectsTab() {
    if (_subjects.isEmpty) {
      return _empty(widget.staff
          ? 'No practice questions yet. Add questions in the Question bank '
              'and leave "Students can practise this" on.'
          : 'Your teachers haven\'t added practice questions yet.');
    }
    final columns = context.isExpanded ? 3 : context.isMediumUp ? 2 : 1;
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: 104,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _subjects.length,
        itemBuilder: (_, i) {
          final s = _subjects[i];
          Map<String, dynamic>? stat;
          for (final h in cbtList(_history['subjects'])) {
            if (h['subject'] == s['subject']) stat = h;
          }
          return GlassPanel(
            radius: 18,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _setup(s),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [BookNestColors.navy, BookNestColors.navyDeep]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                        s['subject'].toString().characters.first.toUpperCase(),
                        style: const TextStyle(
                            color: BookNestColors.cyan,
                            fontSize: 20,
                            fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s['subject'].toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w800)),
                          Text(
                              '${s['count']} questions'
                              '${((s['years'] as List?) ?? const []).isNotEmpty ? ' · ${(s['years'] as List).length} years' : ''}',
                              style: const TextStyle(fontSize: 12)),
                          if (stat != null)
                            Text('Your average: ${cbtNum(stat['average'])}%',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: BookNestColors.cyan)),
                        ]),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _savedTab() {
    if (_saved.isEmpty) {
      return _empty('Tap the bookmark on any practice question to save it '
          'here. Saved questions work offline.');
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Expanded(child: Text('${_saved.length} saved question(s)')),
          FilledButton.tonalIcon(
            onPressed: () => _open(List.of(_saved), subject: 'Saved', mock: false),
            icon: const Icon(Icons.menu_book_rounded),
            label: const Text('Study all'),
          ),
        ]),
        const SizedBox(height: 10),
        for (final q in _saved)
          Card(
            child: ListTile(
              title: Text(q['text']?.toString() ?? '',
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text([q['subject'], q['year']]
                  .where((s) => '${s ?? ''}'.isNotEmpty)
                  .join(' · ')),
              trailing: IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.bookmark_remove_outlined),
                onPressed: () async {
                  setState(() => _saved.removeWhere((s) => s['id'] == q['id']));
                  await _Bookmarks.save(widget.schoolId, _saved);
                },
              ),
              onTap: () => _open([q], subject: 'Saved', mock: false),
            ),
          ),
      ],
    );
  }

  Widget _historyTab() {
    final subjects = cbtList(_history['subjects']);
    final recent = cbtList(_history['recent']);
    if (recent.isEmpty) {
      return _empty('Finish a mock exam or study session to see your '
          'progress, best scores and history here.');
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('By subject',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final s in subjects)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(s['subject'].toString(),
                        style: const TextStyle(fontWeight: FontWeight.w700))),
                Text('avg ${cbtNum(s['average'])}% · best ${cbtNum(s['best'])}% · '
                    '${s['sessions']} session(s)',
                    style: const TextStyle(fontSize: 12)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (((s['average'] as num?) ?? 0) / 100).clamp(0, 1).toDouble(),
                  minHeight: 8,
                  color: BookNestColors.cyan,
                  backgroundColor: BookNestColors.cyan.withValues(alpha: .12),
                ),
              ),
            ]),
          ),
        const SizedBox(height: 12),
        const Text('Recent',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        for (final r in recent)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(r['mode'] == 'study'
                ? Icons.menu_book_rounded
                : Icons.timer_outlined),
            title: Text('${r['subject']} · ${r['mode'] == 'study' ? 'Study' : 'Mock'}'),
            subtitle: Text(
                '${cbtWhen(cbtDate(r['at']))} · ${((r['seconds'] as num?) ?? 0) ~/ 60} min'),
            trailing: Text('${cbtNum(r['score'])}/${cbtNum(r['total'])}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
      ],
    );
  }
}

/// ── A practice session: study (answers as you go) or a timed mock ──────
class CbtPracticeSessionScreen extends StatefulWidget {
  const CbtPracticeSessionScreen({
    super.key,
    required this.schoolId,
    required this.subject,
    required this.questions,
    required this.mock,
    this.minutes = 0,
  });

  final String schoolId;
  final String subject;
  final List<Map<String, dynamic>> questions;
  final bool mock;
  final int minutes;

  @override
  State<CbtPracticeSessionScreen> createState() =>
      _CbtPracticeSessionScreenState();
}

class _CbtPracticeSessionScreenState extends State<CbtPracticeSessionScreen> {
  late final List<Map<String, dynamic>> _qs = widget.questions;
  final Map<int, int> _picked = {};
  final Set<String> _saved = {};
  List<Map<String, dynamic>> _bookmarks = [];
  int _index = 0;
  bool _finished = false;
  final _clock = Stopwatch()..start();
  Timer? _tick;
  late DateTime _ends =
      DateTime.now().add(Duration(minutes: widget.minutes));

  bool get _mock => widget.mock;
  List<int> get _mcqIndexes =>
      [for (var i = 0; i < _qs.length; i++) if (_qs[i]['type'] != 'theory') i];

  @override
  void initState() {
    super.initState();
    _Bookmarks.load(widget.schoolId).then((list) {
      if (!mounted) return;
      setState(() {
        _bookmarks = list;
        _saved.addAll(list.map((q) => '${q['id']}'));
      });
    });
    if (_mock) {
      _ends = DateTime.now().add(Duration(minutes: widget.minutes));
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _finished) return;
        if (DateTime.now().isAfter(_ends)) {
          _finish();
        } else {
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  int get _correct => _picked.entries
      .where((e) => (_qs[e.key]['answer'] as num?)?.toInt() == e.value)
      .length;

  Future<void> _finish() async {
    if (_finished) return;
    _clock.stop();
    _tick?.cancel();
    setState(() => _finished = true);
    final total = _mock ? _mcqIndexes.length : _picked.length;
    if (total == 0) return;
    BackendApi.instance.call('cbt.practice.record', {
      'schoolId': widget.schoolId,
      'subject': widget.subject.startsWith('"') ? 'Search' : widget.subject,
      'score': _correct,
      'total': total,
      'seconds': _clock.elapsed.inSeconds,
      'mode': _mock ? 'mock' : 'study',
    });
  }

  Future<void> _toggleSave(Map<String, dynamic> q) async {
    final id = '${q['id']}';
    setState(() {
      if (_saved.contains(id)) {
        _saved.remove(id);
        _bookmarks.removeWhere((b) => '${b['id']}' == id);
      } else {
        _saved.add(id);
        _bookmarks.insert(0, q);
      }
    });
    await _Bookmarks.save(widget.schoolId, _bookmarks);
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _ends.difference(DateTime.now());
    return PopScope(
      canPop: _finished || !_mock,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          if (!_mock && !_finished && _picked.isNotEmpty) _finish();
          return;
        }
        final leave = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('End this mock exam?'),
            content: const Text('Your answers so far will be marked.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(d, false),
                  child: const Text('Continue')),
              FilledButton(
                  onPressed: () => Navigator.pop(d, true),
                  child: const Text('End & mark')),
            ],
          ),
        );
        if (leave == true) _finish();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.subject, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            if (!_finished)
              IconButton(
                tooltip: 'Calculator',
                onPressed: () => showCbtCalculator(context),
                icon: const Icon(Icons.calculate_outlined),
              ),
            if (_mock && !_finished)
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Center(
                  child: Text(cbtCountdown(remaining),
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: remaining.inSeconds < 60
                              ? Colors.redAccent
                              : BookNestColors.cyan)),
                ),
              ),
          ],
        ),
        body: _finished && _mock ? _review() : _question(),
      ),
    );
  }

  Widget _question() {
    final q = _qs[_index];
    final options = ((q['options'] as List?) ?? const []).map((e) => '$e').toList();
    final answer = (q['answer'] as num?)?.toInt() ?? -1;
    final picked = _picked[_index];
    final reveal = !_mock && picked != null;
    final theory = q['type'] == 'theory';
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final last = _index == _qs.length - 1;
    return Column(children: [
      LinearProgressIndicator(
        value: (_index + 1) / _qs.length,
        minHeight: 3,
        color: BookNestColors.cyan,
        backgroundColor: onSurface.withValues(alpha: .08),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(
                        'Question ${_index + 1} of ${_qs.length}'
                        '${'${q['year'] ?? ''}'.isNotEmpty ? ' · ${q['year']}' : ''}'
                        '${'${q['topic'] ?? ''}'.isNotEmpty ? ' · ${q['topic']}' : ''}',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: onSurface.withValues(alpha: .6))),
                  ),
                  IconButton(
                    tooltip: 'Save question',
                    onPressed: () => _toggleSave(q),
                    icon: Icon(
                        _saved.contains('${q['id']}')
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        color: BookNestColors.cyan),
                  ),
                ]),
                const SizedBox(height: 6),
                SelectableText(q['text']?.toString() ?? '',
                    style: const TextStyle(fontSize: 17, height: 1.45)),
                if ('${q['imageUrl'] ?? ''}'.startsWith('https://'))
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(q['imageUrl'].toString(),
                          errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                    ),
                  ),
                const SizedBox(height: 16),
                if (theory) ...[
                  Text('Theory question — think it through, then check the guide.',
                      style: TextStyle(color: onSurface.withValues(alpha: .7))),
                  if ('${q['explanation'] ?? ''}'.isNotEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Show answer guide'),
                      children: [Text(q['explanation'].toString())],
                    ),
                ] else
                  for (var k = 0; k < options.length; k++)
                    _option(k, options[k], picked, answer, reveal, onSurface),
                if (reveal) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (picked == answer
                              ? const Color(0xFF00B894)
                              : Colors.redAccent)
                          .withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              picked == answer
                                  ? 'Correct!'
                                  : 'The answer is ${cbtLetters[answer.clamp(0, 5)]}.',
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                          if ('${q['explanation'] ?? ''}'.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(q['explanation'].toString()),
                          ],
                        ]),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Row(children: [
            OutlinedButton.icon(
              onPressed: _index == 0 ? null : () => setState(() => _index--),
              icon: const Icon(Icons.chevron_left_rounded),
              label: const Text('Prev'),
            ),
            const Spacer(),
            if (_mock)
              Text('${_picked.length}/${_mcqIndexes.length} answered',
                  style: const TextStyle(fontSize: 12.5)),
            const Spacer(),
            if (last)
              FilledButton(
                onPressed: () {
                  if (_mock) {
                    _finish();
                  } else {
                    _finish();
                    Navigator.of(context).pop();
                  }
                },
                child: Text(_mock ? 'Submit' : 'Finish'),
              )
            else
              FilledButton.icon(
                onPressed: () => setState(() => _index++),
                icon: const Icon(Icons.chevron_right_rounded),
                label: const Text('Next'),
              ),
          ]),
        ),
      ),
    ]);
  }

  Widget _option(int k, String text, int? picked, int answer, bool reveal,
      Color onSurface) {
    Color border = onSurface.withValues(alpha: .12);
    Color? fill;
    if (reveal && k == answer) {
      border = const Color(0xFF00B894);
      fill = const Color(0xFF00B894).withValues(alpha: .12);
    } else if (reveal && k == picked) {
      border = Colors.redAccent;
      fill = Colors.redAccent.withValues(alpha: .1);
    } else if (!reveal && k == picked) {
      border = BookNestColors.cyan;
      fill = BookNestColors.cyan.withValues(alpha: .14);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: fill ?? onSurface.withValues(alpha: .04),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: border, width: 1.4)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: reveal ? null : () => setState(() => _picked[_index] = k),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(children: [
              Text('${cbtLetters[k]}.',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 15.5))),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _review() {
    final total = _mcqIndexes.length;
    final pct = total == 0 ? 0 : _correct / total * 100;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Center(
          child: Column(children: [
            Text('$_correct / $total',
                style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    color: BookNestColors.cyan)),
            Text('${pct.toStringAsFixed(0)}% · ${_clock.elapsed.inMinutes} min '
                '${_clock.elapsed.inSeconds % 60} s'),
            const SizedBox(height: 18),
          ]),
        ),
        for (final i in _mcqIndexes)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Builder(builder: (_) {
                    final q = _qs[i];
                    final options = ((q['options'] as List?) ?? const [])
                        .map((e) => '$e')
                        .toList();
                    final answer = (q['answer'] as num?)?.toInt() ?? -1;
                    final picked = _picked[i];
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(
                                picked == answer
                                    ? Icons.check_circle_rounded
                                    : Icons.cancel_rounded,
                                size: 20,
                                color: picked == answer
                                    ? const Color(0xFF00B894)
                                    : Colors.redAccent),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text('${i + 1}. ${q['text']}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600))),
                            IconButton(
                              onPressed: () => _toggleSave(q),
                              icon: Icon(
                                  _saved.contains('${q['id']}')
                                      ? Icons.bookmark_rounded
                                      : Icons.bookmark_border_rounded,
                                  color: BookNestColors.cyan),
                            ),
                          ]),
                          if (picked != null && picked != answer &&
                              picked < options.length)
                            Text('Your answer: ${cbtLetters[picked]}. ${options[picked]}',
                                style: const TextStyle(color: Colors.redAccent)),
                          if (picked == null)
                            Text('Not answered',
                                style: TextStyle(color: onSurface.withValues(alpha: .6))),
                          if (answer >= 0 && answer < options.length)
                            Text('Answer: ${cbtLetters[answer]}. ${options[answer]}',
                                style: const TextStyle(
                                    color: Color(0xFF00B894),
                                    fontWeight: FontWeight.w700)),
                          if ('${q['explanation'] ?? ''}'.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(q['explanation'].toString(),
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: onSurface.withValues(alpha: .75))),
                            ),
                        ]);
                  }),
                ),
              ),
            ),
          ),
        const SizedBox(height: 10),
        Center(
          child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done')),
        ),
      ],
    );
  }
}
