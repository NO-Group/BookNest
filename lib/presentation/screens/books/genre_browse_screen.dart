import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../../services/supabase_service.dart';
import '../../components/booknest_ui.dart';

/// Browse one of the 22 BookNest genres (?name=Fantasy).
class GenreBrowseScreen extends StatefulWidget {
  final String genre;

  const GenreBrowseScreen({super.key, required this.genre});

  @override
  State<GenreBrowseScreen> createState() => _GenreBrowseScreenState();
}

class _GenreBrowseScreenState extends State<GenreBrowseScreen> {
  List<Map<String, dynamic>> _books = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await BackendApi.instance
          .call('books.list', {'genre': widget.genre, 'limit': 60});
      final rows = (res?['books'] as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        _books = (rows as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
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
        title: Text(widget.genre,
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: BookNestColors.cyan))
          : _books.isEmpty
              ? EmptyState(
                  icon: Icons.category_rounded,
                  title: 'Nothing in $widget.genre yet',
                  subtitle:
                      'Authors, this genre is wide open — be the first to fill it.',
                  action: GradientButton(
                    label: 'Write in this genre',
                    icon: Icons.edit_rounded,
                    onPressed: () =>
                        AuthGuardRoute.push(context, '/editor'),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 14,
                    childAspectRatio: .62,
                  ),
                  itemCount: _books.length,
                  itemBuilder: (context, index) {
                    final book = _books[index];
                    final id = book['id']?.toString() ?? '';
                    final title = book['title']?.toString() ?? 'Untitled';
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => context.push('/book/$id'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Hero(
                            tag: 'book-$id',
                            child: BookCover(
                              coverUrl: book['cover_url']?.toString(),
                              title: title,
                              width: double.infinity,
                              height: 130,
                              radius: 12,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5)),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

/// Tiny helper so the empty-state CTA can guard sign-in without extra imports.
class AuthGuardRoute {
  AuthGuardRoute._();

  static void push(BuildContext context, String route) {
    final loggedIn = SupabaseService().auth.currentUser != null;
    if (loggedIn) {
      context.push(route);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please sign in to continue.')));
      context.push('/login');
    }
  }
}
