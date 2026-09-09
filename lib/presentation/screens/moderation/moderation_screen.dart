import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../../services/supabase_service.dart';
import '../../components/booknest_ui.dart';

/// The overall moderator's console: reports, readers, and the state of
/// the world — every power enforced server-side, every action logged.
class ModerationScreen extends StatelessWidget {
  const ModerationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('Moderation',
              style: TextStyle(fontWeight: FontWeight.w800)),
          bottom: const TabBar(
            indicatorColor: BookNestColors.cyan,
            dividerColor: Colors.transparent,
            tabs: [
              Tab(icon: Icon(Icons.flag_rounded, size: 18), text: 'Reports'),
              Tab(icon: Icon(Icons.people_rounded, size: 18), text: 'Readers'),
              Tab(icon: Icon(Icons.monitor_heart_outlined, size: 18),
                  text: 'Pulse'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ReportsTab(),
            _ReadersTab(),
            _StatsTab(),
          ],
        ),
      ),
    );
  }
}

// ── Reports ────────────────────────────────────────────────────────────────

class _ReportsTab extends StatefulWidget {
  const _ReportsTab();

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _reports = [];
  bool _loading = true;
  bool _showResolved = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await BackendApi.instance.call('moderation.list', {
      'status': _showResolved ? 'resolved' : 'open',
    });
    if (!mounted) return;
    if (res == null) {
      setState(() {
        _loading = false;
        _error = 'Only the overall moderator can open this console.';
      });
      return;
    }
    setState(() {
      _reports = ((res['reports'] as List?) ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _loading = false;
    });
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _resolve(Map<String, dynamic> report, String outcome) async {
    final res = await BackendApi.instance.call('moderation.resolve', {
      'reportId': report['id']?.toString() ?? '',
      'outcome': outcome,
    });
    if (!mounted) return;
    _notice(res == null
        ? 'Could not update the report — please try again.'
        : (outcome == 'dismissed' ? 'Report dismissed.' : 'Report resolved.'));
    _load();
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirm',
                  style: TextStyle(
                      color: Color(0xFFD06A6A),
                      fontWeight: FontWeight.bold))),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _deleteContent(Map<String, dynamic> report) async {
    final kind = report['kind']?.toString() ?? '';
    if (!await _confirm('Delete this $kind?',
        'It disappears for every reader, along with its comments, likes and '
            'views. This cannot be undone.')) {
      return;
    }
    final res = await BackendApi.instance.call('admin.deleteContent', {
      'kind': kind,
      'targetId': report['targetId']?.toString() ?? '',
    });
    if (!mounted) return;
    if (res == null) {
      _notice('Could not delete — it may already be gone.');
      return;
    }
    _notice('Content deleted.');
    _resolve(report, 'resolved');
  }

  Future<void> _deleteBook(Map<String, dynamic> report) async {
    if (!await _confirm('Delete this book?',
        'The book and every chapter vanish for every reader. This cannot '
            'be undone.')) {
      return;
    }
    final res = await BackendApi.instance.call('admin.deleteBook', {
      'bookId': report['targetId']?.toString() ?? '',
    });
    if (!mounted) return;
    _notice(res == null
        ? 'The book could not be deleted — please try again.'
        : 'Book deleted.');
    if (res != null) _resolve(report, 'resolved');
  }

  Future<void> _feature(Map<String, dynamic> report, bool on) async {
    final res = await BackendApi.instance.call('admin.feature', {
      'bookId': report['targetId']?.toString() ?? '',
      'on': on,
    });
    if (!mounted) return;
    _notice(res == null
        ? 'Could not update the spotlight — please try again.'
        : (on ? 'Book featured — it leads Discover.' : 'Spotlight removed.'));
    if (res != null) _resolve(report, 'resolved');
  }

  Future<void> _suspend(Map<String, dynamic> report) async {
    final reason = await _askReason('Suspend this reader?');
    if (reason == null) return;
    final res = await BackendApi.instance.call('admin.ban', {
      'userId': report['targetId']?.toString() ?? '',
      'reason': reason,
    });
    if (!mounted) return;
    _notice(res == null
        ? 'Could not suspend — please try again.'
        : 'Reader suspended. They can no longer post, message or publish.');
    if (res != null) _resolve(report, 'resolved');
  }

  Future<String?> _askReason(String title) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(
              labelText: 'Reason (kept in the moderation log)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Confirm',
                  style: TextStyle(
                      color: Color(0xFFD06A6A),
                      fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return _loading
        ? const Center(child: BookNestLoader(size: 56))
        : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.hintColor)),
                ),
              )
            : _reports.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified_rounded,
                            size: 46,
                            color: BookNestColors.cyan.withOpacity(.6)),
                        const SizedBox(height: 12),
                        Text(
                          _showResolved
                              ? 'Nothing resolved yet.'
                              : 'All clear — no open reports.',
                          style: TextStyle(color: theme.hintColor),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    color: BookNestColors.cyan,
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 30),
                      itemCount: _reports.length,
                      itemBuilder: (context, i) {
                        final r = _reports[i];
                        final reason = r['reason']?.toString() ?? 'other';
                        final kind = r['kind']?.toString() ?? 'post';
                        final details = r['details']?.toString() ?? '';
                        final when =
                            DateTime.tryParse(r['createdAt']?.toString() ?? '')
                                    ?.toLocal() ??
                                DateTime.now();
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            color: dark
                                ? Colors.white.withOpacity(.04)
                                : BookNestColors.navyDeep.withOpacity(.03),
                            border: Border.all(
                                color: BookNestColors.cyan.withOpacity(.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 9, vertical: 4),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      color:
                                          BookNestColors.cyan.withOpacity(.14),
                                    ),
                                    child: Text('$kind · $reason',
                                        style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w800,
                                            color: BookNestColors.cyan)),
                                  ),
                                  const Spacer(),
                                  Text(
                                      '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: theme.hintColor)),
                                ],
                              ),
                              if (details.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(details,
                                    style: TextStyle(
                                        fontSize: 13.5, height: 1.4)),
                              ],
                              const SizedBox(height: 6),
                              Text('target: ${r['targetId'] ?? '—'}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: theme.hintColor)),
                              if (!_showResolved) ...[
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (kind == 'book') ...[
                                      _ActionChip(
                                          icon: Icons.auto_awesome_rounded,
                                          label: 'Feature',
                                          onTap: () => _feature(r, true)),
                                      _ActionChip(
                                          icon: Icons.star_outline_rounded,
                                          label: 'Unfeature',
                                          onTap: () => _feature(r, false)),
                                      _ActionChip(
                                          icon: Icons.delete_forever_rounded,
                                          label: 'Delete book',
                                          danger: true,
                                          onTap: () => _deleteBook(r)),
                                    ] else ...[
                                      _ActionChip(
                                          icon: Icons.delete_forever_rounded,
                                          label: 'Delete $kind',
                                          danger: true,
                                          onTap: () => _deleteContent(r)),
                                    ],
                                    if (kind == 'user' || kind == 'message' ||
                                        kind == 'post')
                                      _ActionChip(
                                          icon: Icons.block_rounded,
                                          label: 'Suspend reader',
                                          danger: true,
                                          onTap: () => _suspend(r)),
                                    _ActionChip(
                                        icon: Icons.check_rounded,
                                        label: 'Handled',
                                        onTap: () => _resolve(r, 'resolved')),
                                    _ActionChip(
                                        icon: Icons.close_rounded,
                                        label: 'Dismiss',
                                        onTap: () => _resolve(r, 'dismissed')),
                                  ],
                                ),
                              ] else
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Chip(
                                    visualDensity: VisualDensity.compact,
                                    backgroundColor:
                                        BookNestColors.cyan.withOpacity(.12),
                                    label: Text(
                                        r['outcome']?.toString() ??
                                            'resolved',
                                        style: const TextStyle(
                                            fontSize: 11.5,
                                            color: BookNestColors.cyan)),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFD06A6A) : BookNestColors.cyan;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(.5)),
          color: color.withOpacity(.08),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: color)),
          ],
        ),
      ),
    );
  }
}

// ── Readers ────────────────────────────────────────────────────────────────

class _ReadersTab extends StatefulWidget {
  const _ReadersTab();

  @override
  State<_ReadersTab> createState() => _ReadersTabState();
}

class _ReadersTabState extends State<_ReadersTab>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _search = TextEditingController();
  List<Map<String, dynamic>> _people = [];
  Set<String> _banned = {};
  bool _searching = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadBans();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadBans() async {
    final res = await BackendApi.instance.call('admin.bans');
    final rows = res?['bans'];
    if (rows is List && mounted) {
      setState(() {
        _banned = rows
            .map((r) => r is Map ? r['userId']?.toString() ?? '' : '')
            .toSet();
      });
    }
  }

  Future<void> _runSearch(String query) async {
    final q = query.trim();
    if (q.length < 2) {
      setState(() => _people = const []);
      return;
    }
    setState(() => _searching = true);
    try {
      final rows = await SupabaseService()
          .client
          .from('profiles')
          .select('id, username, display_name, avatar_url')
          .ilike('username', '%$q%')
          .limit(20);
      _people = (rows as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
    } catch (_) {
      _people = const [];
    }
    if (mounted) setState(() => _searching = false);
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleBan(Map<String, dynamic> person) async {
    final id = person['id']?.toString() ?? '';
    final banned = _banned.contains(id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(banned
            ? 'Lift the suspension?'
            : 'Suspend @${person['username'] ?? 'reader'}?'),
        content: Text(banned
            ? 'They will be able to post, message and publish again.'
            : 'They can no longer post, message, review or publish until '
                'you lift it. Reading stays open.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(banned ? 'Lift' : 'Suspend',
                  style: TextStyle(
                      color: banned
                          ? BookNestColors.cyan
                          : const Color(0xFFD06A6A),
                      fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final res = await BackendApi.instance
        .call(banned ? 'admin.unban' : 'admin.ban', {
      'userId': id,
      if (!banned) 'reason': 'Moderator decision',
    });
    if (!mounted) return;
    if (res == null) {
      _notice('That could not be completed — please try again.');
      return;
    }
    setState(() {
      banned ? _banned.remove(id) : _banned.add(id);
    });
    _notice(banned ? 'Reader reinstated.' : 'Reader suspended.');
  }

  Future<void> _adjustGems(Map<String, dynamic> person) async {
    final controller = TextEditingController(text: '25');
    final delta = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Gems for @${person['username'] ?? 'reader'}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              labelText: 'Amount (negative to remove)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(
                  dialogContext, int.tryParse(controller.text.trim()) ?? 0),
              child: const Text('Apply',
                  style: TextStyle(
                      color: BookNestColors.cyan,
                      fontWeight: FontWeight.bold))),
        ],
      ),
    );
    controller.dispose();
    if (delta == null || delta == 0 || !mounted) return;
    final res = await BackendApi.instance.call('admin.gems', {
      'userId': person['id']?.toString() ?? '',
      'delta': delta,
      'reason': 'moderator adjustment',
    });
    if (!mounted) return;
    final balance = (res?['balance'] as num?)?.toInt();
    _notice(res == null
        ? 'Could not adjust gems — please try again.'
        : 'Done — their balance is now $balance gems.');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: TextField(
            controller: _search,
            onChanged: _runSearch,
            decoration: InputDecoration(
              hintText: 'Search readers by @username',
              prefixIcon:
                  const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: BookNestColors.cyan)),
                    )
                  : null,
            ),
          ),
        ),
        Expanded(
          child: _people.isEmpty
              ? Center(
                  child: Text(
                    _search.text.trim().length < 2
                        ? 'Find a reader to act on'
                        : 'No readers matched.',
                    style: TextStyle(color: theme.hintColor),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 30),
                  itemCount: _people.length,
                  itemBuilder: (context, i) {
                    final person = _people[i];
                    final id = person['id']?.toString() ?? '';
                    final banned = _banned.contains(id);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: dark
                            ? Colors.white.withOpacity(.04)
                            : BookNestColors.navyDeep.withOpacity(.03),
                        border: Border.all(
                            color: banned
                                ? const Color(0xFFD06A6A).withOpacity(.5)
                                : BookNestColors.cyan.withOpacity(.2)),
                      ),
                      child: Row(
                        children: [
                          BookNestAvatar(
                            imageUrl:
                                person['avatar_url']?.toString(),
                            name: (person['display_name'] ??
                                    person['username'] ??
                                    '?')
                                .toString(),
                            radius: 19,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (person['display_name'] ??
                                          person['username'] ??
                                          'Reader')
                                      .toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14),
                                ),
                                Text('@${person['username'] ?? ''}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: theme.hintColor)),
                              ],
                            ),
                          ),
                          if (banned)
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Icon(Icons.block_rounded,
                                  size: 18, color: Color(0xFFD06A6A)),
                            ),
                          IconButton(
                            tooltip: banned
                                ? 'Lift suspension'
                                : 'Suspend reader',
                            icon: Icon(
                              banned
                                  ? Icons.lock_open_rounded
                                  : Icons.block_rounded,
                              size: 20,
                              color: banned
                                  ? BookNestColors.cyan
                                  : const Color(0xFFD06A6A),
                            ),
                            onPressed: () => _toggleBan(person),
                          ),
                          IconButton(
                            tooltip: 'Adjust gems',
                            icon: const Icon(Icons.diamond_outlined,
                                size: 20, color: BookNestColors.cyan),
                            onPressed: () => _adjustGems(person),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── Pulse: stats + audit ───────────────────────────────────────────────────

class _StatsTab extends StatefulWidget {
  const _StatsTab();

  @override
  State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab>
    with AutomaticKeepAliveClientMixin {
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _audit = [];
  bool _loading = true;
  bool _denied = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await BackendApi.instance.call('admin.stats');
    if (!mounted) return;
    if (res == null) {
      setState(() {
        _loading = false;
        _denied = true;
      });
      return;
    }
    setState(() {
      _stats = res['stats'] is Map
          ? Map<String, dynamic>.from(res['stats'] as Map)
          : null;
      _audit = ((res['audit'] as List?) ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _loading = false;
      _denied = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    if (_loading) {
      return const Center(child: BookNestLoader(size: 56));
    }
    if (_denied || _stats == null) {
      return Center(
        child: Text('Only the overall moderator can view this.',
            style: TextStyle(color: theme.hintColor)),
      );
    }
    final s = _stats!;
    final tiles = [
      ('Readers', s['readers'], Icons.people_outline_rounded),
      ('Books', s['books'], Icons.menu_book_outlined),
      ('Posts', s['posts'], Icons.article_outlined),
      ('Messages · 24h', s['messages24h'], Icons.chat_bubble_outline_rounded),
      ('Open reports', s['openReports'], Icons.flag_outlined),
      ('Active suspensions', s['activeBans'], Icons.block_outlined),
    ];
    return RefreshIndicator(
      color: BookNestColors.cyan,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.5,
            children: [
              for (final tile in tiles)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: dark
                        ? Colors.white.withOpacity(.04)
                        : BookNestColors.navyDeep.withOpacity(.03),
                    border: Border.all(
                        color: BookNestColors.cyan.withOpacity(.2)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(tile.$3, size: 18, color: BookNestColors.cyan),
                      const Spacer(),
                      Text('${tile.$2 ?? 0}',
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      Text(tile.$1,
                          style: TextStyle(
                              fontSize: 11.5, color: theme.hintColor)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text('Moderation log',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (_audit.isEmpty)
            Text('No admin actions recorded yet.',
                style: TextStyle(color: theme.hintColor, fontSize: 13))
          else
            ..._audit.map((entry) {
              final when =
                  DateTime.tryParse(entry['createdAt']?.toString() ?? '')
                          ?.toLocal() ??
                      DateTime.now();
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: dark
                      ? Colors.white.withOpacity(.03)
                      : BookNestColors.navyDeep.withOpacity(.02),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined,
                        size: 14, color: BookNestColors.cyan),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${entry['action'] ?? ''} · ${entry['detail']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Text(
                        '${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}',
                        style: TextStyle(
                            fontSize: 10.5, color: theme.hintColor)),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
