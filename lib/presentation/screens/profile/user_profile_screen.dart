import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/time_format.dart';
import '../../../services/supabase_service.dart';
import '../../components/user_avatar.dart';
import '../../../config/theme.dart';

/// Public profile of another user (`/user/:userId`).
///
/// Shows avatar, name, username, bio, gem balance, their published books and
/// recent posts, plus a "Message" button that starts (or reuses) a DM via the
/// `get_or_create_dm` RPC.
class UserProfileScreen extends StatefulWidget {
  final String userId;

  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  Map<String, dynamic>? _profile;
  final List<Map<String, dynamic>> _books = [];
  final List<Map<String, dynamic>> _posts = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profileRow = await SupabaseService()
          .client
          .from('profiles')
          .select('id, username, display_name, bio, avatar_url, gems, created_at')
          .eq('id', widget.userId)
          .maybeSingle();
      if (!mounted) return;
      if (profileRow == null) {
        setState(() {
          _isLoading = false;
          _error = 'This user could not be found.';
        });
        return;
      }
      _profile = Map<String, dynamic>.from(profileRow as Map);

      final books = await SupabaseService()
          .client
          .from('club_books')
          .select('id, title, description, created_at, views')
          .eq('added_by', widget.userId)
          .eq('moderation_status', 'approved')
          .order('created_at', ascending: false)
          .limit(30);
      final posts = await SupabaseService()
          .client
          .from('posts')
          .select('id, type, title, content, created_at')
          .eq('created_by', widget.userId)
          .order('created_at', ascending: false)
          .limit(30);
      if (!mounted) return;
      setState(() {
        _books
          ..clear()
          ..addAll(books.map((r) => Map<String, dynamic>.from(r)).toList());
        _posts
          ..clear()
          ..addAll(posts.map((r) => Map<String, dynamic>.from(r)).toList());
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Could not load this profile: $e';
      });
    }
  }

  Future<void> _startDm() async {
    try {
      final conversationId = await SupabaseService()
          .client
          .rpc('get_or_create_dm', params: {'other_user': widget.userId});
      if (!mounted) return;
      context.push('/dm/$conversationId');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start a conversation: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NOC.bg,
      appBar: AppBar(
        backgroundColor: NOC.surface,
        elevation: 1,
        leading: IconButton(
          icon:  Icon(Icons.arrow_back, color: NOC.text),
          onPressed: () => context.pop(),
        ),
        title:  Text('Profile', style: TextStyle(color: NOC.text, fontSize: 18)),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return  Center(child: CircularProgressIndicator(color: NOC.accent));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
               Icon(Icons.error_outline, size: 56, color: NOC.textFaint),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center, style:  TextStyle(color: NOC.textMuted)),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final profile = _profile!;
    final displayName = profile['display_name']?.toString() ?? 'Reader';
    final username = profile['username']?.toString() ?? 'reader';
    final bio = profile['bio']?.toString() ?? '';
    final gems = (profile['gems'] as num?)?.toInt() ?? 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: [
        const SizedBox(height: 8),
        Center(
          child: UserAvatar(
            imageUrl: profile['avatar_url']?.toString(),
            name: displayName,
            radius: 44,
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            displayName,
            style:  TextStyle(color: NOC.text, fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            '@$username',
            style:  TextStyle(color: NOC.textMuted, fontSize: 14),
          ),
        ),
        if (bio.isNotEmpty) ...[
          const SizedBox(height: 10),
          Center(
            child: Text(
              bio,
              textAlign: TextAlign.center,
              style:  TextStyle(color: NOC.textMuted, fontSize: 14, height: 1.5),
            ),
          ),
        ],
        if (profile['created_at'] != null) ...[
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Joined ${formatFullDate(profile['created_at'])}',
              style:  TextStyle(color: NOC.textFaint, fontSize: 12),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: NOC.surfaceAlt,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: NOC.border),
                ),
                child: Column(
                  children: [
                    Text('${_books.length}', style:  TextStyle(color: NOC.text, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                     Text('Books', style: TextStyle(color: NOC.textMuted, fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: NOC.surfaceAlt,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: NOC.border),
                ),
                child: Column(
                  children: [
                    Text('${_posts.length}', style:  TextStyle(color: NOC.text, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                     Text('Posts', style: TextStyle(color: NOC.textMuted, fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: NOC.surfaceAlt,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: NOC.border),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                         Icon(Icons.diamond, size: 14, color: NOC.gold),
                        const SizedBox(width: 4),
                        Text('$gems', style:  TextStyle(color: NOC.gold, fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                     Text('Gems', style: TextStyle(color: NOC.textMuted, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _startDm,
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Message'),
          ),
        ),
        const SizedBox(height: 28),
         Text('Books', style: TextStyle(color: NOC.text, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        if (_books.isEmpty)
           Text('No published books yet.', style: TextStyle(color: NOC.textMuted, fontSize: 13))
        else
          ..._books.map((book) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: NOC.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: NOC.border),
              ),
              child: InkWell(
                onTap: () => context.push('/publish-details?bookId=${book['id']}'),
                borderRadius: BorderRadius.circular(10),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: NOC.surfaceAlt,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child:  Icon(Icons.menu_book, color: NOC.accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            book['title']?.toString() ?? 'Untitled',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:  TextStyle(color: NOC.text, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${formatFullDate(book['created_at'])} · ${book['views'] ?? 0} views',
                            style:  TextStyle(color: NOC.textFaint, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 24),
         Text('Recent Posts', style: TextStyle(color: NOC.text, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        if (_posts.isEmpty)
           Text('No posts yet.', style: TextStyle(color: NOC.textMuted, fontSize: 13))
        else
          ..._posts.map((post) {
            final preview = (post['content']?.toString() ?? '').isNotEmpty
                ? post['content'].toString()
                : (post['title']?.toString() ?? '');
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: NOC.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: NOC.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: NOC.accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      (post['type']?.toString() ?? 'text').toUpperCase(),
                      style:  TextStyle(color: NOC.accent, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:  TextStyle(color: NOC.textMuted, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    formatFullDate(post['created_at']),
                    style:  TextStyle(color: NOC.textFaint, fontSize: 11),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
