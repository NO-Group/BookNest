import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../services/backend_api.dart';
import 'booknest_ui.dart';
import 'skeleton_kit.dart';

/// The group curator's book picker: live search over the whole BookNest
/// catalogue, cover-first results, returns the picked book map
/// ({id, title, authorName, coverUrl}) or null when dismissed.
Future<Map<String, dynamic>?> showBookPicker(
  BuildContext context, {
  String title = 'Pick a book',
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _BookPickerSheet(),
  );
}

class _BookPickerSheet extends StatefulWidget {
  const _BookPickerSheet();

  @override
  State<_BookPickerSheet> createState() => _BookPickerSheetState();
}

class _BookPickerSheetState extends State<_BookPickerSheet> {
  final TextEditingController _query = TextEditingController();
  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await BackendApi.instance.callFresh('books.list',
        {'limit': 120});
    if (!mounted) return;
    if (res == null) {
      setState(() {
        _loading = false;
        _error = 'The catalogue could not be reached — check your connection.';
      });
      return;
    }
    setState(() {
      _all = ((res['books'] as List?) ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all
        .where((b) =>
            b['title'].toString().toLowerCase().contains(q) ||
            b['authorName'].toString().toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .78,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).hintColor.withOpacity(.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Text('Pick a book',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _query,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search title or author…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? RowsSkeleton(count: 6)
                  : _error != null
                      ? EmptyState(
                          icon: Icons.cloud_off_rounded,
                          title: 'Catalogue unreachable',
                          subtitle: _error!,
                          action: TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _loading = true;
                                _error = null;
                              });
                              _load();
                            },
                            icon: const Icon(Icons.refresh_rounded,
                                size: 18, color: BookNestColors.cyan),
                            label: const Text('Retry',
                                style:
                                    TextStyle(color: BookNestColors.cyan)),
                          ),
                        )
                      : _filtered.isEmpty
                          ? EmptyState(
                              icon: Icons.search_off_rounded,
                              title: 'Nothing matches',
                              subtitle:
                                  'Try another title or author from the catalogue.',
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                  16, 8, 16, 20),
                              itemCount: _filtered.length,
                              itemBuilder: (context, i) {
                                final book = _filtered[i];
                                return Card(
                                  elevation: 0,
                                  margin:
                                      const EdgeInsets.only(bottom: 8),
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surface
                                      .withOpacity(.6),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(14)),
                                  child: ListTile(
                                    onTap: () =>
                                        Navigator.pop(context, book),
                                    contentPadding: const EdgeInsets
                                        .symmetric(
                                        horizontal: 10, vertical: 4),
                                    leading: BookCover(
                                      coverUrl:
                                          book['coverUrl']?.toString(),
                                      title:
                                          book['title'].toString(),
                                      width: 42,
                                      height: 58,
                                      radius: 8,
                                    ),
                                    title: Text(
                                      book['title'].toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13.5),
                                    ),
                                    subtitle: Text(
                                      book['authorName'].toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
