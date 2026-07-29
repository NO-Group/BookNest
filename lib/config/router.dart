import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../presentation/screens/discover/discover_screen.dart';
import '../presentation/screens/books/books_library_screen.dart';
import '../presentation/screens/books/book_editor_screen.dart';

// Placeholder for reader screen until fully built
class BookReaderScreen extends StatelessWidget {
  final String bookId;
  const BookReaderScreen({super.key, required this.bookId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('Reader'),
        backgroundColor: const Color(0xFF1F1F1F),
      ),
      body: Center(
        child: Text(
          'Reading Book ID: $bookId',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}

final GoRouter appRouter = GoRouter(
  initialLocation: '/library',
  routes: [
    GoRoute(
      path: '/library',
      builder: (context, state) => const BooksLibraryScreen(),
    ),
    GoRoute(
      path: '/discover',
      builder: (context, state) => const DiscoverScreen(),
    ),
    GoRoute(
      path: '/editor',
      builder: (context, state) {
        final clubId = state.uri.queryParameters['clubId'] ?? '';
        return BookEditorScreen(clubId: clubId);
      },
    ),
    GoRoute(
      path: '/reader/:id',
      builder: (context, state) {
        final bookId = state.pathParameters['id'] ?? '';
        return BookReaderScreen(bookId: bookId);
      },
    ),
  ],
);