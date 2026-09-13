import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_config.dart';
import '../../config/theme.dart';
import '../../services/backend_api.dart';
import '../../services/supabase_service.dart';

/// Owner-only maintenance banner + deploy kit. When the deployed edge
/// function is older than the app, the owner gets three taps:
///   1. **Copy server code** — the entire updated `index.ts` is on the
///      clipboard (it ships inside the app; it contains no secrets).
///   2. **Open Supabase** — deep link to the exact function page.
///   3. Paste (select-all → paste → Deploy), then **Re-test** — the
///      banner vanishes the moment the server answers with the current
///      version. Everyone who isn't the owner sees nothing at all.
class ServerStatusBanner extends StatefulWidget {
  const ServerStatusBanner({super.key});

  @override
  State<ServerStatusBanner> createState() => _ServerStatusBannerState();
}

class _ServerStatusBannerState extends State<ServerStatusBanner> {
  static const String _ownerEmail = 'n.ogroup@yahoo.com';
  static const String _sourceAsset =
      'supabase/functions/booknest-api/index.ts';

  late Future<({bool reachable, bool upToDate})> _status;
  String? _note;

  @override
  void initState() {
    super.initState();
    _status = BackendApi.instance.serverStatus();
  }

  void _retest() {
    setState(() {
      _note = null;
      _status = BackendApi.instance.serverStatus();
    });
  }

  Future<void> _copyServerCode() async {
    String message;
    try {
      final src = await rootBundle.loadString(_sourceAsset);
      await Clipboard.setData(ClipboardData(text: src));
      message = 'Server code copied (${(src.length / 1024).round()} KB) — '
          'now: Supabase → select all in the editor → paste → Deploy.';
    } catch (_) {
      message = 'Could not load the server code from this install — '
          'copy supabase/functions/booknest-api/index.ts from GitHub '
          'instead.';
    }
    if (mounted) setState(() => _note = message);
  }

  Future<void> _openSupabase() async {
    final uri = Uri.parse(AppConfig.dashboardFunctionUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (mounted) {
        setState(() => _note =
            'Supabase opened — booknest-api → Edit → select all → '
            'paste → press publish. Then come back and tap Re-test.');
      }
    } catch (_) {
      if (mounted) {
        final page = AppConfig.dashboardFunctionUrl;
        setState(() => _note =
            'If the page did not open, visit: $page — '
            'then paste and press publish.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = SupabaseService().auth.currentUser?.email;
    if ((email ?? '').toLowerCase() != _ownerEmail) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<({bool reachable, bool upToDate})>(
      future: _status,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                          ? 'Server update needed — the live edge '
                              'predates this app. Reports, deletes, '
                              'reactions, books and this console need the '
                              'update — three taps:'
                          : 'BookNest server unreachable — check your '
                              'connection, then re-test.',
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
              if (outdated) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _action('Copy server code', Icons.copy_rounded,
                        _copyServerCode),
                    _action('Open Supabase', Icons.open_in_new_rounded,
                        _openSupabase),
                    _action('Re-test', Icons.refresh_rounded, _retest),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 8),
                _action('Re-test', Icons.refresh_rounded, _retest),
              ],
              if (_note != null) ...[
                const SizedBox(height: 8),
                Text(
                  _note!,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(.75),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _action(String label, IconData icon, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 15, color: BookNestColors.cyan),
      label: Text(label,
          style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: BookNestColors.cyan)),
      onPressed: onTap,
    );
  }
}
