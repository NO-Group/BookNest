import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../../services/supabase_service.dart';
import '../../components/booknest_ui.dart';

/// All reviews for one book. Readers can remove their own review.
class BookReviewsScreen extends StatefulWidget {
  final String bookId;

  const BookReviewsScreen({super.key, required this.bookId});

  @override
  State<BookReviewsScreen> createState() => _BookReviewsScreenState();
}

class _BookReviewsScreenState extends State<BookReviewsScreen> {
  List<Map<String, dynamic>> _reviews = [];
  bool _loading = true;
  bool _offline = false;

  String? get _viewerId => SupabaseService().auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await BackendApi.instance.call('reviews.list',
        <String, dynamic>{'bookId': widget.bookId, 'limit': 50});
    if (!mounted) return;
    setState(() {
      _offline = res == null;
      _reviews = (res?['reviews'] as List? ?? [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _loading = false;
    });
  }

  Future<void> _deleteMine(Map<String, dynamic> review) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete your review?'),
        content: const Text('You can always write a new one.'),
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
    if (confirmed != true) return;
    await BackendApi.instance.deleteReview(widget.bookId);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Review deleted.')));
    _load();
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
        title: const Text('Ratings & reviews',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: BookNestColors.cyan,
        foregroundColor: BookNestColors.navyDeep,
        onPressed: () => context.pop(),
        icon: const Icon(Icons.rate_review_rounded),
        label: const Text('Write one',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: BookNestColors.cyan))
          : _offline
              ? EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Cloud not connected yet',
                  subtitle:
                      'Reviews live in the BookNest cloud and will appear here '
                      'once it is connected.',
                  action: GradientButton(
                      label: 'Retry',
                      icon: Icons.refresh_rounded,
                      onPressed: () {
                        setState(() => _loading = true);
                        _load();
                      }),
                )
              : _reviews.isEmpty
                  ? const EmptyState(
                      icon: Icons.star_border_rounded,
                      title: 'No reviews yet',
                      subtitle: 'Be the first reader to rate this book.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
                      itemCount: _reviews.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final review = _reviews[index];
                        final rating =
                            ((review['rating'] as num?)?.toInt() ?? 0)
                                .clamp(0, 5);
                        final mine = review['userId']?.toString() == _viewerId;
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            color: theme.colorScheme.surface,
                            border: Border.all(color: theme.dividerColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                        review['userName']?.toString() ??
                                            'Reader',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800)),
                                  ),
                                  if (mine)
                                    TextButton(
                                      onPressed: () => _deleteMine(review),
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        foregroundColor:
                                            theme.colorScheme.error,
                                      ),
                                      child: const Text('Delete',
                                          style: TextStyle(fontSize: 12.5)),
                                    ),
                                ],
                              ),
                              Row(
                                children: [
                                  ...List.generate(
                                      rating,
                                      (_) => const Icon(Icons.star_rounded,
                                          color: BookNestColors.cyan,
                                          size: 16)),
                                  ...List.generate(
                                      5 - rating,
                                      (_) => Icon(Icons.star_outline_rounded,
                                          color: theme.hintColor,
                                          size: 16)),
                                ],
                              ),
                              if (review['body']?.toString().isNotEmpty ==
                                  true) ...[
                                const SizedBox(height: 8),
                                Text(review['body'].toString(),
                                    style: TextStyle(
                                        color: theme
                                            .colorScheme.onSurface
                                            .withOpacity(.85),
                                        height: 1.45,
                                        fontSize: 13.5)),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}
