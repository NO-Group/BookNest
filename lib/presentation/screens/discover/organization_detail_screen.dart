import 'package:flutter/material.dart';

import 'group_base_screen.dart';

/// The full organization experience: profile, membership, announcements,
/// named directory with deputy management, and the members-only chat.
class OrganizationDetailScreen extends StatelessWidget {
  final String id;

  const OrganizationDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    return GroupBaseScreen(
      kind: 'organizations',
      groupId: id,
      title: 'Organization',
    );
  }
}
