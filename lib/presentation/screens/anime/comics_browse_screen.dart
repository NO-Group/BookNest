import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../components/booknest_ui.dart';

/// The Anime shelf — comics published by the community, rendered live
/// from their JSON pages. One tap opens the studio to make your own.
class ComicsBrowseScreen extends StatefulWidget {
  const ComicsBrowseScreen({super.key});

  @override
  State<ComicsBrowseScreen> createState() => _ComicsBrowseScreenState();
}

class _ComicsBrowseScreenState extends State<ComicsBrowseScreen> {
  bool _loading = true;
  bool _offline = false;
  List<Map<String, dynamic>> _comics = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await BackendApi.instance.call('comics.list');
    if (!mounted) return;
    setState(() {
      _offline = res == null;
      _comics = ((res?['comics'] as List?) ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        title: const Text('Anime',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: BookNestColors.cyan,
        foregroundColor: BookNestColors.navy,
        onPressed: () => context.push('/anime/studio'),
        icon: const Icon(Icons.brush_rounded),
        label: const Text('Studio',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: BookNestColors.cyan))
          : _offline
              ? const Center(
                  child: Text('The comic shelf needs the BookNest cloud.'))
              : _comics.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_stories_rounded,
                                size: 44, color: BookNestColors.cyan),
                            const SizedBox(height: 12),
                            const Text(
                              'No comics yet — the shelf is waiting '
                              'for the first one. Yours?',
                              textAlign: TextAlign.center,
                              style: TextStyle(height: 1.4),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                  backgroundColor: BookNestColors.cyan),
                              onPressed: () => context.push('/anime/studio'),
                              icon: const Icon(Icons.brush_rounded,
                                  color: BookNestColors.navy),
                              label: const Text('Open the Studio',
                                  style: TextStyle(
                                      color: BookNestColors.navy,
                                      fontWeight: FontWeight.w800)),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      color: BookNestColors.cyan,
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                        itemCount: _comics.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final comic = _comics[i];
                          final cover =
                              comic['coverUrl']?.toString() ?? '';
                          final updated = DateTime.tryParse(
                                  comic['updatedAt']?.toString() ?? '') ??
                              DateTime.now();
                          return Material(
                            color: theme.colorScheme.surface.withOpacity(.72),
                            borderRadius: BorderRadius.circular(18),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18)),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: cover.startsWith('http')
                                    ? Image.network(cover,
                                        width: 52,
                                        height: 68,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            Container(
                                                width: 52,
                                                height: 68,
                                                color: BookNestColors.cyan
                                                    .withOpacity(.12),
                                                child: const Icon(
                                                    Icons
                                                        .auto_stories_rounded,
                                                    color: BookNestColors
                                                        .cyan)))
                                    : Container(
                                        width: 52,
                                        height: 68,
                                        color:
                                            BookNestColors.cyan.withOpacity(.12),
                                        child: const Icon(
                                            Icons.auto_stories_rounded,
                                            color: BookNestColors.cyan)),
                              ),
                              title: Text(
                                  comic['title']?.toString() ?? 'Untitled',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800)),
                              subtitle: Text(
                                '${comic['ownerName']?.toString() ?? 'Anonymous'}'
                                ' · ${comic['pagesCount'] ?? 1} page(s)'
                                ' · ${DateFormat.yMMMd().format(updated)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: theme.hintColor, fontSize: 12),
                              ),
                              trailing:
                                  const Icon(Icons.chevron_right_rounded),
                              onTap: () => context
                                  .push('/anime/${comic['id']}'),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
