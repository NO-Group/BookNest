import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../services/backend_api.dart';

/// Community safety, everywhere content lives: a single designed sheet for
/// reporting posts, messages, books, clubs and readers, and for blocking
/// readers. Every report lands in the moderation store with the reporter's
/// id — nothing is anonymous, nothing is fake.
enum ReportTargetKind { post, message, user, book, club }

/// Reasons are the platform's moderation vocabulary — the labels stay
/// human.
const List<({String id, String label})> kReportReasons = [
  (id: 'spam', label: 'Spam or scam'),
  (id: 'harassment', label: 'Harassment or bullying'),
  (id: 'hate', label: 'Hate speech or symbols'),
  (id: 'violence', label: 'Violence or threats'),
  (id: 'sexual', label: 'Sexual content'),
  (id: 'misinformation', label: 'Misinformation'),
  (id: 'copyright', label: 'Copyright theft'),
  (id: 'self_harm', label: 'Self-harm or danger to life'),
  (id: 'illegal', label: 'Illegal activity'),
  (id: 'other', label: 'Something else'),
];

Future<void> showReportSheet(
  BuildContext context, {
  required ReportTargetKind kind,
  required String targetId,
  String? hintName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _ReportSheet(
      kind: kind,
      targetId: targetId,
      hintName: hintName,
    ),
  );
}

class _ReportSheet extends StatefulWidget {
  final ReportTargetKind kind;
  final String targetId;
  final String? hintName;
  const _ReportSheet(
      {required this.kind, required this.targetId, this.hintName});

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String _reason = 'spam';
  final _details = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  String get _kindLabel => switch (widget.kind) {
        ReportTargetKind.post => 'post',
        ReportTargetKind.message => 'message',
        ReportTargetKind.user => 'reader',
        ReportTargetKind.book => 'book',
        ReportTargetKind.club => 'club',
      };

  Future<void> _send() async {
    if (_sending) return;
    setState(() => _sending = true);
    final res = await BackendApi.instance.call('moderation.report', {
      'kind': widget.kind.name,
      'targetId': widget.targetId,
      'reason': _reason,
      if (_details.text.trim().isNotEmpty) 'details': _details.text.trim(),
    });
    if (!mounted) return;
    setState(() => _sending = false);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res == null
          ? 'The report could not be sent — please try again.'
          : 'Report received. Our moderators will review this $_kindLabel'
              ' — thank you for keeping BookNest safe.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .78,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).hintColor.withOpacity(.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(Icons.flag_rounded,
                        color: BookNestColors.cyan, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Report this $_kindLabel${widget.hintName != null ? ' · ${widget.hintName}' : ''}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                child: Text(
                  'Tell us what is wrong. Reports are confidential and go '
                  'straight to the moderation team.',
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: Theme.of(context).hintColor),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  children: [
                    for (final reason in kReportReasons)
                      RadioListTile<String>(
                        value: reason.id,
                        groupValue: _reason,
                        onChanged: (value) =>
                            setState(() => _reason = value ?? 'spam'),
                        activeColor: BookNestColors.cyan,
                        title: Text(reason.label,
                            style: const TextStyle(fontSize: 14.5)),
                        dense: true,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: TextField(
                        controller: _details,
                        maxLines: 3,
                        maxLength: 500,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Anything else we should know?',
                          hintText: 'Optional — a sentence helps the '
                              'moderators act faster.',
                          counterText: '',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                child: SizedBox(
                  width: double.infinity,
                  child: _sending
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(10),
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: BookNestColors.cyan),
                            ),
                          ),
                        )
                      : FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: BookNestColors.cyan,
                            foregroundColor: BookNestColors.navyDeep,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _send,
                          icon: const Icon(Icons.send_rounded, size: 18),
                          label: const Text('Send report',
                              style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Blocks a reader for real (server-enforced) and says so honestly.
Future<void> confirmBlock(
  BuildContext context, {
  required String peerId,
  required String peerName,
  required bool currentlyBlocked,
  VoidCallback? onDone,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(currentlyBlocked ? 'Unblock $peerName?' : 'Block $peerName?'),
      content: Text(currentlyBlocked
          ? '$peerName will be able to message you again.'
          : '$peerName will no longer be able to message you, and their '
              'messages in shared clubs stay hidden from you. You can '
              'unblock any time from their profile.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(currentlyBlocked ? 'Unblock' : 'Block',
                style: TextStyle(
                    color: currentlyBlocked
                        ? BookNestColors.cyan
                        : const Color(0xFFD06A6A),
                    fontWeight: FontWeight.bold))),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final res = await BackendApi.instance
      .call(currentlyBlocked ? 'dm.unblock' : 'dm.block', {'peerId': peerId});
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(res == null
        ? 'That could not be completed — please try again.'
        : (currentlyBlocked
            ? '$peerName is unblocked.'
            : '$peerName is blocked.')),
  ));
  onDone?.call();
}
