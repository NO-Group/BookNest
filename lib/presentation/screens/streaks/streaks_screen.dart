// lib/presentation/screens/streaks/streaks_screen.dart
//
// Reading streaks — glass hero card with the current streak, a
// last-7-days dot calendar, and one-tap daily logging. Logging the first
// time each day grants +2 gems (edge action updates profiles.gems and
// writes the wallet ledger). Data: streak.get / streak.log edge actions;
// logs live in booknest_social.reading_logs.

import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../components/booknest_ui.dart';

class StreaksScreen extends StatefulWidget {
  const StreaksScreen({super.key});

  @override
  State<StreaksScreen> createState() => _StreaksScreenState();
}

class _StreaksScreenState extends State<StreaksScreen> {
  bool _loading = true;
  bool _offline = false;
  bool _logging = false;
  int _current = 0;
  int _longest = 0;
  int _total = 0;
  bool _todayLogged = false;
  List<bool> _last7 = const [false, false, false, false, false, false, false];

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
    final res = await BackendApi.instance.call('streak.get');
    if (!mounted) return;
    if (res == null) {
      setState(() {
        _offline = true;
        _loading = false;
      });
      return;
    }
    _apply(res);
  }

  void _apply(Map<String, dynamic> res) {
    setState(() {
      _current = (res['current'] as num?)?.toInt() ?? 0;
      _longest = (res['longest'] as num?)?.toInt() ?? 0;
      _total = (res['total'] as num?)?.toInt() ?? 0;
      _todayLogged = res['todayLogged'] == true;
      _last7 = ((res['last7'] as List?) ?? const [])
          .map((v) => v == true)
          .toList();
      _loading = false;
    });
  }

  Future<void> _logToday() async {
    if (_logging) return;
    final minutes = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text("Log today's reading"),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: 'Minutes read (optional)',
                hintText: 'e.g. 30'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () {
                  final value = int.tryParse(controller.text.trim());
                  Navigator.pop(dialogContext, value ?? 0);
                },
                child: const Text('Log it')),
          ],
        );
      },
    );
    if (minutes == null || !mounted) return; // cancelled

    setState(() => _logging = true);
    final res = await BackendApi.instance
        .call('streak.log', {'minutes': minutes});
    if (!mounted) return;
    setState(() => _logging = false);
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not reach the streak service — try again.')));
      return;
    }
    _apply(res);
    final awarded = (res['gemsAwarded'] as num?)?.toInt() ?? 0;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(awarded > 0
            ? 'Day $_current logged — +$awarded gems 💎'
            : 'Already logged today — streak safe 🔥')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dayLabels = const ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Scaffold(
      appBar: const GlassAppBar(title: 'Reading streaks'),
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(color: BookNestColors.cyan))
          : _offline
              ? EmptyState(
                  icon: Icons.wifi_off_rounded,
                  title: 'Streaks are offline',
                  subtitle: 'You seem offline — check your connection and try '
                      'again.',
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
                    GlassPanel(
                      radius: 24,
                      blur: 22,
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          children: [
                            Container(
                              width: 74,
                              height: 74,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(colors: [
                                  BookNestColors.cyan.withOpacity(.25),
                                  BookNestColors.cyanSoft.withOpacity(.15),
                                ]),
                                border: Border.all(
                                    color: BookNestColors.cyan
                                        .withOpacity(.55)),
                                boxShadow: [
                                  BoxShadow(
                                      color: BookNestColors.cyan
                                          .withOpacity(.3),
                                      blurRadius: 22),
                                ],
                              ),
                              child: const Icon(Icons.local_fire_department_rounded,
                                  size: 40, color: BookNestColors.cyan),
                            ),
                            const SizedBox(height: 14),
                            AnimatedCount(
                              value: _current,
                              style: const TextStyle(
                                  fontSize: 44,
                                  fontWeight: FontWeight.w800),
                            ),
                            Text(
                                _current == 1
                                    ? 'day streak'
                                    : 'day streak — keep it burning',
                                style: TextStyle(
                                    color: theme.hintColor, fontSize: 13.5)),
                            const SizedBox(height: 20),
                            // last-7-days dots
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                for (var i = 0; i < 7; i++)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7),
                                    child: Column(
                                      children: [
                                        AnimatedContainer(
                                          duration: const Duration(
                                              milliseconds: 260),
                                          width: 26,
                                          height: 26,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: i < _last7.length &&
                                                    _last7[i]
                                                ? BookNestColors.cyan
                                                : theme
                                                    .colorScheme.surface,
                                            border: Border.all(
                                                color: i < _last7.length &&
                                                        _last7[i]
                                                    ? BookNestColors.cyan
                                                    : theme.dividerColor),
                                          ),
                                          child: i < _last7.length &&
                                                  _last7[i]
                                              ? const Icon(Icons.check_rounded,
                                                  size: 15,
                                                  color: BookNestColors
                                                      .navyDeep)
                                              : null,
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                            dayLabels[DateTime.now()
                                                .subtract(Duration(
                                                    days: 6 - i))
                                                .weekday %
                                                7],
                                            style: TextStyle(
                                                color: theme.hintColor,
                                                fontSize: 10.5)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_todayLogged)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_rounded,
                              size: 18, color: BookNestColors.cyan),
                          const SizedBox(width: 8),
                          Text('Logged today — see you tomorrow!',
                              style: TextStyle(
                                  color: theme.hintColor, fontSize: 13)),
                        ],
                      )
                    else
                      GradientButton(
                        label: "Log today's reading · +2 gems",
                        icon: Icons.menu_book_rounded,
                        busy: _logging,
                        onPressed: _logToday,
                      ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: GlassPanel(
                            radius: 18,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 16),
                              child: Column(
                                children: [
                                  const Icon(Icons.emoji_events_rounded,
                                      color: BookNestColors.cyan),
                                  const SizedBox(height: 6),
                                  AnimatedCount(
                                      value: _longest,
                                      style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800)),
                                  Text('longest',
                                      style: TextStyle(
                                          color: theme.hintColor,
                                          fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GlassPanel(
                            radius: 18,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 16),
                              child: Column(
                                children: [
                                  const Icon(Icons.calendar_month_rounded,
                                      color: BookNestColors.cyan),
                                  const SizedBox(height: 6),
                                  AnimatedCount(
                                      value: _total,
                                      style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800)),
                                  Text('days total',
                                      style: TextStyle(
                                          color: theme.hintColor,
                                          fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Log any day you read — even a page counts. Every new '
                      'streak day drops +2 gems into your wallet.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: theme.hintColor, fontSize: 12.5),
                    ),
                  ],
                ),
    );
  }
}
