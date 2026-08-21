// lib/presentation/screens/discover/create_organization_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../services/supabase_service.dart';
import '../../../config/theme.dart';

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

      final orgResponse = await SupabaseService()
          .client
          .from('organizations')
          .insert({
            'name': _nameController.text.trim(),
            'description': _descriptionController.text.trim(),
            'mission': _missionController.text.trim(),
            'org_type': _selectedType,
            'owner_id': userId,
            'vice_moderator_id': null,
            'is_verified': false,
          })
          .select();

      // Owner joins as a member (seeds them into the default chat group).
      final orgId = orgResponse[0]['id'];
      await SupabaseService().client.from('organization_members').insert({
        'organization_id': orgId,
        'user_id': userId,
        'role': 'owner',
      });

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
            content: Text('Organization created!'),
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
        title: const Text('New Organization'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _createOrganization,
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
                Text('Add cover photo', style: TextStyle(color: NOC.textFaint, fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Name
          TextField(
            controller: _nameController,
            style:  TextStyle(color: NOC.text, fontSize: 20, fontWeight: FontWeight.bold),
            decoration:  InputDecoration(
              hintText: 'Organization name',
              hintStyle: TextStyle(color: NOC.textFaint),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 16),

          // Type selector
           Text('Organization Type', style: TextStyle(color: NOC.textMuted, fontSize: 14)),
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
                    color: isSelected ? NOC.hot : NOC.surfaceAlt,
                    borderRadius: BorderRadius.circular(20),
                    border: isSelected ? null : Border.all(color: NOC.border),
                  ),
                  child: Text(
                    type,
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

          // Description
          TextField(
            controller: _descriptionController,
            style:  TextStyle(color: NOC.text, fontSize: 16, height: 1.6),
            maxLines: 3,
            decoration:  InputDecoration(
              hintText: 'What does your organization do?',
              hintStyle: TextStyle(color: NOC.textFaint),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 16),

          // Mission
           Text('Mission Statement', style: TextStyle(color: NOC.textMuted, fontSize: 14)),
          const SizedBox(height: 8),
          TextField(
            controller: _missionController,
            style:  TextStyle(color: NOC.text, fontSize: 14, height: 1.6),
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Your mission...',
              hintStyle:  TextStyle(color: NOC.textFaint),
              filled: true,
              fillColor: NOC.surfaceAlt,
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
              color: NOC.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child:  Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Organization Features',
                  style: TextStyle(color: NOC.text, fontSize: 14, fontWeight: FontWeight.bold),
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
        Icon(icon, size: 16, color: NOC.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style:  TextStyle(color: NOC.textMuted, fontSize: 12),
          ),
        ),
      ],
    );
  }
}