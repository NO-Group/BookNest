import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// The BookNest Store — gem packs and the Reader / BookWorm plans.
/// The app never decides a price: it sends a product id, the server
/// answers with the checkout and the books/gems land only after Paystack
/// verifies the payment. All amounts are integer minor units and are
/// only ever FORMATTED here, never calculated.
/// ─────────────────────────────────────────────────────────────────────────────

class _Pack {
  final String productId;
  final int gems;
  const _Pack({required this.productId, required this.gems});
}

class _PlanPeriod {
  final String productId;
  final String label;
  final int periodDays;
  final int unlimited;
  const _PlanPeriod({
    required this.productId,
    required this.label,
    required this.periodDays,
    required this.unlimited,
  });
}

class _Plan {
  final String name;
  final String plan;
  final String themeLine;
  final IconData star;
  final Color starColor;
  final List<String> benefits;
  final List<_PlanPeriod> periods;
  const _Plan({
    required this.name,
    required this.plan,
    required this.themeLine,
    required this.star,
    required this.starColor,
    required this.benefits,
    required this.periods,
  });
}

class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  bool _loading = true;
  bool _paying = false;
  String _currency = 'NGN';
  List<Map<String, dynamic>> _products = [];
  Map<String, dynamic>? _sub;
  int _selectedPeriod = 0; // index into the period list

  static const _packs = [
    _Pack(productId: 'gems_100', gems: 100),
    _Pack(productId: 'gems_500', gems: 500),
    _Pack(productId: 'gems_1000', gems: 1000),
    _Pack(productId: 'gems_5000', gems: 5000),
    _Pack(productId: 'gems_10000', gems: 10000),
  ];

  static const _plans = [
    _Plan(
      name: 'Reader',
      plan: 'reader',
      themeLine: 'Cyan & yellow star',
      star: Icons.star_rounded,
      starColor: BookNestColors.cyan,
      benefits: [
        'Premium features',
        '20% off every book unlock',
        '5 unlimited-access books, picked for you',
      ],
      periods: [
        _PlanPeriod(
            productId: 'reader_monthly',
            label: 'Monthly',
            periodDays: 30,
            unlimited: 5),
        _PlanPeriod(
            productId: 'reader_six_month',
            label: '6 months',
            periodDays: 182,
            unlimited: 5),
        _PlanPeriod(
            productId: 'reader_yearly',
            label: 'Yearly',
            periodDays: 365,
            unlimited: 5),
      ],
    ),
    _Plan(
      name: 'BookWorm',
      plan: 'bookworm',
      themeLine: 'Yellow & orange star',
      star: Icons.star_rounded,
      starColor: Color(0xFFFFC94D),
      benefits: [
        'Everything in Reader',
        '10 unlimited-access books, picked for you',
        'Monthly gem allowance from your verified reading time',
      ],
      periods: [
        _PlanPeriod(
            productId: 'bookworm_monthly',
            label: 'Monthly',
            periodDays: 30,
            unlimited: 10),
        _PlanPeriod(
            productId: 'bookworm_six_month',
            label: '6 months',
            periodDays: 182,
            unlimited: 10),
        _PlanPeriod(
            productId: 'bookworm_yearly',
            label: 'Yearly',
            periodDays: 365,
            unlimited: 10),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<dynamic>([
      BackendApi.instance.call('wallet.catalog'),
      BackendApi.instance.call('sub.status'),
    ]);
    if (!mounted) return;
    setState(() {
      _products = ((results[0]?['products'] as List?) ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _sub = results[1] == null
          ? null
          : Map<String, dynamic>.from(results[1] as Map);
      _loading = false;
    });
  }

  Map<String, dynamic>? _product(String productId) {
    for (final row in _products) {
      if (row['productId']?.toString() == productId) return row;
    }
    return null;
  }

  /// Minor units → display string. Formatting only; never math.
  String _price(Map<String, dynamic>? product) {
    final prices = (product?['prices'] as Map?) ?? const {};
    final minor = (prices[_currency] as num?)?.toInt() ?? 0;
    if (minor <= 0) return '—';
    if (_currency == 'USD') {
      return '\$${(minor ~/ 100)}.${(minor % 100).toString().padLeft(2, '0')}';
    }
    final naira = minor ~/ 100;
    final kobo = (minor % 100).toString().padLeft(2, '0');
    final whole = naira.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
    return '₦$whole.$kobo';
  }

  Future<void> _buy(String productId) async {
    if (_paying) return;
    setState(() => _paying = true);
    try {
      final res = await BackendApi.instance
          .call('payments.initialize', {'productId': productId, 'currency': _currency});
      if (!mounted) return;
      final url = res?['checkoutUrl']?.toString() ?? '';
      final reference = res?['reference']?.toString() ?? '';
      if (url.isEmpty || reference.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(res == null
                ? 'The store could not be reached — try again in a moment.'
                : 'Payments are not ready yet — please try again shortly.')));
        return;
      }
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      // Back from the checkout — Paystack may need a beat to settle.
      var paid = false;
      for (var attempt = 0; attempt < 3 && !paid; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        final check = await BackendApi.instance
            .call('payments.verify', {'reference': reference});
        paid = check?['fulfilled'] == true;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(paid
              ? 'Payment confirmed — enjoy!'
              : 'Payment still settling — your gems or plan will appear '
                  'within a minute or two.')));
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('The checkout could not be opened — try again.')));
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _claimAllowance() async {
    final res = await BackendApi.instance.call('reading.allowance');
    if (!mounted) return;
    final granted = (res?['granted'] as num?)?.toInt() ?? 0;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(granted > 0
            ? '+$granted gems from your reading this month!'
            : 'Nothing to claim yet — keep reading, the gems stack up.')));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final allowance = ((_sub?['allowance'] as Map?) ?? const {});
    final pendingGems = (allowance['pendingGems'] as num?)?.toInt() ?? 0;
    final monthMinutes = (allowance['monthMinutes'] as num?)?.toInt() ?? 0;
    final active = _sub?['active'] == true;
    final plan = _sub?['plan']?.toString() ?? '';
    return Scaffold(
      backgroundColor: dark
          ? BookNestColors.darkChatBackground
          : BookNestColors.lightSurface,
      appBar: AppBar(
        title: const Text('BookNest Store',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          // Currency is a display choice — the catalog holds both prices.
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                segments: const [
                  ButtonSegment(value: 'NGN', label: Text('₦')),
                  ButtonSegment(value: 'USD', label: Text('\$')),
                ],
                selected: {_currency},
                onSelectionChanged: (next) =>
                    setState(() => _currency = next.first),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: BookNestColors.cyan))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
              children: [
                // ── Current status ──
                if (active) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: BookNestColors.cyan.withOpacity(.10),
                      border:
                          Border.all(color: BookNestColors.cyan.withOpacity(.35)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_rounded,
                            color: BookNestColors.cyan, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            plan == 'bookworm'
                                ? 'BookWorm is active — thank you!'
                                : 'Reader is active — thank you!',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 13.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (plan == 'bookworm') ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: dark
                          ? Colors.white.withOpacity(.05)
                          : BookNestColors.navyDeep.withOpacity(.04),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('This month\'s reading',
                            style: TextStyle(
                                color: theme.hintColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          '$monthMinutes verified minutes · '
                          '${(allowance['allowanceGems'] as num?)?.toInt() ?? 0} gems earned · '
                          '$pendingGems ready',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 13.5),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed:
                                pendingGems > 0 ? _claimAllowance : null,
                            icon: const Icon(Icons.redeem_rounded,
                                size: 17, color: BookNestColors.cyan),
                            label: Text(
                                pendingGems > 0
                                    ? 'Claim $pendingGems gems'
                                    : 'Keep reading to earn',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                // ── Gem packs ──
                const Text('Top up gems',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                Text('1 Gem reads 100 words.',
                    style:
                        TextStyle(color: theme.hintColor, fontSize: 12.5)),
                const SizedBox(height: 10),
                for (final pack in _packs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buyCard(
                      dark: dark,
                      leading: const Icon(Icons.diamond_rounded,
                          color: BookNestColors.cyan, size: 26),
                      title: '${pack.gems} gems',
                      subtitle:
                          '${pack.gems * 100} words of reading',
                      trailing: _price(_product(pack.productId)),
                      onPressed: () => _buy(pack.productId),
                      busy: _paying,
                    ),
                  ),
                const SizedBox(height: 18),
                // ── Plans ──
                const Text('Go premium',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 10),
                for (final planDef in _plans) ...[
                  _planCard(context, planDef, dark: dark),
                  const SizedBox(height: 14),
                ],
                const SizedBox(height: 6),
                Text(
                  'Payments are handled by Paystack — card or bank transfer. '
                  'Gems and plans unlock only after the payment is verified.',
                  style: TextStyle(color: theme.hintColor, fontSize: 11.5),
                ),
              ],
            ),
    );
  }

  Widget _planCard(BuildContext context, _Plan plan, {required bool dark}) {
    final theme = Theme.of(context);
    final period = plan.periods[_selectedPeriod.clamp(0, plan.periods.length - 1)];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(plan.star, color: plan.starColor, size: 20),
              const SizedBox(width: 8),
              Text(plan.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15.5)),
              const SizedBox(width: 8),
              Text(plan.themeLine,
                  style: TextStyle(
                      color: theme.hintColor, fontSize: 11.5)),
            ],
          ),
          const SizedBox(height: 8),
          for (final benefit in plan.benefits)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  const Icon(Icons.check_rounded,
                      size: 15, color: BookNestColors.cyan),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(benefit,
                        style: const TextStyle(fontSize: 12.5, height: 1.3)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              for (var i = 0; i < plan.periods.length; i++)
                ButtonSegment(value: i, label: Text(plan.periods[i].label)),
            ],
            selected: {_selectedPeriod},
            onSelectionChanged: (next) =>
                setState(() => _selectedPeriod = next.first),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: BookNestColors.cyan,
                foregroundColor: BookNestColors.navyDeep,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
              ),
              onPressed: _paying ? null : () => _buy(period.productId),
              child: Text(
                'Subscribe · ${_price(_product(period.productId))} '
                '· ${_periodLabel(period.periodDays)}',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _periodLabel(int days) {
    if (days >= 360) return '12 months of access';
    if (days >= 180) return '6 months of access';
    return '1 month of access';
  }

  Widget _buyCard({
    required bool dark,
    required Widget leading,
    required String title,
    required String subtitle,
    required String trailing,
    required VoidCallback onPressed,
    required bool busy,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: busy ? null : onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14)),
                    Text(subtitle,
                        style: TextStyle(
                            color: theme.hintColor, fontSize: 11.5)),
                  ],
                ),
              ),
              Text(trailing,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: BookNestColors.cyan)),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
