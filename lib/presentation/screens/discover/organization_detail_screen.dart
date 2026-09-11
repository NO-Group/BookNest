import 'package:flutter/material.dart';

import 'group_base_screen.dart';
import 'group_extras.dart';
import 'school_lms.dart';

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
      extraSections: (state) => [
        const SizedBox(height: 16),
        GroupEventsSection(state: state.ctx),
        const SizedBox(height: 16),
        GroupReadingListSection(state: state),
        const SizedBox(height: 16),
        GroupLeaderboardSection(state: state),
      ],
    );
  }
}
