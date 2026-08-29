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

  List<Map<String, dynamic>> _works = [];
  bool _worksLoading = true;

  String? get _viewerId => SupabaseService().auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _loadSaved();
    _loadWorks();
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
            onRetry: _loadSaved,
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
  final VoidCallback onRetry;

  const _SavedTab({
    required this.loading,
    required this.offline,
    required this.books,
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
    return RefreshIndicator(
      color: BookNestColors.cyan,
      onRefresh: onRetry,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        itemCount: books.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final book = books[index];
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
