import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../components/book_picker_sheet.dart';
import '../../components/booknest_ui.dart';
import 'group_base_screen.dart';

/// ── School LMS, part I: Classes ─────────────────────────────────────────
/// Real class groups inside the school: managers create them, teachers
/// carry their class, students join the ones they attend. Assignments
/// attach to classes; the class code is the join button.
class SchoolClassesSection extends StatefulWidget {
  const SchoolClassesSection({required this.state, super.key});

  final GroupBaseScreenState state;

  @override
  State<SchoolClassesSection> createState() => _SchoolClassesSectionState();
}

class _SchoolClassesSectionState extends State<SchoolClassesSection> {
  List<Map<String, dynamic>> _classes = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await BackendApi.instance
        .call('schools.class.list', {'schoolId': widget.state.groupId});
    if (!mounted) return;
    setState(() {
      _classes = ((res?['classes'] as List?) ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _loading = false;
    });
  }

  Future<void> _createClass() async {
    final nameCtrl = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New class'),
        content: TextField(
          controller: nameCtrl,
          maxLength: 120,
          textCapitalization: TextCapitalization.words,
          decoration:
              const InputDecoration(hintText: 'e.g. SS3 Physics', counterText: ''),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Create',
                  style: TextStyle(
                      color: BookNestColors.cyan,
                      fontWeight: FontWeight.w800))),
        ],
      ),
    );
    if (created != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    final res = await BackendApi.instance.call('schools.class.create', {
      'schoolId': widget.state.groupId,
      'name': name,
    });
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res == null
            ? 'Could not create the class — try again.'
            : '"$name" is open for enrolment.')));
    if (res != null) _load();
  }

  Future<void> _toggleJoin(Map<String, dynamic> klass) async {
    if (_busy) return;
    setState(() => _busy = true);
    final action =
        klass['joined'] == true ? 'schools.class.leave' : 'schools.class.join';
    final res = await BackendApi.instance.call(action, {
      'classId': klass['id']?.toString() ?? '',
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(klass['joined'] == true
              ? 'Could not leave the class — try again.'
              : 'Could not join the class — try again.')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(klass['joined'] == true
            ? 'You left ${klass['name']}.'
            : 'Welcome to ${klass['name']}!')));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassPanel(
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.class_rounded,
                size: 19, color: BookNestColors.cyan),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Classes · ${_classes.length}',
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: onSurface)),
            ),
            if (widget.state.isManager)
              IconButton(
                onPressed: _busy ? null : _createClass,
                icon: const Icon(Icons.add_circle_rounded,
                    color: BookNestColors.cyan, size: 24),
                tooltip: 'New class',
              ),
          ]),
          const SizedBox(height: 6),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: BookNestColors.cyan)),
            )
          else if (_classes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                widget.state.isManager
                    ? 'Create the first class — assignments and attendance '
                        'live inside classes.'
                    : 'No classes yet.',
                style: TextStyle(
                    fontSize: 12.5, color: onSurface.withOpacity(.55)),
              ),
            )
          else
            for (final klass in _classes)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [
                        BookNestColors.navy,
                        BookNestColors.navyDeep
                      ]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      (klass['name']?.toString() ?? 'C')
                          .characters
                          .first
                          .toUpperCase(),
                      style: const TextStyle(
                          color: BookNestColors.cyan,
                          fontWeight: FontWeight.w800,
                          fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(klass['name']?.toString() ?? 'Class',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: onSurface)),
                          const SizedBox(height: 2),
                          Text(
                            '${klass['teacherName']} · ${(klass['members'] as num?)?.toInt() ?? 0} student${((klass['members'] as num?)?.toInt() ?? 0) == 1 ? '' : 's'}',
                            style: TextStyle(
                                fontSize: 11.5,
                                color: onSurface.withOpacity(.55)),
                          ),
                        ]),
                  ),
                  if (klass['joined'] == true)
                    Icon(Icons.check_circle_rounded,
                        size: 19, color: BookNestColors.cyan),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: _busy ? null : () => _toggleJoin(klass),
                    style: TextButton.styleFrom(
                        foregroundColor: BookNestColors.cyan,
                        padding: const EdgeInsets.symmetric(horizontal: 10)),
                    child: Text(klass['joined'] == true ? 'Leave' : 'Join',
                        style:
                            const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ]),
              ),
        ]),
      ),
    );
  }
}

/// ── School LMS, part II: Assignments ────────────────────────────────────
/// Teachers set work per class (optionally anchored to a book); students
/// tick them off; everyone sees due-date countdowns and completion counts.
class SchoolAssignmentsSection extends StatefulWidget {
  const SchoolAssignmentsSection({required this.state, super.key});

  final GroupBaseScreenState state;

  @override
  State<SchoolAssignmentsSection> createState() =>
      _SchoolAssignmentsSectionState();
}

class _SchoolAssignmentsSectionState extends State<SchoolAssignmentsSection> {
  List<Map<String, dynamic>> _assignments = [];
  List<Map<String, dynamic>> _classes = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await BackendApi.instance
        .call('schools.assignment.list', {'schoolId': widget.state.groupId});
    if (!mounted) return;
    setState(() {
      _assignments = ((res?['assignments'] as List?) ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _loading = false;
    });
    final classes = await BackendApi.instance
        .call('schools.class.list', {'schoolId': widget.state.groupId});
    if (!mounted) return;
    setState(() => _classes = ((classes?['classes'] as List?) ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList());
  }

  String _dueLabel(Map<String, dynamic> a) {
    final at = DateTime.tryParse(a['dueAt']?.toString() ?? '');
    if (at == null) return 'No due date';
    final diff = at.difference(DateTime.now());
    if (diff.isNegative) return 'Was due ${at.month}/${at.day}';
    if (diff.inDays >= 1) return 'Due in ${diff.inDays} day${diff.inDays == 1 ? '' : 's'}';
    if (diff.inHours >= 1) return 'Due in ${diff.inHours} hour${diff.inHours == 1 ? '' : 's'}';
    return 'Due in ${diff.inMinutes.clamp(1, 59)} min!';
  }

  Future<void> _create() async {
    if (_classes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Create a class first — assignments live in classes.')));
      return;
    }
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    String? classId = _classes.first['id']?.toString();
    DateTime? due;
    Map<String, dynamic>? book;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: const Text('New assignment'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: classId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Class'),
                items: _classes
                    .map((k) => DropdownMenuItem(
                        value: k['id']?.toString(),
                        child: Text(k['name']?.toString() ?? 'Class',
                            overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) => setDialog(() => classId = v),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: titleCtrl,
                maxLength: 160,
                decoration: const InputDecoration(
                    hintText: 'Title', counterText: ''),
              ),
              TextField(
                controller: bodyCtrl,
                minLines: 3,
                maxLines: 6,
                decoration:
                    const InputDecoration(hintText: 'What should they do?'),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime.now(),
                        initialDate:
                            DateTime.now().add(const Duration(days: 7)),
                        lastDate: DateTime.now()
                            .add(const Duration(days: 365 * 2)),
                      );
                      if (picked != null) setDialog(() => due = picked);
                    },
                    icon: const Icon(Icons.event_rounded, size: 17),
                    label: Text(due == null
                        ? 'Due date'
                        : '${due!.month}/${due!.day}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked =
                          await showBookPicker(dialogContext);
                      if (picked != null) setDialog(() => book = picked);
                    },
                    icon: const Icon(Icons.menu_book_rounded, size: 17),
                    label: Text(book == null
                        ? 'Book'
                        : (book!['title']?.toString() ?? 'Book'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
              ]),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Assign',
                    style: TextStyle(
                        color: BookNestColors.cyan,
                        fontWeight: FontWeight.w800))),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final title = titleCtrl.text.trim();
    if (title.isEmpty || classId == null) return;
    setState(() => _busy = true);
    final res = await BackendApi.instance.call('schools.assignment.create', {
      'classId': classId,
      'title': title,
      'body': bodyCtrl.text.trim(),
      if (due != null)
        'dueAt': DateTime(due!.year, due!.month, due!.day, 23, 59)
            .toIso8601String(),
      if (book != null) 'bookId': book!['id']?.toString() ?? '',
    });
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res == null
            ? 'Could not create the assignment — try again.'
            : 'Assignment set for the class.')));
    if (res != null) _load();
  }

  Future<void> _toggleDone(Map<String, dynamic> a) async {
    if (_busy) return;
    setState(() => _busy = true);
    final res = await BackendApi.instance.call('schools.assignment.done', {
      'assignmentId': a['id']?.toString() ?? '',
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not update — try again.')));
      return;
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassPanel(
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.assignment_rounded,
                size: 19, color: BookNestColors.cyan),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Assignments · ${_assignments.length}',
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: onSurface)),
            ),
            if (widget.state.isManager)
              IconButton(
                onPressed: _busy ? null : _create,
                icon: const Icon(Icons.add_circle_rounded,
                    color: BookNestColors.cyan, size: 24),
                tooltip: 'New assignment',
              ),
          ]),
          const SizedBox(height: 6),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: BookNestColors.cyan)),
            )
          else if (_assignments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                widget.state.isManager
                    ? 'Set the first assignment — pick a class, a due date, '
                        'even a book to read.'
                    : 'No assignments yet.',
                style: TextStyle(
                    fontSize: 12.5, color: onSurface.withOpacity(.55)),
              ),
            )
          else
            for (final a in _assignments)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: onSurface.withOpacity(.04),
                    border: a['done'] == true
                        ? Border.all(
                            color: BookNestColors.cyan.withOpacity(.35))
                        : null,
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: BookNestColors.cyan.withOpacity(.13),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                                a['className']?.toString() ?? 'Class',
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: BookNestColors.cyan)),
                          ),
                          const Spacer(),
                          Text(_dueLabel(a),
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: (a['dueAt']?.toString() ?? '')
                                          .isNotEmpty
                                      ? Theme.of(context)
                                          .colorScheme
                                          .error
                                          .withOpacity(.8)
                                      : onSurface.withOpacity(.5))),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          GestureDetector(
                            onTap: () => _toggleDone(a),
                            child: Icon(
                              a['done'] == true
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 21,
                              color: a['done'] == true
                                  ? BookNestColors.cyan
                                  : onSurface.withOpacity(.4),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(a['title']?.toString() ?? '',
                                style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: onSurface,
                                    decoration: a['done'] == true
                                        ? TextDecoration.lineThrough
                                        : null)),
                          ),
                          Text(
                            '${(a['doneCount'] as num?)?.toInt() ?? 0} done',
                            style: TextStyle(
                                fontSize: 11,
                                color: onSurface.withOpacity(.5)),
                          ),
                        ]),
                        if ((a['body']?.toString() ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6, left: 30),
                            child: Text(a['body'].toString(),
                                style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.4,
                                    color: onSurface.withOpacity(.8))),
                          ),
                        if (a['book'] is Map) ...[
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () => context.push(
                                '/book/${(a['book'] as Map)['bookId']?.toString() ?? ''}'),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: BookNestColors.cyan.withOpacity(.08),
                              ),
                              child: Row(children: [
                                const Icon(Icons.menu_book_rounded,
                                    size: 16, color: BookNestColors.cyan),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                      'Read: ${(a['book'] as Map)['title']?.toString() ?? 'Book'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: BookNestColors.cyan)),
                                ),
                              ]),
                            ),
                          ),
                        ],
                      ]),
                ),
              ),
        ]),
      ),
    );
  }
}

/// ── School LMS, part III: Exam countdowns ───────────────────────────────
class SchoolExamsSection extends StatefulWidget {
  const SchoolExamsSection({required this.state, super.key});

  final GroupBaseScreenState state;

  @override
  State<SchoolExamsSection> createState() => _SchoolExamsSectionState();
}

class _SchoolExamsSectionState extends State<SchoolExamsSection> {
  List<Map<String, dynamic>> _exams = [];
  bool _loading = true;
  bool _busy = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    // Live countdowns: tick every minute while the page is open.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await BackendApi.instance
        .call('schools.exam.list', {'schoolId': widget.state.groupId});
    if (!mounted) return;
    setState(() {
      _exams = ((res?['exams'] as List?) ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _loading = false;
    });
  }

  Future<void> _addExam() async {
    final titleCtrl = TextEditingController();
    final subjectCtrl = TextEditingController();
    DateTime? at;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: const Text('Schedule an exam'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: titleCtrl,
              maxLength: 160,
              decoration: const InputDecoration(
                  hintText: 'e.g. WAEC Mock — Mathematics', counterText: ''),
            ),
            TextField(
              controller: subjectCtrl,
              maxLength: 60,
              decoration: const InputDecoration(
                  hintText: 'Subject (optional)', counterText: ''),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  firstDate: DateTime.now(),
                  initialDate: DateTime.now().add(const Duration(days: 14)),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                );
                if (date == null || !dialogContext.mounted) return;
                final time = await showTimePicker(
                  context: context,
                  initialTime: const TimeOfDay(hour: 9, minute: 0),
                );
                if (time == null) return;
                setDialog(() => at = DateTime(
                    date.year, date.month, date.day, time.hour, time.minute));
              },
              icon: const Icon(Icons.event_rounded, size: 17),
              label: Text(at == null
                  ? 'Pick date & time'
                  : '${at!.month}/${at!.day} · ${at!.hour}:${at!.minute.toString().padLeft(2, '0')}'),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Schedule',
                    style: TextStyle(
                        color: BookNestColors.cyan,
                        fontWeight: FontWeight.w800))),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final title = titleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _busy = true);
    final res = await BackendApi.instance.call('schools.exam.create', {
      'schoolId': widget.state.groupId,
      'title': title,
      'subject': subjectCtrl.text.trim(),
      if (at != null) 'at': at!.toIso8601String(),
    });
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res == null
            ? 'Could not schedule — try again.'
            : 'Exam on the calendar — countdown is live.')));
    if (res != null) _load();
  }

  String _countdown(Map<String, dynamic> exam) {
    final at = DateTime.tryParse(exam['at']?.toString() ?? '');
    if (at == null) return 'Date to be set';
    final diff = at.difference(DateTime.now());
    if (diff.isNegative) return 'Written ✅';
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final minutes = diff.inMinutes % 60;
    if (days >= 1) return '$days d · ${hours}h to go';
    if (hours >= 1) return '$hours h · ${minutes}m to go';
    return '${minutes.clamp(1, 59)} min to go!';
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassPanel(
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.timer_rounded,
                size: 19, color: BookNestColors.cyan),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Exam countdowns · ${_exams.length}',
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: onSurface)),
            ),
            if (widget.state.isManager)
              IconButton(
                onPressed: _busy ? null : _addExam,
                icon: const Icon(Icons.add_circle_rounded,
                    color: BookNestColors.cyan, size: 24),
                tooltip: 'Schedule exam',
              ),
          ]),
          const SizedBox(height: 6),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: BookNestColors.cyan)),
            )
          else if (_exams.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                widget.state.isManager
                    ? 'Put the first exam on the calendar — every student '
                        'sees a live countdown.'
                    : 'No exams scheduled.',
                style: TextStyle(
                    fontSize: 12.5, color: onSurface.withOpacity(.55)),
              ),
            )
          else
            for (final exam in _exams)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: BookNestColors.cyan.withOpacity(.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.quiz_outlined,
                        size: 19, color: BookNestColors.cyan),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(exam['title']?.toString() ?? 'Exam',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: onSurface)),
                          const SizedBox(height: 2),
                          if ((exam['subject']?.toString() ?? '').isNotEmpty)
                            Text(exam['subject'].toString(),
                                style: TextStyle(
                                    fontSize: 11,
                                    color: onSurface.withOpacity(.5))),
                        ]),
                  ),
                  Text(_countdown(exam),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: BookNestColors.cyan)),
                ]),
              ),
        ]),
      ),
    );
  }
}

/// The group's curated shelf — schools call it a reading list,
/// organizations call it a book programme. Managers add from the
/// catalogue; every
/// member taps straight into the book.
class GroupReadingListSection extends StatefulWidget {
  const GroupReadingListSection({super.key, required this.state});

  final GroupBaseScreenState state;

  @override
  State<GroupReadingListSection> createState() => _GroupReadingListSectionState();
}

class _GroupReadingListSectionState extends State<GroupReadingListSection> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;
  bool _busy = false;

  GroupBaseScreenState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _list = _fromDoc();
    _loading = false;
  }

  List<Map<String, dynamic>> _fromDoc() {
    final raw = (state.group?['readingList'] as List?) ?? const [];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList()
      ..sort((a, b) => (b['addedAt']?.toString() ?? '')
          .compareTo(a['addedAt']?.toString() ?? ''));
  }

  Future<void> _add() async {
    if (_busy) return;
    final book = await showBookPicker(context, title: 'Add to reading list');
    if (book == null) return;
    setState(() => _busy = true);
    final res = await BackendApi.instance.call('schools.readinglist.add', {
      'groupId': state.groupId,
      'kind': state.kind,
      'bookId': book['id']?.toString() ?? '',
    });
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res == null
            ? 'Could not add it right now — try again.'
            : '"${book['title']}" added to the reading list.')));
    if (res != null) await state.reload();
    if (mounted) setState(() => _list = _fromDoc());
  }

  Future<void> _remove(Map<String, dynamic> entry) async {
    if (_busy) return;
    setState(() => _busy = true);
    final res = await BackendApi.instance
        .call('schools.readinglist.remove', {
      'groupId': state.groupId,
      'kind': state.kind,
      'bookId': entry['bookId']?.toString() ?? '',
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not remove it — try again.')));
      return;
    }
    await state.reload();
    if (mounted) setState(() => _list = _fromDoc());
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassPanel(
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.menu_book_rounded,
                size: 19, color: BookNestColors.cyan),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Reading list · ${_list.length}',
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: onSurface)),
            ),
            if (state.isManager)
              IconButton(
                onPressed: _busy ? null : _add,
                icon: const Icon(Icons.add_circle_rounded,
                    color: BookNestColors.cyan, size: 24),
                tooltip: 'Add a book',
              ),
          ]),
          const SizedBox(height: 6),
          if (_list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                state.isManager
                    ? 'Curate the shelf your members should read — add the first book.'
                    : 'No books on the list yet.',
                style: TextStyle(
                    fontSize: 12.5, color: onSurface.withOpacity(.55)),
              ),
            )
          else
            SizedBox(
              height: 148,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _list.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final entry = _list[i];
                  return GestureDetector(
                    onTap: () => context
                        .push('/book/${entry['bookId']?.toString() ?? ''}'),
                    onLongPress:
                        state.isManager ? () => _remove(entry) : null,
                    child: SizedBox(
                      width: 100,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          BookCover(
                            coverUrl: entry['coverUrl']?.toString(),
                            title: entry['title']?.toString() ?? 'Book',
                            width: 96,
                            height: 96,
                            radius: 14,
                          ),
                          const SizedBox(height: 6),
                          Text(entry['title']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: onSurface)),
                          Text(entry['authorName']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: onSurface.withOpacity(.55))),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          if (state.isManager && _list.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Hold a cover to remove it from the list.',
                style: TextStyle(
                    fontSize: 10.5, color: onSurface.withOpacity(.45)),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Top readers, computed server-side: distinct books opened per member in
/// the last 30 days. Medals for the first three. Works for every group
/// kind — schools, organizations, communities and clubs alike.
class GroupLeaderboardSection extends StatefulWidget {
  const GroupLeaderboardSection({super.key, required this.state});

  final GroupBaseScreenState state;

  @override
  State<GroupLeaderboardSection> createState() => _GroupLeaderboardSectionState();
}

class _GroupLeaderboardSectionState extends State<GroupLeaderboardSection> {
  List<Map<String, dynamic>> _leaders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await BackendApi.instance.call('schools.leaderboard', {
      'groupId': widget.state.groupId,
      'kind': widget.state.kind,
    });
    if (!mounted) return;
    setState(() {
      _leaders = ((res?['leaders'] as List?) ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _loading = false;
    });
  }

  static const _medals = ['🥇', '🥈', '🥉'];

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassPanel(
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.emoji_events_rounded,
                size: 19, color: BookNestColors.cyan),
            const SizedBox(width: 8),
            Text('Top readers · 30 days',
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: onSurface)),
            const Spacer(),
            IconButton(
              onPressed: _loading ? null : _load,
              icon: Icon(Icons.refresh_rounded,
                  size: 19, color: onSurface.withOpacity(.6)),
              tooltip: 'Refresh',
            ),
          ]),
          const SizedBox(height: 4),
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: BookNestColors.cyan),
              ),
            )
          else if (_leaders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'No reading activity yet — open a book from the list to lead the board.',
                style: TextStyle(
                    fontSize: 12.5, color: onSurface.withOpacity(.55)),
              ),
            )
          else
            for (final leader in _leaders)
              Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Row(children: [
                  SizedBox(
                    width: 26,
                    child: Text(
                      (leader['rank'] as num?)?.toInt() != null &&
                              (leader['rank'] as num).toInt() <= 3
                          ? _medals[(leader['rank'] as num).toInt() - 1]
                          : '${leader['rank']}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: onSurface.withOpacity(.75)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: BookNestColors.navy,
                    child: Text(
                      (leader['name']?.toString() ?? 'R')
                          .substring(0, 1)
                          .toUpperCase(),
                      style: const TextStyle(
                          color: BookNestColors.cyan,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(leader['name']?.toString() ?? 'Reader',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.2,
                            fontWeight: FontWeight.w700,
                            color: onSurface)),
                  ),
                  Text(
                    '${(leader['books'] as num?)?.toInt() ?? 0} book${((leader['books'] as num?)?.toInt() ?? 0) == 1 ? '' : 's'}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: BookNestColors.cyan),
                  ),
                ]),
              ),
        ]),
      ),
    );
  }
}
