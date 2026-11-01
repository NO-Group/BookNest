import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../components/adaptive.dart';
import '../../components/booknest_ui.dart';
import 'group_base_screen.dart';
import 'school_cbt_authoring.dart';
import 'school_cbt_common.dart';
import 'school_cbt_practice.dart';

/// ── School CBT ─────────────────────────────────────────────────────────
/// Distance-learning exams the MySchool way, for the school's own
/// students: teachers set papers, questions stay locked on the server until
/// the start time, each student gets one timed attempt, and leaving the
/// exam (switching apps, going home, closing the app) submits it.
class SchoolCbtSection extends StatefulWidget {
  const SchoolCbtSection({required this.state, super.key});

  final GroupBaseScreenState state;

  @override
  State<SchoolCbtSection> createState() => _SchoolCbtSectionState();
}

class _SchoolCbtSectionState extends State<SchoolCbtSection> {
  List<Map<String, dynamic>> _exams = [];
  List<Map<String, dynamic>> _dates = [];
  bool _loading = true;
  bool _staff = false;
  bool _manager = false;
  List<String> _teacherIds = [];
  Duration _skew = Duration.zero;
  Timer? _tick;

  String get _schoolId => widget.state.groupId;

  @override
  void initState() {
    super.initState();
    _load();
    // Countdowns tick and an upcoming exam flips to "live" on its own.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _exams.isNotEmpty) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  DateTime get _now => DateTime.now().add(_skew);

  Future<void> _load() async {
    final role = await BackendApi.instance
        .call('cbt.role', {'schoolId': _schoolId});
    final res = await BackendApi.instance
        .call('cbt.exam.list', {'schoolId': _schoolId});
    final dates = await BackendApi.instance
        .call('schools.exam.list', {'schoolId': _schoolId});
    if (!mounted) return;
    setState(() {
      _loading = false;
      _staff = role?['staff'] == true;
      _manager = role?['manager'] == true;
      _teacherIds = ((role?['teacherIds'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList();
      _exams = cbtList(res?['exams']);
      final cutoff = DateTime.now().subtract(const Duration(days: 2));
      _dates = cbtList(dates?['exams'])
          .where((d) => (cbtDate(d['at']) ?? DateTime(2100)).isAfter(cutoff))
          .toList();
      final server = cbtDate(res?['serverNow']);
      if (server != null) _skew = server.difference(DateTime.now());
    });
  }

  String _statusOf(Map<String, dynamic> e) {
    final start = cbtDate(e['startsAt']);
    final end = cbtDate(e['endsAt']);
    if (start == null || end == null) return 'closed';
    if (_now.isBefore(start)) return 'upcoming';
    if (_now.isBefore(end)) return 'live';
    return 'closed';
  }

  Future<void> _push(Widget page) async {
    await Navigator.of(context, rootNavigator: true)
        .push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) _load();
  }

  Future<void> _enter(Map<String, dynamic> exam) async {
    final strict = exam['strictExit'] != false;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.assignment_turned_in_rounded,
            color: BookNestColors.cyan, size: 34),
        title: Text(exam['title']?.toString() ?? 'Exam'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                      '${exam['questionCount']} questions · ${cbtNum(exam['totalMarks'])} marks · '
                      '${exam['durationMin']} minutes',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  if ((exam['instructions']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(exam['instructions'].toString()),
                  ],
                  const SizedBox(height: 14),
                  _rule(Icons.timer_outlined,
                      'The timer starts the moment you enter and does not pause.',
                      onSurface),
                  _rule(Icons.cloud_done_outlined,
                      'Your answers save automatically as you go.', onSurface),
                  _rule(
                      Icons.block_rounded,
                      strict
                          ? 'Do NOT leave the exam. Switching apps, going to '
                              'the home screen, locking the phone or closing '
                              'BookNest submits your exam immediately.'
                          : 'Leaving the exam is recorded and shown to your '
                              'teacher.',
                      strict ? Colors.redAccent : onSurface),
                  _rule(Icons.looks_one_outlined,
                      'You have one attempt. You cannot re-enter after you submit.',
                      onSurface),
                ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Not yet')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Start exam'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    await _push(CbtExamRoomScreen(
        examId: exam['id'].toString(),
        title: exam['title']?.toString() ?? 'Exam'));
  }

  Widget _rule(IconData icon, String text, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color))),
        ]),
      );

  Future<void> _delete(Map<String, dynamic> exam) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete exam?'),
        content: Text(
            '"${exam['title']}" and every student\'s script will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final res = await cbtCall(
        context, 'cbt.exam.delete', {'examId': exam['id']},
        fallback: 'Could not delete the exam.');
    if (res != null) _load();
  }

  Future<void> _manageTeachers() async {
    final members = widget.state.members;
    final names = widget.state.memberNames;
    final chosen = {..._teacherIds};
    await showAdaptiveSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setLocal) => SheetBody(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('CBT teachers',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text(
                      'Teachers can build the question bank, set exams and '
                      'mark scripts. Class teachers, the owner and the deputy '
                      'already can.',
                      style: TextStyle(fontSize: 12.5)),
                  const SizedBox(height: 8),
                  if (members.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('No members yet.'),
                    ),
                  for (final m in members)
                    Builder(builder: (_) {
                      final id = (m['user_id'] ?? m['userId'])
                              ?.toString() ??
                          '';
                      if (id.isEmpty || id == widget.state.viewerId) {
                        return const SizedBox.shrink();
                      }
                      return SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: BookNestColors.cyan,
                        value: chosen.contains(id),
                        title: Text(names[id] ?? 'Member'),
                        onChanged: (v) async {
                          final res = await cbtCall(
                              context,
                              'cbt.teachers.set',
                              {'schoolId': _schoolId, 'userId': id, 'teacher': v});
                          if (res != null) {
                            setLocal(() => v ? chosen.add(id) : chosen.remove(id));
                          }
                        },
                      );
                    }),
                ]),
          ),
        ),
      ),
    );
    _load();
  }

  Future<void> _duplicate(Map<String, dynamic> exam) async {
    final res = await cbtCall(
        context, 'cbt.exam.duplicate', {'examId': exam['id']},
        fallback: 'Could not copy the exam.');
    if (res == null || !mounted) return;
    cbtToast(context, 'Copied as a draft — set the new date, then publish.');
    _push(CbtSetExamScreen(
        schoolId: _schoolId, examId: res['exam']['id'].toString()));
  }

  /// A paper exam sat in class — just a date on the calendar.
  Future<void> _addDate() async {
    final title = TextEditingController();
    final subject = TextEditingController();
    var at = DateTime.now().add(const Duration(days: 7));
    at = DateTime(at.year, at.month, at.day, 9);
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Add an exam date'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text(
                    'For exams written in class (not on BookNest). Students '
                    'see a countdown.',
                    style: TextStyle(fontSize: 12.5)),
                const SizedBox(height: 10),
                TextField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'Title')),
                TextField(
                    controller: subject,
                    decoration: const InputDecoration(labelText: 'Subject')),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(cbtWhen(at)),
                  trailing: const Icon(Icons.edit_calendar_rounded),
                  onTap: () async {
                    final d = await showDatePicker(
                        context: context,
                        initialDate: at,
                        firstDate: DateTime.now()
                            .subtract(const Duration(days: 1)),
                        lastDate:
                            DateTime.now().add(const Duration(days: 730)));
                    if (d == null || !context.mounted) return;
                    final t = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(at));
                    setLocal(() => at = DateTime(d.year, d.month, d.day,
                        t?.hour ?? at.hour, t?.minute ?? at.minute));
                  },
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Add')),
          ],
        ),
      ),
    );
    if (save != true || title.text.trim().isEmpty || !mounted) return;
    final res = await cbtCall(context, 'schools.exam.create', {
      'schoolId': _schoolId,
      'title': title.text.trim(),
      'subject': subject.text.trim(),
      'at': at.toUtc().toIso8601String(),
    }, fallback: 'Could not add the date.');
    if (res != null) _load();
  }

  Future<void> _removeDate(Map<String, dynamic> d) async {
    final res = await cbtCall(
        context, 'schools.exam.delete', {'examId': d['id']},
        fallback: 'Could not remove the date.');
    if (res != null) _load();
  }

  Widget _datesGroup() {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('WRITTEN IN CLASS',
            style: TextStyle(
                fontSize: 11,
                letterSpacing: .8,
                fontWeight: FontWeight.w800,
                color: onSurface.withValues(alpha: .5))),
        for (final d in _dates)
          Builder(builder: (_) {
            final at = cbtDate(d['at']);
            final left = at?.difference(_now);
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_document,
                  color: BookNestColors.cyan, size: 22),
              title: Text(d['title']?.toString() ?? 'Exam',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text([
                if ((d['subject']?.toString() ?? '').isNotEmpty) d['subject'],
                cbtWhen(at),
              ].join(' · ')),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (left != null && !left.isNegative)
                  Text(cbtCountdown(left),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: BookNestColors.cyan)),
                if (_staff)
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => _removeDate(d),
                  ),
              ]),
            );
          }),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final member = widget.state.isMember || _staff;
    final live = _exams.where((e) => _statusOf(e) == 'live').toList();
    final upcoming = _exams.where((e) => _statusOf(e) == 'upcoming').toList()
      ..sort((a, b) => '${a['startsAt']}'.compareTo('${b['startsAt']}'));
    final closed = _exams.where((e) => _statusOf(e) == 'closed').toList();
    return GlassPanel(
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.fact_check_rounded,
                size: 19, color: BookNestColors.cyan),
            const SizedBox(width: 8),
            Expanded(
              child: Text('CBT & exams',
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: onSurface)),
            ),
            if (_manager)
              IconButton(
                tooltip: 'CBT teachers',
                onPressed: _manageTeachers,
                icon: const Icon(Icons.manage_accounts_rounded,
                    color: BookNestColors.cyan),
              ),
          ]),
          const SizedBox(height: 8),
          if (!member && !_loading)
            Text('Join the school to practise and sit its exams.',
                style:
                    TextStyle(fontSize: 12.5, color: onSurface.withValues(alpha: .6)))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              _chip(Icons.school_rounded, 'Practice', () {
                _push(CbtPracticeScreen(
                    schoolId: _schoolId, staff: _staff));
              }),
              if (_staff) ...[
                _chip(Icons.add_task_rounded, 'Set exam', () {
                  _push(CbtSetExamScreen(schoolId: _schoolId));
                }),
                _chip(Icons.inventory_2_rounded, 'Question bank', () {
                  _push(CbtQuestionBankScreen(schoolId: _schoolId));
                }),
                _chip(Icons.event_note_rounded, 'Exam date', _addDate),
              ],
            ]),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: BookNestColors.cyan)),
            )
          else if (member) ...[
            if (_exams.isEmpty && _dates.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                    _staff
                        ? 'No exams yet — tap "Set exam" to schedule one. '
                            'Questions stay locked until it starts.'
                        : 'No exams scheduled for you yet.',
                    style: TextStyle(
                        fontSize: 12.5, color: onSurface.withValues(alpha: .6))),
              ),
            if (live.isNotEmpty) _group('Live now', live),
            if (upcoming.isNotEmpty) _group('Upcoming', upcoming),
            if (_dates.isNotEmpty) _datesGroup(),
            if (closed.isNotEmpty) _group('Past', closed.take(8).toList()),
          ],
        ]),
      ),
    );
  }

  Widget _chip(IconData icon, String label, VoidCallback onTap) => ActionChip(
        avatar: Icon(icon, size: 18, color: BookNestColors.cyan),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        onPressed: onTap,
      );

  Widget _group(String title, List<Map<String, dynamic>> exams) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                letterSpacing: .8,
                fontWeight: FontWeight.w800,
                color: onSurface.withValues(alpha: .5))),
        for (final e in exams) _examTile(e),
      ]),
    );
  }

  Widget _examTile(Map<String, dynamic> e) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final status = _statusOf(e);
    final start = cbtDate(e['startsAt']);
    final end = cbtDate(e['endsAt']);
    final mine = e['myAttempt'] is Map
        ? Map<String, dynamic>.from(e['myAttempt'] as Map)
        : null;
    final done = mine != null && mine['status'] != 'in_progress';
    String line;
    if (status == 'upcoming') {
      line = 'Opens in ${cbtCountdown(start!.difference(_now))} · ${cbtWhen(start)}';
    } else if (status == 'live') {
      line = 'Closes in ${cbtCountdown(end!.difference(_now))}';
    } else {
      line = 'Closed ${cbtWhen(end)}';
    }
    final meta = [
      if ((e['subject']?.toString() ?? '').isNotEmpty) e['subject'],
      if (e['className'] != null) e['className'],
      '${e['questionCount']} Qs',
      '${e['durationMin']} min',
    ].join(' · ');
    Widget trailing;
    if (_staff) {
      trailing = PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'edit') {
            _push(CbtSetExamScreen(
                schoolId: _schoolId, examId: e['id'].toString()));
          } else if (v == 'results') {
            _push(CbtResultsScreen(
                examId: e['id'].toString(),
                title: e['title']?.toString() ?? 'Results'));
          } else if (v == 'duplicate') {
            _duplicate(e);
          } else if (v == 'delete') {
            _delete(e);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'results', child: Text('Results & marking')),
          PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(value: 'duplicate', child: Text('Duplicate (reuse paper)')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      );
    } else if (done) {
      final score = mine['score'];
      trailing = score == null
          ? const Chip(label: Text('Submitted'))
          : TextButton(
              onPressed: () => _push(CbtScriptScreen(
                  attemptId: mine['id'].toString(), staff: false)),
              child: Text('${cbtNum(score)}/${cbtNum(mine['total'])}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15)),
            );
    } else if (status == 'live') {
      trailing = FilledButton(
        onPressed: () => _enter(e),
        child: const Text('Enter'),
      );
    } else if (status == 'upcoming') {
      trailing = Icon(Icons.lock_clock_rounded,
          color: onSurface.withValues(alpha: .45));
    } else {
      trailing = Text('Missed',
          style: TextStyle(color: onSurface.withValues(alpha: .45)));
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: status == 'live'
                ? const [Color(0xFF00B894), Color(0xFF00806A)]
                : const [BookNestColors.navy, BookNestColors.navyDeep]),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
              status == 'upcoming'
                  ? Icons.lock_rounded
                  : status == 'live'
                      ? Icons.play_arrow_rounded
                      : Icons.check_rounded,
              color: status == 'live' ? Colors.white : BookNestColors.cyan,
              size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(e['title']?.toString() ?? 'Exam',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: onSurface)),
              ),
              if (_staff && e['published'] != true)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Text('DRAFT',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.orangeAccent)),
                ),
            ]),
            const SizedBox(height: 2),
            Text(meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5, color: onSurface.withValues(alpha: .6))),
            Text(
                _staff
                    ? '$line · ${e['attempts'] ?? 0} sat'
                    : done
                        ? (mine['score'] == null
                            ? 'Submitted — result not released yet'
                            : 'Submitted${(mine['theoryPending'] ?? 0) > 0 ? ' · theory being marked' : ''}')
                        : line,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: status == 'live'
                        ? const Color(0xFF00B894)
                        : onSurface.withValues(alpha: .6))),
          ]),
        ),
        const SizedBox(width: 6),
        trailing,
      ]),
    );
  }
}

/// ── The exam room ──────────────────────────────────────────────────────
class CbtExamRoomScreen extends StatefulWidget {
  const CbtExamRoomScreen(
      {super.key, required this.examId, required this.title});

  final String examId;
  final String title;

  @override
  State<CbtExamRoomScreen> createState() => _CbtExamRoomScreenState();
}

class _CbtExamRoomScreenState extends State<CbtExamRoomScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  String? _error;
  String _attemptId = '';
  DateTime? _deadline;
  Duration _skew = Duration.zero;
  Map<String, dynamic> _exam = {};
  List<Map<String, dynamic>> _questions = [];
  final Map<String, dynamic> _answers = {};
  final Map<String, TextEditingController> _theory = {};
  final Set<String> _flagged = {};
  int _index = 0;
  Timer? _tick;
  Timer? _saveTimer;
  Timer? _grace;
  bool _dirty = false;
  bool _submitting = false;
  Map<String, dynamic>? _done;

  bool get _strict => _exam['strictExit'] != false;
  bool get _active => !_loading && _done == null && _attemptId.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _saveTimer?.cancel();
    _grace?.cancel();
    for (final c in _theory.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _start() async {
    final res = await BackendApi.instance
        .call('cbt.exam.start', {'examId': widget.examId});
    if (!mounted) return;
    if (res == null) {
      setState(() {
        _loading = false;
        _error = BackendApi.instance
            .errorOr('Could not open the exam — check your connection.');
      });
      return;
    }
    final attempt = Map<String, dynamic>.from(res['attempt'] as Map);
    final server = cbtDate(attempt['serverNow']);
    setState(() {
      _loading = false;
      _attemptId = attempt['id'].toString();
      _deadline = cbtDate(attempt['deadline']);
      if (server != null) _skew = server.difference(DateTime.now());
      _exam = Map<String, dynamic>.from(res['exam'] as Map);
      _questions = cbtList(res['questions']);
      final saved = (attempt['answers'] as Map?) ?? const {};
      saved.forEach((k, v) => _answers[k.toString()] = v);
      for (final q in _questions) {
        if (q['type'] == 'theory') {
          _theory[q['id'].toString()] = TextEditingController(
              text: _answers[q['id'].toString()]?.toString() ?? '');
        }
      }
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_active) return;
      if (_remaining <= Duration.zero) {
        _submit('time');
      } else {
        setState(() {});
      }
    });
  }

  Duration get _remaining {
    final d = _deadline;
    if (d == null) return Duration.zero;
    return d.difference(DateTime.now().add(_skew));
  }

  // ── anti-cheat: leaving the exam submits it ──
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_active) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _grace?.cancel();
        break;
      case AppLifecycleState.inactive:
        // The notification shade, an incoming call screen or another
        // window taking focus. A short grace covers accidental pulls;
        // staying away submits.
        if (_strict) {
          _grace?.cancel();
          _grace = Timer(const Duration(seconds: 3), () {
            if (_active) _submit('left_app');
          });
        }
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _grace?.cancel();
        if (_strict) {
          _submit('left_app');
        } else {
          BackendApi.instance.call('cbt.attempt.event',
              {'attemptId': _attemptId, 'type': state.name});
        }
        break;
    }
  }

  void _answer(String qid, Object value) {
    setState(() => _answers[qid] = value);
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1200), _flush);
  }

  Future<void> _flush() async {
    if (!_dirty || !_active) return;
    _dirty = false;
    final res = await BackendApi.instance.call('cbt.attempt.save',
        {'attemptId': _attemptId, 'answers': Map.of(_answers)});
    if (res == null && mounted) {
      _dirty = true; // try again with the next change or on submit
      if ((BackendApi.instance.lastError ?? '').contains('Time is up')) {
        _submit('time');
      }
    }
  }

  Future<void> _submit(String reason) async {
    if (_submitting || _done != null) return;
    _submitting = true;
    _tick?.cancel();
    _saveTimer?.cancel();
    _grace?.cancel();
    if (mounted) setState(() {});
    final payload = {
      'attemptId': _attemptId,
      'answers': Map.of(_answers),
      'reason': reason,
    };
    Map<String, dynamic>? res;
    for (var tries = 0; tries < 4 && res == null; tries++) {
      res = await BackendApi.instance.call('cbt.attempt.submit', payload);
      if (res == null) {
        await Future<void>.delayed(Duration(seconds: 2 + tries * 2));
      }
    }
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _done = res ??
          {
            'status': 'offline',
            'reason': reason,
          };
    });
  }

  Future<void> _confirmSubmit() async {
    final answered = _questions.where((q) => _isAnswered(q)).length;
    final left = _questions.length - answered;
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Submit your exam?'),
        content: Text(left == 0
            ? 'You answered every question. You can\'t change your answers after submitting.'
            : 'You have $left unanswered question${left == 1 ? '' : 's'}. You can\'t change your answers after submitting.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep writing')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Submit')),
        ],
      ),
    );
    if (sure == true) _submit('manual');
  }

  bool _isAnswered(Map<String, dynamic> q) {
    final v = _answers[q['id'].toString()];
    if (v == null) return false;
    return v is num || v.toString().trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_active,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _active) _confirmSubmit();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !_active,
          title: Text(_exam['title']?.toString() ?? widget.title,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            if (_active) ...[
              IconButton(
                tooltip: 'Calculator',
                onPressed: () => showCbtCalculator(context),
                icon: const Icon(Icons.calculate_outlined),
              ),
              _timerChip(),
              const SizedBox(width: 10),
            ],
          ],
        ),
        body: _body(),
      ),
    );
  }

  Widget _timerChip() {
    final r = _remaining;
    final low = r.inSeconds <= 300;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (low ? Colors.redAccent : BookNestColors.cyan).withValues(alpha: .15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.timer_rounded,
            size: 17, color: low ? Colors.redAccent : BookNestColors.cyan),
        const SizedBox(width: 5),
        Text(
          r.inHours > 0
              ? '${r.inHours}:${cbtTwo(r.inMinutes % 60)}:${cbtTwo(r.inSeconds % 60)}'
              : '${cbtTwo(r.inMinutes)}:${cbtTwo(r.inSeconds % 60)}',
          style: TextStyle(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: low ? Colors.redAccent : BookNestColors.cyan),
        ),
      ]),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: BookNestColors.cyan));
    }
    if (_error != null) {
      return _message(Icons.lock_clock_rounded, 'Can\'t open this exam', _error!);
    }
    if (_submitting) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: BookNestColors.cyan),
          SizedBox(height: 14),
          Text('Submitting your exam…'),
        ]),
      );
    }
    if (_done != null) return _result();
    if (_questions.isEmpty) {
      return _message(Icons.help_outline, 'No questions',
          'This exam has no questions yet.');
    }
    final wide = context.isExpanded;
    final paper = _questionPane();
    if (wide) {
      return Row(children: [
        Expanded(child: paper),
        const VerticalDivider(width: 1),
        SizedBox(width: 320, child: _navigator(compact: false)),
      ]);
    }
    return paper;
  }

  Widget _message(IconData icon, String title, String body) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: BookNestColors.cyan),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Back to school')),
          ]),
        ),
      );

  Widget _result() {
    final done = _done!;
    final reason = done['reason']?.toString() ?? '';
    final result =
        done['result'] is Map ? Map<String, dynamic>.from(done['result'] as Map) : null;
    final offline = done['status'] == 'offline';
    final headline = offline
        ? 'Answers saved'
        : reason == 'left_app'
            ? 'Exam submitted — you left the exam'
            : reason == 'time'
                ? 'Time up — exam submitted'
                : 'Exam submitted';
    final note = offline
        ? 'We could not reach BookNest to submit. Your answers were saved as '
            'you went; the exam will be closed automatically when the time '
            'runs out.'
        : reason == 'left_app'
            ? 'Leaving the exam screen ends the attempt. Your saved answers '
                'were submitted and your teacher can see why.'
            : 'Well done for finishing.';
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(
                reason == 'left_app'
                    ? Icons.exit_to_app_rounded
                    : Icons.verified_rounded,
                size: 60,
                color: reason == 'left_app'
                    ? Colors.orangeAccent
                    : BookNestColors.cyan),
            const SizedBox(height: 14),
            Text(headline,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(note, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            if (result != null) ...[
              Text('${cbtNum(result['score'])} / ${cbtNum(result['total'])}',
                  style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      color: BookNestColors.cyan)),
              Text('${result['correct']} objective correct'
                  '${(result['theoryPending'] ?? 0) > 0 ? ' · theory answers will be marked by your teacher' : ''}'),
            ] else if (!offline)
              const Text('Your teacher will release the results.',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 24),
            FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done')),
          ]),
        ),
      ),
    );
  }

  Widget _questionPane() {
    final q = _questions[_index];
    final qid = q['id'].toString();
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final options = cbtList(q['options']);
    final last = _index == _questions.length - 1;
    return Column(children: [
      LinearProgressIndicator(
        value: _questions.where(_isAnswered).length / _questions.length,
        minHeight: 3,
        color: BookNestColors.cyan,
        backgroundColor: onSurface.withValues(alpha: .08),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('Question ${_index + 1} of ${_questions.length}',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: onSurface.withValues(alpha: .6))),
                      const Spacer(),
                      Text('${cbtNum(q['marks'])} mark${q['marks'] == 1 ? '' : 's'}',
                          style: TextStyle(color: onSurface.withValues(alpha: .6))),
                      IconButton(
                        tooltip: 'Flag for review',
                        onPressed: () => setState(() => _flagged.contains(qid)
                            ? _flagged.remove(qid)
                            : _flagged.add(qid)),
                        icon: Icon(
                            _flagged.contains(qid)
                                ? Icons.flag_rounded
                                : Icons.outlined_flag_rounded,
                            color: _flagged.contains(qid)
                                ? Colors.orangeAccent
                                : null),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    SelectableText(q['text']?.toString() ?? '',
                        style: const TextStyle(fontSize: 17, height: 1.45)),
                    if ((q['imageUrl']?.toString() ?? '').startsWith('https://'))
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(q['imageUrl'].toString(),
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox.shrink()),
                        ),
                      ),
                    const SizedBox(height: 18),
                    if (q['type'] == 'theory')
                      TextField(
                        controller: _theory[qid],
                        minLines: 6,
                        maxLines: 18,
                        onChanged: (v) => _answer(qid, v),
                        decoration: const InputDecoration(
                          hintText: 'Write your answer here…',
                          border: OutlineInputBorder(),
                        ),
                      )
                    else
                      for (var i = 0; i < options.length; i++)
                        _optionTile(qid, i, options[i]),
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
            if (!context.isExpanded)
              TextButton.icon(
                onPressed: _openNavigator,
                icon: const Icon(Icons.grid_view_rounded),
                label: Text('${_questions.where(_isAnswered).length}/${_questions.length}'),
              ),
            const Spacer(),
            if (last)
              FilledButton.icon(
                onPressed: _confirmSubmit,
                icon: const Icon(Icons.send_rounded),
                label: const Text('Submit'),
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

  Widget _optionTile(String qid, int i, Map<String, dynamic> option) {
    final k = (option['k'] as num?)?.toInt() ?? i;
    final selected = _answers[qid] is num && (_answers[qid] as num).toInt() == k;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected
            ? BookNestColors.cyan.withValues(alpha: .14)
            : onSurface.withValues(alpha: .04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
              color: selected
                  ? BookNestColors.cyan
                  : onSurface.withValues(alpha: .12),
              width: selected ? 1.6 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _answer(qid, k),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(children: [
              CircleAvatar(
                radius: 14,
                backgroundColor:
                    selected ? BookNestColors.cyan : onSurface.withValues(alpha: .1),
                child: Text(cbtLetters[i],
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: selected ? BookNestColors.navyDeep : onSurface)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(option['t']?.toString() ?? '',
                    style: const TextStyle(fontSize: 15.5)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _openNavigator() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
          child: _navigator(
              compact: true, onPick: () => Navigator.pop(sheetContext))),
    );
  }

  Widget _navigator({required bool compact, VoidCallback? onPick}) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final answered = _questions.where(_isAnswered).length;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Text('$answered of ${_questions.length} answered',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Wrap(spacing: 12, children: [
              _legend(BookNestColors.cyan, 'Answered'),
              _legend(Colors.orangeAccent, 'Flagged'),
              _legend(onSurface.withValues(alpha: .15), 'Not yet'),
            ]),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (var i = 0; i < _questions.length; i++)
                    _navCell(i, onPick),
                ]),
              ),
            ),
            if (!compact) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _confirmSubmit,
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Submit exam'),
                ),
              ),
              const SizedBox(height: 8),
              if (_strict)
                Text('Leaving this window submits your exam.',
                    style: TextStyle(
                        fontSize: 12, color: Colors.redAccent.withValues(alpha: .9))),
            ],
          ]),
    );
  }

  Widget _legend(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 10,
              height: 10,
              decoration:
                  BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11.5)),
        ],
      );

  Widget _navCell(int i, VoidCallback? onPick) {
    final q = _questions[i];
    final answered = _isAnswered(q);
    final flagged = _flagged.contains(q['id'].toString());
    final current = i == _index;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final bg = flagged
        ? Colors.orangeAccent
        : answered
            ? BookNestColors.cyan
            : onSurface.withValues(alpha: .08);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        setState(() => _index = i);
        onPick?.call();
      },
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: current
              ? Border.all(color: onSurface, width: 2)
              : null,
        ),
        child: Text('${i + 1}',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: answered || flagged ? BookNestColors.navyDeep : onSurface)),
      ),
    );
  }
}

/// ── Results & marking (teachers) ───────────────────────────────────────
class CbtResultsScreen extends StatefulWidget {
  const CbtResultsScreen({super.key, required this.examId, required this.title});

  final String examId;
  final String title;

  @override
  State<CbtResultsScreen> createState() => _CbtResultsScreenState();
}

class _CbtResultsScreenState extends State<CbtResultsScreen> {
  bool _loading = true;
  Map<String, dynamic> _exam = {};
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await cbtCall(context, 'cbt.results', {'examId': widget.examId},
        fallback: 'Could not load results.');
    if (!mounted) return;
    setState(() {
      _loading = false;
      _exam = Map<String, dynamic>.from((res?['exam'] as Map?) ?? const {});
      _rows = cbtList(res?['attempts']);
      _items = cbtList(res?['items']);
    });
  }

  /// Item analysis: per question, how many got it right and how the
  /// picks spread — the questions everyone missed show what to reteach.
  Widget _analysis() {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final mcq = _items.where((i) => i['type'] == 'mcq').toList();
    if (mcq.isEmpty || _rows.isEmpty) return const SizedBox.shrink();
    double rate(Map<String, dynamic> i) {
      final sat = (i['sat'] as num?)?.toDouble() ?? 0;
      return sat <= 0 ? 0 : ((i['correct'] as num?) ?? 0) / sat * 100;
    }
    final hardest = [...mcq]..sort((a, b) => rate(a).compareTo(rate(b)));
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: const Icon(Icons.insights_rounded, color: BookNestColors.cyan),
        title: const Text('Question analysis',
            style: TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
            'Hardest: Q${mcq.indexOf(hardest.first) + 1} · '
            '${rate(hardest.first).toStringAsFixed(0)}% correct'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (var n = 0; n < _items.length; n++)
            if (_items[n]['type'] == 'mcq')
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Builder(builder: (_) {
                  final i = _items[n];
                  final r = rate(i);
                  final picks = ((i['picks'] as List?) ?? const [])
                      .map((e) => (e as num).toInt())
                      .toList();
                  final options = ((i['options'] as List?) ?? const [])
                      .map((e) => '$e')
                      .toList();
                  final answer = (i['answer'] as num?)?.toInt() ?? -1;
                  final sat = (i['sat'] as num?)?.toInt() ?? 0;
                  final color = r >= 70
                      ? const Color(0xFF00B894)
                      : r >= 40
                          ? Colors.orangeAccent
                          : Colors.redAccent;
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text('Q${n + 1}. ${i['text']}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 8),
                          Text('${r.toStringAsFixed(0)}%',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900, color: color)),
                        ]),
                        const SizedBox(height: 4),
                        Wrap(spacing: 10, runSpacing: 2, children: [
                          for (var k = 0; k < picks.length && k < options.length; k++)
                            Text(
                                '${cbtLetters[k]}${k == answer ? '✓' : ''} '
                                '${sat == 0 ? 0 : (picks[k] / sat * 100).round()}%',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: k == answer
                                        ? FontWeight.w800
                                        : FontWeight.w400,
                                    color: k == answer
                                        ? const Color(0xFF00B894)
                                        : onSurface.withValues(alpha: .7))),
                          Text(
                              'skipped ${sat - ((i['answered'] as num?)?.toInt() ?? 0)}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: onSurface.withValues(alpha: .5))),
                        ]),
                      ]);
                }),
              ),
        ],
      ),
    );
  }

  double _pct(Map<String, dynamic> r) {
    final total = (r['total'] as num?)?.toDouble() ?? 0;
    final score = (r['score'] as num?)?.toDouble() ?? 0;
    return total <= 0 ? 0 : score / total * 100;
  }

  Future<void> _release() async {
    final released = _exam['released'] == true;
    final res = await cbtCall(context, 'cbt.exam.release',
        {'examId': widget.examId, 'released': !released});
    if (res != null && mounted) {
      cbtToast(context,
          released ? 'Results hidden from students.' : 'Results released to students.');
      _load();
    }
  }

  void _copy() {
    final lines = <String>['Name,Score,Total,Percent,Status,Reason,Exits'];
    for (final r in _rows) {
      lines.add([
        '"${(r['name'] ?? '').toString().replaceAll('"', '""')}"',
        cbtNum(r['score']),
        cbtNum(r['total']),
        _pct(r).toStringAsFixed(1),
        r['status'],
        cbtReason(r['reason']),
        r['exits'] ?? 0,
      ].join(','));
    }
    Clipboard.setData(ClipboardData(text: lines.join('\n')));
    cbtToast(context, 'Copied — paste into Excel or Google Sheets.');
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final done = _rows.where((r) => r['status'] != 'in_progress').toList();
    final pass = (_exam['passMark'] as num?)?.toDouble() ?? 50;
    final avg = done.isEmpty
        ? 0.0
        : done.map(_pct).reduce((a, b) => a + b) / done.length;
    final passed = done.where((r) => _pct(r) >= pass).length;
    final best = done.isEmpty ? 0.0 : done.map(_pct).reduce((a, b) => a > b ? a : b);
    final pending = done.where((r) => (r['theoryPending'] ?? 0) > 0).length;
    return Scaffold(
      appBar: GlassAppBar(
        title: widget.title,
        actions: [
          IconButton(
              tooltip: 'Copy as spreadsheet',
              onPressed: _rows.isEmpty ? null : _copy,
              icon: const Icon(Icons.table_view_rounded)),
          IconButton(
              tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: BookNestColors.cyan))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(spacing: 10, runSpacing: 10, children: [
                              _stat('Sat', '${done.length}'),
                              _stat('Average', '${avg.toStringAsFixed(1)}%'),
                              _stat('Passed ($pass%)', '$passed'),
                              _stat('Highest', '${best.toStringAsFixed(1)}%'),
                              if (pending > 0) _stat('To mark', '$pending'),
                            ]),
                            const SizedBox(height: 12),
                            Card(
                              child: SwitchListTile(
                                activeThumbColor: BookNestColors.cyan,
                                value: _exam['released'] == true,
                                onChanged: (_) => _release(),
                                title: const Text('Results released'),
                                subtitle: Text(_exam['results'] == 'instant'
                                    ? 'Students see their score as soon as they submit.'
                                    : _exam['results'] == 'after_close'
                                        ? 'Students see scores when the exam closes, or now if released.'
                                        : 'Students see scores only after you release them.'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _analysis(),
                            if (_rows.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text('Nobody has sat this exam yet.',
                                    style: TextStyle(
                                        color: onSurface.withValues(alpha: .6))),
                              ),
                            for (var i = 0; i < _rows.length; i++)
                              _row(i + 1, _rows[i], pass),
                          ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _stat(String label, String value) => Container(
        width: 150,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: BookNestColors.cyan.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: BookNestColors.cyan)),
          Text(label, style: const TextStyle(fontSize: 12)),
        ]),
      );

  Widget _row(int rank, Map<String, dynamic> r, double pass) {
    final writing = r['status'] == 'in_progress';
    final pct = _pct(r);
    final reason = cbtReason(r['reason']);
    final flagged = r['reason'] == 'left_app' || r['reason'] == 'reentered' ||
        ((r['exits'] as num?) ?? 0) > 0;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: BookNestColors.navy,
          child: Text('$rank',
              style: const TextStyle(
                  color: BookNestColors.cyan, fontWeight: FontWeight.w800)),
        ),
        title: Text(r['name']?.toString() ?? 'Student',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(writing
            ? 'Writing now…'
            : [
                reason,
                if (((r['exits'] as num?) ?? 0) > 0) 'left ${r['exits']}×',
                if ((r['theoryPending'] ?? 0) > 0)
                  '${r['theoryPending']} theory to mark',
              ].where((s) => s.isNotEmpty).join(' · ')),
        trailing: writing
            ? const Icon(Icons.edit_rounded)
            : Row(mainAxisSize: MainAxisSize.min, children: [
                if (flagged)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.warning_amber_rounded,
                        color: Colors.orangeAccent, size: 20),
                  ),
                Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${cbtNum(r['score'])}/${cbtNum(r['total'])}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 15)),
                      Text('${pct.toStringAsFixed(0)}%',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: pct >= pass
                                  ? const Color(0xFF00B894)
                                  : Colors.redAccent)),
                    ]),
              ]),
        onTap: writing
            ? null
            : () async {
                await Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => CbtScriptScreen(
                        attemptId: r['id'].toString(), staff: true)));
                _load();
              },
      ),
    );
  }
}

/// One student's script: answers, the right answers, explanations, and
/// (for teachers) theory marking.
class CbtScriptScreen extends StatefulWidget {
  const CbtScriptScreen(
      {super.key, required this.attemptId, required this.staff});

  final String attemptId;
  final bool staff;

  @override
  State<CbtScriptScreen> createState() => _CbtScriptScreenState();
}

class _CbtScriptScreenState extends State<CbtScriptScreen> {
  bool _loading = true;
  Map<String, dynamic> _attempt = {};
  List<Map<String, dynamic>> _questions = [];
  final Map<String, TextEditingController> _marks = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _marks.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final res = await cbtCall(
        context, 'cbt.attempt.view', {'attemptId': widget.attemptId},
        fallback: 'Could not open the script.');
    if (!mounted) return;
    setState(() {
      _loading = false;
      _attempt = Map<String, dynamic>.from((res?['attempt'] as Map?) ?? const {});
      _questions = cbtList(res?['questions']);
      for (final q in _questions) {
        if (q['type'] == 'theory') {
          _marks.putIfAbsent(q['id'].toString(), () => TextEditingController())
              .text = q['awarded'] == null ? '' : cbtNum(q['awarded']);
        }
      }
    });
  }

  Future<void> _saveMarks() async {
    setState(() => _saving = true);
    final marks = <String, dynamic>{
      for (final e in _marks.entries)
        e.key: e.value.text.trim().isEmpty ? null : double.tryParse(e.value.text.trim()),
    };
    final res = await cbtCall(context, 'cbt.attempt.grade',
        {'attemptId': widget.attemptId, 'marks': marks},
        fallback: 'Could not save the marks.');
    if (!mounted) return;
    setState(() => _saving = false);
    if (res != null) {
      cbtToast(context, 'Saved — ${cbtNum(res['score'])}/${cbtNum(res['total'])}.');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final hasTheory = _questions.any((q) => q['type'] == 'theory');
    return Scaffold(
      appBar: GlassAppBar(title: _attempt['name']?.toString() ?? 'Script'),
      floatingActionButton: widget.staff && hasTheory
          ? FloatingActionButton.extended(
              onPressed: _saving ? null : _saveMarks,
              icon: const Icon(Icons.save_rounded),
              label: const Text('Save marks'),
            )
          : null,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: BookNestColors.cyan))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${cbtNum(_attempt['score'])} / ${cbtNum(_attempt['total'])}',
                              style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w900,
                                  color: BookNestColors.cyan)),
                          Text([
                            cbtReason(_attempt['reason']),
                            if (((_attempt['exits'] as num?) ?? 0) > 0)
                              'left the exam ${_attempt['exits']}×',
                            if (_attempt['submittedAt'] != null)
                              cbtWhen(cbtDate(_attempt['submittedAt'])),
                          ].where((s) => s.isNotEmpty).join(' · ')),
                          const SizedBox(height: 16),
                          for (var i = 0; i < _questions.length; i++)
                            _questionCard(i, _questions[i], onSurface),
                        ]),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _questionCard(int i, Map<String, dynamic> q, Color onSurface) {
    final options = ((q['options'] as List?) ?? const []).map((e) => '$e').toList();
    final given = q['given'];
    final answer = (q['answer'] as num?)?.toInt() ?? -1;
    final theory = q['type'] == 'theory';
    final right = !theory && given is num && given.toInt() == answer;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Q${i + 1}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            if (!theory)
              Icon(right ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  color: right ? const Color(0xFF00B894) : Colors.redAccent,
                  size: 20),
            const SizedBox(width: 6),
            Text(theory
                ? '${q['awarded'] == null ? '–' : cbtNum(q['awarded'])}/${cbtNum(q['marks'])}'
                : '${cbtNum(q['awarded'])}/${cbtNum(q['marks'])}'),
          ]),
          const SizedBox(height: 6),
          Text(q['text']?.toString() ?? '', style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 8),
          if (theory) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: onSurface.withValues(alpha: .05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                  (given?.toString() ?? '').trim().isEmpty
                      ? '(no answer)'
                      : given.toString()),
            ),
            if (widget.staff && (q['explanation']?.toString() ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Marking guide: ${q['explanation']}',
                    style: TextStyle(
                        fontSize: 12.5, color: onSurface.withValues(alpha: .7))),
              ),
            if (widget.staff)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _marks[q['id'].toString()],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'Marks (of ${cbtNum(q['marks'])})',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ),
          ] else ...[
            for (var k = 0; k < options.length; k++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Icon(
                      k == answer
                          ? Icons.check_rounded
                          : (given is num && given.toInt() == k)
                              ? Icons.close_rounded
                              : Icons.circle_outlined,
                      size: 16,
                      color: k == answer
                          ? const Color(0xFF00B894)
                          : (given is num && given.toInt() == k)
                              ? Colors.redAccent
                              : onSurface.withValues(alpha: .3)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${cbtLetters[k]}. ${options[k]}',
                        style: TextStyle(
                            fontWeight:
                                k == answer ? FontWeight.w700 : FontWeight.w400)),
                  ),
                ]),
              ),
            if (given == null)
              Text('Not answered',
                  style: TextStyle(
                      fontSize: 12, color: onSurface.withValues(alpha: .6))),
            if ((q['explanation']?.toString() ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Explanation: ${q['explanation']}',
                    style: TextStyle(
                        fontSize: 12.5, color: onSurface.withValues(alpha: .75))),
              ),
          ],
        ]),
      ),
    );
  }
}
