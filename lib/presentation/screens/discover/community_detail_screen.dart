import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/time_format.dart';
import '../../../services/supabase_service.dart';
import '../../components/user_avatar.dart';
import '../../../config/theme.dart';

/// Community profile screen (`/community/:id`).
///
/// Tabs:
/// - **Groups** — the auto-created Announcements + Chat groups and any
///   owner-created groups. Tapping one opens the group chat.
/// - **Library** — books reposted/added to the community (with Pending/Approved/
///   Draft chips). A "+" FAB expands vertically (like the Feed stylus) into
///   **Add** (pick public books — `CommunityAddBooksScreen`) and **Write**
///   (reuse the Book editor; drafts land in this community's library).
/// - **Members** — member list; users who are admins of a group show the group
///   name(s) beside their name.
///
/// The Owner (only) can create new groups via the `create_group` RPC.
class CommunityDetailScreen extends StatefulWidget {
  final String id;

  const CommunityDetailScreen({super.key, required this.id});

  @override
  State<CommunityDetailScreen> createState() => _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends State<CommunityDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  Map<String, dynamic>? _community;
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _libraryBooks = [];
  List<Map<String, dynamic>> _members = [];
  Map<String, List<String>> _adminGroupNamesByUser = {};

  bool _isMember = false;
  bool _isOwner = false;
  bool _isLoading = true;
  String? _error;
  String? _myId;

  bool _isLibraryFabOpen = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Rebuild when the tab changes so the library FAB appears/disappears.
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _myId = SupabaseService().auth.currentUser?.id;
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final supabase = SupabaseService().client;

      final communityRow = await supabase
          .from('communities')
          .select('*')
          .eq('id', widget.id)
          .maybeSingle();
      if (!mounted) return;
      if (communityRow == null) {
        setState(() {
          _isLoading = false;
          _error = 'This community could not be found.';
        });
        return;
      }
      _community = Map<String, dynamic>.from(communityRow as Map);
      final ownerId = _community!['owner_id']?.toString();
      _isOwner = ownerId != null && ownerId == _myId;

      // Membership
      if (_myId != null) {
        final membership = await supabase
            .from('community_members')
            .select('user_id')
            .eq('community_id', widget.id)
            .eq('user_id', _myId!)
            .maybeSingle();
        _isMember = membership != null;
      }

      // Groups
      final groups = await supabase
          .from('groups')
          .select('*')
          .eq('entity_type', 'community')
          .eq('entity_id', widget.id)
          .order('is_default', ascending: false);
      _groups = groups.map((r) => Map<String, dynamic>.from(r)).toList();

      // Library (reposted + community-written books)
      if (_isMember || _isOwner) {
        final books = await supabase
            .from('community_books')
            .select(
              'id, created_at, club_books(id, title, description, moderation_status, views, created_at)',
            )
            .eq('community_id', widget.id)
            .order('created_at', ascending: false);
        _libraryBooks =
            books.map((r) => Map<String, dynamic>.from(r)).toList();
      }

      // Members
      final members = await supabase
          .from('community_members')
          .select('user_id, role, profiles(id, username, display_name, avatar_url)')
          .eq('community_id', widget.id);
      _members = members.map((r) => Map<String, dynamic>.from(r)).toList();

      // Admin group names per member
      final groupIds = _groups.map((g) => g['id'].toString()).toList();
      if (groupIds.isNotEmpty) {
        final adminRows = await supabase
            .from('group_members')
            .select('user_id, groups!inner(name)')
            .eq('role', 'admin')
            .inFilter('group_id', groupIds);
        final map = <String, List<String>>{};
        for (final row in adminRows) {
          final r = Map<String, dynamic>.from(row as Map);
          final userId = r['user_id'].toString();
          final groupsList = (r['groups'] as List?) ?? [];
          final name = groupsList.isNotEmpty
              ? (groupsList.first as Map)['name']?.toString()
              : null;
          if (name != null) {
            map.putIfAbsent(userId, () => []).add(name);
          }
        }
        _adminGroupNamesByUser = map;
      }

      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Could not load this community: $e';
      });
    }
  }

  Future<void> _join() async {
    final myId = _myId;
    if (myId == null) {
      context.push('/login');
      return;
    }
    try {
      await SupabaseService().client.from('community_members').insert({
        'community_id': widget.id,
        'user_id': myId,
        'role': 'member',
      });
      if (!mounted) return;
      setState(() => _isMember = true);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not join: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _leave() async {
    final myId = _myId;
    if (myId == null) return;
    try {
      await SupabaseService()
          .client
          .from('community_members')
          .delete()
          .eq('community_id', widget.id)
          .eq('user_id', myId);
      if (!mounted) return;
      setState(() => _isMember = false);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not leave: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _createGroup() async {
    final nameController = TextEditingController();
    String groupType = 'regular';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: NOC.surfaceAlt,
          title:  Text('New group', style: TextStyle(color: NOC.text)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                style:  TextStyle(color: NOC.text),
                decoration: InputDecoration(
                  hintText: 'Group name',
                  hintStyle:  TextStyle(color: NOC.textFaint),
                  filled: true,
                  fillColor: NOC.surfaceAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('Chat group'),
                    selected: groupType == 'regular',
                    onSelected: (_) => setDialogState(() => groupType = 'regular'),
                    selectedColor: NOC.hot,
                    backgroundColor: NOC.surfaceAlt,
                    labelStyle:  TextStyle(color: NOC.text),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Announcements'),
                    selected: groupType == 'announcement',
                    onSelected: (_) => setDialogState(() => groupType = 'announcement'),
                    selectedColor: NOC.accent,
                    backgroundColor: NOC.surfaceAlt,
                    labelStyle:  TextStyle(color: NOC.text),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(dialogContext);
                try {
                  await SupabaseService().client.rpc(
                        'create_group',
                        params: {
                          'e_type': 'community',
                          'e_id': widget.id,
                          'group_name': name,
                          'g_type': groupType,
                        },
                      );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(
                      content: Text('Group created!'),
                      backgroundColor: NOC.accent,
                    ),
                  );
                  _load();
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not create group: $e'), backgroundColor: Colors.redAccent),
                  );
                }
              },
              child:  Text('Create', style: TextStyle(color: NOC.accent)),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
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
        title:  Text('Community', style: TextStyle(color: NOC.text, fontSize: 18)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: NOC.accent,
          labelColor: NOC.accent,
          unselectedLabelColor: NOC.textMuted,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Groups'),
            Tab(text: 'Library'),
            Tab(text: 'Members'),
          ],
        ),
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

    final community = _community!;
    final name = community['name']?.toString() ?? 'Community';

    return Stack(
      children: [
        Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              decoration:  BoxDecoration(
                border: Border(bottom: BorderSide(color: NOC.surface)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: NOC.surfaceAlt,
                      borderRadius: BorderRadius.circular(20),
                      image: community['cover_image_url'] != null
                          ? DecorationImage(
                              image: NetworkImage(community['cover_image_url'].toString()),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: community['cover_image_url'] == null
                        ?  Icon(Icons.account_tree, color: NOC.accent, size: 32)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style:  TextStyle(
                            color: NOC.text,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (community['is_verified'] == true) ...[
                        const SizedBox(width: 6),
                         Icon(Icons.verified, color: NOC.accent, size: 20),
                      ],
                    ],
                  ),
                  if ((community['description']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      community['description'].toString(),
                      textAlign: TextAlign.center,
                      style:  TextStyle(color: NOC.textMuted, fontSize: 13, height: 1.5),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildStat('Members', _members.length),
                      _buildStatDivider(),
                      _buildStat('Groups', _groups.length),
                      _buildStatDivider(),
                      _buildStat('Books', _libraryBooks.length),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (_isMember)
                    OutlinedButton(
                      onPressed: _leave,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: NOC.danger,
                        side:  BorderSide(color: NOC.danger),
                      ),
                      child: const Text('Leave'),
                    )
                  else
                    ElevatedButton(
                      onPressed: _join,
                      child: const Text('Join community'),
                    ),
                ],
              ),
            ),
            // Tabs content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildGroupsTab(),
                  _buildLibraryTab(),
                  _buildMembersTab(),
                ],
              ),
            ),
          ],
        ),
        // Library FAB (only on the Library tab)
        if (_tabController.index == 1 && (_isMember || _isOwner))
          Positioned(
            right: 20,
            bottom: 24,
            child: _buildLibraryFab(),
          ),
      ],
    );
  }

  Widget _buildStat(String label, int value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        children: [
          Text('$value', style:  TextStyle(color: NOC.text, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style:  TextStyle(color: NOC.textMuted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(width: 1, height: 28, color: NOC.border);
  }

  // ---------------- Groups tab ----------------
  Widget _buildGroupsTab() {
    if (!_isMember && !_isOwner) {
      return  Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Join this community to see its groups and chat.',
            textAlign: TextAlign.center,
            style: TextStyle(color: NOC.textMuted, fontSize: 14),
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: NOC.accent,
      backgroundColor: NOC.surface,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_isOwner) ...[
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: _createGroup,
                icon: const Icon(Icons.add),
                label: const Text('New group (owner only)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: NOC.accent,
                  side:  BorderSide(color: NOC.accent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_groups.isEmpty)
             Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No groups yet.', style: TextStyle(color: NOC.textMuted)),
              ),
            )
          else
            ..._groups.map(_buildGroupTile),
          const SizedBox(height: 60),
        ],
      ),
    );
  }

  Widget _buildGroupTile(Map<String, dynamic> group) {
    final isAnnouncement = group['group_type'] == 'announcement';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: NOC.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NOC.border),
      ),
      child: ListTile(
        onTap: () => context.push('/group-chat/${group['conversation_id']}'),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: (isAnnouncement ? NOC.accent : NOC.hot).withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            isAnnouncement ? Icons.campaign : Icons.chat_bubble_outline,
            color: isAnnouncement ? NOC.accent : NOC.hot,
            size: 22,
          ),
        ),
        title: Text(
          group['name']?.toString() ?? 'Group',
          style:  TextStyle(color: NOC.text, fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          isAnnouncement ? 'Announcements · admins only' : 'Chat group',
          style:  TextStyle(color: NOC.textMuted, fontSize: 12),
        ),
        trailing:  Icon(Icons.chevron_right, color: NOC.textFaint),
        onLongPress: isAnnouncement ? null : () => context.push('/group/${group['id']}'),
      ),
    );
  }

  // ---------------- Library tab ----------------
  Widget _buildLibraryTab() {
    if (!_isMember && !_isOwner) {
      return  Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Join this community to browse its library.',
            textAlign: TextAlign.center,
            style: TextStyle(color: NOC.textMuted, fontSize: 14),
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: NOC.accent,
      backgroundColor: NOC.surface,
      onRefresh: _load,
      child: _libraryBooks.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children:  [
                SizedBox(height: 120),
                Icon(Icons.menu_book_outlined, size: 64, color: NOC.textFaint),
                SizedBox(height: 16),
                Center(
                  child: Text(
                    'No books in this library yet',
                    style: TextStyle(color: NOC.text, fontSize: 17),
                  ),
                ),
                SizedBox(height: 8),
                Center(
                  child: Text(
                    'Tap + to add a public book or write one here.',
                    style: TextStyle(color: NOC.textMuted, fontSize: 13),
                  ),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              itemCount: _libraryBooks.length,
              itemBuilder: (context, index) {
                final entry = _libraryBooks[index];
                final book = entry['club_books'] is Map
                    ? Map<String, dynamic>.from(entry['club_books'] as Map)
                    : null;
                if (book == null) return const SizedBox.shrink();
                return _buildBookTile(book);
              },
            ),
    );
  }

  Widget _buildBookTile(Map<String, dynamic> book) {
    final status = book['moderation_status']?.toString() ?? 'pending';
    final isApproved = status == 'approved';
    final isDraft = status == 'draft';
    final title = book['title']?.toString() ?? 'Untitled';
    final bookId = book['id']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NOC.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NOC.border),
      ),
      child: InkWell(
        onTap: () => context.push('/publish-details?bookId=$bookId'),
        borderRadius: BorderRadius.circular(10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: NOC.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
              ),
              child:  Icon(Icons.menu_book, color: NOC.accent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
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
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isApproved
                    ? NOC.accent.withOpacity(0.12)
                    : isDraft
                        ? NOC.gold.withOpacity(0.12)
                        : NOC.hot.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isApproved ? 'Approved' : (isDraft ? 'Draft' : 'Pending'),
                style: TextStyle(
                  color: isApproved
                      ? NOC.accent
                      : isDraft
                          ? NOC.gold
                          : NOC.hot,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryFab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Expanded actions (vertical, like the Feed stylus)
        AnimatedOpacity(
          opacity: _isLibraryFabOpen ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            height: _isLibraryFabOpen ? 108 : 0,
            child: Column(
              children: [
                _buildFabAction(
                  label: 'Write',
                  icon: Icons.edit,
                  color: NOC.hot,
                  onTap: () {
                    setState(() => _isLibraryFabOpen = false);
                    context.push('/editor?communityId=${widget.id}');
                  },
                ),
                const SizedBox(height: 8),
                _buildFabAction(
                  label: 'Add',
                  icon: Icons.add,
                  color: NOC.accent,
                  onTap: () async {
                    setState(() => _isLibraryFabOpen = false);
                    await context.push('/community/${widget.id}/library/add');
                    if (mounted) _load();
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => setState(() => _isLibraryFabOpen = !_isLibraryFabOpen),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: NOC.accent,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: NOC.accent.withOpacity(0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: AnimatedRotation(
              turns: _isLibraryFabOpen ? 0.125 : 0,
              duration: const Duration(milliseconds: 300),
              child:  Icon(Icons.add, color: NOC.onAccent, size: 28),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFabAction({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: NOC.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NOC.border),
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
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(label, style:  TextStyle(color: NOC.text, fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  // ---------------- Members tab ----------------
  Widget _buildMembersTab() {
    return RefreshIndicator(
      color: NOC.accent,
      backgroundColor: NOC.surface,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_members.isEmpty)
             Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No members yet.', style: TextStyle(color: NOC.textMuted)),
              ),
            )
          else
            ..._members.map((member) {
              final profile = member['profiles'];
              final name = (profile?['display_name']?.toString() ?? '').isNotEmpty
                  ? profile!['display_name'].toString()
                  : profile?['username']?.toString() ?? 'Unknown';
              final role = member['role']?.toString() ?? 'member';
              final userId = member['user_id']?.toString() ?? '';
              final adminGroups = _adminGroupNamesByUser[userId] ?? [];

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: NOC.surfaceAlt,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: NOC.border),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => context.push('/user/$userId'),
                      child: UserAvatar(
                        imageUrl: profile?['avatar_url']?.toString(),
                        name: name,
                        radius: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:  TextStyle(color: NOC.text, fontSize: 15, fontWeight: FontWeight.w600),
                                ),
                              ),
                              if (role == 'owner') ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: NOC.gold.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child:  Text(
                                    'OWNER',
                                    style: TextStyle(color: NOC.gold, fontSize: 10, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '@${profile?['username'] ?? ''}',
                            style:  TextStyle(color: NOC.textMuted, fontSize: 12),
                          ),
                          if (adminGroups.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: adminGroups.map((g) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: NOC.accent.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'Admin · $g',
                                    style:  TextStyle(color: NOC.accent, fontSize: 10, fontWeight: FontWeight.w600),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 60),
        ],
      ),
    );
  }
}
