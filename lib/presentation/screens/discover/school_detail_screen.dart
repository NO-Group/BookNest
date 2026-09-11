import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../components/book_picker_sheet.dart';
import '../../components/booknest_ui.dart';
import 'group_base_screen.dart';
import 'school_lms.dart';

/// The full school experience: everything a group gets (profile,
/// membership, announcements, directory, chat) plus the two things only a
/// school needs — a curated reading list and a live top-readers
/// leaderboard (distinct books opened in the last 30 days, computed on the
/// server from real reading activity).
class SchoolDetailScreen extends StatelessWidget {
  final String id;

  const SchoolDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    return GroupBaseScreen(
      kind: 'schools',
      groupId: id,
      title: 'School',
      extraSections: (state) => [
        SchoolClassesSection(state: state),
        const SizedBox(height: 16),
        SchoolAssignmentsSection(state: state),
        const SizedBox(height: 16),
        SchoolExamsSection(state: state),
        const SizedBox(height: 16),
        _ReadingListSection(state: state),
        const SizedBox(height: 16),
        _LeaderboardSection(state: state),
      ],
    );
  }
}

/// The school's curated shelf. Managers add from the catalogue; every
/// member taps straight into the book.
class _ReadingListSection extends StatefulWidget {
  const _ReadingListSection({required this.state});

  final GroupBaseScreenState state;

  @override
  State<_ReadingListSection> createState() => _ReadingListSectionState();
}

class _ReadingListSectionState extends State<_ReadingListSection> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;
  bool _busy = false;

  GroupBaseScreenState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _list = _fromDoc();
    _loading = false;
  }

  List<Map<String, dynamic>> _fromDoc() {
    final raw = (state.group?['readingList'] as List?) ?? const [];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList()
      ..sort((a, b) => (b['addedAt']?.toString() ?? '')
          .compareTo(a['addedAt']?.toString() ?? ''));
  }

  Future<void> _add() async {
    if (_busy) return;
    final book = await showBookPicker(context, title: 'Add to reading list');
    if (book == null) return;
    setState(() => _busy = true);
    final res = await BackendApi.instance.call('schools.readinglist.add', {
      'groupId': state.groupId,
      'kind': state.kind,
      'bookId': book['id']?.toString() ?? '',
    });
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res == null
            ? 'Could not add it right now — try again.'
            : '"${book['title']}" added to the reading list.')));
    if (res != null) await state.reload();
    if (mounted) setState(() => _list = _fromDoc());
  }

  Future<void> _remove(Map<String, dynamic> entry) async {
    if (_busy) return;
    setState(() => _busy = true);
    final res = await BackendApi.instance
        .call('schools.readinglist.remove', {
      'groupId': state.groupId,
      'kind': state.kind,
      'bookId': entry['bookId']?.toString() ?? '',
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not remove it — try again.')));
      return;
    }
    await state.reload();
    if (mounted) setState(() => _list = _fromDoc());
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassPanel(
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.menu_book_rounded,
                size: 19, color: BookNestColors.cyan),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Reading list · ${_list.length}',
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: onSurface)),
            ),
            if (state.isManager)
              IconButton(
                onPressed: _busy ? null : _add,
                icon: const Icon(Icons.add_circle_rounded,
                    color: BookNestColors.cyan, size: 24),
                tooltip: 'Add a book',
              ),
          ]),
          const SizedBox(height: 6),
          if (_list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                state.isManager
                    ? 'Curate the shelf your students should read — add the first book.'
                    : 'No books on the list yet.',
                style: TextStyle(
                    fontSize: 12.5, color: onSurface.withOpacity(.55)),
              ),
            )
          else
            SizedBox(
              height: 148,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _list.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final entry = _list[i];
                  return GestureDetector(
                    onTap: () => context
                        .push('/book/${entry['bookId']?.toString() ?? ''}'),
                    onLongPress:
                        state.isManager ? () => _remove(entry) : null,
                    child: SizedBox(
                      width: 100,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          BookCover(
                            coverUrl: entry['coverUrl']?.toString(),
                            title: entry['title']?.toString() ?? 'Book',
                            width: 96,
                            height: 96,
                            radius: 14,
                          ),
                          const SizedBox(height: 6),
                          Text(entry['title']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: onSurface)),
                          Text(entry['authorName']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: onSurface.withOpacity(.55))),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          if (state.isManager && _list.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Hold a cover to remove it from the list.',
                style: TextStyle(
                    fontSize: 10.5, color: onSurface.withOpacity(.45)),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Top readers, computed server-side: distinct books opened per member in
/// the last 30 days. Medals for the first three.
class _LeaderboardSection extends StatefulWidget {
  const _LeaderboardSection({required this.state});

  final GroupBaseScreenState state;

  @override
  State<_LeaderboardSection> createState() => _LeaderboardSectionState();
}

class _LeaderboardSectionState extends State<_LeaderboardSection> {
  List<Map<String, dynamic>> _leaders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await BackendApi.instance.call('schools.leaderboard', {
      'groupId': widget.state.groupId,
      'kind': widget.state.kind,
    });
    if (!mounted) return;
    setState(() {
      _leaders = ((res?['leaders'] as List?) ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _loading = false;
    });
  }

  static const _medals = ['🥇', '🥈', '🥉'];

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassPanel(
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.emoji_events_rounded,
                size: 19, color: BookNestColors.cyan),
            const SizedBox(width: 8),
            Text('Top readers · 30 days',
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: onSurface)),
            const Spacer(),
            IconButton(
              onPressed: _loading ? null : _load,
              icon: Icon(Icons.refresh_rounded,
                  size: 19, color: onSurface.withOpacity(.6)),
              tooltip: 'Refresh',
            ),
          ]),
          const SizedBox(height: 4),
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: BookNestColors.cyan),
              ),
            )
          else if (_leaders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'No reading activity yet — open a book from the list to lead the board.',
                style: TextStyle(
                    fontSize: 12.5, color: onSurface.withOpacity(.55)),
              ),
            )
          else
            for (final leader in _leaders)
              Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Row(children: [
                  SizedBox(
                    width: 26,
                    child: Text(
                      (leader['rank'] as num?)?.toInt() != null &&
                              (leader['rank'] as num).toInt() <= 3
                          ? _medals[(leader['rank'] as num).toInt() - 1]
                          : '${leader['rank']}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: onSurface.withOpacity(.75)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: BookNestColors.navy,
                    child: Text(
                      (leader['name']?.toString() ?? 'R')
                          .substring(0, 1)
                          .toUpperCase(),
                      style: const TextStyle(
                          color: BookNestColors.cyan,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(leader['name']?.toString() ?? 'Reader',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.2,
                            fontWeight: FontWeight.w700,
                            color: onSurface)),
                  ),
                  Text(
                    '${(leader['books'] as num?)?.toInt() ?? 0} book${((leader['books'] as num?)?.toInt() ?? 0) == 1 ? '' : 's'}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: BookNestColors.cyan),
                  ),
                ]),
              ),
        ]),
      ),
    );
  }
}
