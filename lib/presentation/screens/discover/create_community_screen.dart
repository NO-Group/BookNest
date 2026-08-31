// lib/presentation/screens/discover/create_community_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../services/supabase_service.dart';

class CreateCommunityScreen extends StatefulWidget {
  const CreateCommunityScreen({super.key});

  @override
  State<CreateCommunityScreen> createState() => _CreateCommunityScreenState();
}

class _CreateCommunityScreenState extends State<CreateCommunityScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isLoading = false;

  Future<void> _createCommunity() async {
    if (_nameController.text.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final userId = SupabaseService().auth.currentUser!.id;
      
      // 1. Create community
      final communityResponse = await SupabaseService()
          .client
          .from('communities')
          .insert({
            'name': _nameController.text.trim(),
            'description': _descriptionController.text.trim(),
            'owner_id': userId,
            'vice_moderator_id': null,
          })
          .select();

      final communityId = communityResponse[0]['id'];

      // 2. Create Announcements group automatically
      await SupabaseService().client.from('announcement_groups').insert({
        'community_id': communityId,
        'name': '${_nameController.text.trim()} Announcements',
      });

      // 3. Owner joins as member
      await SupabaseService().client.from('community_members').insert({
        'community_id': communityId,
        'user_id': userId,
        'role': 'owner',
      });

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Community created!'),
            backgroundColor: Color(0xFF00D4FF),
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
        title: const Text('New Community'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _createCommunity,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Create', style: TextStyle(color: Color(0xFF00D4FF))),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover placeholder
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
                  Text(
                    'Add cover photo',
                    style: TextStyle(color: Color(0xFF666666), fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                hintText: 'Community name',
                hintStyle: TextStyle(color: Color(0xFF444444)),
                border: InputBorder.none,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.6),
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'What is this community about?',
                hintStyle: TextStyle(color: Color(0xFF444444)),
                border: InputBorder.none,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1F1F1F),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF888888), size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'An Announcements group will be created automatically. You can add Clubs, Organizations, and Schools later.',
                      style: TextStyle(color: Color(0xFF888888), fontSize: 12, height: 1.5),
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
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}