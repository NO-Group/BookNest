// lib/presentation/screens/discover/create_organization_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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

  Future<void> _createOrganization() async {
    if (_nameController.text.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final userId = SupabaseService().auth.currentUser!.id;

      await SupabaseService().client.from('organizations').insert({
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'mission': _missionController.text.trim(),
        'org_type': _selectedType,
        'owner_id': userId,
        'vice_moderator_id': null,
        'is_verified': false,
      });

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Organization created!'),
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
        title: const Text('New Organization'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _createOrganization,
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
                Text('Add cover photo', style: TextStyle(color: Color(0xFF666666), fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Name
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              hintText: 'Organization name',
              hintStyle: TextStyle(color: Color(0xFF444444)),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 16),

          // Type selector
          const Text('Organization Type', style: TextStyle(color: Color(0xFF888888), fontSize: 14)),
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
                    color: isSelected ? const Color(0xFFFF6A00) : const Color(0xFF1F1F1F),
                    borderRadius: BorderRadius.circular(20),
                    border: isSelected ? null : Border.all(color: const Color(0xFF222222)),
                  ),
                  child: Text(
                    type,
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

          // Description
          TextField(
            controller: _descriptionController,
            style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.6),
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'What does your organization do?',
              hintStyle: TextStyle(color: Color(0xFF444444)),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 16),

          // Mission
          const Text('Mission Statement', style: TextStyle(color: Color(0xFF888888), fontSize: 14)),
          const SizedBox(height: 8),
          TextField(
            controller: _missionController,
            style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.6),
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Your mission...',
              hintStyle: const TextStyle(color: Color(0xFF444444)),
              filled: true,
              fillColor: const Color(0xFF1F1F1F),
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
              color: const Color(0xFF1F1F1F),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Organization Features',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
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
        Icon(icon, size: 16, color: const Color(0xFF00D4FF)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
          ),
        ),
      ],
    );
  }
}