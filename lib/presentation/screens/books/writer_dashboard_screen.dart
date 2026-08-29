import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../services/supabase_service.dart';
import '../../components/booknest_ui.dart';

/// Writer dashboard — the author's home: works, tools, quick actions.
class WriterDashboardScreen extends StatefulWidget {
  const WriterDashboardScreen({super.key});

  @override
  State<WriterDashboardScreen> createState() => _WriterDashboardScreenState();
}

class _WriterDashboardScreenState extends State<WriterDashboardScreen> {
  List<Map<String, dynamic>> _works = [];
  bool _loading = true;

  String? get _viewerId => SupabaseService().auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await SupabaseService()
          .client
          .from('club_books')
          .select()
          .eq('added_by', _viewerId ?? '')
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _works = (rows as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
          ? BookNestColors.darkChatBackground
          : BookNestColors.lightSurface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Writer dashboard',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: BookNestColors.cyan))
          : RefreshIndicator(
              color: BookNestColors.cyan,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          icon: Icons.menu_book_rounded,
                          value: '${_works.length}',
                          label: 'Books',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => context.push('/my-reviews'),
                          child: const StatTile(
                            icon: Icons.rate_review_rounded,
                            value: '→',
                            label: 'Reviews hub',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  GradientButton(
                    label: 'Start a new book',
                    icon: Icons.edit_rounded,
                    onPressed: () => context.push('/editor'),
                  ),
                  const SizedBox(height: 22),
                  SectionHeader(title: 'Your works'),
                  const SizedBox(height: 12),
                  if (_works.isEmpty)
                    const EmptyState(
                      icon: Icons.auto_stories_rounded,
                      title: 'No books yet',
                      subtitle:
                          'Every great author started with a blank page. '
                          'Write chapter one today.',
                    )
                  else
                    ..._works.map((book) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _WorkCard(book: book),
                        )),
                ],
              ),
            ),
    );
  }
}

class _WorkCard extends StatelessWidget {
  final Map<String, dynamic> book;
  const _WorkCard({required this.book});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = book['id']?.toString() ?? '';
    final title = book['title']?.toString() ?? 'Untitled';
    final live = (book['moderation_status']?.toString() ?? '') == 'approved';
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(18)),
            onTap: () => context.push('/manage/$id'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Hero(
                    tag: 'book-$id',
                    child: BookCover(
                        coverUrl: book['cover_url']?.toString(), title: title),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              live
                                  ? Icons.check_circle_rounded
                                  : Icons.hourglass_top_rounded,
                              size: 14,
                              color: live
                                  ? BookNestColors.cyan
                                  : theme.hintColor,
                            ),
                            const SizedBox(width: 5),
                            Text(live ? 'Live' : 'In review',
                                style: TextStyle(
                                    color: theme.hintColor, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: theme.hintColor),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: theme.dividerColor),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () => context.push('/manage/$id/chapters'),
                  icon: const Icon(Icons.format_list_bulleted_rounded,
                      size: 17, color: BookNestColors.cyan),
                  label: const Text('Chapters',
                      style: TextStyle(
                          color: BookNestColors.cyan,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5)),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => context.push('/analytics/$id'),
                  icon: const Icon(Icons.insights_rounded,
                      size: 17, color: BookNestColors.cyan),
                  label: const Text('Analytics',
                      style: TextStyle(
                          color: BookNestColors.cyan,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
