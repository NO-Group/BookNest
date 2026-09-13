import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../services/backend_api.dart';
import '../../services/supabase_service.dart';

/// Owner-only maintenance banner. When the deployed edge function is
/// older than the app (or unreachable), the owner sees exactly what to
/// do about it — everyone else sees nothing at all. Disappears the
/// moment the server is current, so "it still says old" always means
/// the paste didn't take.
class ServerStatusBanner extends StatelessWidget {
  const ServerStatusBanner({super.key});

  static const String _ownerEmail = 'n.ogroup@yahoo.com';

  @override
  Widget build(BuildContext context) {
    final email = SupabaseService().auth.currentUser?.email;
    if ((email ?? '').toLowerCase() != _ownerEmail) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<({bool reachable, bool upToDate})>(
      future: BackendApi.instance.serverStatus(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final s = snap.data!;
        if (s.reachable && s.upToDate) return const SizedBox.shrink();
        final outdated = s.reachable && !s.upToDate;
        final color =
            outdated ? const Color(0xFFD06A6A) : BookNestColors.cyan;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: color.withOpacity(.12),
            border: Border.all(color: color.withOpacity(.55)),
          ),
          child: Row(
            children: [
              Icon(
                outdated
                    ? Icons.system_update_alt_rounded
                    : Icons.cloud_off_rounded,
                size: 20,
                color: color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  outdated
                      ? 'Server update needed — copy '
                          'supabase/functions/booknest-api/index.ts from '
                          'GitHub into Supabase → Edge Functions → '
                          'booknest-api, then Deploy. Reports, deletes, '
                          'reactions, books and this console need it.'
                      : 'BookNest server unreachable — check your '
                          'connection and try again.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(.9),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
