import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../services/supabase_service.dart';
import '../../../config/theme.dart';

/// Community library "Add" picker (`/community/:communityId/library/add`).
///
/// Lists all **public** (approved) books on the platform with a search bar on
/// top and a **Hot 🔥** section first — algorithmized from the most-read books
/// (reads in the last 7 days via `get_hot_books`, then total views).
/// Tapping a book selects it (checkmark); the Done button reposts all
/// selected books into the community library (`community_books`).
class CommunityAddBooksScreen extends StatefulWidget {
  final String communityId;

  const CommunityAddBooksScreen({super.key, required this.communityId});

  @override
  State<CommunityAddBooksScreen> createState() => _CommunityAddBooksScreenState();
}

class _CommunityAddBooksScreenState extends State<CommunityAddBooksScreen> {
  final TextEditingController _searchController = TextEditingController();

  final List<Map<String, dynamic>> _hotBooks = [];
  List<Map<String, dynamic>> _allBooks = [];
  final Set<String> _selectedIds = {};
  Set<String> _alreadyInLibrary = {};

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onQueryChanged);
    _load();
  }

  Future<void> _load() async {
    try {
      final supabase = SupabaseService().client;

      // Hot 🔥 = most-read books (reads in last 7 days, then views).
      final hot = await supabase.rpc('get_hot_books', params: {
        'days': 7,
        'max_count': 20,
      });

      final all = await supabase
          .from('club_books')
          .select('id, title, description, views, created_at')
          .eq('moderation_status', 'approved')
          .order('created_at', ascending: false)
          .limit(200);

      // Books already reposted into this community (excluded / shown as added).
      final existing = await supabase
          .from('community_books')
          .select('club_book_id')
          .eq('community_id', widget.communityId);
      final existingIds = existing
          .map((r) => (r as Map)['club_book_id'].toString())
          .toSet();

      if (!mounted) return;
      setState(() {
        _hotBooks
          ..clear()
          ..addAll(hot.map((r) => Map<String, dynamic>.from(r as Map)).toList());
        _allBooks
          ..clear()
          ..addAll(all.map((r) => Map<String, dynamic>.from(r)).toList());
        _alreadyInLibrary = existingIds;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Could not load books: $e';
      });
    }
  }

  void _onQueryChanged() {
    setState(() {}); // rebuild to re-filter
  }

  List<Map<String, dynamic>> get _filteredAll {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _allBooks;
    return _allBooks
        .where((b) =>
            (b['title']?.toString() ?? '').toLowerCase().contains(q) ||
            (b['description']?.toString() ?? '').toLowerCase().contains(q))
        .toList();
  }

  void _toggleBook(Map<String, dynamic> book) {
    final id = book['id'].toString();
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _done() async {
    if (_selectedIds.isEmpty || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      final myId = SupabaseService().auth.currentUser?.id;
      await SupabaseService().client.from('community_books').insert(
            _selectedIds.map((bookId) {
              return {
                'community_id': widget.communityId,
                'club_book_id': bookId,
                'added_by': myId,
              };
            }).toList(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedIds.length == 1
                ? 'Book added to the library.'
                : '${_selectedIds.length} books added to the library.',
          ),
          backgroundColor: NOC.accent,
        ),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add books: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NOC.bg,
      appBar: AppBar(
        backgroundColor: NOC.surface,
        elevation: 1,
        leading: IconButton(
          icon:  Icon(Icons.arrow_back, color: NOC.text),
          onPressed: () => context.pop(),
        ),
        title:  Text('Add books', style: TextStyle(color: NOC.text, fontSize: 18)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: _isSaving || _selectedIds.isEmpty ? null : _done,
              icon: _isSaving
                  ?  SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: NOC.accent),
                    )
                  :  Icon(Icons.done, size: 18, color: NOC.accent),
              label: Text(
                'Done${_selectedIds.isEmpty ? '' : ' (${_selectedIds.length})'}',
                style:  TextStyle(color: NOC.accent, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return  Center(child: CircularProgressIndicator(color: NOC.accent));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
               Icon(Icons.error_outline, size: 56, color: NOC.textFaint),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center, style:  TextStyle(color: NOC.textMuted)),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final searchActive = _searchController.text.trim().isNotEmpty;

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _searchController,
            style:  TextStyle(color: NOC.text),
            decoration: InputDecoration(
              hintText: 'Search public books...',
              hintStyle:  TextStyle(color: NOC.textFaint),
              prefixIcon:  Icon(Icons.search, color: NOC.textFaint),
              filled: true,
              fillColor: NOC.surfaceAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: searchActive
              ? _buildBookList(_filteredAll)
              : ListView(
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    if (_hotBooks.isNotEmpty) ...[
                       Padding(
                        padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
                        child: Row(
                          children: [
                            Icon(Icons.local_fire_department, color: NOC.hot, size: 18),
                            SizedBox(width: 6),
                            Text(
                              'Hot 🔥',
                              style: TextStyle(
                                color: NOC.hot,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                       Padding(
                        padding: EdgeInsets.fromLTRB(20, 2, 20, 8),
                        child: Text(
                          'Most read this week',
                          style: TextStyle(color: NOC.textMuted, fontSize: 12),
                        ),
                      ),
                      ..._hotBooks.map(_buildBookCard),
                      const SizedBox(height: 12),
                    ],
                     Padding(
                      padding: EdgeInsets.fromLTRB(20, 14, 20, 8),
                      child: Text(
                        'All public books',
                        style: TextStyle(color: NOC.text, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (_allBooks.isEmpty)
                       Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: Text('No public books yet.', style: TextStyle(color: NOC.textMuted)),
                        ),
                      )
                    else
                      ..._allBooks.map(_buildBookCard),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildBookList(List<Map<String, dynamic>> books) {
    if (books.isEmpty) {
      return  Center(
        child: Text('No books match your search.', style: TextStyle(color: NOC.textMuted)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      itemCount: books.length,
      itemBuilder: (context, index) => _buildBookCard(books[index]),
    );
  }

  Widget _buildBookCard(Map<String, dynamic> book) {
    final id = book['id'].toString();
    final isSelected = _selectedIds.contains(id);
    final alreadyAdded = _alreadyInLibrary.contains(id);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSelected
            ? NOC.accent.withOpacity(0.08)
            : NOC.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? NOC.accent : NOC.border,
          width: isSelected ? 1.2 : 1,
        ),
      ),
      child: InkWell(
        onTap: alreadyAdded ? null : () => _toggleBook(book),
        borderRadius: BorderRadius.circular(10),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: NOC.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child:  Icon(Icons.menu_book, color: NOC.accent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book['title']?.toString() ?? 'Untitled',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:  TextStyle(color: NOC.text, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${book['views'] ?? 0} views',
                    style:  TextStyle(color: NOC.textFaint, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (alreadyAdded)
               Icon(Icons.check_circle, color: NOC.success, size: 24)
            else if (isSelected)
               Icon(Icons.check_circle, color: NOC.accent, size: 24)
            else
               Icon(Icons.radio_button_unchecked, color: NOC.textFaint, size: 24),
          ],
        ),
      ),
    );
  }
}
