import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/time_format.dart';
import '../../../services/supabase_service.dart';
import '../../components/user_avatar.dart';
import '../../../config/theme.dart';

/// Direct-messages inbox (Tab 4 of the bottom nav).
///
/// Live behaviour:
/// - A Supabase `.stream()` on `conversation_members` (filtered to the current
///   user) keeps the membership set fresh — new conversations appear without
///   a manual refresh.
/// - A realtime channel on `messages` acts as a "ticker": any new message
///   triggers a debounced re-fetch of the conversation list, so ordering and
///   previews stay current.
/// - The heavy lifting (partner profile, last message, unread count) is done
///   by the `get_my_conversations()` RPC, keeping this screen dumb and fast.
class DMListScreen extends StatefulWidget {
  const DMListScreen({super.key});

  @override
  State<DMListScreen> createState() => _DMListScreenState();
}

class _DMListScreenState extends State<DMListScreen> {
  final List<Map<String, dynamic>> _conversations = [];
  bool _isLoading = true;
  String? _myId;

  StreamSubscription<List<Map<String, dynamic>>>? _membershipSub;
  RealtimeChannel? _tickerChannel;
  Timer? _refreshDebounce;

  @override
  void initState() {
    super.initState();
    _myId = SupabaseService().auth.currentUser?.id;
    if (_myId == null) return;
    _subscribeMemberships();
    _subscribeMessageTicker();
    _refreshConversations();
  }

  void _subscribeMemberships() {
    _membershipSub = SupabaseService()
        .client
        .from('conversation_members')
        .stream(primaryKey: ['id'])
        .eq('user_id', _myId!)
        .listen((_) => _refreshConversations(debounce: true));
  }

  void _subscribeMessageTicker() {
    final channel = SupabaseService().client.channel('dm-ticker');
    _tickerChannel = channel;
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
        )
        .listen((_) => _refreshConversations(debounce: true));
    channel.subscribe();
  }

  Future<void> _refreshConversations({bool debounce = false}) async {
    if (debounce) {
      _refreshDebounce?.cancel();
      _refreshDebounce = Timer(
        const Duration(milliseconds: 400),
        () => _refreshConversations(),
      );
      return;
    }

    try {
      final rows = await SupabaseService().client.rpc('get_my_conversations');
      if (!mounted) return;
      setState(() {
        _conversations
          ..clear()
          ..addAll(
            rows.map((r) => Map<String, dynamic>.from(r as Map)).toList(),
          );
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openNewMessageSheet() async {
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: NOC.surfaceAlt,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _NewConversationSheet(myId: _myId),
    );

    if (selected == null || !mounted) return;

    try {
      final conversationId = await SupabaseService()
          .client
          .rpc('get_or_create_dm', params: {'other_user': selected['id']});
      if (!mounted) return;
      context.push('/dm/$conversationId');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not start a conversation: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _openConversation(Map<String, dynamic> conversation) {
    context.push('/dm/${conversation['conversation_id']}');
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _membershipSub?.cancel();
    _tickerChannel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NOC.bg,
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            icon:  Icon(Icons.search, color: NOC.text),
            tooltip: 'Search messages',
            onPressed: () {},
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openNewMessageSheet,
        backgroundColor: NOC.accent,
        child:  Icon(Icons.edit_outlined, color: NOC.onAccent),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_myId == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
             Icon(
              Icons.lock_outline,
              size: 56,
              color: NOC.textFaint,
            ),
            const SizedBox(height: 16),
             Text(
              'Sign in to see your messages',
              style: TextStyle(color: NOC.text, fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/login'),
              child: const Text('Sign in'),
            ),
          ],
        ),
      );
    }

    if (_isLoading && _conversations.isEmpty) {
      return  Center(
        child: CircularProgressIndicator(color: NOC.accent),
      );
    }

    if (_conversations.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      color: NOC.accent,
      backgroundColor: NOC.surface,
      onRefresh: _refreshConversations,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        itemCount: _conversations.length,
        itemBuilder: (context, index) => _ConversationTile(
          conversation: _conversations[index],
          myId: _myId,
          onTap: () => _openConversation(_conversations[index]),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   Icon(
                    Icons.chat_bubble_outline,
                    size: 64,
                    color: NOC.textFaint,
                  ),
                  const SizedBox(height: 16),
                   Text(
                    'No messages yet',
                    style: TextStyle(color: NOC.text, fontSize: 20),
                  ),
                  const SizedBox(height: 8),
                   Text(
                    'Tap the compose button to start a conversation with any reader.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: NOC.textMuted, fontSize: 14),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: _openNewMessageSheet,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('New message'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One row in the DM list.
class _ConversationTile extends StatelessWidget {
  final Map<String, dynamic> conversation;
  final String? myId;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.conversation,
    required this.myId,
    required this.onTap,
  });

  String get _name {
    final displayName = conversation['partner_display_name'];
    final username = conversation['partner_username'];
    if (displayName != null && displayName.toString().isNotEmpty) {
      return displayName.toString();
    }
    return username?.toString() ?? 'Unknown';
  }

  String get _preview {
    final lastSenderId = conversation['last_sender_id']?.toString();
    final prefix = (lastSenderId != null && lastSenderId == myId)
        ? 'You: '
        : '';

    // Non-text messages show a friendly label instead of raw metadata.
    final type = conversation['last_message_type']?.toString();
    switch (type) {
      case 'image':
        return '$prefix📷 Photo';
      case 'file':
        return '$prefix📎 Attachment';
      case 'system':
        return '$prefix${conversation['last_message'] ?? ''}';
    }

    final lastMessage = conversation['last_message']?.toString();
    if (lastMessage == null || lastMessage.isEmpty) {
      return 'No messages yet';
    }
    return '$prefix$lastMessage';
  }

  int get _unreadCount => (conversation['unread_count'] as num?)?.toInt() ?? 0;
  bool get _isUnread => _unreadCount > 0;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            UserAvatar(
              imageUrl: conversation['partner_avatar_url']?.toString(),
              name: _name,
              radius: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: NOC.text,
                      fontSize: 15,
                      fontWeight:
                          _isUnread ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _isUnread
                          ? NOC.textMuted
                          : NOC.textMuted,
                      fontSize: 13,
                      fontWeight:
                          _isUnread ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatRelativeTime(
                    DateTime.tryParse(
                          conversation['last_message_at']?.toString() ?? '',
                        ) ??
                        DateTime.now(),
                  ),
                  style:  TextStyle(
                    color: NOC.textFaint,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 6),
                if (_isUnread)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: NOC.accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _unreadCount > 99 ? '99+' : '$_unreadCount',
                      style:  TextStyle(
                        color: NOC.bg,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet that searches profiles and starts a new DM.
class _NewConversationSheet extends StatefulWidget {
  final String? myId;

  const _NewConversationSheet({this.myId});

  @override
  State<_NewConversationSheet> createState() => _NewConversationSheetState();
}

class _NewConversationSheetState extends State<_NewConversationSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onQueryChanged);
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _search(_searchController.text),
    );
  }

  Future<void> _search(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    try {
      final res = await SupabaseService()
          .client
          .from('profiles')
          .select('id, username, display_name, avatar_url')
          .neq('id', widget.myId!)
          .or('username.ilike.%$q%,display_name.ilike.%$q%')
          .limit(20);
      if (!mounted) return;
      // Ignore stale responses: only apply the result if the query is still
      // the one the user last typed.
      if (_searchController.text.trim() != q) return;
      setState(() {
        _results = res.map((r) => Map<String, dynamic>.from(r)).toList();
        _isSearching = false;
      });
    } catch (_) {
      if (!mounted) return;
      if (_searchController.text.trim() != q) return;
      setState(() => _isSearching = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Text(
                  'New message',
                  style: TextStyle(
                    color: NOC.text,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style:  TextStyle(color: NOC.text),
                  decoration: InputDecoration(
                    hintText: 'Search by username or name',
                    hintStyle:  TextStyle(color: NOC.textFaint),
                    prefixIcon:
                         Icon(Icons.search, color: NOC.textFaint),
                    filled: true,
                    fillColor: NOC.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _isSearching
                    ?  Center(
                        child: CircularProgressIndicator(
                          color: NOC.accent,
                        ),
                      )
                    : _results.isEmpty
                        ?  Center(
                            child: Text(
                              'No users found',
                              style: TextStyle(color: NOC.textMuted),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: _results.length,
                            itemBuilder: (context, index) {
                              final user = _results[index];
                              final name = (user['display_name']?.toString() ??
                                      user['username']?.toString() ??
                                      'Unknown');
                              return ListTile(
                                leading: UserAvatar(
                                  imageUrl: user['avatar_url']?.toString(),
                                  name: name,
                                  radius: 22,
                                ),
                                title: Text(
                                  name,
                                  style:  TextStyle(color: NOC.text),
                                ),
                                subtitle: Text(
                                  '@${user['username'] ?? ''}',
                                  style:  TextStyle(
                                    color: NOC.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                                onTap: () => Navigator.pop(context, user),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
