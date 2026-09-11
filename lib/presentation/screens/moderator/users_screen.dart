import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../components/booknest_ui.dart';

/// Every reader on BookNest, with the levers: suspend for a stretch,
/// ban outright, or lift it and welcome them back. All enforced at the
/// identity layer (Supabase auth) and mirrored in the moderation store.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  bool _busy = false;
  int _page = 1;
  bool _moreExist = false;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400 &&
          !_loading &&
          _moreExist) {
        _page += 1;
        _load(append: true);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    if (!append) setState(() => _loading = true);
    final res = await BackendApi.instance.adminUsersList(page: _page);
    if (!mounted) return;
    final rows = ((res?['users'] as List?) ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    setState(() {
      _users = append ? [..._users, ...rows] : rows;
      _moreExist = rows.length >= 100;
      _loading = false;
    });
  }

  String _nameOf(Map<String, dynamic> u) {
    final display = u['displayName']?.toString() ?? '';
    if (display.isNotEmpty) return display;
    final username = u['username']?.toString() ?? '';
    if (username.isNotEmpty) return '@$username';
    final email = u['email']?.toString() ?? '';
    return email.isEmpty ? 'Reader' : email.split('@').first;
  }

  String _banLabel(String? banned) => switch (banned) {
        'ban' => 'Banned',
        'suspend' => 'Suspended',
        _ => '',
      };

  Future<void> _act(Map<String, dynamic> u) async {
    final banned = u['banned']?.toString();
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 6),
          ListTile(
            leading: const Icon(Icons.timer_outlined,
                color: BookNestColors.cyan),
            title: const Text('Suspend…'),
            subtitle: const Text('Temporary — 1 to 365 days'),
            onTap: () => Navigator.pop(sheetContext, 'suspend'),
          ),
          if (banned != 'ban')
            ListTile(
              leading:
                  const Icon(Icons.block_rounded, color: Color(0xFFD06A6A)),
              title: const Text('Ban permanently'),
              subtitle: const Text(
                  'They lose their sessions and cannot sign back in'),
              onTap: () => Navigator.pop(sheetContext, 'ban'),
            ),
          if (banned != null)
            ListTile(
              leading: const Icon(Icons.lock_open_rounded,
                  color: BookNestColors.cyan),
              title: Text('Lift the ${_banLabel(banned).toLowerCase()}'),
              onTap: () => Navigator.pop(sheetContext, 'lift'),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'suspend') await _suspend(u);
    if (action == 'ban') await _punish(u, mode: 'ban');
    if (action == 'lift') await _lift(u);
  }

  Future<void> _suspend(Map<String, dynamic> u) async {
    final daysCtrl = TextEditingController(text: '7');
    final reasonCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Suspend ${_nameOf(u)}?',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: daysCtrl,
            keyboardType: TextInputType.number,
            maxLength: 3,
            decoration: const InputDecoration(
                labelText: 'Days (1–365)', counterText: ''),
          ),
          TextField(
            controller: reasonCtrl,
            maxLength: 300,
            decoration: const InputDecoration(
                labelText: 'Reason (shown in your records)'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: BookNestColors.navy),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Suspend')),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    setState(() => _busy = true);
    final res = await BackendApi.instance.call('admin.ban', {
      'userId': u['id']?.toString() ?? '',
      'mode': 'suspend',
      'days': int.tryParse(daysCtrl.text.trim()) ?? 7,
      'reason': reasonCtrl.text.trim(),
    });
    if (!mounted) return;
    setState(() => _busy = false);
    _notice(res == null
        ? 'Could not suspend — try again.'
        : 'Suspension recorded and enforced at the identity layer.');
    if (res != null) _load();
  }

  Future<void> _punish(Map<String, dynamic> u, {required String mode}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Ban ${_nameOf(u)} permanently?',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        content: const Text(
            'They lose their sessions and cannot sign back in. They can '
            'only appeal by writing to n.ogroup@yahoo.com.',
            style: TextStyle(fontSize: 13.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB3261E)),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Ban')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final res = await BackendApi.instance.call('admin.ban', {
      'userId': u['id']?.toString() ?? '',
      'mode': 'ban',
      'reason': 'Permanent ban by the moderator',
    });
    if (!mounted) return;
    setState(() => _busy = false);
    _notice(res == null ? 'Could not ban — try again.' : 'Banned, everywhere.');
    if (res != null) _load();
  }

  Future<void> _lift(Map<String, dynamic> u) async {
    setState(() => _busy = true);
    final res = await BackendApi.instance.call('admin.unban', {
      'userId': u['id']?.toString() ?? '',
    });
    if (!mounted) return;
    setState(() => _busy = false);
    _notice(res == null
        ? 'Could not lift it — try again.'
        : 'Punishment lifted — they can read again.');
    if (res != null) _load();
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      appBar: GlassAppBar(title: 'All readers'),
      body: _loading && _users.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: BookNestColors.cyan))
          : RefreshIndicator(
              color: BookNestColors.cyan,
              onRefresh: () async {
                _page = 1;
                await _load();
              },
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                itemCount: _users.length + (_moreExist ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i >= _users.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Center(
                          child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: BookNestColors.cyan))),
                    );
                  }
                  final u = _users[i];
                  final banned = u['banned']?.toString();
                  final banLabel = _banLabel(banned);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassPanel(
                      radius: 18,
                      child: InkWell(
                        onTap: _busy ? null : () => _act(u),
                        borderRadius: BorderRadius.circular(18),
                        child: Padding(
                          padding: const EdgeInsets.all(13),
                          child: Row(children: [
                            CircleAvatar(
                              radius: 19,
                              backgroundColor: BookNestColors.navy,
                              child: Text(
                                _nameOf(u).characters.isEmpty
                                    ? '?'
                                    : _nameOf(u).characters.first
                                        .toUpperCase(),
                                style: const TextStyle(
                                    color: BookNestColors.cyan,
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(_nameOf(u),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w800,
                                            color: onSurface)),
                                    const SizedBox(height: 2),
                                    Text(
                                        u['email']?.toString() ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            color: onSurface
                                                .withOpacity(.55))),
                                    if ((u['phone']?.toString() ?? '')
                                        .isNotEmpty)
                                      Text(
                                          u['phone'].toString(),
                                          style: TextStyle(
                                              fontSize: 10.5,
                                              color: onSurface
                                                  .withOpacity(.45))),
                                  ]),
                            ),
                            if (banLabel.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD06A6A)
                                      .withOpacity(.14),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(banLabel,
                                    style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFFD06A6A))),
                              )
                            else
                              Icon(Icons.chevron_right_rounded,
                                  size: 18,
                                  color: onSurface.withOpacity(.35)),
                          ]),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
