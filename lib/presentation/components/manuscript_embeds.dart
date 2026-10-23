import 'dart:convert' as convert;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../config/theme.dart';

/// BookNest manuscript embeds: pictures and dividers live inside chapters
/// as first-class content (Quill custom block embeds), stored in the
/// chapter's Delta document — no markdown anywhere.

/// A picture inside a chapter. Stored as `{"insert": {"image": "<url>"}}`.
class ImageBlockEmbed extends CustomBlockEmbed {
  const ImageBlockEmbed(String url) : super(imageType, url);

  static const String imageType = 'image';

  String get url => data as String;
}

/// A horizontal rule inside a chapter (`{"insert": {"hr": "hr"}}`).
class DividerBlockEmbed extends CustomBlockEmbed {
  const DividerBlockEmbed() : super(hrType, 'hr');

  static const String hrType = 'hr';
}

/// Renders chapter pictures: rounded, full-width, tap to zoom.
class ImageEmbedBuilder extends EmbedBuilder {
  @override
  String get key => ImageBlockEmbed.imageType;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final value = embedContext.node.value;
    final url = value.data is String ? value.data as String : '';
    if (!url.startsWith('http')) return const SizedBox.shrink();
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          barrierColor: Colors.black.withOpacity(.92),
          builder: (_) => Dialog.fullscreen(
            backgroundColor: Colors.black,
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    maxScale: 4,
                    child: Image.network(url, fit: BoxFit.contain),
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: IconButton.filled(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(.12),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(
              url,
              width: double.infinity,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
                  height: 180,
                  color: BookNestColors.cyan.withOpacity(.06),
                  child: const Center(
                    child: CircularProgressIndicator(
                        color: BookNestColors.cyan, strokeWidth: 2),
                  ),
                );
              },
              errorBuilder: (_, __, ___) => Container(
                height: 120,
                color: BookNestColors.cyan.withOpacity(.06),
                child: const Icon(Icons.broken_image_outlined,
                    color: BookNestColors.cyan),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders the horizontal rule embed.
class DividerEmbedBuilder extends EmbedBuilder {
  @override
  String get key => DividerBlockEmbed.hrType;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Divider(color: BookNestColors.cyan, thickness: 1.2, height: 1.2),
    );
  }
}

/// A formula inside a chapter. Stored as
/// `{"insert": {"math": {"tex": "x^2 + y^2 = z^2"}}}` — real TeX, so it
/// renders beautifully in the reader and stays editable forever.
class MathBlockEmbed extends CustomBlockEmbed {
  /// Quill embeds carry a string payload — the TeX rides as JSON.
  MathBlockEmbed(String tex)
      : super(mathType, convert.jsonEncode(<String, dynamic>{'tex': tex}));

  static const String mathType = 'math';

  String get tex {
    final d = data;
    if (d is String) {
      try {
        final decoded = convert.jsonDecode(d);
        if (decoded is Map && decoded['tex'] != null) {
          return decoded['tex'].toString();
        }
      } catch (_) {}
      return d; // raw TeX written directly into the payload
    }
    return '';
  }
}

/// One rendered formula. In the editor it is tappable to edit; in the
/// reader it is pure ink.
class MathEmbedBuilder extends EmbedBuilder {
  @override
  String get key => MathBlockEmbed.mathType;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    String tex = '';
    final d = embedContext.node.value.data;
    if (d is String) {
      try {
        final decoded = convert.jsonDecode(d);
        if (decoded is Map && decoded['tex'] != null) {
          tex = decoded['tex'].toString();
        }
      } catch (_) {
        tex = d; // raw TeX payload
      }
    }
    return MathFormulaView(
      tex: tex,
      editable: !embedContext.readOnly,
      color: embedContext.textStyle.color,
      fontSize: embedContext.textStyle.fontSize,
      onTap: embedContext.readOnly
          ? null
          : () async {
              final next =
                  await askFormula(context, initial: tex);
              if (next == null) return;
              final controller = embedContext.controller;
              final at = embedContext.node.offset;
              if (next.trim().isEmpty) {
                controller.replaceText(at, 1, '',
                    TextSelection.collapsed(offset: at));
              } else {
                controller.replaceText(at, 1, MathBlockEmbed(next),
                    TextSelection.collapsed(offset: at + 1));
              }
            },
    );
  }
}

/// The rendered formula itself — used by the editor, the preview and the
/// reader. Invalid TeX degrades to a readable marker, never a crash.
class MathFormulaView extends StatelessWidget {
  final String tex;
  final bool editable;
  final Color? color;
  final double? fontSize;
  final VoidCallback? onTap;

  const MathFormulaView({
    super.key,
    required this.tex,
    this.editable = false,
    this.color,
    this.fontSize,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (tex.trim().isEmpty) {
      if (!editable) return const SizedBox.shrink();
      return _chip(
        context,
        child: Row(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.functions_rounded, size: 15, color: BookNestColors.cyan),
          SizedBox(width: 6),
          Text('Add formula',
              style: TextStyle(
                  fontSize: 12.5,
                  color: BookNestColors.cyan,
                  fontWeight: FontWeight.w700)),
        ]),
      );
    }
    final rendered = Math.tex(
      tex,
      textStyle: (fontSize != null || color != null)
          ? TextStyle(fontSize: fontSize ?? 16, color: color)
          : null,
      onErrorFallback: (error) => Text(
        'Math: $tex',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: 13, fontStyle: FontStyle.italic, color: color),
      ),
    );
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: rendered,
    );
    if (!editable || onTap == null) return body;
    return _chip(context, child: body);
  }

  Widget _chip(BuildContext context, {required Widget child}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: (dark ? Colors.white : BookNestColors.navy).withOpacity(.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: BookNestColors.cyan.withOpacity(.35)),
        ),
        child: child,
      ),
    );
  }
}

/// Ask for a formula: a TeX box with a LIVE preview and honest hints.
/// Returns the new TeX (empty string = remove), or null for cancel.
Future<String?> askFormula(BuildContext context, {String initial = ''}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: const [
        Icon(Icons.functions_rounded, color: BookNestColors.cyan, size: 20),
        SizedBox(width: 8),
        Text('Formula', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ]),
      content: StatefulBuilder(
        builder: (dialogContext, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
              decoration: const InputDecoration(
hintText: r'x^2 + \frac{a}{b} \sum_{i=1}^{n} i \sqrt{2}',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setDialogState(() {}),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: BookNestColors.cyan.withOpacity(.07),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: controller.text.trim().isEmpty
                  ? Text('Live preview',
                      style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Theme.of(dialogContext).hintColor))
                  : MathFormulaView(
                      tex: controller.text,
                      editable: false,
                    ),
            ),
          ],
        ),
      ),
      actions: [
        if (initial.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, ''),
            child: const Text('Remove',
                style: TextStyle(color: Colors.redAccent)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: BookNestColors.cyan),
          onPressed: () =>
              Navigator.pop(dialogContext, controller.text.trim()),
          child: Text(initial.isEmpty ? 'Insert' : 'Save',
              style: const TextStyle(
                  color: BookNestColors.navy, fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
}

/// Markdown with real math: `$$…$$` blocks and inline `$…$` render as
/// typeset formulas; everything else stays standard markdown. Legacy
/// markdown chapters keep full math support this way.
class MathAwareMarkdown extends StatelessWidget {
  final String data;
  final MarkdownStyleSheet styleSheet;

  const MathAwareMarkdown({
    super.key,
    required this.data,
    required this.styleSheet,
  });

  static final RegExp _blockMath = RegExp(r'\$\$([\s\S]+?)\$\$');
  static final RegExp _inlineMath = RegExp(r'\$([^\$\n]{1,200}?)\$');

  bool _looksLikeMath(String candidate) {
    final t = candidate.trim();
    if (t.isEmpty || t.startsWith(' ') || t.endsWith(' ')) return false;
    // Currency amounts ("$5", "$5.99") are not formulas.
    if (RegExp(r'^\d+([.,]\d+)?$').hasMatch(t)) return false;
    return true;
  }

  List<Widget> segments(String text, bool isBlock) {
    final pattern = isBlock ? _blockMath : _inlineMath;
    final out = <Widget>[];
    var cursor = 0;
    for (final match in pattern.allMatches(text)) {
      final candidate = match.group(1) ?? '';
      if (!_looksLikeMath(candidate)) continue;
      if (match.start > cursor) {
        out.add(MarkdownBody(
          data: text.substring(cursor, match.start),
          selectable: true,
          styleSheet: styleSheet,
        ));
      }
      out.add(Padding(
        padding: EdgeInsets.symmetric(vertical: isBlock ? 6 : 0),
        child: MathFormulaView(tex: candidate),
      ));
      cursor = match.end;
    }
    if (cursor < text.length) {
      out.add(MarkdownBody(
        data: text.substring(cursor),
        selectable: true,
        styleSheet: styleSheet,
      ));
    }
    if (out.isEmpty) {
      out.add(MarkdownBody(data: text, selectable: true, styleSheet: styleSheet));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    // Pass 1: block math splits the document; pass 2: inline math inside
    // the surviving markdown stretches.
    final chunks = <Widget>[];
    var last = 0;
    for (final m in _blockMath.allMatches(data)) {
      final candidate = m.group(1) ?? '';
      if (!_looksLikeMath(candidate)) continue;
      if (m.start > last) chunks.addAll(segments(data.substring(last, m.start), false));
      chunks.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: MathFormulaView(tex: candidate),
      ));
      last = m.end;
    }
    if (last < data.length) chunks.addAll(segments(data.substring(last), false));
    if (chunks.isEmpty) {
      chunks.add(MarkdownBody(data: data, selectable: true, styleSheet: styleSheet));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: chunks,
    );
  }
}

/// Fallback for anything the editor doesn't know (older/foreign content).
/// Without it Quill throws and release builds paint the whole page grey.
class UnknownEmbedBuilder extends EmbedBuilder {
  const UnknownEmbedBuilder();

  @override
  String get key => '__unknown__';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    return const SizedBox(height: 4);
  }
}

const EmbedBuilder manuscriptUnknownEmbedBuilder = UnknownEmbedBuilder();

/// Everything a manuscript needs, registered in one line.
final List<EmbedBuilder> manuscriptEmbedBuilders = [
  ImageEmbedBuilder(),
  DividerEmbedBuilder(),
  MathEmbedBuilder(),
];

/// True when [content] is a stored Quill Delta document (the rich-text
/// format). Legacy chapters were stored as markdown — those fall back.
bool isQuillDelta(String content) {
  final trimmed = content.trim();
  if (!trimmed.startsWith('[{')) return false;
  try {
    final decoded = convert.jsonDecode(trimmed);
    return decoded is List &&
        decoded.isNotEmpty &&
        decoded.first is Map &&
        (decoded.first as Map).containsKey('insert');
  } catch (_) {
    return false;
  }
}
