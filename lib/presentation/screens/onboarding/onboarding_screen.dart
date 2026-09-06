import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../components/booknest_ui.dart';

/// First-run genre picker — personalizes the library. Best-effort sync to
/// the cloud (no-op until the edge function is deployed); always proceeds.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              BookNestColors.navyDeep.withOpacity(.16),
              theme.scaffoldBackgroundColor,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: const LinearGradient(
                              colors: [
                                BookNestColors.cyan,
                                BookNestColors.cyanSoft
                              ],
                            ),
                          ),
                          child: const Icon(Icons.auto_stories_rounded,
                              color: BookNestColors.navyDeep),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => context.go('/feed'),
                          child: Text('Skip',
                              style: TextStyle(color: theme.hintColor)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text('What do you love to read?',
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(
                      'Pick a few genres — we\'ll shape your library around them. '
                      'You can change these anytime.',
                      style: TextStyle(
                          color: theme.hintColor, height: 1.4),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Wrap(
                    spacing: 9,
                    runSpacing: 9,
                    children: kBookNestGenres
                        .map((genre) => TagChip(
                              label: genre,
                              selected: _selected.contains(genre),
                              onTap: () => setState(() {
                                _selected.contains(genre)
                                    ? _selected.remove(genre)
                                    : _selected.add(genre);
                              }),
                            ))
                        .toList(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 26),
                child: GradientButton(
                  label: _selected.isEmpty
                      ? 'Continue'
                      : 'Continue with ${_selected.length} genre${_selected.length == 1 ? '' : 's'}',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () async {
                    if (_selected.isNotEmpty) {
                      // Fire-and-forget: personalization syncs when cloud is up.
                      BackendApi.instance.savePreferences(_selected.toList());
                    }
                    if (!context.mounted) return;
                    context.go('/feed');
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
