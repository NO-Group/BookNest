import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Pagination engine for the Reader: slices a flowing chapter into
/// viewport-fitting pages by measuring real text with [TextPainter].
/// Works on the plain-paragraph pipeline (markdown is pre-flattened for
/// pagination) — headings, paragraphs and block quotes keep their styles.
class Paragraph {
  const Paragraph({
    required this.text,
    this.isHeading = false,
    this.isSubheading = false,
  });

  final String text;
  final bool isHeading;
  final bool isSubheading;
}

class ReaderPaginator {
  ReaderPaginator._();

  /// Flattens raw markdown into styled paragraphs for pagination. Handles
  /// the constructs authors actually write: headings, quotes, lists,
  /// rules — everything else flows as body text.
  static List<Paragraph> parse(String markdown) {
    final paragraphs = <Paragraph>[];
    var buffer = <String>[];
    // Markdown hard breaks (two trailing spaces or a trailing backslash)
    // keep verse lines on their own lines instead of reflowing them.
    var breakAfter = <bool>[];
    void flush() {
      if (buffer.isEmpty) return;
      final out = StringBuffer();
      for (var i = 0; i < buffer.length; i++) {
        if (i > 0) out.write(breakAfter[i - 1] ? '\n' : ' ');
        out.write(buffer[i]);
      }
      paragraphs.add(Paragraph(text: out.toString().trim()));
      buffer = [];
      breakAfter = [];
    }

    for (final rawLine in markdown.split('\n')) {
      final hardBreak = rawLine.endsWith('  ') || rawLine.trimRight().endsWith('\\');
      var line = rawLine.trim();
      if (line.endsWith('\\')) line = line.substring(0, line.length - 1).trimRight();
      if (line.isEmpty) {
        flush();
        continue;
      }
      if (line.startsWith('# ')) {
        flush();
        paragraphs.add(Paragraph(text: line.substring(2).trim(), isHeading: true));
      } else if (line.startsWith('## ') || line.startsWith('### ')) {
        flush();
        paragraphs.add(Paragraph(
            text: line.substring(line.indexOf(' ') + 1).trim(),
            isSubheading: true));
      } else if (line.startsWith('> ')) {
        flush();
        paragraphs.add(Paragraph(text: line.substring(2).trim()));
      } else if (line == '---' || line == '***') {
        flush();
        paragraphs.add(const Paragraph(text: '⁂', isSubheading: true));
      } else {
        buffer.add(line);
        breakAfter.add(hardBreak);
        // A long poem is split into page-sized stanzas so one paragraph
        // never outgrows a page.
        if (hardBreak && breakAfter.where((b) => b).length >= 12) flush();
      }
    }
    flush();
    return paragraphs;
  }

  /// Measures the paragraphs into pages that fit [viewport] (already
  /// inset by the reader's padding). Fonts must match the on-screen
  /// styles or pages will under/overflow.
  static List<List<Paragraph>> paginate({
    required List<Paragraph> paragraphs,
    required Size viewport,
    required TextStyle body,
    required TextStyle heading,
    required TextStyle subheading,
    required double lineHeight,
  }) {
    if (paragraphs.isEmpty) return const [];
    final pages = <List<Paragraph>>[];
    var current = <Paragraph>[];
    var used = 0.0;

    double measure(Paragraph p) {
      final style = p.isHeading
          ? heading
          : p.isSubheading
              ? subheading
              : body;
      final tp = TextPainter(
        text: TextSpan(text: p.text, style: style),
        textDirection: TextDirection.ltr,
        maxLines: null,
      )..layout(maxWidth: viewport.width);
      final height = tp.height;
      tp.dispose();
      return height + style.height! * lineHeight * 0.45;
    }

    for (final p in paragraphs) {
      final h = measure(p);
      if (used + h > viewport.height && current.isNotEmpty) {
        pages.add(current);
        current = <Paragraph>[];
        used = 0.0;
        if (h > viewport.height) {
          // A single oversized paragraph still gets its own page.
          pages.add([p]);
          continue;
        }
      }
      current.add(p);
      used += h;
    }
    if (current.isNotEmpty) pages.add(current);
    return pages;
  }

  static int words(String markdown) => markdown
      .split(RegExp(r'\s+'))
      .where((w) => w.trim().isNotEmpty)
      .length;

  /// Reading-time label at 220 wpm — the honest professional estimate.
  static String minutesLabel(int words) {
    final minutes = math.max(1, (words / 220).round());
    if (minutes < 60) return '~$minutes min read';
    return '~${(minutes / 60).toStringAsFixed(1)} hr read';
  }
}
