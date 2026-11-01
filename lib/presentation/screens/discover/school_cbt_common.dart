import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';

/// Shared bits of the school CBT: API calls with server error messages,
/// time formatting, the CSV / Excel paste parser and the exam calculator.

Future<Map<String, dynamic>?> cbtCall(
  BuildContext context,
  String action,
  Map<String, dynamic> payload, {
  String fallback = 'Something went wrong — try again.',
  bool quiet = false,
}) async {
  final res = await BackendApi.instance.call(action, payload);
  if (res == null && !quiet && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(BackendApi.instance.errorOr(fallback))));
  }
  return res;
}

void cbtToast(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}

List<Map<String, dynamic>> cbtList(Object? raw) => ((raw as List?) ?? const [])
    .whereType<Map>()
    .map((e) => Map<String, dynamic>.from(e))
    .toList();

DateTime? cbtDate(Object? raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString())?.toLocal();
}

String cbtTwo(int n) => n.toString().padLeft(2, '0');

/// "Mon 3 Nov, 09:30"
String cbtWhen(DateTime? t) {
  if (t == null) return '—';
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${days[t.weekday - 1]} ${t.day} ${months[t.month - 1]}, '
      '${cbtTwo(t.hour)}:${cbtTwo(t.minute)}';
}

/// "2d 4h", "3h 12m", "04:59" — for countdowns.
String cbtCountdown(Duration d) {
  if (d.isNegative) return '00:00';
  if (d.inDays >= 1) return '${d.inDays}d ${d.inHours % 24}h';
  if (d.inHours >= 1) return '${d.inHours}h ${cbtTwo(d.inMinutes % 60)}m';
  return '${cbtTwo(d.inMinutes)}:${cbtTwo(d.inSeconds % 60)}';
}

String cbtNum(Object? n) {
  final v = (n is num) ? n : num.tryParse('$n') ?? 0;
  return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

String cbtReason(Object? reason) {
  switch (reason?.toString()) {
    case 'left_app':
      return 'Left the exam';
    case 'reentered':
      return 'Re-entered (auto-submitted)';
    case 'time':
      return 'Time up';
    case 'manual':
      return 'Submitted';
    default:
      return '';
  }
}

const cbtLetters = ['A', 'B', 'C', 'D', 'E', 'F'];

/// The import format teachers paste from Excel / Google Sheets (tabs) or a
/// CSV file (commas):
///
///   subject, topic, year, question, A, B, C, D, answer, explanation, marks
///
/// `answer` is a letter (A–F) or the option text. Leave A–D and answer
/// empty for a theory question. A header row is skipped automatically.
const cbtCsvHelp =
    'One question per line, columns in this order:\n'
    'subject, topic, year, question, A, B, C, D, answer, explanation, marks\n\n'
    '• Paste straight from Excel / Google Sheets, or CSV text.\n'
    '• answer is a letter (A–D) or the exact option text.\n'
    '• Leave A–D and answer empty for a theory question.\n'
    '• marks is optional (default 1).';

class CbtCsvResult {
  CbtCsvResult(this.questions, this.errors);
  final List<Map<String, dynamic>> questions;
  final List<String> errors;
}

List<List<String>> _splitRows(String text) {
  final tab = text.contains('\t');
  final sep = tab ? '\t' : ',';
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
      continue;
    }
    if (ch == '"' && cell.isEmpty) {
      quoted = true;
    } else if (ch == sep) {
      row.add(cell.toString().trim());
      cell.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString().trim());
      cell.clear();
      if (row.any((c) => c.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
    }
  }
  row.add(cell.toString().trim());
  if (row.any((c) => c.isNotEmpty)) rows.add(row);
  return rows;
}

CbtCsvResult parseCbtCsv(String text) {
  final out = <Map<String, dynamic>>[];
  final errors = <String>[];
  final rows = _splitRows(text);
  for (var r = 0; r < rows.length; r++) {
    final c = [...rows[r], ...List.filled(12, '')];
    if (r == 0 && c[0].toLowerCase() == 'subject') continue;
    final question = c[3];
    if (question.isEmpty) {
      errors.add('Line ${r + 1}: no question text');
      continue;
    }
    final options = [c[4], c[5], c[6], c[7]].where((o) => o.isNotEmpty).toList();
    final answerRaw = c[8].trim();
    final marks = double.tryParse(c[10]) ?? 1;
    if (options.isEmpty && answerRaw.isEmpty) {
      out.add({
        'type': 'theory', 'subject': c[0], 'topic': c[1], 'year': c[2],
        'text': question, 'explanation': c[9], 'marks': marks,
      });
      continue;
    }
    var answer = -1;
    final letter = cbtLetters.indexOf(answerRaw.toUpperCase());
    if (answerRaw.length == 1 && letter >= 0) {
      answer = letter;
    } else {
      answer = options.indexWhere(
          (o) => o.toLowerCase() == answerRaw.toLowerCase());
    }
    if (options.length < 2) {
      errors.add('Line ${r + 1}: needs at least 2 options');
      continue;
    }
    if (answer < 0 || answer >= options.length) {
      errors.add('Line ${r + 1}: answer "$answerRaw" is not one of the options');
      continue;
    }
    out.add({
      'type': 'mcq', 'subject': c[0], 'topic': c[1], 'year': c[2],
      'text': question, 'options': options, 'answer': answer,
      'explanation': c[9], 'marks': marks,
    });
  }
  return CbtCsvResult(out, errors);
}

/// Paste box for bulk import. Returns parsed questions or null.
Future<List<Map<String, dynamic>>?> showCbtBulkImport(
    BuildContext context) async {
  final ctrl = TextEditingController();
  CbtCsvResult? preview;
  return showDialog<List<Map<String, dynamic>>>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: const Text('Bulk import questions'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(cbtCsvHelp,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(.7))),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                minLines: 6,
                maxLines: 12,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText:
                      'Mathematics,Algebra,2024,Solve 2x = 8,2,4,6,8,B,x = 8 ÷ 2',
                ),
                onChanged: (v) => setLocal(() => preview = parseCbtCsv(v)),
              ),
              if (preview != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${preview!.questions.length} question(s) ready'
                    '${preview!.errors.isEmpty ? '' : ' · ${preview!.errors.length} line(s) skipped'}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: BookNestColors.cyan),
                  ),
                ),
                for (final e in preview!.errors.take(6))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(e,
                        style: const TextStyle(
                            fontSize: 11.5, color: Colors.redAccent)),
                  ),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: (preview?.questions.isEmpty ?? true)
                ? null
                : () => Navigator.pop(dialogContext, preview!.questions),
            child: Text('Import ${preview?.questions.length ?? 0}'),
          ),
        ],
      ),
    ),
  );
}

/// Add / edit one question. [withMeta] shows subject / topic / year and
/// the practice switch (question bank); exam papers hide them.
Future<Map<String, dynamic>?> showCbtQuestionEditor(
  BuildContext context, {
  Map<String, dynamic>? initial,
  bool withMeta = true,
  String defaultSubject = '',
}) {
  final q = Map<String, dynamic>.from(initial ?? const {});
  var type = q['type']?.toString() == 'theory' ? 'theory' : 'mcq';
  final text = TextEditingController(text: q['text']?.toString() ?? '');
  final explanation =
      TextEditingController(text: q['explanation']?.toString() ?? '');
  final marks = TextEditingController(text: cbtNum(q['marks'] ?? 1));
  final subject = TextEditingController(
      text: q['subject']?.toString() ?? defaultSubject);
  final topic = TextEditingController(text: q['topic']?.toString() ?? '');
  final year = TextEditingController(text: q['year']?.toString() ?? '');
  final opts = <TextEditingController>[
    for (final o in ((q['options'] as List?) ?? const ['', '', '', '']))
      TextEditingController(text: o.toString()),
  ];
  while (opts.length < 2) {
    opts.add(TextEditingController());
  }
  var answer = (q['answer'] as num?)?.toInt() ?? 0;
  var practice = q['practice'] != false;
  String? error;

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setLocal) {
        final onSurface = Theme.of(context).colorScheme.onSurface;
        return AlertDialog(
          title: Text(initial == null ? 'New question' : 'Edit question'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                            value: 'mcq',
                            label: Text('Objective'),
                            icon: Icon(Icons.radio_button_checked)),
                        ButtonSegment(
                            value: 'theory',
                            label: Text('Theory'),
                            icon: Icon(Icons.edit_note_rounded)),
                      ],
                      selected: {type},
                      onSelectionChanged: (s) =>
                          setLocal(() => type = s.first),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: text,
                      minLines: 2,
                      maxLines: 6,
                      decoration: const InputDecoration(
                          labelText: 'Question',
                          border: OutlineInputBorder()),
                    ),
                    if (type == 'mcq') ...[
                      const SizedBox(height: 10),
                      Text('Options — tap the circle to mark the answer',
                          style: TextStyle(
                              fontSize: 12,
                              color: onSurface.withOpacity(.65))),
                      for (var i = 0; i < opts.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(children: [
                            Radio<int>(
                              value: i,
                              groupValue: answer,
                              activeColor: BookNestColors.cyan,
                              onChanged: (v) =>
                                  setLocal(() => answer = v ?? 0),
                            ),
                            Expanded(
                              child: TextField(
                                controller: opts[i],
                                decoration: InputDecoration(
                                  isDense: true,
                                  labelText: 'Option ${cbtLetters[i]}',
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ),
                            if (opts.length > 2)
                              IconButton(
                                tooltip: 'Remove option',
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: () => setLocal(() {
                                  opts.removeAt(i);
                                  if (answer >= opts.length) {
                                    answer = opts.length - 1;
                                  }
                                }),
                              ),
                          ]),
                        ),
                      if (opts.length < 6)
                        TextButton.icon(
                          onPressed: () => setLocal(
                              () => opts.add(TextEditingController())),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add option'),
                        ),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                      controller: explanation,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                          labelText: type == 'mcq'
                              ? 'Explanation (shown in practice and review)'
                              : 'Marking guide (teachers only)',
                          border: const OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    Wrap(spacing: 10, runSpacing: 10, children: [
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: marks,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Marks',
                              border: OutlineInputBorder()),
                        ),
                      ),
                      if (withMeta) ...[
                        SizedBox(
                          width: 180,
                          child: TextField(
                            controller: subject,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                                isDense: true,
                                labelText: 'Subject',
                                border: OutlineInputBorder()),
                          ),
                        ),
                        SizedBox(
                          width: 180,
                          child: TextField(
                            controller: topic,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                                isDense: true,
                                labelText: 'Topic',
                                border: OutlineInputBorder()),
                          ),
                        ),
                        SizedBox(
                          width: 110,
                          child: TextField(
                            controller: year,
                            decoration: const InputDecoration(
                                isDense: true,
                                labelText: 'Year',
                                border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ]),
                    if (withMeta)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: practice,
                        activeColor: BookNestColors.cyan,
                        onChanged: (v) => setLocal(() => practice = v),
                        title: const Text('Students can practise this'),
                        subtitle: const Text(
                            'Turn off to keep it secret for exams only.'),
                      ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(error!,
                            style: const TextStyle(color: Colors.redAccent)),
                      ),
                  ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final options = opts.map((c) => c.text.trim()).toList();
                if (text.text.trim().isEmpty) {
                  setLocal(() => error = 'Write the question.');
                  return;
                }
                if (type == 'mcq' &&
                    (options.where((o) => o.isNotEmpty).length < 2 ||
                        options[answer].isEmpty)) {
                  setLocal(() => error =
                      'Fill at least two options and mark the correct one.');
                  return;
                }
                // Drop blank options while keeping the answer pointing at
                // the same text.
                final kept = <String>[];
                var newAnswer = 0;
                for (var i = 0; i < options.length; i++) {
                  if (options[i].isEmpty) continue;
                  if (i == answer) newAnswer = kept.length;
                  kept.add(options[i]);
                }
                Navigator.pop(dialogContext, <String, dynamic>{
                  ...q,
                  'type': type,
                  'text': text.text.trim(),
                  'options': type == 'mcq' ? kept : <String>[],
                  'answer': type == 'mcq' ? newAnswer : -1,
                  'explanation': explanation.text.trim(),
                  'marks': double.tryParse(marks.text.trim()) ?? 1,
                  'subject': subject.text.trim(),
                  'topic': topic.text.trim(),
                  'year': year.text.trim(),
                  'practice': practice,
                });
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
}

/// The calculator students may use during an exam (like JAMB's).
Future<void> showCbtCalculator(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const Dialog(
        insetPadding: EdgeInsets.all(20),
        child: _Calculator(),
      ),
    );

class _Calculator extends StatefulWidget {
  const _Calculator();

  @override
  State<_Calculator> createState() => _CalculatorState();
}

class _CalculatorState extends State<_Calculator> {
  String _expr = '';
  String _result = '';

  void _tap(String key) {
    setState(() {
      switch (key) {
        case 'C':
          _expr = '';
          _result = '';
          break;
        case '⌫':
          if (_expr.isNotEmpty) _expr = _expr.substring(0, _expr.length - 1);
          break;
        case '=':
          final v = _CalcParser(_expr).parse();
          _result = v == null
              ? 'Error'
              : (v == v.roundToDouble() && v.abs() < 1e15
                  ? v.toInt().toString()
                  : v.toStringAsPrecision(10)
                      .replaceFirst(RegExp(r'\.?0+$'), ''));
          break;
        case '√':
          _expr += '√(';
          break;
        default:
          _expr += key;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const keys = [
      ['C', '(', ')', '⌫'],
      ['7', '8', '9', '÷'],
      ['4', '5', '6', '×'],
      ['1', '2', '3', '−'],
      ['0', '.', '√', '+'],
      ['%', '^', '='],
    ];
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: onSurface.withOpacity(.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_expr.isEmpty ? '0' : _expr,
                  style: TextStyle(fontSize: 18, color: onSurface)),
              Text(_result,
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: BookNestColors.cyan)),
            ]),
          ),
          const SizedBox(height: 10),
          for (final row in keys)
            Row(children: [
              for (final k in row)
                Expanded(
                  flex: k == '=' ? 2 : 1,
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: SizedBox(
                      height: 46,
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          backgroundColor:
                              k == '=' ? BookNestColors.cyan : null,
                          foregroundColor:
                              k == '=' ? BookNestColors.navyDeep : null,
                        ),
                        onPressed: () => _tap(k),
                        child: Text(k,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ),
            ]),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close')),
          ),
        ]),
      ),
    );
  }
}

/// Tiny recursive-descent parser: + − × ÷ ^ % √ and brackets.
class _CalcParser {
  _CalcParser(String source)
      : _s = source
            .replaceAll('×', '*')
            .replaceAll('÷', '/')
            .replaceAll('−', '-')
            .replaceAll(' ', '');
  final String _s;
  int _i = 0;

  double? parse() {
    try {
      final v = _expr();
      if (_i != _s.length || v.isNaN || v.isInfinite) return null;
      return v;
    } catch (_) {
      return null;
    }
  }

  String? get _peek => _i < _s.length ? _s[_i] : null;

  double _expr() {
    var v = _term();
    while (_peek == '+' || _peek == '-') {
      final op = _s[_i++];
      final r = _term();
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  double _term() {
    var v = _power();
    while (_peek == '*' || _peek == '/') {
      final op = _s[_i++];
      final r = _power();
      v = op == '*' ? v * r : v / r;
    }
    return v;
  }

  double _power() {
    final base = _unary();
    if (_peek == '^') {
      _i++;
      final exp = _power();
      return _pow(base, exp);
    }
    return base;
  }

  double _pow(double b, double e) => math.pow(b, e).toDouble();

  double _unary() {
    if (_peek == '-') {
      _i++;
      return -_unary();
    }
    if (_peek == '√') {
      _i++;
      final v = _unary();
      if (v < 0) throw const FormatException('negative root');
      return _sqrt(v);
    }
    var v = _atom();
    while (_peek == '%') {
      _i++;
      v = v / 100;
    }
    return v;
  }

  double _sqrt(double v) => math.sqrt(v);

  double _atom() {
    if (_peek == '(') {
      _i++;
      final v = _expr();
      if (_peek == ')') _i++;
      return v;
    }
    final start = _i;
    while (_peek != null && RegExp(r'[0-9.]').hasMatch(_peek!)) {
      _i++;
    }
    if (start == _i) throw const FormatException('number expected');
    return double.parse(_s.substring(start, _i));
  }
}
