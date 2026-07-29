import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import '../../../services/supabase_service.dart';

class BookEditorScreen extends StatefulWidget {
  final String? clubId;
  
  const BookEditorScreen({Key? key, this.clubId}) : super(key: key);

  @override
  State<BookEditorScreen> createState() => _BookEditorScreenState();
}

class _BookEditorScreenState extends State<BookEditorScreen> {
  final _titleController = TextEditingController();
  late final quill.QuillController _quillController;
  final FocusNode _editorFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _quillController = quill.QuillController.basic();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _quillController.dispose();
    _editorFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _saveBook() async {
    final title = _titleController.text.trim();
    final plainText = _quillController.document.toPlainText().trim();
    
    if (title.isEmpty || plainText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a title and start writing your story.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      final supabase = SupabaseService().client;
      final user = supabase.auth.currentUser!;
      
      final deltaJson = jsonEncode(_quillController.document.toDelta().toJson());
      
      final bookResponse = await supabase.from('club_books').insert({
        'club_id': widget.clubId,
        'title': title,
        'author': user.email,
        'description': plainText.substring(0, plainText.length > 100 ? 100 : plainText.length),
        'content_format': 'delta', 
        'moderation_status': 'pending',
        'added_by': user.id,
      }).select();
      
      final bookId = bookResponse[0]['id'];
      
      await supabase.from('book_chapters').insert({
        'club_book_id': bookId,
        'chapter_number': 1,
        'title': 'Chapter 1',
        'content': deltaJson, 
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Book submitted for review'),
            backgroundColor: Color(0xFF00D4FF),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text('Write Book', style: TextStyle(color: Colors.white, fontSize: 18)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: TextButton(
              onPressed: _isLoading ? null : _saveBook,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00D4FF)),
                    )
                  : const Text(
                      'Publish', 
                      style: TextStyle(color: Color(0xFF00D4FF), fontWeight: FontWeight.bold, fontSize: 16),
                    ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _titleController,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                decoration: const InputDecoration(
                  hintText: 'Book Title',
                  hintStyle: TextStyle(color: Color(0xFF444444)),
                  border: InputBorder.none,
                ),
              ),
            ),
            
            const Divider(color: Color(0xFF222222), height: 1),
            
            // v2.0.7 precise toolbar syntax
            Theme(
              data: ThemeData.dark().copyWith(
                iconTheme: const IconThemeData(color: Colors.white70),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                color: const Color(0xFF141414),
                child: quill.QuillToolbar.basic(
                  controller: _quillController,
                ),
              ),
            ),
            
            const Divider(color: Color(0xFF222222), height: 1),
            
            // v2.0.7 precise editor syntax
            Expanded(
              child: Theme(
                data: ThemeData.dark(),
                child: Container(
                  color: const Color(0xFF0A0A0A),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: quill.QuillEditor(
                    controller: _quillController,
                    focusNode: _editorFocusNode,
                    scrollController: _scrollController,
                    scrollable: true,
                    autoFocus: false,
                    padding: EdgeInsets.zero,
                    expands: true,
                    readOnly: false, // Required boolean in older versions
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}