// lib/presentation/screens/discover/create_community_screen.dart

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../config/theme.dart';
import '../../../services/cloudinary_service.dart';
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


  Uint8List? _coverBytes;

  Future<void> _pickCover() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 900,
        imageQuality: 82,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => _coverBytes = bytes);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not open the photo picker.')));
      }
    }
  }

  Future<void> _createCommunity() async {
    if (_nameController.text.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final userId = SupabaseService().auth.currentUser!.id;
      
      // 1. Create community (with optional cover upload)
      String? coverUrl;
      if (_coverBytes != null) {
        coverUrl = await CloudinaryService.uploadImage(
          bytes: _coverBytes!,
          folder: 'covers',
          publicId:
              'community-$userId-${DateTime.now().millisecondsSinceEpoch}',
        );
      }

      final community = await SupabaseService().writeRow('communities', {
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'owner_id': userId,
        'vice_moderator_id': null,
        if (coverUrl != null) 'cover_url': coverUrl,
      });
      final communityId = community!['id'].toString();

      // 2. Create Announcements group automatically
      await SupabaseService().writeRow('announcement_groups', {
        'community_id': communityId,
        'name': '${_nameController.text.trim()} Announcements',
      });

      // 3. Owner joins as member
      await SupabaseService().writeRow('community_members', {
        'community_id': communityId,
        'user_id': userId,
        'role': 'owner',
      });

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Community created!'),
            backgroundColor: BookNestColors.cyan,
          ),
        );
      }
    } on WriteException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
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
        title: const Text('New Community'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _createCommunity,
            child: _isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onSurface),
                  )
                : const Text('Create', style: TextStyle(color: BookNestColors.cyan)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover — tap to choose, preview once chosen, upload on create
            GestureDetector(
              onTap: _isLoading ? null : _pickCover,
              child: Container(
                width: double.infinity,
                height: 160,
                decoration: BoxDecoration(
                  color: BookNestColors.navy,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: BookNestColors.lightTextSecondary,
                    style: BorderStyle.solid,
                  ),
                  image: _coverBytes != null
                      ? DecorationImage(
                          image: MemoryImage(_coverBytes!), fit: BoxFit.cover)
                      : null,
                ),
                child: _coverBytes == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_photo_alternate,
                              size: 40,
                              color: BookNestColors.lightTextSecondary),
                          const SizedBox(height: 8),
                          Text(
                            'Add cover photo',
                            style: const TextStyle(
                                color: BookNestColors.lightTextSecondary,
                                fontSize: 14),
                          ),
                        ],
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 20, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                hintText: 'Community name',
                hintStyle: TextStyle(color: BookNestColors.lightTextSecondary),
                border: InputBorder.none,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16, height: 1.6),
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'What is this community about?',
                hintStyle: TextStyle(color: BookNestColors.lightTextSecondary),
                border: InputBorder.none,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: BookNestColors.lightTextSecondary, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'An Announcements group will be created automatically. You can add Clubs, Organizations, and Schools later.',
                      style: TextStyle(color: BookNestColors.lightTextSecondary, fontSize: 12, height: 1.5),
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