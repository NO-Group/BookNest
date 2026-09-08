
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../../config/theme.dart';
import '../../../services/chat_backup_service.dart';
import '../../../services/chat_store.dart';
import '../../components/booknest_ui.dart';

/// WhatsApp-style Chat backup: everything about where your chats live —
/// the encrypted vault on this phone, the passphrase-sealed backup in
/// your Google account, and the way back (restore).
class ChatBackupScreen extends StatefulWidget {
  const ChatBackupScreen({super.key});

  @override
  State<ChatBackupScreen> createState() => _ChatBackupScreenState();
}

class _ChatBackupScreenState extends State<ChatBackupScreen> {
  bool _working = false;
  String? _accountEmail;
  DateTime? _lastAt;
  int _lastSize = 0;
  BackupFrequency _freq = BackupFrequency.off;
  bool _hasPassKey = false;
  int _localMessages = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    await ChatBackupService.instance.warmUp();
    final email = await ChatBackupService.instance.connectedAccountEmail();
    final last = await ChatBackupService.instance.lastBackupAt;
    final size = await ChatBackupService.instance.lastBackupSize;
    final hasKey = await ChatBackupService.instance.hasPassphraseKey;
    var stored = 0;
    for (final id in ChatStore.instance.conversationIds) {
      final msgs = await ChatStore.instance.load(id);
      stored += msgs.length;
    }
    if (!mounted) return;
    setState(() {
      _accountEmail = email;
      _lastAt = last;
      _lastSize = size;
      _freq = ChatBackupService.instance.frequency;
      _hasPassKey = hasKey;
      _localMessages = stored;
    });
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ── passphrase flows ────────────────────────────────────────────────

  Future<String?> _askNewPassphrase() async {
    final first = TextEditingController();
    final second = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Create your backup passphrase'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Your backup is sealed with this passphrase — nobody can '
                  'open it without it, not even BookNest. Write it down; '
                  'losing it means losing the backup.',
                  style: TextStyle(fontSize: 13.5, height: 1.45)),
              const SizedBox(height: 14),
              TextField(
                controller: first,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Passphrase (6+ characters)'),
                onChanged: (_) => setDialogState(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: second,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Confirm passphrase'),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            TextButton(
              onPressed: first.text.trim().length >= 6 &&
                      first.text.trim() == second.text.trim()
                  ? () => Navigator.pop(dialogContext, first.text.trim())
                  : null,
              child: const Text('Save passphrase',
                  style:
                      TextStyle(color: BookNestColors.cyan, fontWeight:
                          FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askPassphrase({String title = 'Enter your passphrase'}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'The passphrase seals your backup — without it nothing can '
                'be opened.',
                style: TextStyle(fontSize: 13.5, height: 1.45)),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              onSubmitted: (value) =>
                  Navigator.pop(dialogContext, value.trim()),
              decoration: const InputDecoration(labelText: 'Passphrase'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Unlock',
                  style: TextStyle(
                      color: BookNestColors.cyan,
                      fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  // ── actions ─────────────────────────────────────────────────────────

  Future<void> _backUpNow() async {
    if (_working) return;
    var passphrase = _hasPassKey
        ? await _askPassphrase(title: 'Confirm your passphrase')
        : await _askNewPassphrase();
    if (passphrase == null || passphrase.isEmpty) return;
    setState(() => _working = true);
    try {
      final size = await ChatBackupService.instance.backupNow(passphrase);
      if (!mounted) return;
      setState(() => _working = false);
      if (size < 0) {
        _notice(ChatBackupService.instance.driveSupported
            ? 'The backup could not reach your Google account — check your '
                'connection, sign in to your Google account on this phone, '
                'and try again.'
            : 'The encrypted backup file could not be created — please try '
                'again.');
        return;
      }
      _notice('Backup complete — ${_prettySize(size)} encrypted and safe.');
      _refresh();
    } catch (_) {
      if (!mounted) return;
      setState(() => _working = false);
      _notice('The backup hit a snag — please try again.');
    }
  }

  Future<void> _restore() async {
    if (_working) return;
    final passphrase = _hasPassKey
        ? await _askPassphrase(title: 'Restore your chats')
        : await _askPassphrase(title: 'Enter the backup passphrase');
    if (passphrase == null || passphrase.isEmpty) return;
    String? filePath;
    if (!ChatBackupService.instance.driveSupported) {
      final picked = await FilePicker.platform.pickFiles(
        type: 'any',
        dialogTitle: 'Choose your BookNest backup file (.bnbk)',
      );
      filePath = picked?.files.single.path;
      if (filePath == null) return;
    }
    setState(() => _working = true);
    try {
      final count = ChatBackupService.instance.driveSupported
          ? await ChatBackupService.instance.restoreFromDrive(passphrase)
          : await ChatBackupService.instance
              .restoreFromFile(passphrase, filePath!);
      if (!mounted) return;
      setState(() => _working = false);
      _notice(count > 0
          ? 'Restored $count message${count == 1 ? '' : 's'} — your history '
              'is back on this phone.'
          : 'The backup was empty — nothing to restore.');
      _refresh();
    } on BackupPassphraseWrong {
      if (!mounted) return;
      setState(() => _working = false);
      _notice('That passphrase does not open this backup — check for typos '
          '(it is case-sensitive).');
    } on BackupUnavailable catch (error) {
      if (!mounted) return;
      setState(() => _working = false);
      _notice(error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _working = false);
      _notice('The restore hit a snag — please try again.');
    }
  }

  Future<void> _exportCopy() async {
    if (_working) return;
    final passphrase = _hasPassKey
        ? await _askPassphrase(title: 'Confirm your passphrase')
        : await _askNewPassphrase();
    if (passphrase == null || passphrase.isEmpty) return;
    setState(() => _working = true);
    final size = await ChatBackupService.instance.backupNow(passphrase);
    if (!mounted) return;
    setState(() => _working = false);
    _notice(size < 0
        ? 'The export could not complete — please try again.'
        : 'Encrypted copy ready — choose where to keep it.');
    _refresh();
  }

  Future<void> _deleteBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete the cloud backup?'),
        content: const Text(
            'Your chats stay safe on this phone, but the copy in your '
            'Google account is gone. A new phone could not restore them.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep it')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete backup',
                  style: TextStyle(
                      color: Color(0xFFD06A6A),
                      fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _working = true);
    final ok = await ChatBackupService.instance.deleteDriveBackup();
    if (!mounted) return;
    setState(() => _working = false);
    _notice(ok
        ? 'The cloud backup is deleted.'
        : 'The backup could not be deleted — please try again.');
    _refresh();
  }

  // ── build ───────────────────────────────────────────────────────────

  String _prettySize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get _lastLabel {
    if (_lastAt == null) return 'Never';
    final diff = DateTime.now().difference(_lastAt!);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    return intlFormat(_lastAt!);
  }

  String intlFormat(DateTime at) =>
      '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')} '
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final drive = ChatBackupService.instance.driveSupported;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Chat backup',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: BookNestColors.cyan.withOpacity(.12),
                border:
                    Border.all(color: BookNestColors.cyan.withOpacity(.4)),
              ),
              child: const Icon(Icons.backup_rounded,
                  size: 40, color: BookNestColors.cyan),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Your chats live encrypted on this phone and travel in a '
            'passphrase-sealed backup to your own Google account. BookNest '
            'keeps server copies only while chats are syncing — your '
            'history belongs to you.',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.hintColor, height: 1.5,
                fontSize: 13),
          ),
          const SizedBox(height: 20),

          // ── status card ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: dark
                  ? Colors.white.withOpacity(.05)
                  : BookNestColors.navyDeep.withOpacity(.04),
              border:
                  Border.all(color: BookNestColors.cyan.withOpacity(.22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.verified_user_rounded,
                        size: 18, color: BookNestColors.cyan),
                    const SizedBox(width: 8),
                    Text('Last backup',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const Spacer(),
                    if (_working)
                      const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: BookNestColors.cyan)),
                  ],
                ),
                const SizedBox(height: 10),
                _StatusRow(
                    icon: Icons.schedule_rounded,
                    label: 'Last backup',
                    value: _lastLabel),
                _StatusRow(
                    icon: _lastAt == null
                        ? Icons.circle_outlined
                        : Icons.check_circle_rounded,
                    label: 'Size',
                    value:
                        _lastAt == null ? '—' : _prettySize(_lastSize)),
                _StatusRow(
                    icon: Icons.smartphone_rounded,
                    label: 'On this phone',
                    value: '$_localMessages message'
                        '${_localMessages == 1 ? '' : 's'} · encrypted'),
                if (drive)
                  _StatusRow(
                      icon: Icons.account_circle_rounded,
                      label: 'Google account',
                      value: _accountEmail ?? 'Not connected'),
                _StatusRow(
                    icon: Icons.lock_rounded,
                    label: 'Passphrase',
                    value: _hasPassKey ? 'Saved on this phone' : 'Not set'),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: GradientButton(
                    label: _lastAt == null
                        ? 'Back up now'
                        : 'Back up now · $_lastLabel',
                    icon: Icons.backup_rounded,
                    busy: _working,
                    onPressed: _backUpNow,
                  ),
                ),
                if (!drive) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _working ? null : _exportCopy,
                      icon: const Icon(Icons.ios_share_rounded, size: 18),
                      label: const Text('Export encrypted copy'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 22),

          // ── schedule ──
          Text('Back up to your Google account',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            drive
                ? 'Backups land in a hidden BookNest folder in your own '
                    'Google Drive — only this app can see it.'
                : 'Google Drive backups work on Android phones. Here, keep '
                    'encrypted copies with "Export encrypted copy".',
            style: TextStyle(color: theme.hintColor, fontSize: 12.5,
                height: 1.45),
          ),
          const SizedBox(height: 10),
          ...List.generate(BackupFrequency.values.length, (i) {
            final f = BackupFrequency.values[i];
            final labels = {
              BackupFrequency.off: 'Never — only when I tap Back up',
              BackupFrequency.daily: 'Daily',
              BackupFrequency.weekly: 'Weekly',
              BackupFrequency.monthly: 'Monthly',
            };
            return RadioListTile<BackupFrequency>(
              value: f,
              groupValue: _freq,
              onChanged: (value) async {
                if (value == null) return;
                await ChatBackupService.instance.setFrequency(value);
                setState(() => _freq = value);
              },
              activeColor: BookNestColors.cyan,
              title: Text(labels[f]!,
                  style: const TextStyle(fontSize: 14.5)),
              dense: true,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            );
          }),
          const SizedBox(height: 20),

          // ── restore ──
          Text('Restore',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'New phone, reinstall, or a moment of regret — bring your '
            'history back. You will need your passphrase.',
            style: TextStyle(color: theme.hintColor, fontSize: 12.5,
                height: 1.45),
          ),
          const SizedBox(height: 10),
          if (drive)
            ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              tileColor: dark
                  ? Colors.white.withOpacity(.04)
                  : BookNestColors.navyDeep.withOpacity(.04),
              leading: const Icon(Icons.cloud_download_rounded,
                  color: BookNestColors.cyan),
              title: const Text('Restore from Google account',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Bring your history back to this phone',
                  style: TextStyle(fontSize: 12)),
              onTap: _working ? null : _restore,
            ),
          ListTile(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            tileColor: dark
                ? Colors.white.withOpacity(.04)
                : BookNestColors.navyDeep.withOpacity(.04),
            leading: const Icon(Icons.folder_open_rounded,
                color: BookNestColors.cyan),
            title: const Text('Restore from a backup file',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Open a .bnbk copy you exported before',
                style: TextStyle(fontSize: 12)),
            onTap: _working ? null : _restore,
          ),
          if (drive) ...[
            const SizedBox(height: 20),
            Center(
              child: TextButton(
                onPressed: _working ? null : _deleteBackup,
                child: const Text('Delete the cloud backup',
                    style: TextStyle(
                        color: Color(0xFFD06A6A),
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatusRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.hintColor),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(color: theme.hintColor, fontSize: 13)),
          const Spacer(),
          Flexible(
            child: Text(value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
