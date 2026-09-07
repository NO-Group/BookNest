import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../config/theme.dart';
import '../../config/locales.dart';
import 'booknest_emojis.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// The BookNest keyboard, modelled on Microsoft SwiftKey: a toolbar with
/// translate and voice-typing, four pages (Emotes / Animated / System
/// emojis / Recent), one-tap sending — and it can be switched off in
/// Settings entirely.
/// ─────────────────────────────────────────────────────────────────────────────

/// Master switch (Settings → Language & keyboard).
final ValueNotifier<bool> booknestKeyboardEnabled = ValueNotifier<bool>(true);

Future<void> loadKeyboardEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  booknestKeyboardEnabled.value = prefs.getBool('bn_custom_keyboard') ?? true;
}

Future<void> setKeyboardEnabled(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('bn_custom_keyboard', value);
  booknestKeyboardEnabled.value = value;
}

/// When non-null, the next sent message is translated into this
/// language code first (the keyboard's translator toggle).
final ValueNotifier<String?> booknestTranslateTarget = ValueNotifier<String?>(null);

class BookNestKeyboard extends StatefulWidget {
  /// A BookNest emote was tapped — senders fire immediately.
  final ValueChanged<EmojiDef> onEmote;

  /// A system (Unicode) emoji was tapped — sent as a normal message.
  final ValueChanged<String> onSystemEmoji;

  /// Voice typing produced words — appended to the message field.
  final ValueChanged<String> onVoiceText;

  /// The reader's preferred language (defaults the translator target).
  final String preferredLanguage;

  const BookNestKeyboard({
    super.key,
    required this.onEmote,
    required this.onSystemEmoji,
    required this.onVoiceText,
    this.preferredLanguage = 'en',
  });

  @override
  State<BookNestKeyboard> createState() => _BookNestKeyboardState();
}

enum _KbPage { emotes, animated, system, recent }

class _BookNestKeyboardState extends State<BookNestKeyboard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wobble = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();
  _KbPage _page = _KbPage.emotes;
  List<String> _recentCodes = [];
  bool _loaded = false;
  bool _translateOn = false;
  late String _target = widget.preferredLanguage;

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _listening = false;
  bool _speechReady = false;

  @override
  void initState() {
    super.initState();
    booknestTranslateTarget.value = null;
    _loadRecents();
  }

  @override
  void dispose() {
    _wobble.dispose();
    _speech.stop();
    if (booknestTranslateTarget.value != null) booknestTranslateTarget.value = null;
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
    final next =
        [e.code, ..._recentCodes.where((c) => c != e.code)].take(24).toList();
    await prefs.setStringList('bn_emote_recents', next);
    if (!mounted) return;
    setState(() => _recentCodes = next);
  }

  void _pick(EmojiDef e) {
    _remember(e);
    widget.onEmote(e);
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    try {
      _speechReady = await _speech.initialize(
        onStatus: (status) {
          if ((status == 'done' || status == 'notListening') && mounted) {
            setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
    } catch (_) {
      _speechReady = false;
    }
    if (!_speechReady) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Voice typing is not available on this device — check the microphone permission.')));
      }
      return;
    }
    await _speech.listen(
      onResult: (result) {
        final words = result.recognizedWords.trim();
        if (words.isNotEmpty) widget.onVoiceText(words);
      },
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
      ),
      localeId: widget.preferredLanguage,
    );
    if (mounted) setState(() => _listening = true);
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
          height: 288,
          child: Column(
            children: [
              _toolbar(dark),
              Divider(height: 1, thickness: .6, color: Theme.of(context).dividerColor),
              if (_translateOn) _translateBar(dark),
              Expanded(child: _body(dark)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolbar(bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
      child: Row(
        children: [
          // Translator toggle
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() {
              _translateOn = !_translateOn;
              booknestTranslateTarget.value = _translateOn ? _target : null;
            }),
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Icon(Icons.translate_rounded,
                  size: 21,
                  color: _translateOn
                      ? BookNestColors.cyan
                      : (dark ? Colors.white54 : BookNestColors.navyDeep.withOpacity(.55))),
            ),
          ),
          // Voice typing
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _toggleMic,
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: _listening
                  ? SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: BookNestColors.cyan))
                  : Icon(Icons.mic_none_rounded,
                      size: 21,
                      color: dark ? Colors.white54 : BookNestColors.navyDeep.withOpacity(.55)),
            ),
          ),
          const Spacer(),
          _pageIcon(_KbPage.emotes, Icons.auto_awesome_rounded, 'Emotes', dark),
          _pageIcon(_KbPage.animated, Icons.animation_rounded, 'Animated', dark),
          _pageIcon(_KbPage.system, Icons.emoji_emotions_outlined, 'System', dark),
          _pageIcon(_KbPage.recent, Icons.history_rounded, 'Recent', dark),
        ],
      ),
    );
  }

  Widget _pageIcon(_KbPage page, IconData icon, String tip, bool dark) {
    final active = _page == page;
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _page = page),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(icon,
              size: 21,
              color: active
                  ? BookNestColors.cyan
                  : (dark ? Colors.white54 : BookNestColors.navyDeep.withOpacity(.55))),
        ),
      ),
    );
  }

  Widget _translateBar(bool dark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: BookNestColors.cyan.withOpacity(dark ? .1 : .08),
      child: Row(
        children: [
          Icon(Icons.translate_rounded, size: 15, color: BookNestColors.cyan),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Messages send translated',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: dark ? Colors.white : BookNestColors.navyDeep),
            ),
          ),
          DropdownButton<String>(
            value: _target,
            underline: const SizedBox.shrink(),
            isDense: true,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: dark ? Colors.white : BookNestColors.navyDeep),
            dropdownColor: dark ? BookNestColors.navy : Colors.white,
            items: [
              for (final l in bookNestLanguages)
                DropdownMenuItem(value: l.code, child: Text(l.name)),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _target = v);
              if (_translateOn) booknestTranslateTarget.value = v;
            },
          ),
        ],
      ),
    );
  }

  Widget _body(bool dark) {
    if (_listening) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: Tween<double>(begin: .9, end: 1.15)
                  .animate(CurvedAnimation(parent: _wobble, curve: Curves.easeInOut)),
              child: Container(
                width: 62,
                height: 62,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                        colors: [BookNestColors.cyan, BookNestColors.navy])),
                child: const Icon(Icons.mic_rounded,
                    color: Colors.white, size: 30),
              ),
            ),
            const SizedBox(height: 10),
            Text('Listening… speak now',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: dark ? Colors.white70 : BookNestColors.navyDeep)),
            const SizedBox(height: 4),
            Text('Words land in the message box. Tap the mic to stop.',
                style: TextStyle(
                    fontSize: 11,
                    color: dark ? Colors.white38 : BookNestColors.navyDeep.withOpacity(.5))),
          ],
        ),
      );
    }
    switch (_page) {
      case _KbPage.emotes:
        return _grid(_staticEmotes, dark, animate: false);
      case _KbPage.animated:
        return _grid(_animatedEmotes, dark, animate: true);
      case _KbPage.system:
        return _systemEmojiPage(dark);
      case _KbPage.recent:
        return _recentTab(dark);
    }
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
          child: BookNestEmojiView(e.code, size: 30, animate: true),
          onTap: () => _pick(e),
        );
      },
    );
  }

  // ── system (Unicode) emoji page ──

  static const Map<String, List<String>> _systemCategories = {
    'Smileys': [
      '😀','😃','😄','😁','😆','😅','🤣','😂','🙂','🙃','😉','😊','😇','🥰','😍','🤩',
      '😘','😗','😚','😙','🥲','😋','😛','😜','🤪','😝','🤑','🤗','🤭','🤫','🤔','🤐',
      '😐','😑','😶','😏','😒','🙄','😬','😮‍💨','🤥','😌','😔','😪','🤤','😴','😷','🤒',
      '🤕','🤢','🤮','🥵','🥶','😵','🤯','🤠','🥳','🥸','😎','🤓','🧐','😕','😟','🙁',
      '😮','😯','😲','😳','🥺','😦','😧','😨','😰','😥','😢','😭','😱','😖','😣','😞',
      '😓','😩','😫','🥱','😤','😡','😠','🤬','😈','👿','💀','💩','🤡','👻','👽','🤖',
    ],
    'Hearts & symbols': [
      '❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎','💔','❣️','💕','💞','💓','💗','💖',
      '💘','💝','💟','✨','⭐','🌟','💫','⚡','🔥','🌈','☀️','🌙','☁️','❄️','💧','🎉',
      '🎊','🎈','🎁','🎁','🏆','🥇','🎯','💡','📚','✍️','🫶','👍','👎','👏','🙌','🤝',
      '🙏','💪','👀','🧠','👑','💬','💭','🔔','📌','🔖','✅','❌','❗','❓','💯','🆗',
    ],
    'Animals & nature': [
      '🐶','🐱','🐭','🐹','🐰','🦊','🐻','🐼','🐨','🐯','🦁','🐮','🐷','🐸','🐵','🙈',
      '🐔','🐧','🐦','🐤','🦆','🦉','🦇','🐺','🐗','🐴','🦄','🐝','🦋','🐌','🐞','🐢',
      '🐍','🐙','🦑','🦐','🐠','🐟','🐬','🐳','🐘','🦒','🦓','🐭','🦔','🐰','🌍','🌙',
      '🌵','🌲','🌳','🌴','🌱','🌿','☘️','🍀','🍃','🌸','🌺','🌻','🌼','🌷','🥀','🌾',
    ],
    'Food & drink': [
      '🍏','🍎','🍐','🍊','🍋','🍌','🍉','🍇','🍓','🫐','🍈','🍒','🍑','🥭','🍍','🥥',
      '🥝','🍅','🥑','🥦','🥬','🥒','🌶️','🌽','🥕','🧄','🧅','🥔','🍠','🥐','🍞','🥖',
      '🧇','🧀','🍗','🍖','🥩','🍤','🍳','🍔','🍟','🍕','🌮','🌯','🥗','🍝','🍜','🍲',
      '🍣','🍱','🍛','🍚','🥟','🍦','🍰','🎂','🍫','🍬','🍭','🍩','🍪','☕','🍵','🧋',
    ],
    'Activities & travel': [
      '⚽','🏀','🏈','⚾','🎾','🏐','🏉','🥏','🎱','🏓','🏸','🥊','🥋','⛳','🎣','🤿',
      '🎽','🛹','🛼','🎮','🎲','🧩','🎨','🎬','🎤','🎧','🎼','🎹','🥁','🎸','🎺','📚',
      '✈️','🚀','🛳️','🚗','🚕','🚌','🚲','🛴','🗺️','🧭','🏔️','🏖️','🏙️','🎡','🎢','🎪',
    ],
  };

  Widget _systemEmojiPage(bool dark) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      children: [
        for (final entry in _systemCategories.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 0, 4),
            child: Text(entry.key.toUpperCase(),
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: .8,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).hintColor)),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 46,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            itemCount: entry.value.length,
            itemBuilder: (context, i) {
              final emoji = entry.value[i];
              return _EmoteButton(
                child: Text(emoji,
                    style: const TextStyle(fontSize: 24),
                    textAlign: TextAlign.center),
                onTap: () => widget.onSystemEmoji(emoji),
              );
            },
          ),
        ],
      ],
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
              color:
                  dark ? Colors.white38 : BookNestColors.navyDeep.withOpacity(.45)),
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
        child: BookNestEmojiView(defs[i].code, size: 30, animate: true),
        onTap: () => _pick(defs[i]),
      ),
    );
  }
}

class _EmoteButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;

  const _EmoteButton({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: dark
                ? Colors.white.withOpacity(.05)
                : BookNestColors.lightSurface,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}
