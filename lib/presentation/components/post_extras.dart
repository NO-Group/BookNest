import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../config/theme.dart';

/// Expandable post body — long stories collapse behind a "Read more"
/// control so the feed stays scannable, and expand fully on demand.
class ExpandableText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final int collapsedLines;

  const ExpandableText(
    this.text, {
    super.key,
    this.style,
    this.collapsedLines = 6,
  });

  bool get _isLong {
    if (text.length > 260) return true;
    return '\n'.allMatches(text).length >= collapsedLines;
  }

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final widget = this.widget;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          style: widget.style,
          maxLines: _expanded ? null : widget.collapsedLines,
          overflow: _expanded ? null : TextOverflow.ellipsis,
        ),
        if (widget._isLong)
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _expanded ? 'Show less' : 'Read more',
                    style: const TextStyle(
                      color: BookNestColors.cyan,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 17,
                    color: BookNestColors.cyan,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ── Link previews ────────────────────────────────────────────────────────────

class _LinkData {
  final String url;
  final String title;
  final String? description;
  final String? imageUrl;
  final String host;
  _LinkData({
    required this.url,
    required this.title,
    this.description,
    this.imageUrl,
    required this.host,
  });
}

final RegExp _urlPattern = RegExp(
  r'https?:\/\/[^\s<>"\)\]]+',
  caseSensitive: false,
);

final Map<String, Future<_LinkData?>> _linkCache = {};

/// Fetches and caches the OpenGraph preview for the first link in [text].
/// Degrades to a simple link chip when a site refuses to preview.
Future<_LinkData?> _fetchLink(String url) {
  return _linkCache.putIfAbsent(url, () async {
    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (compatible; BookNestBot/1.0; +https://booknest.app)',
          'Accept': 'text/html',
        },
      ).timeout(const Duration(seconds: 7));
      if (res.statusCode != 200 || res.bodyBytes.length > 3 * 1024 * 1024) {
        return _LinkData(
            url: url, title: url, host: Uri.parse(url).host);
      }
      final body = res.body;
      String? meta(String property) {
        final patterns = [
          RegExp(
            'property=["\']$property["\'][^>]*content=["\']([^"\']+)["\']',
            caseSensitive: false,
          ),
          RegExp(
            'content=["\']([^"\']+)["\'][^>]*property=["\']$property["\']',
            caseSensitive: false,
          ),
        ];
        for (final p in patterns) {
          final m = p.firstMatch(body);
          if (m != null) return _decode(m.group(1) ?? '');
        }
        return null;
      }

      String? decodeEntities(String? input) => input == null ? null : _decode(input);
      final title = decodeEntities(meta('og:title')) ??
          decodeEntities(meta('title')) ??
          _titleTag(body) ??
          url;
      final description = decodeEntities(meta('og:description')) ??
          decodeEntities(meta('description'));
      final image = decodeEntities(meta('og:image'));
      return _LinkData(
        url: url,
        title: title.trim().isEmpty ? url : title.trim(),
        description: description?.trim(),
        imageUrl: image,
        host: Uri.parse(url).host.replaceFirst('www.', ''),
      );
    } catch (_) {
      return _LinkData(url: url, title: url, host: Uri.parse(url).host);
    }
  });
}

String _decode(String input) => const HtmlEscape().convert(
      input
          .replaceAll('&amp;', '&')
          .replaceAll('&quot;', '"')
          .replaceAll('&#39;', "'")
          .replaceAll('&apos;', "'")
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&nbsp;', ' '),
    );

String? _titleTag(String body) {
  final m = RegExp(r'<title[^>]*>([^<]+)</title>', caseSensitive: false)
      .firstMatch(body);
  return m?.group(1)?.trim();
}

/// The link preview card shown beneath a post that contains a link:
/// picture, headline, excerpt and host — tap to open in the browser.
class LinkPreviewCard extends StatelessWidget {
  final String content;

  const LinkPreviewCard({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    final match = _urlPattern.firstMatch(content);
    if (match == null) return const SizedBox.shrink();
    final url = match.group(0)!;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    return FutureBuilder<_LinkData?>(
      future: _fetchLink(url),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return const SizedBox(
            height: 44,
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: BookNestColors.cyan),
              ),
            ),
          );
        }
        return GestureDetector(
          onTap: () {
            launchUrl(Uri.parse(data.url), mode: LaunchMode.externalApplication);
          },
          child: Container(
            margin: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              color: dark ? Colors.white.withOpacity(.04) : BookNestColors.lightSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: BookNestColors.cyan.withOpacity(.28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data.imageUrl != null)
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(13)),
                    child: Image.network(
                      data.imageUrl!,
                      width: double.infinity,
                      height: 148,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.host.toUpperCase(),
                        style: const TextStyle(
                          color: BookNestColors.cyan,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        data.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: dark
                              ? BookNestColors.darkTextPrimary
                              : BookNestColors.navyDeep,
                        ),
                      ),
                      if (data.description != null &&
                          data.description!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          data.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: theme.hintColor),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.open_in_new_rounded,
                              size: 12, color: BookNestColors.cyan),
                          const SizedBox(width: 5),
                          Text(
                            'Open link',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: BookNestColors.cyan.withOpacity(.9),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
