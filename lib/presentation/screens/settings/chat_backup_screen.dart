import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../../config/theme.dart';
import '../../../services/chat_backup_service.dart';
import '../../../services/chat_store.dart';
import '../../../services/media_backup_service.dart';
import '../../../services/media_storage.dart';
import '../../components/booknest_ui.dart';

/// Chat backup, split by what it costs to keep:
///   • Text messages → BookNest (MongoDB), sealed with the reader's
///     passphrase — BookNest stores ciphertext only.
///   • Photos, videos, voice notes and files → the reader's own Google
///     Drive (hidden BookNest folder). BookNest relays media for 30 days.
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
  ServerBackupInfo? _server;
  bool _serverChecked = false;
  bool _mediaOn = false;
  bool _mediaVideos = true;
  DateTime? _mediaLastAt;
  int _mediaFiles = 0;
  int _mediaBytes = 0;
  int _deviceBytes = -1;

  final _svc = ChatBackupService.instance;
  final _media = MediaBackupService.instance;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    await _svc.warmUp();
    final email = await _svc.connectedAccountEmail();
    final last = await _svc.lastBackupAt;
    final size = await _svc.lastBackupSize;
    final hasKey = await _svc.hasPassphraseKey;
    final server = await _svc.peekServerBackup();
    final mediaOn = await _media.enabled;
    final videos = await _media.includeVideos;
    final mediaLast = await _media.lastAt;
    final stored = await _media.stored;
    final deviceBytes = await MediaStorage.usage();
    var local = 0;
    for (final id in ChatStore.instance.conversationIds) {
      final msgs = await ChatStore.instance.load(id);
      local += msgs.length;
    }
    if (!mounted) return;
    setState(() {
      _accountEmail = email;
      _lastAt = last ?? server?.updatedAt;
      _lastSize = size > 0 ? size : (server?.size ?? 0);
      _freq = _svc.frequency;
      _hasPassKey = hasKey;
      _localMessages = local;
      _server = server;
      _serverChecked = true;
      _mediaOn = mediaOn;
      _mediaVideos = videos;
      _mediaLastAt = mediaLast;
      _mediaFiles = stored.$1;
      _mediaBytes = stored.$2;
      _deviceBytes = deviceBytes;
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
          scrollable: true,
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
        scrollable: true,
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
    final passphrase = _hasPassKey
        ? await _askPassphrase(title: 'Confirm your passphrase')
        : await _askNewPassphrase();
    if (passphrase == null || passphrase.isEmpty) return;
    setState(() => _working = true);
    try {
      final size = await _svc.backupNow(passphrase);
      if (!mounted) return;
      setState(() => _working = false);
      if (size < 0) {
        _notice('The backup could not reach BookNest — check your '
            'connection and try again.');
        return;
      }
      _notice('Text backup complete — ${_prettySize(size)}, sealed with your '
          'passphrase.');
      _refresh();
    } on BackupUnavailable catch (error) {
      if (!mounted) return;
      setState(() => _working = false);
      _notice(error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _working = false);
      _notice('The backup hit a snag — please try again.');
    }
  }

  Future<void> _exportCopy() async {
    if (_working) return;
    final passphrase = _hasPassKey
        ? await _askPassphrase(title: 'Confirm your passphrase')
        : await _askNewPassphrase();
    if (passphrase == null || passphrase.isEmpty) return;
    setState(() => _working = true);
    final size = await _svc.exportCopy(passphrase);
    if (!mounted) return;
    setState(() => _working = false);
    _notice(size < 0
        ? 'The export could not complete — please try again.'
        : 'Encrypted copy ready — choose where to keep it.');
    _refresh();
  }

  Future<void> _backUpMedia() async {
    if (_media.running) return;
    final n = await _media.backupNow(interactive: true);
    if (!mounted) return;
    if (n < 0) {
      _notice(Platform.isAndroid || Platform.isIOS
          ? 'Could not connect to your Google account — sign in to Google '
              'on this device and try again.'
          : 'Could not connect to your Google account — finish the Google '
              'sign-in in your browser and try again.');
    } else {
      _notice(n == 0
          ? 'Your media backup is up to date.'
          : 'Backed up $n new file${n == 1 ? '' : 's'} to your Google Drive.');
      if (!_mediaOn) {
        await _media.setEnabled(true);
      }
    }
    _refresh();
  }

  Future<void> _restore(String from) async {
    if (_working) return;
    String? filePath;
    if (from == 'file') {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: 'Choose your BookNest backup file (.bnbk)',
      );
      filePath = picked?.files.single.path;
      if (filePath == null) return;
    }
    final passphrase = await _askPassphrase(title: 'Enter the backup passphrase');
    if (passphrase == null || passphrase.isEmpty) return;
    setState(() => _working = true);
    try {
      final count = switch (from) {
        'drive' => await _svc.restoreFromDrive(passphrase),
        'file' => await _svc.restoreFromFile(passphrase, filePath!),
        _ => await _svc.restoreFromServer(passphrase),
      };
      if (!mounted) return;
      setState(() => _working = false);
      _notice(count > 0
          ? 'Restored $count message${count == 1 ? '' : 's'} — your history '
              'is back. Photos and files come back from your Google Drive as '
              'you open them.'
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

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep it')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(action,
                  style: const TextStyle(
                      color: Color(0xFFD06A6A), fontWeight: FontWeight.bold))),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _deleteText() async {
    if (!await _confirm(
        'Delete your text backup?',
        'Your chats stay on this phone, but the sealed copy stored with '
            'BookNest is gone — a new phone could not restore them.',
        'Delete backup')) {
      return;
    }
    setState(() => _working = true);
    final ok = await _svc.deleteServerBackup();
    if (!mounted) return;
    setState(() => _working = false);
    _notice(ok
        ? 'Your text backup is deleted.'
        : 'The backup could not be deleted — please try again.');
    _refresh();
  }

  Future<void> _deleteMedia() async {
    if (!await _confirm(
        'Delete your media backup?',
        'Photos, videos, voice notes and files backed up to your Google Drive '
            'are removed. Media older than 30 days could then not come back.',
        'Delete media')) {
      return;
    }
    setState(() => _working = true);
    final ok = await _media.deleteAll();
    if (!mounted) return;
    setState(() => _working = false);
    _notice(ok
        ? 'Your media backup is deleted from Google Drive.'
        : 'Some files could not be deleted — please try again.');
    _refresh();
  }

  // ── build ───────────────────────────────────────────────────────────

  String _prettySize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _ago(DateTime? at) {
    if (at == null) return 'Never';
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    return '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
  }

  Widget _card(bool dark, List<Widget> children) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: dark
              ? Colors.white.withOpacity(.05)
              : BookNestColors.navyDeep.withOpacity(.04),
          border: Border.all(color: BookNestColors.cyan.withOpacity(.22)),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _cardTitle(ThemeData theme, IconData icon, String title,
          {bool busy = false}) =>
      Row(children: [
        Icon(icon, size: 18, color: BookNestColors.cyan),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
        ),
        if (busy)
          const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: BookNestColors.cyan)),
      ]);

  Widget _tile(bool dark, IconData icon, String title, String subtitle,
          VoidCallback? onTap) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          tileColor: dark
              ? Colors.white.withOpacity(.04)
              : BookNestColors.navyDeep.withOpacity(.04),
          leading: Icon(icon, color: BookNestColors.cyan),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
          onTap: onTap,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final drive = _media.supported;
    final hint = TextStyle(color: theme.hintColor, fontSize: 12.5, height: 1.45);
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
                border: Border.all(color: BookNestColors.cyan.withOpacity(.4)),
              ),
              child: const Icon(Icons.backup_rounded,
                  size: 40, color: BookNestColors.cyan),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Text messages are backed up to BookNest, sealed with your '
            'passphrase — nobody else can read them. Photos, videos, voice '
            'notes and files are backed up to your own Google account.',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.hintColor, height: 1.5, fontSize: 13),
          ),
          const SizedBox(height: 20),

          // ── text → BookNest ──
          _card(dark, [
            _cardTitle(theme, Icons.chat_rounded, 'Text messages → BookNest',
                busy: _working),
            const SizedBox(height: 10),
            _StatusRow(
                icon: Icons.schedule_rounded,
                label: 'Last backup',
                value: _ago(_lastAt)),
            _StatusRow(
                icon: Icons.cloud_done_rounded,
                label: 'Stored with BookNest',
                value: !_serverChecked
                    ? '…'
                    : _server == null
                        ? 'No backup yet'
                        : '${_prettySize(_server!.size)} · ${_server!.messages} messages'),
            _StatusRow(
                icon: Icons.smartphone_rounded,
                label: 'On this device',
                value: '$_localMessages message'
                    '${_localMessages == 1 ? '' : 's'} · encrypted'),
            _StatusRow(
                icon: Icons.lock_rounded,
                label: 'Passphrase',
                value: _hasPassKey ? 'Saved on this device' : 'Not set'),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: GradientButton(
                label: 'Back up text now',
                icon: Icons.backup_rounded,
                busy: _working,
                onPressed: _backUpNow,
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton.icon(
                onPressed: _working ? null : _exportCopy,
                icon: const Icon(Icons.ios_share_rounded, size: 17),
                label: const Text('Also save an encrypted copy as a file'),
              ),
            ),
          ]),
          const SizedBox(height: 16),

          // ── media on this device (BookNest folder, never deleted) ──
          _card(dark, [
            _cardTitle(theme, Icons.sd_storage_rounded, 'Media on this device'),
            const SizedBox(height: 8),
            Text(
                'Every chat photo, video, voice note and file is saved to '
                'BookNest\'s own folder on this device and stays there — '
                'BookNest never deletes it. (Our servers only pass media on: '
                'photos for 30 days, files for 3 days.)',
                style: hint),
            const SizedBox(height: 6),
            _StatusRow(
                icon: Icons.folder_rounded,
                label: 'Folder',
                value: Platform.isIOS
                    ? 'Files → On My iPhone → BookNest'
                    : MediaStorage.base.contains('/Android/media/')
                        ? 'Android/media/…/BookNest/Media'
                        : MediaStorage.base),
            _StatusRow(
                icon: Icons.data_usage_rounded,
                label: 'Used',
                value: _deviceBytes < 0 ? '…' : _prettySize(_deviceBytes)),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: MediaStorage.autoSave,
              activeColor: BookNestColors.cyan,
              title: const Text('Save chat media automatically',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
              subtitle: const Text('Photos, voice notes and files',
                  style: TextStyle(fontSize: 12)),
              onChanged: (v) async {
                await MediaStorage.setAutoSave(v);
                setState(() {});
              },
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: MediaStorage.autoSaveVideos,
              activeColor: BookNestColors.cyan,
              title: const Text('Save videos automatically',
                  style: TextStyle(fontSize: 14.5)),
              subtitle: const Text('Videos use the most data and space',
                  style: TextStyle(fontSize: 12)),
              onChanged: MediaStorage.autoSave
                  ? (v) async {
                      await MediaStorage.setAutoSaveVideos(v);
                      setState(() {});
                    }
                  : null,
            ),
            if (Platform.isAndroid)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: MediaStorage.showInGallery,
                activeColor: BookNestColors.cyan,
                title: const Text('Show photos & videos in Gallery',
                    style: TextStyle(fontSize: 14.5)),
                onChanged: (v) async {
                  await MediaStorage.setShowInGallery(v);
                  setState(() {});
                },
              ),
          ]),
          const SizedBox(height: 16),
          // ── media → Google Drive ──
          _card(dark, [
            _cardTitle(theme, Icons.perm_media_rounded,
                'Photos, videos & files → Google Drive'),
            const SizedBox(height: 8),
            if (!drive)
              Text(
                  'Media backup uses your Google account and is not available '
                  'in this build yet. BookNest keeps chat photos for 30 days '
                  'and files, voice notes and videos for 3 days — open and '
                  'save anything you want to keep.',
                  style: hint)
            else ...[
              Text(
                  'Saved in a hidden BookNest folder in your own Google Drive '
                  '(uses your Google storage, not BookNest\'s). BookNest keeps '
                  'chat photos for 30 days and files, voice notes and videos '
                  'for 3 days — after that they come back from here.',
                  style: hint),
              const SizedBox(height: 6),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _mediaOn,
                activeColor: BookNestColors.cyan,
                title: const Text('Back up media to my Google account',
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                onChanged: (v) async {
                  await _media.setEnabled(v);
                  setState(() => _mediaOn = v);
                  if (v) _backUpMedia();
                },
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _mediaVideos,
                activeColor: BookNestColors.cyan,
                title: const Text('Include videos',
                    style: TextStyle(fontSize: 14.5)),
                subtitle: const Text('Videos use the most space',
                    style: TextStyle(fontSize: 12)),
                onChanged: (v) async {
                  await _media.setIncludeVideos(v);
                  setState(() => _mediaVideos = v);
                },
              ),
              _StatusRow(
                  icon: Icons.account_circle_rounded,
                  label: 'Google account',
                  value: _accountEmail ?? 'Not connected'),
              _StatusRow(
                  icon: Icons.photo_library_rounded,
                  label: 'In your Drive',
                  value: '$_mediaFiles file${_mediaFiles == 1 ? '' : 's'} · '
                      '${_prettySize(_mediaBytes)}'),
              _StatusRow(
                  icon: Icons.schedule_rounded,
                  label: 'Last media backup',
                  value: _ago(_mediaLastAt)),
              const SizedBox(height: 10),
              ValueListenableBuilder<MediaBackupProgress?>(
                valueListenable: _media.progress,
                builder: (context, p, _) {
                  if (p == null) {
                    return SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _backUpMedia,
                        icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                        label: const Text('Back up media now'),
                      ),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(
                        value: p.total == 0 ? null : p.done / p.total,
                        color: BookNestColors.cyan,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      const SizedBox(height: 6),
                      Text(
                          'Backing up ${p.done} of ${p.total} · '
                          '${_prettySize(p.bytes)}',
                          style: hint),
                    ],
                  );
                },
              ),
            ],
          ]),
          const SizedBox(height: 22),

          // ── schedule ──
          Text('Automatic backups',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
              'Runs quietly when you open your chats: text to BookNest, and '
              'new media to Google Drive when that is switched on.',
              style: hint),
          const SizedBox(height: 10),
          ...List.generate(BackupFrequency.values.length, (i) {
            final f = BackupFrequency.values[i];
            const labels = {
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
                await _svc.setFrequency(value);
                setState(() => _freq = value);
              },
              activeColor: BookNestColors.cyan,
              title: Text(labels[f]!, style: const TextStyle(fontSize: 14.5)),
              dense: true,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
              style: hint),
          const SizedBox(height: 10),
          _tile(dark, Icons.cloud_download_rounded, 'Restore from BookNest',
              'Your sealed text backup', _working ? null : () => _restore('server')),
          if (drive)
            _tile(dark, Icons.history_rounded, 'Restore an older Google backup',
                'Text backups made before version 2.38',
                _working ? null : () => _restore('drive')),
          _tile(dark, Icons.folder_open_rounded, 'Restore from a backup file',
              'A .bnbk copy you saved before',
              _working ? null : () => _restore('file')),
          const SizedBox(height: 16),
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              children: [
                if (_server != null)
                  TextButton(
                    onPressed: _working ? null : _deleteText,
                    child: const Text('Delete my text backup',
                        style: TextStyle(
                            color: Color(0xFFD06A6A),
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ),
                if (drive && _mediaFiles > 0)
                  TextButton(
                    onPressed: _working ? null : _deleteMedia,
                    child: const Text('Delete my media backup',
                        style: TextStyle(
                            color: Color(0xFFD06A6A),
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ),
              ],
            ),
          ),
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
