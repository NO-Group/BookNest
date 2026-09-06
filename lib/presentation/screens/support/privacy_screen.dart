import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// Privacy & safety — plain-language summary of where BookNest keeps things
/// and how to report problems.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Privacy & safety',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          _Card(theme: theme, icon: Icons.lock_outline_rounded, title: 'Your account',
              body:
                  'Your login is protected by Supabase authentication. We store '
                  'only the basics: username, display name, phone number (for '
                  'account recovery) and the profile photo you upload.'),
          _Card(theme: theme, icon: Icons.image_outlined, title: 'Images',
              body:
                  'Profile photos and book covers are stored on Cloudinary and '
                  'optimized automatically. We keep URLs, never your raw photos.'),
          _Card(theme: theme, icon: Icons.menu_book_rounded, title: 'Books & manuscripts',
              body:
                  'What you write belongs to you. Manuscripts, chapters, likes, '
                  'reviews and chats are stored in BookNest\'s document database '
                  '(MongoDB) and are only visible to you unless you publish or '
                  'share them.'),
          _Card(theme: theme, icon: Icons.flag_rounded, title: 'Reporting',
              body:
                  'See something wrong? Long-press any book or tap the report '
                  'action to flag it for the moderators. Reports are private and '
                  'reviewed by humans.'),
          _Card(theme: theme, icon: Icons.cleaning_services_outlined, title: 'Deleting things',
              body:
                  'You can delete your own reviews and comments anytime. Account '
                  'deletion arrives with the community update — until then, '
                  'contact the team and it will be handled manually.'),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final ThemeData theme;
  final IconData icon;
  final String title;
  final String body;

  const _Card({
    required this.theme,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: BookNestColors.cyan.withOpacity(.12),
            ),
            child: Icon(icon, size: 19, color: BookNestColors.cyan),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14.5)),
                const SizedBox(height: 5),
                Text(body,
                    style: TextStyle(
                        color: theme.hintColor,
                        fontSize: 13,
                        height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
