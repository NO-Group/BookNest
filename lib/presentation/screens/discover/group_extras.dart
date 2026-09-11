import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../components/booknest_ui.dart';

/// The live facts a shared group section needs. Hosted by whichever
/// screen is showing the group — the group base page or the club page.
class GroupContext {
  const GroupContext({
    required this.kind,
    required this.groupId,
    this.group,
    this.isMember = false,
    this.isManager = false,
    required this.reload,
  });

  final String kind;
  final String groupId;
  final Map<String, dynamic>? group;
  final bool isMember;
  final bool isManager;
  final Future<void> Function() reload;
}

/// ── Community channels ──────────────────────────────────────────────────
/// Named, members-only topic chat rooms. Owners and deputies add and
/// remove them; every member reads and writes. The chat itself opens in
/// the standard group chat screen, scoped to the channel.
class GroupChannelsSection extends StatefulWidget {
  const GroupChannelsSection({super.key, required this.state});

  final GroupContext state;

  @override
  State<GroupChannelsSection> createState() => _GroupChannelsSectionState();
}

class _GroupChannelsSectionState extends State<GroupChannelsSection> {
  List<Map<String, dynamic>> _channels = [];
  bool _loading = true;
  bool _busy = false;

  GroupContext get _state => widget.state;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await BackendApi.instance
        .call('groups.channels.list', {'groupId': _state.groupId});
    if (!mounted) return;
    setState(() {
      _channels = ((res?['channels'] as List?) ?? const [])
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _loading = false;
    });
  }

  Future<void> _createChannel() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('New channel',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 48,
          decoration: const InputDecoration(
              prefixText: '# ',
              hintText: 'e.g. poetry, launches, help'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: BookNestColors.navy),
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    setState(() => _busy = true);
    final res = await BackendApi.instance.call('groups.channels.create',
        {'kind': _state.kind, 'groupId': _state.groupId, 'name': name});
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res != null
            ? 'Channel "$name" created.'
            : 'Could not create the channel — try again.')));
    if (res != null) _load();
  }

  Future<void> _removeChannel(Map<String, dynamic> channel) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove channel?',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text(
            '"${channel['name']?.toString() ?? 'This channel'}" will be '
            'removed from the channel list.',
            style: const TextStyle(fontSize: 13.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (sure != true) return;
    final res = await BackendApi.instance.call('groups.channels.remove', {
      'kind': _state.kind,
      'groupId': _state.groupId,
      'channelId': channel['id']?.toString() ?? '',
    });
    if (!mounted) return;
    if (res != null) _load();
  }

  void _openChannel(Map<String, dynamic> channel) {
    final groupName = _state.group?['name']?.toString() ?? '';
    final name = channel['name']?.toString() ?? '';
    context.push('/club-chat?id=${_state.groupId}&kind=${_state.kind}'
        '&chan=${Uri.encodeComponent(name)}'
        '&title=${Uri.encodeComponent('#$name · $groupName')}');
  }

  @override
  Widget build(BuildContext context) {
    if (!_state.isMember) return const SizedBox.shrink();
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassPanel(
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.tag_rounded, size: 19, color: BookNestColors.cyan),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Channels · ${_channels.length}',
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: onSurface)),
            ),
            if (_state.isManager)
              IconButton(
                tooltip: 'New channel',
                icon: const Icon(Icons.add_circle_outline_rounded,
                    size: 21, color: BookNestColors.cyan),
                onPressed: _busy ? null : _createChannel,
              ),
          ]),
          const SizedBox(height: 4),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                  child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: BookNestColors.cyan))),
            )
          else if (_channels.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                  _state.isManager
                      ? 'No channels yet — add topic rooms like poetry '
                          'or launches.'
                      : 'No channels yet.',
                  style: TextStyle(
                      fontSize: 12.5, color: onSurface.withOpacity(.6))),
            )
          else
            for (final channel in _channels)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: InkWell(
                  onTap: () => _openChannel(channel),
                  onLongPress:
                      _state.isManager ? () => _removeChannel(channel) : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                    child: Row(children: [
                      const Icon(Icons.tag_rounded,
                          size: 17, color: BookNestColors.cyan),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(channel['name']?.toString() ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13.2,
                                fontWeight: FontWeight.w700,
                                color: onSurface)),
                      ),
                      const Text('Open chat',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: BookNestColors.cyan)),
                      Icon(Icons.chevron_right_rounded,
                          size: 17, color: onSurface.withOpacity(.35)),
                    ]),
                  ),
                ),
              ),
        ]),
      ),
    );
  }
}

/// ── Group events with RSVPs ─────────────────────────────────────────────
/// Scheduled happenings for the group: owners and deputies create them,
/// members respond Going / Interested, and live countdowns keep the
/// anticipation honest.
class GroupEventsSection extends StatefulWidget {
  const GroupEventsSection({super.key, required this.state});

  final GroupContext state;

  @override
  State<GroupEventsSection> createState() => _GroupEventsSectionState();
}

class _GroupEventsSectionState extends State<GroupEventsSection> {
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  bool _busy = false;
  Timer? _ticker;

  GroupContext get _state => widget.state;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await BackendApi.instance
        .call('groups.events.list', {'groupId': _state.groupId});
    if (!mounted) return;
    setState(() {
      _events = ((res?['events'] as List?) ?? const [])
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _loading = false;
    });
  }

  String _whenLabel(DateTime? at) {
    if (at == null) return 'Date to be announced';
    final diff = at.difference(DateTime.now());
    if (diff.inMinutes < 0 && diff.inMinutes > -180) return 'Happening now';
    if (diff.inMinutes <= 0) return 'Done';
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final minutes = diff.inMinutes % 60;
    if (days > 0) return 'In $days d ${hours}h';
    if (hours > 0) return 'In ${hours}h ${minutes}m';
    return 'In ${minutes}m';
  }

  Future<void> _createEvent() async {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    DateTime? chosenDate;
    TimeOfDay? chosenTime;
    final form = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: const Text('New event',
              style: TextStyle(fontWeight: FontWeight.w800)),
          content: Form(
            key: form,
            child: SizedBox(
              width: double.maxFinite,
              child: ListView(shrinkWrap: true, children: [
                TextFormField(
                  controller: titleController,
                  maxLength: 120,
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'A title is required' : null,
                  decoration: const InputDecoration(
                      labelText: 'Event title',
                      hintText: 'e.g. Author night · Poetry slam'),
                ),
                TextFormField(
                  controller: bodyController,
                  maxLines: 2,
                  maxLength: 600,
                  decoration: const InputDecoration(
                      labelText: 'Details (optional)',
                      hintText: 'What is happening, where, for whom…'),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: dialogContext,
                          initialDate: DateTime.now().add(const Duration(days: 1)),
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setDialogState(() => chosenDate = picked);
                        }
                      },
                      icon: const Icon(Icons.event_outlined, size: 17),
                      label: Text(chosenDate == null
                          ? 'Pick date'
                          : '${chosenDate!.year}-${chosenDate!.month.toString().padLeft(2, '0')}-${chosenDate!.day.toString().padLeft(2, '0')}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: chosenDate == null
                          ? null
                          : () async {
                              final picked = await showTimePicker(
                                context: dialogContext,
                                initialTime: const TimeOfDay(hour: 17, minute: 0),
                              );
                              if (picked != null) {
                                setDialogState(() => chosenTime = picked);
                              }
                            },
                      icon: const Icon(Icons.schedule_rounded, size: 17),
                      label: Text(chosenTime == null
                          ? 'Pick time'
                          : chosenTime!.format(dialogContext)),
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                Text('Skip the date to announce it later.',
                    style: TextStyle(
                        fontSize: 11, color: Theme.of(dialogContext).hintColor)),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: BookNestColors.navy),
                onPressed: () {
                  if (!(form.currentState?.validate() ?? false)) return;
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('Schedule')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    DateTime? at;
    if (chosenDate != null) {
      final t = chosenTime ?? const TimeOfDay(hour: 17, minute: 0);
      at = DateTime(chosenDate!.year, chosenDate!.month, chosenDate!.day,
          t.hour, t.minute);
    }
    setState(() => _busy = true);
    final res = await BackendApi.instance.call('groups.events.create', {
      'kind': _state.kind,
      'groupId': _state.groupId,
      'title': titleController.text.trim(),
      'body': bodyController.text.trim(),
      if (at != null) 'at': at.toIso8601String(),
    });
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res != null
            ? 'Event scheduled ✓'
            : 'Could not schedule the event — try again.')));
    if (res != null) _load();
  }

  Future<void> _rsvp(Map<String, dynamic> event, String status) async {
    if (_busy) return;
    final current = event['myStatus']?.toString() ?? '';
    final next = current == status ? 'none' : status;
    setState(() {
      _busy = true;
      event['myStatus'] = next == 'none' ? null : next;
      if (next == 'none') {
        if (current == 'going') {
          event['going'] = (((event['going'] as num?) ?? 0).toInt() - 1);
        } else if (current == 'interested') {
          event['interested'] =
              (((event['interested'] as num?) ?? 0).toInt() - 1);
        }
      } else {
        if (next == 'going') {
          event['going'] = (((event['going'] as num?) ?? 0).toInt() + 1);
          if (current == 'interested') {
            event['interested'] =
                (((event['interested'] as num?) ?? 0).toInt() - 1);
          }
        } else {
          event['interested'] =
              (((event['interested'] as num?) ?? 0).toInt() + 1);
          if (current == 'going') {
            event['going'] = (((event['going'] as num?) ?? 0).toInt() - 1);
          }
        }
      }
    });
    final res = await BackendApi.instance.call('groups.events.rsvp',
        {'eventId': event['id']?.toString() ?? '', 'status': next});
    if (!mounted) return;
    setState(() => _busy = false);
    if (res == null) _load();
  }

  Future<void> _removeEvent(Map<String, dynamic> event) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove event?',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text(
            '"${event['title']?.toString() ?? 'This event'}" and its RSVPs '
            'will be removed.',
            style: const TextStyle(fontSize: 13.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (sure != true) return;
    final res = await BackendApi.instance
        .call('groups.events.remove', {'eventId': event['id']?.toString() ?? ''});
    if (!mounted) return;
    if (res != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassPanel(
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.event_rounded, size: 19, color: BookNestColors.cyan),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Events · ${_events.length}',
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: onSurface)),
            ),
            if (_state.isManager)
              IconButton(
                tooltip: 'New event',
                icon: const Icon(Icons.add_circle_outline_rounded,
                    size: 21, color: BookNestColors.cyan),
                onPressed: _busy ? null : _createEvent,
              ),
          ]),
          const SizedBox(height: 4),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                  child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: BookNestColors.cyan))),
            )
          else if (_events.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                  _state.isManager
                      ? 'No events yet — schedule the first meetup, launch '
                          'or reading night.'
                      : 'No events yet.',
                  style: TextStyle(
                      fontSize: 12.5, color: onSurface.withOpacity(.6))),
            )
          else
            for (final event in _events)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: BookNestColors.cyan.withOpacity(.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: BookNestColors.cyan.withOpacity(.16)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                              child: Text(
                                  event['title']?.toString() ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: onSurface)),
                            ),
                            Text(
                                _whenLabel(event['at'] == null
                                    ? null
                                    : DateTime.tryParse(
                                        event['at'].toString())),
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: BookNestColors.cyan)),
                            if (_state.isManager) ...[
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => _removeEvent(event),
                                child: Icon(Icons.close_rounded,
                                    size: 15,
                                    color: onSurface.withOpacity(.4)),
                              ),
                            ],
                          ]),
                          if ((event['body']?.toString() ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(event['body'].toString(),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12.3,
                                    height: 1.35,
                                    color: onSurface.withOpacity(.75))),
                          ],
                          const SizedBox(height: 10),
                          Row(children: [
                            _RsvpChip(
                              icon: Icons.check_circle_outline_rounded,
                              label:
                                  'Going · ${((event['going'] as num?) ?? 0).toInt()}',
                              selected:
                                  event['myStatus']?.toString() == 'going',
                              onTap: () => _rsvp(event, 'going'),
                            ),
                            const SizedBox(width: 8),
                            _RsvpChip(
                              icon: Icons.star_outline_rounded,
                              label:
                                  'Interested · ${((event['interested'] as num?) ?? 0).toInt()}',
                              selected: event['myStatus']?.toString() ==
                                  'interested',
                              onTap: () => _rsvp(event, 'interested'),
                            ),
                          ]),
                        ]),
                  ),
                ),
              ),
        ]),
      ),
    );
  }
}

class _RsvpChip extends StatelessWidget {
  const _RsvpChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? BookNestColors.cyan.withOpacity(.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected
                  ? BookNestColors.cyan
                  : BookNestColors.cyan.withOpacity(.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: 14,
              color: selected
                  ? BookNestColors.cyan
                  : BookNestColors.cyan.withOpacity(.75)),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: selected
                      ? BookNestColors.cyan
                      : BookNestColors.cyan.withOpacity(.8))),
        ]),
      ),
    );
  }
}

/// ── Group rules ─────────────────────────────────────────────────────────
/// The house rules, set by owners and deputies (one rule per line in the
/// editor), shown numbered to every member.
class GroupRulesSection extends StatelessWidget {
  const GroupRulesSection({super.key, required this.state});

  final GroupContext state;

  Future<void> _editRules(BuildContext context) async {
    final current =
        ((state.group?['rules'] as List?) ?? const [])
            .map((r) => r.toString())
            .join('\n');
    final controller = TextEditingController(text: current);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Group rules',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          maxLines: 8,
          maxLength: 3600,
          decoration: const InputDecoration(
              hintText: 'One rule per line, up to 12 rules.\n'
                  'e.g. Be kind to every reader.'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: BookNestColors.navy),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save rules')),
        ],
      ),
    );
    if (saved != true) return;
    final rules = controller.text
        .split('\n')
        .map((r) => r.trim())
        .where((r) => r.isNotEmpty)
        .take(12)
        .toList();
    final res = await BackendApi.instance.call('groups.rules.set', {
      'kind': state.kind,
      'groupId': state.groupId,
      'rules': rules,
    });
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res != null
            ? 'Rules saved ✓'
            : 'Could not save the rules — try again.')));
    if (res != null) state.reload();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final rules =
        ((state.group?['rules'] as List?) ?? const [])
            .map((r) => r.toString())
            .toList();
    return GlassPanel(
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.gavel_rounded, size: 19, color: BookNestColors.cyan),
            const SizedBox(width: 8),
            Expanded(
              child: Text('House rules',
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: onSurface)),
            ),
            if (state.isManager)
              IconButton(
                tooltip: 'Edit rules',
                icon: const Icon(Icons.edit_outlined,
                    size: 19, color: BookNestColors.cyan),
                onPressed: () => _editRules(context),
              ),
          ]),
          const SizedBox(height: 4),
          if (rules.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                  state.isManager
                      ? 'No rules yet — write the house rules so every '
                          'reader knows the culture.'
                      : 'No rules yet.',
                  style: TextStyle(
                      fontSize: 12.5, color: onSurface.withOpacity(.6))),
            )
          else
            for (var i = 0; i < rules.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: BookNestColors.cyan.withOpacity(.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            color: BookNestColors.cyan)),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(rules[i],
                        style: TextStyle(
                            fontSize: 12.8,
                            height: 1.35,
                            color: onSurface.withOpacity(.85))),
                  ),
                ]),
              ),
        ]),
      ),
    );
  }
}
