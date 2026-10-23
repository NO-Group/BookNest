import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:typed_data' show BytesBuilder, Uint8List;

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../../services/cloudinary_service.dart';
import '../../../services/doc_extract.dart';
import '../../../services/media_backup_service.dart';

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

  bool get isImage => isImageExtension(extension);
  bool get isVideo => isVideoExtension(extension);
  bool get isPdf => extension == 'pdf';
  bool get isAudio => isAudioExtension(extension);
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

/// Open any file attachment in-app — videos and audio start playing at
/// once (streamed), every document type opens in the BookNest reader.
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

/// Opens a file that is already on this device (e.g. one taken out of a
/// zip inside the viewer).
Future<void> openLocalFile(BuildContext context, File file, String name) {
  return Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
    builder: (_) => MediaFileViewer(
      item: MediaItem(url: file.uri.toString(), name: name),
      localFile: file,
    ),
  ));
}

/// Hands a copy (with its real file name) to the system share sheet, so it
/// can be saved to Files/Downloads or sent elsewhere.
Future<void> shareMediaFile(BuildContext context, File file, String name) async {
  try {
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    final dir = Directory('${Directory.systemTemp.path}/booknest_share');
    await dir.create(recursive: true);
    final copy = await file.copy('${dir.path}/${safe.isEmpty ? 'attachment' : safe}');
    await Share.shareXFiles([XFile(copy.path)]);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Could not share this file.')));
    }
  }
}

String _mediaCachePath(String url) => mediaCachePath(url);

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
      await res.stream.drain<void>();
      // Chat media leaves BookNest after 30 days — the reader's own Google
      // Drive backup has it.
      final recovered = await MediaBackupService.instance.recover(url);
      if (recovered != null) return recovered;
      throw res.statusCode == 401 || res.statusCode == 403
          ? 'The file host refused to deliver this file (${res.statusCode}). '
              'PDF and ZIP files need to be allowed by the BookNest team — '
              'please try again later.'
          : res.statusCode == 404
              ? 'This file is older than 30 days and is no longer on '
                  'BookNest. Turn on media backup (Settings → Chat backup) to '
                  'keep chat media in your Google account.'
              : 'The file could not be loaded (${res.statusCode}).';
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
              // Videos own their page — playback instead of zoom.
              if (widget.items[i].isVideo) {
                return Center(
                  child: i == _index
                      ? _VideoPlayerPane.network(
                          url: widget.items[i].url,
                          name: widget.items[i].name,
                        )
                      : _VideoPoster(url: widget.items[i].url),
                );
              }
              final zoom = _zoom ??= TransformationController();
              final media = CachedNetworkImage(
                imageUrl: CloudinaryService.transformUrl(
                    widget.items[i].url,
                    width: 1200),
                fit: BoxFit.contain,
                memCacheWidth: 1200,
                fadeInDuration: const Duration(milliseconds: 180),
                progressIndicatorBuilder: (context, _, progress) {
                  final expected = (progress.downloaded ??
                      0);
                  final total =
                      (progress.totalSize ?? 0);
                  return Center(
                    child: CircularProgressIndicator(
                      value: total > 0 ? expected / total : null,
                      color: BookNestColors.cyan,
                    ),
                  );
                },
                errorWidget: (_, __, ___) => const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.broken_image_outlined,
                        color: Colors.white38, size: 44),
                    SizedBox(height: 10),
                    Text('This photo could not be loaded.',
                        style: TextStyle(color: Colors.white38)),
                  ],
                ),
              );
              return InteractiveViewer(
                transformationController: zoom,
                maxScale: 6,
                child: Center(
                  child: i == _index
                      ? GestureDetector(
                          onDoubleTap: _doubleTapZoom,
                          child: media,
                        )
                      : media,
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
                              '${item.isVideo ? 'Video' : 'Photo'} ${_index + 1} of ${widget.items.length}  ·  swipe for more',
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

  /// Already on the device — nothing to download.
  final File? localFile;

  const MediaFileViewer({super.key, required this.item, this.localFile});

  @override
  State<MediaFileViewer> createState() => _MediaFileViewerState();
}

class _MediaFileViewerState extends State<MediaFileViewer> {
  File? _file;
  String? _error;
  int _received = 0;
  int _total = 0;
  bool _downloading = true;

  /// Videos and audio stream straight away instead of downloading first.
  bool get _streams =>
      widget.localFile == null &&
      widget.item.url.startsWith('http') &&
      (widget.item.isVideo || widget.item.isAudio);

  @override
  void initState() {
    super.initState();
    if (widget.localFile != null) {
      _file = widget.localFile;
      _downloading = false;
    } else if (_streams) {
      _downloading = false;
    } else {
      _load();
    }
  }

  Future<void> _share() async {
    var file = _file;
    if (file == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Preparing the file…')));
      try {
        file = await _downloadToCache(widget.item.url, null);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(content: Text('The file could not be loaded.')));
        }
        return;
      }
    }
    if (!mounted) return;
    await shareMediaFile(context, file, widget.item.name);
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
    final cinema = _streams && item.isVideo;
    return Scaffold(
      backgroundColor: cinema
          ? Colors.black
          : (dark ? BookNestColors.navyDeep : BookNestColors.lightSurface),
      appBar: AppBar(
        backgroundColor: dark || cinema ? Colors.black : Colors.white,
        foregroundColor: dark || cinema ? Colors.white : BookNestColors.navyDeep,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Save / share',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: _share,
          ),
        ],
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
                  color: dark || cinema
                      ? Colors.white54
                      : BookNestColors.navyDeep.withOpacity(.55)),
            ),
          ],
        ),
      ),
      body: _streams
          ? (item.isVideo
              ? Center(child: _VideoPlayerPane.network(url: item.url, name: item.name))
              : _AudioPane(url: item.url, dark: dark, name: item.name))
          : _downloading
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

  Widget _body(bool dark) =>
      _UniversalPane(file: _file!, item: widget.item, dark: dark);
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
  final File? file;
  final String? url;
  final bool dark;
  final String name;
  const _AudioPane({this.file, this.url, required this.dark, required this.name});

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
    if (widget.url != null) {
      await _player.play(UrlSource(widget.url!));
    } else {
      await _player.play(DeviceFileSource(widget.file!.path));
    }
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

// ── Video playback (viewer pages: album + file) ──────────────────────────────

/// Full video playback inside the viewer — one controller, honest
/// states, cyan controls. Used for both streamed-album videos and
/// downloaded file attachments.
class _VideoPlayerPane extends StatefulWidget {
  final String? url;
  final File? file;
  final String name;

  const _VideoPlayerPane.network({required this.url, required this.name})
      : file = null;
  const _VideoPlayerPane.file({required File this.file, required this.name})
      : url = null;

  @override
  State<_VideoPlayerPane> createState() => _VideoPlayerPaneState();
}

class _VideoPlayerPaneState extends State<_VideoPlayerPane> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;
  bool _muted = false;
  double _speed = 1.0;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final controller = widget.url != null
        ? VideoPlayerController.networkUrl(Uri.parse(widget.url!))
        : VideoPlayerController.file(widget.file!);
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() => _ready = true);
      await controller.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
    controller.addListener(() {
      if (mounted) setState(() {});
    });
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_failed || controller == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.videocam_off_rounded, color: Colors.white38, size: 44),
          SizedBox(height: 10),
          Text('This video could not be played.',
              style: TextStyle(color: Colors.white38)),
        ],
      );
    }
    if (!_ready) {
      return const CircularProgressIndicator(color: BookNestColors.cyan);
    }
    final value = controller.value;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => setState(() {
            value.isPlaying ? controller.pause() : controller.play();
          }),
          child: AspectRatio(
            aspectRatio:
                value.aspectRatio > 0 ? value.aspectRatio : 16 / 9,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(controller),
                if (!value.isPlaying)
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: BookNestColors.navyDeep.withOpacity(.55),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 40),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 4),
          child: Row(
            children: [
              InkWell(
                onTap: () => setState(() {
                  _muted = !_muted;
                  controller.setVolume(_muted ? 0 : 1);
                }),
                child: Icon(
                    _muted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    color: Colors.white70,
                    size: 21),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3.5,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 11),
                  ),
                  child: Slider(
                    value: value.position.inMilliseconds
                        .toDouble()
                        .clamp(0, value.duration.inMilliseconds.toDouble()),
                    max: value.duration.inMilliseconds.toDouble() == 0
                        ? 1
                        : value.duration.inMilliseconds.toDouble(),
                    activeColor: BookNestColors.cyan,
                    inactiveColor: Colors.white24,
                    onChanged: (v) =>
                        controller.seekTo(Duration(milliseconds: v.round())),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () {
                  const speeds = [1.0, 1.5, 2.0];
                  final next =
                      speeds[(speeds.indexOf(_speed) + 1) % speeds.length];
                  setState(() {
                    _speed = next;
                    controller.setPlaybackSpeed(next);
                  });
                },
                child: Text('${_speed}x',
                    style: const TextStyle(
                        color: BookNestColors.cyan,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 6),
              Text(
                '${value.position.inMinutes}:${_two(value.position.inSeconds % 60)} / '
                '${value.duration.inMinutes}:${_two(value.duration.inSeconds % 60)}',
                style: const TextStyle(color: Colors.white54, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The quiet poster tile for album pages that are not front and center —
/// the video's own first-seconds frame when Cloudinary can serve one.
class _VideoPoster extends StatelessWidget {
  final String url;
  const _VideoPoster({required this.url});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (CloudinaryService.videoThumb(url).isEmpty)
            Container(
              color: BookNestColors.navyDeep,
              child: const Icon(Icons.movie_rounded,
                  color: Colors.white24, size: 42),
            )
          else
          CachedNetworkImage(
            imageUrl: CloudinaryService.videoThumb(url),
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Container(
              color: BookNestColors.navyDeep,
              child: const Icon(Icons.movie_rounded,
                  color: Colors.white24, size: 42),
            ),
          ),
          const Center(
            child: Icon(Icons.play_arrow_rounded,
                color: Colors.white70, size: 42),
          ),
        ],
      ),
    );
  }
}

// ── Universal document pane ──────────────────────────────────────────────────
//
// Looks at the file's own bytes (not just its name) and picks the right
// view: PDF pages, pictures, SVG, video, audio, Markdown, or the BookNest
// reader for everything else (Word, Excel, PowerPoint, OpenDocument,
// e-books, web pages, CSV, archives, code, unknown files…).

class _UniversalPane extends StatefulWidget {
  final File file;
  final MediaItem item;
  final bool dark;
  const _UniversalPane({required this.file, required this.item, required this.dark});

  @override
  State<_UniversalPane> createState() => _UniversalPaneState();
}

class _UniversalPaneState extends State<_UniversalPane> {
  String? _kind;

  @override
  void initState() {
    super.initState();
    _sniff();
  }

  Future<void> _sniff() async {
    var kind = 'document';
    try {
      final raf = await widget.file.open();
      final head = await raf.read(4096);
      await raf.close();
      kind = sniffKind(head, widget.item.extension);
    } catch (_) {}
    if (mounted) setState(() => _kind = kind);
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final item = widget.item;
    final dark = widget.dark;
    switch (_kind) {
      case null:
        return const Center(child: CircularProgressIndicator(color: BookNestColors.cyan));
      case 'pdf':
        return _PdfPane(file: file, dark: dark);
      case 'image':
        return InteractiveViewer(
          maxScale: 6,
          child: Center(
            child: Image.file(file,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    _DocPane(file: file, item: item, dark: dark)),
          ),
        );
      case 'svg':
        return InteractiveViewer(
          maxScale: 8,
          child: Center(
            child: SvgPicture.file(file,
                fit: BoxFit.contain,
                placeholderBuilder: (_) =>
                    const CircularProgressIndicator(color: BookNestColors.cyan)),
          ),
        );
      case 'video':
        return Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: _VideoPlayerPane.file(file: file, name: item.name),
        );
      case 'audio':
        return _AudioPane(file: file, dark: dark, name: item.name);
      case 'markdown':
        return _MarkdownPane(file: file, dark: dark);
      default:
        return _DocPane(file: file, item: item, dark: dark);
    }
  }
}

class _MarkdownPane extends StatelessWidget {
  final File file;
  final bool dark;
  const _MarkdownPane({required this.file, required this.dark});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: file.readAsBytes().then((b) => utf8.decode(b, allowMalformed: true)),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: BookNestColors.cyan));
        }
        return Markdown(
          data: snap.data!,
          selectable: true,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        );
      },
    );
  }
}

/// Reads the document in a background isolate, then shows it.
class _DocPane extends StatefulWidget {
  final File file;
  final MediaItem item;
  final bool dark;
  const _DocPane({required this.file, required this.item, required this.dark});

  @override
  State<_DocPane> createState() => _DocPaneState();
}

class _DocPaneState extends State<_DocPane> {
  static const _maxBytes = 80 * 1024 * 1024;
  ExtractedDoc? _doc;
  Uint8List? _bytes;
  String? _problem;
  File? _previewPdf;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final length = await widget.file.length();
      if (length > _maxBytes) {
        setState(() => _problem =
            'This file is ${_formatBytes(length)} — too large to open on the phone. '
            'Use Save / share to keep it.');
        return;
      }
      final bytes = await widget.file.readAsBytes();
      final doc = await compute(extractDocumentFromMap,
          <String, Object?>{'bytes': bytes, 'ext': widget.item.extension});
      File? pdf;
      if (doc.previewPdf != null) {
        pdf = File('${widget.file.path}.preview.pdf');
        await pdf.writeAsBytes(doc.previewPdf!, flush: true);
      }
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _bytes = doc.entries.isNotEmpty ? bytes : null;
        _previewPdf = pdf;
      });
    } catch (_) {
      if (mounted) setState(() => _problem = 'This file could not be read.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    if (_problem != null) {
      return _DocumentCard(file: widget.file, item: widget.item, dark: dark, note: _problem);
    }
    final doc = _doc;
    if (doc == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(color: BookNestColors.cyan),
          const SizedBox(height: 14),
          Text('Opening the document…',
              style: TextStyle(
                  color: dark ? Colors.white60 : BookNestColors.navyDeep.withOpacity(.6))),
        ]),
      );
    }
    if (_previewPdf != null) return _PdfPane(file: _previewPdf!, dark: dark);
    if (doc.previewImage != null) {
      return Column(children: [
        if (doc.note != null) _NoteBanner(doc.note!, dark: dark),
        Expanded(
          child: InteractiveViewer(
            maxScale: 6,
            child: Center(child: Image.memory(doc.previewImage!, fit: BoxFit.contain)),
          ),
        ),
      ]);
    }
    if (doc.entries.isNotEmpty) {
      return _ArchiveList(doc: doc, bytes: _bytes!, item: widget.item, dark: dark);
    }
    if (doc.isEmpty || doc.pages.every((p) => p.blocks.isEmpty)) {
      return _DocumentCard(
          file: widget.file,
          item: widget.item,
          dark: dark,
          note: doc.note ?? 'There is nothing readable inside this file.');
    }
    return _DocReader(doc: doc, dark: dark);
  }
}

class _NoteBanner extends StatelessWidget {
  final String text;
  final bool dark;
  const _NoteBanner(this.text, {required this.dark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      color: BookNestColors.cyan.withOpacity(.12),
      child: Row(children: [
        const Icon(Icons.info_outline_rounded, size: 16, color: BookNestColors.cyan),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: dark ? Colors.white : BookNestColors.navyDeep)),
        ),
      ]),
    );
  }
}

/// The BookNest reader: pages (slides, sheets, chapters) with a picker,
/// adjustable text size, selectable text, tables and pictures.
class _DocReader extends StatefulWidget {
  final ExtractedDoc doc;
  final bool dark;
  const _DocReader({required this.doc, required this.dark});

  @override
  State<_DocReader> createState() => _DocReaderState();
}

class _DocReaderState extends State<_DocReader> {
  int _page = 0;
  double _scale = 1.0;

  List<DocPage> get _pages => widget.doc.pages;

  void _pickPage() {
    final dark = widget.dark;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: dark ? BookNestColors.navyDeep : Colors.white,
      builder: (sheetContext) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _pages.length,
          itemBuilder: (_, i) => ListTile(
            dense: true,
            selected: i == _page,
            selectedColor: BookNestColors.cyan,
            leading: Text('${i + 1}',
                style: const TextStyle(fontWeight: FontWeight.w800, color: BookNestColors.cyan)),
            title: Text(_pageTitle(i), maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () {
              Navigator.pop(sheetContext);
              setState(() => _page = i);
            },
          ),
        ),
      ),
    );
  }

  String _pageTitle(int i) {
    final t = _pages[i].title.trim();
    return t.isEmpty ? 'Page ${i + 1}' : t;
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final doc = widget.doc;
    final fg = dark ? Colors.white : BookNestColors.navyDeep;
    final page = _pages[_page < _pages.length ? _page : _pages.length - 1];
    final sheetGrid = page.isSheet &&
        page.blocks.length == 1 &&
        page.blocks.first.type == DocBlockType.table;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          decoration: BoxDecoration(
            color: dark ? Colors.white.withOpacity(.04) : Colors.white,
            border: Border(bottom: BorderSide(color: BookNestColors.cyan.withOpacity(.18))),
          ),
          child: Row(
            children: [
              Icon(_formatIcon(doc.format), size: 18, color: BookNestColors.cyan),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  doc.title?.isNotEmpty == true ? '${doc.format} · ${doc.title}' : doc.format,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg),
                ),
              ),
              if (!sheetGrid) ...[
                IconButton(
                  tooltip: 'Smaller text',
                  visualDensity: VisualDensity.compact,
                  onPressed: _scale > .8 ? () => setState(() => _scale -= .1) : null,
                  icon: Icon(Icons.text_decrease_rounded, size: 20, color: fg),
                ),
                IconButton(
                  tooltip: 'Larger text',
                  visualDensity: VisualDensity.compact,
                  onPressed: _scale < 1.8 ? () => setState(() => _scale += .1) : null,
                  icon: Icon(Icons.text_increase_rounded, size: 20, color: fg),
                ),
              ],
            ],
          ),
        ),
        if (doc.note != null) _NoteBanner(doc.note!, dark: dark),
        if (_pages.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(children: [
              IconButton(
                onPressed: _page > 0 ? () => setState(() => _page--) : null,
                icon: const Icon(Icons.chevron_left_rounded),
                color: BookNestColors.cyan,
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _pickPage,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            '${_pageTitle(_page)}  ·  ${_page + 1} of ${_pages.length}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w800, color: fg),
                          ),
                        ),
                        const Icon(Icons.expand_more_rounded, color: BookNestColors.cyan),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed:
                    _page < _pages.length - 1 ? () => setState(() => _page++) : null,
                icon: const Icon(Icons.chevron_right_rounded),
                color: BookNestColors.cyan,
              ),
            ]),
          ),
        Expanded(
          child: sheetGrid
              ? _SheetGrid(key: ValueKey(_page), rows: page.blocks.first.rows, dark: dark)
              : page.blocks.isEmpty
                  ? Center(
                      child: Text('This page is empty.',
                          style: TextStyle(color: fg.withOpacity(.6))))
                  : MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                          textScaler: TextScaler.linear(_scale)),
                      child: ListView.builder(
                        key: PageStorageKey('doc-page-$_page'),
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 48),
                        itemCount: page.blocks.length,
                        itemBuilder: (_, i) => _BlockView(
                            block: page.blocks[i], dark: dark, monospace: doc.monospace),
                      ),
                    ),
        ),
      ],
    );
  }

  static IconData _formatIcon(String format) {
    final f = format.toLowerCase();
    if (f.contains('spreadsheet')) return Icons.table_chart_rounded;
    if (f.contains('slides')) return Icons.slideshow_rounded;
    if (f.contains('e-book')) return Icons.menu_book_rounded;
    if (f.contains('web')) return Icons.language_rounded;
    if (f.contains('message') || f.contains('mail')) return Icons.mail_outline_rounded;
    return Icons.description_rounded;
  }
}

class _BlockView extends StatelessWidget {
  final DocBlock block;
  final bool dark;
  final bool monospace;
  const _BlockView({required this.block, required this.dark, required this.monospace});

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : BookNestColors.navyDeep;
    final body = TextStyle(fontSize: 15.5, height: 1.55, color: fg.withOpacity(.92));
    TextSpan spans(TextStyle base) => TextSpan(
          style: base,
          children: [
            for (final s in block.spans)
              TextSpan(
                text: s.text,
                style: TextStyle(
                  fontWeight: s.bold ? FontWeight.w800 : null,
                  fontStyle: s.italic ? FontStyle.italic : null,
                  decoration: s.underline ? TextDecoration.underline : null,
                ),
              ),
          ],
        );
    switch (block.type) {
      case DocBlockType.heading:
        final level = block.level < 1 ? 1 : (block.level > 6 ? 6 : block.level);
        final size = const [24.0, 21.0, 18.5, 17.0, 16.0, 15.5][level - 1];
        return Padding(
          padding: EdgeInsets.only(top: block.level <= 2 ? 18 : 12, bottom: 8),
          child: SelectableText(block.text,
              style: TextStyle(
                  fontSize: size, fontWeight: FontWeight.w800, height: 1.3, color: fg)),
        );
      case DocBlockType.paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SelectableText.rich(spans(body)),
        );
      case DocBlockType.bullet:
        return Padding(
          padding: EdgeInsets.only(
              bottom: 6, left: 6.0 + 16.0 * (block.level < 1 ? 0 : (block.level > 5 ? 4 : block.level - 1))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 1, right: 8),
              child: Text('•',
                  style: body.copyWith(color: BookNestColors.cyan, fontWeight: FontWeight.w900)),
            ),
            Expanded(child: SelectableText.rich(spans(body))),
          ]),
        );
      case DocBlockType.code:
        return Container(
          margin: EdgeInsets.only(bottom: monospace ? 0 : 10),
          padding: monospace ? EdgeInsets.zero : const EdgeInsets.all(12),
          decoration: monospace
              ? null
              : BoxDecoration(
                  color: fg.withOpacity(.06), borderRadius: BorderRadius.circular(10)),
          child: SelectableText(block.text,
              style: TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5, color: fg)),
        );
      case DocBlockType.table:
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _DocTable(rows: block.rows, dark: dark),
        );
      case DocBlockType.image:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(block.image!,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          ),
        );
      case DocBlockType.divider:
        return Divider(height: 28, color: BookNestColors.cyan.withOpacity(.3));
    }
  }
}

/// A table inside a document: scrolls sideways, header row in bold.
class _DocTable extends StatelessWidget {
  final List<List<String>> rows;
  final bool dark;
  const _DocTable({required this.rows, required this.dark});

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : BookNestColors.navyDeep;
    final shown = rows.length > 400 ? rows.sublist(0, 400) : rows;
    final width = shown.fold<int>(0, (w, r) => r.length > w ? r.length : w);
    if (width == 0) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: BookNestColors.cyan.withOpacity(.28), width: .8),
        children: [
          for (var r = 0; r < shown.length; r++)
            TableRow(
              decoration: BoxDecoration(
                  color: r == 0 ? BookNestColors.cyan.withOpacity(.10) : null),
              children: [
                for (var c = 0; c < width; c++)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      child: Text(
                        c < shown[r].length ? shown[r][c] : '',
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: r == 0 ? FontWeight.w800 : FontWeight.w500,
                            color: fg),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A spreadsheet tab: a real grid with column letters and row numbers that
/// scrolls both ways and builds only the visible rows. Long-press a cell to
/// copy it.
class _SheetGrid extends StatelessWidget {
  final List<List<String>> rows;
  final bool dark;
  const _SheetGrid({super.key, required this.rows, required this.dark});

  static String _letters(int i) {
    var n = i + 1;
    var s = '';
    while (n > 0) {
      final r = (n - 1) % 26;
      s = String.fromCharCode(65 + r) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : BookNestColors.navyDeep;
    final line = BookNestColors.cyan.withOpacity(.22);
    final cols = rows.fold<int>(0, (w, r) => r.length > w ? r.length : w);
    final widths = List<double>.filled(cols, 64);
    for (final r in rows.take(300)) {
      for (var c = 0; c < r.length; c++) {
        final chars = r[c].split('\n').fold<int>(0, (m, l) => l.length > m ? l.length : m);
        final w = (chars < 3 ? 3 : (chars > 42 ? 42 : chars)) * 7.6 + 22;
        if (w > widths[c]) widths[c] = w;
      }
    }
    const rowHead = 46.0, rowHeight = 34.0;
    final total = rowHead + widths.fold<double>(0, (a, b) => a + b);

    Widget cell(String text, double width,
        {bool head = false, Alignment align = Alignment.centerLeft}) {
      return GestureDetector(
        onLongPress: head || text.isEmpty
            ? null
            : () {
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(content: Text('Cell copied')));
              },
        child: Container(
          width: width,
          height: rowHeight,
          alignment: align,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: head ? BookNestColors.cyan.withOpacity(.10) : null,
            border: Border(right: BorderSide(color: line), bottom: BorderSide(color: line)),
          ),
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: head ? FontWeight.w800 : FontWeight.w500,
                  color: head ? BookNestColors.cyan : fg)),
        ),
      );
    }

    final numeric = RegExp(r'^-?[\d,.]+%?$');
    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: total,
          child: ListView.builder(
            itemCount: rows.length + 1,
            itemBuilder: (_, i) {
              if (i == 0) {
                return Row(children: [
                  cell('', rowHead, head: true),
                  for (var c = 0; c < cols; c++)
                    cell(_letters(c), widths[c], head: true, align: Alignment.center),
                ]);
              }
              final r = rows[i - 1];
              return Row(children: [
                cell('$i', rowHead, head: true, align: Alignment.center),
                for (var c = 0; c < cols; c++)
                  cell(
                    c < r.length ? r[c] : '',
                    widths[c],
                    align: c < r.length && numeric.hasMatch(r[c])
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                  ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

/// The files inside a zip / tar: tap one to open it in the viewer.
class _ArchiveList extends StatelessWidget {
  final ExtractedDoc doc;
  final Uint8List bytes;
  final MediaItem item;
  final bool dark;
  const _ArchiveList(
      {required this.doc, required this.bytes, required this.item, required this.dark});

  static IconData _icon(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if (isImageExtension(ext)) return Icons.image_outlined;
    if (isVideoExtension(ext)) return Icons.movie_outlined;
    if (isAudioExtension(ext)) return Icons.audiotrack_outlined;
    if (ext == 'pdf') return Icons.picture_as_pdf_outlined;
    if (const {'zip', 'tar', 'gz', 'tgz', 'rar', '7z'}.contains(ext)) {
      return Icons.folder_zip_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  Future<void> _open(BuildContext context, ArchiveEntryInfo e) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final data = await compute(archiveEntryFromMap,
        <String, Object?>{'bytes': bytes, 'ext': item.extension, 'name': e.name});
    if (data == null) {
      messenger?.showSnackBar(const SnackBar(content: Text('That file could not be opened.')));
      return;
    }
    final base = e.name.split('/').last;
    final dir = Directory(
        '${Directory.systemTemp.path}/booknest_media/zip_${(item.url + e.name).hashCode.abs().toRadixString(36)}');
    await dir.create(recursive: true);
    final file = File('${dir.path}/$base');
    await file.writeAsBytes(data, flush: true);
    if (!context.mounted) return;
    await openLocalFile(context, file, base);
  }

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : BookNestColors.navyDeep;
    return Column(children: [
      _NoteBanner(
          '${doc.format} · ${doc.entries.length} file${doc.entries.length == 1 ? '' : 's'} — tap one to open it',
          dark: dark),
      Expanded(
        child: ListView.separated(
          itemCount: doc.entries.length,
          separatorBuilder: (_, __) =>
              Divider(height: 1, color: BookNestColors.cyan.withOpacity(.12)),
          itemBuilder: (_, i) {
            final e = doc.entries[i];
            final slash = e.name.lastIndexOf('/');
            return ListTile(
              leading: Icon(_icon(e.name), color: BookNestColors.cyan),
              title: Text(slash < 0 ? e.name : e.name.substring(slash + 1),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, color: fg)),
              subtitle: Text(
                  [if (slash > 0) e.name.substring(0, slash), _formatBytes(e.size)].join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: fg.withOpacity(.6))),
              onTap: () => _open(context, e),
            );
          },
        ),
      ),
    ]);
  }
}
