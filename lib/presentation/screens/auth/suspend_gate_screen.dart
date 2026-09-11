import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/theme.dart';
import '../../../services/supabase_service.dart';
import '../../components/booknest_ui.dart';

/// What a suspended or banned reader sees instead of BookNest: the
/// honest truth about why, and exactly one way back — writing to the
/// overall moderator. Reading elsewhere may work; being here does not.
class SuspendGateScreen extends StatelessWidget {
  const SuspendGateScreen({
    super.key,
    required this.mode,
    required this.reason,
    this.until,
  });

  final String mode;
  final String reason;
  final DateTime? until;

  static const String appealEmail = 'n.ogroup@yahoo.com';

  Future<void> _appeal() async {
    final subject =
        Uri.encodeComponent('BookNest appeal — $mode');
    final body = Uri.encodeComponent(
        'Hello,\n\nI am appealing my $mode on BookNest.\n\n'
        'My account email: \nReason I believe this should be lifted: \n\n'
        'Thank you.');
    final uri = Uri.parse('mailto:$appealEmail?subject=$subject&body=$body');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // No mail app on the device — the address is on screen anyway.
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = dark ? Colors.white : BookNestColors.navyDeep;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: dark
            ? BookNestColors.darkChatBackground
            : BookNestColors.lightSurface,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 86,
                  height: 86,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD06A6A).withOpacity(.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                      mode == 'ban'
                          ? Icons.block_rounded
                          : Icons.timer_outlined,
                      size: 42,
                      color: const Color(0xFFD06A6A)),
                ),
                const SizedBox(height: 22),
                Text(
                  mode == 'ban'
                      ? 'Account banned'
                      : 'Account suspended',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                      color: onSurface),
                ),
                const SizedBox(height: 10),
                Text(
                  mode == 'ban'
                      ? 'This account can no longer use BookNest.'
                      : until == null
                          ? 'This account is suspended for now.'
                          : 'This account is suspended until '
                              '${until!.year}-${until!.month.toString().padLeft(2, '0')}-${until!.day.toString().padLeft(2, '0')}.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14.5,
                      height: 1.45,
                      color: onSurface.withOpacity(.75)),
                ),
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  GlassPanel(
                    radius: 18,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Reason',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1,
                                    color: onSurface.withOpacity(.5))),
                            const SizedBox(height: 5),
                            Text(reason,
                                style: TextStyle(
                                    fontSize: 13.5,
                                    height: 1.4,
                                    color: onSurface)),
                          ]),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                Text(
                  'You can appeal by writing to',
                  style: TextStyle(
                      fontSize: 13, color: onSurface.withOpacity(.6)),
                ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: _appeal,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: BookNestColors.cyan.withOpacity(.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: BookNestColors.cyan.withOpacity(.5)),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.mail_outline_rounded,
                          size: 17, color: BookNestColors.cyan),
                      SizedBox(width: 8),
                      Text(appealEmail,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: BookNestColors.cyan)),
                    ]),
                  ),
                ),
                const SizedBox(height: 26),
                TextButton(
                  onPressed: () {
                    SupabaseService().auth.signOut();
                    context.go('/login');
                  },
                  child: const Text('Sign out of this device',
                      style: TextStyle(color: BookNestColors.cyan)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
