// lib/presentation/screens/feed/create_news_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../../config/theme.dart';
import '../../../services/supabase_service.dart';

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


  DateTime? _selectedPostDate;

  Future<void> _pickPostDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedPostDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.dark(primary: BookNestColors.cyan),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedPostDate = picked);
  }

  Future<void> _publishNews() async {
    if (_titleController.text.isEmpty || _contentController.text.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final userId = SupabaseService().auth.currentUser!.id;
      await SupabaseService().writeRow('posts', {
        'type': 'news',
        'title': _titleController.text.trim(),
        'content': _contentController.text.trim(),
        'metadata': {
          'source': _sourceController.text.trim(),
          if (_selectedPostDate != null)
            'date': DateFormat('EEE, MMM d, yyyy').format(_selectedPostDate!),
        },
        'created_by': userId,
      });

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('News posted!'),
            backgroundColor: BookNestColors.navy,
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


  /// Optional publish date chip shown above the submit button.
  Widget _buildDateChip(ThemeData theme) {
    return Center(
      child: ActionChip(
        avatar: Icon(Icons.event_outlined,
            size: 18,
            color: _selectedPostDate != null
                ? BookNestColors.cyan
                : theme.hintColor),
        label: Text(
          _selectedPostDate == null
              ? 'Add date (optional)'
              : DateFormat('EEE, MMM d, yyyy').format(_selectedPostDate!),
          style:
              TextStyle(color: theme.colorScheme.onSurface, fontSize: 13),
        ),
        side: BorderSide(
            color: _selectedPostDate != null
                ? BookNestColors.cyan.withOpacity(.6)
                : theme.dividerColor),
        backgroundColor: theme.colorScheme.surface,
        onPressed: () async {
          await _pickPostDate();
          if (mounted) setState(() {});
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Share News'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _publishNews,
            child: _isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onSurface),
                  )
                : const Text('Post', style: TextStyle(color: BookNestColors.navy)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDateChip(Theme.of(context)),
            const SizedBox(height: 18),
            TextField(
              controller: _titleController,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 20, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                hintText: 'Headline',
                hintStyle: TextStyle(color: BookNestColors.lightTextSecondary, fontSize: 20),
                border: InputBorder.none,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _contentController,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16, height: 1.6),
              maxLines: 10,
              decoration: const InputDecoration(
                hintText: 'Write the news story...',
                hintStyle: TextStyle(color: BookNestColors.lightTextSecondary),
                border: InputBorder.none,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link, color: BookNestColors.lightTextSecondary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _sourceController,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                      decoration: const InputDecoration(
                        hintText: 'Source URL (optional)',
                        hintStyle: TextStyle(color: BookNestColors.lightTextSecondary),
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