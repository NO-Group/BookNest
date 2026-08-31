import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../../services/supabase_service.dart';

/// Telegram-style conversation list.
///
/// Conversations come from the booknest-api edge function (MongoDB); the
/// people behind them come from Supabase `profiles` (per the architecture
/// decision: profiles stay relational, chats are heavy data).
/// Before the edge function is deployed the screen degrades gracefully:
/// it says so honestly and offers the contact directory to start chats,
/// which then run in local-echo mode inside [DMChatScreen].
class DMListScreen extends StatefulWidget {
  const DMListScreen({super.key});

  @override
  State<DMListScreen> createState() => _DMListScreenState();
}

class _DMListScreenState extends State<DMListScreen> {
  bool _loading = true;
  bool _cloudReady = false;
  List<Map<String, dynamic>> _conversations = [];
  Map<String, Map<String, dynamic>> _people = {};
  Future<List<Map<String, dynamic>>>? _directory;

  @override
  void initState() {
    super.initState();
    _directory = _loadDirectory();
    _load();
  }

  Future<List<Map<String, dynamic>>> _loadDirectory() async {
    try {
      final rows = await SupabaseService()
          .client
          .from('profiles')
          .select('id, username, display_name, avatar_url')
          .limit(50);
      return (rows as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .where((person) => person['id'] != viewerId)
          .toList();
    } catch (_) {
      return [];
    }
  }

  String? get viewerId => SupabaseService().auth.currentUser?.id;

  Future<void> _load() async {
    final res = await BackendApi.instance.listConversations();
    if (!mounted) return;
    if (res == null) {
      setState(() {
        _loading = false;
        _cloudReady = false;
      });
      return;
    }
    final conversations = (res['conversations'] as List? ?? [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    final peerIds = conversations
        .map((c) => c['peerId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final people = <String, Map<String, dynamic>>{};
    if (peerIds.isNotEmpty) {
      try {
        final rows = await SupabaseService()
            .client
            .from('profiles')
            .select('id, username, display_name, avatar_url')
            .inFilter('id', peerIds);
        for (final row in rows as List) {
          final person = Map<String, dynamic>.from(row as Map);
          people[person['id']?.toString() ?? ''] = person;
        }
      } catch (_) {}
    }
    setState(() {
      _conversations = conversations;
      _people = people;
      _cloudReady = true;
      _loading = false;
    });
  }

  String _displayName(String peerId) {
    final person = _people[peerId];
    final name = (person?['display_name'] ?? person?['username'])?.toString();
    return (name == null || name.trim().isEmpty) ? 'BookNest reader' : name;
  }

  String _preview(Map<String, dynamic> conversation) {
    final last = conversation['lastMessage'];
    if (last is! Map) return 'Say hello 👋';
    final mine = last['senderId']?.toString() == viewerId;
    final prefix = mine ? 'You: ' : '';
    final type = last['type']?.toString() ?? 'text';
    final text = last['text']?.toString() ?? '';
    if (type == 'book_share') return '$prefix📖 $text';
    if (type == 'image') return '${prefix}📷 Photo';
    if (type == 'voice') return '${prefix}🎙 Voice note';
    if (type == 'file') return '${prefix}📎 Attachment';
    return '$prefix$text';
  }

  String _timeLabel(dynamic timestamp) {
    if (timestamp is! DateTime) return '';
    final now = DateTime.now();
    final local = timestamp.toLocal();
    if (local.year == now.year && local.month == now.month && local.day == now.day) {
      return DateFormat('HH:mm').format(local);
    }
    if (now.difference(local).inDays < 7) return DateFormat('EEE').format(local);
    return DateFormat('MMM d').format(local);
  }

  Future<void> _pickContact() async {
    final directory = await _directory;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ContactPickerSheet(contacts: directory ?? const <Map<String, dynamic>>[]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: dark ? BookNestColors.darkChatBackground : BookNestColors.lightSurface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Messages',
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        Text(
                          _cloudReady
                              ? 'Your BookNest conversations'
                              : 'BookNest readers',
                          style: TextStyle(color: BookNestColors.cyan),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: _pickContact,
                    icon: const Icon(Icons.edit_square),
                    tooltip: 'New chat',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: BookNestColors.cyan))
                  : RefreshIndicator(
                      color: BookNestColors.cyan,
                      onRefresh: _load,
                      child: _cloudReady
                          ? _buildConversationList(theme, dark)
                          : _buildFallback(theme, dark),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationList(ThemeData theme, bool dark) {
    if (_conversations.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 90),
          Icon(Icons.forum_outlined,
              size: 64, color: BookNestColors.cyan.withOpacity(.5)),
          const SizedBox(height: 14),
          Center(
            child: Text('No conversations yet',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text('Tap ✏️ to share a book or say hello.',
                style: TextStyle(color: theme.hintColor)),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: _conversations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final conversation = _conversations[index];
        final peerId = conversation['peerId']?.toString() ?? '';
        final last = conversation['lastMessage'];
        final unreadish = last != null && last['senderId']?.toString() != viewerId;
        return ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          leading: _PersonAvatar(
            person: _people[peerId],
            name: _displayName(peerId),
          ),
          title: Text(
            _displayName(peerId),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            _preview(conversation),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: unreadish
                  ? (dark ? BookNestColors.darkTextPrimary : BookNestColors.navyDeep)
                  : theme.hintColor,
              fontWeight: unreadish ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          trailing: Text(
            _timeLabel(conversation['updatedAt']),
            style: TextStyle(color: theme.hintColor, fontSize: 12),
          ),
          onTap: () => context.push('/chat/${conversation['id']}?peer=$peerId'),
        );
      },
    );
  }

  Widget _buildFallback(ThemeData theme, bool dark) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: BookNestColors.cyan.withOpacity(.08),
            border: Border.all(color: BookNestColors.cyan.withOpacity(.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.cloud_off_rounded, color: BookNestColors.cyan),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Chats sync once the message cloud is connected. '
                  'You can still start conversations now.',
                  style: TextStyle(color: theme.hintColor, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Start a chat',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _directory,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                  child: Padding(
                padding: EdgeInsets.all(28),
                child: CircularProgressIndicator(color: BookNestColors.cyan),
              ));
            }
            final contacts = snapshot.data ?? [];
            if (contacts.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text('No BookNest readers found yet.',
                      style: TextStyle(color: theme.hintColor)),
                ),
              );
            }
            return Column(
              children: contacts
                  .map((person) => _directoryTile(theme, person))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _directoryTile(ThemeData theme, Map<String, dynamic> person) {
    final name = (person['display_name'] ?? person['username'] ?? 'Reader')
        .toString();
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      leading: _PersonAvatar(person: person, name: name),
      title: Text(name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: person['username'] == null
          ? null
          : Text('@${person['username']}'),
      trailing: const Icon(Icons.chat_bubble_outline,
          size: 18, color: BookNestColors.cyan),
      onTap: () => context.push('/chat/peer/${person['id']}'),
    );
  }
}

class _PersonAvatar extends StatelessWidget {
  final Map<String, dynamic>? person;
  final String name;

  const _PersonAvatar({required this.person, required this.name});

  @override
  Widget build(BuildContext context) {
    final url = person?['avatar_url']?.toString();
    final initial = name.characters.isEmpty
        ? '?'
        : name.characters.first.toUpperCase();
    return CircleAvatar(
      radius: 24,
      backgroundColor: BookNestColors.navy,
      backgroundImage:
          url != null && url.startsWith('http') ? NetworkImage(url) : null,
      child: url != null && url.startsWith('http')
          ? null
          : Text(initial, style: const TextStyle(color: Colors.white)),
    );
  }
}

/// Simple contact directory used for starting new chats.
class _ContactPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> contacts;

  const _ContactPickerSheet({required this.contacts});

  @override
  State<_ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<_ContactPickerSheet> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = const [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
  }

  /// Realtime search: every keystroke (debounced 280 ms) queries the
  /// profiles table server-side by username AND display name, so readers
  /// are found no matter how many accounts exist.
  void _onSearchChanged() {
    _debounce?.cancel();
    final term = _search.text.trim();
    if (term.isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      final found = await SupabaseService().searchProfiles(term);
      if (!mounted) return;
      setState(() {
        _results = found;
        _searching = false;
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: MediaQuery.sizeOf(context).height * .7,
            decoration: BoxDecoration(
              color: (theme.brightness == Brightness.dark
                      ? BookNestColors.darkChatBackground
                      : Colors.white)
                  .withOpacity(.96),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(30)),
              border: Border.all(color: BookNestColors.cyan.withOpacity(.22)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 16),
                Text('New chat',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Search BookNest readers',
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Builder(builder: (context) {
                    final term = _search.text.trim();
                    final contacts = term.isEmpty ? widget.contacts : _results;
                    if (contacts.isEmpty) {
                      return Center(
                        child: Text('No readers found.',
                            style: TextStyle(color: theme.hintColor)),
                      );
                    }
                    return ListView.separated(
                      itemCount: contacts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 2),
                      itemBuilder: (_, index) {
                        final person = contacts[index];
                        final name =
                            (person['display_name'] ?? person['username'] ?? 'Reader')
                                .toString();
                        return ListTile(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          leading: _PersonAvatar(person: person, name: name),
                          title: Text(name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: person['username'] == null
                              ? null
                              : Text('@${person['username']}'),
                          onTap: () =>
                              context.push('/chat/peer/${person['id']}'),
                        );
                      },
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
