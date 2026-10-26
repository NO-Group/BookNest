import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../../services/book_repository.dart';
import '../../components/booknest_ui.dart';
import '../../../state/book_providers.dart';

/// Chapter manager — reorderable-feeling list of a book's chapters with
/// add / edit / delete. Data comes from [manageBookProvider]; the
/// legacy-episode fallback lives inside the repository, not here.
class ChapterManagerScreen extends ConsumerStatefulWidget {
  final String bookId;

  const ChapterManagerScreen({super.key, required this.bookId});

  @override
  ConsumerState<ChapterManagerScreen> createState() =>
      _ChapterManagerScreenState();
}

class _ChapterManagerScreenState extends ConsumerState<ChapterManagerScreen> {
  @override
  void initState() {
    super.initState();
  }

  Future<void> _deleteChapter(Map<String, dynamic> chapter) async {
    final number = (chapter['chapterNumber'] as num?)?.toInt() ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Delete chapter?'),
        content: Text(
            'Chapter $number (${chapter['title'] ?? ''}) will be removed for '
            'every reader. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || number == 0) return;
    await BookRepository.instance
        .deleteChapter(bookId: widget.bookId, chapterNumber: number);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chapter deleted.')));
    ref.invalidate(manageBookProvider(widget.bookId));
  }

  @override
  Widget build(BuildContext context) {
    final managed = ref.watch(manageBookProvider(widget.bookId));
    final List<Map<String, dynamic>> _chapters = managed.asData?.value.chapters ?? const [];
    final String _title = managed.asData?.value.book?['title']?.toString() ?? '';
    final bool _loading = managed.isLoading;
    final bool _offline = managed.asData?.value.fromLegacyFallback ?? false;
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
          ? BookNestColors.darkChatBackground
          : BookNestColors.lightSurface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chapters',
                style: TextStyle(fontWeight: FontWeight.w800)),
            if (_title.isNotEmpty)
              Text(_title,
                  style:
                      TextStyle(color: theme.hintColor, fontSize: 12)),
          ],
        ),
      ),
      // Lifted above the navigation bar so it is never covered.
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 68),
        child: FloatingActionButton.extended(
        backgroundColor: BookNestColors.cyan,
        foregroundColor: BookNestColors.navyDeep,
        onPressed: () async {
          await context.push(
              '/write-chapter?bookId=${widget.bookId}&number=${_chapters.length + 1}');
          if (mounted) ref.invalidate(manageBookProvider(widget.bookId));
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add chapter',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: BookNestColors.cyan))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
              children: [
                if (_offline) ...[
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: BookNestColors.cyan.withOpacity(.08),
                      border: Border.all(
                          color: BookNestColors.cyan.withOpacity(.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_off_rounded,
                            color: BookNestColors.cyan, size: 19),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Reading from the temporary store. Editing and '
                            'new chapters activate once the cloud connects.',
                            style: TextStyle(
                                color: theme.hintColor,
                                fontSize: 12.5,
                                height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (_chapters.isEmpty && !_offline)
                  const EmptyState(
                    icon: Icons.format_list_numbered_rounded,
                    title: 'No chapters yet',
                    subtitle: 'Add chapter one and start writing.',
                  )
                else
                  ..._chapters.asMap().entries.map((entry) {
                    final index = entry.key;
                    final chapter = entry.value;
                    final number =
                        (chapter['chapterNumber'] as num?)?.toInt() ?? index + 1;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: theme.colorScheme.surface,
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          leading: CircleAvatar(
                            radius: 17,
                            backgroundColor:
                                BookNestColors.cyan.withOpacity(.15),
                            child: Text('$number',
                                style: const TextStyle(
                                    color: BookNestColors.cyan,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13)),
                          ),
                          title: Text(
                              chapter['title']?.toString() ??
                                  'Chapter $number',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_rounded,
                                    size: 19, color: BookNestColors.cyan),
                                tooltip: 'Edit',
                                onPressed: () async {
                                  await context.push(
                                      '/write-chapter?bookId=${widget.bookId}&number=$number&title=${Uri.encodeComponent(chapter['title']?.toString() ?? '')}');
                                  if (mounted) {
                                    ref.invalidate(
                                        manageBookProvider(widget.bookId));
                                  }
                                },
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline_rounded,
                                    size: 19,
                                    color: theme.colorScheme.error),
                                tooltip: 'Delete',
                                onPressed: () => _deleteChapter(chapter),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
