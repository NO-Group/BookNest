import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/theme.dart';
import '../../config/locales.dart';
import '../../services/reader_profile.dart';
import '../screens/chat/voice_recorder_sheet.dart';
import '../screens/chat/camera_screen.dart';
import '../screens/chat/file_picker_screen.dart';
import '../screens/chat/media_viewer_screen.dart';
import '../../services/backend_api.dart';
import '../../services/cloudinary_service.dart';
import '../../services/supabase_service.dart';
import 'booknest_ui.dart';
import 'booknest_emojis.dart';
import 'booknest_keyboard.dart';
import 'watermark_background.dart';

/// Shared chat kit — one messaging language across 1:1 and club chats.
/// Original BookNest styling: navy/cyan glass bubbles on the watermark
/// canvas, delivery ticks, day separators and a Cloudinary-backed photo
/// composer. Built to feel as immediate as the best chat apps, without
/// copying any of them.

// ── Time helpers ─────────────────────────────────────────────────────────────

/// Normalises the wire formats a message timestamp arrives in.
DateTime? chatTimestamp(dynamic value) {
  if (value is DateTime) return value.toLocal();
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toLocal();
  }
  return null;
}

String chatTimeLabel(dynamic timestamp) {
  final time = chatTimestamp(timestamp);
  return time == null ? '' : DateFormat('HH:mm').format(time);
}

String chatDayLabel(dynamic timestamp) {
  final time = chatTimestamp(timestamp);
  if (time == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (now.year == time.year) return DateFormat('d MMM').format(time);
  return DateFormat('d MMM, yyyy').format(time);
}

/// Interleaves day separators into a message stream.
/// Returns `String` date labels mixed with the original message maps.
List<Object> withDaySeparators(List<Map<String, dynamic>> messages) {
  final rows = <Object>[];
  String? lastDay;
  for (final message in messages) {
    final day = chatDayLabel(message['createdAt']);
    if (day.isNotEmpty && day != lastDay) {
      rows.add(day);
      lastDay = day;
    }
    rows.add(message);
  }
  return rows;
}

/// Filters chat messages for the search bar: case-insensitive substring
/// match over the message text (and file names for documents).
List<Map<String, dynamic>> filterChatMessages(
    List<Map<String, dynamic>> messages, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return messages;
  return messages
      .where((m) =>
          (m['text']?.toString() ?? '').toLowerCase().contains(q) ||
          (m['fileName']?.toString() ?? '').toLowerCase().contains(q))
      .toList();
}

/// The slim search bar pinned above the message list while searching.
/// Type to filter the conversation live; the trailing count keeps it
/// honest about how much actually matched.
class ChatSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final int resultCount;
  final bool hasQuery;
  final VoidCallback onClose;
  final ValueChanged<String> onChanged;

  const ChatSearchBar({
    super.key,
    required this.controller,
    required this.resultCount,
    required this.hasQuery,
    required this.onClose,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: onSurface.withOpacity(.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: BookNestColors.cyan.withOpacity(.35)),
      ),
      child: Row(children: [
        const Icon(Icons.search_rounded, size: 19, color: BookNestColors.cyan),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: onChanged,
            style: TextStyle(fontSize: 14, color: onSurface),
            decoration: const InputDecoration(
              hintText: 'Search this chat…',
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
        if (hasQuery)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text('$resultCount',
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: BookNestColors.cyan)),
          ),
        InkWell(
          onTap: onClose,
          borderRadius: BorderRadius.circular(20),
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.close_rounded, size: 18),
          ),
        ),
      ]),
    );
  }
}

// ── Watermark chat scaffold ──────────────────────────────────────────────────

/// Standard chat page background: the watermark canvas over the chat color.
class ChatCanvas extends StatelessWidget {
  final Widget child;
  const ChatCanvas({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: dark ? BookNestColors.darkChatBackground : BookNestColors.lightSurface,
      child: WatermarkBackground(
        opacity: dark ? 0.10 : 0.09,
        child: child,
      ),
    );
  }
}

// ── Bubbles ──────────────────────────────────────────────────────────────────

/// A single chat message. Knows about real read receipts (the blue
/// ticks light up only when someone actually read it), reactions,
/// forwarding, deletes and emote messages — and opens the message
/// toolkit on long-press.
class ChatBubble extends StatefulWidget {
  final Map<String, dynamic> message;
  final bool mine;

  /// Group chats show a name above other people's messages. Tapping it
  /// opens that reader's profile.
  final String? senderName;
  final String? senderId;
  final String viewerId;
  final VoidCallback? onOpenBook;
  final VoidCallback? onOpenImage;
  final VoidCallback? onOpenFile;
  final ValueChanged<String>? onReact;
  final VoidCallback? onForward;
  final VoidCallback? onInfo;
  final VoidCallback? onDeleteForMe;
  final VoidCallback? onDeleteForEveryone;

  /// Triple-tap: translate the message into the reader's preferred
  /// language.
  final VoidCallback? onTranslate;

  /// Swipe the bubble toward the center — replies to the message.
  final VoidCallback? onReply;

  /// Report this message to the moderators.
  final VoidCallback? onReport;

  /// Pin (or unpin) this message in the room — owners and deputies only.
  final VoidCallback? onPin;

  /// Whether this message is currently the room's pinned one.
  final bool isPinned;

  const ChatBubble({
    super.key,
    required this.message,
    required this.mine,
    this.viewerId = '',
    this.senderName,
    this.senderId,
    this.onOpenBook,
    this.onOpenImage,
    this.onOpenFile,
    this.onReact,
    this.onForward,
    this.onInfo,
    this.onDeleteForMe,
    this.onDeleteForEveryone,
    this.onTranslate,
    this.onReply,
    this.onReport,
    this.onPin,
    this.isPinned = false,
  });

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    value: 1,
  );

  // Double-tap = heart, triple-tap = translate. Taps are counted and
  // resolved when a short window closes, so a third tap converts a
  // heart into a translation instead of firing both.
  int _tapStreak = 0;
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _tapTimer;

  @override
  void dispose() {
    _tapTimer?.cancel();
    _burst.dispose();
    super.dispose();
  }

  void _countTap() {
    final now = DateTime.now();
    _tapStreak =
        now.difference(_lastTap).inMilliseconds < 450 ? _tapStreak + 1 : 1;
    _lastTap = now;
    if (_pending || _failed) return;
    _tapTimer?.cancel();
    _tapTimer = Timer(const Duration(milliseconds: 330), () {
      final taps = _tapStreak;
      _tapStreak = 0;
      if (taps == 2) {
        _fireBurst();
      } else if (taps >= 3) {
        widget.onTranslate?.call();
      }
    });
  }

  bool get _pending => widget.message['pending'] == true;
  bool get _failed => widget.message['failed'] == true;
  bool get _deletedForEveryone => widget.message['deletedForEveryone'] == true;
  String get _type =>
      _deletedForEveryone ? 'deleted' : (widget.message['type']?.toString() ?? 'text');
  String get _text => widget.message['text']?.toString() ?? '';
  String get _mediaUrl => widget.message['mediaUrl']?.toString() ?? '';
  bool get _isMine => widget.mine;

  /// The blue ticks. True only when someone OTHER than the sender has
  /// actually read this message on the server.
  bool get _readBySomeone {
    final readBy = widget.message['readBy'];
    if (readBy is! List) return false;
    return readBy.any((r) => r != null && r.toString() != widget.viewerId);
  }

  Map<String, int> get _reactionCounts {
    final raw = widget.message['reactions'];
    final counts = <String, int>{};
    if (raw is Map) {
      for (final e in raw.values) {
        final code = e?.toString() ?? '';
        if (code.isEmpty) continue;
        counts[code] = (counts[code] ?? 0) + 1;
      }
    }
    return counts;
  }

  bool _reactedByMe(String code) {
    final raw = widget.message['reactions'];
    if (raw is! Map) return false;
    return raw[widget.viewerId]?.toString() == code;
  }

  // ── Swipe-to-reply ──────────────────────────────────────────────────
  double _swipe = 0;

  /// +1 for bubbles on the left (drag right), −1 for mine (drag left).
  double get _swipeDir => widget.mine ? -1 : 1;

  void _onSwipeUpdate(DragUpdateDetails d) {
    if (widget.onReply == null) return;
    setState(() {
      final next = _swipe + d.delta.dx * _swipeDir;
      _swipe = next.clamp(0.0, 88.0);
    });
  }

  void _onSwipeEnd(DragEndDetails d) {
    if (widget.onReply == null) return;
    if (_swipe >= 56) {
      HapticFeedback.mediumImpact();
      widget.onReply!();
    }
    setState(() => _swipe = 0);
  }

  void _fireBurst() {
    _burst.forward(from: 0);
    widget.onReact?.call(doubleTapReactionCode);
  }

  void _showToolkit() {
    final canAct = !_pending && !_failed && !_deletedForEveryone;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onReact != null && canAct) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final code in quickReactionCodes)
                      InkWell(
                        borderRadius: BorderRadius.circular(30),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          widget.onReact?.call(code);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: BookNestEmojiView(code, size: 34, animate: true),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
            ],
            if (widget.onForward != null && canAct)
              ListTile(
                leading: const Icon(Icons.shortcut_rounded,
                    color: BookNestColors.cyan),
                title: const Text('Forward',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onForward?.call();
                },
              ),
            if (widget.onReport != null && canAct)
              ListTile(
                leading: const Icon(Icons.flag_rounded, color: Colors.redAccent),
                title: const Text('Report message',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onReport?.call();
                },
              ),
            if (widget.onInfo != null && canAct)
              ListTile(
                leading: const Icon(Icons.info_outline_rounded,
                    color: BookNestColors.cyan),
                title: const Text('Message info',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onInfo?.call();
                },
              ),
            if (widget.onDeleteForMe != null && canAct)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: BookNestColors.cyan),
                title: const Text('Delete for me',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onDeleteForMe?.call();
                },
              ),
            if (widget.onPin != null && canAct)
              ListTile(
                leading: Icon(
                    widget.isPinned
                        ? Icons.push_pin_outlined
                        : Icons.push_pin_rounded,
                    color: BookNestColors.cyan),
                title: Text(
                    widget.isPinned ? 'Unpin from the chat' : 'Pin to the chat',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: BookNestColors.cyan)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onPin?.call();
                },
              ),
            if (widget.onDeleteForEveryone != null &&
                canAct &&
                _isMine &&
                !_deletedForEveryone)
              ListTile(
                leading: const Icon(Icons.delete_forever_rounded,
                    color: Color(0xFFFF8A8A)),
                title: const Text('Delete for everyone',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: Color(0xFFFF8A8A))),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onDeleteForEveryone?.call();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _ticks(Color base, Color readColor) {
    if (!_isMine) return const SizedBox.shrink();
    if (_pending) {
      return Icon(Icons.schedule_rounded, size: 13, color: base);
    }
    if (_failed) {
      return const Icon(Icons.error_outline_rounded,
          size: 13, color: Color(0xFFFF8A8A));
    }
    if (_readBySomeone) {
      return Icon(Icons.done_all_rounded, size: 13, color: readColor);
    }
    return Icon(Icons.done_rounded, size: 13, color: base);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final mine = widget.mine;

    final Widget content;
    if (_type == 'deleted') {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block_rounded,
              size: 13,
              color: mine
                  ? Colors.white54
                  : (dark ? Colors.white38 : BookNestColors.navyDeep.withOpacity(.45))),
          const SizedBox(width: 6),
          Text(
            'This message was deleted',
            style: TextStyle(
              fontStyle: FontStyle.italic,
              fontSize: 13.5,
              color: mine
                  ? Colors.white54
                  : (dark ? Colors.white38 : BookNestColors.navyDeep.withOpacity(.45)),
            ),
          ),
        ],
      );
    } else if (_type == 'emoji' && _text.isNotEmpty) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: BookNestEmojiView(_text, size: 72, animate: true),
      );
    } else if (_type == 'video' &&
        _mediaUrl.startsWith('http') &&
        !_deletedForEveryone) {
      // Our own player — videos play right inside the chat.
      content = _VideoContent(url: _mediaUrl, dark: dark);
    } else if (_type == 'image' &&
        _mediaUrl.startsWith('http') &&
        !_deletedForEveryone) {
      content = _ImageContent(url: _mediaUrl, onTap: widget.onOpenImage);
    } else if (_type == 'file' &&
        _mediaUrl.startsWith('http') &&
        !_deletedForEveryone) {
      content = _FileContent(
        url: _mediaUrl,
        dark: dark,
        name: (widget.message['fileName']?.toString().isNotEmpty == true)
            ? widget.message['fileName'].toString()
            : _text,
        fileSize: (widget.message['fileSize'] as num?)?.toInt(),
        onTap: widget.onOpenFile,
      );
    } else if (_type == 'book_share' && !_deletedForEveryone) {
      content = _BookShareContent(
        title: _text,
        onOpen: widget.onOpenBook,
        dark: dark,
      );
    } else {
      content = Text(
        _text,
        style: TextStyle(
          color: mine
              ? Colors.white
              : (dark ? BookNestColors.darkTextPrimary : BookNestColors.navyDeep),
          height: 1.35,
          fontSize: 15,
        ),
      );
    }

    final bubble = Container(
      margin: EdgeInsets.only(
        top: 3,
        bottom: 3,
        left: mine ? 48 : 0,
        right: mine ? 0 : 48,
      ),
      padding: (_type == 'book_share' || _type == 'file')
          ? const EdgeInsets.all(10)
          : (_type == 'image' || _type == 'video'
              ? const EdgeInsets.all(4)
              : const EdgeInsets.fromLTRB(13, 8, 13, 6)),
      constraints:
          BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
      decoration: BoxDecoration(
        gradient: mine
            ? const LinearGradient(
                colors: [Color(0xFF0E2A57), BookNestColors.navyDeep],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: mine
            ? null
            : (dark ? BookNestColors.darkReceivedMessage : Colors.white),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(mine ? 18 : 4),
          bottomRight: Radius.circular(mine ? 4 : 18),
        ),
        border: mine
            ? Border.all(color: Colors.white.withOpacity(.06))
            : Border.all(color: BookNestColors.cyan.withOpacity(.22)),
        boxShadow: [
          BoxShadow(
            color: BookNestColors.navyDeep.withOpacity(dark ? .28 : .10),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine &&
              !_deletedForEveryone &&
              widget.senderName != null &&
              widget.senderName!.isNotEmpty &&
              _type != 'book_share') ...[
            GestureDetector(
              onTap: () {
                final id = widget.senderId;
                if (id != null && id.isNotEmpty) context.push('/user/$id');
              },
              child: Text(
                widget.senderName!,
                style: TextStyle(
                  color: BookNestColors.cyan,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  decoration:
                      widget.senderId == null ? null : TextDecoration.underline,
                  decorationColor: BookNestColors.cyan.withOpacity(.5),
                ),
              ),
            ),
            const SizedBox(height: 2),
          ],
          if (widget.message['forwarded'] == true && !_deletedForEveryone) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shortcut_rounded,
                    size: 12,
                    color: mine
                        ? Colors.white.withOpacity(.65)
                        : BookNestColors.cyan),
                const SizedBox(width: 4),
                Text(
                  'Forwarded',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w600,
                      color: mine
                          ? Colors.white.withOpacity(.65)
                          : BookNestColors.cyan),
                ),
              ],
            ),
            const SizedBox(height: 2),
          ],
          content,
          if (_type != 'image') ...[
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_failed)
                  const Icon(Icons.error_outline_rounded,
                      size: 11, color: Color(0xFFFF8A8A)),
                Text(
                  chatTimeLabel(widget.message['createdAt']),
                  style: TextStyle(
                    fontSize: 10,
                    color: mine
                        ? Colors.white.withOpacity(.65)
                        : (dark
                            ? Colors.white.withOpacity(.45)
                            : BookNestColors.navyDeep.withOpacity(.5)),
                  ),
                ),
                if (mine) ...[
                  const SizedBox(width: 4),
                  _ticks(
                    Colors.white.withOpacity(.55),
                    BookNestColors.cyan,
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );

    final bubbleStack = _type == 'image' && !_deletedForEveryone
        ? Stack(
            children: [
              bubble,
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(.45),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(chatTimeLabel(widget.message['createdAt']),
                          style:
                              const TextStyle(fontSize: 10, color: Colors.white)),
                      if (mine) ...[
                        const SizedBox(width: 4),
                        _ticks(Colors.white.withOpacity(.6), BookNestColors.cyan),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          )
        : bubble;

    final reactions = _reactionCounts;
    final hasReactions = reactions.isNotEmpty && !_deletedForEveryone;

    final replyStrip = widget.message['replyTo'] is Map
        ? _ReplyStrip(
            replyTo: widget.message['replyTo'] as Map,
            mine: mine,
            dark: dark,
          )
        : null;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Listener(
        onPointerUp: (_) => _countTap(),
        child: GestureDetector(
        onHorizontalDragUpdate: widget.onReply != null ? _onSwipeUpdate : null,
        onHorizontalDragEnd: widget.onReply != null ? _onSwipeEnd : null,
        onLongPress: _showToolkit,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment:
                  mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (replyStrip != null) replyStrip,
                Transform.translate(
                  offset: Offset(_swipe * _swipeDir, 0),
                  child: bubbleStack,
                ),
                if (hasReactions)
                  Padding(
                    padding:
                        const EdgeInsets.only(top: 2, bottom: 3, left: 4, right: 4),
                    child: Wrap(
                      spacing: 5,
                      children: [
                        for (final entry in reactions.entries)
                          InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: widget.onReact == null
                                ? null
                                : () => widget.onReact!(entry.key),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: _reactedByMe(entry.key)
                                    ? BookNestColors.cyan.withOpacity(.18)
                                    : (dark
                                        ? Colors.white.withOpacity(.07)
                                        : BookNestColors.navyDeep.withOpacity(.06)),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _reactedByMe(entry.key)
                                      ? BookNestColors.cyan
                                      : (dark
                                          ? Colors.white.withOpacity(.12)
                                          : BookNestColors.navyDeep
                                              .withOpacity(.12)),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  BookNestEmojiView(entry.key,
                                      size: 15, animate: true),
                                  if (entry.value > 1) ...[
                                    const SizedBox(width: 4),
                                    Text(
                                      '${entry.value}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: dark
                                              ? Colors.white70
                                              : BookNestColors.navyDeep),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
            // Reply arrow revealed by the swipe.
            if (_swipe > 6)
              Positioned(
                top: 0,
                bottom: 0,
                left: mine ? 0 : null,
                right: mine ? null : 0,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: (_swipe / 56).clamp(0.0, 1.0),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: BookNestColors.cyan.withOpacity(.16),
                        border: Border.all(
                            color: BookNestColors.cyan.withOpacity(.5)),
                      ),
                      child: Icon(
                        mine
                            ? Icons.reply_rounded
                            : Icons.shortcut_rounded,
                        color: BookNestColors.cyan,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
            // Double-tap love burst.
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: FadeTransition(
                    opacity: Tween<double>(begin: 1, end: 0).animate(
                        CurvedAnimation(
                            parent: _burst, curve: const Interval(.35, 1))),
                    child: ScaleTransition(
                      scale: Tween<double>(begin: .5, end: 1.7).animate(
                          CurvedAnimation(parent: _burst, curve: Curves.easeOut)),
                      child: const BookNestEmojiView('heart',
                          size: 46, animate: false),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// Reply preview pinned above the input while composing.
class _ComposerReplyBar extends StatelessWidget {
  final Map<String, dynamic> message;
  final VoidCallback? onCancel;
  final bool dark;
  const _ComposerReplyBar(
      {required this.message, required this.dark, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final type = message['type']?.toString() ?? 'text';
    final preview = switch (type) {
      'image' => '📷 Photo',
      'video' => '🎬 Video',
      'voice' => '🎤 Voice message',
      'file' => message['fileName']?.toString() ?? 'File',
      'emoji' => 'BookNest emote',
      'book_share' => message['bookTitle']?.toString() ?? 'Book',
      _ => message['text']?.toString() ?? '',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: dark
            ? Colors.white.withOpacity(.06)
            : BookNestColors.navyDeep.withOpacity(.05),
        border: const Border(
            left: BorderSide(color: BookNestColors.cyan, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Replying',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: BookNestColors.cyan)),
                const SizedBox(height: 2),
                Text(
                  preview.isEmpty ? 'Message' : preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      color: dark
                          ? Colors.white.withOpacity(.75)
                          : BookNestColors.navyDeep.withOpacity(.75)),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            color: dark ? Colors.white54 : BookNestColors.navyDeep.withOpacity(.55),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

/// The quoted strip shown above a reply — who answered what.
class _ReplyStrip extends StatelessWidget {
  final Map<dynamic, dynamic> replyTo;
  final bool mine;
  final bool dark;
  const _ReplyStrip(
      {required this.replyTo, required this.mine, required this.dark});

  @override
  Widget build(BuildContext context) {
    final text = replyTo['text']?.toString() ?? '';
    return Container(
      margin: EdgeInsets.only(
          bottom: 2, left: mine ? 48 : 2, right: mine ? 2 : 48),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: dark
            ? Colors.white.withOpacity(.05)
            : BookNestColors.navyDeep.withOpacity(.05),
        border: Border(
          left: BorderSide(
              color: BookNestColors.cyan, width: 2.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.reply_rounded,
              size: 13,
              color: BookNestColors.cyan.withOpacity(.9)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text.isEmpty ? 'Media message' : text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontStyle: FontStyle.italic,
                color: dark
                    ? Colors.white.withOpacity(.65)
                    : BookNestColors.navyDeep.withOpacity(.65),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// BookNest's own in-chat video player: tap to play and pause, a
/// scrubber, mute, and an in-app fullscreen theater. Videos never leave
/// the app.
class _VideoContent extends StatefulWidget {
  final String url;
  final bool dark;
  const _VideoContent({required this.url, required this.dark});
  @override
  State<_VideoContent> createState() => _VideoContentState();
}

class _VideoContentState extends State<_VideoContent> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
      }).catchError((_) {
        if (mounted) setState(() => _failed = true);
      });
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width * .72)
        .clamp(220.0, 340.0);
    final aspect = _ready && _controller.value.aspectRatio > 0
        ? _controller.value.aspectRatio
        : 16 / 9;
    return GestureDetector(
      onTap: () {
        if (!_ready) return;
        setState(() {
          _controller.value.isPlaying
              ? _controller.pause()
              : _controller.play();
        });
      },
      onDoubleTap: _ready
          ? () => _openFullscreen(context)
          : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: width,
          color: BookNestColors.navyDeep,
          child: AspectRatio(
            aspectRatio: aspect,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_ready)
                  VideoPlayer(_controller)
                else if (_failed)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_off_rounded,
                          color: Colors.white54, size: 30),
                      const SizedBox(height: 6),
                      Text('Video unavailable',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(.7))),
                      const SizedBox(height: 14),
                    ],
                  )
                else
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: BookNestColors.cyan),
                  ),
                if (_ready && !_controller.value.isPlaying)
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: BookNestColors.navyDeep.withOpacity(.55),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 34),
                  ),
                if (_ready)
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 8,
                    child: Row(
                      children: [
                        ValueListenableBuilder<VideoPlayerValue>(
                          valueListenable: _controller,
                          builder: (context, value, _) => Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: value.duration.inMilliseconds == 0
                                    ? 0
                                    : value.position.inMilliseconds /
                                        value.duration.inMilliseconds,
                                minHeight: 3.5,
                                backgroundColor: Colors.white24,
                                valueColor: const AlwaysStoppedAnimation(
                                    BookNestColors.cyan),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => setState(() {
                            _controller.value.volume > 0
                                ? _controller.setVolume(0)
                                : _controller.setVolume(1);
                          }),
                          child: Icon(
                            _controller.value.volume > 0
                                ? Icons.volume_up_rounded
                                : Icons.volume_off_rounded,
                            color: Colors.white.withOpacity(.85),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => _openFullscreen(context),
                          child: const Icon(Icons.fullscreen_rounded,
                              color: Colors.white, size: 20),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openFullscreen(BuildContext context) {
    if (!_ready) return;
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) => _VideoFullscreen(controller: _controller),
    ));
  }
}

/// In-app fullscreen theater for chat videos — never an external app.
class _VideoFullscreen extends StatefulWidget {
  final VideoPlayerController controller;
  const _VideoFullscreen({required this.controller});
  @override
  State<_VideoFullscreen> createState() => _VideoFullscreenState();
}

class _VideoFullscreenState extends State<_VideoFullscreen> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    widget.controller.play();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: widget.controller.value.aspectRatio == 0
                    ? 16 / 9
                    : widget.controller.value.aspectRatio,
                child: VideoPlayer(widget.controller),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 24,
              child: Row(
                children: [
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: widget.controller,
                    builder: (context, value, _) {
                      final total = value.duration.inSeconds;
                      final pos = value.position.inSeconds;
                      return Expanded(
                        child: Row(
                          children: [
                            Text('$pos:$total'.replaceAllMapped(
                                RegExp(r'^(\d+):(\d+)$'), (m) =>
                                    '${m[1]!.padLeft(2, '0')}:${m[2]!.padLeft(2, '0')}'),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: VideoProgressIndicator(
                                widget.controller,
                                allowScrubbing: true,
                                colors: const VideoProgressColors(
                                  playedColor: BookNestColors.cyan,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    icon: ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: widget.controller,
                      builder: (context, value, _) => Icon(
                        value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                      ),
                    ),
                    onPressed: () => setState(() {
                      widget.controller.value.isPlaying
                          ? widget.controller.pause()
                          : widget.controller.play();
                    }),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageContent extends StatelessWidget {
  final String url;
  final VoidCallback? onTap;
  const _ImageContent({required this.url, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * .72,
            maxHeight: 320,
          ),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Container(
                width: 220,
                height: 160,
                color: Colors.white.withOpacity(.05),
                child: const Center(
                  child: CircularProgressIndicator(
                      color: BookNestColors.cyan, strokeWidth: 2),
                ),
              );
            },
            errorBuilder: (_, __, ___) => Container(
              width: 220,
              height: 120,
              color: Colors.white.withOpacity(.05),
              child: const Icon(Icons.broken_image_outlined,
                  color: BookNestColors.cyan),
            ),
          ),
        ),
      ),
    );
  }
}

/// An attachment chip for any file type — tap to open or download.
class _FileContent extends StatelessWidget {
  final String url;
  final bool dark;
  final VoidCallback? onTap;
  final String? name;
  final int? fileSize;
  const _FileContent({
    required this.url,
    required this.dark,
    this.onTap,
    this.name,
    this.fileSize,
  });

  String get _name {
    final given = name?.trim() ?? '';
    if (given.isNotEmpty) return given;
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      if (segments.isNotEmpty) {
        final last = Uri.decodeComponent(segments.last);
        final dot = last.indexOf('.', last.indexOf('/') == -1 ? 0 : last.length - 8);
        final clean = last.contains('/') ? last.split('/').last : last;
        // Cloudinary appends an extension: 'invoice1234.pdf' stays, hashed
        // ids keep their extension too — show as-is, minus version suffix.
        return clean.replaceAll(RegExp(r'\.[a-z0-9]{6,8}$'), '');
      }
    } catch (_) {}
    return 'Attachment';
  }

  String get _extension {
    final match = RegExp(r'\.([a-z0-9]{2,5})(?:\?|$)').firstMatch(url);
    return (match?.group(1) ?? 'file').toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: dark ? Colors.white.withOpacity(.06) : Colors.white,
          border: Border.all(color: BookNestColors.cyan.withOpacity(.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(
                  colors: [BookNestColors.navy, BookNestColors.navyDeep],
                ),
              ),
              child: Text(
                _extension.characters.take(4).toString(),
                style: const TextStyle(
                  color: BookNestColors.cyan,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: dark ? BookNestColors.darkTextPrimary : BookNestColors.navyDeep,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.open_in_full_rounded,
                          size: 11, color: BookNestColors.cyan),
                      const SizedBox(width: 4),
                      Text(
                        'View in BookNest',
                        style: TextStyle(
                          fontSize: 11,
                          color: BookNestColors.cyan,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookShareContent extends StatelessWidget {
  final String title;
  final VoidCallback? onOpen;
  final bool dark;
  const _BookShareContent({
    required this.title,
    required this.onOpen,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: dark ? Colors.white.withOpacity(.06) : Colors.white,
          border: Border.all(color: BookNestColors.cyan.withOpacity(.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: const LinearGradient(
                  colors: [BookNestColors.navy, BookNestColors.navyDeep],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Icon(Icons.auto_stories_rounded,
                  color: BookNestColors.cyan, size: 20),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Shared a book',
                    style: TextStyle(
                      fontSize: 11,
                      color: BookNestColors.cyan,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title.isEmpty ? 'Open in BookNest' : title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: dark ? BookNestColors.darkTextPrimary : BookNestColors.navyDeep,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: BookNestColors.cyan),
          ],
        ),
      ),
    );
  }
}

// ── Day chip ─────────────────────────────────────────────────────────────────

class ChatDayChip extends StatelessWidget {
  final String label;
  const ChatDayChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: dark ? Colors.white.withOpacity(.07) : BookNestColors.navyDeep.withOpacity(.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: dark ? Colors.white.withOpacity(.08) : BookNestColors.navyDeep.withOpacity(.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: dark ? BookNestColors.darkTextPrimary.withOpacity(.85) : BookNestColors.navyDeep,
          ),
        ),
      ),
    );
  }
}

// ── Triple-tap translation ───────────────────────────────────────────────────

/// Translates [text] into [target] and shows the result in a sheet.
Future<void> showMessageTranslation(
  BuildContext context,
  Map<String, dynamic> message, {
  required String target,
}) async {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final text = message['text']?.toString() ?? '';
  if (text.trim().isEmpty ||
      (message['type']?.toString() == 'emoji' && message['animated'] == true)) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('There is nothing to translate in that message.')));
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: FutureBuilder<Map<String, dynamic>?>(
          future: BackendApi.instance.translateText(text, target),
          builder: (context, snap) {
            final translated =
                snap.data?['translated']?.toString();
            final detected =
                snap.data?['detectedLanguage']?.toString();
            final targetName =
                languageNameFor(target) ?? target.toUpperCase();
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.translate_rounded,
                        size: 18, color: BookNestColors.cyan),
                    const SizedBox(width: 8),
                    Text('Translated to $targetName',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color:
                                dark ? Colors.white : BookNestColors.navyDeep)),
                  ]),
                  const SizedBox(height: 14),
                  if (snap.connectionState != ConnectionState.done)
                    const Center(
                        child: Padding(
                      padding: EdgeInsets.all(18),
                      child: CircularProgressIndicator(
                          color: BookNestColors.cyan),
                    ))
                  else if (translated == null || translated.isEmpty)
                    Text(
                      'This could not be translated right now — please try again in a moment.',
                      style: TextStyle(
                          fontSize: 13.5,
                          height: 1.45,
                          color: dark ? Colors.white70 : BookNestColors.navyDeep),
                    )
                  else ...[
                    if (detected != null && detected != target)
                      Text(
                        'Original (${languageNameFor(detected) ?? detected.toUpperCase()})',
                        style: TextStyle(
                            fontSize: 10.5,
                            letterSpacing: .8,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(sheetContext).hintColor),
                      ),
                    if (detected != null && detected != target) ...[
                      const SizedBox(height: 4),
                      Text(text,
                          style: TextStyle(
                              fontSize: 13.5,
                              height: 1.45,
                              color: dark
                                  ? Colors.white54
                                  : BookNestColors.navyDeep.withOpacity(.7))),
                      const SizedBox(height: 12),
                    ],
                    Text(translated,
                        style: TextStyle(
                            fontSize: 15.5,
                            height: 1.5,
                            fontWeight: FontWeight.w600,
                            color:
                                dark ? Colors.white : BookNestColors.navyDeep)),
                  ],
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

// ── Badged avatar: country flag on top, gender underneath ────────────────────

class BadgedAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double radius;
  final String? countryCode;
  final String? gender;

  /// Tapping the picture opens the full-screen view.
  final VoidCallback? onTap;

  const BadgedAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.radius = 20,
    this.countryCode,
    this.gender,
    this.onTap,
  });

  IconData? get _genderIcon {
    switch (gender) {
      case 'female':
        return Icons.female_rounded;
      case 'male':
        return Icons.male_rounded;
      case 'nonbinary':
        return Icons.transgender_rounded;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final flag = countryCode == null ? null : flagForCountry(countryCode!);
    final countryName =
        countryCode == null ? null : countryNameFor(countryCode!);
    final icon = _genderIcon;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (flag != null)
          Tooltip(
            message: countryName ?? 'Country',
            triggerMode: TooltipTriggerMode.tap,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(flag, style: const TextStyle(fontSize: 12)),
            ),
          )
        else
          const SizedBox(height: 14),
        GestureDetector(
          onTap: (onTap != null && (imageUrl?.isNotEmpty ?? false))
              ? onTap
              : null,
          child: ChatAvatar(name: name, imageUrl: imageUrl, radius: radius),
        ),
        if (icon != null)
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dark ? Colors.white.withOpacity(.08) : Colors.white,
              border: Border.all(
                  color: BookNestColors.cyan.withOpacity(.5), width: .8),
            ),
            child: Icon(icon, size: 10, color: BookNestColors.cyan),
          )
        else
          const SizedBox(height: 14),
      ],
    );
  }
}

// ── Forward picker + message info (shared by DM and club chats) ─────────────

class ForwardTarget {
  final String conversationId;
  final String title;
  final bool isClub;
  const ForwardTarget({
    required this.conversationId,
    required this.title,
    required this.isClub,
  });
}

/// The forward picker: every DM and every group room the reader is in.
Future<void> showForwardPicker(
  BuildContext context, {
  required Future<void> Function(ForwardTarget target) onDeliver,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final dark = Theme.of(sheetContext).brightness == Brightness.dark;
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .68,
          child: FutureBuilder<List<ForwardTarget>>(
            future: _loadForwardTargets(),
            builder: (context, snap) {
              final targets = snap.data;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                    child: Row(
                      children: [
                        Text('Forward to',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: dark ? Colors.white : BookNestColors.navyDeep)),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: Theme.of(sheetContext).dividerColor),
                  Expanded(
                    child: snap.connectionState != ConnectionState.done
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: BookNestColors.cyan))
                        : (targets == null || targets.isEmpty)
                            ? Center(
                                child: Text(
                                  'No chats to forward to yet.',
                                  style: TextStyle(
                                      color: dark ? Colors.white54 : null),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                itemCount: targets.length,
                                itemBuilder: (context, i) {
                                  final t = targets[i];
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: BookNestColors.cyan
                                          .withOpacity(.15),
                                      child: Icon(
                                        t.isClub
                                            ? Icons.groups_rounded
                                            : Icons.person_rounded,
                                        color: BookNestColors.cyan,
                                        size: 20,
                                      ),
                                    ),
                                    title: Text(t.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: dark
                                                ? Colors.white
                                                : BookNestColors.navyDeep)),
                                    subtitle: Text(
                                        t.isClub ? 'Group chat' : 'Direct message',
                                        style: const TextStyle(fontSize: 11.5)),
                                    trailing: const Icon(Icons.shortcut_rounded,
                                        color: BookNestColors.cyan),
                                    onTap: () {
                                      Navigator.pop(sheetContext);
                                      onDeliver(t);
                                    },
                                  );
                                },
                              ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}

Future<List<ForwardTarget>> _loadForwardTargets() async {
  final targets = <ForwardTarget>[];
  final dmRes = await BackendApi.instance.listConversations();
  final conversations =
      (dmRes?['conversations'] as List?) ?? const <Never>[];
  final dmIds = <String>[];
  for (final c in conversations) {
    if (c is Map && c['id'] != null) {
      dmIds.add(c['id'].toString());
      targets.add(ForwardTarget(
        conversationId: c['id'].toString(),
        title: 'Direct message',
        isClub: false,
      ));
    }
  }
  // Resolve the person behind each DM from the profiles table.
  try {
    if (dmIds.isNotEmpty) {
      final rows = await SupabaseService().client
          .from('profiles')
          .select('id, username, display_name')
          .inFilter('id', dmIds);
      final names = <String, String>{};
      for (final r in (rows as List)) {
        if (r is Map) {
          final id = r['id']?.toString() ?? '';
          final name = (r['display_name'] ?? r['username'])?.toString() ?? '';
          if (id.isNotEmpty && name.trim().isNotEmpty) names[id] = name.trim();
        }
      }
      for (var i = 0; i < targets.length; i++) {
        final conv = i < conversations.length ? conversations[i] : null;
        if (conv is Map) {
          final peer = conv['peerId']?.toString() ?? '';
          if (names[peer] != null) {
            targets[i] = ForwardTarget(
              conversationId: targets[i].conversationId,
              title: names[peer]!,
              isClub: false,
            );
          }
        }
      }
    }
  } catch (_) {
    // Names stay generic if profiles hiccup — forwarding still works.
  }
  final roomsRes = await BackendApi.instance.listClubChatRooms();
  final rooms = (roomsRes?['rooms'] as List?) ?? const <Never>[];
  for (final r in rooms) {
    if (r is Map && r['conversationId'] != null) {
      targets.add(ForwardTarget(
        conversationId: r['conversationId'].toString(),
        title: (r['title']?.toString().isNotEmpty == true)
            ? r['title'].toString()
            : 'Group chat',
        isClub: true,
      ));
    }
  }
  return targets;
}

/// The message info sheet: status, timestamps, receipts, reactions.
void showMessageInfo(
  BuildContext context,
  Map<String, dynamic> message, {
  String? viewerId,
  String? Function(String userId)? nameOf,
}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final readBy = (message['readBy'] is List)
      ? (message['readBy'] as List)
          .whereType<String>()
          .where((r) => r != (viewerId ?? ''))
          .toList()
      : <String>[];
  final mine = message['senderId']?.toString() == (viewerId ?? '');
  final reactions = <String, List<String>>{};
  final raw = message['reactions'];
  if (raw is Map) {
    for (final entry in raw.entries) {
      reactions
          .putIfAbsent(entry.value?.toString() ?? '', () => [])
          .add(entry.key?.toString() ?? '');
    }
  }
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      String labelOf(String uid) => nameOf?.call(uid) ?? 'Reader';
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Message info',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: dark ? Colors.white : BookNestColors.navyDeep)),
              const SizedBox(height: 14),
              if (mine)
                Row(children: [
                  Icon(
                    readBy.isEmpty
                        ? Icons.done_rounded
                        : Icons.done_all_rounded,
                    size: 18,
                    color: readBy.isEmpty
                        ? BookNestColors.navyDeep.withOpacity(.5)
                        : BookNestColors.cyan,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    readBy.isEmpty
                        ? 'Sent — not read yet'
                        : 'Read${readBy.length > 1 ? ' by ${readBy.length} readers' : ''}',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: dark ? Colors.white : BookNestColors.navyDeep),
                  ),
                ])
              else ...[
                Text('Delivered to you',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: dark ? Colors.white : BookNestColors.navyDeep)),
              ],
              const SizedBox(height: 10),
              Text(
                'Sent ${chatTimeLabel(message['createdAt'])}',
                style: TextStyle(
                    fontSize: 12.5,
                    color: dark ? Colors.white54 : BookNestColors.navyDeep.withOpacity(.6)),
              ),
              if ((message['type']?.toString() == 'file') &&
                  message['fileSize'] != null) ...[
                const SizedBox(height: 6),
                Text(
                  'File: ${message['fileName'] ?? 'attachment'} · '
                  '${((message['fileSize'] as num?)?.toInt() ?? 0) < 1024 * 1024 ? '${((message['fileSize'] as num?)!.toInt() / 1024).toStringAsFixed(0)} KB' : '${((message['fileSize'] as num?)!.toInt() / (1024 * 1024)).toStringAsFixed(1)} MB'}',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: dark ? Colors.white54 : BookNestColors.navyDeep.withOpacity(.6)),
                ),
              ],
              if (readBy.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('READ BY',
                    style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: .8,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).hintColor)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final uid in readBy)
                      Text(labelOf(uid),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: dark ? Colors.white70 : BookNestColors.navyDeep)),
                  ],
                ),
              ],
              if (reactions.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('REACTIONS',
                    style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: .8,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).hintColor)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    for (final entry in reactions.entries)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        BookNestEmojiView(entry.key, size: 20, animate: true),
                        const SizedBox(width: 5),
                        Text(
                          entry.value.map(labelOf).join(', '),
                          style: TextStyle(
                              fontSize: 12.5,
                              color: dark ? Colors.white70 : BookNestColors.navyDeep),
                        ),
                      ]),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

// ── Composer ─────────────────────────────────────────────────────────────────

class ChatComposer extends StatefulWidget {
  final String hint;
  final Future<void> Function(String text) onSendText;
  final Future<void> Function(Uint8List bytes, String extension) onSendImage;

  /// Any file format — invoked from the paperclip's "File" option.
  final Future<void> Function(String filename, Uint8List bytes)? onSendFile;

  /// The message being replied to — shown as a quote strip above the
  /// input, cleared by [onCancelReply].
  final Map<String, dynamic>? replyTo;
  final VoidCallback? onCancelReply;

  /// A clip recorded in the BookNest camera (local file path), with
  /// duration in seconds.
  final Future<void> Function(String videoPath, int seconds)? onSendVideo;

  /// The reader is typing — throttled ping for the typing indicator.
  final VoidCallback? onTyping;

  /// BookNest emote tapped on our own keyboard — sends instantly,
  /// Snapchat-style.
  final Future<void> Function(EmojiDef emote)? onSendEmote;
  final bool enabled;

  const ChatComposer({
    super.key,
    required this.onSendText,
    required this.onSendImage,
    this.onSendFile,
    this.onSendVideo,
    this.onSendEmote,
    this.hint = 'Message…',
    this.enabled = true,
    this.replyTo,
    this.onCancelReply,

    /// Fired (throttled inside) while the reader types — feeds the
    /// room's typing indicator.
    this.onTyping,
  });

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final TextEditingController _input = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  bool _uploading = false;
  bool _emotesOpen = false;
  String? _photoName;

  Future<void> _sendEmote(EmojiDef emote) async {
    if (_uploading || widget.onSendEmote == null) return;
    setState(() => _uploading = true);
    try {
      await widget.onSendEmote!(emote);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    var text = _input.text.trim();
    if (text.isEmpty || _uploading) return;
    // Keyboard translator: translate, then send the translation.
    final target = booknestTranslateTarget.value;
    if (target != null && target.isNotEmpty) {
      setState(() => _uploading = true);
      try {
        final res = await BackendApi.instance.translateText(text, target);
        final translated = res?['translated']?.toString();
        if (translated != null && translated.isNotEmpty) {
          text = translated;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    'Sent in ${languageNameFor(target) ?? target.toUpperCase()}')));
          }
        }
      } catch (_) {
        // Translation hiccup: the original words still go out.
      } finally {
        if (mounted) setState(() => _uploading = false);
      }
    }
    _input.clear();
    widget.onTyping?.call();
    await widget.onSendText(text);
  }

  Future<void> _attachFromGallery() async {
    if (_uploading) return;
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1600,
      );
      if (picked == null || !mounted) return;
      setState(() {
        _uploading = true;
        _photoName = picked.name;
      });
      final bytes = await picked.readAsBytes();
      await _rememberInRecents(
          picked.name.isNotEmpty ? picked.name : 'photo.jpg', bytes);
      final extension =
          picked.name.contains('.') ? picked.name.split('.').last.toLowerCase() : 'jpg';
      await widget.onSendImage(
        bytes,
        (extension == 'jpg' || extension == 'jpeg' ||
                extension == 'png' || extension == 'webp')
            ? extension
            : 'jpg',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('That photo could not be attached — please try another one.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Snap in the BookNest camera → polish in the studio → send.
  /// No hand-off to the phone's camera app, ever.
  Future<void> _snap() async {
    if (_uploading) return;
    try {
      final edited = await openBookNestCamera(context);
      if (!mounted || edited == null) return;
      setState(() {
        _uploading = true;
        _photoName = 'camera shot';
      });
      await _rememberInRecents('shot-${DateTime.now().millisecondsSinceEpoch}.png', edited);
      await widget.onSendImage(edited, 'png');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('The camera shot could not be attached — please try again.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Record inside the BookNest camera → upload → send as video.
  Future<void> _snapVideo() async {
    if (_uploading || widget.onSendVideo == null) return;
    String? path;
    try {
      path = await openBookNestCameraForVideo(context);
    } catch (_) {
      path = null;
    }
    if (!mounted || path == null || path.isEmpty) return;
    setState(() => _uploading = true);
    try {
      await widget.onSendVideo!(path, 0);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'The video could not be attached — please try again.')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Keeps a copy of outgoing media in the app cache so the custom file
  /// picker can offer it as a recent file next time.
  Future<void> _rememberInRecents(String name, Uint8List bytes) async {
    try {
      final dir = Directory(
          '${Directory.systemTemp.path}/booknest_files');
      await dir.create(recursive: true);
      await File('${dir.path}/$name').writeAsBytes(bytes, flush: true);
    } catch (_) {
      // Recents are a convenience — never block a send on them.
    }
  }

  /// Any file format, through the BookNest picker.
  Future<void> _attachFile() async {
    if (_uploading || widget.onSendFile == null) return;
    try {
      final choice = await pickBookNestFile(context);
      if (choice == null || !mounted) return;
      setState(() {
        _uploading = true;
        _photoName = choice.name;
      });
      await _rememberInRecents(choice.name, choice.bytes);
      await widget.onSendFile!(choice.name, choice.bytes);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('That file could not be attached — please try another one.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _openAttachSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                  color: BookNestColors.cyan),
              title: const Text('Camera',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Shoot inside BookNest, add filters',
                  style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(sheetContext);
                _snap();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: BookNestColors.cyan),
              title: const Text('Photo library',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Send a picture from your gallery',
                  style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(sheetContext);
                _attachFromGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.movie_creation_outlined,
                  color: BookNestColors.cyan),
              title: const Text('Video with sound',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Record inside BookNest — up to 60s',
                  style: TextStyle(fontSize: 12)),
              onTap: widget.onSendVideo == null
                  ? null
                  : () {
                      Navigator.pop(sheetContext);
                      _snapVideo();
                    },
            ),
            ListTile(
              leading: const Icon(Icons.mic_rounded,
                  color: BookNestColors.cyan),
              title: const Text('Voice message',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Hold to record — up to 2 minutes',
                  style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(sheetContext);
                showVoiceRecorder(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_rounded,
                  color: BookNestColors.cyan),
              title: const Text('Files',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Documents, PDFs, audio — up to 25 MB',
                  style: TextStyle(fontSize: 12)),
              onTap: widget.onSendFile == null
                  ? null
                  : () {
                      Navigator.pop(sheetContext);
                      _attachFile();
                    },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: booknestKeyboardEnabled,
      builder: (context, keyboardOn, _) => _buildComposer(context, keyboardOn),
    );
  }

  Widget _buildComposer(BuildContext context, bool keyboardOn) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: (dark ? BookNestColors.darkChatBackground : Colors.white).withOpacity(.97),
        border: Border(top: BorderSide(color: theme.dividerColor.withOpacity(.5))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.replyTo != null)
              _ComposerReplyBar(
                message: widget.replyTo!,
                onCancel: widget.onCancelReply,
                dark: dark,
              ),
            if (_emotesOpen && keyboardOn)
              BookNestKeyboard(
                preferredLanguage:
                    ReaderProfile.instance.preferredLanguage ?? 'en',
                onEmote: (e) {
                  FocusScope.of(context).unfocus();
                  _sendEmote(e);
                },
                onSystemEmoji: (emoji) async {
                  if (_uploading) return;
                  setState(() => _uploading = true);
                  try {
                    await widget.onSendText(emoji);
                  } finally {
                    if (mounted) setState(() => _uploading = false);
                  }
                },
                onVoiceText: (words) {
                  final current = _input.text;
                  _input.text = current.isEmpty ? words : '$current $words';
                  _input.selection =
                      TextSelection.collapsed(offset: _input.text.length);
                },
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _uploading
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: BookNestColors.cyan, strokeWidth: 2.2),
                        ),
                      )
                    : IconButton(
                        onPressed: widget.enabled ? _openAttachSheet : null,
                        icon: const Icon(Icons.attach_file_rounded),
                        color: BookNestColors.cyan,
                        tooltip: 'Attach',
                      ),
                if (!_uploading)
                  IconButton(
                    onPressed: widget.enabled ? _snap : null,
                    icon: const Icon(Icons.photo_camera_outlined),
                    color: BookNestColors.cyan,
                    tooltip: 'Camera',
                  ),
                if (!_uploading && widget.onSendEmote != null && keyboardOn)
                  IconButton(
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      setState(() => _emotesOpen = !_emotesOpen);
                    },
                    icon: Icon(_emotesOpen
                        ? Icons.keyboard_alt_outlined
                        : Icons.emoji_emotions_outlined),
                    color: _emotesOpen ? BookNestColors.cyan : BookNestColors.cyan,
                    tooltip: 'BookNest Emotes',
                  ),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: TextField(
                  controller: _input,
                  enabled: widget.enabled,
                  onChanged: (_) => widget.onTyping?.call(),
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: _uploading
                        ? 'Uploading ${_photoName ?? 'photo'}…'
                        : widget.hint,
                    filled: true,
                    fillColor: dark
                        ? BookNestColors.darkReceivedMessage
                        : BookNestColors.lightSurface,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
                const SizedBox(width: 6),
                IconButton.filled(
                  onPressed: widget.enabled ? _send : null,
                  icon: const Icon(Icons.send_rounded, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: BookNestColors.cyan,
                    foregroundColor: Colors.black,
                  ),
                  tooltip: 'Send',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared avatar ────────────────────────────────────────────────────────────

/// Small circular avatar for chat headers and group bubbles.
class ChatAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double radius;
  const ChatAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.radius = 17,
  });

  @override
  Widget build(BuildContext context) {
    return BookNestAvatar(imageUrl: imageUrl, name: name, radius: radius);
  }
}

/// Uploads any chat attachment (documents, audio, PDFs…) and returns the
/// hosted URL, or null when the upload could not complete.
Future<String?> uploadChatFile(String filename, Uint8List bytes) {
  return CloudinaryService.uploadRaw(bytes: bytes, filename: filename);
}

/// Uploads chat photos to Cloudinary under the chat folder and returns the
/// hosted URL, or null when the upload could not complete.
Future<String?> uploadChatImage(Uint8List bytes, String extension) {
  return CloudinaryService.uploadImage(
    bytes: bytes,
    folder: 'chat',
    extension: extension,
  );
}

/// Convenience: the signed-in reader's id ('' when signed out).
String get viewerId => SupabaseService().auth.currentUser?.id ?? '';

// ── Chat themes: WhatsApp-style wallpapers for every conversation ──────────

enum ChatWallPattern {
  none,
  dots,
  lines,
  grid,
  stars,
  hearts,
  waves,
  rings,
  sparkles,
  crosses,
  books,
}

class ChatVisualTheme {
  final String id;
  final String name;
  final int baseLight;
  final int baseDark;
  final int patternLight;
  final int patternDark;
  final ChatWallPattern pattern;

  const ChatVisualTheme({
    required this.id,
    required this.name,
    required this.baseLight,
    required this.baseDark,
    required this.patternLight,
    required this.patternDark,
    required this.pattern,
  });

  Color base(bool dark) => dark ? Color(baseDark) : Color(baseLight);
  Color patternColor(bool dark) =>
      dark ? Color(patternDark) : Color(patternLight);
}

/// Twelve designed wallpapers — the BookNest palette first, tasteful
/// companions after. 'classic' keeps the original watermark look.
const List<ChatVisualTheme> kChatThemes = [
  ChatVisualTheme(
      id: 'classic',
      name: 'Classic',
      baseLight: 0xFFFFFFFF,
      baseDark: 0xFF0A1220,
      patternLight: 0x00000000,
      patternDark: 0x00000000,
      pattern: ChatWallPattern.none),
  ChatVisualTheme(
      id: 'midnight',
      name: 'Midnight',
      baseLight: 0xFFE8EDF5,
      baseDark: 0xFF0B1626,
      patternLight: 0x229EB8D8,
      patternDark: 0x221E3A5C,
      pattern: ChatWallPattern.dots),
  ChatVisualTheme(
      id: 'mist',
      name: 'Cyan Mist',
      baseLight: 0xFFEAF6FA,
      baseDark: 0xFF0D1F2D,
      patternLight: 0x33B9E2F2,
      patternDark: 0x26274349,
      pattern: ChatWallPattern.lines),
  ChatVisualTheme(
      id: 'paper',
      name: 'Paper',
      baseLight: 0xFFFBFBF6,
      baseDark: 0xFF14202E,
      patternLight: 0x2E9DB8CD,
      patternDark: 0x26334A63,
      pattern: ChatWallPattern.lines),
  ChatVisualTheme(
      id: 'sepia',
      name: 'Sepia',
      baseLight: 0xFFF6EFE3,
      baseDark: 0xFF211D16,
      patternLight: 0x30C4A87A,
      patternDark: 0x264A4132,
      pattern: ChatWallPattern.dots),
  ChatVisualTheme(
      id: 'slate',
      name: 'Slate',
      baseLight: 0xFFEDF0F4,
      baseDark: 0xFF131C26,
      patternLight: 0x2A93A3B5,
      patternDark: 0x262C3B4D,
      pattern: ChatWallPattern.grid),
  ChatVisualTheme(
      id: 'forest',
      name: 'Forest',
      baseLight: 0xFFE9F2EA,
      baseDark: 0xFF0E1F19,
      patternLight: 0x337FAF8B,
      patternDark: 0x262B4A3C,
      pattern: ChatWallPattern.crosses),
  ChatVisualTheme(
      id: 'ocean',
      name: 'Ocean',
      baseLight: 0xFFE7F0F8,
      baseDark: 0xFF0A1826,
      patternLight: 0x307FB2D9,
      patternDark: 0x26284663,
      pattern: ChatWallPattern.waves),
  ChatVisualTheme(
      id: 'plum',
      name: 'Plum',
      baseLight: 0xFFF3EBF4,
      baseDark: 0xFF1E1524,
      patternLight: 0x30B39AC0,
      patternDark: 0x26463A52,
      pattern: ChatWallPattern.rings),
  ChatVisualTheme(
      id: 'rose',
      name: 'Rose',
      baseLight: 0xFFF9EEF1,
      baseDark: 0xFF241318,
      patternLight: 0x33E3AEC1,
      patternDark: 0x26543A44,
      pattern: ChatWallPattern.hearts),
  ChatVisualTheme(
      id: 'ink',
      name: 'Ink',
      baseLight: 0xFFEEF0F2,
      baseDark: 0xFF0D0F12,
      patternLight: 0x2AA9B4BE,
      patternDark: 0x22323A44,
      pattern: ChatWallPattern.sparkles),
  ChatVisualTheme(
      id: 'meadow',
      name: 'Meadow',
      baseLight: 0xFFEFF4EA,
      baseDark: 0xFF141E12,
      patternLight: 0x30A4C08A,
      patternDark: 0x26374A32,
      pattern: ChatWallPattern.books),
];

/// Paints a chat wallpaper: base color + a gentle tiled pattern, dimmed
/// (WhatsApp-style) in the dark or by the reader's dim slider.
class ChatWallpaper extends StatelessWidget {
  final String themeId;
  final bool dark;
  final double dim;
  const ChatWallpaper(
      {super.key, required this.themeId, required this.dark, this.dim = 0});

  @override
  Widget build(BuildContext context) {
    final theme = kChatThemes.firstWhere(
      (t) => t.id == themeId,
      orElse: () => kChatThemes.first,
    );
    final base = theme.base(dark);
    final pattern = theme.patternColor(dark);
    return ColoredBox(
      color: base,
      child: theme.pattern == ChatWallPattern.none
          ? null
          : Opacity(
              opacity: (1 - dim).clamp(0.25, 1.0),
              child: CustomPaint(
                painter: _WallPainter(theme.pattern, pattern),
                size: Size.infinite,
              ),
            ),
    );
  }
}

class _WallPainter extends CustomPainter {
  final ChatWallPattern pattern;
  final Color color;
  _WallPainter(this.pattern, this.color);

  static const double _tile = 46;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final cols = (size.width / _tile).ceil() + 1;
    final rows = (size.height / _tile).ceil() + 1;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final x = c * _tile + (r.isOdd ? _tile / 2 : 0);
        final y = r * _tile;
        final center = Offset(x, y);
        switch (pattern) {
          case ChatWallPattern.none:
            break;
          case ChatWallPattern.dots:
            canvas.drawCircle(center, 1.6, paint);
          case ChatWallPattern.lines:
            canvas.drawLine(
                Offset(x - 8, y + 8), Offset(x + 8, y - 8), stroke);
          case ChatWallPattern.grid:
            canvas.drawLine(
                Offset(x - _tile / 2, y), Offset(x + _tile / 2, y), stroke);
            canvas.drawLine(
                Offset(x, y - _tile / 2), Offset(x, y + _tile / 2), stroke);
          case ChatWallPattern.stars:
            _star(canvas, center, 3.4, paint);
          case ChatWallPattern.hearts:
            _heart(canvas, center, 3.2, paint);
          case ChatWallPattern.waves:
            final path = Path()
              ..moveTo(x - 10, y)
              ..quadraticBezierTo(x - 5, y - 4, x, y)
              ..quadraticBezierTo(x + 5, y + 4, x + 10, y);
            canvas.drawPath(path, stroke);
          case ChatWallPattern.rings:
            canvas.drawCircle(center, 4.5, stroke);
          case ChatWallPattern.sparkles:
            canvas.drawLine(Offset(x - 4, y), Offset(x + 4, y), stroke);
            canvas.drawLine(Offset(x, y - 4), Offset(x, y + 4), stroke);
          case ChatWallPattern.crosses:
            canvas.drawLine(Offset(x - 4, y - 4), Offset(x + 4, y + 4), stroke);
            canvas.drawLine(Offset(x + 4, y - 4), Offset(x - 4, y + 4), stroke);
          case ChatWallPattern.books:
            canvas.drawRect(Rect.fromCenter(center: center, width: 9, height: 6),
                stroke);
        }
      }
    }
  }

  void _star(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 5; i++) {
      final outer = c + Offset.fromDirection(-1.5708 + i * 1.2566, r);
      final inner =
          c + Offset.fromDirection(-1.5708 + i * 1.2566 + .6283, r * .45);
      if (i == 0) {
        path.moveTo(outer.dx, outer.dy);
      } else {
        path.lineTo(outer.dx, outer.dy);
      }
      path.lineTo(inner.dx, inner.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _heart(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy + r)
      ..cubicTo(c.dx - r * 1.6, c.dy - r * .2, c.dx - r * .5, c.dy - r * 1.3,
          c.dx, c.dy - r * .4)
      ..cubicTo(c.dx + r * .5, c.dy - r * 1.3, c.dx + r * 1.6, c.dy - r * .2,
          c.dx, c.dy + r)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WallPainter old) =>
      old.pattern != pattern || old.color != color;
}

// ── theme persistence ───────────────────────────────────────────────────────

/// Per-chat wallpaper choice with a global default — WhatsApp's exact
/// model: pick for this chat, or set for all chats.
class ChatThemePrefs {
  static const _defaultKey = 'chat.theme.default';
  static const _dimKey = 'chat.theme.dim';

  static Future<String> defaultId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_defaultKey) ?? 'classic';
  }

  static Future<String> forConversation(String conversationKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('chat.theme.$conversationKey') ??
        await defaultId();
  }

  static Future<void> setForConversation(
      String? conversationKey, String id) async {
    final prefs = await SharedPreferences.getInstance();
    if (conversationKey == null) {
      await prefs.setString(_defaultKey, id);
      // A new default clears per-chat overrides so "all chats" is true.
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith('chat.theme.') && key != _defaultKey) {
          await prefs.remove(key);
        }
      }
    } else {
      await prefs.setString('chat.theme.$conversationKey', id);
    }
  }

  static Future<double> dim() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_dimKey) ?? 0;
  }

  static Future<void> setDim(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_dimKey, value.clamp(0, .8));
  }
}

/// The wallpaper picker: previews of every theme, a dim slider, and the
/// "apply to all chats" switch.
Future<void> showChatThemePicker(
  BuildContext context, {
  String? conversationKey,
}) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _ChatThemeSheet(
        conversationKey: conversationKey),
  );
  if (changed == true) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Chat theme updated.')));
  }
}

class _ChatThemeSheet extends StatefulWidget {
  final String? conversationKey;
  const _ChatThemeSheet({this.conversationKey});
  @override
  State<_ChatThemeSheet> createState() => _ChatThemeSheetState();
}

class _ChatThemeSheetState extends State<_ChatThemeSheet> {
  String _selected = 'classic';
  bool _forAll = false;
  double _dim = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = await ChatThemePrefs.forConversation(
        widget.conversationKey ?? '');
    final dim = await ChatThemePrefs.dim();
    if (mounted) {
      setState(() {
        _selected = id;
        _dim = dim;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .8,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Text('Chat theme',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                widget.conversationKey == null
                    ? 'The wallpaper for all of your chats'
                    : 'The wallpaper for this chat',
                style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context).hintColor),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: .9,
                  ),
                  itemCount: kChatThemes.length,
                  itemBuilder: (context, i) {
                    final theme = kChatThemes[i];
                    final selected = theme.id == _selected;
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        ChatThemePrefs.setForConversation(
                            _forAll ? null : widget.conversationKey,
                            theme.id);
                        setState(() => _selected = theme.id);
                        Navigator.pop(context, true);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            width: selected ? 2.4 : 1,
                            color: selected
                                ? BookNestColors.cyan
                                : Theme.of(context)
                                    .dividerColor
                                    .withOpacity(.6),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: ChatWallpaper(
                                    themeId: theme.id, dark: dark),
                              ),
                              Positioned(
                                left: 6,
                                bottom: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    color: Colors.black45,
                                  ),
                                  child: Text(theme.name,
                                      style: const TextStyle(
                                          fontSize: 9.5,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700)),
                                ),
                              ),
                              if (selected)
                                const Positioned(
                                  top: 6,
                                  right: 6,
                                  child: Icon(Icons.check_circle_rounded,
                                      size: 18,
                                      color: BookNestColors.cyan),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                child: Row(
                  children: [
                    const Icon(Icons.contrast_rounded,
                        size: 18, color: BookNestColors.cyan),
                    const SizedBox(width: 10),
                    const Text('Dim wallpaper in the dark',
                        style: TextStyle(fontSize: 13.5)),
                    Expanded(
                      child: Slider(
                        value: _dim,
                        max: .8,
                        divisions: 8,
                        activeColor: BookNestColors.cyan,
                        onChanged: (value) {
                          ChatThemePrefs.setDim(value);
                          setState(() => _dim = value);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                dense: true,
                title: const Text('Also set for all chats',
                    style: TextStyle(fontSize: 13.5)),
                value: _forAll,
                activeColor: BookNestColors.cyan,
                onChanged: (value) => setState(() => _forAll = value),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
