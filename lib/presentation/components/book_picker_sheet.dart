import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../services/backend_api.dart';
import 'adaptive.dart';
import 'booknest_ui.dart';
import 'skeleton_kit.dart';

/// The group curator's book picker: live search over the WHOLE BookNest
/// catalogue (server-side — the old picker only filtered the newest 50
/// books on the device, so most classics could never be found).
/// A bottom sheet on phones, a centred dialog on tablets / PC.
/// Returns the picked book map ({id, title, authorName, coverUrl}) or null.
Future<Map<String, dynamic>?> showBookPicker(
  BuildContext context, {
  String title = 'Pick a book',
}) {
  return showAdaptiveSheet<Map<String, dynamic>>(
    context: context,
    maxWidth: 620,
    builder: (_) => _BookPickerSheet(title: title),
  );
}

class _BookPickerSheet extends StatefulWidget {
  final String title;

  const _BookPickerSheet({required this.title});

  @override
  State<_BookPickerSheet> createState() => _BookPickerSheetState();
}

class _BookPickerSheetState extends State<_BookPickerSheet> {
  final TextEditingController _query = TextEditingController();
  List<Map<String, dynamic>> _books = [];
  bool _loading = true;
  String? _error;
  Timer? _debounce;
  int _ticket = 0;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQuery(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      _load(value.trim());
    });
  }

  Future<void> _load(String search) async {
    final ticket = ++_ticket;
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await BackendApi.instance.callFresh('books.list', {
      'limit': 50,
      if (search.isNotEmpty) 'search': search,
    });
    if (!mounted || ticket != _ticket) return; // a newer search won
    if (res == null) {
      setState(() {
        _loading = false;
        _error = BackendApi.instance.errorOr(
            'The catalogue could not be reached — check your connection.');
      });
      return;
    }
    setState(() {
      _books = ((res['books'] as List?) ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .where((b) => (b['id']?.toString() ?? '').isNotEmpty)
          // books.list speaks `author` / `cover_url`; callers expect the
          // picker contract {id, title, authorName, coverUrl}.
          .map((b) => <String, dynamic>{
                ...b,
                'authorName': b['authorName'] ?? b['author'],
                'coverUrl': b['coverUrl'] ?? b['cover_url'],
              })
          .toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = context.isCompact;
    final height = MediaQuery.sizeOf(context).height * (compact ? .78 : .74);
    return Padding(
      padding: EdgeInsets.only(
          bottom: compact ? MediaQuery.viewInsetsOf(context).bottom : 0),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, compact ? 0 : 18, 8, 0),
              child: Row(children: [
                const Icon(Icons.menu_book_rounded,
                    color: BookNestColors.cyan, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(widget.title,
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.onSurface)),
                ),
                if (!compact)
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _query,
                autofocus: !compact,
                onChanged: _onQuery,
                onSubmitted: (v) => _load(v.trim()),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search any title or author…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            Expanded(child: _results(theme)),
          ],
        ),
      ),
    );
  }

  Widget _results(ThemeData theme) {
    if (_loading) return const RowsSkeleton(count: 6);
    if (_error != null) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Catalogue unreachable',
        subtitle: _error!,
        action: TextButton.icon(
          onPressed: () => _load(_query.text.trim()),
          icon: const Icon(Icons.refresh_rounded,
              size: 18, color: BookNestColors.cyan),
          label: const Text('Retry',
              style: TextStyle(color: BookNestColors.cyan)),
        ),
      );
    }
    if (_books.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Nothing matches',
        subtitle: 'Try another title or author from the catalogue.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      itemCount: _books.length,
      itemBuilder: (context, i) {
        final book = _books[i];
        final title = book['title']?.toString() ?? 'Untitled';
        final author = book['authorName']?.toString() ?? '';
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 8),
          color: theme.colorScheme.surface.withOpacity(.6),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: ListTile(
            onTap: () => Navigator.pop(context, book),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            leading: BookCover(
              coverUrl: book['coverUrl']?.toString(),
              title: title,
              width: 42,
              height: 58,
              radius: 8,
            ),
            title: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13.5)),
            subtitle: Text(author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.add_circle_outline_rounded,
                color: BookNestColors.cyan),
          ),
        );
      },
    );
  }
}
