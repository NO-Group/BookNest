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
      appBar: AppBar(
        title: Text(
          'School',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
      ),
      body: Center(
        child: Text(
          'School $id',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
      ),
    );
  }
}
