import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../../services/cloudinary_service.dart';
import '../../../services/supabase_service.dart';
import '../../components/booknest_ui.dart';

/// Manage a published book: metadata, cover art, genre. Writes to the
/// transitional Supabase row (works today) and syncs to MongoDB (edge API).
class ManageBookScreen extends StatefulWidget {
  final String bookId;

  const ManageBookScreen({super.key, required this.bookId});

  @override
  State<ManageBookScreen> createState() => _ManageBookScreenState();
}

class _ManageBookScreenState extends State<ManageBookScreen> {
  Map<String, dynamic>? _book;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingCover = false;
  String? _pickedCoverUrl;

  late final TextEditingController _title = TextEditingController();
  late final TextEditingController _description = TextEditingController();
  String? _genre;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final row = await SupabaseService()
          .client
          .from('club_books')
          .select()
          .eq('id', widget.bookId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _book = row == null ? null : Map<String, dynamic>.from(row);
        _title.text = _book?['title']?.toString() ?? '';
        _description.text = _book?['description']?.toString() ?? '';
        final genre = _book?['genre']?.toString();
        _genre = kBookNestGenres.contains(genre) ? genre : null;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeCover() async {
    try {
      final file = await ImagePicker()
          .pickImage(source: ImageSource.gallery, maxWidth: 1200, maxHeight: 1600);
      if (file == null) return;
      setState(() => _uploadingCover = true);
      final bytes = await file.readAsBytes();
      final url = await CloudinaryService.uploadImage(
        bytes: bytes,
        folder: 'covers',
        publicId: 'cover-${widget.bookId}-${DateTime.now().millisecondsSinceEpoch}',
        extension: file.name.contains('.')
            ? file.name.split('.').last.toLowerCase()
            : 'jpg',
      );
      if (!mounted) return;
      setState(() {
        _uploadingCover = false;
        _pickedCoverUrl = url ?? _pickedCoverUrl;
      });
      if (url == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Cover upload failed — try again.')));
      }
    } catch (_) {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Give the book a proper title.')));
      return;
    }
    setState(() => _saving = true);
    final coverUrl = _pickedCoverUrl;
    try {
      await SupabaseService().client.from('club_books').update({
        'title': title,
        'description': _description.text.trim(),
        'genre': _genre,
        if (coverUrl != null) 'cover_url': coverUrl,
      }).eq('id', widget.bookId);
      // Best-effort sync to MongoDB (no-op until the cloud is connected).
      await BackendApi.instance.updateBook(
        bookId: widget.bookId,
        title: title,
        description: _description.text.trim(),
        genre: _genre,
        coverUrl: coverUrl,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Book updated ✓')));
      context.pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not save — check your connection.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Scaffold(
          body: Center(
              child: CircularProgressIndicator(color: BookNestColors.cyan)));
    }
    if (_book == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: const EmptyState(
          icon: Icons.search_off_rounded,
          title: 'Book not found',
          subtitle: 'It may have been removed.',
        ),
      );
    }
    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
          ? BookNestColors.darkChatBackground
          : BookNestColors.lightSurface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Manage book',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: _uploadingCover ? null : _changeCover,
                  child: Stack(
                    children: [
                      BookCover(
                        coverUrl: _pickedCoverUrl ??
                            _book?['cover_url']?.toString(),
                        title: _title.text.isEmpty ? 'Cover' : _title.text,
                        width: 96,
                        height: 130,
                        radius: 14,
                      ),
                      if (_uploadingCover)
                        const Positioned.fill(
                          child: ColoredBox(
                            color: Colors.black45,
                            child: Center(
                              child: CircularProgressIndicator(
                                  color: BookNestColors.cyan, strokeWidth: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Cover art',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                        'Tap the cover to upload. Cloudinary resizes and '
                        'optimizes it automatically.',
                        style: TextStyle(
                            color: theme.hintColor,
                            fontSize: 12.5,
                            height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _Field(
                label: 'Title',
                child: TextField(
                  controller: _title,
                  onChanged: (_) => setState(() {}),
                  decoration: _inputDecoration(theme),
                )),
            const SizedBox(height: 16),
            _Field(
              label: 'Genre',
              child: DropdownButtonFormField<String>(
                value: _genre,
                hint: const Text('Pick one of the 22 BookNest genres'),
                isExpanded: true,
                decoration: _inputDecoration(theme),
                dropdownColor: theme.colorScheme.surface,
                items: kBookNestGenres
                    .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                    .toList(),
                onChanged: (value) => setState(() => _genre = value),
              ),
            ),
            const SizedBox(height: 16),
            _Field(
              label: 'Description',
              child: TextField(
                controller: _description,
                minLines: 4,
                maxLines: 8,
                decoration: _inputDecoration(theme, hint: 'What is it about?'),
              ),
            ),
            const SizedBox(height: 24),
            GradientButton(
                label: 'Save changes',
                icon: Icons.check_rounded,
                busy: _saving,
                onPressed: _save),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.push('/manage/${widget.bookId}/chapters'),
              style: OutlinedButton.styleFrom(
                foregroundColor: BookNestColors.cyan,
                side: const BorderSide(color: BookNestColors.cyan),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.format_list_bulleted_rounded, size: 19),
              label: const Text('Manage chapters',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(ThemeData theme, {String? hint}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: theme.colorScheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: theme.dividerColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: theme.dividerColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: BookNestColors.cyan, width: 1.6),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final Widget child;
  const _Field({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
