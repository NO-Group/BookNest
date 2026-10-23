import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../components/booknest_ui.dart';

/// One "create" choice in the PC feed panel.
class FeedCreateType {
  final String label;
  final IconData icon;
  final Color color;

  const FeedCreateType(this.label, this.icon, this.color);
}

/// Right-hand column of the PC feed: create a post in one click, trending
/// books, and shortcuts — the space a phone can't afford.
class FeedSidePanel extends StatefulWidget {
  final List<FeedCreateType> postTypes;
  final ValueChanged<String> onCreate;

  const FeedSidePanel(
      {super.key, required this.postTypes, required this.onCreate});

  @override
  State<FeedSidePanel> createState() => _FeedSidePanelState();
}

class _FeedSidePanelState extends State<FeedSidePanel> {
  List<Map<String, dynamic>> _books = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await BackendApi.instance.call('books.list', {'limit': 8});
    if (!mounted) return;
    setState(() {
      _books = ((res?['books'] as List?) ?? const [])
          .whereType<Map>()
          .map((b) => Map<String, dynamic>.from(b))
          .toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 18, 20, 40),
      children: [
        _Card(
          title: 'Create',
          icon: Icons.auto_awesome_rounded,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in widget.postTypes)
                ActionChip(
                  avatar: Icon(t.icon, size: 18, color: BookNestColors.cyan),
                  label: Text(t.label,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  onPressed: () => widget.onCreate(t.label),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _Card(
          title: 'New on BookNest',
          icon: Icons.local_fire_department_rounded,
          trailing: TextButton(
            onPressed: () => context.go('/books'),
            child: const Text('See all'),
          ),
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: BookNestColors.cyan)),
                )
              : _books.isEmpty
                  ? Text('Books appear here as authors publish.',
                      style: TextStyle(color: Theme.of(context).hintColor))
                  : Column(
                      children: [
                        for (final b in _books.take(6))
                          _BookRow(book: b),
                      ],
                    ),
        ),
        const SizedBox(height: 14),
        _Card(
          title: 'Shortcuts',
          icon: Icons.bolt_rounded,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Shortcut('Clubs & groups', Icons.groups_rounded,
                  () => context.go('/discover')),
              _Shortcut('My library', Icons.local_library_rounded,
                  () => context.push('/library')),
              _Shortcut('Dictionary', Icons.translate_rounded,
                  () => context.push('/dictionary')),
              _Shortcut('Streaks', Icons.local_fire_department_outlined,
                  () => context.push('/streaks')),
              _Shortcut('Events', Icons.event_rounded,
                  () => context.push('/events')),
              _Shortcut('Brainstorm', Icons.lightbulb_outline_rounded,
                  () => context.push('/brainstorm')),
            ],
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  const _Card(
      {required this.title,
      required this.icon,
      required this.child,
      this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withOpacity(.04) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 19, color: BookNestColors.cyan),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _BookRow extends StatelessWidget {
  final Map<String, dynamic> book;

  const _BookRow({required this.book});

  @override
  Widget build(BuildContext context) {
    final title = book['title']?.toString() ?? 'Untitled';
    final author =
        (book['author'] ?? book['authorName'] ?? '').toString();
    final id = book['id']?.toString() ?? '';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: id.isEmpty ? null : () => context.push('/book/$id'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          BookCover(
            coverUrl: (book['cover_url'] ?? book['coverUrl'])?.toString(),
            title: title,
            width: 40,
            height: 56,
            radius: 8,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13.5)),
                const SizedBox(height: 2),
                Text(author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: Theme.of(context).hintColor)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _Shortcut extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _Shortcut(this.label, this.icon, this.onTap);

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 17, color: BookNestColors.cyan),
      label: Text(label),
      onPressed: onTap,
    );
  }
}
