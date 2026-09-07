import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../components/report_sheet.dart';

/// Terms of Service — the honest, readable agreement between BookNest and
/// its readers. Real rules, no boilerplate fog.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Terms of Service',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          _Card(
            theme: theme,
            icon: Icons.handshake_outlined,
            title: 'The deal',
            body:
                'BookNest gives you a place to write, read and talk about '
                'books. We provide the service as it is, keep improving it, '
                'and may change or discontinue features — significant changes '
                'are announced in the app first.',
          ),
          _Card(
            theme: theme,
            icon: Icons.edit_note_rounded,
            title: 'Your words stay yours',
            body:
                'You own everything you write — manuscripts, reviews, posts '
                'and messages. By publishing in BookNest you give us the '
                'limited permission to store, display and share that content '
                'inside the app while your account exists. Delete a book or '
                'your whole account and that permission ends.',
          ),
          _Card(
            theme: theme,
            icon: Icons.gavel_rounded,
            title: 'Play fair',
            body:
                'Do not steal other writers\' work, harass readers, spread '
                'hate, post sexual content involving minors, break the law, '
                'or try to break the app. Remixes and sequels must credit '
                'the original author — BookNest carries those marks for you '
                'and strips them from thieves.',
          ),
          _Card(
            theme: theme,
            icon: Icons.diamond_outlined,
            title: 'Gems',
            body:
                'Gems are earned inside BookNest — daily claims, publishing, '
                'remixes and reading milestones. They have no cash value, '
                'cannot be bought or sold, and exist to unlock boosts and '
                'fun. We can reverse gems obtained through abuse.',
          ),
          _Card(
            theme: theme,
            icon: Icons.flag_rounded,
            title: 'Moderation',
            body:
                'Every post, message, book and profile can be reported '
                'in-app. Reports go to the moderation team with the '
                'reporter\'s identity and are handled confidentially. We may '
                'remove content and suspend accounts that break these rules '
                '— serious violations end in deletion.',
          ),
          _Card(
            theme: theme,
            icon: Icons.delete_forever_rounded,
            title: 'Leaving',
            body:
                'You can delete your whole account from Settings at any '
                'time. That erases your profile, books, drafts, posts, '
                'reviews, messages and gems for good.',
          ),
          _Card(
            theme: theme,
            icon: Icons.balance_rounded,
            title: 'Liability',
            body:
                'BookNest is provided "as is". To the fullest extent the law '
                'allows, N-O Group is not liable for indirect damages or '
                'lost content caused by service interruptions. Nothing here '
                'limits rights you have under consumer law that cannot be '
                'waived.',
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Questions about these terms? Report anything from any piece '
              'of content, or reach the team from About BookNest in '
              'Settings.',
              style: TextStyle(fontSize: 12.5, color: theme.hintColor,
                  height: 1.45),
            ),
          ),
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
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withOpacity(.04)
            : BookNestColors.navyDeep.withOpacity(.03),
        border: Border.all(
            color: BookNestColors.cyan.withOpacity(.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: BookNestColors.cyan),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14.5)),
            ],
          ),
          const SizedBox(height: 6),
          Text(body,
              style: TextStyle(
                  color: theme.hintColor, fontSize: 13, height: 1.5)),
        ],
      ),
    );
  }
}
