import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../../services/supabase_service.dart';
import '../../components/booknest_ui.dart';

enum _Health { checking, ok, down }

class _LayerResult {
  final _Health health;
  final String hint;
  _LayerResult(this.health, this.hint);
}

/// Connection status — live check of the three layers every feature sits
/// on: account sign-in, feed & library storage, and the smart services
/// (wallet, Jenny, likes, trending). Helps pinpoint exactly what is and
/// isn't reachable without any guesswork.
class ConnectionStatusScreen extends StatefulWidget {
  const ConnectionStatusScreen({super.key});

  @override
  State<ConnectionStatusScreen> createState() =>
      _ConnectionStatusScreenState();
}

class _ConnectionStatusScreenState extends State<ConnectionStatusScreen> {
  _LayerResult _account = _LayerResult(_Health.checking, 'Checking…');
  _LayerResult _storage = _LayerResult(_Health.checking, 'Checking…');
  _LayerResult _services = _LayerResult(_Health.checking, 'Checking…');
  DateTime? _checkedAt;

  @override
  void initState() {
    super.initState();
    _runChecks();
  }

  Future<void> _runChecks() async {
    setState(() {
      _account = _LayerResult(_Health.checking, 'Checking…');
      _storage = _LayerResult(_Health.checking, 'Checking…');
      _services = _LayerResult(_Health.checking, 'Checking…');
    });

    // 1 · Account
    final user = SupabaseService().client.auth.currentUser;
    setState(() {
      _account = user == null
          ? const _LayerResult(_Health.down,
              'You are not signed in. Sign in again and recheck.')
          : _LayerResult(_Health.ok, 'Signed in${user.email != null ? ' as ${user.email}' : ''}.');
    });

    // 2 · Feed & library storage
    try {
      await SupabaseService()
          .client
          .from('posts')
          .select('id')
          .limit(1);
      setState(() => _storage =
          const _LayerResult(_Health.ok, 'Reachable and responding.'));
    } catch (_) {
      setState(() => _storage = const _LayerResult(_Health.down,
          'Can’t be reached right now. Check your connection, then recheck.'));
    }

    // 3 · Smart services (wallet, Jenny, likes, trending)
    try {
      final res = await SupabaseService()
          .client
          .functions
          .invoke('booknest-api', body: {'action': 'ping'});
      final data = res.data;
      if (data is Map && data['ok'] == true) {
        setState(() => _services = const _LayerResult(_Health.ok,
            'Responding — wallet, Jenny, likes and trends are live.'));
      } else {
        setState(() => _services = const _LayerResult(_Health.down,
            'Responded with an unexpected answer. Try again shortly.'));
      }
    } catch (_) {
      setState(() => _services = const _LayerResult(_Health.down,
          'Waking up or unavailable. If this persists, the services need '
          'their data connection configured — check back soon.'));
    }

    setState(() => _checkedAt = DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allOk = _account.health == _Health.ok &&
        _storage.health == _Health.ok &&
        _services.health == _Health.ok;

    return Scaffold(
      appBar: const GlassAppBar(title: 'Connection status'),
      body: RefreshIndicator(
        color: BookNestColors.cyan,
        onRefresh: _runChecks,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            GlassPanel(
              child: Row(
                children: [
                  Icon(
                    allOk
                        ? Icons.verified_rounded
                        : Icons.info_outline_rounded,
                    color: allOk ? BookNestColors.cyan : theme.hintColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      allOk
                          ? 'Everything is working.'
                          : 'Some parts are resting. Pull down to check again.',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _layerCard(
              theme,
              icon: Icons.person_rounded,
              title: 'Account sign-in',
              result: _account,
            ),
            _layerCard(
              theme,
              icon: Icons.auto_stories_rounded,
              title: 'Feed & library storage',
              result: _storage,
            ),
            _layerCard(
              theme,
              icon: Icons.auto_awesome_rounded,
              title: 'Smart services',
              subtitle: 'Wallet · Jenny · likes · trending words',
              result: _services,
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: _runChecks,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                    _checkedAt == null ? 'Check again' : 'Checked again just now — tap to refresh'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _layerCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    String? subtitle,
    required _LayerResult result,
  }) {
    final (color, label) = switch (result.health) {
      _Health.checking => (theme.hintColor, 'Checking…'),
      _Health.ok => (BookNestColors.cyan, 'Working'),
      _Health.down => (theme.colorScheme.error, 'Not responding'),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassPanel(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: theme.hintColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            color: theme.hintColor, fontSize: 12)),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    result.hint,
                    style: TextStyle(
                        color: theme.hintColor,
                        fontSize: 12.5,
                        height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
