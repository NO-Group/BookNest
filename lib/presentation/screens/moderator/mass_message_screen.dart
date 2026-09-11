import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../components/booknest_ui.dart';

/// The moderator's megaphone: one message, every reader. It lands as a
/// full dialog the next time each reader opens BookNest — the classic
/// "new feature is live" announcement.
class MassMessageScreen extends StatefulWidget {
  const MassMessageScreen({super.key});

  @override
  State<MassMessageScreen> createState() => _MassMessageScreenState();
}

class _MassMessageScreenState extends State<MassMessageScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty || _sending) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Send to every reader?',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text(
            '"$title" will greet every reader the next time they open '
            'BookNest.',
            style: const TextStyle(fontSize: 13.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Not yet')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: BookNestColors.navy),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Send it')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _sending = true);
    final res = await BackendApi.instance
        .adminMassMessage(title: title, body: body);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (res != null) {
        _titleCtrl.clear();
        _bodyCtrl.clear();
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res == null
            ? 'Could not send — try again.'
            : 'Broadcast sent — every reader will see it. 📣')));
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      appBar: GlassAppBar(title: 'Broadcast'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          GlassPanel(
            radius: 24,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.campaign_rounded,
                          size: 20, color: BookNestColors.cyan),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('A message for everyone',
                            style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: onSurface)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                        'Perfect for announcing new features. Only the ten '
                        'latest broadcasts are kept.',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: onSurface.withOpacity(.5))),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _titleCtrl,
                      maxLength: 120,
                      style: TextStyle(color: onSurface),
                      decoration: const InputDecoration(
                          labelText: 'Title',
                          hintText: 'e.g. Calls are here 📞',
                          counterText: ''),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _bodyCtrl,
                      minLines: 4,
                      maxLines: 8,
                      maxLength: 2000,
                      style: TextStyle(color: onSurface, height: 1.45),
                      decoration: const InputDecoration(
                          labelText: 'Message',
                          hintText:
                              'Tell every reader what is new and why it '
                              'matters…'),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _sending ? null : _send,
                        style: FilledButton.styleFrom(
                            backgroundColor: BookNestColors.navy,
                            foregroundColor: BookNestColors.cyan,
                            padding: const EdgeInsets.symmetric(vertical: 13)),
                        icon: _sending
                            ? const SizedBox(
                                width: 17,
                                height: 17,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: BookNestColors.cyan))
                            : const Icon(Icons.send_rounded, size: 18),
                        label: Text(_sending ? 'Sending…' : 'Send to everyone',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ]),
            ),
          ),
        ],
      ),
    );
  }
}
