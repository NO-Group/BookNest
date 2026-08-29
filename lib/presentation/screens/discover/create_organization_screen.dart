// lib/presentation/screens/discover/create_organization_screen.dart

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../config/theme.dart';
import '../../../services/cloudinary_service.dart';
import '../../../services/supabase_service.dart';

class CreateOrganizationScreen extends StatefulWidget {
  const CreateOrganizationScreen({super.key});

  @override
  State<CreateOrganizationScreen> createState() => _CreateOrganizationScreenState();
}

class _CreateOrganizationScreenState extends State<CreateOrganizationScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _missionController = TextEditingController();
  String _selectedType = 'Non-Profit';
  bool _isLoading = false;

  final List<String> _orgTypes = [
    'Non-Profit',
    'Educational',
    'Tech',
    'Literary',
    'Cultural',
    'Professional',
  ];


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
      setState(() => _coverBytes = await file.readAsBytes());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not open the photo picker.')));
      }
    }
  }

  Future<void> _createOrganization() async {
    if (_nameController.text.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final userId = SupabaseService().auth.currentUser!.id;

      String? coverUrl;
      if (_coverBytes != null) {
        coverUrl = await CloudinaryService.uploadImage(
          bytes: _coverBytes!,
          folder: 'covers',
          publicId: 'org-$userId-${DateTime.now().millisecondsSinceEpoch}',
        );
      }

      await SupabaseService().writeRow('organizations', {
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'mission': _missionController.text.trim(),
        'org_type': _selectedType,
        'owner_id': userId,
        'vice_moderator_id': null,
        'is_verified': false,
        if (coverUrl != null) 'cover_url': coverUrl,
      });

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Organization created!'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Organization'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _createOrganization,
            child: _isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onSurface),
                  )
                : const Text('Create', style: TextStyle(color: BookNestColors.navy)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Cover
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
                      size: 40, color: BookNestColors.lightTextSecondary),
                  const SizedBox(height: 8),
                  Text('Add cover photo',
                      style: const TextStyle(
                          color: BookNestColors.lightTextSecondary, fontSize: 14)),
                ],
                  )
                  : null,
            ),
          ),
          const SizedBox(height: 24),

          // Name
          TextField(
            controller: _nameController,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 20, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              hintText: 'Organization name',
              hintStyle: TextStyle(color: BookNestColors.lightTextSecondary),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 16),

          // Type selector
          const Text('Organization Type', style: TextStyle(color: BookNestColors.lightTextSecondary, fontSize: 14)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _orgTypes.map((type) {
              final isSelected = _selectedType == type;
              return GestureDetector(
                onTap: () => setState(() => _selectedType = type),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? BookNestColors.navy : Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: isSelected ? null : Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Text(
                    type,
                    style: TextStyle(
                      color: isSelected ? BookNestColors.navyDeep : Theme.of(context).colorScheme.onSurface,
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // Description
          TextField(
            controller: _descriptionController,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16, height: 1.6),
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'What does your organization do?',
              hintStyle: TextStyle(color: BookNestColors.lightTextSecondary),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 16),

          // Mission
          const Text('Mission Statement', style: TextStyle(color: BookNestColors.lightTextSecondary, fontSize: 14)),
          const SizedBox(height: 8),
          TextField(
            controller: _missionController,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, height: 1.6),
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Your mission...',
              hintStyle: const TextStyle(color: BookNestColors.lightTextSecondary),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Features preview
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Organization Features',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 12),
                _FeatureRow(icon: Icons.verified, text: 'Verified badge (after review)'),
                SizedBox(height: 8),
                _FeatureRow(icon: Icons.account_tree, text: 'Role-based hierarchy (Owner, Vice, Moderators)'),
                SizedBox(height: 8),
                _FeatureRow(icon: Icons.announcement, text: 'Official announcements & documents'),
                SizedBox(height: 8),
                _FeatureRow(icon: Icons.event, text: 'Event calendar with RSVP'),
                SizedBox(height: 8),
                _FeatureRow(icon: Icons.folder, text: 'Resource library (PDFs, syllabi, templates)'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _missionController.dispose();
    super.dispose();
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: BookNestColors.cyan),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: BookNestColors.lightTextSecondary, fontSize: 12),
          ),
        ),
      ],
    );
  }
}