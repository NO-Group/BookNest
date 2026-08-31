// lib/presentation/screens/feed/feed_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../services/supabase_service.dart';

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
    'Reel',
    'Article',
  ];

  final List<_PostType> _postTypes = const [
    _PostType(label: 'Quote', icon: Icons.format_quote, color: Color(0xFF00D4FF)),
    _PostType(label: 'News', icon: Icons.newspaper, color: Color(0xFFFF6A00)),
    _PostType(label: 'Poll', icon: Icons.poll, color: Color(0xFF00D4FF)),
    _PostType(label: 'Event', icon: Icons.event, color: Color(0xFFFF6A00)),
    _PostType(label: 'Reel', icon: Icons.videocam, color: Color(0xFF00D4FF)),
    _PostType(label: 'Article', icon: Icons.article, color: Color(0xFFFF6A00)),
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
    try {
      final response = await SupabaseService()
          .client
          .from('posts')
          .select('*, profiles(username, avatar_url)')
          .order('created_at', ascending: false);

      setState(() {
        _posts = response;
        _filteredPosts = response;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
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

  void _onPostTypeTap(_PostType type) {
    _toggleStylus();
    switch (type.label) {
      case 'Quote':
        context.push('/create/quote');
        break;
      case 'News':
        context.push('/create/news');
        break;
      case 'Poll':
        context.push('/create/poll');
        break;
      case 'Event':
        context.push('/create/event');
        break;
      case 'Reel':
        context.push('/create/reel');
        break;
      case 'Article':
        context.push('/editor');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
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
                      const Text(
                        'Feed',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.search, color: Colors.white),
                            onPressed: () {},
                          ),
                          IconButton(
                            icon: const Icon(Icons.notifications_none, color: Colors.white),
                            onPressed: () {},
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
                                  ? const Color(0xFF00D4FF)
                                  : const Color(0xFF1F1F1F),
                              borderRadius: BorderRadius.circular(20),
                              border: isActive
                                  ? null
                                  : Border.all(color: const Color(0xFF222222)),
                            ),
                            child: Text(
                              filter,
                              style: TextStyle(
                                color: isActive ? const Color(0xFF0A0A0A) : Colors.white,
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
                      ? const Center(
                          child: CircularProgressIndicator(color: Color(0xFF00D4FF)),
                        )
                      : _filteredPosts.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              itemCount: _filteredPosts.length,
                              itemBuilder: (context, index) {
                                return _PostCard(post: _filteredPosts[index]);
                              },
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
                    height: _isStylusOpen ? (_postTypes.length * 64.0) : 0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: _postTypes.map((type) {
                        return _buildPostTypeButton(type);
                      }).toList(),
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
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00D4FF),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00D4FF).withOpacity(0.3),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Transform.rotate(
                            angle: -0.785, // -45 degrees to tilt the stylus
                            child: CustomPaint(
                              size: const Size(28, 28),
                              painter: _StylusPainter(),
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
    return GestureDetector(
      onTap: () => _onPostTypeTap(type),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1F1F1F),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF222222)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(type.icon, color: type.color, size: 20),
            const SizedBox(width: 8),
            Text(
              type.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.feed_outlined,
            size: 64,
            color: Color(0xFF444444),
          ),
          SizedBox(height: 16),
          Text(
            'No posts yet',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Tap the stylus to create your first post',
            style: TextStyle(
              color: Color(0xFF888888),
              fontSize: 14,
            ),
          ),
        ],
      ),
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
class _StylusPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final width = size.width;
    final height = size.height;

    // Stylus body (tapered rectangle)
    final bodyPath = Path()
      ..moveTo(width * 0.45, height * 0.05)
      ..lineTo(width * 0.55, height * 0.05)
      ..lineTo(width * 0.6, height * 0.65)
      ..lineTo(width * 0.4, height * 0.65)
      ..close();

    // Stylus grip bands
    final band1 = Path()
      ..addRect(Rect.fromLTWH(width * 0.38, height * 0.62, width * 0.24, height * 0.04));

    final band2 = Path()
      ..addRect(Rect.fromLTWH(width * 0.38, height * 0.67, width * 0.24, height * 0.04));

    // Nib (pointed tip)
    final nibPath = Path()
      ..moveTo(width * 0.4, height * 0.72)
      ..lineTo(width * 0.6, height * 0.72)
      ..lineTo(width * 0.55, height * 0.88)
      ..lineTo(width * 0.5, height * 0.95)
      ..lineTo(width * 0.45, height * 0.88)
      ..close();

    // Nib hole
    final holePaint = Paint()
      ..color = const Color(0xFF00D4FF)
      ..style = PaintingStyle.fill;

    canvas.drawPath(bodyPath, paint);
    canvas.drawPath(band1, paint);
    canvas.drawPath(band2, paint);
    canvas.drawPath(nibPath, paint);
    canvas.drawCircle(
      Offset(width * 0.5, height * 0.82),
      width * 0.06,
      holePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Post card widget (renders different types)
class _PostCard extends StatelessWidget {
  final dynamic post;

  const _PostCard({required this.post});

  @override
  Widget build(BuildContext context) {
    final type = post['type'] ?? 'text';
    final author = post['profiles']?['username'] ?? 'Unknown';

    switch (type) {
      case 'quote':
        return _QuotePostCard(post: post, author: author);
      case 'news':
        return _NewsPostCard(post: post, author: author);
      case 'poll':
        return _PollPostCard(post: post, author: author);
      case 'event':
        return _EventPostCard(post: post, author: author);
      case 'reel':
        return _ReelPostCard(post: post, author: author);
      case 'article':
        return _ArticlePostCard(post: post, author: author);
      default:
        return _DefaultPostCard(post: post, author: author);
    }
  }
}

// Quote post: "Content" — Author
class _QuotePostCard extends StatelessWidget {
  final dynamic post;
  final String author;

  const _QuotePostCard({required this.post, required this.author});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1F1F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF222222)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Type badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF00D4FF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'QUOTE',
              style: TextStyle(
                color: Color(0xFF00D4FF),
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
            style: const TextStyle(
              color: Colors.white,
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
                  color: const Color(0xFF00D4FF),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '— ${post['metadata']?['quote_author'] ?? author}',
                style: const TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Footer
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFF2A2A2A),
                child: Text(
                  author[0].toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF00D4FF),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                author,
                style: const TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.favorite_border, color: Color(0xFF888888), size: 20),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.share_outlined, color: Color(0xFF888888), size: 20),
                onPressed: () {},
              ),
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
  final String author;

  const _NewsPostCard({required this.post, required this.author});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1F1F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF222222)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (post['metadata']?['image_url'] != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Image.network(
                post['metadata']['image_url'],
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
                    color: const Color(0xFFFF6A00).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'NEWS',
                    style: TextStyle(
                      color: Color(0xFFFF6A00),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  post['title'] ?? 'Untitled',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  post['content'] ?? '',
                  style: const TextStyle(
                    color: Color(0xFF888888),
                    fontSize: 14,
                    height: 1.5,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'By $author',
                      style: const TextStyle(
                        color: Color(0xFF888888),
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_forward, color: Color(0xFF00D4FF), size: 16),
                  ],
                ),
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
  final String author;

  const _PollPostCard({required this.post, required this.author});

  @override
  Widget build(BuildContext context) {
    final options = post['metadata']?['options'] ?? ['Yes', 'No'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1F1F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF222222)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF00D4FF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'POLL',
              style: TextStyle(
                color: Color(0xFF00D4FF),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            post['content'] ?? 'Poll question?',
            style: const TextStyle(
              color: Colors.white,
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
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF222222)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF888888)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    option,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            );
          }).toList(),
          const SizedBox(height: 8),
          Text(
            '$author • ${post['metadata']?['votes'] ?? 0} votes',
            style: const TextStyle(
              color: Color(0xFF888888),
              fontSize: 12,
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
  final String author;

  const _EventPostCard({required this.post, required this.author});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1F1F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF222222)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6A00).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'EVENT',
              style: TextStyle(
                color: Color(0xFFFF6A00),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            post['title'] ?? 'Event',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.calendar_today, color: Color(0xFF00D4FF), size: 16),
              const SizedBox(width: 8),
              Text(
                post['metadata']?['date'] ?? 'TBD',
                style: const TextStyle(color: Color(0xFF888888), fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.location_on, color: Color(0xFF00D4FF), size: 16),
              const SizedBox(width: 8),
              Text(
                post['metadata']?['location'] ?? 'Online',
                style: const TextStyle(color: Color(0xFF888888), fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00D4FF),
                foregroundColor: const Color(0xFF0A0A0A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('RSVP'),
            ),
          ),
        ],
      ),
    );
  }
}

// Reel post (video thumbnail)
class _ReelPostCard extends StatelessWidget {
  final dynamic post;
  final String author;

  const _ReelPostCard({required this.post, required this.author});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1F1F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF222222)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                height: 240,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  image: post['metadata']?['thumbnail_url'] != null
                      ? DecorationImage(
                          image: NetworkImage(post['metadata']['thumbnail_url']),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: post['metadata']?['thumbnail_url'] == null
                    ? const Center(
                        child: Icon(
                          Icons.videocam,
                          size: 48,
                          color: Color(0xFF444444),
                        ),
                      )
                    : null,
              ),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFF00D4FF).withOpacity(0.9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              // Duration badge
              Positioned(
                bottom: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    post['metadata']?['duration'] ?? '0:00',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post['title'] ?? 'Untitled Reel',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$author • ${post['metadata']?['views'] ?? 0} views',
                  style: const TextStyle(
                    color: Color(0xFF888888),
                    fontSize: 12,
                  ),
                ),
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
  final String author;

  const _ArticlePostCard({required this.post, required this.author});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1F1F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF222222)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6A00).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'ARTICLE',
              style: TextStyle(
                color: Color(0xFFFF6A00),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            post['title'] ?? 'Untitled Article',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            post['content'] ?? '',
            style: const TextStyle(
              color: Color(0xFF888888),
              fontSize: 14,
              height: 1.5,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'By $author',
                style: const TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.push('/publish-details?bookId=${post['id']}'),
                child: const Text(
                  'Read',
                  style: TextStyle(color: Color(0xFF00D4FF)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Default fallback post
class _DefaultPostCard extends StatelessWidget {
  final dynamic post;
  final String author;

  const _DefaultPostCard({required this.post, required this.author});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1F1F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF222222)),
      ),
      child: Text(
        post['content'] ?? '',
        style: const TextStyle(color: Colors.white),
      ),
    );
  }
}