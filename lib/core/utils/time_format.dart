import 'package:intl/intl.dart';

/// Formats a timestamp the way a chat app would: "now", "5m", "3h",
/// "yesterday", "5d", or "Aug 3" for anything older than a week.
String formatRelativeTime(DateTime time, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final diff = current.difference(time);

  if (diff.inSeconds < 60) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24 && current.day == time.day) return '${diff.inHours}h';
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return DateFormat('MMM d').format(time);
}

/// Formats a chat-message timestamp: "14:30" for today, "Aug 3, 14:30"
/// otherwise. Falls back to an empty string when [raw] cannot be parsed.
String formatMessageTimestamp(dynamic raw) {
  if (raw == null) return '';
  try {
    final date = DateTime.parse(raw.toString()).toLocal();
    final time = DateFormat('HH:mm').format(date);
    final now = DateTime.now();
    final isSameDay =
        date.year == now.year && date.month == now.month && date.day == now.day;
    if (isSameDay) return time;
    return '${DateFormat('MMM d').format(date)}, $time';
  } catch (_) {
    return '';
  }
}

/// Formats a date like "Aug 3, 2026". Returns '' when [raw] cannot be parsed.
String formatFullDate(dynamic raw) {
  if (raw == null) return '';
  try {
    return DateFormat('MMM d, yyyy').format(DateTime.parse(raw.toString()).toLocal());
  } catch (_) {
    return '';
  }
}
