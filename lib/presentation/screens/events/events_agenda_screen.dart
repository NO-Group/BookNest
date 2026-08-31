// lib/presentation/screens/events/events_agenda_screen.dart
//
// Events agenda — every event post in one glass timeline, with live RSVP
// toggles. Backend: events.list / events.rsvp edge actions (events come
// from the posts table; RSVPs live in booknest_social.event_rsvps).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../components/booknest_ui.dart';

class EventsAgendaScreen extends StatefulWidget {
  const EventsAgendaScreen({super.key});

  @override
  State<EventsAgendaScreen> createState() => _EventsAgendaScreenState();
}

class _EventsAgendaScreenState extends State<EventsAgendaScreen> {
  bool _loading = true;
  bool _offline = false;
  bool _onlyMine = false;
  List<Map<String, dynamic>> _events = const [];
  final Set<String> _busy = {};

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
    final res = await BackendApi.instance.call('events.list');
    if (!mounted) return;
    if (res == null) {
      setState(() {
        _offline = true;
        _loading = false;
      });
      return;
    }
    setState(() {
      _events = ((res['events'] as List?) ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _loading = false;
    });
  }

  DateTime? _eventDate(Map<String, dynamic> event) {
    final meta = event['metadata'];
    if (meta is Map) {
      final parsed =
          DateFormat('EEE, MMM d, yyyy').tryParse(meta['date']?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return DateTime.tryParse(event['createdAt']?.toString() ?? '');
  }

  Future<void> _toggleRsvp(Map<String, dynamic> event) async {
    final id = event['id']?.toString() ?? '';
    if (id.isEmpty || _busy.contains(id)) return;
    setState(() => _busy.add(id));
    final res =
        await BackendApi.instance.call('events.rsvp', {'postId': id});
    if (!mounted) return;
    setState(() => _busy.remove(id));
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not reach the event service — try again.')));
      return;
    }
    setState(() {
      event['rsvped'] = res['rsvped'] == true;
      event['going'] = (res['going'] as num?)?.toInt() ?? event['going'];
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res['rsvped'] == true
            ? 'You are going to "${event['title']}" 🎉'
            : 'RSVP withdrawn')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _onlyMine
        ? _events.where((e) => e['rsvped'] == true).toList()
        : List<Map<String, dynamic>>.of(_events);
    visible.sort((a, b) {
      final da = _eventDate(a) ?? DateTime(1970);
      final db = _eventDate(b) ?? DateTime(1970);
      return da.compareTo(db);
    });

    return Scaffold(
      appBar: GlassAppBar(title: 'Events agenda', actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded,
              color: BookNestColors.cyan),
        ),
      ]),
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(color: BookNestColors.cyan))
          : _offline
              ? EmptyState(
                  icon: Icons.wifi_off_rounded,
                  title: 'Agenda is offline',
                  subtitle: 'The BookNest backend is not reachable yet.',
                  action: TextButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded,
                        size: 18, color: BookNestColors.cyan),
                    label: const Text('Retry',
                        style: TextStyle(color: BookNestColors.cyan)),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                      child: Row(
                        children: [
                          _filterChip('All events', !_onlyMine, () {
                            setState(() => _onlyMine = false);
                          }),
                          const SizedBox(width: 8),
                          _filterChip('Going', _onlyMine, () {
                            setState(() => _onlyMine = true);
                          }),
                        ],
                      ),
                    ),
                    Expanded(
                      child: visible.isEmpty
                          ? EmptyState(
                              icon: Icons.event_busy_rounded,
                              title: _onlyMine
                                  ? 'No RSVPs yet'
                                  : 'No events scheduled',
                              subtitle: _onlyMine
                                  ? 'Tap Going on an event and it lands here.'
                                  : 'Create one from the feed with the '
                                      'stylus → Event.',
                            )
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 8, 20, 40),
                              itemCount: visible.length,
                              itemBuilder: (context, index) {
                                return Entrance(
                                  index: index,
                                  child: _eventCard(theme, visible[index]),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? BookNestColors.cyan
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: selected
                ? null
                : Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? BookNestColors.navyDeep
                  : Theme.of(context).colorScheme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _eventCard(ThemeData theme, Map<String, dynamic> event) {
    final meta = event['metadata'];
    final metaMap = meta is Map ? meta : <String, dynamic>{};
    final date = _eventDate(event);
    final isOnline = metaMap['is_online'] == true;
    final location = metaMap['location']?.toString();
    final rsvped = event['rsvped'] == true;
    final going = (event['going'] as num?)?.toInt() ?? 0;
    final id = event['id']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassPanel(
        radius: 22,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // date badge
              Container(
                width: 54,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [
                    BookNestColors.cyanSoft,
                    BookNestColors.cyan,
                  ]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Text(
                      date != null ? DateFormat('MMM').format(date) : '—',
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: BookNestColors.navyDeep),
                    ),
                    Text(
                      date != null ? DateFormat('d').format(date) : '?',
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: BookNestColors.navyDeep),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event['title']?.toString() ?? 'Untitled event',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text('by ${event['author'] ?? 'Reader'}',
                        style: TextStyle(
                            color: theme.hintColor, fontSize: 12)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                            isOnline
                                ? Icons.videocam_rounded
                                : Icons.location_on_rounded,
                            size: 14,
                            color: BookNestColors.cyan),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                              isOnline
                                  ? 'Online event'
                                  : (location?.isNotEmpty == true
                                      ? location!
                                      : 'Venue to be announced'),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: theme.hintColor, fontSize: 12)),
                        ),
                      ],
                    ),
                    if (metaMap['time'] != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.schedule_rounded,
                              size: 14, color: BookNestColors.cyan),
                          const SizedBox(width: 5),
                          Text(metaMap['time'].toString(),
                              style: TextStyle(
                                  color: theme.hintColor, fontSize: 12)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          child: GestureDetector(
                            onTap: () => _toggleRsvp(event),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: rsvped
                                    ? BookNestColors.cyan
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                    color: BookNestColors.cyan
                                        .withOpacity(.7)),
                              ),
                              child: _busy.contains(id)
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: BookNestColors.cyan))
                                  : Text(
                                      rsvped ? 'Going ✓' : 'RSVP',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: rsvped
                                              ? BookNestColors.navyDeep
                                              : BookNestColors.cyan),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text('$going going',
                            style: TextStyle(
                                color: theme.hintColor, fontSize: 12.5)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
