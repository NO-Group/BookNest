import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../config/theme.dart';
import '../../components/booknest_ui.dart';
import '../../../services/dictionary_service.dart';

/// Full page for one dictionary entry — opened from any Word Nest list,
/// chip, or lucky dip.
class WordDetailScreen extends StatelessWidget {
  final WordEntry entry;

  const WordDetailScreen({super.key, required this.entry});

  Future<void> _openSynonym(BuildContext context, String term) async {
    final found = await DictionaryService.instance.lookup(term);
    if (found != null && context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => WordDetailScreen(entry: found)),
      );
      return;
    }
    // Not in this edition as its own entry — search for it instead.
    if (context.mounted) {
      await context.push('/dictionary?q=${Uri.encodeComponent(term)}');
    }
  }

  void _share(BuildContext context) {
    final buffer = StringBuffer('${entry.word} (${entry.pos})\n');
    buffer.write(entry.definition);
    if (entry.example.isNotEmpty) buffer.write('\n\n"${entry.example}"');
    buffer.write('\n\n— from Word Nest in BookNest');
    Share.share(buffer.toString());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: GlassAppBar(
        title: 'Word Nest',
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: 'Share word',
            onPressed: () => _share(context),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Copy',
            onPressed: () {
              Clipboard.setData(ClipboardData(
                text: '${entry.word} — ${entry.definition}',
              ));
              HapticFeedback.selectionClick();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Word copied.')),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.word,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  entry.pos,
                  style: TextStyle(
                    color: BookNestColors.cyan,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Meaning',
                  style: TextStyle(
                    color: theme.hintColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  entry.definition,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 16,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          if (entry.example.isNotEmpty) ...[
            const SizedBox(height: 12),
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'In a sentence',
                    style: TextStyle(
                      color: theme.hintColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '"${entry.example}"',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 15,
                      height: 1.45,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (entry.synonyms.isNotEmpty) ...[
            const SizedBox(height: 12),
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Kindred words',
                    style: TextStyle(
                      color: theme.hintColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: entry.synonyms.map((syn) {
                      return GestureDetector(
                        onTap: () => _openSynonym(context, syn),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: BookNestColors.cyan.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: BookNestColors.cyan.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            syn,
                            style: const TextStyle(
                              fontSize: 13,
                              color: BookNestColors.cyan,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
