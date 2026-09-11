import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../components/booknest_ui.dart';

/// The moderator's cockpit: everything BookNest is, in numbers — people,
/// their gender and age shapes, who is online right now, and the size of
/// every library on the platform. Custom-painted bars: crisp at every
/// DPI, no chart library, nothing to break.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  Map<String, dynamic>? _insights;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await BackendApi.instance.adminInsights();
    if (!mounted) return;
    setState(() {
      _insights = res == null ? null : (res['insights'] is Map
          ? Map<String, dynamic>.from(res['insights'] as Map)
          : null);
      _loading = false;
      _error = _insights == null
          ? 'Insights are only for the overall moderator — and the cloud '
              'must be reachable.'
          : null;
    });
  }

  int _num(String key) => ((_insights?[key] as num?) ?? 0).toInt();

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      appBar: GlassAppBar(
        title: 'Insights',
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded, size: 21),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: BookNestColors.cyan))
          : _error != null
              ? EmptyState(
                  icon: Icons.insights_rounded,
                  title: 'Not available',
                  subtitle: _error!,
                  action: TextButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded,
                        size: 18, color: BookNestColors.cyan),
                    label: const Text('Retry',
                        style: TextStyle(color: BookNestColors.cyan)),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                  children: [
                    Row(children: [
                      Expanded(
                        child: _StatTile(
                            icon: Icons.people_outline_rounded,
                            label: 'Readers',
                            value: _insights?['readers'] ?? 0),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatTile(
                            icon: Icons.wifi_tethering_rounded,
                            label: 'Online now',
                            value: _insights?['online'] ?? 0,
                            highlight: true),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    _genderPanel(onSurface),
                    const SizedBox(height: 12),
                    _agePanel(onSurface),
                    const SizedBox(height: 12),
                    _libraryPanel(onSurface),
                    const SizedBox(height: 12),
                    _groupsPanel(onSurface),
                    const SizedBox(height: 12),
                    _moderationPanel(onSurface),
                  ],
                ),
    );
  }

  Widget _genderPanel(Color onSurface) {
    final genders = Map<String, dynamic>.from(
        (_insights?['genders'] as Map?) ?? {});
    final female = ((genders['female'] as num?) ?? 0).toInt();
    final male = ((genders['male'] as num?) ?? 0).toInt();
    final other = genders.entries
        .where((e) => e.key != 'female' && e.key != 'male')
        .fold<int>(0, (sum, e) => sum + ((e.value as num?) ?? 0).toInt());
    final total = female + male + other;
    return _Panel(
      icon: Icons.wc_rounded,
      title: 'Gender',
      child: Column(children: [
        Row(children: [
          Expanded(child: _BarStrip(
            segments: [
              if (total > 0) ...[
                (female / total, BookNestColors.cyan),
                (male / total, BookNestColors.navy),
                (other / total, Colors.white24),
              ],
            ],
          )),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _LegendDot(color: BookNestColors.cyan,
              label: 'Female · $female'),
          const SizedBox(width: 14),
          _LegendDot(color: BookNestColors.navy, label: 'Male · $male'),
          if (other > 0) ...[
            const SizedBox(width: 14),
            _LegendDot(color: Colors.white24, label: 'Other · $other'),
          ],
        ]),
      ]),
    );
  }

  Widget _agePanel(Color onSurface) {
    final ages = Map<String, dynamic>.from((_insights?['ages'] as Map?) ?? {});
    final order = ['13-17', '18-24', '25-34', '35-44', '45-54', '55+'];
    final values = [for (final k in order) ((ages[k] as num?) ?? 0).toInt()];
    final maxV = values.fold<int>(0, (m, v) => v > m ? v : m);
    final withBirth = _num('withBirth');
    return _Panel(
      icon: Icons.cake_outlined,
      title: 'Ages of readers',
      subtitle: withBirth == 0
          ? 'Birth years fill in as readers complete their profiles'
          : '$withBirth reader${withBirth == 1 ? '' : 's'} shared their age',
      child: Column(children: [
        for (var i = 0; i < order.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              SizedBox(
                  width: 52,
                  child: Text(order[i],
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: onSurface.withOpacity(.7)))),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(children: [
                    Container(height: 14, color: onSurface.withOpacity(.06)),
                    FractionallySizedBox(
                      widthFactor: maxV == 0 ? 0 : values[i] / maxV,
                      child: Container(
                        height: 14,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [
                            BookNestColors.cyan,
                            BookNestColors.navy,
                          ]),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                  width: 34,
                  child: Text('${values[i]}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: onSurface.withOpacity(.8)))),
            ]),
          ),
        if (((ages['unset'] as num?) ?? 0).toInt() > 0)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
                '${ages['unset']} reader${((ages['unset'] as num?) ?? 0).toInt() == 1 ? '' : 's'} haven\u2019t set a birth year yet',
                style: TextStyle(
                    fontSize: 11, color: onSurface.withOpacity(.45))),
          ),
      ]),
    );
  }

  Widget _libraryPanel(Color onSurface) {
    return _Panel(
      icon: Icons.local_library_outlined,
      title: 'The library',
      child: Row(children: [
        Expanded(child: _MiniStat(
            label: 'Books', value: _num('books'))),
        Expanded(child: _MiniStat(
            label: 'Quotes', value: _num('quotes'))),
        Expanded(child: _MiniStat(
            label: 'Reviews', value: _num('reviews'))),
      ]),
    );
  }

  Widget _groupsPanel(Color onSurface) {
    final groups =
        Map<String, dynamic>.from((_insights?['groups'] as Map?) ?? {});
    return _Panel(
      icon: Icons.groups_outlined,
      title: 'Communities of readers',
      child: Row(children: [
        Expanded(child: _MiniStat(
            label: 'Clubs',
            value: ((groups['clubs'] as num?) ?? 0).toInt())),
        Expanded(child: _MiniStat(
            label: 'Communities',
            value: ((groups['communities'] as num?) ?? 0).toInt())),
        Expanded(child: _MiniStat(
            label: 'Orgs',
            value: ((groups['organizations'] as num?) ?? 0).toInt())),
        Expanded(child: _MiniStat(
            label: 'Schools',
            value: ((groups['schools'] as num?) ?? 0).toInt())),
      ]),
    );
  }

  Widget _moderationPanel(Color onSurface) {
    return _Panel(
      icon: Icons.gavel_rounded,
      title: 'Pulse',
      child: Column(children: [
        Row(children: [
          Expanded(child: _MiniStat(
              label: 'Messages', value: _num('messages'))),
          Expanded(child: _MiniStat(
              label: 'Posts', value: _num('posts'))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _MiniStat(
              label: 'Open reports',
              value: _num('openReports'),
              tone: _num('openReports') > 0
                  ? const Color(0xFFD06A6A)
                  : null)),
          Expanded(child: _MiniStat(
              label: 'Active punishments',
              value: _num('activeBans'))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => context.push('/moderator/users'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: BookNestColors.cyan.withOpacity(.55)),
                foregroundColor: BookNestColors.cyan,
              ),
              icon: const Icon(Icons.people_rounded, size: 17),
              label: const Text('All readers',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => context.push('/moderator/mass'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: BookNestColors.cyan.withOpacity(.55)),
                foregroundColor: BookNestColors.cyan,
              ),
              icon: const Icon(Icons.campaign_rounded, size: 17),
              label: const Text('Broadcast',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassPanel(
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 19, color: BookNestColors.cyan),
            const SizedBox(width: 8),
            Text(title,
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: onSurface)),
          ]),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(subtitle!,
                style: TextStyle(
                    fontSize: 11, color: onSurface.withOpacity(.5))),
          ],
          const SizedBox(height: 12),
          child,
        ]),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final dynamic value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassPanel(
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon,
              size: 20,
              color: highlight ? BookNestColors.cyan : onSurface.withOpacity(.6)),
          const SizedBox(height: 8),
          Text('$value',
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: highlight ? BookNestColors.cyan : onSurface)),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: onSurface.withOpacity(.6))),
        ]),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, this.tone});

  final String label;
  final int value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$value',
          style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: tone ?? BookNestColors.cyan)),
      const SizedBox(height: 2),
      Text(label,
          style: TextStyle(fontSize: 11.5, color: onSurface.withOpacity(.6))),
    ]);
  }
}

class _BarStrip extends StatelessWidget {
  const _BarStrip({required this.segments});

  final List<(double, Color)> segments;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 18,
        child: Row(children: [
          for (final (fraction, color) in segments)
            Expanded(
              flex: (fraction * 1000).round().clamp(0, 1000),
              child: Container(color: color),
            ),
        ]),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label,
          style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: onSurface.withOpacity(.75))),
    ]);
  }
}
