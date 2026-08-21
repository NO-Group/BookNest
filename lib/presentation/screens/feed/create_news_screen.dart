// lib/presentation/screens/feed/create_news_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../services/supabase_service.dart';
import '../../../config/theme.dart';

class CreateNewsScreen extends StatefulWidget {
  const CreateNewsScreen({super.key});

  @override
  State<CreateNewsScreen> createState() => _CreateNewsScreenState();
}

class _CreateNewsScreenState extends State<CreateNewsScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _sourceController = TextEditingController();
  bool _isLoading = false;

  Future<void> _publishNews() async {
    if (_titleController.text.isEmpty || _contentController.text.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final userId = SupabaseService().auth.currentUser!.id;
      await SupabaseService().client.from('posts').insert({
        'type': 'news',
        'title': _titleController.text.trim(),
        'content': _contentController.text.trim(),
        'metadata': {
          'source': _sourceController.text.trim(),
        },
        'created_by': userId,
      });

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
            content: Text('News posted!'),
            backgroundColor: NOC.hot,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NOC.bg,
      appBar: AppBar(
        title: const Text('Share News'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _publishNews,
            child: _isLoading
                ?  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: NOC.text),
                  )
                :  Text('Post', style: TextStyle(color: NOC.hot)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              style:  TextStyle(color: NOC.text, fontSize: 20, fontWeight: FontWeight.bold),
              decoration:  InputDecoration(
                hintText: 'Headline',
                hintStyle: TextStyle(color: NOC.textFaint, fontSize: 20),
                border: InputBorder.none,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _contentController,
              style:  TextStyle(color: NOC.text, fontSize: 16, height: 1.6),
              maxLines: 10,
              decoration:  InputDecoration(
                hintText: 'Write the news story...',
                hintStyle: TextStyle(color: NOC.textFaint),
                border: InputBorder.none,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: NOC.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                   Icon(Icons.link, color: NOC.textMuted, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _sourceController,
                      style:  TextStyle(color: NOC.text),
                      decoration:  InputDecoration(
                        hintText: 'Source URL (optional)',
                        hintStyle: TextStyle(color: NOC.textFaint),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _sourceController.dispose();
    super.dispose();
  }
}