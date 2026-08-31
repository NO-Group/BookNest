// lib/presentation/screens/jenny/jenny_screen.dart
//
// Ask Jenny — BookNest's AI reading companion. Glass chat over the
// jenny.chat edge action; conversation history persists in MongoDB
// (booknest_chats.jenny_messages) and the last 10 turns are replayed
// as model context. Without the JENNY_API_KEY secret, Jenny says so.

import 'package:flutter/material.dart';
import 'dart:ui';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';

class _JennyMessage {
  final String role; // 'user' | 'assistant' | 'system'
  final String text;
  _JennyMessage(this.role, this.text);
}

class JennyScreen extends StatefulWidget {
  const JennyScreen({super.key});

  @override
  State<JennyScreen> createState() => _JennyScreenState();
}

class _JennyScreenState extends State<JennyScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_JennyMessage> _messages = [
    _JennyMessage(
        'assistant',
        'Hi, I am Jenny — your BookNest companion 📖\n\n'
            'Ask me for book recommendations, study help, or a nudge to '
            'finish that chapter tonight.'),
  ];
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    setState(() {
      _messages.add(_JennyMessage('user', text));
      _busy = true;
    });
    _scrollDown();

    final res =
        await BackendApi.instance.call('jenny.chat', {'message': text});
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (res == null) {
        _messages.add(_JennyMessage('system',
            'Jenny is unreachable right now — check your connection and try again.'));
      } else {
        _messages.add(
            _JennyMessage('assistant', res['reply']?.toString() ?? '…'));
      }
    });
    _scrollDown();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final glassBase =
        (dark ? BookNestColors.darkChatBackground : Colors.white);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [
                  BookNestColors.cyanSoft,
                  BookNestColors.cyan,
                ]),
                boxShadow: [
                  BoxShadow(
                      color: BookNestColors.cyan.withOpacity(.35),
                      blurRadius: 12),
                ],
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  size: 19, color: BookNestColors.navyDeep),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Jenny',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                Text('AI reading companion',
                    style:
                        TextStyle(color: theme.hintColor, fontSize: 11.5)),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              itemCount: _messages.length + (_busy ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= _messages.length) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: glassBase.withOpacity(.55),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                  color:
                                      BookNestColors.cyan.withOpacity(.2)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: BookNestColors.cyan),
                                ),
                                const SizedBox(width: 10),
                                Text('Jenny is reading…',
                                    style: TextStyle(
                                        color: theme.hintColor,
                                        fontSize: 13)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }
                final message = _messages[index];
                final isUser = message.role == 'user';
                final bubbleRadius = BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft:
                      Radius.circular(isUser ? 18 : 5),
                  bottomRight:
                      Radius.circular(isUser ? 5 : 18),
                );

                if (message.role == 'system') {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: Text(message.text,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: theme.hintColor, fontSize: 12.5)),
                      ),
                    ),
                  );
                }

                final bubble = Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 15, vertical: 11),
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * .76),
                  decoration: isUser
                      ? BoxDecoration(
                          gradient: const LinearGradient(colors: [
                            BookNestColors.cyanSoft,
                            BookNestColors.cyan,
                          ]),
                          borderRadius: bubbleRadius,
                        )
                      : BoxDecoration(
                          color: glassBase.withOpacity(.55),
                          borderRadius: bubbleRadius,
                          border: Border.all(
                              color: BookNestColors.cyan.withOpacity(.2)),
                        ),
                  child: Text(
                    message.text,
                    style: TextStyle(
                      color: isUser
                          ? BookNestColors.navyDeep
                          : theme.colorScheme.onSurface,
                      fontSize: 14.5,
                      height: 1.4,
                    ),
                  ),
                );

                final glassBubble = isUser
                    ? bubble
                    : ClipRRect(
                        borderRadius: bubbleRadius,
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                          child: bubble,
                        ),
                      );

                return Align(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: glassBubble,
                );
              },
            ),
          ),
          // ── glass composer bar ──
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(18, 4, 8, 4),
                    decoration: BoxDecoration(
                      color: glassBase.withOpacity(.62),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                          color: BookNestColors.cyan.withOpacity(.25)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontSize: 14.5),
                            decoration: InputDecoration(
                              hintText: 'Ask Jenny anything…',
                              hintStyle:
                                  TextStyle(color: theme.hintColor),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _busy ? null : _send,
                          style: IconButton.styleFrom(
                            backgroundColor: BookNestColors.cyan,
                          ),
                          icon: const Icon(Icons.send_rounded,
                              size: 19, color: BookNestColors.navyDeep),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
