// lib/presentation/screens/discover/create_school_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../services/supabase_service.dart';

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

      await SupabaseService().client.from('schools').insert({
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'location': _locationController.text.trim(),
        'website': _websiteController.text.trim(),
        'school_type': _schoolType,
        'owner_id': userId,
        'vice_moderator_id': null,
        'is_verified': false,
      });

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('School registered!'),
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
        title: const Text('Register School'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _createSchool,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Register', style: TextStyle(color: Color(0xFF00D4FF))),
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
                Text('Add school photo', style: TextStyle(color: Color(0xFF666666), fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Name
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              hintText: 'School name',
              hintStyle: TextStyle(color: Color(0xFF444444)),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 16),

          // Type
          const Text('School Type', style: TextStyle(color: Color(0xFF888888), fontSize: 14)),
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
                    color: isSelected ? const Color(0xFF00D4FF) : const Color(0xFF1F1F1F),
                    borderRadius: BorderRadius.circular(20),
                    border: isSelected ? null : Border.all(color: const Color(0xFF222222)),
                  ),
                  child: Text(
                    type,
                    style: TextStyle(
                      color: isSelected ? const Color(0xFF0A0A0A) : Colors.white,
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
              hintText: 'About this school...',
              hintStyle: TextStyle(color: Color(0xFF444444)),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 24),

          // Location
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1F1F1F),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on, color: Color(0xFF888888), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _locationController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'City, Country',
                      hintStyle: TextStyle(color: Color(0xFF666666)),
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
              color: const Color(0xFF1F1F1F),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.language, color: Color(0xFF888888), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _websiteController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'School website (optional)',
                      hintStyle: TextStyle(color: Color(0xFF666666)),
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
              color: const Color(0xFF1F1F1F),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'School Features',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
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