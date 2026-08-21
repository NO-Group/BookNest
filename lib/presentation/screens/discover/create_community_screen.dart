// lib/presentation/screens/discover/create_community_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../services/supabase_service.dart';
import '../../../config/theme.dart';

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

      // Create the community. The database trigger automatically creates the
      // default Announcements group + Chat group (and the owner's memberships).
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

      // 2. Owner joins as member (triggers seed them into the default groups).
      await SupabaseService().client.from('community_members').insert({
        'community_id': communityId,
        'user_id': userId,
        'role': 'owner',
      });

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
            content: Text('Community created!'),
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
        title: const Text('New Community'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _createCommunity,
            child: _isLoading
                ?  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: NOC.text),
                  )
                :  Text('Create', style: TextStyle(color: NOC.accent)),
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
                  Text(
                    'Add cover photo',
                    style: TextStyle(color: NOC.textFaint, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              style:  TextStyle(color: NOC.text, fontSize: 20, fontWeight: FontWeight.bold),
              decoration:  InputDecoration(
                hintText: 'Community name',
                hintStyle: TextStyle(color: NOC.textFaint),
                border: InputBorder.none,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              style:  TextStyle(color: NOC.text, fontSize: 16, height: 1.6),
              maxLines: 4,
              decoration:  InputDecoration(
                hintText: 'What is this community about?',
                hintStyle: TextStyle(color: NOC.textFaint),
                border: InputBorder.none,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: NOC.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
              ),
              child:  Row(
                children: [
                  Icon(Icons.info_outline, color: NOC.textMuted, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'An Announcements group (admins only) and a Chat group will be created automatically. You can add more groups and link Clubs, Organizations, and Schools later.',
                      style: TextStyle(color: NOC.textMuted, fontSize: 12, height: 1.5),
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