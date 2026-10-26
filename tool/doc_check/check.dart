// CI check for lib/services/doc_extract.dart: opens every fixture in
// test/fixtures/docs and verifies the expected text comes out.
//   dart run check.dart <fixtures dir>
import 'dart:io';
import 'dart:typed_data';

import 'doc_extract.dart';

const expectations = <String, List<String>>{
  'modern.docx': ['Word document', 'BookNest Test Document', 'Chapter One', 'bold words', 'First bullet', 'Dune', '412', '<tags>', '[image]', '[h1]', '[bullet]'],
  'modern.xlsx': ['Spreadsheet', 'Readers', 'Ada', '2024-03-05', '3.5', 'Total', 'hello from sheet two', 'Second'],
  'modern.pptx': ['Slides', 'Welcome to BookNest', 'Slide one subtitle', 'Second slide', 'Point B', '[image]'],
  'modern.odt': ['ODT Heading', 'bold span', 'odt bullet', '| x | 1'],
  'modern.ods': ['Spreadsheet', 'Budget', 'Books', '2500'],
  'modern.odp': ['Slides', 'ODP slide text'],
  'book.epub': ['E-book (EPUB)', 'Chapter I', 'bright', 'thirteen', 'Chapter II', 'two', '| 1 | 2', '[image]'],
  'letter.rtf': ['Dear reader', 'café', '€', 'Second paragraph'],
  'page.html': ['Web page', 'HTML Title', 'emphasis', 'a < b'],
  'data.csv': ['Ada', 'He said "hi", twice', 'Abuja'],
  'data.json': ['"c": "d"'],
  'fiction.fb2': ['Part One', 'Once upon a', 'time'],
  'bundle.zip': ['readme.txt', 'folder/data.csv'],
  'bundle.tar.gz': ['inner.txt'],
  'single.txt.gz': ['gzipped plain text'],
  'tiny.mobi': ['Mobi Title', 'Hello mobi hello mobi world.'],
  'mystery.bin': ['Readable secret sentence inside binary'],
  'unknown.xyz': ['A text file with a strange extension.'],
  'utf16.txt': ['UTF-16 text ✓'],
  'legacy.doc': ['I am a test document', 'This is page two', 'It’s also in blue'],
  'legacy-table.doc': ['Word 97', '| Cell 1,1 | Cell 1,2 | Cell 1,3', 'Cell 2,3', 'This text is below the table.'],
  'legacy.xls': ['First Sheet', 'Test spreadsheet', '2nd row 2nd column', 'Sheet Number 2', 'cb=sum', '13'],
  'legacy.ppt': ['Slides', 'This is a test title', 'This is on page 1', 'This is the title on page 2', '!page: Slide 3', '!formattingT'],
};

const kinds = <String, String>{
  'notes.md': 'markdown',
  'modern.docx': 'document',
  'legacy.doc': 'document',
  'tiny.mobi': 'document',
  'mystery.bin': 'document',
};

String dump(ExtractedDoc d) {
  final sb = StringBuffer('${d.format}\n');
  if (d.title != null) sb.writeln('title: ${d.title}');
  if (d.note != null) sb.writeln('note: ${d.note}');
  for (final e in d.entries) {
    sb.writeln('entry: ${e.name} (${e.size})');
  }
  for (final p in d.pages) {
    sb.writeln('--- page: ${p.title}${p.isSheet ? ' (sheet)' : ''}');
    for (final b in p.blocks) {
      switch (b.type) {
        case DocBlockType.heading:
          sb.writeln('[h${b.level}] ${b.text}');
          break;
        case DocBlockType.bullet:
          sb.writeln('[bullet] ${b.text}');
          break;
        case DocBlockType.table:
          for (final r in b.rows) {
            sb.writeln('| ${r.join(' | ')}');
          }
          break;
        case DocBlockType.image:
          sb.writeln('[image] ${b.image?.length} bytes');
          break;
        case DocBlockType.divider:
          sb.writeln('[hr]');
          break;
        default:
          final styled = b.spans.map((s) => s.bold ? '**${s.text}**' : (s.italic ? '_${s.text}_' : s.text)).join();
          sb.writeln(styled);
      }
    }
  }
  return sb.toString();
}

void main(List<String> args) {
  final dir = Directory(args.isEmpty ? 'test/fixtures/docs' : args.first);
  var failures = 0;
  final report = StringBuffer();
  final files = dir.listSync().whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final name = f.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1);
    final bytes = Uint8List.fromList(f.readAsBytesSync());
    final kind = sniffKind(bytes, ext);
    final sw = Stopwatch()..start();
    ExtractedDoc doc;
    String out;
    try {
      doc = extractDocument(bytes, ext);
      out = dump(doc);
    } catch (e, st) {
      out = 'CRASH $e\n$st';
    }
    final missing = <String>[];
    for (final want in expectations[name] ?? const <String>[]) {
      if (want.startsWith('!')) {
        if (out.contains(want.substring(1))) missing.add('NOT ${want.substring(1)}');
      } else if (!out.contains(want)) {
        missing.add(want);
      }
    }
    final wantKind = kinds[name];
    if (wantKind != null && wantKind != kind) missing.add('kind=$wantKind (got $kind)');
    if (out.startsWith('CRASH')) missing.add('no crash');
    final ok = missing.isEmpty;
    if (!ok) failures++;
    report.writeln('### ${ok ? '✅' : '❌'} $name — kind `$kind`, ${sw.elapsedMilliseconds} ms');
    if (!ok) report.writeln('missing: ${missing.map((m) => '`$m`').join(', ')}');
    report.writeln('```text');
    final lines = out.split('\n');
    report.writeln(lines.take(30).join('\n').replaceAll('```', "'''"));
    if (lines.length > 30) report.writeln('… ${lines.length - 30} more lines');
    report.writeln('```');
  }
  stdout.writeln('# Document viewer check — ${files.length - failures}/${files.length} files OK\n');
  stdout.write(report);
  exitCode = failures == 0 ? 0 : 1;
}
