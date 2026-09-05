import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../config/theme.dart';
import '../../services/cloudinary_service.dart';
import '../../services/supabase_service.dart';
import 'booknest_ui.dart';
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
        opacity: dark ? 0.045 : 0.055,
        child: child,
      ),
    );
  }
}

// ── Bubbles ──────────────────────────────────────────────────────────────────

class ChatBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool mine;

  /// Group chats show a name above other people's messages.
  final String? senderName;
  final VoidCallback? onOpenBook;
  final VoidCallback? onOpenImage;

  const ChatBubble({
    super.key,
    required this.message,
    required this.mine,
    this.senderName,
    this.onOpenBook,
    this.onOpenImage,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pending = message['pending'] == true;
    final failed = message['failed'] == true;
    final type = message['type']?.toString() ?? 'text';
    final text = message['text']?.toString() ?? '';
    final mediaUrl = message['mediaUrl']?.toString();

    final Widget content;
    if (type == 'image' && mediaUrl != null && mediaUrl.startsWith('http')) {
      content = _ImageContent(url: mediaUrl, onTap: onOpenImage);
    } else if (type == 'book_share') {
      content = _BookShareContent(
        title: text,
        onOpen: onOpenBook,
        dark: dark,
      );
    } else {
      content = Text(
        text,
        style: TextStyle(
          color: mine ? Colors.white : (dark ? BookNestColors.darkTextPrimary : BookNestColors.navyDeep),
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
      padding: type == 'book_share'
          ? const EdgeInsets.all(10)
          : (type == 'image'
              ? const EdgeInsets.fromLTRB(4, 4, 4, 4)
              : const EdgeInsets.fromLTRB(13, 8, 13, 6)),
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
      decoration: BoxDecoration(
        gradient: mine
            ? const LinearGradient(
                colors: [Color(0xFF0E2A57), BookNestColors.navyDeep],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: mine ? null : (dark ? BookNestColors.darkReceivedMessage : Colors.white),
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
          if (!mine && senderName != null && senderName!.isNotEmpty && type != 'book_share') ...[
            Text(
              senderName!,
              style: const TextStyle(
                color: BookNestColors.cyan,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
          ],
          content,
          if (type != 'image') ...[
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (failed)
                  const Icon(Icons.error_outline_rounded,
                      size: 11, color: Color(0xFFFF8A8A)),
                Text(
                  chatTimeLabel(message['createdAt']),
                  style: TextStyle(
                    fontSize: 10,
                    color: mine
                        ? Colors.white.withOpacity(.65)
                        : (dark ? Colors.white.withOpacity(.45) : BookNestColors.navyDeep.withOpacity(.5)),
                  ),
                ),
                if (mine) ...[
                  const SizedBox(width: 4),
                  Icon(
                    pending
                        ? Icons.schedule_rounded
                        : (failed ? Icons.error_outline_rounded : Icons.done_all_rounded),
                    size: 13,
                    color: pending
                        ? Colors.white.withOpacity(.55)
                        : (failed ? const Color(0xFFFF8A8A) : BookNestColors.cyan),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );

    if (type == 'image') {
      // Overlay the time/ticks on the photo, WhatsApp-style but glassy.
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Stack(
          children: [
            bubble,
            Positioned(
              right: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.45),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      chatTimeLabel(message['createdAt']),
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                    if (mine) ...[
                      const SizedBox(width: 4),
                      Icon(
                        pending ? Icons.schedule_rounded : Icons.done_all_rounded,
                        size: 13,
                        color: pending ? Colors.white.withOpacity(.6) : BookNestColors.cyan,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: bubble,
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

// ── Fullscreen photo viewer ──────────────────────────────────────────────────

void showChatPhoto(BuildContext context, String url) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withOpacity(.92),
    builder: (_) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              maxScale: 4,
              child: Image.network(url, fit: BoxFit.contain),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: IconButton.filled(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(.12),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ── Composer ─────────────────────────────────────────────────────────────────

class ChatComposer extends StatefulWidget {
  final String hint;
  final Future<void> Function(String text) onSendText;
  final Future<void> Function(Uint8List bytes, String extension) onSendImage;
  final bool enabled;

  const ChatComposer({
    super.key,
    required this.onSendText,
    required this.onSendImage,
    this.hint = 'Message…',
    this.enabled = true,
  });

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final TextEditingController _input = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  bool _uploading = false;
  String? _photoName;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _uploading) return;
    _input.clear();
    await widget.onSendText(text);
  }

  Future<void> _attach() async {
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

  @override
  Widget build(BuildContext context) {
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
        child: Row(
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
                    onPressed: widget.enabled ? _attach : null,
                    icon: const Icon(Icons.image_outlined),
                    color: BookNestColors.cyan,
                    tooltip: 'Send a photo',
                  ),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: TextField(
                  controller: _input,
                  enabled: widget.enabled,
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
