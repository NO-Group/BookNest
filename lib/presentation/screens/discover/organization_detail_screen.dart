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
      appBar: AppBar(
        title: Text(
          'Organization',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
      ),
      body: Center(
        child: Text(
          'Organization $id',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
      ),
    );
  }
}
