import 'package:flutter/material.dart';

/// Placeholder detail view for a community.
///
/// The full community experience (feed, members, linked clubs) is built out
/// later; for now this renders the identifier so navigation from Discover
/// always resolves to a real route.
class CommunityDetailScreen extends StatelessWidget {
  final String id;

  const CommunityDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Community',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
      ),
      body: Center(
        child: Text(
          'Community $id',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
      ),
    );
  }
}
