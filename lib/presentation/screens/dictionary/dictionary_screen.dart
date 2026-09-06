import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/theme.dart';
import '../../components/booknest_ui.dart';
import '../../../services/dictionary_service.dart';
import '../../../services/supabase_service.dart';

/// Word Nest — the BookNest dictionary. Fully offline lookups from the
/// bundled edition, with word of the day, recent searches, and community
/// trending words when online.
class DictionaryScreen extends StatefulWidget {
  final String? initialQuery;

  const DictionaryScreen({super.key, this.initialQuery});

  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  final TextEditingController _controller = TextEditingController();
  List<WordEntry> _results = const [];
  WordEntry? _wordOfTheDay;
  List<String> _recent = const [];
  List<String> _trending = const [];
  bool _loading = true;
  bool _searching = false;

  static const String _recentKey = 'wordnest_recent';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final all = await DictionaryService.instance.entries();
    WordEntry? wotd;
    try {
      wotd = await DictionaryService.instance.wordOfTheDay();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final recent = prefs.getStringList(_recentKey) ?? <String>[];

    List<String> trending = const [];
    try {
      trending = await SupabaseService().fetchDictionaryTrending();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _wordOfTheDay = wotd;
      _recent = recent;
      _trending = trending;
      _results = all;
      _loading = false;
    });

    final initial = widget.initialQuery?.trim() ?? '';
    if (initial.isNotEmpty) {
      _controller.text = initial;
      await _runSearch(initial, log: false);
    }
  }

  Future<void> _runSearch(String query, {bool log = true}) async {
    final q = query.trim();
    if (q.isEmpty) {
      final all = await DictionaryService.instance.entries();
      if (!mounted) return;
      setState(() {
        _results = all;
        _searching = false;
      });
      return;
    }
    final found = await DictionaryService.instance.search(q);
    if (!mounted) return;
    setState(() {
      _results = found;
      _searching = true;
    });

    await _rememberRecent(q);
    if (log) {
      // Community pulse only — never blocks or surfaces errors on lookup.
      try {
        await SupabaseService().logDictionarySearch(q);
      } catch (_) {}
    }
  }

  Future<void> _rememberRecent(String term) async {
    final next = <String>[term, ..._recent.where((t) => t != term)];
    if (next.length > 8) next.removeRange(8, next.length);
    setState(() => _recent = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentKey, next);
  }

  Future<void> _clearRecent() async {
    setState(() => _recent = const []);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentKey);
  }

  Future<void> _openEntry(WordEntry entry) async {
    await context.push('/dictionary/word', extra: entry);
    // Returning from a synonym tap may have changed the search box intent.
    if (mounted) setState(() {});
  }

  Future<void> _luckyDip() async {
    final entry = await DictionaryService.instance.randomWord();
    if (entry != null && mounted) await _openEntry(entry);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: GlassAppBar(
        title: 'Word Nest',
        actions: [
          IconButton(
            icon: const Icon(Icons.shuffle_rounded),
            tooltip: 'Lucky dip',
            onPressed: _loading ? null : _luckyDip,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: GlassPanel(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _runSearch,
                      onChanged: (v) {
                        if (v.isEmpty) _runSearch('');
                      },
                      decoration: InputDecoration(
                        hintText: 'Look up a word…',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _controller.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded,
                                    size: 18),
                                tooltip: 'Clear',
                                onPressed: () {
                                  _controller.clear();
                                  _runSearch('');
                                },
                              ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _searching
                      ? _buildResults(theme)
                      : _buildDiscover(theme),
                ),
              ],
            ),
    );
  }

  Widget _buildDiscover(ThemeData theme) {
    final children = <Widget>[];

    final wotd = _wordOfTheDay;
    if (wotd != null) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Word of the day',
            style: TextStyle(
              color: BookNestColors.cyan,
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ));
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: GlassPanel(
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _openEntry(wotd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  wotd.word,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  wotd.pos,
                  style: TextStyle(
                    color: BookNestColors.cyan,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  wotd.definition,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: theme.colorScheme.onSurface),
                ),
              ],
            ),
          ),
        ),
      ));
    }

    if (_trending.isNotEmpty) {
      children.add(_chipSection(
        theme,
        title: 'Trending this week',
        terms: _trending,
      ));
    }
    if (_recent.isNotEmpty) {
      children.add(_chipSection(
        theme,
        title: 'Recent searches',
        terms: _recent,
        onClear: _clearRecent,
      ));
    }

    children.add(Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Browse the edition · ${_results.length} words',
          style: TextStyle(
            color: theme.hintColor,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    ));
    children.addAll(_results.map(_entryTile));

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: children,
    );
  }

  bool _onlineLooking = false;

  Future<void> _lookupOnline() async {
    final term = _controller.text.trim();
    if (term.isEmpty || _onlineLooking) return;
    setState(() => _onlineLooking = true);
    WordEntry? entry;
    try {
      entry = await SupabaseService().lookupOnline(term);
    } finally {
      if (mounted) setState(() => _onlineLooking = false);
    }
    if (entry != null && mounted) {
      try {
        await SupabaseService().logDictionarySearch(term);
      } catch (_) {}
      await _openEntry(entry);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That word isn\'t in the full dictionary either — '
              'check the spelling and try again.'),
        ),
      );
    }
  }

  Widget _buildResults(ThemeData theme) {
    if (_results.isEmpty) {
      final term = _controller.text.trim();
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'No match in this edition yet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.hintColor, height: 1.4),
              ),
              const SizedBox(height: 14),
              if (term.isNotEmpty)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    foregroundColor: BookNestColors.navy,
                    backgroundColor: BookNestColors.cyan,
                  ),
                  onPressed: _onlineLooking ? null : _lookupOnline,
                  icon: _onlineLooking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.travel_explore_rounded, size: 18),
                  label: Text(_onlineLooking
                      ? 'Searching the full dictionary…'
                      : 'Search the full dictionary'),
                ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: _results.map(_entryTile).toList(),
    );
  }

  Widget _chipSection(
    ThemeData theme, {
    required String title,
    required List<String> terms,
    VoidCallback? onClear,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: theme.hintColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              if (onClear != null)
                GestureDetector(
                  onTap: onClear,
                  child: Text(
                    'Clear',
                    style: TextStyle(
                      color: BookNestColors.cyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: terms.map((term) {
              return GlassPanel(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                radius: 14,
                child: GestureDetector(
                  onTap: () async {
                    final entry =
                        await DictionaryService.instance.lookup(term);
                    if (entry != null && mounted) {
                      await _openEntry(entry);
                    } else if (mounted) {
                      _controller.text = term;
                      await _runSearch(term);
                    }
                  },
                  child: Text(
                    term,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _entryTile(WordEntry entry) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GlassPanel(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openEntry(entry),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            entry.word,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          entry.pos,
                          style: TextStyle(
                            color: BookNestColors.cyan,
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.definition,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.hintColor,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: theme.hintColor),
            ],
          ),
        ),
      ),
    );
  }
}
