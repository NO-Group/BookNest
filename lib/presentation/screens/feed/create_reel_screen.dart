// lib/presentation/screens/feed/create_reel_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../services/supabase_service.dart';
import '../../../config/theme.dart';

class CreateReelScreen extends StatefulWidget {
  const CreateReelScreen({super.key});

  @override
  State<CreateReelScreen> createState() => _CreateReelScreenState();
}

class _CreateReelScreenState extends State<CreateReelScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isLoading = false;

  Future<void> _publishReel() async {
    if (_titleController.text.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final userId = SupabaseService().auth.currentUser!.id;
      await SupabaseService().client.from('posts').insert({
        'type': 'reel',
        'title': _titleController.text.trim(),
        'content': _descriptionController.text.trim(),
        'metadata': {
          'duration': '0:00',
          'views': 0,
          'thumbnail_url': null,
        },
        'created_by': userId,
      });

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
            content: Text('Reel placeholder created! Video upload coming soon.'),
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
        title: const Text('Create Reel'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _publishReel,
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
            // Video upload placeholder
            Container(
              width: double.infinity,
              height: 240,
              decoration: BoxDecoration(
                color: NOC.surfaceAlt,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: NOC.textFaint,
                  style: BorderStyle.solid,
                ),
              ),
              child:  Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.videocam,
                    size: 48,
                    color: NOC.textFaint,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Video upload coming soon',
                    style: TextStyle(
                      color: NOC.textMuted,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'For now, create a placeholder reel',
                    style: TextStyle(
                      color: NOC.textFaint,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _titleController,
              style:  TextStyle(color: NOC.text, fontSize: 18, fontWeight: FontWeight.bold),
              decoration:  InputDecoration(
                hintText: 'Reel title',
                hintStyle: TextStyle(color: NOC.textFaint),
                border: InputBorder.none,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              style:  TextStyle(color: NOC.text, fontSize: 14, height: 1.6),
              maxLines: 3,
              decoration:  InputDecoration(
                hintText: 'Description...',
                hintStyle: TextStyle(color: NOC.textFaint),
                border: InputBorder.none,
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
    _descriptionController.dispose();
    super.dispose();
  }
}