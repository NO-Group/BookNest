import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../../services/supabase_service.dart';
import '../../components/booknest_ui.dart';
import 'group_extras.dart';

/// The full group experience shared by organizations, communities and
/// schools: real membership, announcements, a named member directory with
/// roles, and the members-only chat. Kind-specific sections (school
/// reading lists and leaderboards) plug in via [extraSections].
class GroupBaseScreen extends StatefulWidget {
  const GroupBaseScreen({
    super.key,
    required this.kind,
    required this.groupId,
    required this.title,
    this.extraSections,
  });

  /// 'organizations' | 'communities' | 'schools'
  final String kind;
  final String groupId;
  final String title;

  /// Kind-specific sections appended under the core ones. Receives the
  /// live state (group doc, members, roles, reload).
  final List<Widget> Function(GroupBaseScreenState state)? extraSections;

  @override
  State<GroupBaseScreen> createState() => GroupBaseScreenState();
}

class GroupBaseScreenState extends State<GroupBaseScreen> {
  bool loading = true;
  String? error;
  Map<String, dynamic>? group;
  List<Map<String, dynamic>> members = [];
  Map<String, String> memberNames = {}; // userId → display name
  bool isOwner = false;
  bool isManager = false;
  bool isMember = false;
  bool _membershipBusy = false;

  String get viewerId => SupabaseService().auth.currentUser?.id ?? '';
  String get groupId => widget.groupId;
  String get kind => widget.kind;

  /// A live snapshot for the shared group sections (channels, events,
  /// rules) — they render from whatever this page currently knows.
  GroupContext get ctx => GroupContext(
        kind: kind,
        groupId: groupId,
        group: group,
        isMember: isMember,
        isManager: isManager,
        reload: reload,
      );

  bool memberIsOwner(Map<String, dynamic> m) => m['role']?.toString() == 'owner';
  bool memberIsVice(Map<String, dynamic> m) => m['role']?.toString() == 'vice';

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() {
      loading = true;
      error = null;
    });
    final res = await BackendApi.instance
        .call('groups.get', {'kind': kind, 'groupId': groupId});
    if (!mounted) return;
    if (res == null) {
      setState(() {
        loading = false;
        error = 'This $kind page could not be reached right now.';
      });
      return;
    }
    final doc = res['group'] is Map
        ? Map<String, dynamic>.from(res['group'] as Map)
        : <String, dynamic>{};
    final rows = ((res['members'] as List?) ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    await _loadNames(rows);
    if (!mounted) return;
    setState(() {
      group = doc;
      members = rows;
      isOwner = doc['ownerId']?.toString() == viewerId;
      isManager = isOwner || doc['viceModeratorId']?.toString() == viewerId;
      isMember = isOwner ||
          rows.any((m) => m['user_id']?.toString() == viewerId);
      loading = false;
    });
    _loadAnnouncements();
  }

  Future<void> _loadNames(List<Map<String, dynamic>> rows) async {
    final ids = rows
        .map((m) => m['user_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return;
    try {
      final profiles = await SupabaseService()
          .client
          .from('profiles')
          .select('id, display_name, username, avatar_url')
          .inFilter('id', ids);
      final map = <String, String>{};
      for (final row in (profiles as List)) {
        final person = Map<String, dynamic>.from(row as Map);
        final display = person['display_name']?.toString() ?? '';
        final username = person['username']?.toString() ?? '';
        map[person['id'].toString()] =
            display.isNotEmpty ? display : (username.isNotEmpty ? username : 'Reader');
      }
      memberNames = map;
    } catch (_) {
      // Directory falls back to ids; never blocks the page.
    }
  }

  String _nameOf(String userId) =>
      memberNames[userId] ??
      (userId == group?['ownerId']?.toString()
          ? (group?['ownerName']?.toString() ?? 'Owner')
          : 'Reader');

  Future<void> _toggleMembership() async {
    if (_membershipBusy) return;
    setState(() => _membershipBusy = true);
    final action = isMember ? 'groups.leave' : 'groups.join';
    final res = await BackendApi.instance
        .call(action, {'kind': kind, 'groupId': groupId});
    if (!mounted) return;
    setState(() => _membershipBusy = false);
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isMember
              ? 'Could not leave right now — try again.'
              : 'Could not join right now — try again.')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isMember ? 'You left the group.' : 'Welcome in! 🎉')));
    await reload();
  }

  Future<void> _postAnnouncement() async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    bool pinned = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (sheetContext, setDialog) => AlertDialog(
          title: const Text('New announcement'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: titleCtrl,
              maxLength: 160,
              decoration: const InputDecoration(
                  hintText: 'Title', counterText: ''),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: bodyCtrl,
              minLines: 3,
              maxLines: 6,
              maxLength: 4000,
              decoration: const InputDecoration(hintText: 'Message'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: BookNestColors.cyan,
              title: const Text('Pin to top',
                  style: TextStyle(fontSize: 13.5)),
              value: pinned,
              onChanged: (v) => setDialog(() => pinned = v),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Post',
                    style: TextStyle(
                        color: BookNestColors.cyan,
                        fontWeight: FontWeight.w800))),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final title = titleCtrl.text.trim();
    final body = bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) return;
    final res = await BackendApi.instance.call('groups.announcements.post', {
      'groupId': groupId,
      'kind': kind,
      'title': title,
      'body': body,
      'pinned': pinned,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res == null
            ? 'The announcement could not be posted — try again.'
            : 'Announcement posted to every member.')));
    if (res != null) reload();
  }

  Future<void> _deleteAnnouncement(Map<String, dynamic> a) async {
    final okToDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove announcement?'),
        content: Text('"${a['title']}" disappears for every member.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('Remove',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error))),
        ],
      ),
    );
    if (okToDelete != true) return;
    final res = await BackendApi.instance.call('groups.announcements.delete',
        {'announcementId': a['id']?.toString() ?? ''});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res == null
            ? 'Could not remove it — try again.'
            : 'Announcement removed.')));
    if (res != null) _loadAnnouncements();
  }

  List<Map<String, dynamic>> _announcements = [];

  Future<void> _loadAnnouncements() async {
    final res = await BackendApi.instance
        .call('groups.announcements.list', {'groupId': groupId});
    if (!mounted) return;
    setState(() {
      _announcements = ((res?['announcements'] as List?) ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
    });
  }

  Future<void> _manageVice(Map<String, dynamic> member) async {
    final userId = member['user_id']?.toString() ?? '';
    if (userId.isEmpty || isOwner == false) return;
    final isVice = memberIsVice(member);
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          ListTile(
            leading: Icon(isVice ? Icons.star_outline_rounded : Icons.star_rounded,
                color: BookNestColors.cyan),
            title: Text(isVice
                ? 'Remove deputy role'
                : 'Make ${_nameOf(userId)} deputy'),
            subtitle: Text(
                isVice
                    ? 'They return to a regular member.'
                    : 'Deputies can post announcements and help run the group.',
                style: const TextStyle(fontSize: 12)),
            onTap: () => Navigator.pop(sheetContext, isVice ? 'demote' : 'promote'),
          ),
          const SizedBox(height: 6),
        ]),
      ),
    );
    if (choice == null) return;
    final res = await BackendApi.instance.call('groups.vice.set', {
      'kind': kind,
      'groupId': groupId,
      'userId': choice == 'promote' ? userId : null,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res == null
            ? 'Could not update the role — try again.'
            : (choice == 'promote'
                ? '${_nameOf(userId)} is now the deputy.'
                : 'Deputy role removed.'))));
    if (res != null) reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Scaffold(
      appBar: GlassAppBar(title: group?['name']?.toString() ?? widget.title),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(color: BookNestColors.cyan))
          : error != null
              ? EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Something went wrong',
                  subtitle: error!,
                  action: TextButton.icon(
                    onPressed: reload,
                    icon: const Icon(Icons.refresh_rounded,
                        size: 18, color: BookNestColors.cyan),
                    label: const Text('Retry',
                        style: TextStyle(color: BookNestColors.cyan)),
                  ),
                )
              : RefreshIndicator(
                  color: BookNestColors.cyan,
                  onRefresh: () async {
                    _loadAnnouncements();
                    await reload();
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                    children: [
                      _headerPanel(theme, onSurface),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed:
                                _membershipBusy ? null : _toggleMembership,
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                  color: BookNestColors.cyan
                                      .withOpacity(.55)),
                              foregroundColor: BookNestColors.cyan,
                            ),
                            icon: Icon(isMember
                                ? Icons.logout_rounded
                                : Icons.group_add_rounded,
                                size: 18),
                            label: Text(isMember ? 'Leave' : 'Join',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                          ),
                        ),
                        if (isMember) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {
                                final id = group?['_id']?.toString() ?? '';
                                if (id.isEmpty) return;
                                context.push(
                                  '/club-chat?id=$id&kind=$kind'
                                  '&title=${Uri.encodeComponent(group?['name']?.toString() ?? widget.title)}',
                                );
                              },
                              style: FilledButton.styleFrom(
                                  backgroundColor: BookNestColors.navy,
                                  foregroundColor: BookNestColors.cyan),
                              icon: const Icon(Icons.forum_outlined,
                                  size: 18),
                              label: const Text('Group chat',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w800)),
                            ),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 16),
                      _announcementsPanel(theme, onSurface),
                      if (kind == 'organizations') ...[
                        const SizedBox(height: 16),
                        OrgDepartmentsSection(state: this),
                      ],
                      const SizedBox(height: 16),
                      _membersPanel(theme, onSurface),
                      ...?widget.extraSections?.call(this),
                    ],
                  ),
                ),
    );
  }

  Widget _headerPanel(ThemeData theme, Color onSurface) {
    final g = group ?? const {};
    final tags = (g['genreTags'] as List?) ?? const [];
    return GlassPanel(
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [
                    BookNestColors.navy,
                    BookNestColors.navyDeep
                  ]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  kind == 'organizations'
                      ? Icons.account_balance_rounded
                      : kind == 'schools'
                          ? Icons.school_rounded
                          : Icons.diversity_3_rounded,
                  color: BookNestColors.cyan,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(g['name']?.toString() ?? widget.title,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: onSurface)),
                      ),
                      if (g['verified'] == true) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.verified_rounded,
                            size: 17, color: BookNestColors.cyan),
                      ],
                    ]),
                    const SizedBox(height: 3),
                    Text(
                      '${members.length} member${members.length == 1 ? '' : 's'}'
                      ' · led by ${g['ownerName']?.toString() ?? 'a reader'}',
                      style: TextStyle(
                          fontSize: 12,
                          color: onSurface.withOpacity(.65)),
                    ),
                  ],
                ),
              ),
            ]),
            if ((g['description']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(g['description'].toString(),
                  style: TextStyle(
                      fontSize: 13.5, height: 1.45, color: onSurface.withOpacity(.9))),
            ],
            if (kind == 'organizations' &&
                (g['mission']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.flag_rounded,
                    size: 15, color: BookNestColors.cyan),
                const SizedBox(width: 6),
                Text('Mission',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .4,
                        color: onSurface.withOpacity(.6))),
              ]),
              const SizedBox(height: 4),
              Text(g['mission'].toString(),
                  style: TextStyle(
                      fontSize: 13, height: 1.4, color: onSurface.withOpacity(.85))),
            ],
            if (kind == 'schools' &&
                ((g['location']?.toString() ?? '').isNotEmpty ||
                    (g['website']?.toString() ?? '').isNotEmpty)) ...[
              const SizedBox(height: 10),
              if ((g['location']?.toString() ?? '').isNotEmpty)
                Row(children: [
                  const Icon(Icons.location_on_outlined,
                      size: 14, color: BookNestColors.cyan),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(g['location'].toString(),
                          style: TextStyle(
                              fontSize: 12.5,
                              color: onSurface.withOpacity(.8)))),
                ]),
              if ((g['website']?.toString() ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: [
                    const Icon(Icons.language_rounded,
                        size: 14, color: BookNestColors.cyan),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(g['website'].toString(),
                            style: TextStyle(
                                fontSize: 12.5,
                                color: onSurface.withOpacity(.8)))),
                  ]),
                ),
            ],
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: tags
                    .map((t) => TagChip(label: t.toString()))
                    .toList(),
              ),
            ],
            if (_isOverallModerator && kind == 'organizations') ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  avatar: Icon(
                      g['verified'] == true
                          ? Icons.verified_rounded
                          : Icons.new_releases_outlined,
                      size: 17,
                      color: BookNestColors.cyan),
                  label: Text(
                      g['verified'] == true
                          ? 'Verified — remove badge'
                          : 'Verify this organization',
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w700)),
                  onPressed: _toggleVerified,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool get _isOverallModerator =>
      (SupabaseService().auth.currentUser?.email ?? '')
          .toLowerCase() == 'n.ogroup@yahoo.com';

  Future<void> _toggleVerified() async {
    final g = group;
    if (g == null) return;
    final id = g['_id']?.toString() ?? '';
    if (id.isEmpty) return;
    final next = g['verified'] != true;
    final res = await BackendApi.instance
        .call('groups.verify.set', {'kind': kind, 'groupId': id, 'verified': next});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res != null
            ? (next ? 'Organization verified ✓' : 'Verification removed')
            : 'Could not update verification — try again.')));
    if (res != null) await reload();
  }

  Widget _announcementsPanel(ThemeData theme, Color onSurface) {
    final list = _announcements;
    list.sort((a, b) {
      final pin = (b['pinned'] == true ? 1 : 0) - (a['pinned'] == true ? 1 : 0);
      if (pin != 0) return pin;
      return (b['createdAt']?.toString() ?? '')
          .compareTo(a['createdAt']?.toString() ?? '');
    });
    return GlassPanel(
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.campaign_rounded,
                size: 19, color: BookNestColors.cyan),
            const SizedBox(width: 8),
            Text('Announcements',
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: onSurface)),
            const Spacer(),
            if (isManager)
              IconButton(
                onPressed: _postAnnouncement,
                icon: const Icon(Icons.add_circle_rounded,
                    color: BookNestColors.cyan, size: 24),
                tooltip: 'New announcement',
              ),
          ]),
          const SizedBox(height: 4),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                isManager
                    ? 'Post the first announcement — every member sees it.'
                    : 'No announcements yet.',
                style: TextStyle(
                    fontSize: 12.5, color: onSurface.withOpacity(.55)),
              ),
            )
          else
            for (final a in list)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      if (a['pinned'] == true)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(Icons.push_pin_rounded,
                              size: 13, color: BookNestColors.cyan),
                        ),
                      Expanded(
                        child: Text(a['title']?.toString() ?? '',
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: onSurface)),
                      ),
                      if (isManager)
                        GestureDetector(
                          onTap: () => _deleteAnnouncement(a),
                          child: Icon(Icons.delete_outline_rounded,
                              size: 16,
                              color: onSurface.withOpacity(.45)),
                        ),
                    ]),
                    const SizedBox(height: 4),
                    Text(a['body']?.toString() ?? '',
                        style: TextStyle(
                            fontSize: 12.8,
                            height: 1.4,
                            color: onSurface.withOpacity(.85))),
                  ],
                ),
              ),
        ]),
      ),
    );
  }

  Widget _membersPanel(ThemeData theme, Color onSurface) {
    return GlassPanel(
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.groups_rounded,
                size: 19, color: BookNestColors.cyan),
            const SizedBox(width: 8),
            Text('Members · ${members.length}',
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: onSurface)),
          ]),
          const SizedBox(height: 6),
          for (final m in members.take(60))
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: InkWell(
                onTap: isOwner && !memberIsOwner(m) ? () => _manageVice(m) : null,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 15,
                      backgroundColor: BookNestColors.navy,
                      child: Text(
                        _nameOf(m['user_id']?.toString() ?? '')
                            .substring(0, 1)
                            .toUpperCase(),
                        style: const TextStyle(
                            color: BookNestColors.cyan,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_nameOf(m['user_id']?.toString() ?? ''),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13.2,
                              fontWeight: FontWeight.w700,
                              color: onSurface)),
                    ),
                    if (memberIsOwner(m))
                      _roleBadge('OWNER', BookNestColors.cyan),
                    if (memberIsVice(m)) ...[
                      const SizedBox(width: 6),
                      _roleBadge('DEPUTY', BookNestColors.navy),
                    ],
                    if (isOwner && !memberIsOwner(m))
                      Icon(Icons.chevron_right_rounded,
                          size: 17, color: onSurface.withOpacity(.35)),
                  ]),
                ),
              ),
            ),
          if (members.length > 60)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('and ${members.length - 60} more…',
                  style: TextStyle(
                      fontSize: 12, color: onSurface.withOpacity(.5))),
            ),
        ]),
      ),
    );
  }

  Widget _roleBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withOpacity(.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(.4)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: .6,
              color: color)),
    );
  }
}

/// ── Organization departments ────────────────────────────────────────────
/// The internal structure of an organization: named departments any member
/// can join, each optionally led by a member the owner/deputy appoints.
class OrgDepartmentsSection extends StatefulWidget {
  const OrgDepartmentsSection({super.key, required this.state});

  final GroupBaseScreenState state;

  @override
  State<OrgDepartmentsSection> createState() => _OrgDepartmentsSectionState();
}

class _OrgDepartmentsSectionState extends State<OrgDepartmentsSection> {
  List<Map<String, dynamic>> _units = [];
  bool _loading = true;
  bool _busy = false;

  GroupBaseScreenState get _state => widget.state;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await BackendApi.instance
        .call('groups.units.list', {'kind': _state.kind, 'groupId': _state.groupId});
    if (!mounted) return;
    setState(() {
      _units = ((res?['units'] as List?) ?? const [])
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _loading = false;
    });
  }

  Future<void> _createUnit() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('New department',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(
              hintText: 'e.g. Editorial, Outreach, Design'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: BookNestColors.navy),
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    setState(() => _busy = true);
    final res = await BackendApi.instance.call('groups.units.create',
        {'kind': _state.kind, 'groupId': _state.groupId, 'name': name});
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res != null
            ? 'Department "$name" created.'
            : 'Could not create the department — try again.')));
    if (res != null) _load();
  }

  Future<void> _joinLeave(Map<String, dynamic> unit) async {
    if (_busy) return;
    final joined = _isJoined(unit);
    setState(() => _busy = true);
    final res = await BackendApi.instance.call(
        joined ? 'groups.units.leave' : 'groups.units.join',
        {'unitId': unit['id']?.toString() ?? ''});
    if (!mounted) return;
    setState(() => _busy = false);
    if (res != null) _load();
  }

  bool _isJoined(Map<String, dynamic> unit) {
    final ids = (unit['memberIds'] as List?) ?? const [];
    return ids.contains(SupabaseService().auth.currentUser?.id);
  }

  Future<void> _manageUnit(Map<String, dynamic> unit) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 6),
          ListTile(
            leading: const Icon(Icons.star_rounded, color: BookNestColors.cyan),
            title: Text((unit['leadId'] ?? '') != null &&
                    unit['leadId'].toString().isNotEmpty
                ? 'Change the lead'
                : 'Appoint a lead'),
            onTap: () => Navigator.pop(sheetContext, 'lead'),
          ),
          ListTile(
            leading:
                const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            title: const Text('Remove department'),
            onTap: () => Navigator.pop(sheetContext, 'remove'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (action == 'lead') await _pickLead(unit);
    if (action == 'remove') await _removeUnit(unit);
  }

  Future<void> _pickLead(Map<String, dynamic> unit) async {
    final members = _state.members;
    if (members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No members to appoint yet.')));
      return;
    }
    final currentLead = unit['leadId']?.toString() ?? '';
    final picked = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Appoint the lead',
            style: TextStyle(fontWeight: FontWeight.w800)),
        children: [
          for (final m in members.take(30))
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.pop(dialogContext, m['user_id']?.toString() ?? ''),
              child: Row(children: [
                Icon(
                    m['user_id']?.toString() == currentLead
                        ? Icons.star_rounded
                        : Icons.person_outline_rounded,
                    size: 19,
                    color: BookNestColors.cyan),
                const SizedBox(width: 10),
                Flexible(
                    child: Text(
                        _state._nameOf(m['user_id']?.toString() ?? ''),
                        overflow: TextOverflow.ellipsis)),
              ]),
            ),
        ],
      ),
    );
    if (picked == null || picked.isEmpty) return;
    final res = await BackendApi.instance
        .call('groups.units.setLead', {'unitId': unit['id']?.toString() ?? '', 'userId': picked});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res != null
            ? 'Lead appointed ✓'
            : 'Could not appoint the lead — try again.')));
    if (res != null) _load();
  }

  Future<void> _removeUnit(Map<String, dynamic> unit) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove department?',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text(
            '"${unit['name']?.toString() ?? 'This department'}" and its '
            'membership list will be removed.',
            style: const TextStyle(fontSize: 13.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (sure != true) return;
    final res = await BackendApi.instance.call('groups.units.remove', {
      'kind': _state.kind,
      'groupId': _state.groupId,
      'unitId': unit['id']?.toString() ?? '',
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res != null
            ? 'Department removed.'
            : 'Could not remove the department — try again.')));
    if (res != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return GlassPanel(
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.account_tree_rounded,
                size: 19, color: BookNestColors.cyan),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Departments · ${_units.length}',
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: onSurface)),
            ),
            if (_state.isManager)
              IconButton(
                tooltip: 'New department',
                icon: const Icon(Icons.add_circle_outline_rounded,
                    size: 21, color: BookNestColors.cyan),
                onPressed: _busy ? null : _createUnit,
              ),
          ]),
          const SizedBox(height: 4),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                  child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: BookNestColors.cyan))),
            )
          else if (_units.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                  _state.isManager
                      ? 'No departments yet — add teams like Editorial, '
                          'Outreach or Design.'
                      : 'No departments yet.',
                  style: TextStyle(
                      fontSize: 12.5, color: onSurface.withOpacity(.6))),
            )
          else
            for (final unit in _units)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: InkWell(
                  onTap: _state.isManager ? () => _manageUnit(unit) : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: _isJoined(unit)
                              ? BookNestColors.cyan.withOpacity(.16)
                              : BookNestColors.navy.withOpacity(.08),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(
                            _isJoined(unit)
                                ? Icons.check_rounded
                                : Icons.account_tree_outlined,
                            size: 16,
                            color: BookNestColors.cyan),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(unit['name']?.toString() ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 13.2,
                                      fontWeight: FontWeight.w700,
                                      color: onSurface)),
                              Text(
                                  '${((unit['memberCount'] as num?) ?? 0).toInt()} '
                                  'member${((unit['memberCount'] as num?) ?? 0).toInt() == 1 ? '' : 's'}'
                                  ' · lead: ${_leadLabel(unit)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: onSurface.withOpacity(.6))),
                            ]),
                      ),
                      if (_state.isMember)
                        TextButton(
                          onPressed: _busy ? null : () => _joinLeave(unit),
                          style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              minimumSize: const Size(0, 34)),
                          child: Text(_isJoined(unit) ? 'Leave' : 'Join',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: BookNestColors.cyan)),
                        ),
                      if (_isJoined(unit))
                        IconButton(
                          tooltip: 'Department chat',
                          icon: const Icon(Icons.forum_outlined,
                              size: 18, color: BookNestColors.cyan),
                          onPressed: () {
                            final groupName =
                                _state.group?['name']?.toString() ?? '';
                            final unitName = unit['name']?.toString() ?? '';
                            context.push(
                              '/club-chat?id=${_state.groupId}'
                              '&kind=${_state.kind}'
                              '&unit=${unit['id']?.toString() ?? ''}'
                              '&title=${Uri.encodeComponent('$unitName · $groupName')}',
                            );
                          },
                        ),
                    ]),
                  ),
                ),
              ),
        ]),
      ),
    );
  }

  String _leadLabel(Map<String, dynamic> unit) {
    final leadId = unit['leadId']?.toString() ?? '';
    if (leadId.isEmpty) return 'none yet';
    return _state._nameOf(leadId);
  }
}
