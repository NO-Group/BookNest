import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/theme.dart';

/// About BookNest — version, mission, credits.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('About BookNest',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        children: [
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(
                  colors: [BookNestColors.cyan, BookNestColors.cyanSoft],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: BookNestColors.cyan.withOpacity(.3),
                    blurRadius: 26,
                    offset: const Offset(0, 9),
                  ),
                ],
              ),
              child: const Icon(Icons.menu_book_rounded,
                  color: BookNestColors.navyDeep, size: 40),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text('BookNest',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          Center(
            child: Text('The Digital Library Ecosystem',
                style: TextStyle(color: BookNestColors.cyan)),
          ),
          const SizedBox(height: 22),
          Text(
            'BookNest is a social reading and writing home for bookworms and '
            'STEM minds — write books, build clubs, share what you love, and '
            'discover your next unforgettable read.',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.hintColor, height: 1.5),
          ),
          const SizedBox(height: 28),
          _Row(label: 'Version', value: AppConfig.appVersion),
          _Row(label: 'Built with', value: 'Flutter'),
          _Row(label: 'Cloud', value: 'Supabase · MongoDB · Cloudinary · R2'),
          _Row(label: 'By', value: 'N.O Group'),
          const SizedBox(height: 28),
          Center(
            child: Text(
              'Made with 💙 for readers everywhere.\nNext stop: v1.2 — with Jenny on the team.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.hintColor, fontSize: 12.5, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(color: theme.hintColor, fontSize: 13.5)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13.5)),
        ],
      ),
    );
  }
}
