import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../components/booknest_ui.dart';
import '../../components/skeleton_kit.dart';

/// Brainstorm — BookNest's idea boards. Anyone floats an idea; everyone
/// builds on it in true threads: replies nest one level deep with
/// "replying to" badges, exactly like post conversations. 💡 to boost the
/// ideas worth building.
class BrainstormScreen extends StatefulWidget {
  const BrainstormScreen({super.key});

  @override
  State<BrainstormScreen> createState() => _BrainstormScreenState();
}

class _BrainstormScreenState extends State<BrainstormScreen> {
  List<Map<String, dynamic>> _ideas = [];
  bool _loading = true;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await BackendApi.instance.callFresh('brainstorm.list');
    if (!mounted) return;
    setState(() {
      _ideas = ((res?['ideas'] as List?) ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _loading = false;
    });
  }

  String _nameOf(Map<String, dynamic> row) {
    final profile = row['profile'];
    if (profile is Map) {
      final m = Map<String, dynamic>.from(profile);
      return (m['username']?.toString().isNotEmpty ?? false)
          ? m['username'].toString()
          : (m['display_name']?.toString().isNotEmpty ?? false
              ? m['display_name'].toString()
              : 'Reader');
    }
    return 'Reader';
  }

  Future<void> _newIdea() async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .62,
          child: Column(children: [
            const SizedBox(height: 12),
            Text('Float an idea',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: TextField(
                controller: titleCtrl,
                maxLength: 160,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    hintText: 'What should BookNest build, host or try next?',
                    counterText: ''),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: TextField(
                controller: bodyCtrl,
                minLines: 4,
                maxLines: 9,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    hintText:
                        'Sketch it out — the thread builds on what you start…'),
              ),
            ),
            const Spacer(),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: BookNestColors.navy,
                        foregroundColor: BookNestColors.cyan),
                    onPressed: () => Navigator.pop(sheetContext, true),
                    icon: const Icon(Icons.lightbulb_rounded, size: 19),
                    label: const Text('Share the idea',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
    if (created != true) return;
    final title = titleCtrl.text.trim();
    final body = bodyCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _posting = true);
    final res = await BackendApi.instance
        .call('brainstorm.create', {'title': title, 'body': body});
    if (!mounted) return;
    setState(() => _posting = false);
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('The idea could not be posted — please try again.')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Idea live — the floor is yours. 💡')));
    _load();
  }

  Future<void> _like(Map<String, dynamic> idea) async {
    final res = await BackendApi.instance
        .call('brainstorm.like', {'ideaId': idea['id']?.toString() ?? ''});
    if (!mounted || res == null) return;
    setState(() {
      idea['liked'] = res['liked'] == true;
      idea['likeCount'] = (res['likeCount'] as num?)?.toInt() ?? 0;
    });
  }

  void _openThread(Map<String, dynamic> idea) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _IdeaThreadSheet(idea: idea),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Scaffold(
      appBar: GlassAppBar(
        title: 'Brainstorm',
        actions: [
          IconButton(
            tooltip: 'New idea',
            icon: const Icon(Icons.lightbulb_rounded,
                color: BookNestColors.cyan),
            onPressed: _posting ? null : _newIdea,
          ),
        ],
      ),
      body: _loading
          ? const RowsSkeleton(count: 6)
          : RefreshIndicator(
              color: BookNestColors.cyan,
              onRefresh: _load,
              child: _ideas.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 120),
                      EmptyState(
                        icon: Icons.lightbulb_rounded,
                        title: 'The board is empty',
                        subtitle:
                            'Float the first idea — every thread starts with '
                            'one bold thought.',
                        action: GradientButton(
                          label: 'Float an idea',
                          icon: Icons.lightbulb_outline_rounded,
                          onPressed: _newIdea,
                        ),
                      ),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      itemCount: _ideas.length,
                      itemBuilder: (context, i) {
                        final idea = _ideas[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GlassPanel(
                            radius: 20,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => _openThread(idea),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      CircleAvatar(
                                        radius: 14,
                                        backgroundColor:
                                            BookNestColors.navy,
                                        child: Text(
                                            _nameOf(idea).characters.isEmpty
                                                ? '?'
                                                : _nameOf(idea)
                                                    .characters
                                                    .first
                                                    .toUpperCase(),
                                            style: const TextStyle(
                                                color:
                                                    BookNestColors.cyan,
                                                fontSize: 11,
                                                fontWeight:
                                                    FontWeight.bold)),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(_nameOf(idea),
                                            maxLines: 1,
                                            overflow:
                                                TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 12.5,
                                                fontWeight:
                                                    FontWeight.w700)),
                                      ),
                                      Text(
                                        _relative(idea['createdAt']
                                                ?.toString() ??
                                            ''),
                                        style: TextStyle(
                                            fontSize: 10.5,
                                            color: onSurface
                                                .withOpacity(.5)),
                                      ),
                                    ]),
                                    const SizedBox(height: 10),
                                    Text(idea['title']?.toString() ?? '',
                                        style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: onSurface)),
                                    if ((idea['body']?.toString() ?? '')
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 5),
                                      Text(idea['body'].toString(),
                                          maxLines: 4,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 13.2,
                                              height: 1.4,
                                              color: onSurface
                                                  .withOpacity(.85))),
                                    ],
                                    const SizedBox(height: 12),
                                    Row(children: [
                                      GestureDetector(
                                        onTap: () => _like(idea),
                                        child: Row(children: [
                                          Icon(
                                            idea['liked'] == true
                                                ? Icons.lightbulb_rounded
                                                : Icons
                                                    .lightbulb_outline_rounded,
                                            size: 18,
                                            color: BookNestColors.cyan,
                                          ),
                                          if (((idea['likeCount']
                                                          as num?)
                                                      ?.toInt() ??
                                                  0) !=
                                              0) ...[
                                            const SizedBox(width: 5),
                                            Text(
                                              '${(idea['likeCount'] as num?)?.toInt() ?? 0}',
                                              style: const TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight:
                                                      FontWeight.w800,
                                                  color: BookNestColors
                                                      .cyan),
                                            ),
                                          ],
                                        ]),
                                      ),
                                      const SizedBox(width: 18),
                                      Icon(Icons.mode_comment_outlined,
                                          size: 17,
                                          color: onSurface
                                              .withOpacity(.55)),
                                      const SizedBox(width: 5),
                                      Text(
                                        '${(idea['replyCount'] as num?)?.toInt() ?? 0}',
                                        style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                            color: onSurface
                                                .withOpacity(.65)),
                                      ),
                                      const Spacer(),
                                      Text('Build on it →',
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: BookNestColors.cyan)),
                                    ]),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }

  String _relative(String iso) {
    final at = DateTime.tryParse(iso);
    if (at == null) return '';
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    return '${at.month}/${at.day}';
  }
}

/// The idea's thread sheet: full replies with one-level threading.
class _IdeaThreadSheet extends StatefulWidget {
  final Map<String, dynamic> idea;
  const _IdeaThreadSheet({required this.idea});

  @override
  State<_IdeaThreadSheet> createState() => _IdeaThreadSheetState();
}

class _IdeaThreadSheetState extends State<_IdeaThreadSheet> {
  List<Map<String, dynamic>> _replies = [];
  bool _loading = true;
  bool _sending = false;
  final _input = TextEditingController();
  Map<String, dynamic>? _replyTarget;
  final Set<String> _expanded = {};
  bool _liked = false;
  int _likeCount = 0;

  @override
  void initState() {
    super.initState();
    _liked = widget.idea['liked'] == true;
    _likeCount = (widget.idea['likeCount'] as num?)?.toInt() ?? 0;
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await BackendApi.instance
        .call('brainstorm.replies', {'ideaId': widget.idea['id']?.toString()});
    if (!mounted) return;
    setState(() {
      _replies = ((res?['replies'] as List?) ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _loading = false;
    });
  }

  String _nameOf(Map<String, dynamic> row) {
    final profile = row['profile'];
    if (profile is Map) {
      final m = Map<String, dynamic>.from(profile);
      return (m['username']?.toString().isNotEmpty ?? false)
          ? m['username'].toString()
          : 'Reader';
    }
    return 'Reader';
  }

  List<Map<String, dynamic>> get _roots => _replies
      .where((r) =>
          r['parentId'] == null || r['parentId'].toString().isEmpty)
      .toList();

  List<Map<String, dynamic>> _repliesOf(String rootId) => _replies
      .where((r) => r['parentId'].toString() == rootId)
      .toList();

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final target = _replyTarget;
    final res = await BackendApi.instance.call('brainstorm.reply', {
      'ideaId': widget.idea['id']?.toString() ?? '',
      'text': text,
      if (target != null) 'parentId': target['id']?.toString() ?? '',
    });
    if (!mounted) return;
    setState(() => _sending = false);
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not post — please try again.')));
      return;
    }
    _input.clear();
    final reply = res['reply'] is Map
        ? Map<String, dynamic>.from(res['reply'] as Map)
        : <String, dynamic>{
            'text': text,
            'createdAt': DateTime.now().toIso8601String(),
            if (target != null)
              'parentId': target['parentId']?.toString().isNotEmpty == true
                  ? target['parentId'].toString()
                  : target['id'].toString(),
            if (target != null) 'replyToName': _nameOf(target),
          };
    setState(() {
      _replies = [..._replies, reply];
      if (reply['parentId']?.toString().isNotEmpty ?? false) {
        _expanded.add(reply['parentId'].toString());
      }
      _replyTarget = null;
    });
  }

  Future<void> _like() async {
    final res = await BackendApi.instance.call('brainstorm.like',
        {'ideaId': widget.idea['id']?.toString() ?? ''});
    if (!mounted || res == null) return;
    setState(() {
      _liked = res['liked'] == true;
      _likeCount = (res['likeCount'] as num?)?.toInt() ?? 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final idea = widget.idea;
    final roots = _roots;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: Column(children: [
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).hintColor.withOpacity(.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(children: [
              Expanded(
                child: Text(idea['title']?.toString() ?? 'Idea',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurface)),
              ),
              GestureDetector(
                onTap: _like,
                child: Row(children: [
                  Icon(
                    _liked
                        ? Icons.lightbulb_rounded
                        : Icons.lightbulb_outline_rounded,
                    size: 19,
                    color: BookNestColors.cyan,
                  ),
                  if (_likeCount > 0) ...[
                    const SizedBox(width: 4),
                    Text('$_likeCount',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: BookNestColors.cyan)),
                  ],
                ]),
              ),
            ]),
          ),
          Expanded(
            child: _loading
                ? const RowsSkeleton(count: 5)
                : roots.isEmpty
                    ? Center(
                        child: Text('Build on this idea — start the thread.',
                            style: TextStyle(
                                color: Theme.of(context).hintColor)),
                      )
                    : ListView.builder(
                        padding:
                            const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        itemCount: roots.length,
                        itemBuilder: (context, i) {
                          final root = roots[i];
                          final rootId = root['id']?.toString() ?? '';
                          final replies = _repliesOf(rootId);
                          final expanded = _expanded.contains(rootId);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.white.withOpacity(.05)
                                  : BookNestColors.navyDeep
                                      .withOpacity(.04),
                            ),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                _row(root, () {
                                  setState(() => _replyTarget = root);
                                }),
                                if (replies.isNotEmpty && !expanded)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        top: 6, left: 34),
                                    child: GestureDetector(
                                      onTap: () => setState(
                                          () => _expanded.add(rootId)),
                                      child: Text(
                                          'View ${replies.length} ${replies.length == 1 ? 'reply' : 'replies'}',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color:
                                                  BookNestColors.cyan)),
                                    ),
                                  ),
                                if (expanded) ...[
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        top: 4, left: 34, bottom: 2),
                                    child: GestureDetector(
                                      onTap: () => setState(
                                          () => _expanded.remove(rootId)),
                                      child: Text('Hide replies',
                                          style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w700,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withOpacity(.5))),
                                    ),
                                  ),
                                  for (final reply in replies)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          top: 8, left: 34),
                                      child: _row(
                                          reply,
                                          () => setState(
                                              () => _replyTarget = reply),
                                          badge: reply['replyToName']
                                              ?.toString()),
                                    ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
          ),
          if (_replyTarget != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
              child: Row(children: [
                Icon(Icons.subdirectory_arrow_right_rounded,
                    size: 15, color: BookNestColors.cyan.withOpacity(.9)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Replying to ${_nameOf(_replyTarget!)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                GestureDetector(
                  onTap: () => setState(() => _replyTarget = null),
                  child: Icon(Icons.close_rounded,
                      size: 16,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(.6)),
                ),
              ]),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: _replyTarget != null
                          ? 'Add a reply…'
                          : 'Build on this idea…',
                      suffixIcon: _sending
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: BookNestColors.cyan)),
                            )
                          : null,
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                IconButton(
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.send_rounded,
                      color: BookNestColors.cyan),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _row(Map<String, dynamic> row, VoidCallback onReply,
      {String? badge}) {
    final name = row['mine'] == true ? 'You' : _nameOf(row);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: BookNestColors.navy,
            child: Text(
                name.characters.isEmpty
                    ? '?'
                    : name.characters.first.toUpperCase(),
                style: const TextStyle(
                    color: BookNestColors.cyan,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Text(name,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700)),
          const Spacer(),
          GestureDetector(
            onTap: onReply,
            child: Text('Reply',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: BookNestColors.cyan.withOpacity(.85))),
          ),
        ]),
        if (badge != null && badge.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 5, left: 30),
            child: Text('↩ $badge',
                style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(.55))),
          ),
        const SizedBox(height: 6),
        Text(row['text']?.toString() ?? '',
            style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: Theme.of(context).colorScheme.onSurface)),
      ],
    );
  }
}
