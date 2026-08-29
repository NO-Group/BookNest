// lib/presentation/screens/feed/create_reel_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../config/theme.dart';
import '../../../services/supabase_service.dart';

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
          const SnackBar(
            content: Text('Reel placeholder created! Video upload coming soon.'),
            backgroundColor: BookNestColors.cyan,
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
      appBar: AppBar(
        title: const Text('Create Reel'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _publishReel,
            child: _isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onSurface),
                  )
                : const Text('Post', style: TextStyle(color: BookNestColors.cyan)),
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
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: BookNestColors.lightTextSecondary,
                  style: BorderStyle.solid,
                ),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.videocam,
                    size: 48,
                    color: BookNestColors.lightTextSecondary,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Video upload coming soon',
                    style: TextStyle(
                      color: BookNestColors.lightTextSecondary,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'For now, create a placeholder reel',
                    style: TextStyle(
                      color: BookNestColors.lightTextSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _titleController,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                hintText: 'Reel title',
                hintStyle: TextStyle(color: BookNestColors.lightTextSecondary),
                border: InputBorder.none,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, height: 1.6),
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Description...',
                hintStyle: TextStyle(color: BookNestColors.lightTextSecondary),
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