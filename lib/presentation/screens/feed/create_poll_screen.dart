// lib/presentation/screens/feed/create_poll_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../services/supabase_service.dart';
import '../../../config/theme.dart';

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
      await SupabaseService().client.from('posts').insert({
        'type': 'poll',
        'content': _questionController.text.trim(),
        'metadata': {
          'options': options,
          'votes': 0,
        },
        'created_by': userId,
      });

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
            content: Text('Poll posted!'),
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
        title: const Text('Create Poll'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _publishPoll,
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
            TextField(
              controller: _questionController,
              style:  TextStyle(color: NOC.text, fontSize: 18),
              decoration:  InputDecoration(
                hintText: 'Ask a question...',
                hintStyle: TextStyle(color: NOC.textFaint),
                border: InputBorder.none,
              ),
            ),
            const SizedBox(height: 32),
             Text(
              'Options',
              style: TextStyle(color: NOC.textMuted, fontSize: 14),
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
                        border: Border.all(color: NOC.textMuted),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _optionControllers[index],
                        style:  TextStyle(color: NOC.text),
                        decoration: InputDecoration(
                          hintText: 'Option ${index + 1}',
                          hintStyle:  TextStyle(color: NOC.textFaint),
                          filled: true,
                          fillColor: NOC.surfaceAlt,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    if (_optionControllers.length > 2)
                      IconButton(
                        icon:  Icon(Icons.close, color: NOC.textMuted, size: 20),
                        onPressed: () => _removeOption(index),
                      ),
                  ],
                ),
              );
            }),
            if (_optionControllers.length < 6)
              TextButton.icon(
                onPressed: _addOption,
                icon:  Icon(Icons.add, color: NOC.accent),
                label:  Text('Add option', style: TextStyle(color: NOC.accent)),
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