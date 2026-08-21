// lib/presentation/screens/feed/create_quote_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../services/supabase_service.dart';
import '../../../config/theme.dart';

class CreateQuoteScreen extends StatefulWidget {
  const CreateQuoteScreen({super.key});

  @override
  State<CreateQuoteScreen> createState() => _CreateQuoteScreenState();
}

class _CreateQuoteScreenState extends State<CreateQuoteScreen> {
  final _contentController = TextEditingController();
  final _authorController = TextEditingController();
  bool _isLoading = false;

  Future<void> _publishQuote() async {
    if (_contentController.text.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final userId = SupabaseService().auth.currentUser!.id;
      await SupabaseService().client.from('posts').insert({
        'type': 'quote',
        'content': _contentController.text.trim(),
        'metadata': {
          'quote_author': _authorController.text.trim(),
        },
        'created_by': userId,
      });

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
            content: Text('Quote posted!'),
            backgroundColor: NOC.accent,
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
        title: const Text('Share a Quote'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _publishQuote,
            child: _isLoading
                ?  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: NOC.text),
                  )
                :  Text('Post', style: TextStyle(color: NOC.accent)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preview
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: NOC.surfaceAlt,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: NOC.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Icon(
                    Icons.format_quote,
                    color: NOC.accent,
                    size: 32,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '"${_contentController.text.isEmpty ? 'Your quote will appear here' : _contentController.text}"',
                    style: TextStyle(
                      color: _contentController.text.isEmpty
                          ? NOC.textFaint
                          : NOC.text,
                      fontSize: 18,
                      fontStyle: FontStyle.italic,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 3,
                        height: 20,
                        decoration: BoxDecoration(
                          color: NOC.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '— ${_authorController.text.isEmpty ? 'Author name' : _authorController.text}',
                        style: TextStyle(
                          color: _authorController.text.isEmpty
                              ? NOC.textFaint
                              : NOC.textMuted,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Inputs
             Text(
              'Quote',
              style: TextStyle(
                color: NOC.textMuted,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _contentController,
              onChanged: (_) => setState(() {}),
              style:  TextStyle(color: NOC.text),
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Enter the quote...',
                hintStyle:  TextStyle(color: NOC.textFaint),
                filled: true,
                fillColor: NOC.surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
             Text(
              'Author',
              style: TextStyle(
                color: NOC.textMuted,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _authorController,
              onChanged: (_) => setState(() {}),
              style:  TextStyle(color: NOC.text),
              decoration: InputDecoration(
                hintText: 'Who said this?',
                hintStyle:  TextStyle(color: NOC.textFaint),
                filled: true,
                fillColor: NOC.surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _contentController.dispose();
    _authorController.dispose();
    super.dispose();
  }
}