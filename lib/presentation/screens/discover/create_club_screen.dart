// lib/presentation/screens/discover/create_club_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../services/supabase_service.dart';
import '../../../config/theme.dart';

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

      final clubResponse = await SupabaseService()
          .client
          .from('clubs')
          .insert({
            'name': _nameController.text.trim(),
            'description': _descriptionController.text.trim(),
            'genre_tags': [_selectedGenre],
            'is_private': _isPrivate,
            'owner_id': userId,
            'vice_moderator_id': null,
          })
          .select();

      // Owner joins as a member (seeds them into the default chat group).
      final clubId = clubResponse[0]['id'];
      await SupabaseService().client.from('club_members').insert({
        'club_id': clubId,
        'user_id': userId,
        'role': 'owner',
      });

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
            content: Text('Club created!'),
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
        title: const Text('New Club'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _createClub,
            child: _isLoading
                ?  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: NOC.text),
                  )
                :  Text('Create', style: TextStyle(color: NOC.hot)),
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
              color: NOC.border,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: NOC.textFaint,
                style: BorderStyle.solid,
              ),
            ),
            child:  Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_photo_alternate, size: 40, color: NOC.textFaint),
                SizedBox(height: 8),
                Text('Add club cover', style: TextStyle(color: NOC.textFaint, fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Name
          TextField(
            controller: _nameController,
            style:  TextStyle(color: NOC.text, fontSize: 20, fontWeight: FontWeight.bold),
            decoration:  InputDecoration(
              hintText: 'Club name',
              hintStyle: TextStyle(color: NOC.textFaint),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 16),

          // Description
          TextField(
            controller: _descriptionController,
            style:  TextStyle(color: NOC.text, fontSize: 16, height: 1.6),
            maxLines: 3,
            decoration:  InputDecoration(
              hintText: 'What will you read together?',
              hintStyle: TextStyle(color: NOC.textFaint),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 24),

          // Genre
           Text('Genre', style: TextStyle(color: NOC.textMuted, fontSize: 14)),
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
                    color: isSelected ? NOC.hot : NOC.surfaceAlt,
                    borderRadius: BorderRadius.circular(20),
                    border: isSelected ? null : Border.all(color: NOC.border),
                  ),
                  child: Text(
                    genre,
                    style: TextStyle(
                      color: isSelected ? NOC.text : NOC.text,
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
            title:  Text('Private Club', style: TextStyle(color: NOC.text)),
            subtitle: Text(
              _isPrivate ? 'Invite-only' : 'Anyone can join',
              style:  TextStyle(color: NOC.textMuted, fontSize: 12),
            ),
            value: _isPrivate,
            onChanged: (v) => setState(() => _isPrivate = v),
            activeThumbColor: NOC.hot,
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