import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/time_format.dart';
import '../../../services/supabase_service.dart';
import '../../components/user_avatar.dart';
import '../../../config/theme.dart';

/// Group profile screen (`/group/:groupId`).
///
/// Shows the group's name/type, its entity (e.g. the community it belongs to),
/// and its member list with roles. Owners/Admins can promote members to admin,
/// demote admins back to member, or remove regular members (never the owner).
class GroupProfileScreen extends StatefulWidget {
  final String groupId;

  const GroupProfileScreen({super.key, required this.groupId});

  @override
  State<GroupProfileScreen> createState() => _GroupProfileScreenState();
}

class _GroupProfileScreenState extends State<GroupProfileScreen> {
  Map<String, dynamic>? _group;
  List<Map<String, dynamic>> _members = [];
  String? _entityName;
  bool _isLoading = true;
  String? _error;
  String? _myId;
  String? _myRole;

  @override
  void initState() {
    super.initState();
    _myId = SupabaseService().auth.currentUser?.id;
    _load();
  }

  Future<void> _load() async {
    try {
      final groupRow = await SupabaseService()
          .client
          .from('groups')
          .select('*')
          .eq('id', widget.groupId)
          .maybeSingle();
      if (!mounted) return;
      if (groupRow == null) {
        setState(() {
          _isLoading = false;
          _error = 'This group no longer exists.';
        });
        return;
      }
      _group = Map<String, dynamic>.from(groupRow as Map);

      final members = await SupabaseService()
          .client
          .from('group_members')
          .select('id, user_id, role, profiles(id, username, display_name, avatar_url)')
          .eq('group_id', widget.groupId)
          .order('joined_at', ascending: true);
      if (!mounted) return;

      for (final row in members) {
        final map = Map<String, dynamic>.from(row as Map);
        if (map['user_id']?.toString() == _myId) {
          _myRole = map['role']?.toString();
        }
      }

      _members = members
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

      // Entity display name (community/club/...)
      String? entityName;
      try {
        final entityTable = _group!['entity_type'].toString();
        final entityId = _group!['entity_id'].toString();
        final row = await SupabaseService()
            .client
            .from(entityTable)
            .select('name')
            .eq('id', entityId)
            .maybeSingle();
        entityName = row?['name']?.toString();
      } catch (_) {
        entityName = null;
      }

      setState(() {
        _entityName = entityName;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Could not load this group: $e';
      });
    }
  }

  bool get _canManage {
    return _myRole == 'owner' || _myRole == 'admin';
  }

  String _memberName(Map<String, dynamic> member) {
    final profile = member['profiles'];
    final displayName = profile?['display_name']?.toString();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    return profile?['username']?.toString() ?? 'Unknown';
  }

  Future<void> _changeRole(Map<String, dynamic> member, String newRole) async {
    try {
      await SupabaseService()
          .client
          .from('group_members')
          .update({'role': newRole})
          .eq('id', member['id']);
      if (!mounted) return;
      setState(() => _load());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update member: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _removeMember(Map<String, dynamic> member) async {
    try {
      await SupabaseService()
          .client
          .from('group_members')
          .delete()
          .eq('id', member['id']);
      if (!mounted) return;
      setState(() => _load());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove member: $e'), backgroundColor: Colors.redAccent),
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
        title:  Text('Group', style: TextStyle(color: NOC.text, fontSize: 18)),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return  Center(
        child: CircularProgressIndicator(color: NOC.accent),
      );
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

    final group = _group!;
    final isAnnouncement = group['group_type'] == 'announcement';

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 8),
        Center(
          child: UserAvatar(
            imageUrl: group['avatar_url']?.toString(),
            name: group['name']?.toString() ?? 'Group',
            radius: 40,
            accentColor: NOC.hot,
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            group['name']?.toString() ?? 'Group',
            style:  TextStyle(
              color: NOC.text,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isAnnouncement
                  ? NOC.accent.withOpacity(0.12)
                  : NOC.hot.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isAnnouncement ? 'ANNOUNCEMENTS' : 'CHAT GROUP',
              style: TextStyle(
                color: isAnnouncement ? NOC.accent : NOC.hot,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
        if (_entityName != null) ...[
          const SizedBox(height: 6),
          Center(
            child: Text(
              'in $_entityName',
              style:  TextStyle(color: NOC.textMuted, fontSize: 13),
            ),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: () => context.push('/group-chat/${group['conversation_id']}'),
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Open chat'),
          ),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
             Text(
              'Members',
              style: TextStyle(color: NOC.text, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Text(
              '${_members.length}',
              style:  TextStyle(color: NOC.textMuted, fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._members.map((member) => _buildMemberTile(member)),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildMemberTile(Map<String, dynamic> member) {
    final role = member['role']?.toString() ?? 'member';
    final name = _memberName(member);
    final isMe = member['user_id']?.toString() == _myId;
    final profile = member['profiles'];

    Color roleColor;
    String roleLabel;
    switch (role) {
      case 'owner':
        roleColor = NOC.gold;
        roleLabel = 'Owner';
        break;
      case 'admin':
        roleColor = NOC.accent;
        roleLabel = 'Admin';
        break;
      default:
        roleColor = NOC.textMuted;
        roleLabel = 'Member';
    }

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
            onTap: () => context.push('/user/${member['user_id']}'),
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
                        isMe ? '$name (you)' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:  TextStyle(
                          color: NOC.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: roleColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        roleLabel,
                        style: TextStyle(
                          color: roleColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '@${profile?['username'] ?? ''}',
                  style:  TextStyle(color: NOC.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (_canManage && role != 'owner') ...[
            PopupMenuButton<String>(
              icon:  Icon(Icons.more_vert, color: NOC.textMuted),
              color: NOC.surfaceAlt,
              onSelected: (value) {
                switch (value) {
                  case 'make_admin':
                    _changeRole(member, 'admin');
                    break;
                  case 'make_member':
                    _changeRole(member, 'member');
                    break;
                  case 'remove':
                    _removeMember(member);
                    break;
                }
              },
              itemBuilder: (context) => [
                if (role == 'member')
                  const PopupMenuItem(value: 'make_admin', child: Text('Make admin'))
                else
                  const PopupMenuItem(value: 'make_member', child: Text('Remove admin')),
                const PopupMenuItem(
                  value: 'remove',
                  child: Text('Remove from group', style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
