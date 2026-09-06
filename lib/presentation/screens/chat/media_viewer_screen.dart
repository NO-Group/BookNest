import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdfx/pdfx.dart' as pdfx;

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';

/// One piece of media in a conversation — enough for the viewer to
/// page through an album and label the file.
class MediaItem {
  final String url;
  final String name;
  final int? fileSize;

  const MediaItem({required this.url, this.name = 'Attachment', this.fileSize});

  String get extension {
    final match =
        RegExp(r'\.([A-Za-z0-9]{1,6})(?:[?#]|$)').firstMatch(url.split('/').last);
    final fromUrl = match?.group(1);
    if (fromUrl != null) return fromUrl.toLowerCase();
    final dot = name.lastIndexOf('.');
    if (dot != -1 && dot < name.length - 1) return name.substring(dot + 1).toLowerCase();
    return '';
  }

  bool get isImage =>
      ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic'].contains(extension);
  bool get isPdf => extension == 'pdf';
  bool get isAudio =>
      ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'oga', 'flac', 'opus'].contains(extension);
  bool get isText => [
        'txt', 'md', 'csv', 'json', 'log', 'xml', 'html', 'htm', 'yaml',
        'yml', 'kt', 'java', 'dart', 'js', 'ts', 'py', 'rb', 'go', 'c',
        'cpp', 'h', 'css', 'sh', 'sql',
      ].contains(extension);
}

/// ─────────────────────────────────────────────────────────────────────────────
/// The BookNest media viewer. Every photo, document, PDF and audio clip
/// shared in a chat opens HERE — a full in-app screen with pinch-zoom,
/// album paging, PDF pages, an audio player and a document card. The app
/// never hands media to another app.
/// ─────────────────────────────────────────────────────────────────────────────

/// Open a photo (optionally paging through the whole album of photos in
/// the conversation).
Future<void> openChatPhoto(
  BuildContext context,
  String url, {
  List<MediaItem> album = const [],
  int initialIndex = 0,
}) {
  return Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => _PhotoAlbumViewer(
      items: album.isEmpty
          ? [MediaItem(url: url, name: 'Photo')]
          : album,
      initialIndex: initialIndex,
    ),
  ));
}

/// Open any file attachment in-app.
Future<void> openChatFile(
  BuildContext context,
  String url, {
  String? name,
  int? fileSize,
}) {
  return Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => MediaFileViewer(
      item: MediaItem(url: url, name: name ?? 'Attachment', fileSize: fileSize),
    ),
  ));
}

String _mediaCachePath(String url) {
  final safe = url.hashCode.abs().toRadixString(36);
  return '${Directory.systemTemp.path}/booknest_media/$safe';
}

/// Streams [url] into the app cache with progress, reusing a previous
/// download when present. Returns the local file.
Future<File> _downloadToCache(String url, void Function(int, int)? onProgress) async {
  final file = File(_mediaCachePath(url));
  if (await file.exists() && await file.length() > 0) return file;
  await file.parent.create(recursive: true);
  final client = http.Client();
  try {
    final res = await client.send(http.Request('GET', Uri.parse(url)));
    if (res.statusCode != 200) {
      throw 'The file could not be loaded (${res.statusCode}).';
    }
    final total = res.contentLength ?? 0;
    final builder = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in res.stream) {
      received += chunk.length;
      builder.add(chunk);
      if (onProgress != null && total > 0) onProgress(received, total);
    }
    await file.writeAsBytes(builder.takeBytes(), flush: true);
    return file;
  } finally {
    client.close();
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

// ── Photo album viewer ───────────────────────────────────────────────────────

class _PhotoAlbumViewer extends StatefulWidget {
  final List<MediaItem> items;
  final int initialIndex;

  const _PhotoAlbumViewer({required this.items, this.initialIndex = 0});

  @override
  State<_PhotoAlbumViewer> createState() => _PhotoAlbumViewerState();
}

class _PhotoAlbumViewerState extends State<_PhotoAlbumViewer> {
  late final PageController _page =
      PageController(initialPage: widget.initialIndex.clamp(0, widget.items.length - 1));
  TransformationController? _zoom;
  int _index = 0;

  @override
  void dispose() {
    _page.dispose();
    _zoom?.dispose();
    super.dispose();
  }

  void _doubleTapZoom() {
    final zoom = _zoom ??= TransformationController();
    final zoomed = zoom.value.getMaxScaleOnAxis() > 1.4;
    zoom.value = zoomed
        ? Matrix4.identity()
        : Matrix4.identity()..scale(2.5, 2.5, 1);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _page,
            itemCount: widget.items.length,
            onPageChanged: (i) {
              _zoom?.value = Matrix4.identity();
              setState(() => _index = i);
            },
            itemBuilder: (context, i) {
              final zoom = _zoom ??= TransformationController();
              return InteractiveViewer(
                transformationController: zoom,
                maxScale: 6,
                child: Center(
                  child: i == _index
                      ? GestureDetector(
                          onDoubleTap: _doubleTapZoom,
                          child: Image.network(
                            widget.items[i].url,
                            fit: BoxFit.contain,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              final expected = (progress.expectedTotalBytes ?? 1);
                              return Center(
                                child: CircularProgressIndicator(
                                  value: expected > 0
                                      ? progress.cumulativeBytesLoaded / expected
                                      : null,
                                  color: BookNestColors.cyan,
                                ),
                              );
                            },
                            errorBuilder: (_, __, ___) => const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.broken_image_outlined,
                                    color: Colors.white38, size: 44),
                                SizedBox(height: 10),
                                Text('This photo could not be loaded.',
                                    style: TextStyle(color: Colors.white38)),
                              ],
                            ),
                          ),
                        )
                      : Image.network(widget.items[i].url, fit: BoxFit.contain),
                ),
              );
            },
          ),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w700),
                          ),
                          if (widget.items.length > 1)
                            Text(
                              'Photo ${_index + 1} of ${widget.items.length}  ·  pinch to zoom',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 11.5),
                            )
                          else
                            const Text('Pinch to zoom  ·  double-tap to magnify',
                                style: TextStyle(color: Colors.white54, fontSize: 11.5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Universal file viewer ────────────────────────────────────────────────────

class MediaFileViewer extends StatefulWidget {
  final MediaItem item;

  const MediaFileViewer({super.key, required this.item});

  @override
  State<MediaFileViewer> createState() => _MediaFileViewerState();
}

class _MediaFileViewerState extends State<MediaFileViewer> {
  File? _file;
  String? _error;
  int _received = 0;
  int _total = 0;
  bool _downloading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final file = await _downloadToCache(widget.item.url, (r, t) {
        if (!mounted) return;
        setState(() {
          _received = r;
          _total = t;
        });
      });
      if (!mounted) return;
      setState(() {
        _file = file;
        _downloading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _downloading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final item = widget.item;
    return Scaffold(
      backgroundColor: dark ? BookNestColors.navyDeep : BookNestColors.offWhite,
      appBar: AppBar(
        backgroundColor: dark ? Colors.black : Colors.white,
        foregroundColor: dark ? Colors.white : BookNestColors.navyDeep,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text(
              _downloading && _total > 0
                  ? 'Opening… ${_formatBytes(_received)} of ${_formatBytes(_total)}'
                  : 'Opened inside BookNest',
              style: TextStyle(
                  fontSize: 11.5,
                  color: dark ? Colors.white54 : BookNestColors.navyDeep.withOpacity(.55)),
            ),
          ],
        ),
      ),
      body: _downloading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    value: _total > 0 ? _received / _total : null,
                    color: BookNestColors.cyan,
                  ),
                  const SizedBox(height: 14),
                  Text('Preparing ${item.name}…',
                      style: TextStyle(
                          color: dark ? Colors.white60 : BookNestColors.navyDeep.withOpacity(.6))),
                ],
              ),
            )
          : _error != null
              ? _ErrorPane(message: _error!)
              : _body(dark),
    );
  }

  Widget _body(bool dark) {
    final item = widget.item;
    final file = _file!;
    if (item.isImage) {
      return InteractiveViewer(
        maxScale: 6,
        child: Center(
          child: Image.file(file, fit: BoxFit.contain),
        ),
      );
    }
    if (item.isPdf) return _PdfPane(file: file, dark: dark);
    if (item.isAudio) return _AudioPane(file: file, dark: dark, name: item.name);
    if (item.isText) return _TextPane(file: file, dark: dark);
    return _DocumentCard(file: file, item: item, dark: dark);
  }
}

class _ErrorPane extends StatelessWidget {
  final String message;
  const _ErrorPane({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 46, color: BookNestColors.cyan),
            const SizedBox(height: 14),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ── PDF (in-app pages via pdfx) ──────────────────────────────────────────────

class _PdfPane extends StatefulWidget {
  final File file;
  final bool dark;
  const _PdfPane({required this.file, required this.dark});

  @override
  State<_PdfPane> createState() => _PdfPaneState();
}

class _PdfPaneState extends State<_PdfPane> {
  pdfx.PdfControllerPinch? _controller;
  String? _error;
  int _page = 1;
  int _pages = 0;

  @override
  void initState() {
    super.initState();
    _controller = pdfx.PdfControllerPinch(
        document: pdfx.PdfDocument.openFile(widget.file.path));
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _DocumentCard(
        file: widget.file,
        item: const MediaItem(url: '', name: 'Document'),
        dark: widget.dark,
        note: 'This PDF could not be previewed, but it is safely stored in BookNest.',
      );
    }
    final controller = _controller!;
    return Stack(
      children: [
        pdfx.PdfViewPinch(
          controller: controller,
          onDocumentLoaded: (doc) {
            if (!mounted) return;
            setState(() => _pages = doc.pagesCount);
          },
          onPageChanged: (page) {
            if (!mounted) return;
            setState(() => _page = page);
          },
          onDocumentError: (error) {
            if (!mounted) return;
            setState(() => _error = error.toString());
          },
          documentLoaderBuilder: (_) => const Center(
              child: CircularProgressIndicator(color: BookNestColors.cyan)),
          pageLoaderBuilder: (_) => const Center(
              child: CircularProgressIndicator(color: BookNestColors.cyan)),
          errorBuilder: (_, error) => Center(
            child: Text('This PDF could not be previewed.',
                style: TextStyle(color: widget.dark ? Colors.white60 : null)),
          ),
        ),
        if (_pages > 0)
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.65),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  'Page $_page of $_pages  ·  pinch to zoom',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Audio player ─────────────────────────────────────────────────────────────

class _AudioPane extends StatefulWidget {
  final File file;
  final bool dark;
  final String name;
  const _AudioPane({required this.file, required this.dark, required this.name});

  @override
  State<_AudioPane> createState() => _AudioPaneState();
}

class _AudioPaneState extends State<_AudioPane> {
  final AudioPlayer _player = AudioPlayer();
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _position = Duration.zero;
        });
      }
    });
    _start().catchError((Object e) {
      if (mounted) setState(() => _error = 'This audio could not be played.');
    });
  }

  Future<void> _start() async {
    await _player.play(DeviceFileSource(widget.file.path));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _clock(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: dark ? Colors.white.withOpacity(.06) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: BookNestColors.cyan.withOpacity(.35)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                      colors: [BookNestColors.navy, BookNestColors.navyDeep]),
                ),
                child: const Icon(Icons.graphic_eq_rounded,
                    color: BookNestColors.cyan, size: 42),
              ),
              const SizedBox(height: 16),
              Text(widget.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: dark ? Colors.white : BookNestColors.navyDeep)),
              const SizedBox(height: 20),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.redAccent))
              else ...[
                Slider(
                  min: 0,
                  max: _duration.inMilliseconds
                      .clamp(1, 1 << 31)
                      .toDouble(),
                  value: _position.inMilliseconds
                      .clamp(0, _duration.inMilliseconds.clamp(1, 1 << 31))
                      .toDouble(),
                  activeColor: BookNestColors.cyan,
                  onChanged: (v) =>
                      _player.seek(Duration(milliseconds: v.round())),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_clock(_position),
                        style: TextStyle(
                            fontSize: 12,
                            color:
                                dark ? Colors.white54 : BookNestColors.navyDeep.withOpacity(.6))),
                    Text(_duration == Duration.zero ? '--:--' : _clock(_duration),
                        style: TextStyle(
                            fontSize: 12,
                            color:
                                dark ? Colors.white54 : BookNestColors.navyDeep.withOpacity(.6))),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: () => _player.seek(Duration.zero),
                      icon: const Icon(Icons.replay_rounded),
                      color: dark ? Colors.white : BookNestColors.navyDeep,
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () =>
                          _playing ? _player.pause() : _player.resume(),
                      child: Container(
                        width: 66,
                        height: 66,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [
                            BookNestColors.cyan,
                            Color(0xFF2AA8C4)
                          ]),
                        ),
                        child: Icon(
                          _playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: BookNestColors.navyDeep,
                          size: 36,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<double>(
                      onSelected: _player.setPlaybackRate,
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: .75, child: Text('0.75×')),
                        PopupMenuItem(value: 1, child: Text('1×')),
                        PopupMenuItem(value: 1.25, child: Text('1.25×')),
                        PopupMenuItem(value: 1.5, child: Text('1.5×')),
                        PopupMenuItem(value: 2, child: Text('2×')),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text('Speed',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: BookNestColors.cyan)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Text preview ─────────────────────────────────────────────────────────────

class _TextPane extends StatefulWidget {
  final File file;
  final bool dark;
  const _TextPane({required this.file, required this.dark});

  @override
  State<_TextPane> createState() => _TextPaneState();
}

class _TextPaneState extends State<_TextPane> {
  String? _text;
  bool _truncated = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    final bytes = await widget.file.readAsBytes();
    final limit = bytes.length > 200 * 1024 ? bytes.sublist(0, 200 * 1024) : bytes;
    if (!mounted) return;
    setState(() {
      _text = utf8.decode(limit, allowMalformed: true);
      _truncated = bytes.length > 200 * 1024;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_text == null) {
      return const Center(child: CircularProgressIndicator(color: BookNestColors.cyan));
    }
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: SelectableText(
              _text!,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.5,
                color: widget.dark ? Colors.white : BookNestColors.navyDeep,
              ),
            ),
          ),
        ),
        if (_truncated)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            color: BookNestColors.cyan.withOpacity(.12),
            child: const Text(
              'Preview shows the first 200 KB — the full file is stored in BookNest.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }
}

// ── Document card (any other type) ───────────────────────────────────────────

class _DocumentCard extends StatelessWidget {
  final File file;
  final MediaItem item;
  final bool dark;
  final String? note;

  const _DocumentCard({
    required this.file,
    required this.item,
    required this.dark,
    this.note,
  });

  String get _ext {
    if (item.extension.isNotEmpty) return item.extension.toUpperCase();
    final path = file.path;
    final dot = path.lastIndexOf('.');
    return dot == -1 ? 'FILE' : path.substring(dot + 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Container(
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: dark ? Colors.white.withOpacity(.06) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: BookNestColors.cyan.withOpacity(.35)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 92,
                height: 92,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                      colors: [BookNestColors.navy, BookNestColors.navyDeep]),
                ),
                child: Text(
                  _ext.characters.take(4).toString(),
                  style: const TextStyle(
                      color: BookNestColors.cyan,
                      fontWeight: FontWeight.w900,
                      fontSize: 20),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                item.name.isEmpty ? 'Document' : item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: dark ? Colors.white : BookNestColors.navyDeep),
              ),
              const SizedBox(height: 6),
              FutureBuilder<int>(
                future: file.length(),
                builder: (context, snap) => Text(
                  [
                    '$_ext document',
                    if (snap.hasData) _formatBytes(snap.data!),
                    'stored inside BookNest',
                  ].join('  ·  '),
                  style: TextStyle(
                      fontSize: 12.5,
                      color:
                          dark ? Colors.white54 : BookNestColors.navyDeep.withOpacity(.6)),
                ),
              ),
              if (note != null) ...[
                const SizedBox(height: 12),
                Text(note!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: dark ? Colors.white70 : BookNestColors.navyDeep.withOpacity(.75))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Warms the cache for [url] (used by the file picker's recents so a
/// previously viewed file opens instantly). Never throws.
Future<void> precacheMedia(String url) async {
  try {
    await _downloadToCache(url, null);
  } catch (_) {}
}

/// Books/apps keep auth headers out of media URLs; helper kept for the
/// picker so it can reuse the same downloader.
Future<File?> downloadMedia(String url) async {
  try {
    return await _downloadToCache(url, null);
  } catch (_) {
    return null;
  }
}
