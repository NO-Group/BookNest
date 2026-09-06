import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../components/booknest_ui.dart';
import '../../components/watermark_background.dart';
import '../../../services/backend_api.dart';

/// BookNest Wrapped — your whole reading life on one page: minutes in
/// books, streaks, gems, finished books, words explored, stories shared.
/// Every number is counted from what you actually did, straight from the
/// app's own data store.
class WrappedScreen extends StatefulWidget {
  const WrappedScreen({super.key});

  @override
  State<WrappedScreen> createState() => _WrappedScreenState();
}

class _WrappedScreenState extends State<WrappedScreen> {
  Map<String, dynamic>? _wrapped;
  bool _loading = true;
  bool _offline = false;

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
    final res = await BackendApi.instance.call('wrapped.get');
    if (!mounted) return;
    setState(() {
      _wrapped = res?['wrapped'] is Map
          ? Map<String, dynamic>.from(res!['wrapped'] as Map)
          : null;
      _offline = res == null;
      _loading = false;
    });
  }

  int _num(String key) => (_wrapped?[key] as num?)?.toInt() ?? 0;

  String get _timeRead {
    final minutes = _num('minutesRead');
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (hours <= 0) return '$rest min';
    return '${hours}h ${rest}m';
  }

  String get _daysLine {
    final days = _num('daysRead');
    if (days == 0) {
      return 'Your story starts today — read a chapter and watch this fill up.';
    }
    if (days == 1) return 'One day with a book in your hands — the first of many.';
    return '$days days with a book in your hands.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded), onPressed: context.pop),
        title: const Text('Your BookNest story',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Container(
        color: dark ? BookNestColors.darkChatBackground : BookNestColors.lightSurface,
        child: WatermarkBackground(
          opacity: dark ? 0.04 : 0.05,
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: BookNestColors.cyan))
              : _offline || _wrapped == null
                  ? EmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Your story is still in the cloud',
                      subtitle: 'BookNest could not count your story just '
                          'now. Please try again shortly.',
                      action: GradientButton(
                        label: 'Retry',
                        icon: Icons.refresh_rounded,
                        onPressed: _load,
                      ),
                    )
                  : RefreshIndicator(
                      color: BookNestColors.cyan,
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                        children: [
                          // ── Hero: time inside books ────────────────────
                          GlassPanel(
                            radius: 26,
                            blur: 22,
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                children: [
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(colors: [
                                        BookNestColors.cyan.withOpacity(.28),
                                        BookNestColors.cyanSoft.withOpacity(.16),
                                      ]),
                                      border: Border.all(
                                          color: BookNestColors.cyan
                                              .withOpacity(.5)),
                                    ),
                                    child: const Icon(
                                        Icons.auto_stories_rounded,
                                        color: BookNestColors.cyan,
                                        size: 30),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    _timeRead,
                                    style: theme.textTheme.displaySmall
                                        ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            color: BookNestColors.cyan),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'inside BookNest books',
                                    style: TextStyle(
                                        color: theme.hintColor, fontSize: 13),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _daysLine,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: theme.hintColor, height: 1.4),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // ── Stat grid ──────────────────────────────────
                          Row(
                            children: [
                              Expanded(
                                  child: _StatTile(
                                      icon: Icons.local_fire_department_rounded,
                                      value: '${_num('currentStreak')}',
                                      label: 'day streak',
                                      highlight: true)),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: _StatTile(
                                      icon: Icons.military_tech_rounded,
                                      value: '${_num('longestStreak')}',
                                      label: 'best streak')),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                  child: _StatTile(
                                      icon: Icons.diamond_rounded,
                                      value: '+${_num('gemsEarned')}',
                                      label: 'gems earned',
                                      highlight: true)),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: _StatTile(
                                      icon: Icons.done_all_rounded,
                                      value: '${_num('booksFinished')}',
                                      label: 'books finished')),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                  child: _StatTile(
                                      icon: Icons.travel_explore_rounded,
                                      value: '${_num('wordsExplored')}',
                                      label: 'words explored')),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: _StatTile(
                                      icon: Icons.auto_stories_outlined,
                                      value: '${_num('chaptersOpened')}',
                                      label: 'chapters opened')),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                  child: _StatTile(
                                      icon: Icons.edit_note_rounded,
                                      value: '${_num('storiesShared')}',
                                      label: 'stories shared')),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: _StatTile(
                                      icon: Icons.diversity_3_rounded,
                                      value: '${_num('groupsJoined')}',
                                      label: 'clubs & communities')),
                            ],
                          ),
                          if (_num('chaptersPublished') > 0) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _StatTile(
                                      icon: Icons.publish_rounded,
                                      value: '${_num('chaptersPublished')}',
                                      label: 'chapters you published',
                                      highlight: true),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(child: SizedBox()),
                              ],
                            ),
                          ],
                          const SizedBox(height: 22),
                          Text(
                            'Every number here is yours alone — counted from '
                            'what you actually read, wrote and explored.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: theme.hintColor,
                                fontSize: 12,
                                height: 1.5),
                          ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final bool highlight;

  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return GlassPanel(
      radius: 20,
      blur: 14,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                color: BookNestColors.cyan, size: 22),
            const SizedBox(height: 10),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: highlight
                    ? BookNestColors.cyan
                    : (dark
                        ? BookNestColors.darkTextPrimary
                        : BookNestColors.navyDeep),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(color: theme.hintColor, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
