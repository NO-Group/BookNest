import 'package:flutter/material.dart';

/// Placeholder detail view for an organization.
///
/// The full organization experience (announcements, roles, resources) is
/// built out later; for now this renders the identifier so navigation from
/// Discover always resolves to a real route.
class OrganizationDetailScreen extends StatelessWidget {
  final String id;

  const OrganizationDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: const Text(
          'Organization',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Center(
        child: Text(
          'Organization $id',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
