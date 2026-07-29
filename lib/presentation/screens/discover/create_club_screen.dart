// lib/presentation/screens/discover/create_club_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../services/supabase_service.dart';

class CreateClubScreen extends StatefulWidget {
  const CreateClubScreen({super.key});

  @override
  State<CreateClubScreen> createState() => _CreateClubScreenState();
}

class _CreateClubScreenState extends State<CreateClubScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _selectedGenre = 'Fiction';
  bool _isPrivate = false;
  bool _isLoading = false;

  final List<String> _genres = [
    'Fiction',
    'Non-Fiction',
    'Sci-Fi',
    'Classics',
    'African Lit',
    'Romance',
    'Thriller',
    'Poetry',
    'Academic',
    'WAEC Prep',
  ];

  Future<void> _createClub() async {
    if (_nameController.text.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final userId = SupabaseService().auth.currentUser!.id;

      await SupabaseService().client.from('clubs').insert({
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'genre_tags': [_selectedGenre],
        'is_private': _isPrivate,
        'owner_id': userId,
        'vice_moderator_id': null,
      });

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Club created!'),
            backgroundColor: Color(0xFFFF6A00),
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
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('New Club'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _createClub,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Create', style: TextStyle(color: Color(0xFFFF6A00))),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Cover
          Container(
            width: double.infinity,
            height: 160,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF444444),
                style: BorderStyle.solid,
              ),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_photo_alternate, size: 40, color: Color(0xFF444444)),
                SizedBox(height: 8),
                Text('Add club cover', style: TextStyle(color: Color(0xFF666666), fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Name
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              hintText: 'Club name',
              hintStyle: TextStyle(color: Color(0xFF444444)),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 16),

          // Description
          TextField(
            controller: _descriptionController,
            style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.6),
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'What will you read together?',
              hintStyle: TextStyle(color: Color(0xFF444444)),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 24),

          // Genre
          const Text('Genre', style: TextStyle(color: Color(0xFF888888), fontSize: 14)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _genres.map((genre) {
              final isSelected = _selectedGenre == genre;
              return GestureDetector(
                onTap: () => setState(() => _selectedGenre = genre),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFFF6A00) : const Color(0xFF1F1F1F),
                    borderRadius: BorderRadius.circular(20),
                    border: isSelected ? null : Border.all(color: const Color(0xFF222222)),
                  ),
                  child: Text(
                    genre,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white,
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // Privacy
          SwitchListTile(
            title: const Text('Private Club', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              _isPrivate ? 'Invite-only' : 'Anyone can join',
              style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
            ),
            value: _isPrivate,
            onChanged: (v) => setState(() => _isPrivate = v),
            activeThumbColor: const Color(0xFFFF6A00),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}