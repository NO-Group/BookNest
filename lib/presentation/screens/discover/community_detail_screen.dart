import 'package:flutter/material.dart';

import 'group_base_screen.dart';

/// The full community experience: profile, membership, announcements,
/// named directory with deputy management, and the members-only chat.
class CommunityDetailScreen extends StatelessWidget {
  final String id;

  const CommunityDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    return GroupBaseScreen(
      kind: 'communities',
      groupId: id,
      title: 'Community',
    );
  }
}
