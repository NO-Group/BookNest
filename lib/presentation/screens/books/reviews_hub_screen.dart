import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../../services/supabase_service.dart';
import '../../components/booknest_ui.dart';

/// Reviews hub (author side): every work you've written, ready to inspect.
/// Tapping a book opens its public reviews page.
class ReviewsHubScreen extends StatefulWidget {
  const ReviewsHubScreen({super.key});

  @override
  State<ReviewsHubScreen> createState() => _ReviewsHubScreenState();
}

class _ReviewsHubScreenState extends State<ReviewsHubScreen> {
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
      final res = await BackendApi.instance
          .call('books.list', {'mine': true, 'limit': 60});
      final rows = (res?['books'] as List?) ?? const [];
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
        title: const Text('Reviews hub',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: BookNestColors.cyan))
          : _works.isEmpty
              ? const EmptyState(
                  icon: Icons.rate_review_rounded,
                  title: 'No books to review yet',
                  subtitle: 'Publish a book and reader reviews will gather here.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                  itemCount: _works.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final book = _works[index];
                    final id = book['id']?.toString() ?? '';
                    final title = book['title']?.toString() ?? 'Untitled';
                    return Material(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        leading: BookCover(
                            coverUrl: book['cover_url']?.toString(),
                            title: title,
                            width: 42,
                            height: 58,
                            radius: 8),
                        title: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700)),
                        subtitle: Text(
                            book['genre']?.toString() ?? 'No genre set',
                            style: TextStyle(
                                color: theme.hintColor, fontSize: 12)),
                        trailing: const Icon(Icons.star_rounded,
                            color: BookNestColors.cyan),
                        onTap: () => context.push('/book/$id/reviews'),
                      ),
                    );
                  },
                ),
    );
  }
}
