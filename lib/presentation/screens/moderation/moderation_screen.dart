import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../components/booknest_ui.dart';

/// The overall moderator's console: every community report, newest first,
/// with the power to delete the reported content or clear the report.
class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key});

  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends State<ModerationScreen> {
  List<Map<String, dynamic>> _reports = [];
  bool _loading = true;
  bool _showResolved = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await BackendApi.instance.call('moderation.list', {
      'status': _showResolved ? 'resolved' : 'open',
    });
    if (!mounted) return;
    if (res == null) {
      setState(() {
        _loading = false;
        _error = 'Only the overall moderator can open this console.';
      });
      return;
    }
    setState(() {
      _reports = ((res['reports'] as List?) ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _loading = false;
    });
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _resolve(Map<String, dynamic> report, String outcome) async {
    final res = await BackendApi.instance.call('moderation.resolve', {
      'reportId': report['id']?.toString() ?? '',
      'outcome': outcome,
    });
    if (!mounted) return;
    _notice(res == null
        ? 'Could not update the report — please try again.'
        : (outcome == 'dismissed' ? 'Report dismissed.' : 'Report resolved.'));
    _load();
  }

  Future<void> _deleteContent(Map<String, dynamic> report) async {
    final kind = report['kind']?.toString() ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete this $kind?'),
        content: Text(
            'This permanently removes the reported $kind and every trace of '
            'it (comments, likes, views). This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete',
                  style: TextStyle(
                      color: Color(0xFFD06A6A),
                      fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (confirmed != true) return;
    final res = await BackendApi.instance.call('admin.deleteContent', {
      'kind': kind,
      'targetId': report['targetId']?.toString() ?? '',
    });
    if (!mounted) return;
    if (res == null) {
      _notice('The content could not be deleted — it may already be gone. '
          'Resolve the report anyway.');
      return;
    }
    _notice('Content deleted.');
    _resolve(report, 'resolved');
  }

  String _kindIcon(String kind) => switch (kind) {
        'post' => 'article',
        'message' => 'chat',
        'book' => 'book',
        'user' => 'person',
        _ => 'flag',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Moderation',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: _showResolved ? 'Open reports' : 'Resolved reports',
            icon: Icon(_showResolved
                ? Icons.inbox_rounded
                : Icons.task_alt_rounded),
            onPressed: () {
              setState(() => _showResolved = !_showResolved);
              _load();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: BookNestLoader(size: 56))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(_error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.hintColor)),
                  ),
                )
              : _reports.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_rounded,
                              size: 46,
                              color: BookNestColors.cyan.withOpacity(.6)),
                          const SizedBox(height: 12),
                          Text(
                            _showResolved
                                ? 'Nothing resolved yet.'
                                : 'All clear — no open reports.',
                            style: TextStyle(color: theme.hintColor),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: BookNestColors.cyan,
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 30),
                        itemCount: _reports.length,
                        itemBuilder: (context, i) {
                          final r = _reports[i];
                          final reason = r['reason']?.toString() ?? 'other';
                          final kind = r['kind']?.toString() ?? 'post';
                          final details = r['details']?.toString() ?? '';
                          final when =
                              DateTime.tryParse(r['createdAt']?.toString() ?? '')
                                      ?.toLocal()
                                  ?? DateTime.now();
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              color: dark
                                  ? Colors.white.withOpacity(.04)
                                  : BookNestColors.navyDeep.withOpacity(.03),
                              border: Border.all(
                                  color:
                                      BookNestColors.cyan.withOpacity(.2)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 9, vertical: 4),
                                      decoration: BoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        color: BookNestColors.cyan
                                            .withOpacity(.14),
                                      ),
                                      child: Text('$kind · $reason',
                                          style: const TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w800,
                                              color: BookNestColors.cyan)),
                                    ),
                                    const Spacer(),
                                    Text(
                                        '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: theme.hintColor)),
                                  ],
                                ),
                                if (details.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(details,
                                      style: TextStyle(
                                          fontSize: 13.5, height: 1.4)),
                                ],
                                const SizedBox(height: 6),
                                Text('target: ${r['targetId'] ?? '—'}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: theme.hintColor)),
                                if (!_showResolved)
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () =>
                                              _deleteContent(r),
                                          icon: const Icon(
                                              Icons.delete_forever_rounded,
                                              size: 17,
                                              color: Color(0xFFD06A6A)),
                                          label: Text('Delete $kind',
                                              style: const TextStyle(
                                                  fontSize: 12.5,
                                                  color: Color(0xFFD06A6A),
                                                  fontWeight:
                                                      FontWeight.w700)),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () =>
                                              _resolve(r, 'resolved'),
                                          icon: const Icon(Icons.check_rounded,
                                              size: 17,
                                              color: BookNestColors.cyan),
                                          label: const Text('Handled',
                                              style: TextStyle(
                                                  fontSize: 12.5,
                                                  color:
                                                      BookNestColors.cyan,
                                                  fontWeight:
                                                      FontWeight.w700)),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextButton(
                                          onPressed: () =>
                                              _resolve(r, 'dismissed'),
                                          child: const Text('Dismiss',
                                              style: TextStyle(
                                                  fontSize: 12.5)),
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Chip(
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: BookNestColors.cyan
                                          .withOpacity(.12),
                                      label: Text(
                                          r['outcome']?.toString() ??
                                              'resolved',
                                          style: const TextStyle(
                                              fontSize: 11.5,
                                              color: BookNestColors.cyan)),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
