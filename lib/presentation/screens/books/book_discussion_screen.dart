import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../config/theme.dart';
import '../../../core/utils/auth_guard.dart';
import '../../../services/backend_api.dart';
import '../../../services/supabase_service.dart';
import '../../components/booknest_ui.dart';

/// Book discussion — lightweight comment thread per book.
class BookDiscussionScreen extends StatefulWidget {
  final String bookId;

  const BookDiscussionScreen({super.key, required this.bookId});

  @override
  State<BookDiscussionScreen> createState() => _BookDiscussionScreenState();
}

class _BookDiscussionScreenState extends State<BookDiscussionScreen> {
  final TextEditingController _input = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true;
  bool _offline = false;
  bool _posting = false;

  String? get _viewerId => SupabaseService().auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await BackendApi.instance.listComments(widget.bookId);
    if (!mounted) return;
    setState(() {
      _offline = res == null;
      _comments = (res?['comments'] as List? ?? [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _loading = false;
    });
  }

  String get _viewerName {
    final user = SupabaseService().auth.currentUser;
    final meta = user?.userMetadata;
    final name =
        (meta?['username'] ?? meta?['display_name'] ?? user?.email?.split('@').first)
            ?.toString();
    return (name == null || name.trim().isEmpty) ? 'Reader' : name.trim();
  }

  Future<void> _post() async {
    final body = _input.text.trim();
    if (body.isEmpty) return;
    setState(() => _posting = true);
    // Optimistic append.
    final localIndex = _comments.length;
    setState(() {
      _comments.insert(0, {
        'id': 'local-$localIndex',
        'userId': _viewerId,
        'userName': _viewerName,
        'body': body,
        'createdAt': DateTime.now(),
        'pending': true,
      });
      _input.clear();
    });
    final res = await BackendApi.instance
        .postComment(bookId: widget.bookId, body: body, displayName: _viewerName);
    if (!mounted) return;
    setState(() => _posting = false);
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Comments sync through the BookNest cloud — kept on this device '
              'until then.')));
      return;
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark
          ? BookNestColors.darkChatBackground
          : BookNestColors.lightSurface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Discussion',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: BookNestColors.cyan))
                : _comments.isEmpty
                    ? EmptyState(
                        icon: Icons.forum_rounded,
                        title: 'Start the conversation',
                        subtitle: _offline
                            ? 'Comments sync through the BookNest cloud once '
                                'it is connected.'
                            : 'Ask a question or share a thought about this book.',
                      )
                    : RefreshIndicator(
                        color: BookNestColors.cyan,
                        onRefresh: _load,
                        child: ListView.separated(
                          padding:
                              const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          itemCount: _comments.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final comment = _comments[index];
                            final pending = comment['pending'] == true;
                            final createdAt = comment['createdAt'];
                            final time = createdAt is DateTime
                                ? DateFormat('MMM d · HH:mm')
                                    .format(createdAt.toLocal())
                                : '';
                            final mine =
                                comment['userId']?.toString() == _viewerId;
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                color: mine && !pending
                                    ? BookNestColors.cyan.withOpacity(.07)
                                    : theme.colorScheme.surface,
                                border:
                                    Border.all(color: theme.dividerColor),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      GestureDetector(
                                        onTap: comment['userId'] == null
                                            ? null
                                            : () => context.push(
                                                '/user/${comment['userId']}'),
                                        child: Row(
                                          children: [
                                            BookNestAvatar(
                                              name: comment['userName']
                                                      ?.toString() ??
                                                  'Reader',
                                              radius: 13,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                                comment['userName']
                                                        ?.toString() ??
                                                    'Reader',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w800,
                                                    fontSize: 13)),
                                          ],
                                        ),
                                      ),
                                      const Spacer(),
                                      if (pending)
                                        Icon(Icons.schedule,
                                            size: 13, color: theme.hintColor)
                                      else
                                        Text(time,
                                            style: TextStyle(
                                                color: theme.hintColor,
                                                fontSize: 11)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(comment['body']?.toString() ?? '',
                                      style: TextStyle(
                                        color: theme.colorScheme.onSurface
                                            .withOpacity(.88),
                                        height: 1.4,
                                        fontSize: 13.5,
                                      )),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                    top: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Add to the discussion…',
                        fillColor: dark
                            ? BookNestColors.darkReceivedMessage
                            : BookNestColors.lightSurface,
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _posting
                        ? null
                        : () => AuthGuard.run(context, _post),
                    style: IconButton.styleFrom(
                      backgroundColor: BookNestColors.cyan,
                      foregroundColor: BookNestColors.navyDeep,
                    ),
                    icon: const Icon(Icons.send_rounded, size: 19),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
