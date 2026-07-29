import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

class PublishDetailsScreen extends StatefulWidget {
  final String initialTitle;
  final dynamic quillDocumentJson;

  const PublishDetailsScreen({
    super.key,
    required this.initialTitle,
    required this.quillDocumentJson,
  });

  @override
  State<PublishDetailsScreen> createState() => _PublishDetailsScreenState();
}

class _PublishDetailsScreenState extends State<PublishDetailsScreen> {
  late final TextEditingController _titleController;
  final _teaserController = TextEditingController();
  final _summaryController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
  }

  Future<void> _finalPublish() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title cannot be empty'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) throw Exception('User not authenticated');

      await Supabase.instance.client.from('club_books').insert({
        'title': _titleController.text.trim(),
        'description': _summaryController.text.trim(),
        'content_format': 'json',
        'added_by': currentUserId,
        'metadata': {
          'teaser': _teaserController.text.trim(),
          'rich_content': widget.quillDocumentJson,
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Book published successfully!'), backgroundColor: Colors.green),
        );
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _teaserController.dispose();
    _summaryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Publish Details', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Book Title', style: TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 8),
            _buildTextField(controller: _titleController, hintText: 'Enter title'),
            const SizedBox(height: 20),
            
            const Text('Teaser (Short Hook)', style: TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 8),
            _buildTextField(controller: _teaserController, hintText: 'Write a short hook to grab readers...', maxLines: 2),
            const SizedBox(height: 20),

            const Text('Summary', style: TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 8),
            _buildTextField(controller: _summaryController, hintText: 'Provide a full summary of the book...', maxLines: 5),
            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _finalPublish,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FFFF),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.black)
                    : const Text('Confirm & Publish', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String hintText, int maxLines = 1}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: const Color(0xFF2A2A2A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}