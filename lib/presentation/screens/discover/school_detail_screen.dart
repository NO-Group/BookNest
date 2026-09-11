import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../components/booknest_ui.dart';
import 'group_base_screen.dart';
import 'school_lms.dart';

/// The full school experience: everything a group gets (profile,
/// membership, announcements, directory, chat) plus the two things only a
/// school needs — a curated reading list and a live top-readers
/// leaderboard (distinct books opened in the last 30 days, computed on the
/// server from real reading activity).
class SchoolDetailScreen extends StatelessWidget {
  final String id;

  const SchoolDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    return GroupBaseScreen(
      kind: 'schools',
      groupId: id,
      title: 'School',
      extraSections: (state) => [
        SchoolClassesSection(state: state),
        const SizedBox(height: 16),
        SchoolAssignmentsSection(state: state),
        const SizedBox(height: 16),
        SchoolExamsSection(state: state),
        const SizedBox(height: 16),
        GroupReadingListSection(state: state),
        const SizedBox(height: 16),
        GroupLeaderboardSection(state: state),
      ],
    );
  }
}
