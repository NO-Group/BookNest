import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/supabase_service.dart';
import '../../config/theme.dart';

/// Shared "Groups & chat" section for club / organization / school detail
/// screens. Lists the entity's groups (default Chat group + any created ones)
/// and opens the group chat on tap. The entity owner can create new groups.
///
/// Communities use the richer Groups/Library/Members tabs instead
/// (see `CommunityDetailScreen`).
class EntityGroupsPanel extends StatefulWidget {
  final String entityType; // 'club' | 'organization' | 'school'
  final String entityId;

  const EntityGroupsPanel({
    super.key,
    required this.entityType,
    required this.entityId,
  });

  @override
  State<EntityGroupsPanel> createState() => _EntityGroupsPanelState();
}

class _EntityGroupsPanelState extends State<EntityGroupsPanel> {
  List<Map<String, dynamic>> _groups = [];
  bool _isLoading = true;
  bool _isMemberOrOwner = false;
  String? _myId;

  @override
  void initState() {
    super.initState();
    _myId = SupabaseService().auth.currentUser?.id;
    _load();
  }

  Future<void> _load() async {
    try {
      final supabase = SupabaseService().client;
      final groups = await supabase
          .from('groups')
          .select('*')
          .eq('entity_type', widget.entityType)
          .eq('entity_id', widget.entityId)
          .order('is_default', ascending: false);

      // Are we a member/owner? RLS returns no rows otherwise, so compare ids.
      final memberTable = '${widget.entityType}_members';
      final idColumn = widget.entityType == 'club'
          ? 'club_id'
          : widget.entityType == 'organization'
              ? 'organization_id'
              : 'school_id';
      bool isMember = false;
      if (_myId != null) {
        final row = await supabase
            .from(memberTable)
            .select('user_id')
            .eq(idColumn, widget.entityId)
            .eq('user_id', _myId!)
            .maybeSingle();
        isMember = row != null;
      }

      if (!mounted) return;
      setState(() {
        _groups = groups.map((r) => Map<String, dynamic>.from(r)).toList();
        _isMemberOrOwner = isMember;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createGroup() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: NOC.surfaceAlt,
        title:  Text('New group', style: TextStyle(color: NOC.text)),
        content: TextField(
          controller: controller,
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(dialogContext);
              try {
                await SupabaseService().client.rpc(
                      'create_group',
                      params: {
                        'e_type': widget.entityType,
                        'e_id': widget.entityId,
                        'group_name': name,
                        'g_type': 'regular',
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
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return  Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: CircularProgressIndicator(color: NOC.accent),
        ),
      );
    }

    if (!_isMemberOrOwner) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: NOC.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NOC.border),
        ),
        child:  Column(
          children: [
            Icon(Icons.lock_outline, color: NOC.textFaint, size: 32),
            SizedBox(height: 10),
            Text(
              'Join to chat with this group',
              style: TextStyle(color: NOC.textMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Row(
            children: [
               Text(
                'Groups & Chat',
                style: TextStyle(
                  color: NOC.text,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon:  Icon(Icons.add, color: NOC.accent),
                tooltip: 'New group (owner)',
                onPressed: _createGroup,
              ),
            ],
          ),
        ),
        if (_groups.isEmpty)
           Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'No groups yet.',
              style: TextStyle(color: NOC.textMuted),
            ),
          )
        else
          ..._groups.map((group) {
            final isAnnouncement = group['group_type'] == 'announcement';
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
              decoration: BoxDecoration(
                color: NOC.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: NOC.border),
              ),
              child: ListTile(
                onTap: () => context.push('/group-chat/${group['conversation_id']}'),
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: (isAnnouncement ? NOC.accent : NOC.hot).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isAnnouncement ? Icons.campaign : Icons.chat_bubble_outline,
                    color: isAnnouncement ? NOC.accent : NOC.hot,
                    size: 20,
                  ),
                ),
                title: Text(
                  group['name']?.toString() ?? 'Group',
                  style:  TextStyle(color: NOC.text, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  isAnnouncement ? 'Announcements · admins only' : 'Chat group',
                  style:  TextStyle(color: NOC.textMuted, fontSize: 12),
                ),
                trailing:  Icon(Icons.chevron_right, color: NOC.textFaint),
              ),
            );
          }),
      ],
    );
  }
}
