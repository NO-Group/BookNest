// lib/presentation/screens/discover/create_school_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../services/supabase_service.dart';
import '../../../config/theme.dart';

class CreateSchoolScreen extends StatefulWidget {
  const CreateSchoolScreen({super.key});

  @override
  State<CreateSchoolScreen> createState() => _CreateSchoolScreenState();
}

class _CreateSchoolScreenState extends State<CreateSchoolScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _websiteController = TextEditingController();
  String _schoolType = 'Secondary';
  bool _isLoading = false;

  final List<String> _schoolTypes = [
    'Primary',
    'Secondary',
    'University',
    'Vocational',
    'Online',
  ];

  Future<void> _createSchool() async {
    if (_nameController.text.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final userId = SupabaseService().auth.currentUser!.id;

      final schoolResponse = await SupabaseService()
          .client
          .from('schools')
          .insert({
            'name': _nameController.text.trim(),
            'description': _descriptionController.text.trim(),
            'location': _locationController.text.trim(),
            'website': _websiteController.text.trim(),
            'school_type': _schoolType,
            'owner_id': userId,
            'vice_moderator_id': null,
            'is_verified': false,
          })
          .select();

      // Owner joins as a member (seeds them into the default chat group).
      final schoolId = schoolResponse[0]['id'];
      await SupabaseService().client.from('school_members').insert({
        'school_id': schoolId,
        'user_id': userId,
        'role': 'owner',
      });

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
            content: Text('School registered!'),
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
        title: const Text('Register School'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _createSchool,
            child: _isLoading
                ?  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: NOC.text),
                  )
                :  Text('Register', style: TextStyle(color: NOC.accent)),
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
                Text('Add school photo', style: TextStyle(color: NOC.textFaint, fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Name
          TextField(
            controller: _nameController,
            style:  TextStyle(color: NOC.text, fontSize: 20, fontWeight: FontWeight.bold),
            decoration:  InputDecoration(
              hintText: 'School name',
              hintStyle: TextStyle(color: NOC.textFaint),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 16),

          // Type
           Text('School Type', style: TextStyle(color: NOC.textMuted, fontSize: 14)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _schoolTypes.map((type) {
              final isSelected = _schoolType == type;
              return GestureDetector(
                onTap: () => setState(() => _schoolType = type),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? NOC.accent : NOC.surfaceAlt,
                    borderRadius: BorderRadius.circular(20),
                    border: isSelected ? null : Border.all(color: NOC.border),
                  ),
                  child: Text(
                    type,
                    style: TextStyle(
                      color: isSelected ? NOC.bg : NOC.text,
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
              hintText: 'About this school...',
              hintStyle: TextStyle(color: NOC.textFaint),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 24),

          // Location
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: NOC.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                 Icon(Icons.location_on, color: NOC.textMuted, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _locationController,
                    style:  TextStyle(color: NOC.text),
                    decoration:  InputDecoration(
                      hintText: 'City, Country',
                      hintStyle: TextStyle(color: NOC.textFaint),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Website
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: NOC.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                 Icon(Icons.language, color: NOC.textMuted, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _websiteController,
                    style:  TextStyle(color: NOC.text),
                    decoration:  InputDecoration(
                      hintText: 'School website (optional)',
                      hintStyle: TextStyle(color: NOC.textFaint),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
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
                  'School Features',
                  style: TextStyle(color: NOC.text, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 12),
                _FeatureRow(icon: Icons.class_, text: 'Class/grade channels'),
                SizedBox(height: 8),
                _FeatureRow(icon: Icons.person, text: 'Teacher profiles & directories'),
                SizedBox(height: 8),
                _FeatureRow(icon: Icons.assignment, text: 'Assignment posting & tracking'),
                SizedBox(height: 8),
                _FeatureRow(icon: Icons.trending_up, text: 'Student reading progress'),
                SizedBox(height: 8),
                _FeatureRow(icon: Icons.timer, text: 'Exam countdown & schedule'),
                SizedBox(height: 8),
                _FeatureRow(icon: Icons.family_restroom, text: 'Parent access portal'),
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
    _locationController.dispose();
    _websiteController.dispose();
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