import 'dart:convert' as convert;

import 'package:flutter/material.dart';
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

/// Everything a manuscript needs, registered in one line.
final List<EmbedBuilder> manuscriptEmbedBuilders = [
  ImageEmbedBuilder(),
  DividerEmbedBuilder(),
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
