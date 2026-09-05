import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../components/booknest_ui.dart';

/// Book analytics — real counters from MongoDB (views, likes, saves,
/// reviews, average rating) plus the latest reviews.
class BookAnalyticsScreen extends StatefulWidget {
  final String bookId;

  const BookAnalyticsScreen({super.key, required this.bookId});

  @override
  State<BookAnalyticsScreen> createState() => _BookAnalyticsScreenState();
}

class _BookAnalyticsScreenState extends State<BookAnalyticsScreen> {
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _recent = [];
  bool _loading = true;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await BackendApi.instance.bookStats(widget.bookId);
    if (!mounted) return;
    setState(() {
      _offline = res == null;
      _stats = res?['stats'] == null
          ? null
          : Map<String, dynamic>.from(res!['stats'] as Map);
      _recent = (res?['recentReviews'] as List? ?? [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _loading = false;
    });
  }

  String _fmt(dynamic value) => NumberFormat.decimalPattern()
      .format((value as num?)?.toInt() ?? 0);

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
        title: const Text('Analytics',
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
                      'Reading counts, likes, saves and reviews are counted in '
                      'the BookNest cloud. They will appear here once synced.',
                  action: GradientButton(
                      label: 'Retry',
                      icon: Icons.refresh_rounded,
                      onPressed: () {
                        setState(() => _loading = true);
                        _load();
                      }),
                )
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
                                  icon: Icons.visibility_rounded,
                                  value: _fmt(_stats?['view_count']),
                                  label: 'Views')),
                          const SizedBox(width: 10),
                          Expanded(
                              child: StatTile(
                                  icon: Icons.favorite_rounded,
                                  value: _fmt(_stats?['like_count']),
                                  label: 'Likes')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                              child: StatTile(
                                  icon: Icons.bookmark_rounded,
                                  value: _fmt(_stats?['bookmark_count']),
                                  label: 'Saves')),
                          const SizedBox(width: 10),
                          Expanded(
                              child: StatTile(
                                  icon: Icons.star_rounded,
                                  value:
                                      '${_stats?['average_rating'] ?? 0}★',
                                  label:
                                      '${_fmt(_stats?['review_count'])} reviews')),
                        ],
                      ),
                      const SizedBox(height: 26),
                      SectionHeader(title: 'Latest reviews'),
                      const SizedBox(height: 12),
                      if (_recent.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text('No reviews yet.',
                              style: TextStyle(color: theme.hintColor)),
                        )
                      else
                        ..._recent.map((review) => Container(
                              margin:
                                  const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                color: theme.colorScheme.surface,
                                border: Border.all(
                                    color: theme.dividerColor),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                          review['userName']
                                                  ?.toString() ??
                                              'Reader',
                                          style: const TextStyle(
                                              fontWeight:
                                                  FontWeight.w800,
                                              fontSize: 13)),
                                      const Spacer(),
                                      ...List.generate(
                                        ((review['rating'] as num?)
                                                    ?.toInt() ??
                                                0)
                                            .clamp(0, 5),
                                        (_) => const Icon(
                                            Icons.star_rounded,
                                            color: BookNestColors.cyan,
                                            size: 13),
                                      ),
                                    ],
                                  ),
                                  if (review['body']
                                          ?.toString()
                                          .isNotEmpty ==
                                      true) ...[
                                    const SizedBox(height: 6),
                                    Text(review['body'].toString(),
                                        style: TextStyle(
                                            color: theme.hintColor,
                                            fontSize: 13,
                                            height: 1.4)),
                                  ],
                                ],
                              ),
                            )),
                    ],
                  ),
                ),
    );
  }
}
