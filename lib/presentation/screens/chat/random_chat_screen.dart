import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../components/booknest_ui.dart';

/// Random Chat — tap join, get paired with another reader who's waiting,
/// and land straight in a normal BookNest chat. Everything the app already
/// enforces in chats (blocking, reporting, deletion, retention) applies.
class RandomChatScreen extends StatefulWidget {
  const RandomChatScreen({super.key});

  @override
  State<RandomChatScreen> createState() => _RandomChatScreenState();
}

class _RandomChatScreenState extends State<RandomChatScreen> {
  static const List<String> _hints = [
    'Finding a reader…',
    'Someone, somewhere, is opening BookNest right now…',
    'Pausing on your shelf… scanning the queue…',
    'A reader just turned a page. Maybe them…',
    'Almost there — saying hello is the hard part.',
  ];

  Timer? _poll;
  Timer? _hintCycle;
  bool _leaving = false;
  int _hintIndex = 0;

  @override
  void initState() {
    super.initState();
    _join();
    _hintCycle = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) setState(() => _hintIndex = (_hintIndex + 1) % _hints.length);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _hintCycle?.cancel();
    // Still queued when the reader backs out? Leave quietly.
    if (!_leaving) {
      unawaited(BackendApi.instance.randomLeave());
    }
    super.dispose();
  }

  Future<void> _join() async {
    final res = await BackendApi.instance.randomJoin();
    if (!mounted) return;
    if (res == null) {
      _oops('Random chat is resting right now — try again in a moment.');
      return;
    }
    if (res['matched'] == true) {
      _enter(res);
      return;
    }
    // Waiting for a partner — poll politely.
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
  }

  Future<void> _check() async {
    final res = await BackendApi.instance.randomStatus();
    if (!mounted || res == null) return;
    if (res['matched'] == true) _enter(res);
  }

  void _enter(Map<String, dynamic> res) {
    if (!mounted) return;
    _poll?.cancel();
    final conversation = res['conversation'];
    if (conversation is! Map) {
      _oops('The pairing dissolved — try once more.');
      return;
    }
    final id = conversation['id']?.toString() ?? '';
    final peerId = conversation['peerId']?.toString() ?? '';
    if (id.isEmpty) {
      _oops('The pairing dissolved — try once more.');
      return;
    }
    _leaving = true; // matched — the room belongs to us now.
    context.pushReplacement('/chat/$id?peer=$peerId');
  }

  Future<void> _cancel() async {
    _poll?.cancel();
    setState(() => _leaving = true);
    unawaited(BackendApi.instance.randomLeave());
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _oops(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          dark ? BookNestColors.navyDeep : BookNestColors.lightSurface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Random chat',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Orbiting-books mark: breathing cyan ring while searching.
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(seconds: 3),
                curve: Curves.easeInOut,
                builder: (context, t, child) {
                  return Transform.scale(
                    scale: 1 + 0.06 * (1 - (2 * t - 1).abs()),
                    child: child,
                  );
                },
                child: Container(
                  width: 132,
                  height: 132,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [
                      BookNestColors.cyan.withOpacity(.22),
                      BookNestColors.cyan.withOpacity(.05),
                    ]),
                    border: Border.all(color: BookNestColors.cyan, width: 3),
                  ),
                  child: const Icon(Icons.shuffle_rounded,
                      size: 54, color: BookNestColors.cyan),
                ),
              ),
              const SizedBox(height: 26),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 450),
                child: Text(
                  _hints[_hintIndex],
                  key: ValueKey(_hintIndex),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                    color: dark ? Colors.white : BookNestColors.navyDeep,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'You will be paired with one random reader for a '
                'one-to-one chat. Be kind — the same rules apply as '
                'everywhere in BookNest.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: Theme.of(context).hintColor,
                ),
              ),
              const SizedBox(height: 30),
              GradientButton(
                label: 'Stop searching',
                icon: Icons.close_rounded,
                onPressed: _cancel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
