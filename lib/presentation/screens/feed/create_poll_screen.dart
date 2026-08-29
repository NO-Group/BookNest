// lib/presentation/screens/feed/create_poll_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../../config/theme.dart';
import '../../../services/supabase_service.dart';

class CreatePollScreen extends StatefulWidget {
  const CreatePollScreen({super.key});

  @override
  State<CreatePollScreen> createState() => _CreatePollScreenState();
}

class _CreatePollScreenState extends State<CreatePollScreen> {
  final _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _isLoading = false;

  void _addOption() {
    if (_optionControllers.length < 6) {
      setState(() => _optionControllers.add(TextEditingController()));
    }
  }

  void _removeOption(int index) {
    if (_optionControllers.length > 2) {
      setState(() {
        _optionControllers[index].dispose();
        _optionControllers.removeAt(index);
      });
    }
  }


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

  Future<void> _publishPoll() async {
    if (_questionController.text.isEmpty) return;
    final options = _optionControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (options.length < 2) return;

    setState(() => _isLoading = true);

    try {
      final userId = SupabaseService().auth.currentUser!.id;
      await SupabaseService().writeRow('posts', {
        'type': 'poll',
        'content': _questionController.text.trim(),
        'metadata': {
          'options': options,
          'votes': 0,
          if (_selectedPostDate != null)
            'date': DateFormat('EEE, MMM d, yyyy').format(_selectedPostDate!),
        },
        'created_by': userId,
      });

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Poll posted!'),
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
        title: const Text('Create Poll'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _publishPoll,
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
            _buildDateChip(Theme.of(context)),
            const SizedBox(height: 18),
            TextField(
              controller: _questionController,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 18),
              decoration: const InputDecoration(
                hintText: 'Ask a question...',
                hintStyle: TextStyle(color: BookNestColors.lightTextSecondary),
                border: InputBorder.none,
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Options',
              style: TextStyle(color: BookNestColors.lightTextSecondary, fontSize: 14),
            ),
            const SizedBox(height: 12),
            ...List.generate(_optionControllers.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: BookNestColors.lightTextSecondary),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _optionControllers[index],
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                        decoration: InputDecoration(
                          hintText: 'Option ${index + 1}',
                          hintStyle: const TextStyle(color: BookNestColors.lightTextSecondary),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    if (_optionControllers.length > 2)
                      IconButton(
                        icon: const Icon(Icons.close, color: BookNestColors.lightTextSecondary, size: 20),
                        onPressed: () => _removeOption(index),
                      ),
                  ],
                ),
              );
            }),
            if (_optionControllers.length < 6)
              TextButton.icon(
                onPressed: _addOption,
                icon: const Icon(Icons.add, color: BookNestColors.cyan),
                label: const Text('Add option', style: TextStyle(color: BookNestColors.cyan)),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _questionController.dispose();
    for (var c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }
}