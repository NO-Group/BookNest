import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../components/adaptive.dart';
import '../../components/booknest_ui.dart';
import 'school_cbt_common.dart';

/// ── Set / edit an exam (teachers) ──────────────────────────────────────
class CbtSetExamScreen extends StatefulWidget {
  const CbtSetExamScreen({super.key, required this.schoolId, this.examId});

  final String schoolId;
  final String? examId;

  @override
  State<CbtSetExamScreen> createState() => _CbtSetExamScreenState();
}

class _CbtSetExamScreenState extends State<CbtSetExamScreen> {
  final _title = TextEditingController();
  final _subject = TextEditingController();
  final _instructions = TextEditingController();
  final _duration = TextEditingController(text: '60');
  final _window = TextEditingController(text: '75');
  final _passMark = TextEditingController(text: '50');
  DateTime _start = () {
    final t = DateTime.now().add(const Duration(days: 1));
    return DateTime(t.year, t.month, t.day, 9);
  }();
  String _classId = '';
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _questions = [];
  bool _shuffleQ = true;
  bool _shuffleO = true;
  bool _strict = true;
  String _results = 'after_close';
  bool _published = false;
  int _attempts = 0;
  bool _loading = true;
  bool _saving = false;

  bool get _locked => _attempts > 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final classes = await BackendApi.instance
        .call('schools.class.list', {'schoolId': widget.schoolId});
    Map<String, dynamic>? exam;
    if (widget.examId != null && mounted) {
      final res = await cbtCall(
          context, 'cbt.exam.get', {'examId': widget.examId},
          fallback: 'Could not open the exam.');
      exam = res?['exam'] is Map
          ? Map<String, dynamic>.from(res!['exam'] as Map)
          : null;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _classes = cbtList(classes?['classes']);
      if (exam != null) {
        _title.text = exam['title']?.toString() ?? '';
        _subject.text = exam['subject']?.toString() ?? '';
        _instructions.text = exam['instructions']?.toString() ?? '';
        _duration.text = '${exam['durationMin'] ?? 60}';
        _start = cbtDate(exam['startsAt']) ?? _start;
        final end = cbtDate(exam['endsAt']);
        if (end != null) _window.text = '${end.difference(_start).inMinutes}';
        _classId = exam['classId']?.toString() ?? '';
        _questions = cbtList(exam['questions']);
        final s = Map<String, dynamic>.from((exam['settings'] as Map?) ?? {});
        _shuffleQ = s['shuffleQuestions'] != false;
        _shuffleO = s['shuffleOptions'] != false;
        _strict = s['strictExit'] != false;
        _results = s['results']?.toString() ?? 'after_close';
        _passMark.text = cbtNum(s['passMark'] ?? 50);
        _published = exam['published'] == true;
        _attempts = (exam['attempts'] as num?)?.toInt() ?? 0;
      }
      if (_classId.isNotEmpty && !_classes.any((c) => '${c['id']}' == _classId)) {
        _classId = '';
      }
    });
  }

  Future<void> _pickStart() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_start));
    if (time == null) return;
    setState(() => _start =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save(bool publish) async {
    final duration = int.tryParse(_duration.text.trim()) ?? 0;
    final window = int.tryParse(_window.text.trim()) ?? duration;
    if (_title.text.trim().isEmpty) {
      cbtToast(context, 'Give the exam a title.');
      return;
    }
    if (duration < 1) {
      cbtToast(context, 'Set the duration in minutes.');
      return;
    }
    if (window < duration) {
      cbtToast(context,
          'The window must be at least as long as the exam ($duration min).');
      return;
    }
    if (publish && _questions.isEmpty) {
      cbtToast(context, 'Add at least one question before publishing.');
      return;
    }
    setState(() => _saving = true);
    final res = await cbtCall(context, 'cbt.exam.save', {
      'schoolId': widget.schoolId,
      if (widget.examId != null) 'examId': widget.examId,
      'title': _title.text.trim(),
      'subject': _subject.text.trim(),
      'classId': _classId,
      'instructions': _instructions.text.trim(),
      'startsAt': _start.toUtc().toIso8601String(),
      'endsAt': _start.add(Duration(minutes: window)).toUtc().toIso8601String(),
      'durationMin': duration,
      'questions': _questions,
      'published': publish,
      'settings': {
        'shuffleQuestions': _shuffleQ,
        'shuffleOptions': _shuffleO,
        'strictExit': _strict,
        'results': _results,
        'passMark': double.tryParse(_passMark.text.trim()) ?? 50,
      },
    }, fallback: 'Could not save the exam.');
    if (!mounted) return;
    setState(() => _saving = false);
    if (res == null) return;
    cbtToast(
        context,
        res['locked'] == true
            ? 'Saved. Students have already sat it, so only the closing time and results settings changed.'
            : publish
                ? 'Published — questions unlock ${cbtWhen(_start)}.'
                : 'Draft saved. Students can\'t see it until you publish.');
    Navigator.of(context).pop();
  }

  Future<void> _addQuestion([int? index]) async {
    final q = await showCbtQuestionEditor(context,
        initial: index == null ? null : _questions[index],
        withMeta: false,
        defaultSubject: _subject.text.trim());
    if (q == null) return;
    setState(() {
      if (index == null) {
        _questions.add(q);
      } else {
        _questions[index] = q;
      }
    });
  }

  Future<void> _bulk() async {
    final list = await showCbtBulkImport(context);
    if (list == null || !mounted) return;
    setState(() => _questions.addAll(list));
    cbtToast(context, 'Added ${list.length} question(s) to the paper.');
  }

  Future<void> _fromBank() async {
    final picked = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (_) => _BankPicker(schoolId: widget.schoolId),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() => _questions.addAll(picked.map((q) => {
          ...q,
          'id': null, // a fresh id per paper
        })));
    cbtToast(context, 'Added ${picked.length} question(s) from the bank.');
  }

  @override
  Widget build(BuildContext context) {
    final wide = context.isExpanded;
    return Scaffold(
      appBar: GlassAppBar(
          title: widget.examId == null ? 'Set an exam' : 'Edit exam'),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: BookNestColors.cyan))
          : Column(children: [
              if (_locked)
                MaterialBanner(
                  backgroundColor: Colors.orangeAccent.withValues(alpha: .15),
                  content: Text(
                      '$_attempts student(s) have sat this exam. The questions are '
                      'locked; you can still change the closing time and how results are shown.'),
                  actions: const [SizedBox.shrink()],
                ),
              Expanded(
                child: wide
                    ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(
                            width: 440,
                            child: ListView(
                                padding: const EdgeInsets.all(20),
                                children: _details())),
                        const VerticalDivider(width: 1),
                        Expanded(
                            child: ListView(
                                padding: const EdgeInsets.all(20),
                                children: _paper())),
                      ])
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [..._details(), const SizedBox(height: 20), ..._paper()],
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(children: [
                    if (!_published)
                      OutlinedButton(
                        onPressed: _saving ? null : () => _save(false),
                        child: const Text('Save draft'),
                      ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _saving ? null : () => _save(true),
                      icon: const Icon(Icons.publish_rounded),
                      label: Text(_published ? 'Save' : 'Publish'),
                    ),
                  ]),
                ),
              ),
            ]),
    );
  }

  Widget _field(TextEditingController c, String label,
          {int lines = 1, TextInputType? type, String? helper, bool enabled = true}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          enabled: enabled,
          minLines: lines,
          maxLines: lines == 1 ? 1 : lines + 4,
          keyboardType: type,
          decoration: InputDecoration(
            labelText: label,
            helperText: helper,
            helperMaxLines: 3,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  List<Widget> _details() {
    final window = int.tryParse(_window.text.trim()) ?? 0;
    final end = _start.add(Duration(minutes: window));
    return [
      const Text('Exam details',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      _field(_title, 'Title (e.g. SS2 First Term Mathematics)', enabled: !_locked),
      _field(_subject, 'Subject', enabled: !_locked),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          initialValue: _classId,
          decoration: const InputDecoration(
              labelText: 'Who sits it', border: OutlineInputBorder()),
          items: [
            const DropdownMenuItem(value: '', child: Text('Whole school')),
            for (final c in _classes)
              DropdownMenuItem(
                  value: '${c['id']}', child: Text('${c['name']} only')),
          ],
          onChanged: _locked ? null : (v) => setState(() => _classId = v ?? ''),
        ),
      ),
      _field(_instructions, 'Instructions to candidates', lines: 3, enabled: !_locked),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.event_rounded, color: BookNestColors.cyan),
        title: const Text('Questions unlock at'),
        subtitle: Text(cbtWhen(_start),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: TextButton(
            onPressed: _locked ? null : _pickStart, child: const Text('Change')),
      ),
      Row(children: [
        Expanded(
            child: _field(_duration, 'Duration (min)',
                type: TextInputType.number, enabled: !_locked)),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _window,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Window (min)', border: OutlineInputBorder()),
            ),
          ),
        ),
      ]),
      Text(
          'Students can start any time until ${cbtWhen(end)}. Everyone gets '
          '${_duration.text} minutes, but the paper hard-closes at the end of the window.',
          style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 16),
      const Text('Rules',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        activeThumbColor: BookNestColors.cyan,
        value: _strict,
        onChanged: _locked ? null : (v) => setState(() => _strict = v),
        title: const Text('Leaving submits the exam'),
        subtitle: const Text(
            'Switching apps, the home button, locking the phone or closing '
            'BookNest ends the attempt. Off: exits are only recorded.'),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        activeThumbColor: BookNestColors.cyan,
        value: _shuffleQ,
        onChanged: _locked ? null : (v) => setState(() => _shuffleQ = v),
        title: const Text('Shuffle question order for each student'),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        activeThumbColor: BookNestColors.cyan,
        value: _shuffleO,
        onChanged: _locked ? null : (v) => setState(() => _shuffleO = v),
        title: const Text('Shuffle options (A–D) for each student'),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        initialValue: _results,
        decoration: const InputDecoration(
            labelText: 'Students see their score', border: OutlineInputBorder()),
        items: const [
          DropdownMenuItem(value: 'instant', child: Text('Immediately after submitting')),
          DropdownMenuItem(value: 'after_close', child: Text('When the exam closes')),
          DropdownMenuItem(value: 'released', child: Text('Only when I release them')),
        ],
        onChanged: (v) => setState(() => _results = v ?? 'after_close'),
      ),
      const SizedBox(height: 12),
      _field(_passMark, 'Pass mark (%)', type: TextInputType.number),
    ];
  }

  List<Widget> _paper() {
    final total = _questions.fold<double>(
        0, (s, q) => s + ((q['marks'] as num?)?.toDouble() ?? 1));
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return [
      Row(children: [
        Expanded(
          child: Text('Paper · ${_questions.length} questions · ${cbtNum(total)} marks',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      ]),
      const SizedBox(height: 8),
      if (!_locked)
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.tonalIcon(
              onPressed: () => _addQuestion(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Write question')),
          FilledButton.tonalIcon(
              onPressed: _fromBank,
              icon: const Icon(Icons.inventory_2_rounded),
              label: const Text('From question bank')),
          FilledButton.tonalIcon(
              onPressed: _bulk,
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Paste from Excel / CSV')),
        ]),
      const SizedBox(height: 12),
      if (_questions.isEmpty)
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
              'No questions yet. Students only see them once the exam starts.',
              style: TextStyle(color: onSurface.withValues(alpha: .6))),
        ),
      for (var i = 0; i < _questions.length; i++)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              radius: 15,
              backgroundColor: BookNestColors.navy,
              child: Text('${i + 1}',
                  style: const TextStyle(
                      color: BookNestColors.cyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
            ),
            title: Text(_questions[i]['text']?.toString() ?? '',
                maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(_questions[i]['type'] == 'theory'
                ? 'Theory · ${cbtNum(_questions[i]['marks'])} marks'
                : 'Objective · answer ${cbtLetters[((_questions[i]['answer'] as num?)?.toInt() ?? 0).clamp(0, 5)]} · ${cbtNum(_questions[i]['marks'])} mark(s)'),
            onTap: _locked ? null : () => _addQuestion(i),
            trailing: _locked
                ? null
                : IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => setState(() => _questions.removeAt(i)),
                  ),
          ),
        ),
    ];
  }
}

/// Pick questions from the school's bank into a paper.
class _BankPicker extends StatefulWidget {
  const _BankPicker({required this.schoolId});

  final String schoolId;

  @override
  State<_BankPicker> createState() => _BankPickerState();
}

class _BankPickerState extends State<_BankPicker> {
  List<Map<String, dynamic>> _rows = [];
  final Set<String> _picked = {};
  String _subject = '';
  String _search = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await BackendApi.instance.call('cbt.bank.list', {
      'schoolId': widget.schoolId,
      if (_subject.isNotEmpty) 'subject': _subject,
      if (_search.isNotEmpty) 'search': _search,
      'limit': 500,
    });
    if (!mounted) return;
    setState(() {
      _loading = false;
      _rows = cbtList(res?['questions']);
    });
  }

  @override
  Widget build(BuildContext context) {
    final subjects = {for (final r in _rows) r['subject']?.toString() ?? ''}
      ..remove('');
    return AlertDialog(
      title: const Text('Question bank'),
      content: SizedBox(
        width: 680,
        height: MediaQuery.sizeOf(context).height * .6,
        child: Column(children: [
          TextField(
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search questions',
                isDense: true,
                border: OutlineInputBorder()),
            onSubmitted: (v) {
              _search = v.trim();
              _load();
            },
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: const Text('All'),
                  selected: _subject.isEmpty,
                  onSelected: (_) {
                    _subject = '';
                    _load();
                  },
                ),
              ),
              for (final s in subjects)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(s),
                    selected: _subject == s,
                    onSelected: (_) {
                      _subject = s;
                      _load();
                    },
                  ),
                ),
            ]),
          ),
          Row(children: [
            Text('${_picked.length} selected'),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() {
                final all = _rows.map((r) => '${r['questionId']}').toSet();
                if (_picked.containsAll(all)) {
                  _picked.removeAll(all);
                } else {
                  _picked.addAll(all);
                }
              }),
              child: const Text('Select all'),
            ),
          ]),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? const Center(child: Text('The bank is empty.'))
                    : ListView.builder(
                        itemCount: _rows.length,
                        itemBuilder: (_, i) {
                          final r = _rows[i];
                          final id = '${r['questionId']}';
                          return CheckboxListTile(
                            value: _picked.contains(id),
                            onChanged: (v) => setState(() =>
                                v == true ? _picked.add(id) : _picked.remove(id)),
                            title: Text(r['text']?.toString() ?? '',
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text([
                              r['subject'],
                              r['topic'],
                              r['year'],
                              r['type'] == 'theory' ? 'Theory' : 'Objective',
                            ].where((s) => '${s ?? ''}'.isNotEmpty).join(' · ')),
                          );
                        },
                      ),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _picked.isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  _rows
                      .where((r) => _picked.contains('${r['questionId']}'))
                      .toList()),
          child: Text('Add ${_picked.length}'),
        ),
      ],
    );
  }
}

/// ── The school's question bank (teachers) ──────────────────────────────
class CbtQuestionBankScreen extends StatefulWidget {
  const CbtQuestionBankScreen({super.key, required this.schoolId});

  final String schoolId;

  @override
  State<CbtQuestionBankScreen> createState() => _CbtQuestionBankScreenState();
}

class _CbtQuestionBankScreenState extends State<CbtQuestionBankScreen> {
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _subjects = [];
  String _subject = '';
  String _search = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final subjects = await BackendApi.instance
        .call('cbt.bank.subjects', {'schoolId': widget.schoolId});
    final res = await BackendApi.instance.call('cbt.bank.list', {
      'schoolId': widget.schoolId,
      if (_subject.isNotEmpty) 'subject': _subject,
      if (_search.isNotEmpty) 'search': _search,
      'limit': 500,
    });
    if (!mounted) return;
    setState(() {
      _loading = false;
      _subjects = cbtList(subjects?['subjects']);
      _rows = cbtList(res?['questions']);
    });
  }

  Future<void> _add() async {
    final q = await showCbtQuestionEditor(context, defaultSubject: _subject);
    if (q == null || !mounted) return;
    final res = await cbtCall(context, 'cbt.bank.add', {
      'schoolId': widget.schoolId,
      'questions': [q],
      'practice': q['practice'] != false,
    }, fallback: 'Could not save the question.');
    if (res != null) _load();
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final q = await showCbtQuestionEditor(context, initial: row);
    if (q == null || !mounted) return;
    final res = await cbtCall(context, 'cbt.bank.update', {
      'questionId': row['questionId'],
      'question': q,
      'practice': q['practice'] != false,
    }, fallback: 'Could not save the question.');
    if (res != null) _load();
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final res = await cbtCall(
        context, 'cbt.bank.delete', {'questionId': row['questionId']},
        fallback: 'Could not delete the question.');
    if (res != null) _load();
  }

  Future<void> _bulk() async {
    final list = await showCbtBulkImport(context);
    if (list == null || !mounted) return;
    final practice = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Import ${list.length} question(s)'),
        content: const Text(
            'Should students be able to practise these, or keep them secret for exams?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Exams only (secret)')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Open for practice')),
        ],
      ),
    );
    if (practice == null || !mounted) return;
    var added = 0;
    for (var i = 0; i < list.length; i += 250) {
      final res = await cbtCall(context, 'cbt.bank.add', {
        'schoolId': widget.schoolId,
        'questions': list.sublist(i, (i + 250).clamp(0, list.length)),
        'practice': practice,
      }, fallback: 'Some questions could not be imported.');
      added += (res?['added'] as num?)?.toInt() ?? 0;
    }
    if (!mounted) return;
    cbtToast(context, 'Imported $added question(s).');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      appBar: GlassAppBar(title: 'Question bank', actions: [
        IconButton(
            tooltip: 'Paste from Excel / CSV',
            onPressed: _bulk,
            icon: const Icon(Icons.upload_file_rounded)),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Question'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Search the bank',
                    isDense: true,
                    border: OutlineInputBorder()),
                onSubmitted: (v) {
                  _search = v.trim();
                  _load();
                },
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: const Text('All'),
                        selected: _subject.isEmpty,
                        onSelected: (_) {
                          _subject = '';
                          _load();
                        },
                      ),
                    ),
                    for (final s in _subjects)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text('${s['subject']} · ${s['count']}'),
                          selected: _subject == s['subject'],
                          onSelected: (_) {
                            _subject = s['subject'].toString();
                            _load();
                          },
                        ),
                      ),
                  ]),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: BookNestColors.cyan))
                  : _rows.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Text(
                                'No questions yet. Write them one by one, or paste a '
                                'whole sheet from Excel with the upload button.',
                                textAlign: TextAlign.center,
                                style:
                                    TextStyle(color: onSurface.withValues(alpha: .6))),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                          itemCount: _rows.length,
                          itemBuilder: (_, i) => _card(_rows[i], onSurface),
                        ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _card(Map<String, dynamic> r, Color onSurface) {
    final options = ((r['options'] as List?) ?? const []).map((e) => '$e').toList();
    final answer = (r['answer'] as num?)?.toInt() ?? -1;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _edit(r),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                    [r['subject'], r['topic'], r['year']]
                        .where((s) => '${s ?? ''}'.isNotEmpty)
                        .join(' · '),
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: onSurface.withValues(alpha: .55))),
              ),
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(r['practice'] == true ? 'Practice' : 'Exam only',
                    style: const TextStyle(fontSize: 11)),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => v == 'delete' ? _delete(r) : _edit(r),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ]),
            Text(r['text']?.toString() ?? '',
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            if (r['type'] == 'theory')
              Text('Theory · ${cbtNum(r['marks'])} marks',
                  style: TextStyle(color: onSurface.withValues(alpha: .6)))
            else
              for (var k = 0; k < options.length; k++)
                Text('${cbtLetters[k]}. ${options[k]}',
                    style: TextStyle(
                        color: k == answer ? const Color(0xFF00B894) : null,
                        fontWeight:
                            k == answer ? FontWeight.w800 : FontWeight.w400)),
          ]),
        ),
      ),
    );
  }
}
