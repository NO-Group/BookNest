import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../components/booknest_ui.dart';
import '../../components/chat_kit.dart';
import 'media_viewer_screen.dart';

/// Everything a conversation has exchanged, in tabs: photos, shared
/// documents, links, and files. Served from the edge (full history, not
/// just what the chat has loaded).
class SharedContentScreen extends StatefulWidget {
  const SharedContentScreen({
    super.key,
    required this.conversationId,
    required this.title,
  });

  final String conversationId;
  final String title;

  @override
  State<SharedContentScreen> createState() => _SharedContentScreenState();
}

class _SharedContentScreenState extends State<SharedContentScreen> {
  List<Map<String, dynamic>> _media = [];
  List<Map<String, dynamic>> _docs = [];
  List<Map<String, dynamic>> _links = [];
  List<Map<String, dynamic>> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await BackendApi.instance.chatShared(widget.conversationId);
    if (!mounted) return;
    List<Map<String, dynamic>> toList(dynamic rows) => ((rows as List?) ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final media = toList(res?['media']);
    final files = toList(res?['files']);
    setState(() {
      _media = media;
      _files = files;
      _docs = files
          .where((m) => m['type']?.toString() == 'file')
          .toList();
      _links = toList(res?['links']);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      appBar: GlassAppBar(title: 'Shared · ${widget.title}'),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: BookNestColors.cyan))
          : DefaultTabController(
              length: 4,
              child: Column(children: [
                TabBar(
                  labelColor: BookNestColors.cyan,
                  unselectedLabelColor: onSurface.withOpacity(.55),
                  indicatorColor: BookNestColors.cyan,
                  tabs: [
                    const Tab(icon: Icon(Icons.photo_rounded, size: 19), text: 'Media'),
                    Tab(
                        icon: const Icon(Icons.description_rounded, size: 19),
                        text: 'Docs · ${_docs.length}'),
                    Tab(
                        icon: const Icon(Icons.link_rounded, size: 19),
                        text: 'Links · ${_links.length}'),
                    Tab(
                        icon: const Icon(Icons.folder_rounded, size: 19),
                        text: 'Files · ${_files.length}'),
                  ],
                ),
                Expanded(
                  child: TabBarView(children: [
                    _mediaTab(),
                    _docsTab(onSurface),
                    _linksTab(onSurface),
                    _filesTab(onSurface),
                  ]),
                ),
              ]),
            ),
    );
  }

  Widget _mediaTab() {
    if (_media.isEmpty) {
      return const _EmptyShared(icon: Icons.photo_outlined, label: 'No photos yet');
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4),
      itemCount: _media.length,
      itemBuilder: (context, i) {
        final url = _media[i]['mediaUrl']?.toString() ?? '';
        return GestureDetector(
          onTap: () => openChatPhoto(context, url, album: [
            for (final m in _media)
              MediaItem(url: m['mediaUrl']?.toString() ?? '', name: widget.title)
          ], initialIndex: i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(url, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                    color: BookNestColors.navy.withOpacity(.3),
                    child: const Icon(Icons.broken_image_outlined,
                        color: BookNestColors.cyan))),
          ),
        );
      },
    );
  }

  Widget _docsTab(Color onSurface) {
    if (_docs.isEmpty) {
      return const _EmptyShared(
          icon: Icons.description_outlined, label: 'No documents yet');
    }
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        for (final m in _docs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.description_rounded,
                  color: BookNestColors.cyan),
              title: Text(m['fileName']?.toString() ?? 'Document',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: onSurface)),
              onTap: () => openChatFile(
                context,
                m['mediaUrl']?.toString() ?? '',
                name: m['fileName']?.toString() ?? 'Document',
              ),
            ),
          ),
      ],
    );
  }

  Widget _linksTab(Color onSurface) {
    if (_links.isEmpty) {
      return const _EmptyShared(icon: Icons.link_outlined, label: 'No links yet');
    }
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        for (final m in _links)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GlassPanel(
              radius: 16,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    const Icon(Icons.link_rounded,
                        size: 16, color: BookNestColors.cyan),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(m['text']?.toString() ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              color: onSurface)),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
      ],
    );
  }

  Widget _filesTab(Color onSurface) {
    if (_files.isEmpty) {
      return const _EmptyShared(
          icon: Icons.folder_outlined, label: 'No files yet');
    }
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        for (final m in _files)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(
                  m['type']?.toString() == 'video'
                      ? Icons.movie_rounded
                      : Icons.insert_drive_file_rounded,
                  color: BookNestColors.cyan),
              title: Text(
                  m['fileName']?.toString() ?? m['text']?.toString() ?? 'File',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: onSurface)),
              onTap: () => openChatFile(
                context,
                m['mediaUrl']?.toString() ?? '',
                name: m['fileName']?.toString() ?? 'File',
              ),
            ),
          ),
      ],
    );
  }
}

class _EmptyShared extends StatelessWidget {
  const _EmptyShared({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 40, color: BookNestColors.cyan.withOpacity(.45)),
        const SizedBox(height: 10),
        Text(label,
            style: TextStyle(fontSize: 13.5, color: onSurface.withOpacity(.6))),
      ]),
    );
  }
}
