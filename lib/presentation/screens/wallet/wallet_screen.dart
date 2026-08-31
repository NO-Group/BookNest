// lib/presentation/screens/wallet/wallet_screen.dart
//
// Gems wallet — balance, daily bonus, and the full activity ledger.
// Balance lives in Supabase (profiles.gems); the movement ledger lives in
// MongoDB (booknest_users.gem_ledger) via the wallet.* edge actions.

import 'package:flutter/material.dart';
import 'dart:ui';

import 'package:intl/intl.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../components/booknest_ui.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  bool _loading = true;
  bool _offline = false;
  bool _claiming = false;
  int _gems = 0;
  bool _claimedToday = false;
  List<Map<String, dynamic>> _ledger = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _offline = false;
    });
    final res = await BackendApi.instance.call('wallet.summary');
    if (!mounted) return;
    if (res == null) {
      setState(() {
        _offline = true;
        _loading = false;
      });
      return;
    }
    setState(() {
      _gems = (res['gems'] as num?)?.toInt() ?? 0;
      _ledger = ((res['ledger'] as List?) ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _loading = false;
    });
  }

  Future<void> _claimDaily() async {
    setState(() => _claiming = true);
    final res = await BackendApi.instance.call('wallet.claim');
    if (!mounted) return;
    setState(() => _claiming = false);
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not reach the wallet — try again shortly.')));
      return;
    }
    final granted = res['granted'] == true;
    setState(() {
      _gems = (res['gems'] as num?)?.toInt() ?? _gems;
      if (granted) _claimedToday = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(granted
            ? 'Daily bonus claimed — +5 gems 💎'
            : 'Already claimed today — see you tomorrow!')));
    if (granted) _load();
  }

  String _reasonLabel(String reason) {
    switch (reason) {
      case 'daily':
        return 'Daily reader bonus';
      case 'book_publish':
        return 'Published a book';
      case 'post':
        return 'Shared a post';
      default:
        return reason;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Gems Wallet',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: BookNestColors.cyan))
          : _offline
              ? EmptyState(
                  icon: Icons.wifi_off_rounded,
                  title: 'Wallet is offline',
                  subtitle: 'The BookNest backend is not reachable yet — '
                      'deploy the edge function and retry.',
                  action: TextButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded,
                        size: 18, color: BookNestColors.cyan),
                    label: const Text('Retry',
                        style: TextStyle(color: BookNestColors.cyan)),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                  children: [
                    // ── glass balance card ──
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: (dark
                                    ? BookNestColors.darkChatBackground
                                    : Colors.white)
                                .withOpacity(.62),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                                color:
                                    BookNestColors.cyan.withOpacity(.28)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: const LinearGradient(
                                          colors: [
                                            BookNestColors.cyanSoft,
                                            BookNestColors.cyan
                                          ]),
                                      boxShadow: [
                                        BoxShadow(
                                            color: BookNestColors.cyan
                                                .withOpacity(.35),
                                            blurRadius: 16),
                                      ],
                                    ),
                                    child: const Icon(Icons.diamond_outlined,
                                        color: BookNestColors.navyDeep),
                                  ),
                                  const SizedBox(width: 14),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('BookNest Gems',
                                          style: TextStyle(
                                              color: theme.hintColor,
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w700)),
                                      AnimatedCount(
                                        value: _gems,
                                        style: const TextStyle(
                                            fontSize: 30,
                                            fontWeight: FontWeight.w800),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              _claimedToday
                                  ? Row(
                                      children: [
                                        const Icon(Icons.check_circle_rounded,
                                            size: 18,
                                            color: BookNestColors.cyan),
                                        const SizedBox(width: 8),
                                        Text('Claimed today — back tomorrow!',
                                            style: TextStyle(
                                                color: theme.hintColor,
                                                fontSize: 13)),
                                      ],
                                    )
                                  : GradientButton(
                                      label: 'Claim daily bonus · +5 gems',
                                      icon: Icons.card_giftcard_rounded,
                                      busy: _claiming,
                                      onPressed: _claimDaily,
                                    ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const SectionHeader(title: 'Recent activity'),
                    const SizedBox(height: 10),
                    if (_ledger.isEmpty)
                      const EmptyState(
                        icon: Icons.savings_rounded,
                        title: 'No activity yet',
                        subtitle: 'Claim your first daily bonus and your '
                            'movements will show up here.',
                      )
                    else
                      ..._ledger.map((entry) {
                        final delta = (entry['delta'] as num?)?.toInt() ?? 0;
                        final when = DateTime.tryParse(
                                entry['createdAt']?.toString() ?? '')
                            ?.toLocal();
                        return Entrance(
                          index: _ledger.indexOf(entry),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface
                                    .withOpacity(.7),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: theme.dividerColor
                                        .withOpacity(.6)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: BookNestColors.cyan
                                          .withOpacity(.12),
                                    ),
                                    child: Icon(
                                        delta >= 0
                                            ? Icons.add_rounded
                                            : Icons.remove_rounded,
                                        size: 18,
                                        color: BookNestColors.cyan),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            _reasonLabel(entry['reason']
                                                    ?.toString() ??
                                                'reward'),
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13.5)),
                                        if (when != null)
                                          Text(DateFormat('MMM d · HH:mm')
                                              .format(when)
                                              .toString(),
                                              style: TextStyle(
                                                  color: theme.hintColor,
                                                  fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    delta >= 0
                                        ? '+$delta 💎'
                                        : '$delta 💎',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: BookNestColors.cyan),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
    );
  }
}
