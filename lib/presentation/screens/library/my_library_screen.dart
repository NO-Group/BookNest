import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../../services/supabase_service.dart';
import '../../components/booknest_ui.dart';

/// My Library — everything you keep: cloud-synced saved books + your works.
class MyLibraryScreen extends StatefulWidget {
  const MyLibraryScreen({super.key});

  @override
  State<MyLibraryScreen> createState() => _MyLibraryScreenState();
}

class _MyLibraryScreenState extends State<MyLibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  List<Map<String, dynamic>> _saved = [];
  bool _savedLoading = true;
  bool _cloudOffline = false;

  /// Books the reader is partway through (immersive Reader progress).
  List<Map<String, dynamic>> _continue = [];

  List<Map<String, dynamic>> _works = [];
  bool _worksLoading = true;

  String? get _viewerId => SupabaseService().auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _loadSaved();
    _loadWorks();
    _loadContinue();
  }

  Future<void> _loadContinue() async {
    final res = await BackendApi.instance.call('reader.progress.list');
    if (!mounted) return;
    setState(() {
      _continue = ((res?['items'] as List?) ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
    });
  }

  void _reloadEverything() {
    _loadSaved();
    _loadContinue();
  }

  Future<void> _loadSaved() async {
    final res = await BackendApi.instance.bookmarkedBooks();
    if (!mounted) return;
    setState(() {
      _cloudOffline = res == null;
      _saved = (res?['books'] as List? ?? [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _savedLoading = false;
    });
  }

  Future<void> _loadWorks() async {
    try {
      final res = await BackendApi.instance
          .call('books.list', {'mine': true, 'limit': 60});
      final rows = (res?['books'] as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        _works = (rows as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        _worksLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _worksLoading = false);
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
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: (Theme.of(context).brightness == Brightness.dark
                        ? BookNestColors.darkChatBackground
                        : Colors.white)
                    .withOpacity(.66),
                border: Border(
                  bottom: BorderSide(
                      color: BookNestColors.cyan.withOpacity(.15)),
                ),
              ),
            ),
          ),
        ),
        title: const Text('My library',
            style: TextStyle(fontWeight: FontWeight.w800)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: BookNestColors.cyan,
          labelColor: theme.colorScheme.onSurface,
          unselectedLabelColor: theme.hintColor,
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(icon: Icon(Icons.bookmarks_rounded, size: 19), text: 'Saved'),
            Tab(icon: Icon(Icons.edit_note_rounded, size: 19), text: 'My works'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _SavedTab(
            loading: _savedLoading,
            offline: _cloudOffline,
            books: _saved,
            continueItems: _continue,
            onRetry: _reloadEverything,
          ),
          _WorksTab(loading: _worksLoading, books: _works),
        ],
      ),
    );
  }
}

class _SavedTab extends StatelessWidget {
  final bool loading;
  final bool offline;
  final List<Map<String, dynamic>> books;
  final List<Map<String, dynamic>> continueItems;
  final VoidCallback onRetry;

  const _SavedTab({
    required this.loading,
    required this.offline,
    required this.books,
    required this.continueItems,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
          child: CircularProgressIndicator(color: BookNestColors.cyan));
    }
    if (offline) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Cloud not connected yet',
        subtitle: 'Your saved books sync through the BookNest cloud. '
            'Everything you save on book pages is kept safely until then.',
        action: GradientButton(
            label: 'Retry', icon: Icons.refresh_rounded, onPressed: onRetry),
      );
    }
    if (books.isEmpty) {
      return EmptyState(
        icon: Icons.bookmark_border_rounded,
        title: 'Nothing saved yet',
        subtitle: 'Tap the bookmark on any book and it will wait for you here.',
      );
    }
    final showRail = continueItems.isNotEmpty;
    return RefreshIndicator(
      color: BookNestColors.cyan,
      onRefresh: () async => onRetry(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        itemCount: books.length + (showRail ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == 0 && showRail) {
            return _ContinueRail(items: continueItems);
          }
          final book = books[index - (showRail ? 1 : 0)];
          return _LibraryBookCard(
            id: book['id']?.toString() ?? '',
            title: book['title']?.toString() ?? 'Untitled',
            author: book['author']?.toString() ?? 'Unknown',
            coverUrl: book['cover_url']?.toString(),
            subtitle:
                '${book['like_count'] ?? 0} likes · ${book['average_rating'] ?? 0}★',
          );
        },
      ),
    );
  }
}

/// 'Continue reading' shelf — picks up exactly where the reader stopped.
class _ContinueRail extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _ContinueRail({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_stories_rounded,
                color: BookNestColors.cyan, size: 18),
            const SizedBox(width: 8),
            Text(
              'Continue reading',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 178,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              final percent =
                  ((item['percent'] as num?)?.toDouble() ?? 0).clamp(0, 100);
              return GestureDetector(
                onTap: () => context
                    .push('/reader?bookId=${item['bookId']}'),
                child: SizedBox(
                  width: 108,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 120,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: BookCover(
                                coverUrl: item['coverUrl']?.toString(),
                                title: item['title']?.toString() ?? 'Untitled',
                                width: 108,
                                height: 120,
                              ),
                            ),
                            if (percent >= 99)
                              Positioned(
                                top: 6,
                                right: 6,
                                child: CircleAvatar(
                                  radius: 11,
                                  backgroundColor: BookNestColors.cyan,
                                  child: const Icon(Icons.done_rounded,
                                      size: 14, color: Colors.black),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item['title']?.toString() ?? 'Untitled',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 12.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Chapter ${item['chapterNumber'] ?? 1} of ${item['chaptersCount'] ?? 1}',
                        style: TextStyle(
                            fontSize: 11, color: Theme.of(context).hintColor),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: percent / 100,
                          minHeight: 3,
                          backgroundColor:
                              BookNestColors.cyan.withOpacity(.15),
                          color: BookNestColors.cyan,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WorksTab extends StatelessWidget {
  final bool loading;
  final List<Map<String, dynamic>> books;

  const _WorksTab({required this.loading, required this.books});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
          child: CircularProgressIndicator(color: BookNestColors.cyan));
    }
    if (books.isEmpty) {
      return EmptyState(
        icon: Icons.auto_stories_rounded,
        title: 'You haven\'t written yet',
        subtitle: 'Your stories, textbooks and research live here once published.',
        action: GradientButton(
          label: 'Write your first book',
          icon: Icons.edit_rounded,
          onPressed: () => context.push('/editor'),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      itemCount: books.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final book = books[index];
        final status = book['moderation_status']?.toString() ?? 'pending';
        return _LibraryBookCard(
          id: book['id']?.toString() ?? '',
          title: book['title']?.toString() ?? 'Untitled',
          author: 'You',
          coverUrl: book['cover_url']?.toString(),
          subtitle: status == 'approved' ? 'Live in the library' : 'In review',
          badge: status == 'approved' ? null : Icons.hourglass_top_rounded,
          trailingRoute: '/manage/${book['id']}',
        );
      },
    );
  }
}

class _LibraryBookCard extends StatelessWidget {
  final String id;
  final String title;
  final String author;
  final String? coverUrl;
  final String subtitle;
  final IconData? badge;
  final String? trailingRoute;

  const _LibraryBookCard({
    required this.id,
    required this.title,
    required this.author,
    required this.subtitle,
    this.coverUrl,
    this.badge,
    this.trailingRoute,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push(trailingRoute ?? '/book/$id'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Hero(
                tag: 'book-$id',
                child: BookCover(coverUrl: coverUrl, title: title),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(author,
                        style: const TextStyle(
                            color: BookNestColors.cyan,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(subtitle,
                            style: TextStyle(
                                color: theme.hintColor, fontSize: 12)),
                        if (badge != null) ...[
                          const SizedBox(width: 5),
                          Icon(badge, size: 13, color: theme.hintColor),
                        ],
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
    );
  }
}
