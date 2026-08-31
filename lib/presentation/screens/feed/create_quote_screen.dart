// lib/presentation/screens/feed/create_quote_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../../config/theme.dart';
import '../../../services/supabase_service.dart';

class CreateQuoteScreen extends StatefulWidget {
  const CreateQuoteScreen({super.key});

  @override
  State<CreateQuoteScreen> createState() => _CreateQuoteScreenState();
}

class _CreateQuoteScreenState extends State<CreateQuoteScreen> {
  final _contentController = TextEditingController();
  final _authorController = TextEditingController();
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

  Future<void> _publishQuote() async {
    if (_contentController.text.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final userId = SupabaseService().auth.currentUser!.id;
      await SupabaseService().writeRow('posts', {
        'type': 'quote',
        'content': _contentController.text.trim(),
        'metadata': {
          'quote_author': _authorController.text.trim(),
          if (_selectedPostDate != null)
            'date': DateFormat('EEE, MMM d, yyyy').format(_selectedPostDate!),
        },
        'created_by': userId,
      });

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Quote posted!'),
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
        title: const Text('Share a Quote'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _publishQuote,
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDateChip(Theme.of(context)),
            const SizedBox(height: 18),
            // Preview
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.format_quote,
                    color: BookNestColors.cyan,
                    size: 32,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '"${_contentController.text.isEmpty ? 'Your quote will appear here' : _contentController.text}"',
                    style: TextStyle(
                      color: _contentController.text.isEmpty
                          ? BookNestColors.lightTextSecondary
                          : Theme.of(context).colorScheme.onSurface,
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
                          color: BookNestColors.cyan,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '— ${_authorController.text.isEmpty ? 'Author name' : _authorController.text}',
                        style: TextStyle(
                          color: _authorController.text.isEmpty
                              ? BookNestColors.lightTextSecondary
                              : BookNestColors.lightTextSecondary,
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
                color: BookNestColors.lightTextSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _contentController,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Enter the quote...',
                hintStyle: const TextStyle(color: BookNestColors.lightTextSecondary),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
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
                color: BookNestColors.lightTextSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _authorController,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: 'Who said this?',
                hintStyle: const TextStyle(color: BookNestColors.lightTextSecondary),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
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