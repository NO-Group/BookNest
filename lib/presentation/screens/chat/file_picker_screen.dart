import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// The BookNest file picker. A designed, in-app browser — never a raw
/// system sheet. Recent files live front and center, the device's
/// Download / Documents folders are browsed where Android allows, and
/// everything is previewed before it is attached.
/// ─────────────────────────────────────────────────────────────────────────────

class PickedFileChoice {
  final String name;
  final Uint8List bytes;

  const PickedFileChoice({required this.name, required this.bytes});

  int get size => bytes.length;
}

/// Presents the picker and resolves with the chosen file, or null.
Future<PickedFileChoice?> pickBookNestFile(BuildContext context) {
  return Navigator.of(context, rootNavigator: true)
      .push<PickedFileChoice>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => const BookNestFilePicker(),
  ));
}

class BookNestFilePicker extends StatefulWidget {
  const BookNestFilePicker({super.key});

  @override
  State<BookNestFilePicker> createState() => _BookNestFilePickerState();
}

class _BookNestFilePickerState extends State<BookNestFilePicker> {
  static const _maxBytes = 25 * 1024 * 1024;
  bool _loading = true;
  bool _deviceBlocked = false;
  List<FileSystemEntity> _recents = const [];
  List<FileSystemEntity> _deviceFiles = const [];

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    final recents = <FileSystemEntity>[];
    for (final dir in ['booknest_files', 'booknest_media']) {
      final d = Directory('${Directory.systemTemp.path}/$dir');
      if (!await d.exists()) continue;
      try {
        recents.addAll(await d.list(followLinks: false).toList());
      } on FileSystemException {
        // The folder vanished mid-scan — skip it.
      }
    }
    recents.removeWhere((e) => e.path.endsWith('.tmp'));
    recents.sort((a, b) => _stampOf(b).compareTo(_stampOf(a)));

    var device = <FileSystemEntity>[];
    var blocked = false;
    for (final folder in ['Download', 'Documents']) {
      final d = Directory('/storage/emulated/0/$folder');
      try {
        if (!await d.exists()) continue;
        final found = await d.list(followLinks: false).toList();
        device.addAll(found.where((e) => e is File));
      } on FileSystemException {
        blocked = true; // Scoped storage: this device hides raw folders.
      }
    }
    device.sort((a, b) => _stampOf(b).compareTo(_stampOf(a)));
    if (!mounted) return;
    setState(() {
      _recents = recents;
      _deviceFiles = device.take(80).toList();
      _deviceBlocked = blocked && device.isEmpty;
      _loading = false;
    });
  }

  DateTime _stampOf(FileSystemEntity e) {
    try {
      return e.statSync().modified;
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  Future<void> _useSystemBrowser() async {
    try {
      final result = await FilePicker.platform.pickFiles(withData: true);
      final file = result?.files.single;
      if (file == null || file.bytes == null || !mounted) return;
      await _finish(file.name, file.bytes!);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('The Android browser could not be opened — please try again.')));
      }
    }
  }

  Future<void> _attachDeviceFile(File file) async {
    try {
      final name = file.uri.pathSegments.last;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      await _finish(name, bytes);
    } on FileSystemException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('That file could not be read — pick another one.')));
      }
    }
  }

  Future<void> _finish(String name, Uint8List bytes) async {
    if (bytes.length > _maxBytes) {
      final mb = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('That file is $mb MB — the limit is 25 MB.')));
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(PickedFileChoice(name: name, bytes: bytes));
  }

  String _nameOf(FileSystemEntity e) => e.uri.pathSegments.last;
  String _extOf(FileSystemEntity e) {
    final n = _nameOf(e);
    final dot = n.lastIndexOf('.');
    return dot == -1 || dot == n.length - 1 ? '' : n.substring(dot + 1);
  }

  IconData _iconFor(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'mp3':
      case 'wav':
      case 'm4a':
      case 'aac':
      case 'ogg':
      case 'flac':
      case 'opus':
        return Icons.graphic_eq_rounded;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':
      case 'gif':
        return Icons.image_rounded;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Icons.folder_zip_rounded;
      case 'txt':
      case 'md':
      case 'csv':
      case 'json':
      case 'log':
        return Icons.description_outlined;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  String _sizeOf(FileSystemEntity e) {
    try {
      final b = e.statSync().size;
      if (b < 1024) return '$b B';
      if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? BookNestColors.navyDeep : BookNestColors.lightSurface,
      appBar: AppBar(
        backgroundColor: dark ? BookNestColors.navyDeep : BookNestColors.lightSurface,
        elevation: 0,
        title: const Text('Attach a file',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
              onPressed: _scan, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: BookNestColors.cyan))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                _hintCard(dark),
                _section('Recent BookNest files', Icons.history_rounded, dark,
                    _recents.isEmpty
                        ? [_emptyNote(dark, 'Files you pick or receive show up here.')]
                        : [
                            for (final e in _recents.take(20))
                              _fileTile(e, dark, isRecent: true),
                          ]),
                if (!_deviceBlocked)
                  _section(
                      'On this device (Downloads & Documents)',
                      Icons.phone_android_rounded,
                      dark,
                      _deviceFiles.isEmpty
                          ? [
                              _emptyNote(dark,
                                  'No readable files found in this device\'s Download or Documents folders.')
                            ]
                          : [
                              for (final e in _deviceFiles)
                                _fileTile(e, dark, isRecent: false),
                            ]),
                if (_deviceBlocked) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: dark
                          ? Colors.white.withOpacity(.05)
                          : BookNestColors.navyDeep.withOpacity(.05),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.lock_outline_rounded,
                              size: 16, color: BookNestColors.cyan),
                          const SizedBox(width: 8),
                          Text('Device folders are protected by Android',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  color: dark
                                      ? Colors.white
                                      : BookNestColors.navyDeep)),
                        ]),
                        const SizedBox(height: 8),
                        Text(
                          'This version of Android only lets you choose files '
                          'through its own browser. It opens on top of BookNest — '
                          'whatever you pick is attached here.',
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.45,
                              color: dark
                                  ? Colors.white70
                                  : BookNestColors.navyDeep.withOpacity(.75)),
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _useSystemBrowser,
                          icon: const Icon(Icons.open_in_browser_rounded,
                              size: 18),
                          label: const Text('Use the Android browser'),
                          style: TextButton.styleFrom(
                              foregroundColor: BookNestColors.cyan,
                              textStyle: const TextStyle(
                                  fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _hintCard(bool dark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BookNestColors.cyan.withOpacity(dark ? .1 : .09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BookNestColors.cyan.withOpacity(.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user_outlined,
              color: BookNestColors.cyan, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Books stay private: picking happens inside BookNest, files never leave your hands. Max 25 MB.',
              style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: dark ? Colors.white : BookNestColors.navyDeep),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, IconData icon, bool dark, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: BookNestColors.cyan),
            const SizedBox(width: 7),
            Text(title.toUpperCase(),
                style: TextStyle(
                    fontSize: 11,
                    letterSpacing: .8,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).hintColor)),
          ],
        ),
        const SizedBox(height: 8),
        ...children,
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _emptyNote(bool dark, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(text,
          style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: dark ? Colors.white38 : BookNestColors.navyDeep.withOpacity(.5))),
    );
  }

  Widget _fileTile(FileSystemEntity e, bool dark, {required bool isRecent}) {
    final ext = _extOf(e);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _attachDeviceFile(e as File),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: dark ? Colors.white.withOpacity(.05) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: (isRecent ? BookNestColors.cyan : BookNestColors.navyDeep)
                    .withOpacity(.18)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  color: (isRecent
                          ? BookNestColors.cyan
                          : BookNestColors.navyDeep)
                      .withOpacity(.12),
                ),
                child: Icon(_iconFor(ext),
                    size: 21,
                    color: isRecent
                        ? BookNestColors.cyan
                        : dark
                            ? Colors.white70
                            : BookNestColors.navyDeep),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_nameOf(e),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            color: dark ? Colors.white : BookNestColors.navyDeep)),
                    const SizedBox(height: 2),
                    Text(
                      [if (ext.isNotEmpty) ext.toUpperCase(), _sizeOf(e), if (isRecent) 'recent']
                          .where((s) => s.isNotEmpty)
                          .join('  ·  '),
                      style: TextStyle(
                          fontSize: 11.5,
                          color: dark
                              ? Colors.white38
                              : BookNestColors.navyDeep.withOpacity(.5)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.add_circle_outline_rounded,
                  color: BookNestColors.cyan, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
