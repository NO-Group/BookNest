import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

import '../../config/theme.dart';
import 'booknest_emojis.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// The BookNest keyboard — our own emote panel, Snapchat-style. Slides up
/// where the system keyboard lives: three tabs (Emotes / Animated /
/// Recent), tap once to send. Every emote is drawn in-house; the
/// animated tab plays live right in the grid.
/// ─────────────────────────────────────────────────────────────────────────────

class BookNestKeyboard extends StatefulWidget {
  /// Called when an emote is tapped — senders usually fire immediately.
  final ValueChanged<EmojiDef> onEmote;

  const BookNestKeyboard({super.key, required this.onEmote});

  @override
  State<BookNestKeyboard> createState() => _BookNestKeyboardState();
}

class _BookNestKeyboardState extends State<BookNestKeyboard>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  List<String> _recentCodes = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadRecents();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadRecents() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _recentCodes = prefs.getStringList('bn_emote_recents') ?? [];
      _loaded = true;
    });
  }

  Future<void> _remember(EmojiDef e) async {
    final prefs = await SharedPreferences.getInstance();
    final next = [e.code, ..._recentCodes.where((c) => c != e.code)].take(24).toList();
    await prefs.setStringList('bn_emote_recents', next);
    if (!mounted) return;
    setState(() => _recentCodes = next);
  }

  void _pick(EmojiDef e) {
    _remember(e);
    widget.onEmote(e);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: dark ? BookNestColors.darkChatBackground : Colors.white,
        border: Border(
          top: BorderSide(color: BookNestColors.cyan.withOpacity(.25)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 268,
          child: Column(
            children: [
              // ── header ──
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 8, 0),
                child: Row(
                  children: [
                    Container(
                      width: 22, height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(colors: [
                          BookNestColors.cyan, BookNestColors.navy]),
                      ),
                      child: const Icon(Icons.auto_awesome_rounded,
                          size: 12, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Text('BookNest Emotes',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: dark ? Colors.white : BookNestColors.navyDeep)),
                    const Spacer(),
                    Text('tap to send',
                        style: TextStyle(
                            fontSize: 10.5,
                            color: dark ? Colors.white38 : BookNestColors.navyDeep.withOpacity(.4))),
                  ],
                ),
              ),
              // ── tabs ──
              TabBar(
                controller: _tabs,
                indicatorColor: BookNestColors.cyan,
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: dark ? Colors.white : BookNestColors.navyDeep,
                unselectedLabelColor:
                    dark ? Colors.white38 : BookNestColors.navyDeep.withOpacity(.4),
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                tabs: const [
                  Tab(text: 'EMOTES'),
                  Tab(text: 'ANIMATED'),
                  Tab(text: 'RECENT'),
                ],
              ),
              Expanded(
                child: !_loaded
                    ? const Center(
                        child: SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: BookNestColors.cyan)))
                    : TabBarView(
                        controller: _tabs,
                        children: [
                          _grid(_staticEmotes, dark, animate: false),
                          _grid(_animatedEmotes, dark, animate: true),
                          _recentTab(dark),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static List<EmojiDef> get _staticEmotes =>
      bookNestEmotes.where((e) => !e.isAnimated).toList();
  static List<EmojiDef> get _animatedEmotes =>
      bookNestEmotes.where((e) => e.isAnimated).toList();

  Widget _grid(List<EmojiDef> items, bool dark, {required bool animate}) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 52,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final e = items[i];
        return _EmoteButton(
          def: e,
          animate: animate,
          onTap: () => _pick(e),
        );
      },
    );
  }

  Widget _recentTab(bool dark) {
    if (_recentCodes.isEmpty) {
      return Center(
        child: Text(
          'Emotes you send land here for one-tap reuse.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: dark ? Colors.white38 : BookNestColors.navyDeep.withOpacity(.45)),
        ),
      );
    }
    final defs = <EmojiDef>[];
    for (final c in _recentCodes) {
      final e = emojiByCode(c);
      if (e != null) defs.add(e);
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 52,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: defs.length,
      itemBuilder: (context, i) => _EmoteButton(
        def: defs[i],
        animate: defs[i].isAnimated,
        onTap: () => _pick(defs[i]),
      ),
    );
  }
}

class _EmoteButton extends StatelessWidget {
  final EmojiDef def;
  final bool animate;
  final VoidCallback onTap;

  const _EmoteButton({
    required this.def,
    required this.animate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: dark ? Colors.white.withOpacity(.05) : BookNestColors.lightSurface,
        ),
        child: Center(
          child: BookNestEmojiView(def.code, size: 30, animate: animate),
        ),
      ),
    );
  }
}
