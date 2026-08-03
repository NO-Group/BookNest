import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/auth_guard.dart';
import '../../../services/supabase_service.dart';

/// Realtime library feed of published books.
///
/// Subscribes to `club_books` via a Supabase stream ordered by creation date
/// and renders them as dark cards. Every interactive action (Write, Read,
/// Search, Bookmark) is guarded by [AuthGuard].
class BooksLibraryScreen extends StatefulWidget {
  const BooksLibraryScreen({super.key});

  @override
  State<BooksLibraryScreen> createState() => _BooksLibraryScreenState();
}

class _BooksLibraryScreenState extends State<BooksLibraryScreen> {
  Stream<List<Map<String, dynamic>>>? _booksStream;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    _booksStream = SupabaseService()
        .client
        .from('club_books')
        .stream(primaryKey: ['id'])
        .eq('moderation_status', 'approved')
        .order('created_at', ascending: false)
        .map(
          (rows) => rows
              .map((row) => Map<String, dynamic>.from(row))
              .toList(),
        );
  }

  void _openBook(String bookId) {
    AuthGuard.run(context, () {
      context.push('/publish-details?bookId=$bookId');
    });
  }

  void _onSearchPressed() {
    AuthGuard.run(context, () {
      // Reserved: deep-search is gated behind authentication.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Search is coming soon.'),
          backgroundColor: Color(0xFF00D4FF),
        ),
      );
    });
  }

  void _onWritePressed() {
    AuthGuard.run(context, () {
      context.push('/editor');
    });
  }

  void _onBookmarkPressed(String bookId) {
    AuthGuard.run(context, () {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved book to your library.'),
          backgroundColor: const Color(0xFF00D4FF),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search books',
            onPressed: _onSearchPressed,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _onWritePressed,
        backgroundColor: const Color(0xFF00D4FF),
        icon: const Icon(Icons.edit, color: Colors.white),
        label: const Text(
          'Write',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: RefreshIndicator(
        color: const Color(0xFF00D4FF),
        backgroundColor: const Color(0xFF121212),
        onRefresh: () async {
          setState(_subscribe);
          await Future<void>.delayed(const Duration(milliseconds: 500));
        },
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _booksStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF00D4FF)),
              );
            }

            final books = snapshot.data ?? const <Map<String, dynamic>>[];
            if (books.isEmpty) {
              return _buildEmptyState();
            }

            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: books.length,
              itemBuilder: (context, index) =>
                  _buildBookCard(books[index]),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.menu_book, size: 64, color: Color(0xFF444444)),
                  const SizedBox(height: 16),
                  const Text(
                    'No books yet',
                    style: TextStyle(color: Colors.white, fontSize: 20),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Be the first to publish a story.',
                    style: TextStyle(color: Color(0xFF888888), fontSize: 14),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: _onWritePressed,
                    icon: const Icon(Icons.edit),
                    label: const Text('Write a Book'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00D4FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBookCard(Map<String, dynamic> book) {
    final title = (book['title'] as String?) ?? 'Untitled';
    final author = (book['author'] as String?) ?? 'Unknown author';
    final description = (book['description'] as String?) ?? '';
    final id = (book['id'] as String?) ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF222222)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF1F1F1F),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.book,
                  color: Color(0xFF00D4FF),
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF888888),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0A0A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF00D4FF)),
                ),
                child: const Text(
                  'Markdown',
                  style: TextStyle(
                    color: Color(0xFF00D4FF),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _openBook(id),
                icon: const Icon(Icons.menu_book, size: 18),
                label: const Text('Read'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF00D4FF),
                  side: const BorderSide(color: Color(0xFF00D4FF)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.bookmark_border, color: Colors.white54),
                tooltip: 'Bookmark',
                onPressed: () => _onBookmarkPressed(id),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
