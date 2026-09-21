import 'dart:ui';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../../services/dictionary_service.dart';
import '../../../services/supabase_service.dart';
import '../../components/booknest_ui.dart';

/// Global search — books and people, side by side.
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;

  List<Map<String, dynamic>> _books = [];
  List<Map<String, dynamic>> _people = [];
  List<Map<String, dynamic>> _groups = [];
  List<WordEntry> _words = [];
  bool _searching = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _query.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final term = _query.text.trim();
      if (term.length < 2) {
        setState(() {
          _books = [];
          _people = [];
          _groups = [];
          _words = [];
          _searched = false;
        });
        return;
      }
      _search(term);
    });
  }

  Future<void> _search(String term) async {
    setState(() => _searching = true);
    try {
      final pattern = '${Uri.encodeComponent(term)}';
      final lowercase = term.toLowerCase();
      final kinds = ['clubs', 'communities', 'organizations', 'schools'];
      final results = await Future.wait<dynamic>([
        BackendApi.instance
            .call('books.list', {'search': term, 'limit': 20})
            .then((res) => (res?['books'] as List?) ?? const []),
        SupabaseService()
            .client
            .from('profiles')
            .select('id, username, display_name, avatar_url')
            .or('display_name.ilike.%$pattern%,username.ilike.%$pattern%')
            .limit(12),
        // Every public group space, name-matched here — the shelves are
        // small enough that a client pass is honest and instant.
        Future.wait<List<dynamic>>(kinds
            .map((kind) => BackendApi.instance
                .call('groups.list', {'kind': kind})
                .then((res) => (res?['groups'] as List?) ?? const []))),
        DictionaryService.instance.search(term),
      ]);
      if (!mounted) return;
      final groupRows = <Map<String, dynamic>>[];
      final perKind = results[2] as List<List<dynamic>>;
      for (var k = 0; k < kinds.length; k++) {
        for (final row in perKind[k]) {
          final g = Map<String, dynamic>.from(row as Map);
          final name =
              (g['name'] ?? g['title'] ?? '').toString().toLowerCase();
          if (name.contains(lowercase)) {
            g['kind'] = kinds[k];
            groupRows.add(g);
          }
          if (groupRows.length >= 8) break;
        }
        if (groupRows.length >= 8) break;
      }
      setState(() {
        _books = (results[0] as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        _people = (results[1] as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        _groups = groupRows;
        _words = (results[3] as List<WordEntry>).take(6).toList();
        _searching = false;
        _searched = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
          ? BookNestColors.darkChatBackground
          : BookNestColors.lightSurface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: (Theme.of(context).brightness == Brightness.dark
                        ? BookNestColors.darkChatBackground
                        : Colors.white)
                    .withOpacity(.66),
                border: Border(
                  bottom: BorderSide(
                      color: BookNestColors.cyan.withOpacity(.15)),
                ),
              ),
            ),
          ),
        ),
        titleSpacing: 16,
        title: TextField(
          controller: _query,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search books and readers…',
            prefixIcon:
                const Icon(Icons.search_rounded, color: BookNestColors.cyan),
            filled: true,
            fillColor: theme.colorScheme.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
      body: !_searched
          ? Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: GlassPanel(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        final q = _query.text.trim();
                        context.push(q.isEmpty
                            ? '/dictionary'
                            : '/dictionary?q=${Uri.encodeComponent(q)}');
                      },
                      child: Row(
                        children: [
                          const Icon(Icons.menu_book_rounded,
                              color: BookNestColors.cyan),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Word Nest dictionary',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Meanings, examples, word of the day — works offline.',
                                  style: TextStyle(
                                      color: theme.hintColor, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              color: theme.hintColor),
                        ],
                      ),
                    ),
                  ),
                ),
                const Expanded(
                  child: EmptyState(
                    icon: Icons.travel_explore_rounded,
                    title: 'Find your next favorite',
                    subtitle: 'Search titles, authors, topics — or the readers '
                        'who love them.',
                  ),
                ),
              ],
            )
          : _searching
              ? const Center(
                  child: CircularProgressIndicator(
                      color: BookNestColors.cyan))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                  children: [
                    if (_people.isNotEmpty) ...[
                      const SectionHeader(title: 'Readers'),
                      const SizedBox(height: 10),
                      ..._people.map((person) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Material(
                              color: theme.colorScheme.surface
                                  .withOpacity(.72),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(
                                      color: BookNestColors.cyan
                                          .withOpacity(.16))),
                              borderRadius: BorderRadius.circular(16),
                              child: ListTile(
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(16)),
                                leading: BookNestAvatar(
                                  imageUrl:
                                      person['avatar_url']?.toString(),
                                  name:
                                      (person['display_name'] ?? person['username'] ?? 'Reader')
                                          .toString(),
                                  radius: 20,
                                ),
                                title: Text(
                                    (person['display_name'] ??
                                            person['username'] ??
                                            'Reader')
                                        .toString(),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                subtitle: person['username'] == null
                                    ? null
                                    : Text('@${person['username']}'),
                                trailing: const Icon(
                                    Icons.chevron_right_rounded),
                                onTap: () =>
                                    context.push('/user/${person['id']}'),
                              ),
                            ),
                          )),
                      const SizedBox(height: 18),
                    ],
                    if (_groups.isNotEmpty) ...[
                      const SectionHeader(title: 'Group spaces'),
                      const SizedBox(height: 10),
                      ..._groups.map((group) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Material(
                              color: theme.colorScheme.surface
                                  .withOpacity(.72),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(
                                      color: BookNestColors.cyan
                                          .withOpacity(.16))),
                              borderRadius: BorderRadius.circular(16),
                              child: ListTile(
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(16)),
                                leading: CircleAvatar(
                                  radius: 20,
                                  backgroundColor: BookNestColors.navy,
                                  child: Text(
                                    (group['name'] ?? group['title'] ?? '#')
                                        .toString()
                                        .characters
                                        .first
                                        .toUpperCase(),
                                    style: const TextStyle(
                                        color: BookNestColors.cyan,
                                        fontWeight: FontWeight.w800),
                                  ),
                                ),
                                title: Text(
                                    (group['name'] ?? group['title'] ?? '')
                                        .toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                subtitle: Text(
                                    _kindLabel(group['kind'].toString()),
                                    style: TextStyle(
                                        color: theme.hintColor,
                                        fontSize: 12)),
                                trailing: const Icon(
                                    Icons.chevron_right_rounded),
                                onTap: () => context.push(
                                    '/${_kindRoute(group['kind'].toString())}/${group['id']}'),
                              ),
                            ),
                          )),
                      const SizedBox(height: 18),
                    ],
                    if (_words.isNotEmpty) ...[
                      const SectionHeader(title: 'Word Nest'),
                      const SizedBox(height: 10),
                      ..._words.map((entry) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Material(
                              color: theme.colorScheme.surface
                                  .withOpacity(.72),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(
                                      color: BookNestColors.cyan
                                          .withOpacity(.16))),
                              borderRadius: BorderRadius.circular(16),
                              child: ListTile(
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(16)),
                                leading: const Icon(
                                    Icons.menu_book_rounded,
                                    color: BookNestColors.cyan),
                                title: Text(entry.word,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                subtitle: Text(entry.definition,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: theme.hintColor,
                                        fontSize: 12)),
                                trailing: const Icon(
                                    Icons.chevron_right_rounded),
                                onTap: () => context.push(
                                    '/dictionary?q=${Uri.encodeComponent(entry.word)}'),
                              ),
                            ),
                          )),
                      const SizedBox(height: 18),
                    ],
                    if (_books.isNotEmpty) ...[
                      const SectionHeader(title: 'Books'),
                      const SizedBox(height: 10),
                      ..._books.map((book) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Material(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              child: ListTile(
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(16)),
                                leading: BookCover(
                                  coverUrl:
                                      book['cover_url']?.toString(),
                                  title:
                                      book['title']?.toString() ?? 'Book',
                                  width: 40,
                                  height: 54,
                                  radius: 8,
                                ),
                                title: Text(
                                    book['title']?.toString() ?? 'Untitled',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                subtitle: Text(
                                    'by ${book['author']?.toString() ?? 'Unknown'}'
                                    '${book['genre'] == null ? '' : ' · ${book['genre']}'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: theme.hintColor,
                                        fontSize: 12)),
                                trailing: const Icon(
                                    Icons.chevron_right_rounded),
                                onTap: () => context
                                    .push('/book/${book['id']}'),
                              ),
                            ),
                          )),
                    ],
                    if (_books.isEmpty &&
                        _people.isEmpty &&
                        _groups.isEmpty &&
                        _words.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 60),
                        child: EmptyState(
                          icon: Icons.search_off_rounded,
                          title: 'No matches',
                          subtitle: 'Try a different word or check the spelling.',
                        ),
                      ),
                  ],
                ),
    );
  }

  String _kindLabel(String kind) {
    if (kind.isEmpty) return '';
    return kind[0].toUpperCase() + kind.substring(1);
  }

  String _kindRoute(String kind) {
    switch (kind) {
      case 'communities':
        return 'community';
      case 'organizations':
        return 'organization';
      case 'schools':
        return 'school';
      default:
        return 'club';
    }
  }
}

