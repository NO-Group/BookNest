// lib/presentation/screens/feed/feed_screen.dart

import 'dart:math';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../components/post_extras.dart';
import '../../../services/backend_api.dart';
import '../../../services/supabase_service.dart';
import '../../components/booknest_ui.dart';
import '../../components/report_sheet.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen>
    with SingleTickerProviderStateMixin {
  List<dynamic> _posts = [];
  List<dynamic> _filteredPosts = [];
  bool _isLoading = true;
  String _activeFilter = 'All';
  bool _isStylusOpen = false;

  late AnimationController _stylusController;
  late Animation<double> _stylusRotation;

  final List<String> _filters = [
    'All',
    'Quote',
    'News',
    'Poll',
    'Event',
    'Article',
  ];

  final List<_PostType> _postTypes = const [
    _PostType(label: 'Quote', icon: Icons.format_quote, color: BookNestColors.cyan),
    _PostType(label: 'News', icon: Icons.newspaper, color: BookNestColors.navy),
    _PostType(label: 'Poll', icon: Icons.poll, color: BookNestColors.cyan),
    _PostType(label: 'Event', icon: Icons.event, color: BookNestColors.navy),
    _PostType(label: 'Article', icon: Icons.article, color: BookNestColors.navy),
  ];

  @override
  void initState() {
    super.initState();
    _stylusController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _stylusRotation = Tween<double>(begin: 0, end: 0.5).animate(
      CurvedAnimation(parent: _stylusController, curve: Curves.easeOutBack),
    );
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    // Cutover: the feed lives on the app's own data store now; the legacy
    // SQL read remains as a graceful fallback while devices update.
    List<dynamic> response;
    try {
      final res = await BackendApi.instance.callFresh('posts.list');
      response = (res?['posts'] as List?) ?? const [];
    } catch (_) {
      response = const [];
    }
    if (response.isEmpty) {
      try {
        response = await SupabaseService()
            .client
            .from('posts')
            .select('*, profiles(username, avatar_url)')
            .order('created_at', ascending: false);
      } catch (_) {}
    }
    try {
      // Attach cloud like stats (best-effort — the feed never blocks on it).
      final ids = <String>[];
      for (final p in response) {
        if (p is Map && p['id'] != null) ids.add(p['id'].toString());
      }
      final stats = ids.isNotEmpty
          ? await SupabaseService().feedStats(ids)
          : <String, Map<String, dynamic>>{};
      for (final p in response) {
        if (p is! Map) continue;
        final s = stats[p['id']?.toString()];
        if (s != null) {
          p['like_count'] = s['likeCount'];
          p['liked_by_me'] = s['likedByMe'];
        }
      }

      setState(() {
        _posts = response;
        _filteredPosts = response;
        _isLoading = false;
      });
      // Count this visit's views (the cloud dedupes per reader per day).
      if (ids.isNotEmpty) {
        BackendApi.instance
            .call('posts.view', {'postIds': ids})
            .catchError((_) => null);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _removePostLocally(int index) {
    if (index < 0 || index >= _filteredPosts.length) return;
    final id = _filteredPosts[index]['id']?.toString();
    setState(() {
      _filteredPosts.removeAt(index);
      if (id != null) {
        _posts.removeWhere((p) => p['id']?.toString() == id);
      }
    });
  }

  void _filterPosts(String filter) {
    setState(() {
      _activeFilter = filter;
      if (filter == 'All') {
        _filteredPosts = _posts;
      } else {
        _filteredPosts = _posts.where((p) => p['type'] == filter.toLowerCase()).toList();
      }
    });
  }

  void _toggleStylus() {
    setState(() => _isStylusOpen = !_isStylusOpen);
    if (_isStylusOpen) {
      _stylusController.forward();
    } else {
      _stylusController.reverse();
    }
  }

  Future<void> _onPostTypeTap(_PostType type) async {
    _toggleStylus();
    switch (type.label) {
      case 'Quote':
        await context.push('/create/quote');
        break;
      case 'News':
        await context.push('/create/news');
        break;
      case 'Poll':
        await context.push('/create/poll');
        break;
      case 'Event':
        await context.push('/create/event');
        break;
      case 'Article':
        await context.push('/editor');
        break;
    }
    _loadPosts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Main content
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Feed',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Search',
                            icon: const Icon(Icons.search),
                            onPressed: () => context.push('/search'),
                          ),
                          IconButton(
                            tooltip: 'Notifications',
                            icon: const Icon(Icons.notifications_none),
                            onPressed: () => context.push('/notifications'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Filter bar
                SizedBox(
                  height: 44,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filters.length,
                    itemBuilder: (context, index) {
                      final filter = _filters[index];
                      final isActive = _activeFilter == filter;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => _filterPosts(filter),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? BookNestColors.cyan
                                  : Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: isActive
                                  ? null
                                  : Border.all(color: Theme.of(context).dividerColor),
                            ),
                            child: Text(
                              filter,
                              style: TextStyle(
                                color: isActive
                                    ? BookNestColors.navyDeep
                                    : Theme.of(context).colorScheme.onSurface,
                                fontSize: 13,
                                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 8),

                // Posts list
                Expanded(
                  child: _isLoading
                      ? const Center(child: BookNestLoader(size: 64))
                      : _filteredPosts.isEmpty
                          ? _buildEmptyState()
                          : RefreshIndicator(
                              color: BookNestColors.cyan,
                              onRefresh: _loadPosts,
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                itemCount: _filteredPosts.length,
                                itemBuilder: (context, index) {
                                  return Entrance(
                                    index: index,
                                    child: _PostCard(
                                      post: _filteredPosts[index],
                                      onDeleted: () =>
                                          _removePostLocally(index),
                                    ),
                                  );
                                },
                              ),
                            ),
                ),
              ],
            ),
          ),

          // Stylus FAB with vertical stack
          Positioned(
            right: 20,
            bottom: 100,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Post type buttons (vertical stack above stylus)
                AnimatedOpacity(
                  opacity: _isStylusOpen ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutBack,
                    height: _isStylusOpen
                        ? min(_postTypes.length * 64.0,
                            MediaQuery.sizeOf(context).height * .38)
                        : 0,
                    child: SingleChildScrollView(
                      physics: _isStylusOpen
                          ? const ClampingScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _postTypes.map((type) {
                          return _buildPostTypeButton(type);
                        }).toList(),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Main stylus button
                GestureDetector(
                  onTap: _toggleStylus,
                  child: AnimatedBuilder(
                    animation: _stylusRotation,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: _stylusRotation.value * 3.14159,
                        child: Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [BookNestColors.cyanSoft, BookNestColors.cyan],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: BookNestColors.navyDeep.withOpacity(.25),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: BookNestColors.cyan.withOpacity(0.35),
                                blurRadius: 18,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: SvgPicture.asset(
                              'assets/logo/stylus_polished.svg',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostTypeButton(_PostType type) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => _onPostTypeTap(type),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: (dark
                      ? BookNestColors.darkChatBackground
                      : Colors.white)
                  .withOpacity(.55),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: BookNestColors.cyan.withOpacity(.24)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(type.icon, color: type.color, size: 20),
                const SizedBox(width: 8),
                Text(
                  type.label,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return EmptyState(
      icon: Icons.feed_outlined,
      title: 'No posts yet',
      subtitle: 'Tap the stylus to share a quote, news, a poll or an event — '
          'or open the editor to start a book.',
    );
  }

  @override
  void dispose() {
    _stylusController.dispose();
    super.dispose();
  }
}

// Post type configuration
class _PostType {
  final String label;
  final IconData icon;
  final Color color;

  const _PostType({
    required this.label,
    required this.icon,
    required this.color,
  });
}

// Stylus custom painter (matches your image, tilted)
class _PostCard extends StatelessWidget {
  final dynamic post;
  final VoidCallback? onDeleted;

  const _PostCard({required this.post, this.onDeleted});

  @override
  Widget build(BuildContext context) {
    final type = post['type'] ?? 'text';
    final author = post['profiles']?['username'] ?? 'Unknown';

    switch (type) {
      case 'quote':
        return _QuotePostCard(post: post, author: author, onDeleted: onDeleted);
      case 'news':
        return _NewsPostCard(post: post, author: author, onDeleted: onDeleted);
      case 'poll':
        return _PollPostCard(post: post, author: author, onDeleted: onDeleted);
      case 'event':
        return _EventPostCard(post: post, author: author, onDeleted: onDeleted);
      case 'article':
        return _ArticlePostCard(post: post, author: author, onDeleted: onDeleted);
      default:
        return _DefaultPostCard(post: post, author: author, onDeleted: onDeleted);
    }
  }
}

// Quote post: "Content" — Author
class _QuotePostCard extends StatelessWidget {
  final dynamic post;
  final VoidCallback? onDeleted;
  final String author;

  const _QuotePostCard({required this.post, required this.author, this.onDeleted});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Type badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: BookNestColors.cyan.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'QUOTE',
              style: TextStyle(
                color: BookNestColors.cyan,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Quote content with quotation marks
          Text(
            '"${post['content'] ?? ''}"',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 18,
              fontStyle: FontStyle.italic,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),

          // Author attribution
          Row(
            children: [
              Container(
                width: 3,
                height: 20,
                decoration: BoxDecoration(
                  color: BookNestColors.cyan,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '— ${post['metadata']?['quote_author'] ?? author}',
                style: const TextStyle(
                  color: BookNestColors.lightTextSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (post['metadata']?['date'] != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.event_outlined,
                    size: 14, color: BookNestColors.cyan),
                const SizedBox(width: 6),
                Text(
                  post['metadata']['date'].toString(),
                  style: const TextStyle(
                    color: BookNestColors.lightTextSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),

          // Footer
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: BookNestColors.navy,
                child: Text(
                  author[0].toUpperCase(),
                  style: const TextStyle(
                    color: BookNestColors.cyan,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                author,
                style: const TextStyle(
                  color: BookNestColors.lightTextSecondary,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              _PostActionButtons(post: post),
            ],
          ),
        ],
      ),
    );
  }
}

// News post
class _NewsPostCard extends StatelessWidget {
  final dynamic post;
  final VoidCallback? onDeleted;
  final String author;

  const _NewsPostCard({required this.post, required this.author, this.onDeleted});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (post['metadata']?['image_url'] != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: CachedNetworkImage(
                imageUrl: post['metadata']['image_url'],
                width: double.infinity,
                height: 180,
                fit: BoxFit.cover,
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: BookNestColors.navy.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'NEWS',
                    style: TextStyle(
                      color: BookNestColors.navy,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  post['title'] ?? 'Untitled',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ExpandableText(
                  post['content'] ?? '',
                  collapsedLines: 3,
                  style: const TextStyle(
                    color: BookNestColors.lightTextSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                LinkPreviewCard(content: post['content']?.toString() ?? ''),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'By $author',
                      style: const TextStyle(
                        color: BookNestColors.lightTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_forward, color: BookNestColors.cyan, size: 16),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: [
                const Spacer(),
                _PostActionButtons(
                    post: post, onDeleted: onDeleted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Poll post
class _PollPostCard extends StatelessWidget {
  final dynamic post;
  final VoidCallback? onDeleted;
  final String author;

  const _PollPostCard({required this.post, required this.author, this.onDeleted});

  @override
  Widget build(BuildContext context) {
    final options = post['metadata']?['options'] ?? ['Yes', 'No'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: BookNestColors.cyan.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'POLL',
              style: TextStyle(
                color: BookNestColors.cyan,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            post['content'] ?? 'Poll question?',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...options.map<Widget>((option) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: BookNestColors.navy,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: BookNestColors.lightTextSecondary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    option,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
                  ),
                ],
              ),
            );
          }).toList(),
          const SizedBox(height: 8),
          Text(
            '$author • ${post['metadata']?['votes'] ?? 0} votes',
            style: const TextStyle(
              color: BookNestColors.lightTextSecondary,
              fontSize: 12,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: [
                const Spacer(),
                _PostActionButtons(
                    post: post, onDeleted: onDeleted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Event post
class _EventPostCard extends StatelessWidget {
  final dynamic post;
  final VoidCallback? onDeleted;
  final String author;

  const _EventPostCard({required this.post, required this.author, this.onDeleted});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: BookNestColors.navy.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'EVENT',
              style: TextStyle(
                color: BookNestColors.navy,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            post['title'] ?? 'Event',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.calendar_today, color: BookNestColors.cyan, size: 16),
              const SizedBox(width: 8),
              Text(
                post['metadata']?['date'] ?? 'TBD',
                style: const TextStyle(color: BookNestColors.lightTextSecondary, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.location_on, color: BookNestColors.cyan, size: 16),
              const SizedBox(width: 8),
              Text(
                post['metadata']?['location'] ?? 'Online',
                style: const TextStyle(color: BookNestColors.lightTextSecondary, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _showEventDetails(context, post),
              style: ElevatedButton.styleFrom(
                backgroundColor: BookNestColors.cyan,
                foregroundColor: BookNestColors.navyDeep,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('RSVP'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: [
                const Spacer(),
                _PostActionButtons(
                    post: post, onDeleted: onDeleted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Article post
class _ArticlePostCard extends StatelessWidget {
  final dynamic post;
  final VoidCallback? onDeleted;
  final String author;

  const _ArticlePostCard({required this.post, required this.author, this.onDeleted});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: BookNestColors.navy.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'ARTICLE',
              style: TextStyle(
                color: BookNestColors.navy,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            post['title'] ?? 'Untitled Article',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ExpandableText(
            post['content'] ?? '',
            collapsedLines: 4,
            style: const TextStyle(
              color: BookNestColors.lightTextSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          LinkPreviewCard(content: post['content']?.toString() ?? ''),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'By $author',
                style: const TextStyle(
                  color: BookNestColors.lightTextSecondary,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.push('/publish-details?bookId=${post['id']}'),
                child: const Text(
                  'Read',
                  style: TextStyle(color: BookNestColors.cyan),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: [
                const Spacer(),
                _PostActionButtons(
                    post: post, onDeleted: onDeleted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Default fallback post
class _DefaultPostCard extends StatelessWidget {
  final dynamic post;
  final VoidCallback? onDeleted;
  final String author;

  const _DefaultPostCard({required this.post, required this.author, this.onDeleted});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExpandableText(
            post['content'] ?? '',
            collapsedLines: 5,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface, height: 1.45),
          ),
          LinkPreviewCard(content: post['content']?.toString() ?? ''),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: [
                const Spacer(),
                _PostActionButtons(
                    post: post, onDeleted: onDeleted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Like (optimistic, local until posts sync to the cloud) + real share sheet.
class _PostActionButtons extends StatefulWidget {
  final dynamic post;
  final VoidCallback? onDeleted;
  const _PostActionButtons({required this.post, this.onDeleted});

  @override
  State<_PostActionButtons> createState() => _PostActionButtonsState();
}

class _PostActionButtonsState extends State<_PostActionButtons> {
  late bool _liked = widget.post is Map && widget.post['liked_by_me'] == true;
  late int _count = widget.post is Map
      ? ((widget.post['like_count'] as num?)?.toInt() ?? 0)
      : 0;
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    final post = widget.post;
    final id =
        post is Map && post['id'] != null ? post['id'].toString() : null;
    final target = !_liked;
    HapticFeedback.lightImpact();
    setState(() {
      _liked = target;
      _count = target ? _count + 1 : (_count > 0 ? _count - 1 : 0);
    });
    if (id == null) return; // post not synced yet — local-only like
    _busy = true;
    try {
      final fresh = await SupabaseService().setFeedLike(id, liked: target);
      if (mounted) setState(() => _count = fresh);
    } catch (error) {
      if (mounted) {
        setState(() {
          _liked = !target;
          _count = target ? (_count > 0 ? _count - 1 : 0) : _count + 1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error is WriteException
                ? error.message
                : "BookNest couldn't complete that just now — please try "
                    "again in a moment."),
          ),
        );
      }
    } finally {
      _busy = false;
    }
  }

  bool get _mine =>
      widget.post is Map &&
      widget.post['created_by']?.toString() == viewerId;

  Future<void> _deleteMyPost() async {
    final id = widget.post is Map && widget.post['id'] != null
        ? widget.post['id'].toString()
        : null;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this post?'),
        content: const Text(
            'It disappears for every reader, along with its comments, likes '
            'and reshares. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete',
                  style: TextStyle(
                      color: Color(0xFFD06A6A),
                      fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final res = await BackendApi.instance
        .call('posts.delete', {'postId': id});
    if (!mounted) return;
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'The post could not be deleted — please try again.')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post deleted.')));
    widget.onDeleted?.call();
  }

  late int _views = widget.post is Map
      ? ((widget.post['view_count'] as num?)?.toInt() ?? 0)
      : 0;
  late int _comments = widget.post is Map
      ? ((widget.post['comment_count'] as num?)?.toInt() ?? 0)
      : 0;
  late int _reshares = widget.post is Map
      ? ((widget.post['reshare_count'] as num?)?.toInt() ?? 0)
      : 0;

  void _openComments() {
    final id = widget.post is Map && widget.post['id'] != null
        ? widget.post['id'].toString()
        : null;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This post is still on this device — comments open '
              'once it syncs to the cloud.')));
      return;
    }
    showPostComments(context, postId: id, initialCount: _comments)
        .then((count) {
      if (count != null && mounted) setState(() => _comments = count);
    });
  }

  Future<void> _reshare() async {
    final id = widget.post is Map && widget.post['id'] != null
        ? widget.post['id'].toString()
        : null;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This post is still on this device — reshares open '
              'once it syncs to the cloud.')));
      return;
    }
    HapticFeedback.lightImpact();
    final res = await BackendApi.instance.call('posts.reshare',
        {'postId': id});
    if (!mounted) return;
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not reshare — please try again.')));
      return;
    }
    final already = res['already'] == true;
    final total = (res['reshareCount'] as num?)?.toInt();
    setState(() {
      if (already && _reshares > 0) _reshares -= 1;
      if (!already) _reshares += 1;
      if (total != null) _reshares = total;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(already
            ? 'You already shared this — taken back.'
            : 'Shared with your followers 🎉')));
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).hintColor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.visibility_outlined, color: muted.withOpacity(.8), size: 18),
        const SizedBox(width: 4),
        AnimatedCount(
          value: _views,
          style: TextStyle(color: muted, fontSize: 12.5),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: Icon(
            _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: _liked ? BookNestColors.cyan : muted,
            size: 20,
          ),
          tooltip: _liked ? 'Unlike' : 'Like',
          onPressed: _toggle,
        ),
        AnimatedCount(
          value: _count,
          style: TextStyle(
            color: _liked ? BookNestColors.cyan : muted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 6),
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _openComments,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mode_comment_outlined, color: muted, size: 19),
                const SizedBox(width: 4),
                AnimatedCount(
                  value: _comments,
                  style: TextStyle(color: muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _reshare,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.repeat_rounded,
                    color: muted, size: 19),
                const SizedBox(width: 4),
                AnimatedCount(
                  value: _reshares,
                  style: TextStyle(color: muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ),
        if (_mine)
          IconButton(
            icon: Icon(Icons.delete_outline_rounded,
                color: muted.withOpacity(.7), size: 18),
            tooltip: 'Delete post',
            visualDensity: VisualDensity.compact,
            onPressed: _deleteMyPost,
          )
        else
          IconButton(
            icon: Icon(Icons.flag_outlined,
                color: muted.withOpacity(.7), size: 18),
            tooltip: 'Report post',
          visualDensity: VisualDensity.compact,
          onPressed: () {
            final id = widget.post is Map && widget.post['id'] != null
                ? widget.post['id'].toString()
                : null;
            if (id == null) return;
            showReportSheet(context,
                kind: ReportTargetKind.post, targetId: id);
          },
        ),
      ],
    );
  }
}

/// The post comments sheet: read, write, count flows back to the card.
Future<int?> showPostComments(
  BuildContext context, {
  required String postId,
  required int initialCount,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _PostCommentsSheet(
      postId: postId,
      initialCount: initialCount,
    ),
  );
}

class _PostCommentsSheet extends StatefulWidget {
  final String postId;
  final int initialCount;
  const _PostCommentsSheet(
      {required this.postId, required this.initialCount});
  @override
  State<_PostCommentsSheet> createState() => _PostCommentsSheetState();
}

class _PostCommentsSheetState extends State<_PostCommentsSheet> {
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true;
  bool _sending = false;
  final _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await BackendApi.instance
        .call('posts.comments.list', {'postId': widget.postId});
    if (!mounted) return;
    setState(() {
      _comments = ((res?['comments'] as List?) ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _loading = false;
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final res = await BackendApi.instance
        .call('posts.comments.create', {'postId': widget.postId, 'text': text});
    if (!mounted) return;
    setState(() => _sending = false);
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('The comment could not be posted — please try again.')));
      return;
    }
    _input.clear();
    final comment = res['comment'];
    setState(() {
      if (comment is Map) {
        _comments = [
          Map<String, dynamic>.from(comment),
          ..._comments,
        ];
      } else {
        _comments = [
          {'text': text, 'createdAt': DateTime.now().toIso8601String(), 'mine': true},
          ..._comments,
        ];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final nameOf = (Map<String, dynamic> c) =>
        c['profiles'] is Map
            ? (c['profiles']['username']?.toString() ?? 'Reader')
            : (c['mine'] == true ? 'You' : 'Reader');
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).hintColor.withOpacity(.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Text('Comments',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface)),
            Expanded(
              child: _loading
                  ? const Center(
                      child: BookNestLoader(size: 40),
                    )
                  : _comments.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.mode_comment_outlined,
                                  size: 34,
                                  color: Theme.of(context)
                                      .hintColor
                                      .withOpacity(.5)),
                              const SizedBox(height: 10),
                              Text(
                                'Be the first to comment',
                                style: TextStyle(
                                    color: Theme.of(context).hintColor),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          itemCount: _comments.length,
                          itemBuilder: (context, i) {
                            final c = _comments[i];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: dark
                                    ? Colors.white.withOpacity(.05)
                                    : BookNestColors.navyDeep.withOpacity(.04),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 11,
                                        backgroundColor:
                                            BookNestColors.navy,
                                        child: Text(
                                          nameOf(c)[0].toUpperCase(),
                                          style: const TextStyle(
                                              color: BookNestColors.cyan,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(nameOf(c),
                                          style: const TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w700)),
                                      const Spacer(),
                                      Text(
                                        c['createdAt']?.toString() ?? '',
                                        style: TextStyle(
                                            fontSize: 10.5,
                                            color: Theme.of(context)
                                                .hintColor),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(c['text']?.toString() ?? '',
                                      style: TextStyle(
                                          fontSize: 14,
                                          height: 1.35,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface)),
                                ],
                              ),
                            );
                          },
                        ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: 'Add a comment…',
                          suffixIcon: _sending
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: BookNestColors.cyan)),
                                )
                              : null,
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    IconButton(
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send_rounded,
                          color: BookNestColors.cyan),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Real event details dialog fed from the post's metadata.
void _showEventDetails(BuildContext context, dynamic post) {
  final metadata = post?['metadata'];
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: (Theme.of(dialogContext).brightness == Brightness.dark
              ? BookNestColors.darkChatBackground
              : Colors.white)
          .withOpacity(.88),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: BookNestColors.cyan.withOpacity(.3))),
      title: Text(post?['title']?.toString() ?? 'Event'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(post?['content']?.toString() ?? '',
              style: TextStyle(height: 1.4)),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.calendar_today, size: 15, color: BookNestColors.cyan),
            const SizedBox(width: 7),
            Text(metadata?['date']?.toString() ?? 'Date to be announced'),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.schedule, size: 15, color: BookNestColors.cyan),
            const SizedBox(width: 7),
            Text(metadata?['time']?.toString() ?? 'Time to be announced'),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.location_on_outlined,
                size: 15, color: BookNestColors.cyan),
            const SizedBox(width: 7),
            Expanded(child: Text(metadata?['location']?.toString() ?? 'Location to be announced')),
          ]),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close',
              style: TextStyle(color: BookNestColors.cyan)),
        ),
      ],
    ),
  );
}
