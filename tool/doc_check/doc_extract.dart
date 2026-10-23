// BookNest's universal document reader.
//
// Turns the bytes of (almost) any document into something the in-app
// viewer can show: headings, paragraphs with bold/italic, bullet lists,
// tables, pictures, pages (slides, sheets, chapters) — or, for archives,
// the list of files inside. Pure Dart (no Flutter) so it runs in a
// background isolate and is unit-tested in CI (tool/doc_check).
//
// Understood formats
//   Word        .docx .docm .dotx · .doc (Word 97-2003) · .odt · .rtf
//   Spreadsheet .xlsx .xlsm · .xls (Excel 97-2003) · .ods · .csv .tsv
//   Slides      .pptx .ppsx · .ppt (PowerPoint 97-2003) · .odp
//   E-books     .epub · .mobi .azw .prc (PalmDOC) · .fb2
//   Web/text    .html .htm .xhtml .xml .json .txt .md .log, code, any text
//   Other       .xps .oxps · Apple Pages/Numbers/Keynote (built-in preview)
//               · Outlook .msg · .eml
//   Archives    .zip .jar .apk .epub-like zips · .tar · .gz .tgz
// Anything else still opens: the readable text inside the file is shown.
//
// PDFs, pictures, audio and video are recognised by [sniffKind] and shown
// by their own players in the viewer.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

// ── Result model ─────────────────────────────────────────────────────────────

class DocSpan {
  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  const DocSpan(this.text,
      {this.bold = false, this.italic = false, this.underline = false});
}

enum DocBlockType { heading, paragraph, bullet, table, image, code, divider }

class DocBlock {
  final DocBlockType type;

  /// Heading level 1-6 · list depth for bullets.
  final int level;
  final List<DocSpan> spans;
  final List<List<String>> rows;
  final Uint8List? image;

  const DocBlock(this.type,
      {this.level = 1,
      this.spans = const [],
      this.rows = const [],
      this.image});

  factory DocBlock.text(DocBlockType type, String text, {int level = 1}) =>
      DocBlock(type, level: level, spans: [DocSpan(text)]);

  String get text => spans.map((s) => s.text).join();
}

class DocPage {
  final String title;
  final List<DocBlock> blocks;

  /// Sheets render as one big grid instead of flowing blocks.
  final bool isSheet;
  const DocPage(this.title, this.blocks, {this.isSheet = false});
}

class ArchiveEntryInfo {
  final String name;
  final int size;
  const ArchiveEntryInfo(this.name, this.size);
}

class ExtractedDoc {
  /// Human label: "Word document", "Spreadsheet", "Slides"…
  final String format;
  final List<DocPage> pages;
  final String? note;
  final List<ArchiveEntryInfo> entries;
  final Uint8List? previewPdf;
  final Uint8List? previewImage;

  /// Plain text / code: monospace, no reflow.
  final bool monospace;
  final String? title;

  const ExtractedDoc({
    required this.format,
    this.pages = const [],
    this.note,
    this.entries = const [],
    this.previewPdf,
    this.previewImage,
    this.monospace = false,
    this.title,
  });

  bool get isEmpty =>
      note == null &&
      entries.isEmpty &&
      previewPdf == null &&
      previewImage == null &&
      pages.every((p) => p.blocks.isEmpty);
}

// ── Kinds ────────────────────────────────────────────────────────────────────

const _videoExt = {
  'mp4', 'm4v', 'mov', 'webm', 'mkv', '3gp', '3g2', 'avi', 'flv', 'wmv',
  'mpg', 'mpeg', 'ts', 'ogv',
};
const _audioExt = {
  'mp3', 'm4a', 'aac', 'wav', 'ogg', 'oga', 'opus', 'flac', 'amr', 'wma',
  'weba', 'mka', 'aiff', 'aif', 'caf', 'mid', 'midi',
};
const _imageExt = {
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif', 'ico', 'avif',
  'wbmp',
};
const _codeExt = {
  'txt', 'log', 'ini', 'cfg', 'conf', 'yaml', 'yml', 'toml', 'xml', 'kt',
  'java', 'dart', 'js', 'mjs', 'ts', 'tsx', 'jsx', 'py', 'rb', 'go', 'c', 'h',
  'cpp', 'hpp', 'cs', 'swift', 'php', 'css', 'scss', 'sh', 'bat', 'ps1',
  'sql', 'gradle', 'properties', 'srt', 'vtt', 'tex', 'ics', 'vcf', 'diff',
  'patch', 'rs', 'lua', 'r', 'pl', 'env',
};

/// What the viewer should use for these bytes: 'pdf', 'image', 'svg',
/// 'video', 'audio', 'markdown' or 'document' (everything [extractDocument]
/// handles, including unknown files).
String sniffKind(Uint8List b, String ext) {
  ext = ext.toLowerCase();
  bool at(int o, List<int> sig) {
    if (b.length < o + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (b[o + i] != sig[i]) return false;
    }
    return true;
  }

  bool ascii(int o, String s) => at(o, s.codeUnits);
  final head = String.fromCharCodes(b.take(1024).map((c) => c < 128 ? c : 32));

  if (head.contains('%PDF-')) return 'pdf';
  if (at(0, [0x89, 0x50, 0x4E, 0x47]) ||
      at(0, [0xFF, 0xD8, 0xFF]) ||
      ascii(0, 'GIF8') ||
      (ascii(0, 'RIFF') && ascii(8, 'WEBP'))) {
    return 'image';
  }
  if (ascii(0, 'BM') && ext == 'bmp') return 'image';
  if (at(0, [0, 0, 1, 0]) && ext == 'ico') return 'image';
  if (ascii(4, 'ftyp')) {
    final brand = b.length >= 12 ? String.fromCharCodes(b.sublist(8, 12)) : '';
    if (const {'heic', 'heix', 'mif1', 'msf1', 'avif', 'hevc'}.contains(brand)) {
      return 'image';
    }
    if (brand.startsWith('M4A') || brand.startsWith('M4B') || _audioExt.contains(ext)) {
      return 'audio';
    }
    return 'video';
  }
  if (ascii(0, 'RIFF') && ascii(8, 'WAVE')) return 'audio';
  if (ascii(0, 'RIFF') && ascii(8, 'AVI ')) return 'video';
  if (ascii(0, 'ID3') || ascii(0, 'fLaC') || ascii(0, '#!AMR') ||
      ascii(0, 'FORM') && ascii(8, 'AIFF')) {
    return 'audio';
  }
  if (ascii(0, 'OggS')) return ext == 'ogv' ? 'video' : 'audio';
  if (at(0, [0x1A, 0x45, 0xDF, 0xA3])) {
    return (ext == 'weba' || ext == 'mka') ? 'audio' : 'video';
  }
  if (ascii(0, 'FLV')) return 'video';
  if (b.length > 2 && b[0] == 0xFF && (b[1] & 0xE0) == 0xE0 && _audioExt.contains(ext)) {
    return 'audio';
  }
  final lowerHead = head.toLowerCase();
  if (ext == 'svg' || (lowerHead.contains('<svg') && !lowerHead.contains('<html'))) {
    return 'svg';
  }
  if (ext == 'md' || ext == 'markdown') return 'markdown';
  // Containers we read ourselves come before the extension guesses.
  if (ascii(0, 'PK') || at(0, [0xD0, 0xCF, 0x11, 0xE0]) || at(0, [0x1F, 0x8B])) {
    return 'document';
  }
  if (_videoExt.contains(ext)) return 'video';
  if (_audioExt.contains(ext)) return 'audio';
  if (_imageExt.contains(ext)) return 'image';
  return 'document';
}

bool isVideoExtension(String ext) => _videoExt.contains(ext.toLowerCase());
bool isAudioExtension(String ext) => _audioExt.contains(ext.toLowerCase());
bool isImageExtension(String ext) => _imageExt.contains(ext.toLowerCase());

// ── Entry points ─────────────────────────────────────────────────────────────

/// For `compute()`: {'bytes': Uint8List, 'ext': String}.
ExtractedDoc extractDocumentFromMap(Map<String, Object?> m) =>
    extractDocument(m['bytes'] as Uint8List, (m['ext'] as String?) ?? '');

/// For `compute()`: {'bytes', 'ext', 'name'} → the bytes of one archive entry.
Uint8List? archiveEntryFromMap(Map<String, Object?> m) => archiveEntryBytes(
    m['bytes'] as Uint8List, (m['ext'] as String?) ?? '', m['name'] as String);

/// Never throws: on any parsing trouble the readable text is returned.
ExtractedDoc extractDocument(Uint8List bytes, String ext) {
  ext = ext.toLowerCase();
  try {
    final doc = _extract(bytes, ext);
    if (!doc.isEmpty) return doc;
  } catch (_) {}
  return _fallbackText(bytes, ext);
}

Uint8List? archiveEntryBytes(Uint8List bytes, String ext, String name) {
  try {
    final archive = _openArchive(bytes, ext);
    if (archive == null) return null;
    for (final f in archive.files) {
      if (f.name == name && f.isFile) return _bytesOf(f);
    }
  } catch (_) {}
  return null;
}

ExtractedDoc _extract(Uint8List b, String ext) {
  bool ascii(int o, String s) {
    if (b.length < o + s.length) return false;
    for (var i = 0; i < s.length; i++) {
      if (b[o + i] != s.codeUnitAt(i)) return false;
    }
    return true;
  }

  if (b.length >= 4 && b[0] == 0x50 && b[1] == 0x4B) return _fromZip(b, ext);
  if (b.length >= 8 && b[0] == 0xD0 && b[1] == 0xCF && b[2] == 0x11 && b[3] == 0xE0) {
    return _fromOle(b, ext);
  }
  if (b.length >= 2 && b[0] == 0x1F && b[1] == 0x8B) return _fromGzip(b, ext);
  if (ascii(257, 'ustar')) return _archiveListing(TarDecoder().decodeBytes(b), 'Archive (.tar)');
  if (ascii(0, '{\\rtf')) return _rtf(b);
  if (ascii(60, 'BOOKMOBI') || ascii(60, 'TEXtREAd')) return _mobi(b);

  final text = _decodeText(b);
  final probe = text.length > 2000 ? text.substring(0, 2000) : text;
  final lower = probe.toLowerCase();
  if (ext == 'fb2' || probe.contains('<FictionBook')) {
    return _htmlDoc(text, format: 'E-book (FB2)', fb2: true);
  }
  if (const {'html', 'htm', 'xhtml', 'mht', 'mhtml'}.contains(ext) ||
      lower.contains('<!doctype html') ||
      lower.contains('<html')) {
    return _htmlDoc(text, format: 'Web page');
  }
  if (ext == 'csv' || ext == 'tsv') return _csv(text, ext == 'tsv' ? '\t' : null);
  if (ext == 'json' || ext == 'geojson' || ext == 'ipynb') {
    try {
      final pretty = const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
      return _plain(pretty, 'JSON', monospace: true);
    } catch (_) {}
  }
  if (ext == 'eml') return _plain(text, 'E-mail', monospace: false);
  if (_printable(text)) {
    return _plain(text, _codeExt.contains(ext) ? '${ext.toUpperCase()} file' : 'Text',
        monospace: _codeExt.contains(ext) && ext != 'txt');
  }
  return _fallbackText(b, ext);
}

// ── Text helpers ─────────────────────────────────────────────────────────────

String _decodeText(Uint8List b) {
  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
    return utf8.decode(b.sublist(3), allowMalformed: true);
  }
  if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) return _utf16(b, 2, b.length, little: true);
  if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) return _utf16(b, 2, b.length, little: false);
  try {
    return utf8.decode(b);
  } catch (_) {
    return _cp1252(b, 0, b.length);
  }
}

String _utf16(Uint8List b, int start, int end, {bool little = true}) {
  final units = <int>[];
  for (var i = start; i + 1 < end && i + 1 < b.length; i += 2) {
    units.add(little ? (b[i] | (b[i + 1] << 8)) : ((b[i] << 8) | b[i + 1]));
  }
  return String.fromCharCodes(units);
}

const _cp1252High = [
  0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030,
  0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F, 0x90, 0x2018, 0x2019, 0x201C,
  0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D,
  0x017E, 0x0178,
];

String _cp1252(Uint8List b, int start, int end) {
  final out = StringBuffer();
  for (var i = start; i < end && i < b.length; i++) {
    final c = b[i];
    out.writeCharCode(c >= 0x80 && c < 0xA0 ? _cp1252High[c - 0x80] : c);
  }
  return out.toString();
}

bool _printable(String s) {
  if (s.isEmpty) return true;
  final sample = s.length > 4000 ? s.substring(0, 4000) : s;
  var bad = 0;
  for (final c in sample.codeUnits) {
    if (c == 0xFFFD || (c < 32 && c != 9 && c != 10 && c != 13 && c != 12)) bad++;
  }
  return bad <= sample.length * 0.05;
}

ExtractedDoc _plain(String text, String format, {bool monospace = false}) {
  const maxChars = 3 * 1024 * 1024;
  var note = '';
  if (text.length > maxChars) {
    text = text.substring(0, maxChars);
    note = 'Showing the first 3 MB of text.';
  }
  final blocks = <DocBlock>[];
  if (monospace) {
    // Chunks of ~60 lines keep huge files scrolling smoothly.
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    for (var i = 0; i < lines.length; i += 60) {
      blocks.add(DocBlock.text(DocBlockType.code,
          lines.sublist(i, i + 60 > lines.length ? lines.length : i + 60).join('\n')));
    }
  } else {
    for (final para in text.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n'))) {
      final t = para.trimRight();
      if (t.trim().isNotEmpty) blocks.add(DocBlock.text(DocBlockType.paragraph, t));
    }
  }
  return ExtractedDoc(
      format: format,
      pages: [DocPage('', blocks)],
      monospace: monospace,
      note: note.isEmpty ? null : note);
}

/// Last resort for any file: every readable run of text inside it.
ExtractedDoc _fallbackText(Uint8List b, String ext) {
  final decoded = _decodeText(b);
  if (decoded.trim().isNotEmpty && _printable(decoded)) {
    return _plain(decoded, ext.isEmpty ? 'Text' : '${ext.toUpperCase()} file');
  }
  final runs = _strings(b);
  final label = ext.isEmpty ? 'This file' : '.${ext.toUpperCase()}';
  return ExtractedDoc(
    format: ext.isEmpty ? 'File' : '${ext.toUpperCase()} file',
    pages: [
      DocPage('', [
        for (final r in runs) DocBlock.text(DocBlockType.paragraph, r),
      ])
    ],
    note: runs.isEmpty
        ? '$label has no readable text — it is a binary file. Use Save / share to keep it.'
        : 'No page layout for $label — here is the readable text found inside.',
  );
}

List<String> _strings(Uint8List b) {
  final out = <String>[];
  var total = 0;
  bool good(int c) => (c >= 0x20 && c < 0x7F) || c == 9 || (c >= 0xA0 && c <= 0xFF);
  // 8-bit runs
  var start = -1;
  for (var i = 0; i <= b.length; i++) {
    final ok = i < b.length && good(b[i]);
    if (ok && start < 0) start = i;
    if (!ok && start >= 0) {
      if (i - start >= 6) {
        final s = _cp1252(b, start, i).trim();
        if (RegExp(r'[A-Za-z]{3}').hasMatch(s)) {
          out.add(s);
          total += s.length;
        }
      }
      start = -1;
    }
    if (out.length > 4000 || total > 400000) return out;
  }
  // UTF-16LE runs
  start = -1;
  for (var i = 0; i + 1 <= b.length; i += 2) {
    final ok = i + 1 < b.length && b[i + 1] == 0 && good(b[i]);
    if (ok && start < 0) start = i;
    if (!ok && start >= 0) {
      if ((i - start) ~/ 2 >= 6) {
        final s = _utf16(b, start, i).trim();
        if (RegExp(r'[A-Za-z]{3}').hasMatch(s)) out.add(s);
      }
      start = -1;
    }
    if (out.length > 6000) break;
  }
  return out;
}

// ── A small tolerant XML/HTML tokenizer ──────────────────────────────────────

const int _tStart = 0, _tEnd = 1, _tText = 2;

class _Tok {
  final int kind;
  final String name; // qualified, as written (HTML callers lowercase it)
  final Map<String, String> attrs;
  final bool selfClose;
  final String text;
  const _Tok(this.kind, this.name, this.attrs, this.selfClose, this.text);

  String? attr(String key) {
    final v = attrs[key];
    if (v != null) return v;
    // Accept any prefix: "r:embed" matches "embed".
    for (final e in attrs.entries) {
      final k = e.key;
      final colon = k.indexOf(':');
      if ((colon >= 0 ? k.substring(colon + 1) : k) == key) return e.value;
    }
    return null;
  }

  String get local {
    final colon = name.indexOf(':');
    return colon >= 0 ? name.substring(colon + 1) : name;
  }
}

final _attrRe = RegExp(r'''([^\s=/]+)\s*=\s*("([^"]*)"|'([^']*)'|([^\s"'>]+))''');
final _nameRe = RegExp(r'[A-Za-z_][\w:.\-]*');

Iterable<_Tok> _xml(String s) sync* {
  final n = s.length;
  var i = 0;
  while (i < n) {
    final lt = s.indexOf('<', i);
    if (lt < 0) {
      yield _Tok(_tText, '', const {}, false, _unescape(s.substring(i)));
      return;
    }
    if (lt > i) yield _Tok(_tText, '', const {}, false, _unescape(s.substring(i, lt)));
    if (s.startsWith('<!--', lt)) {
      final e = s.indexOf('-->', lt + 4);
      i = e < 0 ? n : e + 3;
      continue;
    }
    if (s.startsWith('<![CDATA[', lt)) {
      final e = s.indexOf(']]>', lt + 9);
      yield _Tok(_tText, '', const {}, false, s.substring(lt + 9, e < 0 ? n : e));
      i = e < 0 ? n : e + 3;
      continue;
    }
    if (s.startsWith('<?', lt) || s.startsWith('<!', lt)) {
      final e = s.indexOf('>', lt);
      i = e < 0 ? n : e + 1;
      continue;
    }
    final closing = lt + 1 < n && s.codeUnitAt(lt + 1) == 0x2F; // '/'
    final nameStart = closing ? lt + 2 : lt + 1;
    final m = _nameRe.matchAsPrefix(s, nameStart);
    if (m == null) {
      // "a < b" in sloppy HTML: a literal character.
      yield const _Tok(_tText, '', {}, false, '<');
      i = lt + 1;
      continue;
    }
    // Find the closing '>' outside quotes.
    var j = nameStart + m.group(0)!.length;
    int? quote;
    while (j < n) {
      final c = s.codeUnitAt(j);
      if (quote != null) {
        if (c == quote) quote = null;
      } else if (c == 0x22 || c == 0x27) {
        quote = c;
      } else if (c == 0x3E) {
        break;
      }
      j++;
    }
    final name = m.group(0)!;
    if (closing) {
      yield _Tok(_tEnd, name, const {}, false, '');
    } else {
      var body = s.substring(nameStart + name.length, j < n ? j : n);
      var self = false;
      if (body.trimRight().endsWith('/')) {
        self = true;
        body = body.trimRight();
        body = body.substring(0, body.length - 1);
      }
      final attrs = <String, String>{};
      if (body.trim().isNotEmpty) {
        for (final a in _attrRe.allMatches(body)) {
          attrs[a.group(1)!] = _unescape(a.group(3) ?? a.group(4) ?? a.group(5) ?? '');
        }
      }
      yield _Tok(_tStart, name, attrs, self, '');
    }
    i = j + 1;
  }
}

const _entities = {
  'lt': '<', 'gt': '>', 'amp': '&', 'quot': '"', 'apos': "'", 'nbsp': '\u00A0',
  'mdash': '—', 'ndash': '–', 'hellip': '…', 'lsquo': '‘', 'rsquo': '’',
  'ldquo': '“', 'rdquo': '”', 'laquo': '«', 'raquo': '»', 'bull': '•',
  'middot': '·', 'copy': '©', 'reg': '®', 'trade': '™', 'deg': '°',
  'times': '×', 'divide': '÷', 'euro': '€', 'pound': '£', 'yen': '¥',
  'cent': '¢', 'sect': '§', 'para': '¶', 'shy': '', 'zwj': '', 'zwnj': '',
  'eacute': 'é', 'egrave': 'è', 'aacute': 'á', 'agrave': 'à', 'ouml': 'ö',
  'uuml': 'ü', 'auml': 'ä', 'szlig': 'ß', 'ccedil': 'ç', 'ntilde': 'ñ',
  'iacute': 'í', 'oacute': 'ó', 'uacute': 'ú', 'ecirc': 'ê', 'acirc': 'â',
};
final _entityRe = RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[A-Za-z]+);');

String _unescape(String s) {
  if (!s.contains('&')) return s;
  return s.replaceAllMapped(_entityRe, (m) {
    final e = m.group(1)!;
    try {
      if (e.startsWith('#x') || e.startsWith('#X')) {
        return String.fromCharCode(int.parse(e.substring(2), radix: 16));
      }
      if (e.startsWith('#')) return String.fromCharCode(int.parse(e.substring(1)));
    } catch (_) {
      return m.group(0)!;
    }
    return _entities[e] ?? _entities[e.toLowerCase()] ?? m.group(0)!;
  });
}

/// Collects spans for one paragraph, merging neighbours with equal style.
class _Para {
  final List<DocSpan> spans = [];
  void add(String text, {bool bold = false, bool italic = false, bool underline = false}) {
    if (text.isEmpty) return;
    if (spans.isNotEmpty) {
      final last = spans.last;
      if (last.bold == bold && last.italic == italic && last.underline == underline) {
        spans[spans.length - 1] = DocSpan(last.text + text,
            bold: bold, italic: italic, underline: underline);
        return;
      }
    }
    spans.add(DocSpan(text, bold: bold, italic: italic, underline: underline));
  }

  String get text => spans.map((s) => s.text).join();
  bool get blank => text.trim().isEmpty;
}

// ── ZIP family ───────────────────────────────────────────────────────────────

Uint8List _bytesOf(ArchiveFile f) {
  final c = f.content as List<int>;
  return c is Uint8List ? c : Uint8List.fromList(c);
}

Archive? _openArchive(Uint8List b, String ext) {
  if (b.length >= 2 && b[0] == 0x50 && b[1] == 0x4B) return ZipDecoder().decodeBytes(b);
  if (b.length >= 2 && b[0] == 0x1F && b[1] == 0x8B) {
    final inner = Uint8List.fromList(GZipDecoder().decodeBytes(b) as List<int>);
    if (inner.length > 262 && String.fromCharCodes(inner.sublist(257, 262)) == 'ustar') {
      return TarDecoder().decodeBytes(inner);
    }
    return null;
  }
  if (b.length > 262 && String.fromCharCodes(b.sublist(257, 262)) == 'ustar') {
    return TarDecoder().decodeBytes(b);
  }
  return null;
}

class _Zip {
  final Map<String, ArchiveFile> files = {};
  _Zip(Archive a) {
    for (final f in a.files) {
      if (f.isFile) files[f.name] = f;
    }
  }
  bool has(String name) => files.containsKey(name);
  Uint8List? bytes(String name) {
    final f = files[name];
    return f == null ? null : _bytesOf(f);
  }

  String? text(String name) {
    final b = bytes(name);
    return b == null ? null : _decodeText(b);
  }
}

String _dirOf(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i + 1);
}

String _resolve(String baseDir, String target) {
  if (target.startsWith('/')) return target.substring(1);
  final parts = <String>[...baseDir.split('/').where((p) => p.isNotEmpty)];
  for (final p in target.split('/')) {
    if (p == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (p != '.' && p.isNotEmpty) {
      parts.add(p);
    }
  }
  return parts.join('/');
}

Map<String, String> _rels(_Zip z, String relsPath, String baseDir) {
  final out = <String, String>{};
  final xml = z.text(relsPath);
  if (xml == null) return out;
  for (final t in _xml(xml)) {
    if (t.kind == _tStart && t.local == 'Relationship') {
      final id = t.attr('Id');
      final target = t.attr('Target');
      if (id != null && target != null && t.attr('TargetMode') != 'External') {
        out[id] = _resolve(baseDir, Uri.decodeFull(target));
      }
    }
  }
  return out;
}

bool _showableImage(String path) {
  final p = path.toLowerCase();
  return p.endsWith('.png') || p.endsWith('.jpg') || p.endsWith('.jpeg') ||
      p.endsWith('.gif') || p.endsWith('.bmp') || p.endsWith('.webp');
}

ExtractedDoc _fromZip(Uint8List b, String ext) {
  final archive = ZipDecoder().decodeBytes(b);
  final z = _Zip(archive);
  final mimetype = (z.text('mimetype') ?? '').trim();
  if (z.has('word/document.xml')) return _docx(z);
  if (z.has('xl/workbook.xml')) return _xlsx(z);
  if (z.has('ppt/presentation.xml')) return _pptx(z);
  if (mimetype.startsWith('application/epub') || z.has('META-INF/container.xml') && ext == 'epub') {
    return _epub(z);
  }
  if (mimetype.startsWith('application/vnd.oasis.opendocument') || z.has('content.xml') && z.has('styles.xml')) {
    return _odf(z, mimetype, ext);
  }
  for (final name in ['QuickLook/Preview.pdf', 'preview.pdf']) {
    final pdf = z.bytes(name);
    if (pdf != null) return ExtractedDoc(format: 'Apple document', previewPdf: pdf);
  }
  final fpages = z.files.keys.where((n) => n.toLowerCase().endsWith('.fpage')).toList();
  if (fpages.isNotEmpty) return _xps(z, fpages);
  for (final name in ['preview.jpg', 'QuickLook/Thumbnail.jpg', 'preview-web.jpg', 'Thumbnails/thumbnail.png']) {
    final img = z.bytes(name);
    if (img != null && (ext == 'pages' || ext == 'numbers' || ext == 'key')) {
      return ExtractedDoc(format: 'Apple document', previewImage: img,
          note: 'Showing the preview saved inside this file.');
    }
  }
  if (z.has('META-INF/container.xml')) return _epub(z);
  return _archiveListing(archive, 'Archive (.${ext.isEmpty ? 'zip' : ext})');
}

ExtractedDoc _archiveListing(Archive a, String format) {
  final entries = <ArchiveEntryInfo>[
    for (final f in a.files)
      if (f.isFile) ArchiveEntryInfo(f.name, f.size),
  ];
  entries.sort((x, y) => x.name.toLowerCase().compareTo(y.name.toLowerCase()));
  return ExtractedDoc(
    format: format,
    entries: entries,
    note: entries.isEmpty ? 'This archive is empty.' : null,
  );
}

ExtractedDoc _fromGzip(Uint8List b, String ext) {
  final inner = Uint8List.fromList(GZipDecoder().decodeBytes(b) as List<int>);
  if (inner.length > 262 && String.fromCharCodes(inner.sublist(257, 262)) == 'ustar') {
    return _archiveListing(TarDecoder().decodeBytes(inner), 'Archive (.tar.gz)');
  }
  return extractDocument(inner, '');
}

// ── Word (.docx) ─────────────────────────────────────────────────────────────

int? _headingLevel(String styleName) {
  final s = styleName.toLowerCase().replaceAll(' ', '');
  if (s == 'title') return 1;
  if (s == 'subtitle') return 3;
  final m = RegExp(r'(heading|berschrift|titre|titolo|encabezado|título|kop)(\d)').firstMatch(s);
  if (m != null) return _clampInt(int.parse(m.group(2)!), 1, 6);
  return null;
}

bool _on(_Tok t) {
  final v = t.attr('val');
  return v == null || !(v == '0' || v == 'false' || v == 'none' || v == 'off');
}

ExtractedDoc _docx(_Zip z) {
  final xml = z.text('word/document.xml') ?? '';
  final rels = _rels(z, 'word/_rels/document.xml.rels', 'word/');
  final styleNames = <String, String>{};
  final stylesXml = z.text('word/styles.xml');
  if (stylesXml != null) {
    String? id;
    for (final t in _xml(stylesXml)) {
      if (t.kind == _tStart && t.name == 'w:style') id = t.attr('styleId');
      if (t.kind == _tStart && t.name == 'w:name' && id != null) {
        styleNames[id] = t.attr('val') ?? id;
      }
    }
  }

  final blocks = <DocBlock>[];
  _Para? para;
  var pStyle = '';
  var isList = false;
  var outline = -1;
  var bold = false, italic = false, underline = false;
  var inPPr = false, inRPr = false, inT = false;
  var tblDepth = 0;
  List<List<String>>? rows;
  List<String>? row;
  StringBuffer? cell;
  final pendingImages = <Uint8List>[];

  void endParagraph() {
    final p = para;
    para = null;
    if (p == null) return;
    if (tblDepth > 0) {
      if (cell != null && !p.blank) {
        if (cell!.isNotEmpty) cell!.write('\n');
        cell!.write(p.text.trim());
      }
    } else if (!p.blank) {
      final name = styleNames[pStyle] ?? pStyle;
      final level = outline >= 0 && outline < 6 ? outline + 1 : _headingLevel(name);
      if (level != null) {
        blocks.add(DocBlock.text(DocBlockType.heading, p.text.trim(), level: level));
      } else if (isList || name.toLowerCase().contains('list')) {
        blocks.add(DocBlock(DocBlockType.bullet, spans: p.spans));
      } else {
        blocks.add(DocBlock(DocBlockType.paragraph, spans: p.spans));
      }
    }
    if (tblDepth == 0) {
      for (final img in pendingImages) {
        blocks.add(DocBlock(DocBlockType.image, image: img));
      }
      pendingImages.clear();
    }
  }

  for (final t in _xml(xml)) {
    if (blocks.length > 20000) break;
    if (t.kind == _tText) {
      if (inT) para?.add(t.text, bold: bold, italic: italic, underline: underline);
      continue;
    }
    final start = t.kind == _tStart;
    switch (t.name) {
      case 'w:tbl':
        if (start) {
          endParagraph();
          tblDepth++;
          if (tblDepth == 1) rows = [];
        } else if (tblDepth > 0) {
          tblDepth--;
          if (tblDepth == 0 && rows != null) {
            if (rows!.isNotEmpty) blocks.add(DocBlock(DocBlockType.table, rows: rows!));
            rows = null;
            for (final img in pendingImages) {
              blocks.add(DocBlock(DocBlockType.image, image: img));
            }
            pendingImages.clear();
          }
        }
        break;
      case 'w:tr':
        if (tblDepth == 1) {
          if (start) {
            row = [];
          } else if (row != null) {
            rows?.add(row!);
            row = null;
          }
        }
        break;
      case 'w:tc':
        if (tblDepth == 1) {
          if (start) {
            cell = StringBuffer();
          } else if (cell != null) {
            row?.add(cell.toString());
            cell = null;
          }
        }
        break;
      case 'w:p':
        if (start && !t.selfClose) {
          if (para != null) endParagraph(); // text box inside a paragraph
          para = _Para();
          pStyle = '';
          isList = false;
          outline = -1;
        } else if (!start) {
          endParagraph();
        }
        break;
      case 'w:pPr':
        inPPr = start && !t.selfClose;
        break;
      case 'w:rPr':
        inRPr = start && !t.selfClose;
        break;
      case 'w:pStyle':
        if (start && inPPr) pStyle = t.attr('val') ?? '';
        break;
      case 'w:numPr':
        if (start && inPPr) isList = true;
        break;
      case 'w:outlineLvl':
        if (start && inPPr) outline = int.tryParse(t.attr('val') ?? '') ?? -1;
        break;
      case 'w:r':
        if (start) bold = italic = underline = false;
        break;
      case 'w:b':
        if (start && inRPr && !inPPr) bold = _on(t);
        break;
      case 'w:i':
        if (start && inRPr && !inPPr) italic = _on(t);
        break;
      case 'w:u':
        if (start && inRPr && !inPPr) underline = _on(t);
        break;
      case 'w:t':
        inT = start && !t.selfClose;
        break;
      case 'w:tab':
        if (start && !inPPr) para?.add('\t', bold: bold, italic: italic);
        break;
      case 'w:br':
      case 'w:cr':
        if (start) para?.add('\n', bold: bold, italic: italic);
        break;
      case 'w:noBreakHyphen':
        if (start) para?.add('-');
        break;
      case 'a:blip':
        if (start) {
          final target = rels[t.attr('embed') ?? ''];
          if (target != null && _showableImage(target)) {
            final img = z.bytes(target);
            if (img != null) pendingImages.add(img);
          }
        }
        break;
    }
  }
  endParagraph();
  return ExtractedDoc(format: 'Word document', pages: [DocPage('', blocks)]);
}

// ── Excel (.xlsx) ────────────────────────────────────────────────────────────

int _colIndex(String ref) {
  var n = 0;
  for (final c in ref.codeUnits) {
    if (c >= 65 && c <= 90) {
      n = n * 26 + (c - 64);
    } else if (c >= 97 && c <= 122) {
      n = n * 26 + (c - 96);
    } else {
      break;
    }
  }
  return n - 1;
}

int _rowIndex(String ref) {
  final m = RegExp(r'(\d+)$').firstMatch(ref);
  return m == null ? -1 : int.parse(m.group(1)!) - 1;
}

String _num(String v) {
  final d = double.tryParse(v);
  if (d == null) return v;
  if (d == d.roundToDouble() && d.abs() < 1e15) return d.toInt().toString();
  var s = d.toStringAsPrecision(10);
  if (s.contains('.') && !s.contains('e')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}

String _serialDate(double serial, {bool date1904 = false}) {
  final base = date1904 ? DateTime.utc(1904, 1, 1) : DateTime.utc(1899, 12, 30);
  final days = serial.floor();
  final secs = ((serial - days) * 86400).round();
  final dt = base.add(Duration(days: days, seconds: secs));
  String two(int v) => v.toString().padLeft(2, '0');
  final day = '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  return secs == 0 ? day : '$day ${two(dt.hour)}:${two(dt.minute)}';
}

const _maxRows = 2000, _maxCols = 60;

List<List<String>> _gridRows(Map<int, Map<int, String>> grid) {
  if (grid.isEmpty) return const [];
  final rowsSorted = grid.keys.toList()..sort();
  var maxCol = 0;
  for (final r in grid.values) {
    for (final c in r.keys) {
      if (r[c]!.isNotEmpty && c > maxCol) maxCol = c;
    }
  }
  var minCol = maxCol;
  for (final r in grid.values) {
    for (final c in r.keys) {
      if (r[c]!.isNotEmpty && c < minCol) minCol = c;
    }
  }
  final out = <List<String>>[];
  for (final r in rowsSorted) {
    final cells = grid[r]!;
    if (cells.values.every((v) => v.isEmpty)) continue;
    out.add([for (var c = minCol; c <= maxCol; c++) cells[c] ?? '']);
  }
  return out;
}

ExtractedDoc _xlsx(_Zip z) {
  final shared = <String>[];
  final sst = z.text('xl/sharedStrings.xml');
  if (sst != null) {
    StringBuffer? si;
    var inT = false, inPh = false;
    for (final t in _xml(sst)) {
      if (t.kind == _tText) {
        if (si != null && inT && !inPh) si.write(t.text);
        continue;
      }
      final start = t.kind == _tStart;
      switch (t.local) {
        case 'si':
          if (start && !t.selfClose) {
            si = StringBuffer();
          } else {
            shared.add(si?.toString() ?? '');
            si = null;
          }
          break;
        case 't':
          inT = start && !t.selfClose;
          break;
        case 'rPh':
          inPh = start && !t.selfClose;
          break;
      }
    }
  }

  // Which cell styles are dates.
  final dateStyles = <int>{};
  final stylesXml = z.text('xl/styles.xml');
  var date1904 = false;
  if (stylesXml != null) {
    final custom = <int, String>{};
    var inXfs = false;
    var xfIndex = 0;
    for (final t in _xml(stylesXml)) {
      if (t.kind == _tText) continue;
      if (t.local == 'numFmt' && t.kind == _tStart) {
        custom[int.tryParse(t.attr('numFmtId') ?? '') ?? -1] = t.attr('formatCode') ?? '';
      } else if (t.local == 'cellXfs') {
        inXfs = t.kind == _tStart && !t.selfClose;
      } else if (t.local == 'xf' && t.kind == _tStart && inXfs) {
        final id = int.tryParse(t.attr('numFmtId') ?? '0') ?? 0;
        final code = (custom[id] ?? '').toLowerCase().replaceAll(RegExp(r'"[^"]*"|\[[^\]]*\]'), '');
        final isDate = (id >= 14 && id <= 22) || (id >= 45 && id <= 47) ||
            (code.isNotEmpty && RegExp(r'[dy]|mmm').hasMatch(code));
        if (isDate) dateStyles.add(xfIndex);
        xfIndex++;
      }
    }
  }

  final pages = <DocPage>[];
  final wbXml = z.text('xl/workbook.xml') ?? '';
  final wbRels = _rels(z, 'xl/_rels/workbook.xml.rels', 'xl/');
  final sheets = <MapEntry<String, String>>[];
  for (final t in _xml(wbXml)) {
    if (t.kind == _tStart && t.local == 'sheet') {
      final target = wbRels[t.attr('id') ?? ''];
      if (target != null) sheets.add(MapEntry(t.attr('name') ?? 'Sheet', target));
    }
    if (t.kind == _tStart && t.local == 'workbookPr') {
      final v = t.attr('date1904');
      if (v == '1' || v == 'true') date1904 = true;
    }
  }
  for (final sheet in sheets.take(40)) {
    final xml = z.text(sheet.value);
    if (xml == null) continue;
    final grid = <int, Map<int, String>>{};
    var r = -1, c = -1, type = '', style = 0;
    StringBuffer? value;
    var inV = false, inIs = false, inT = false;
    var rowCounter = -1;
    for (final t in _xml(xml)) {
      if (t.kind == _tText) {
        if (value != null && (inV || (inIs && inT))) value.write(t.text);
        continue;
      }
      final start = t.kind == _tStart;
      switch (t.local) {
        case 'row':
          if (start) {
            rowCounter = (int.tryParse(t.attr('r') ?? '') ?? (rowCounter + 2)) - 1;
            c = -1;
          }
          break;
        case 'c':
          if (start) {
            final ref = t.attr('r');
            r = ref == null ? rowCounter : _rowIndex(ref);
            c = ref == null ? c + 1 : _colIndex(ref);
            type = t.attr('t') ?? 'n';
            style = int.tryParse(t.attr('s') ?? '0') ?? 0;
            value = StringBuffer();
            if (t.selfClose) value = null;
          } else if (value != null) {
            final raw = value.toString();
            String shown;
            switch (type) {
              case 's':
                final i = int.tryParse(raw.trim()) ?? -1;
                shown = i >= 0 && i < shared.length ? shared[i] : '';
                break;
              case 'b':
                shown = raw.trim() == '1' ? 'TRUE' : 'FALSE';
                break;
              case 'inlineStr':
              case 'str':
              case 'e':
                shown = raw;
                break;
              default:
                final d = double.tryParse(raw);
                shown = d != null && dateStyles.contains(style)
                    ? _serialDate(d, date1904: date1904)
                    : _num(raw);
            }
            if (r >= 0 && r < _maxRows && c >= 0 && c < _maxCols) {
              (grid[r] ??= {})[c] = shown;
            }
            value = null;
          }
          break;
        case 'v':
          inV = start && !t.selfClose;
          break;
        case 'is':
          inIs = start && !t.selfClose;
          break;
        case 't':
          inT = start && !t.selfClose;
          break;
      }
    }
    final rows = _gridRows(grid);
    pages.add(DocPage(sheet.key, [if (rows.isNotEmpty) DocBlock(DocBlockType.table, rows: rows)],
        isSheet: true));
  }
  return ExtractedDoc(format: 'Spreadsheet', pages: pages);
}

// ── PowerPoint (.pptx) ───────────────────────────────────────────────────────

ExtractedDoc _pptx(_Zip z) {
  final rels = _rels(z, 'ppt/_rels/presentation.xml.rels', 'ppt/');
  final order = <String>[];
  for (final t in _xml(z.text('ppt/presentation.xml') ?? '')) {
    if (t.kind == _tStart && t.local == 'sldId') {
      final target = rels[t.attr('id') ?? ''];
      if (target != null) order.add(target);
    }
  }
  if (order.isEmpty) {
    order.addAll(z.files.keys.where((n) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(n)));
    order.sort((a, b) => _trailingNumber(a).compareTo(_trailingNumber(b)));
  }
  final pages = <DocPage>[];
  for (final path in order.take(500)) {
    final xml = z.text(path);
    if (xml == null) continue;
    final slideRels = _rels(z, '${_dirOf(path)}_rels/${path.split('/').last}.rels', _dirOf(path));
    final blocks = <DocBlock>[];
    var titleShape = false;
    _Para? para;
    var bold = false, italic = false, underline = false, inT = false;
    var lvl = 0;
    var tbl = 0;
    List<List<String>>? rows;
    List<String>? row;
    StringBuffer? cell;
    for (final t in _xml(xml)) {
      if (t.kind == _tText) {
        if (inT) para?.add(t.text, bold: bold, italic: italic, underline: underline);
        continue;
      }
      final start = t.kind == _tStart;
      switch (t.name) {
        case 'p:sp':
          if (start) titleShape = false;
          break;
        case 'p:ph':
          if (start) {
            final type = t.attr('type') ?? '';
            titleShape = type == 'title' || type == 'ctrTitle';
          }
          break;
        case 'a:tbl':
          if (start) {
            tbl++;
            rows = [];
          } else {
            tbl--;
            if (rows != null && rows!.isNotEmpty) blocks.add(DocBlock(DocBlockType.table, rows: rows!));
            rows = null;
          }
          break;
        case 'a:tr':
          if (start) {
            row = [];
          } else if (row != null) {
            rows?.add(row!);
            row = null;
          }
          break;
        case 'a:tc':
          if (start) {
            cell = StringBuffer();
          } else if (cell != null) {
            row?.add(cell.toString().trim());
            cell = null;
          }
          break;
        case 'a:p':
          if (start && !t.selfClose) {
            para = _Para();
            lvl = 0;
          } else if (!start && para != null) {
            final p = para!;
            para = null;
            if (p.blank) break;
            if (tbl > 0) {
              if (cell != null) {
                if (cell!.isNotEmpty) cell!.write('\n');
                cell!.write(p.text);
              }
            } else if (titleShape) {
              blocks.add(DocBlock.text(DocBlockType.heading, p.text.trim(), level: 2));
            } else if (lvl > 0) {
              blocks.add(DocBlock(DocBlockType.bullet, spans: p.spans, level: lvl));
            } else {
              blocks.add(DocBlock(DocBlockType.paragraph, spans: p.spans));
            }
          }
          break;
        case 'a:pPr':
          if (start) lvl = int.tryParse(t.attr('lvl') ?? '0') ?? 0;
          break;
        case 'a:r':
          if (start) bold = italic = underline = false;
          break;
        case 'a:rPr':
          if (start) {
            bold = t.attr('b') == '1' || t.attr('b') == 'true';
            italic = t.attr('i') == '1' || t.attr('i') == 'true';
            underline = (t.attr('u') ?? 'none') != 'none';
          }
          break;
        case 'a:t':
          inT = start && !t.selfClose;
          break;
        case 'a:br':
          if (start) para?.add('\n');
          break;
        case 'a:blip':
          if (start) {
            final target = slideRels[t.attr('embed') ?? ''];
            if (target != null && _showableImage(target)) {
              final img = z.bytes(target);
              if (img != null) blocks.add(DocBlock(DocBlockType.image, image: img));
            }
          }
          break;
      }
    }
    pages.add(DocPage('Slide ${pages.length + 1}', blocks));
  }
  return ExtractedDoc(format: 'Slides', pages: pages);
}

int _trailingNumber(String s) =>
    int.tryParse(RegExp(r'(\d+)\D*$').firstMatch(s)?.group(1) ?? '') ?? 0;

// ── OpenDocument (.odt .ods .odp) ────────────────────────────────────────────

ExtractedDoc _odf(_Zip z, String mimetype, String ext) {
  final xml = z.text('content.xml') ?? '';
  final kind = mimetype.contains('spreadsheet') || ext == 'ods'
      ? 'sheet'
      : (mimetype.contains('presentation') || ext == 'odp' ? 'slides' : 'text');
  final styleBold = <String>{}, styleItalic = <String>{}, styleUnder = <String>{};
  String? styleName;
  final pages = <DocPage>[];
  var blocks = <DocBlock>[];
  _Para? para;
  final spanStack = <String>[];
  var heading = 0;
  var listDepth = 0;
  var skip = 0;
  var tableDepth = 0;
  List<List<String>>? rows;
  List<String>? row;
  StringBuffer? cell;
  var rowRepeat = 1, cellRepeat = 1;
  String pageTitle = '';
  final grid = <int, Map<int, String>>{};
  var gridRow = 0, gridCol = 0;

  bool styled(Set<String> set) => spanStack.any(set.contains);

  void endPara() {
    final p = para;
    para = null;
    if (p == null || p.blank) return;
    if (tableDepth > 0 && cell != null) {
      if (cell!.isNotEmpty) cell!.write('\n');
      cell!.write(p.text);
    } else if (heading > 0) {
      blocks.add(DocBlock.text(DocBlockType.heading, p.text.trim(), level: heading));
    } else if (listDepth > 0) {
      blocks.add(DocBlock(DocBlockType.bullet, spans: p.spans, level: listDepth));
    } else {
      blocks.add(DocBlock(DocBlockType.paragraph, spans: p.spans));
    }
  }

  for (final t in _xml(xml)) {
    if (t.kind == _tText) {
      if (skip == 0 && para != null) {
        para!.add(t.text,
            bold: styled(styleBold), italic: styled(styleItalic), underline: styled(styleUnder));
      }
      continue;
    }
    final start = t.kind == _tStart;
    final open = start && !t.selfClose;
    switch (t.name) {
      case 'style:style':
        if (start) styleName = t.attr('name');
        break;
      case 'style:text-properties':
        if (start && styleName != null) {
          if (t.attr('font-weight') == 'bold') styleBold.add(styleName!);
          if (t.attr('font-style') == 'italic') styleItalic.add(styleName!);
          final u = t.attr('text-underline-style');
          if (u != null && u != 'none') styleUnder.add(styleName!);
        }
        break;
      case 'office:annotation':
      case 'text:note':
      case 'text:tracked-changes':
        if (open) {
          skip++;
        } else if (!start && skip > 0) {
          skip--;
        }
        break;
      case 'text:h':
        if (open) {
          heading = int.tryParse(t.attr('outline-level') ?? '1') ?? 1;
          para = _Para();
          spanStack
            ..clear()
            ..add(t.attr('style-name') ?? '');
        } else if (!start) {
          endPara();
          heading = 0;
        }
        break;
      case 'text:p':
        if (open && skip == 0) {
          para = _Para();
          spanStack
            ..clear()
            ..add(t.attr('style-name') ?? '');
        } else if (!start && skip == 0) {
          endPara();
        }
        break;
      case 'text:span':
        if (open) {
          spanStack.add(t.attr('style-name') ?? '');
        } else if (!start && spanStack.length > 1) {
          spanStack.removeLast();
        }
        break;
      case 'text:s':
        if (start) para?.add(' ' * _clampInt(int.tryParse(t.attr('c') ?? '1') ?? 1, 1, 40));
        break;
      case 'text:tab':
        if (start) para?.add('\t');
        break;
      case 'text:line-break':
        if (start) para?.add('\n');
        break;
      case 'text:list':
        if (open) {
          listDepth++;
        } else if (!start && listDepth > 0) {
          listDepth--;
        }
        break;
      case 'draw:page':
        if (open) {
          blocks = <DocBlock>[];
          pageTitle = t.attr('name') ?? 'Slide ${pages.length + 1}';
        } else if (!start) {
          pages.add(DocPage(pageTitle, blocks));
          blocks = <DocBlock>[];
        }
        break;
      case 'draw:image':
        if (start) {
          final href = t.attr('href');
          if (href != null && _showableImage(href)) {
            final img = z.bytes(href.startsWith('./') ? href.substring(2) : href);
            if (img != null) blocks.add(DocBlock(DocBlockType.image, image: img));
          }
        }
        break;
      case 'table:table':
        if (open) {
          tableDepth++;
          if (tableDepth == 1) {
            rows = [];
            grid.clear();
            gridRow = 0;
            pageTitle = t.attr('name') ?? 'Sheet ${pages.length + 1}';
          }
        } else if (!start && tableDepth > 0) {
          tableDepth--;
          if (tableDepth == 0) {
            if (kind == 'sheet') {
              final r = _gridRows(grid);
              pages.add(DocPage(pageTitle, [if (r.isNotEmpty) DocBlock(DocBlockType.table, rows: r)],
                  isSheet: true));
            } else if (rows != null && rows!.isNotEmpty) {
              blocks.add(DocBlock(DocBlockType.table, rows: rows!));
            }
            rows = null;
          }
        }
        break;
      case 'table:table-row':
        if (tableDepth == 1) {
          if (start) {
            row = [];
            gridCol = 0;
            rowRepeat = (int.tryParse(t.attr('number-rows-repeated') ?? '1') ?? 1);
            if (t.selfClose) {
              gridRow += rowRepeat;
              row = null;
            }
          } else if (row != null) {
            final hasText = row!.any((c) => c.isNotEmpty);
            final times = hasText ? _clampInt(rowRepeat, 1, 50) : 1;
            for (var k = 0; k < times; k++) {
              if (kind == 'sheet') {
                if (gridRow < _maxRows) {
                  final m = grid[gridRow] ??= {};
                  for (var ci = 0; ci < row!.length && ci < _maxCols; ci++) {
                    m[ci] = row![ci];
                  }
                }
              } else {
                final r = List.of(row!);
                while (r.isNotEmpty && r.last.isEmpty) {
                  r.removeLast();
                }
                rows?.add(r);
              }
              gridRow++;
            }
            if (!hasText) gridRow += rowRepeat - 1;
            row = null;
          }
        }
        break;
      case 'table:table-cell':
      case 'table:covered-table-cell':
        if (tableDepth == 1 && row != null) {
          if (start) {
            cellRepeat = int.tryParse(t.attr('number-columns-repeated') ?? '1') ?? 1;
            cell = StringBuffer();
            if (t.selfClose) {
              for (var k = 0; k < _clampInt(cellRepeat, 1, _maxCols) && row!.length < _maxCols; k++) {
                row!.add('');
              }
              cell = null;
            }
          } else if (cell != null) {
            final v = cell.toString();
            final times = _clampInt(cellRepeat, 1, _maxCols);
            for (var k = 0; k < times && row!.length < _maxCols; k++) {
              row!.add(v);
            }
            cell = null;
          }
          gridCol++;
        }
        break;
    }
  }
  endPara();
  if (kind == 'text' || pages.isEmpty) pages.add(DocPage('', blocks));
  // Trailing empty cells from repeats: trim each table row.
  return ExtractedDoc(
      format: kind == 'sheet' ? 'Spreadsheet' : (kind == 'slides' ? 'Slides' : 'Document'),
      pages: pages.where((p) => p.blocks.isNotEmpty || pages.length == 1).toList());
}

// ── E-books: EPUB, FB2, MOBI ─────────────────────────────────────────────────

ExtractedDoc _epub(_Zip z) {
  var opfPath = '';
  for (final t in _xml(z.text('META-INF/container.xml') ?? '')) {
    if (t.kind == _tStart && t.local == 'rootfile') {
      opfPath = t.attr('full-path') ?? '';
      break;
    }
  }
  if (opfPath.isEmpty) {
    opfPath = z.files.keys.firstWhere((n) => n.toLowerCase().endsWith('.opf'), orElse: () => '');
  }
  final opf = z.text(opfPath) ?? '';
  final base = _dirOf(opfPath);
  final manifest = <String, String>{};
  final spine = <String>[];
  String? title;
  var inTitle = false;
  for (final t in _xml(opf)) {
    if (t.kind == _tText) {
      if (inTitle && title == null && t.text.trim().isNotEmpty) title = t.text.trim();
      continue;
    }
    if (t.local == 'title') inTitle = t.kind == _tStart && !t.selfClose;
    if (t.kind != _tStart) continue;
    if (t.local == 'item') {
      final id = t.attr('id'), href = t.attr('href');
      if (id != null && href != null) manifest[id] = _resolve(base, Uri.decodeFull(href));
    } else if (t.local == 'itemref') {
      final id = t.attr('idref');
      if (id != null) spine.add(id);
    }
  }
  final pages = <DocPage>[];
  var imageBudget = 25 * 1024 * 1024;
  for (final id in spine.take(600)) {
    final path = manifest[id];
    if (path == null) continue;
    final html = z.text(path);
    if (html == null) continue;
    final dir = _dirOf(path);
    final blocks = _htmlBlocks(html, image: (src) {
      final p = _resolve(dir, Uri.decodeFull(src.split('#').first));
      if (!_showableImage(p)) return null;
      final b = z.bytes(p);
      if (b == null || b.length > imageBudget) return null;
      imageBudget -= b.length;
      return b;
    });
    if (blocks.isEmpty) continue;
    final heading = blocks.firstWhere((b) => b.type == DocBlockType.heading,
        orElse: () => const DocBlock(DocBlockType.paragraph));
    final name = heading.type == DocBlockType.heading && heading.text.length < 80
        ? heading.text
        : 'Part ${pages.length + 1}';
    pages.add(DocPage(name, blocks));
  }
  return ExtractedDoc(format: 'E-book (EPUB)', pages: pages, title: title);
}

ExtractedDoc _htmlDoc(String html, {required String format, bool fb2 = false}) {
  String? title;
  final m = RegExp(fb2 ? r'<book-title>([^<]*)</book-title>' : r'<title[^>]*>([^<]*)</title>',
          caseSensitive: false)
      .firstMatch(html.length > 20000 ? html.substring(0, 20000) : html);
  if (m != null && m.group(1)!.trim().isNotEmpty) title = _unescape(m.group(1)!.trim());
  return ExtractedDoc(
      format: format, pages: [DocPage('', _htmlBlocks(html, fb2: fb2))], title: title);
}

const _htmlSkip = {
  'script', 'style', 'head', 'noscript', 'template', 'svg', 'math', 'iframe',
  'object', 'select', 'button',
};
const _htmlBlock = {
  'p', 'div', 'section', 'article', 'header', 'footer', 'main', 'aside', 'nav',
  'blockquote', 'pre', 'li', 'dt', 'dd', 'figcaption', 'figure', 'address',
  'center', 'form', 'fieldset', 'body', 'html', 'ul', 'ol', 'dl', 'caption',
  // fb2
  'v', 'stanza', 'poem', 'epigraph', 'cite', 'text-author', 'annotation',
};

List<DocBlock> _htmlBlocks(String html,
    {Uint8List? Function(String src)? image, bool fb2 = false}) {
  final blocks = <DocBlock>[];
  var para = _Para();
  var bold = 0, italic = 0, underline = 0, pre = 0, skip = 0, list = 0, heading = 0;
  var tableDepth = 0;
  List<List<String>>? rows;
  List<String>? row;
  StringBuffer? cell;
  var inLi = false;

  void flush() {
    if (para.blank) {
      para = _Para();
      return;
    }
    if (tableDepth > 0) {
      if (cell != null) {
        if (cell!.isNotEmpty) cell!.write(' ');
        cell!.write(para.text.trim());
      }
    } else if (heading > 0) {
      blocks.add(DocBlock.text(DocBlockType.heading, para.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
          level: heading));
    } else if (pre > 0) {
      blocks.add(DocBlock.text(DocBlockType.code, para.text));
    } else {
      final spans = _trimSpans(para.spans);
      if (spans.isNotEmpty) {
        blocks.add(DocBlock(inLi ? DocBlockType.bullet : DocBlockType.paragraph,
            spans: spans, level: list < 1 ? 1 : list));
      }
    }
    para = _Para();
  }

  for (final t in _xml(html)) {
    if (blocks.length > 50000) break;
    if (t.kind == _tText) {
      if (skip > 0) continue;
      var s = t.text;
      if (pre == 0) s = s.replaceAll(RegExp(r'\s+'), ' ');
      para.add(s, bold: bold > 0, italic: italic > 0, underline: underline > 0);
      continue;
    }
    final name = fb2 ? t.local : t.local.toLowerCase();
    final start = t.kind == _tStart;
    final open = start && !t.selfClose;
    if (_htmlSkip.contains(name) || (fb2 && (name == 'binary' || name == 'description'))) {
      if (open) {
        skip++;
      } else if (!start && skip > 0) {
        skip--;
      }
      continue;
    }
    if (skip > 0) continue;
    final hm = RegExp(r'^h([1-6])$').firstMatch(name);
    if (hm != null || (fb2 && (name == 'title' || name == 'subtitle'))) {
      if (open) {
        flush();
        heading = hm != null ? int.parse(hm.group(1)!) : (name == 'title' ? 2 : 3);
      } else if (!start) {
        flush();
        heading = 0;
      }
      continue;
    }
    switch (name) {
      case 'b':
      case 'strong':
        if (open) bold++; else if (!start && bold > 0) bold--;
        break;
      case 'i':
      case 'em':
      case 'emphasis':
      case 'var':
        if (open) italic++; else if (!start && italic > 0) italic--;
        break;
      case 'u':
      case 'ins':
        if (open) underline++; else if (!start && underline > 0) underline--;
        break;
      case 'pre':
        flush();
        if (open) pre++; else if (!start && pre > 0) pre--;
        break;
      case 'br':
        para.add('\n');
        break;
      case 'hr':
        flush();
        if (tableDepth == 0) blocks.add(const DocBlock(DocBlockType.divider));
        break;
      case 'ul':
      case 'ol':
        flush();
        if (open) list++; else if (!start && list > 0) list--;
        break;
      case 'li':
        flush();
        inLi = open;
        break;
      case 'img':
      case 'image':
        if (start && image != null && tableDepth == 0) {
          final src = t.attr('src') ?? t.attr('href');
          if (src != null && !src.startsWith('data:') && !src.startsWith('http')) {
            final b = image(src);
            if (b != null) {
              flush();
              blocks.add(DocBlock(DocBlockType.image, image: b));
            }
          }
        }
        break;
      case 'table':
        flush();
        if (open) {
          tableDepth++;
          if (tableDepth == 1) rows = [];
        } else if (!start && tableDepth > 0) {
          tableDepth--;
          if (tableDepth == 0) {
            if (rows != null && rows!.isNotEmpty) {
              blocks.add(DocBlock(DocBlockType.table, rows: rows!));
            }
            rows = null;
          }
        }
        break;
      case 'tr':
        if (tableDepth == 1) {
          flush();
          if (open) {
            row = [];
          } else if (!start && row != null) {
            if (row!.isNotEmpty) rows?.add(row!);
            row = null;
          }
        }
        break;
      case 'td':
      case 'th':
        if (tableDepth == 1) {
          if (open) {
            flush();
            cell = StringBuffer();
          } else if (!start) {
            flush();
            if (cell != null) row?.add(cell.toString().trim());
            cell = null;
          }
        }
        break;
      default:
        if (_htmlBlock.contains(name) || (fb2 && name == 'p') || (fb2 && name == 'section')) {
          if (heading == 0 || !fb2) flush();
        }
    }
  }
  flush();
  return blocks;
}

List<DocSpan> _trimSpans(List<DocSpan> spans) {
  if (spans.isEmpty) return spans;
  final out = List<DocSpan>.of(spans);
  DocSpan trim(DocSpan s, String text) =>
      DocSpan(text, bold: s.bold, italic: s.italic, underline: s.underline);
  out[0] = trim(out[0], out[0].text.replaceFirst(RegExp(r'^\s+'), ''));
  out[out.length - 1] = trim(out.last, out.last.text.replaceFirst(RegExp(r'\s+$'), ''));
  return out.where((s) => s.text.isNotEmpty).toList();
}

ExtractedDoc _mobi(Uint8List b) {
  int u16(int o) => (b[o] << 8) | b[o + 1];
  int u32(int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
  final count = u16(76);
  final offsets = [for (var i = 0; i < count; i++) u32(78 + 8 * i)];
  int recEnd(int i) => i + 1 < count ? offsets[i + 1] : b.length;
  final r0 = offsets[0];
  final compression = u16(r0);
  final textLength = u32(r0 + 4);
  final recordCount = u16(r0 + 8);
  var encoding = 1252;
  var extraFlags = 0;
  final encrypted = u16(r0 + 12) != 0;
  String? title;
  final isMobi = b.length > r0 + 20 && String.fromCharCodes(b.sublist(r0 + 16, r0 + 20)) == 'MOBI';
  if (isMobi) {
    final headerLen = u32(r0 + 20);
    encoding = u32(r0 + 28);
    if (headerLen >= 0xE4 && b.length > r0 + 0xF4) extraFlags = u16(r0 + 0xF2);
    final nameOff = u32(r0 + 0x54), nameLen = u32(r0 + 0x58);
    if (nameLen > 0 && nameLen < 1024 && r0 + nameOff + nameLen <= b.length) {
      title = utf8.decode(b.sublist(r0 + nameOff, r0 + nameOff + nameLen), allowMalformed: true);
    }
  }
  title ??= String.fromCharCodes(b.sublist(0, 32).takeWhile((c) => c != 0));
  if (encrypted) {
    return ExtractedDoc(format: 'E-book (MOBI)', title: title,
        note: 'This e-book is DRM-protected, so its text cannot be shown.');
  }
  if (compression != 1 && compression != 2) {
    return ExtractedDoc(format: 'E-book (MOBI)', title: title,
        note: 'This e-book uses Kindle compression that BookNest cannot read yet.');
  }

  int trailing(Uint8List rec) {
    var size = 0;
    var end = rec.length;
    for (var bit = 15; bit > 0; bit--) {
      if (extraFlags & (1 << bit) == 0) continue;
      // Backward-encoded variable-length size.
      var value = 0, shift = 0, pos = end - 1;
      for (var k = 0; k < 4 && pos >= 0; k++, pos--) {
        final v = rec[pos];
        value |= (v & 0x7F) << shift;
        shift += 7;
        if (v & 0x80 != 0) break;
      }
      size += value;
      end -= value;
      if (end < 0) return rec.length;
    }
    if (extraFlags & 1 != 0 && end > 0) {
      size += (rec[end - 1] & 3) + 1;
    }
    return size;
  }

  final out = BytesBuilder(copy: false);
  for (var i = 1; i <= recordCount && i < count; i++) {
    var rec = b.sublist(offsets[i], recEnd(i));
    final cut = extraFlags == 0 ? 0 : trailing(rec);
    if (cut > 0 && cut < rec.length) rec = rec.sublist(0, rec.length - cut);
    out.add(compression == 2 ? _palmDoc(rec) : rec);
    if (out.length >= textLength) break;
  }
  var raw = out.takeBytes();
  if (raw.length > textLength && textLength > 0) raw = raw.sublist(0, textLength);
  final text = encoding == 65001 ? utf8.decode(raw, allowMalformed: true) : _cp1252(raw, 0, raw.length);
  final blocks = text.contains('<')
      ? _htmlBlocks(text.replaceAll(RegExp(r'<mbp:pagebreak\s*/?>', caseSensitive: false), '<hr/>'))
      : _plain(text, '').pages.first.blocks;
  return ExtractedDoc(format: 'E-book (MOBI)', pages: [DocPage('', blocks)], title: title);
}

Uint8List _palmDoc(Uint8List data) {
  final out = <int>[];
  var i = 0;
  while (i < data.length) {
    final c = data[i++];
    if (c == 0 || (c >= 0x09 && c <= 0x7F)) {
      out.add(c);
    } else if (c >= 0x01 && c <= 0x08) {
      for (var k = 0; k < c && i < data.length; k++) {
        out.add(data[i++]);
      }
    } else if (c >= 0x80 && c <= 0xBF) {
      if (i >= data.length) break;
      final pair = ((c << 8) | data[i++]) & 0x3FFF;
      final dist = pair >> 3;
      final len = (pair & 7) + 3;
      if (dist == 0 || dist > out.length) continue;
      final from = out.length - dist;
      for (var k = 0; k < len; k++) {
        out.add(out[from + k]);
      }
    } else {
      out
        ..add(0x20)
        ..add(c ^ 0x80);
    }
  }
  return Uint8List.fromList(out);
}

// ── XPS ──────────────────────────────────────────────────────────────────────

ExtractedDoc _xps(_Zip z, List<String> fpages) {
  fpages.sort((a, b) {
    final da = _dirOf(a), db = _dirOf(b);
    if (da != db) return da.compareTo(db);
    return _trailingNumber(a).compareTo(_trailingNumber(b));
  });
  final pages = <DocPage>[];
  for (final path in fpages.take(500)) {
    final blocks = <DocBlock>[];
    for (final t in _xml(z.text(path) ?? '')) {
      if (t.kind == _tStart && t.local == 'Glyphs') {
        final s = t.attr('UnicodeString');
        if (s != null && s.trim().isNotEmpty) {
          blocks.add(DocBlock.text(DocBlockType.paragraph, s.startsWith('{}') ? s.substring(2) : s));
        }
      }
    }
    pages.add(DocPage('Page ${pages.length + 1}', blocks));
  }
  return ExtractedDoc(format: 'XPS document', pages: pages);
}

// ── RTF ──────────────────────────────────────────────────────────────────────

const _rtfDestinations = {
  'aftncn', 'aftnsep', 'aftnsepc', 'annotation', 'atnauthor', 'atndate', 'atnicn',
  'atnid', 'atnparent', 'atnref', 'atntime', 'atrfend', 'atrfstart', 'author',
  'background', 'bkmkend', 'bkmkstart', 'blipuid', 'buptim', 'category',
  'colorschememapping', 'colortbl', 'comment', 'company', 'creatim', 'datafield',
  'datastore', 'defchp', 'defpap', 'do', 'doccomm', 'docvar', 'dptxbxtext',
  'ebcend', 'ebcstart', 'factoidname', 'falt', 'fchars', 'ffdeftext',
  'ffentrymcr', 'ffexitmcr', 'ffformat', 'ffhelptext', 'ffl', 'ffname',
  'ffstattext', 'field', 'file', 'filetbl', 'fldinst', 'fldtype', 'fname',
  'fontemb', 'fontfile', 'fonttbl', 'footer', 'footerf', 'footerl', 'footerr',
  'footnote', 'formfield', 'ftncn', 'ftnsep', 'ftnsepc', 'g', 'generator',
  'gridtbl', 'header', 'headerf', 'headerl', 'headerr', 'hl', 'hlfr', 'hlinkbase',
  'hlloc', 'hlsrc', 'hsv', 'htmltag', 'info', 'keycode', 'keywords',
  'latentstyles', 'lchars', 'levelnumbers', 'leveltext', 'lfolevel', 'linkval',
  'list', 'listlevel', 'listname', 'listoverride', 'listoverridetable',
  'listpicture', 'liststylename', 'listtable', 'listtext', 'lsdlockedexcept',
  'macc', 'maccPr', 'mailmerge', 'maln', 'malnScr', 'manager', 'margPr', 'mbar',
  'mbarPr', 'mbaseJc', 'mbegChr', 'mborderBox', 'mborderBoxPr', 'mbox', 'mboxPr',
  'mchr', 'mcount', 'mctrlPr', 'md', 'mdeg', 'mdegHide', 'mden', 'mdiff', 'mdPr',
  'me', 'mendChr', 'meqArr', 'meqArrPr', 'mf', 'mfName', 'mfPr', 'mfunc',
  'mfuncPr', 'mgroupChr', 'mgroupChrPr', 'mgrow', 'mhideBot', 'mhideLeft',
  'mhideRight', 'mhideTop', 'mhtmltag', 'mlim', 'mlimloc', 'mlimlow',
  'mlimlowPr', 'mlimupp', 'mlimuppPr', 'mm', 'mmaddfieldname', 'mmath',
  'mmathPict', 'mmathPr', 'mmaxdist', 'mmc', 'mmcJc', 'mmconnectstr',
  'mmconnectstrdata', 'mmcPr', 'mmcs', 'mmdatasource', 'mmheadersource',
  'mmmailsubject', 'mmodso', 'mmodsofilter', 'mmodsofldmpdata',
  'mmodsomappedname', 'mmodsoname', 'mmodsorecipdata', 'mmodsosort',
  'mmodsosrc', 'mmodsotable', 'mmodsoudl', 'mmodsoudldata', 'mmodsouniquetag',
  'mmPr', 'mmquery', 'mmr', 'mnary', 'mnaryPr', 'mnoBreak', 'mnum', 'mobjDist',
  'moMath', 'moMathPara', 'moMathParaPr', 'mopEmu', 'mphant', 'mphantPr',
  'mplcHide', 'mpos', 'mr', 'mrad', 'mradPr', 'mrPr', 'msepChr', 'mshow',
  'mshp', 'msPre', 'msPrePr', 'msSub', 'msSubPr', 'msSubSup', 'msSubSupPr',
  'msSup', 'msSupPr', 'mstrikeBLTR', 'mstrikeH', 'mstrikeTLBR', 'mstrikeV',
  'msub', 'msubHide', 'msup', 'msupHide', 'mtransp', 'mtype', 'mvertJc',
  'mvfmf', 'mvfml', 'mvtof', 'mvtol', 'mzeroAsc', 'mzeroDesc', 'mzeroWid',
  'nesttableprops', 'nextfile', 'nonesttables', 'objalias', 'objclass',
  'objdata', 'object', 'objname', 'objsect', 'objtime', 'oldcprops',
  'oldpprops', 'oldsprops', 'oldtprops', 'oleclsid', 'operator', 'panose',
  'password', 'passwordhash', 'pgp', 'pgptbl', 'picprop', 'pict', 'pn', 'pnseclvl',
  'pntext', 'pntxta', 'pntxtb', 'printim', 'private', 'propname', 'protend',
  'protstart', 'protusertbl', 'pxe', 'result', 'revtbl', 'revtim', 'rsidtbl',
  'rxe', 'shp', 'shpgrp', 'shpinst', 'shppict', 'shprslt', 'shptxt', 'sn', 'sp',
  'staticval', 'stylesheet', 'subject', 'sv', 'svb', 'tc', 'template',
  'themedata', 'title', 'txe', 'ud', 'upr', 'userprops', 'wgrffmtfilter',
  'windowcaption', 'writereservation', 'writereservhash', 'xe', 'xform',
  'xmlattrname', 'xmlattrvalue', 'xmlclose', 'xmlname', 'xmlnstbl', 'xmlopen',
};
const _rtfSpecial = {
  'par': '\n', 'sect': '\n\n', 'page': '\n\n', 'line': '\n', 'tab': '\t',
  'emdash': '—', 'endash': '–', 'emspace': ' ', 'enspace': ' ', 'qmspace': ' ',
  'bullet': '•', 'lquote': '‘', 'rquote': '’', 'ldblquote': '“',
  'rdblquote': '”', 'row': '\n', 'cell': ' | ', 'nestcell': ' | ',
};
final _rtfRe = RegExp(
    r"\\([a-z]{1,32})(-?\d{1,10})?[ ]?|\\'([0-9a-f]{2})|\\([^a-z])|([{}])|[\r\n]+|(.)",
    caseSensitive: false,
    dotAll: true);

ExtractedDoc _rtf(Uint8List b) {
  final text = String.fromCharCodes(b); // RTF is 7-bit; \'hh escapes carry the rest
  final stack = <List<Object>>[];
  var ignorable = false;
  var ucskip = 1;
  var curskip = 0;
  final out = StringBuffer();
  for (final m in _rtfRe.allMatches(text)) {
    final word = m.group(1), arg = m.group(2), hex = m.group(3);
    final ch = m.group(4), brace = m.group(5), tchar = m.group(6);
    if (brace != null) {
      curskip = 0;
      if (brace == '{') {
        stack.add([ucskip, ignorable]);
      } else if (stack.isNotEmpty) {
        final top = stack.removeLast();
        ucskip = top[0] as int;
        ignorable = top[1] as bool;
      }
    } else if (ch != null) {
      curskip = 0;
      if (ch == '~') {
        if (!ignorable) out.write('\u00A0');
      } else if ('{}\\'.contains(ch)) {
        if (!ignorable) out.write(ch);
      } else if (ch == '*') {
        ignorable = true;
      } else if (ch == '-' || ch == '_') {
        if (!ignorable && ch == '_') out.write('-');
      }
    } else if (word != null) {
      curskip = 0;
      if (_rtfDestinations.contains(word)) {
        ignorable = true;
      } else if (ignorable) {
        // nothing
      } else if (_rtfSpecial.containsKey(word)) {
        out.write(_rtfSpecial[word]);
      } else if (word == 'uc') {
        ucskip = int.tryParse(arg ?? '1') ?? 1;
      } else if (word == 'u') {
        var c = int.tryParse(arg ?? '') ?? 0;
        if (c < 0) c += 0x10000;
        out.writeCharCode(c);
        curskip = ucskip;
      }
    } else if (hex != null) {
      if (curskip > 0) {
        curskip--;
      } else if (!ignorable) {
        final c = int.parse(hex, radix: 16);
        out.write(_cp1252(Uint8List.fromList([c]), 0, 1));
      }
    } else if (tchar != null) {
      if (curskip > 0) {
        curskip--;
      } else if (!ignorable) {
        out.write(tchar);
      }
    }
  }
  final blocks = <DocBlock>[
    for (final p in out.toString().split('\n'))
      if (p.trim().isNotEmpty) DocBlock.text(DocBlockType.paragraph, p.trim()),
  ];
  return ExtractedDoc(format: 'Rich text (RTF)', pages: [DocPage('', blocks)]);
}

// ── CSV ──────────────────────────────────────────────────────────────────────

ExtractedDoc _csv(String text, String? delimiter) {
  final firstLine = text.split('\n').first;
  final d = delimiter ??
      (';'.allMatches(firstLine).length > ','.allMatches(firstLine).length
          ? ';'
          : ('\t'.allMatches(firstLine).length > ','.allMatches(firstLine).length ? '\t' : ','));
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length && rows.length < _maxRows; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == d) {
      row.add(cell.toString());
      cell.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      if (row.any((v) => v.isNotEmpty)) rows.add(row.take(_maxCols).toList());
      row = <String>[];
    } else {
      cell.write(c);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    if (row.any((v) => v.isNotEmpty)) rows.add(row.take(_maxCols).toList());
  }
  final width = rows.fold<int>(0, (w, r) => r.length > w ? r.length : w);
  final padded = [for (final r in rows) [...r, for (var k = r.length; k < width; k++) '']];
  return ExtractedDoc(
      format: 'Spreadsheet (CSV)',
      pages: [DocPage('', [if (padded.isNotEmpty) DocBlock(DocBlockType.table, rows: padded)], isSheet: true)]);
}

// ── OLE compound files: .doc .xls .ppt .msg ──────────────────────────────────

class _Cfb {
  final Uint8List b;
  late final int sectorSize, miniSize, cutoff;
  final List<int> fat = [];
  final List<int> miniFat = [];
  final List<_CfbEntry> entries = [];
  late final Uint8List miniStream;

  int u16(int o) => b[o] | (b[o + 1] << 8);
  int u32(int o) => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

  _Cfb(this.b) {
    sectorSize = 1 << u16(0x1E);
    miniSize = 1 << u16(0x20);
    final nFat = u32(0x2C);
    final dir0 = u32(0x30);
    cutoff = u32(0x38);
    final mini0 = u32(0x3C);
    var difatSector = u32(0x44);
    final nDifat = u32(0x48);
    final difat = <int>[for (var i = 0; i < 109; i++) u32(0x4C + 4 * i)];
    for (var k = 0; k < nDifat && difatSector < 0xFFFFFFFA; k++) {
      final off = _off(difatSector);
      final n = sectorSize ~/ 4;
      if (off + sectorSize > b.length) break;
      for (var i = 0; i < n - 1; i++) {
        difat.add(u32(off + 4 * i));
      }
      difatSector = u32(off + 4 * (n - 1));
    }
    for (final d in difat.where((d) => d < 0xFFFFFFFA).take(nFat)) {
      final off = _off(d);
      if (off + sectorSize > b.length) continue;
      for (var i = 0; i < sectorSize ~/ 4; i++) {
        fat.add(u32(off + 4 * i));
      }
    }
    for (final s in _chain(mini0)) {
      final off = _off(s);
      for (var i = 0; i < sectorSize ~/ 4; i++) {
        miniFat.add(u32(off + 4 * i));
      }
    }
    final dir = _read(dir0, null);
    for (var i = 0; i + 128 <= dir.length; i += 128) {
      final nameLen = dir[i + 64] | (dir[i + 65] << 8);
      final name = nameLen >= 2 ? _utf16(dir, i, i + nameLen - 2) : '';
      entries.add(_CfbEntry(
          name,
          dir[i + 66],
          dir[i + 116] | (dir[i + 117] << 8) | (dir[i + 118] << 16) | (dir[i + 119] << 24),
          dir[i + 120] | (dir[i + 121] << 8) | (dir[i + 122] << 16) | (dir[i + 123] << 24)));
    }
    miniStream = entries.isEmpty ? Uint8List(0) : _read(entries[0].start, entries[0].size);
  }

  int _off(int sector) => (sector + 1) * sectorSize;

  List<int> _chain(int start) {
    final out = <int>[];
    var s = start;
    while (s < 0xFFFFFFFA && s < fat.length && out.length < 2000000) {
      out.add(s);
      s = fat[s];
    }
    if (fat.isEmpty && start < 0xFFFFFFFA) out.add(start);
    return out;
  }

  Uint8List _read(int start, int? size) {
    final out = BytesBuilder(copy: false);
    for (final s in _chain(start)) {
      final o = _off(s);
      if (o >= b.length) break;
      out.add(b.sublist(o, o + sectorSize > b.length ? b.length : o + sectorSize));
      if (size != null && out.length >= size) break;
    }
    final all = out.takeBytes();
    return size == null || all.length <= size ? all : all.sublist(0, size);
  }

  Uint8List? stream(String name) {
    for (final e in entries) {
      if (e.type == 2 && e.name.toLowerCase() == name.toLowerCase()) {
        if (e.size < cutoff) {
          final out = BytesBuilder(copy: false);
          var s = e.start;
          var n = 0;
          while (s < 0xFFFFFFFA && n++ < 1000000) {
            final o = s * miniSize;
            if (o + miniSize > miniStream.length) break;
            out.add(miniStream.sublist(o, o + miniSize));
            if (s >= miniFat.length) break;
            s = miniFat[s];
          }
          final all = out.takeBytes();
          return all.length <= e.size ? all : all.sublist(0, e.size);
        }
        return _read(e.start, e.size);
      }
    }
    return null;
  }
}

class _CfbEntry {
  final String name;
  final int type, start, size;
  const _CfbEntry(this.name, this.type, this.start, this.size);
}

ExtractedDoc _fromOle(Uint8List b, String ext) {
  final c = _Cfb(b);
  if (c.stream('WordDocument') != null) return _doc(c);
  if (c.stream('Workbook') != null || c.stream('Book') != null) return _xls(c);
  if (c.stream('PowerPoint Document') != null) return _ppt(c);
  if (c.entries.any((e) => e.name.startsWith('__substg1.0_'))) return _msg(c);
  if (c.entries.any((e) => e.name == 'EncryptedPackage')) {
    return const ExtractedDoc(format: 'Protected document',
        note: 'This document is password-protected, so its contents cannot be shown.');
  }
  return _fallbackText(b, ext);
}

ExtractedDoc _doc(_Cfb c) {
  final wd = c.stream('WordDocument')!;
  int u16(Uint8List d, int o) => d[o] | (d[o + 1] << 8);
  int u32(Uint8List d, int o) => d[o] | (d[o + 1] << 8) | (d[o + 2] << 16) | (d[o + 3] << 24);
  final flags = u16(wd, 0x0A);
  if (flags & 0x0100 != 0) {
    return const ExtractedDoc(format: 'Word document',
        note: 'This document is password-protected, so its contents cannot be shown.');
  }
  final table = c.stream(flags & 0x0200 != 0 ? '1Table' : '0Table');
  if (table == null) return _fallbackText(wd, 'doc');
  final csw = u16(wd, 32);
  var o = 34 + csw * 2;
  final cslw = u16(wd, o);
  final lw = o + 2;
  final ccpText = u32(wd, lw + 3 * 4);
  final ccpFtn = u32(wd, lw + 4 * 4);
  o = lw + cslw * 4 + 2;
  final fcClx = u32(wd, o + 66 * 4);
  final lcbClx = u32(wd, o + 66 * 4 + 4);
  final clx = table.sublist(fcClx, fcClx + lcbClx);
  var p = 0;
  while (p < clx.length && clx[p] == 1) {
    p += 3 + u16(clx, p + 1);
  }
  if (p >= clx.length || clx[p] != 2) return _fallbackText(wd, 'doc');
  final lcb = u32(clx, p + 1);
  final plc = clx.sublist(p + 5, p + 5 + lcb);
  final n = (lcb - 4) ~/ 12;
  final cps = [for (var i = 0; i <= n; i++) u32(plc, 4 * i)];
  final sb = StringBuffer();
  for (var i = 0; i < n; i++) {
    final pcd = 4 * (n + 1) + 8 * i;
    final fc = u32(plc, pcd + 2);
    final count = cps[i + 1] - cps[i];
    if (fc & 0x40000000 != 0) {
      final st = (fc & 0x3FFFFFFF) ~/ 2;
      sb.write(_cp1252(wd, st, st + count));
    } else {
      sb.write(_utf16(wd, fc, fc + 2 * count));
    }
  }
  final all = sb.toString();
  final mainEnd = ccpText > 0 && ccpText <= all.length ? ccpText : all.length;
  final notesEnd = _clampInt(mainEnd + ccpFtn, mainEnd, all.length);
  final main = _wordFields(all.substring(0, mainEnd));
  final notes = _wordFields(all.substring(mainEnd, notesEnd));

  final blocks = <DocBlock>[];
  void emit(String para) {
    final t = _cleanWord(para);
    final pieces = t.split('\x0c');
    for (var k = 0; k < pieces.length; k++) {
      if (k > 0) blocks.add(const DocBlock(DocBlockType.divider));
      if (pieces[k].trim().isNotEmpty) {
        blocks.add(DocBlock.text(DocBlockType.paragraph, pieces[k].trim()));
      }
    }
  }

  // Table text: each cell ends with \x07 and a row with one more \x07;
  // a paragraph mark right after a row end means the table is over.
  List<List<String>>? rows;
  var row = <String>[];
  final buf = StringBuffer();
  final cellParas = <String>[];
  var lastWasCellEnd = false, afterRowEnd = false;
  void endTable() {
    if (rows == null) return;
    if (row.isNotEmpty) rows!.add(row);
    if (rows!.isNotEmpty) blocks.add(DocBlock(DocBlockType.table, rows: rows!));
    rows = null;
    row = <String>[];
  }

  for (final ch in main.codeUnits) {
    if (ch == 0x07) {
      if (lastWasCellEnd) {
        if (row.isNotEmpty) rows?.add(row);
        row = <String>[];
        lastWasCellEnd = false;
        afterRowEnd = true;
        buf.clear();
        cellParas.clear();
        continue;
      }
      rows ??= [];
      cellParas.add(buf.toString());
      row.add(_cleanWord(cellParas.join('\n')).trim());
      cellParas.clear();
      buf.clear();
      lastWasCellEnd = true;
      afterRowEnd = false;
    } else if (ch == 0x0D) {
      final para = buf.toString();
      buf.clear();
      if (rows != null && !afterRowEnd) {
        cellParas.add(para);
      } else {
        endTable();
        emit(para);
      }
      lastWasCellEnd = false;
      afterRowEnd = false;
    } else {
      buf.writeCharCode(ch);
      lastWasCellEnd = false;
    }
  }
  if (buf.isNotEmpty) {
    if (rows != null && !afterRowEnd) {
      cellParas.add(buf.toString());
    } else {
      endTable();
      emit(buf.toString());
    }
  }
  endTable();
  final noteLines = notes.split('\r').map(_cleanWord).where((s) => s.trim().isNotEmpty).toList();
  if (noteLines.isNotEmpty) {
    blocks.add(const DocBlock(DocBlockType.divider));
    blocks.add(DocBlock.text(DocBlockType.heading, 'Notes', level: 3));
    for (final l in noteLines) {
      blocks.add(DocBlock.text(DocBlockType.paragraph, l.trim()));
    }
  }
  return ExtractedDoc(format: 'Word document (97-2003)', pages: [DocPage('', blocks)]);
}

/// Field codes: \x13 code \x14 result \x15 → result only.
String _wordFields(String t) {
  final out = StringBuffer();
  final modes = <bool>[]; // true = inside code part
  for (final ch in t.codeUnits) {
    if (ch == 0x13) {
      modes.add(true);
    } else if (ch == 0x14) {
      if (modes.isNotEmpty) modes[modes.length - 1] = false;
    } else if (ch == 0x15) {
      if (modes.isNotEmpty) modes.removeLast();
    } else if (!modes.contains(true)) {
      out.writeCharCode(ch);
    }
  }
  return out.toString();
}

int _clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

String _cleanWord(String s) => s
    .replaceAll('\x0b', '\n')
    .replaceAll('\x1e', '-')
    .replaceAll('\x1f', '')
    .replaceAll(RegExp(r'[\x00-\x08\x0e-\x1d]'), '');

ExtractedDoc _xls(_Cfb c) {
  final wb = (c.stream('Workbook') ?? c.stream('Book'))!;
  int u16(Uint8List d, int o) => d[o] | (d[o + 1] << 8);
  int u32(Uint8List d, int o) => d[o] | (d[o + 1] << 8) | (d[o + 2] << 16) | (d[o + 3] << 24);
  double f64(Uint8List d, int o) => ByteData.sublistView(d, o, o + 8).getFloat64(0, Endian.little);
  double rk(Uint8List d, int o) {
    final v = u32(d, o);
    double val;
    if (v & 2 != 0) {
      val = (v.toSigned(32) >> 2).toDouble();
    } else {
      final bd = ByteData(8)..setUint32(4, v & 0xFFFFFFFC, Endian.little);
      val = bd.getFloat64(0, Endian.little);
    }
    return v & 1 != 0 ? val / 100 : val;
  }

  final recs = <MapEntry<int, Uint8List>>[];
  var p = 0;
  while (p + 4 <= wb.length) {
    final t = u16(wb, p), l = u16(wb, p + 2);
    final end = p + 4 + l > wb.length ? wb.length : p + 4 + l;
    recs.add(MapEntry(t, wb.sublist(p + 4, end)));
    p = end;
  }
  var sst = <String>[];
  final names = <String>[];
  final sheets = <Map<int, Map<int, String>>>[];
  Map<int, Map<int, String>>? cur;
  int? pendingRow, pendingCol;
  var filepass = false;
  void put(int r, int col, String v) {
    if (cur == null || r >= _maxRows || col >= _maxCols) return;
    (cur![r] ??= {})[col] = v;
  }

  for (var i = 0; i < recs.length; i++) {
    final t = recs[i].key;
    final d = recs[i].value;
    switch (t) {
      case 0x2F:
        filepass = true;
        break;
      case 0x85: // BOUNDSHEET
        if (d.length > 8) {
          final len = d[6], f = d[7];
          names.add(f & 1 != 0 ? _utf16(d, 8, 8 + 2 * len) : _cp1252(d, 8, 8 + len));
        }
        break;
      case 0xFC: // SST (+ CONTINUE)
        final parts = <Uint8List>[d];
        var j = i + 1;
        while (j < recs.length && recs[j].key == 0x3C) {
          parts.add(recs[j].value);
          j++;
        }
        sst = _readSst(parts, u32(d, 4));
        break;
      case 0x809: // BOF
        if (d.length >= 4 && u16(d, 2) == 0x10) {
          cur = {};
          sheets.add(cur!);
        }
        break;
      case 0x0A: // EOF
        cur = null;
        break;
      case 0xFD: // LABELSST
        final idx = u32(d, 6);
        put(u16(d, 0), u16(d, 2), idx < sst.length ? sst[idx] : '');
        break;
      case 0x203: // NUMBER
        put(u16(d, 0), u16(d, 2), _num(f64(d, 6).toString()));
        break;
      case 0x27E: // RK
        put(u16(d, 0), u16(d, 2), _num(rk(d, 6).toString()));
        break;
      case 0xBD: // MULRK
        final r = u16(d, 0), c0 = u16(d, 2);
        final n = (d.length - 6) ~/ 6;
        for (var k = 0; k < n; k++) {
          put(r, c0 + k, _num(rk(d, 4 + 6 * k + 2).toString()));
        }
        break;
      case 0x204: // LABEL
        final len = u16(d, 6);
        final f = d.length > 8 ? d[8] : 0;
        put(u16(d, 0), u16(d, 2),
            f & 1 != 0 ? _utf16(d, 9, 9 + 2 * len) : _cp1252(d, 9, 9 + len));
        break;
      case 0x06: // FORMULA (cached result)
        if (d.length >= 14) {
          if (u16(d, 12) != 0xFFFF) {
            put(u16(d, 0), u16(d, 2), _num(f64(d, 6).toString()));
          } else if (d[6] == 0) {
            pendingRow = u16(d, 0);
            pendingCol = u16(d, 2);
          } else if (d[6] == 1) {
            put(u16(d, 0), u16(d, 2), d[8] != 0 ? 'TRUE' : 'FALSE');
          }
        }
        break;
      case 0x207: // STRING (formula text result)
        if (pendingRow != null && d.length >= 3) {
          final len = u16(d, 0), f = d[2];
          put(pendingRow!, pendingCol!,
              f & 1 != 0 ? _utf16(d, 3, 3 + 2 * len) : _cp1252(d, 3, 3 + len));
          pendingRow = null;
        }
        break;
    }
  }
  if (filepass) {
    return const ExtractedDoc(format: 'Spreadsheet (97-2003)',
        note: 'This workbook is password-protected, so its contents cannot be shown.');
  }
  final pages = <DocPage>[];
  for (var s = 0; s < sheets.length; s++) {
    final rows = _gridRows(sheets[s]);
    pages.add(DocPage(s < names.length ? names[s] : 'Sheet ${s + 1}',
        [if (rows.isNotEmpty) DocBlock(DocBlockType.table, rows: rows)],
        isSheet: true));
  }
  return ExtractedDoc(format: 'Spreadsheet (97-2003)', pages: pages);
}

List<String> _readSst(List<Uint8List> parts, int total) {
  final out = <String>[];
  var pi = 0;
  var buf = parts[0];
  var p = 8;
  int u16() => buf[p] | (buf[p + 1] << 8);
  int u32() => buf[p] | (buf[p + 1] << 8) | (buf[p + 2] << 16) | (buf[p + 3] << 24);
  bool next() {
    if (pi + 1 >= parts.length) return false;
    pi++;
    buf = parts[pi];
    p = 0;
    return true;
  }

  for (var n = 0; n < total && n < 200000; n++) {
    if (p + 3 > buf.length && !next()) break;
    final cch = u16();
    final flags = buf[p + 2];
    p += 3;
    var rich = 0, ext = 0;
    if (flags & 8 != 0) {
      rich = u16();
      p += 2;
    }
    if (flags & 4 != 0) {
      ext = u32();
      p += 4;
    }
    var wide = flags & 1 != 0;
    final sb = StringBuffer();
    var left = cch;
    while (left > 0) {
      if (p >= buf.length) {
        if (!next()) break;
        wide = buf[0] & 1 != 0;
        p = 1;
      }
      final avail = (buf.length - p) ~/ (wide ? 2 : 1);
      final take = avail < left ? avail : left;
      if (take <= 0) {
        p = buf.length;
        continue;
      }
      sb.write(wide ? _utf16(buf, p, p + 2 * take) : _cp1252(buf, p, p + take));
      p += wide ? 2 * take : take;
      left -= take;
    }
    out.add(sb.toString());
    var skip = rich * 4 + ext;
    while (skip > 0) {
      if (p >= buf.length && !next()) break;
      final k = buf.length - p < skip ? buf.length - p : skip;
      p += k;
      skip -= k;
    }
  }
  return out;
}

ExtractedDoc _ppt(_Cfb c) {
  final d = c.stream('PowerPoint Document')!;
  int u16(int o) => d[o] | (d[o + 1] << 8);
  int u32(int o) => d[o] | (d[o + 1] << 8) | (d[o + 2] << 16) | (d[o + 3] << 24);
  final slides = <List<DocBlock>>[];
  var textType = 1;

  // Text of each slide lives in SlideListWithText (instance 0) as atoms
  // separated by SlidePersistAtom markers.
  void walk(int a, int b, {required bool inSlideList}) {
    var p = a;
    while (p + 8 <= b) {
      final verInst = u16(p);
      final type = u16(p + 2);
      final len = u32(p + 4);
      final s = p + 8;
      final e = s + len > b ? b : s + len;
      final instance = verInst >> 4;
      if (verInst & 0xF == 0xF) {
        if (type == 0x0FF0) {
          if (instance == 0) walk(s, e, inSlideList: true);
        } else {
          walk(s, e, inSlideList: inSlideList);
        }
      } else if (inSlideList) {
        if (type == 0x03F3) {
          slides.add(<DocBlock>[]);
        } else if (type == 0x0F9F && e - s >= 4) {
          textType = u32(s);
        } else if ((type == 0x0FA0 || type == 0x0FA8) && slides.isNotEmpty) {
          final text = type == 0x0FA0 ? _utf16(d, s, e) : _cp1252(d, s, e);
          final isTitle = textType == 0 || textType == 6;
          final lines = text.split(RegExp('[\r\x0b]')).where((l) => l.trim().isNotEmpty).toList();
          for (var k = 0; k < lines.length; k++) {
            slides.last.add(isTitle && k == 0
                ? DocBlock.text(DocBlockType.heading, lines[k].trim(), level: 2)
                : DocBlock.text(isTitle ? DocBlockType.paragraph : DocBlockType.bullet, lines[k].trim()));
          }
        }
      }
      p = e;
    }
  }

  walk(0, d.length, inSlideList: false);
  final pages = <DocPage>[
    for (var i = 0; i < slides.length; i++) DocPage('Slide ${i + 1}', slides[i]),
  ];
  if (pages.every((p) => p.blocks.isEmpty)) return _fallbackText(d, 'ppt');
  return ExtractedDoc(format: 'Slides (97-2003)', pages: pages);
}

ExtractedDoc _msg(_Cfb c) {
  String? prop(String id) {
    final u = c.stream('__substg1.0_${id}001F');
    if (u != null) return _utf16(u, 0, u.length).replaceAll('\x00', '');
    final a = c.stream('__substg1.0_${id}001E');
    if (a != null) return _cp1252(a, 0, a.length).replaceAll('\x00', '');
    return null;
  }

  final subject = prop('0037') ?? '(no subject)';
  final from = prop('0C1A') ?? prop('0042');
  final to = prop('0E04');
  final body = prop('1000') ?? '';
  final blocks = <DocBlock>[
    DocBlock.text(DocBlockType.heading, subject, level: 2),
    if (from != null) DocBlock(DocBlockType.paragraph, spans: [const DocSpan('From: ', bold: true), DocSpan(from)]),
    if (to != null) DocBlock(DocBlockType.paragraph, spans: [const DocSpan('To: ', bold: true), DocSpan(to)]),
    const DocBlock(DocBlockType.divider),
    for (final p in body.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n')))
      if (p.trim().isNotEmpty) DocBlock.text(DocBlockType.paragraph, p.trim()),
  ];
  return ExtractedDoc(format: 'Outlook message', pages: [DocPage('', blocks)]);
}
