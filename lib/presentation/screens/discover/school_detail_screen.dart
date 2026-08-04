import 'package:flutter/material.dart';

/// Placeholder detail view for a school.
///
/// The full school experience (classes, directories, exam countdowns) is
/// built out later; for now this renders the identifier so navigation from
/// Discover always resolves to a real route.
class SchoolDetailScreen extends StatelessWidget {
  final String id;

  const SchoolDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: const Text(
          'School',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Center(
        child: Text(
          'School $id',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
