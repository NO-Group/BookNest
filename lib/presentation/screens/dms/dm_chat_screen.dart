import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/time_format.dart';
import '../../../services/supabase_service.dart';
import '../../components/user_avatar.dart';
import 'video_player_screen.dart';
import '../../../config/theme.dart';

/// Conversation screen for both 1-on-1 DMs (`/dm/:conversationId`) and group
/// chats (`/group-chat/:conversationId`).
///
/// Direct mode: partner avatar/name in the app bar; right/left bubbles.
///
/// Group mode:
/// - Streams the conversation's `messages` rows live (primaryKey `id`,
///   filtered by `conversation_id`, ascending), rendered reversed so the
///   newest bubble sits at the bottom.
/// - Sender names shown above received bubbles (profiles loaded once from
///   `group_members`).
/// - Reactions: tap the heart on any bubble to like/unlike (announcements are
///   react-only for normal members).
/// - Admins/Owners: long-press a bubble to Pin/Unpin or Delete. The pin guard
///   is enforced server-side too (`enforce_pin_permission` trigger).
/// - Announcement groups: the input bar is hidden for non-admin members.
class ConversationChatScreen extends StatefulWidget {
  final String conversationId;
  final bool isGroup;

  const ConversationChatScreen({
    super.key,
    required this.conversationId,
    this.isGroup = false,
  });

  @override
  State<ConversationChatScreen> createState() => _ConversationChatScreenState();
}

class _ConversationChatScreenState extends State<ConversationChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();

  Map<String, dynamic>? _partner;
  Map<String, dynamic>? _group;
  Map<String, dynamic>? _myMembership; // group mode: my group_members row
  bool _isLoading = true;
  String? _error;
  String? _myId;

  final Map<String, Map<String, dynamic>> _senderProfiles = {};

  Stream<List<Map<String, dynamic>>>? _messagesStream;
  Timer? _readTimer;

  // Reactions state: messageId -> count, plus the set I have reacted to.
  final Map<String, int> _reactionCounts = {};
  final Set<String> _reactedByMe = {};
  String _loadedReactionKey = '';

  @override
  void initState() {
    super.initState();
    _myId = SupabaseService().auth.currentUser?.id;
    _loadConversation();
    _messagesStream = SupabaseService()
        .client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', widget.conversationId)
        .order('created_at', ascending: true);
    _markRead();
    _readTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _markRead(),
    );
  }

  Future<void> _loadConversation() async {
    try {
      final row = await SupabaseService()
          .client
          .from('conversations')
          .select('*, groups!inner(*)')
          .eq('id', widget.conversationId)
          .maybeSingle();

      if (!mounted) return;

      if (row == null) {
        setState(() {
          _isLoading = false;
          _error = 'This conversation no longer exists.';
        });
        return;
      }

      if (widget.isGroup) {
        final groupRow = (row['groups'] as List?)?.isNotEmpty == true
            ? Map<String, dynamic>.from((row['groups'] as List).first as Map)
            : null;
        if (groupRow == null) {
          setState(() {
            _isLoading = false;
            _error = 'This group no longer exists.';
          });
          return;
        }
        _group = groupRow;
        await _loadGroupMembers(groupRow['id'].toString());
      } else {
        final members = (row['conversation_members'] as List?) ?? [];
        Map<String, dynamic>? partner;
        for (final member in members) {
          final memberMap = Map<String, dynamic>.from(member as Map);
          final isMe = memberMap['user_id']?.toString() == _myId;
          final profile = memberMap['profiles'];
          if (!isMe && profile != null) {
            partner = Map<String, dynamic>.from(profile as Map);
            break;
          }
        }
        _partner = partner;
      }

      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Could not load this conversation: $e';
      });
    }
  }

  Future<void> _loadGroupMembers(String groupId) async {
    try {
      final rows = await SupabaseService()
          .client
          .from('group_members')
          .select('user_id, role, profiles(id, username, display_name, avatar_url)')
          .eq('group_id', groupId);
      if (!mounted) return;
      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final profile = map['profiles'];
        if (profile != null) {
          _senderProfiles[map['user_id'].toString()] =
              Map<String, dynamic>.from(profile as Map);
        }
        if (map['user_id']?.toString() == _myId) {
          _myMembership = map;
        }
      }
    } catch (_) {
      // Non-fatal: names fall back to "Unknown".
    }
  }

  bool get _isAnnouncement => _group?['group_type'] == 'announcement';

  bool get _canPostInGroup {
    if (!widget.isGroup) return true;
    if (!_isAnnouncement) return true;
    final role = _myMembership?['role']?.toString();
    return role == 'owner' || role == 'admin';
  }

  bool get _canManageGroup {
    if (!widget.isGroup) return false;
    final role = _myMembership?['role']?.toString();
    return role == 'owner' || role == 'admin';
  }

  Future<void> _markRead() async {
    final myId = _myId;
    if (myId == null) return;
    await SupabaseService()
        .client
        .from('conversation_members')
        .update({'last_read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('conversation_id', widget.conversationId)
        .eq('user_id', myId);
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    final myId = _myId;
    if (text.isEmpty || myId == null) return;

    try {
      await SupabaseService().client.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': myId,
        'type': 'text',
        'content': text,
      });
      if (!mounted) return;
      _inputController.clear();
      _markRead();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not send message: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  /// Paper-clip menu: pick a photo, a video or a document to send. All media
  /// is uploaded at its **original (HD) quality** — no compression is applied.
  Future<void> _showAttachmentSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: NOC.surfaceAlt,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined, color: Color(0xFF1E4FD6)),
              title: Text('Photo', style: TextStyle(color: NOC.text)),
              subtitle: Text(
                'HD quality',
                style: TextStyle(color: NOC.textMuted, fontSize: 12),
              ),
              onTap: () => Navigator.pop(sheetContext, 'photo'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined, color: Color(0xFF1E4FD6)),
              title: Text('Video', style: TextStyle(color: NOC.text)),
              subtitle: Text(
                'HD quality',
                style: TextStyle(color: NOC.textMuted, fontSize: 12),
              ),
              onTap: () => Navigator.pop(sheetContext, 'video'),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined, color: Color(0xFF1E4FD6)),
              title: Text('Document', style: TextStyle(color: NOC.text)),
              subtitle: Text(
                'PDF, Word, TXT and more',
                style: TextStyle(color: NOC.textMuted, fontSize: 12),
              ),
              onTap: () => Navigator.pop(sheetContext, 'document'),
            ),
            ListTile(
              leading: Icon(Icons.close, color: NOC.textMuted),
              title: Text('Cancel', style: TextStyle(color: NOC.textMuted)),
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );

    if (choice == null) return;
    await _pickAndSendAttachment(kind: choice);
  }

  /// Best-effort MIME type from a file name (used for documents/videos).
  String _mimeForName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return 'application/octet-stream';
    final ext = name.substring(dot + 1).toLowerCase();
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'txt':
        return 'text/plain';
      case 'md':
        return 'text/markdown';
      case 'zip':
        return 'application/zip';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      default:
        return 'application/octet-stream';
    }
  }

  /// Picks, uploads and sends an attachment. [kind] is
  /// 'photo' | 'video' | 'document'. Media keeps its original (HD) bytes.
  Future<void> _pickAndSendAttachment({required String kind}) async {
    final myId = _myId;
    if (myId == null) return;

    try {
      Uint8List bytes;
      String name;
      String mime;

      switch (kind) {
        case 'photo':
          final picked =
              await ImagePicker().pickImage(source: ImageSource.gallery);
          if (picked == null || !mounted) return;
          bytes = await picked.readAsBytes();
          name = picked.name.isNotEmpty ? picked.name : 'photo.jpg';
          mime = _mimeForName(name);
          break;
        case 'video':
          final picked =
              await ImagePicker().pickVideo(source: ImageSource.gallery);
          if (picked == null || !mounted) return;
          bytes = await picked.readAsBytes();
          name = picked.name.isNotEmpty ? picked.name : 'video.mp4';
          mime = _mimeForName(name);
          break;
        case 'document':
        default:
          final result = await FilePicker.platform.pickFiles(
            type: FileType.any,
            withData: true,
          );
          if (result == null || result.files.isEmpty || !mounted) return;
          final file = result.files.single;
          final fileBytes = file.bytes;
          if (fileBytes == null) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not read this file.'),
                backgroundColor: Colors.redAccent,
              ),
            );
            return;
          }
          bytes = fileBytes;
          name = file.name;
          mime = _mimeForName(name);
          break;
      }

      final path =
          '${widget.conversationId}/${DateTime.now().millisecondsSinceEpoch}_$name';

      final url = await SupabaseService().uploadPublicImage(
        bucket: 'attachments',
        path: path,
        bytes: bytes,
        contentType: mime,
      );

      if (!mounted) return;
      await SupabaseService().client.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': myId,
        'type': kind == 'photo' ? 'image' : 'file',
        'content': name,
        'metadata': {
          'url': url,
          'mime_type': mime,
          'size': bytes.length,
          'name': name,
          'kind': kind,
        },
      });
      _markRead();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not send attachment: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _loadReactions(List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    final key = messageIds.join(',');
    if (key == _loadedReactionKey) return;
    _loadedReactionKey = key;
    try {
      final rows = await SupabaseService()
          .client
          .from('message_reactions')
          .select('message_id, user_id')
          .inFilter('message_id', messageIds);
      if (!mounted) return;
      setState(() {
        _reactionCounts.clear();
        _reactedByMe.clear();
        for (final row in rows) {
          final map = Map<String, dynamic>.from(row as Map);
          final mid = map['message_id'].toString();
          _reactionCounts[mid] = (_reactionCounts[mid] ?? 0) + 1;
          if (map['user_id']?.toString() == _myId) _reactedByMe.add(mid);
        }
      });
    } catch (_) {
      _loadedReactionKey = '';
    }
  }

  Future<void> _toggleReaction(String messageId) async {
    final myId = _myId;
    if (myId == null) return;
    try {
      if (_reactedByMe.contains(messageId)) {
        await SupabaseService()
            .client
            .from('message_reactions')
            .delete()
            .eq('message_id', messageId)
            .eq('user_id', myId);
      } else {
        await SupabaseService().client.from('message_reactions').insert({
          'message_id': messageId,
          'user_id': myId,
          'reaction': 'like',
        });
      }
      _loadedReactionKey = ''; // force refresh
      final ids = _reactionCounts.keys.toList();
      if (!ids.contains(messageId)) ids.add(messageId);
      await _loadReactions(ids);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update reaction: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _showMessageActions(Map<String, dynamic> message) async {
    final mid = message['id'].toString();
    final isPinned = message['is_pinned'] == true;
    final isMine = message['sender_id']?.toString() == _myId;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: NOC.surfaceAlt,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_canManageGroup)
              ListTile(
                leading: Icon(
                  isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                  color: NOC.accent,
                ),
                title: Text(
                  isPinned ? 'Unpin message' : 'Pin message',
                  style:  TextStyle(color: NOC.text),
                ),
                onTap: () => Navigator.pop(sheetContext, 'pin'),
              ),
            if (_canManageGroup || isMine)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text(
                  'Delete message',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () => Navigator.pop(sheetContext, 'delete'),
              ),
            ListTile(
              leading:  Icon(Icons.close, color: NOC.textMuted),
              title:  Text('Cancel', style: TextStyle(color: NOC.textMuted)),
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );

    if (action == null || !mounted) return;
    try {
      if (action == 'pin') {
        await SupabaseService()
            .client
            .from('messages')
            .update({'is_pinned': !isPinned})
            .eq('id', mid);
      } else if (action == 'delete') {
        await SupabaseService().client.from('messages').delete().eq('id', mid);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Action failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  String get _title {
    if (widget.isGroup) {
      return _group?['name']?.toString() ?? 'Group';
    }
    final displayName = _partner?['display_name']?.toString();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    return _partner?['username']?.toString() ?? 'Chat';
  }

  String? _senderName(String senderId) {
    final profile = _senderProfiles[senderId];
    final displayName = profile?['display_name']?.toString();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    return profile?['username']?.toString();
  }

  @override
  void dispose() {
    _readTimer?.cancel();
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
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
        titleSpacing: 0,
        title: Row(
          children: [
            if (widget.isGroup)
              UserAvatar(
                imageUrl: _group?['avatar_url']?.toString(),
                name: _title,
                radius: 18,
                accentColor: NOC.hot,
              )
            else
              UserAvatar(
                imageUrl: _partner?['avatar_url']?.toString(),
                name: _title,
                radius: 18,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:  TextStyle(
                      color: NOC.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (widget.isGroup && _isAnnouncement)
                     Text(
                      'Announcements',
                      style: TextStyle(
                        color: NOC.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (widget.isGroup && _group?['id'] != null)
            IconButton(
              icon:  Icon(Icons.info_outline, color: NOC.text),
              tooltip: 'Group info',
              onPressed: () => context.push('/group/${_group!['id']}'),
            )
          else
            PopupMenuButton<String>(
              icon:  Icon(Icons.more_vert, color: NOC.text),
              color: NOC.surfaceAlt,
              onSelected: (value) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      value == 'profile'
                          ? 'Profile pages are coming soon.'
                          : 'Coming soon.',
                    ),
                    backgroundColor: NOC.accent,
                  ),
                );
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'profile',
                  child: Text('View profile'),
                ),
                PopupMenuItem(
                  value: 'clear',
                  child: Text('Clear chat'),
                ),
              ],
            ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: widget.isGroup && _isAnnouncement && !_canPostInGroup
          ? _buildAnnouncementBanner()
          : _buildInputBar(),
    );
  }

  Widget _buildAnnouncementBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: NOC.surface,
      child:  Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.campaign_outlined, color: NOC.accent, size: 18),
          SizedBox(width: 8),
          Text(
            'Only owners and admins can post in Announcements',
            style: TextStyle(color: NOC.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _partner == null && _group == null && _error == null) {
      return  Center(
        child: CircularProgressIndicator(color: NOC.accent),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
             Icon(Icons.error_outline, size: 56, color: NOC.textFaint),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style:  TextStyle(color: NOC.textMuted, fontSize: 15),
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _loadConversation();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _messagesStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return  Center(
            child: CircularProgressIndicator(color: NOC.accent),
          );
        }

        final messages = snapshot.data ?? const <Map<String, dynamic>>[];
        if (messages.isNotEmpty) {
          _loadReactions(
            messages.map((m) => m['id'].toString()).toList(),
          );
        }

        if (messages.isEmpty) {
          final greeting = widget.isGroup
              ? 'No messages yet — say something!'
              : 'Say hi to ${_title.split(' ').first}!';
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                 Icon(
                  Icons.waving_hand_outlined,
                  size: 56,
                  color: NOC.textFaint,
                ),
                const SizedBox(height: 16),
                Text(
                  greeting,
                  style:  TextStyle(color: NOC.text, fontSize: 16),
                ),
                const SizedBox(height: 8),
                 Text(
                  'Your messages will appear here.',
                  style: TextStyle(color: NOC.textMuted, fontSize: 13),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[messages.length - 1 - index];
            final senderId = message['sender_id']?.toString() ?? '';
            final metadata = message['metadata'] is Map
                ? Map<String, dynamic>.from(message['metadata'] as Map)
                : const <String, dynamic>{};
            final type = message['type']?.toString() ?? 'text';
            final attachmentUrl = metadata['url']?.toString();
            final attachmentKind = metadata['kind']?.toString();
            final attachmentMime = metadata['mime_type']?.toString();
            final isVideoAttachment = type == 'file' &&
                (attachmentKind == 'video' ||
                    (attachmentMime?.startsWith('video/') ?? false));

            return _MessageBubble(
              message: message,
              isMine: senderId == _myId,
              showSenderName: widget.isGroup &&
                  senderId != _myId &&
                  (_senderName(senderId) ?? '').isNotEmpty,
              senderName: _senderName(senderId) ?? '',
              reactionCount: _reactionCounts[message['id'].toString()] ?? 0,
              reactedByMe: _reactedByMe.contains(message['id'].toString()),
              onReactionTap: widget.isGroup
                  ? () => _toggleReaction(message['id'].toString())
                  : null,
              onLongPress: () => _showMessageActions(message),
              onAttachmentTap: type == 'image' && attachmentUrl != null
                  ? () => _openImageViewer(attachmentUrl,
                      message['content']?.toString() ?? 'Photo')
                  : isVideoAttachment && attachmentUrl != null
                      ? () => _openVideoPlayer(attachmentUrl,
                          message['content']?.toString() ?? 'Video')
                      : type == 'file' && attachmentUrl != null
                          ? () => _openAttachmentUrl(attachmentUrl)
                          : null,
            );
          },
        );
      },
    );
  }

  Widget _buildInputBar() {
    return Container(
      decoration:  BoxDecoration(
        color: NOC.surface,
        border: Border(top: BorderSide(color: NOC.border)),
      ),
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Paper clip: attach photos / videos (HD).
          IconButton(
            onPressed: _showAttachmentSheet,
            tooltip: 'Attach',
            icon: const Icon(Icons.attach_file, color: Color(0xFF1E4FD6)),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _inputController,
              focusNode: _inputFocusNode,
              minLines: 1,
              maxLines: 4,
              style:  TextStyle(color: NOC.text, fontSize: 15),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: 'Message...',
                hintStyle:  TextStyle(color: NOC.textFaint),
                filled: true,
                fillColor: NOC.surfaceAlt,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _sendMessage,
            tooltip: 'Send',
            icon: const Icon(Icons.send, color: Color(0xFF1E4FD6)),
          ),
        ],
      ),
    );
  }

  /// Opens an image message in a full-screen, pinch-zoomable viewer.
  void _openImageViewer(String url, String title) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:  TextStyle(color: NOC.text, fontSize: 16),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              maxScale: 5,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>  Center(
                  child: Text(
                    'Could not load image.',
                    style: TextStyle(color: NOC.textMuted),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Opens a video attachment in the full-screen in-app player.
  void _openVideoPlayer(String url, String title) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => VideoPlayerScreen(url: url, title: title),
      ),
    );
  }

  /// Opens a non-image, non-video attachment (e.g. a document) in the system
  /// browser / default app.
  Future<void> _openAttachmentUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open this attachment.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
}

/// A single message bubble. Sent messages are right-aligned and tinted with
/// the brand cyan, received messages left-aligned on the dark surface.
/// In groups, received bubbles show the sender name; admins can long-press
/// any bubble to pin/delete (server-enforced).
class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMine;
  final bool showSenderName;
  final String senderName;
  final int reactionCount;
  final bool reactedByMe;
  final VoidCallback? onReactionTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onAttachmentTap;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.showSenderName,
    required this.senderName,
    required this.reactionCount,
    required this.reactedByMe,
    required this.onReactionTap,
    required this.onLongPress,
    required this.onAttachmentTap,
  });

  @override
  Widget build(BuildContext context) {
    final type = message['type']?.toString() ?? 'text';
    final content = message['content']?.toString() ?? '';
    final time = formatMessageTimestamp(message['created_at']);
    final isPinned = message['is_pinned'] == true;
    final metadata = message['metadata'] is Map
        ? Map<String, dynamic>.from(message['metadata'] as Map)
        : const <String, dynamic>{};
    final attachmentUrl = metadata['url']?.toString();
    final isImage = type == 'image' && attachmentUrl != null;
    final isFile = type == 'file' && attachmentUrl != null;
    final isVideoAttachment = isFile &&
        (metadata['kind']?.toString() == 'video' ||
            (metadata['mime_type']?.toString().startsWith('video/') ?? false));

    return GestureDetector(
      onLongPress: onLongPress,
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (showSenderName)
              Padding(
                padding: const EdgeInsets.only(left: 10, top: 8, bottom: 2),
                child: Text(
                  senderName,
                  style:  TextStyle(
                    color: NOC.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (isMine) _buildReactionButton(),
                Flexible(
                  child: Container(
                    margin: EdgeInsets.only(
                      top: 4,
                      bottom: 4,
                      left: isMine ? 56 : 0,
                      right: isMine ? 0 : 56,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: isMine
                          ? NOC.accentSoft
                          : NOC.surfaceAlt,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isMine ? 18 : 4),
                        bottomRight: Radius.circular(isMine ? 4 : 18),
                      ),
                      border: isMine
                          ? null
                          : Border.all(color: NOC.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isPinned)
                           Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.push_pin,
                                size: 12,
                                color: NOC.accent,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'PINNED',
                                style: TextStyle(
                                  color: NOC.accent,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        if (isImage) ...[
                          GestureDetector(
                            onTap: onAttachmentTap,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                attachmentUrl!,
                                width: 220,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    SizedBox(
                                  width: 220,
                                  height: 120,
                                  child: Center(
                                    child: Text(
                                      'Photo',
                                      style: TextStyle(
                                        color: isMine
                                            ? NOC.textMuted
                                            : NOC.textMuted,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                        ] else if (isFile) ...[
                          GestureDetector(
                            onTap: onAttachmentTap,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isVideoAttachment
                                        ? Icons.play_circle_outline
                                        : Icons.description_outlined,
                                    color: NOC.accent,
                                    size: 26,
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          content.isEmpty
                                              ? (isVideoAttachment
                                                  ? 'Video attachment'
                                                  : 'Document')
                                              : content,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: NOC.text,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          isVideoAttachment
                                              ? 'Video · tap to play'
                                              : 'Document · tap to open',
                                          style: TextStyle(
                                            color: NOC.textMuted,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                        ] else
                          Text(
                            content,
                            style:  TextStyle(
                              color: NOC.text,
                              fontSize: 15,
                              height: 1.4,
                            ),
                          ),
                        const SizedBox(height: 3),
                        Text(
                          time,
                          style:  TextStyle(
                            color: NOC.textFaint,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!isMine) _buildReactionButton(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReactionButton() {
    final reactionTap = onReactionTap;
    if (reactionTap == null) return const SizedBox(width: 8);
    return GestureDetector(
      onTap: reactionTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: reactedByMe
              ? NOC.accent.withOpacity(0.15)
              : NOC.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: reactedByMe
                ? NOC.accent.withOpacity(0.5)
                : NOC.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              reactedByMe ? Icons.favorite : Icons.favorite_border,
              size: 14,
              color: reactedByMe
                  ? NOC.danger
                  : NOC.textMuted,
            ),
            if (reactionCount > 0) ...[
              const SizedBox(width: 3),
              Text(
                '$reactionCount',
                style: TextStyle(
                  color: reactedByMe
                      ? NOC.danger
                      : NOC.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
