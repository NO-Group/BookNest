# Document viewer check — 2026-10-23 08:48 UTC · Dart SDK version: 3.13.7 (stable) (Thu Oct 22 14:28:57 2026 -0700) on "linux_x64"

## archive ^3.6.1 ()
```text
warning - doc_extract.dart:574:38 - Unnecessary cast. Try removing the cast. - unnecessary_cast
warning - doc_extract.dart:689:36 - Unnecessary cast. Try removing the cast. - unnecessary_cast
warning - doc_extract.dart:746:17 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:746:35 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:747:13 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:784:21 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:784:85 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:798:26 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1144:37 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1144:101 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1152:26 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1169:27 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1174:25 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1174:43 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1175:21 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1247:20 - The value of the local variable 'gridCol' isn't used. Try removing the variable or using it. - unused_local_variable
warning - doc_extract.dart:1256:15 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1256:33 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1257:11 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1283:71 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1284:74 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1286:65 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1377:44 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1378:65 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1395:32 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1401:44 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1402:32 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1406:38 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1426:76 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1427:20 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1434:45 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1435:18 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1553:17 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1553:35 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1554:13 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1659:37 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1660:65 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1672:20 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1672:47 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:2331:9 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
```
# Document viewer check — 24/24 files OK

### ✅ book.epub — kind `document`, 13 ms
```text
E-book (EPUB)
title: Tiny Epub
--- page: Chapter I
[h1] Chapter I
It was a **bright** cold day & the clocks were striking thirteen.
[image] 72 bytes
--- page: Chapter II
[h2] Chapter II
[bullet] one
[bullet] two
| a | b
| 1 | 2

```
### ✅ bundle.tar.gz — kind `document`, 6 ms
```text
Archive (.tar.gz)
entry: inner.txt (14)

```
### ✅ bundle.zip — kind `document`, 0 ms
```text
Archive (.zip)
entry: folder/data.csv (8)
entry: readme.txt (25)

```
### ✅ data.csv — kind `document`, 1 ms
```text
Spreadsheet (CSV)
--- page:  (sheet)
| name | city | quote
| Ada | Lagos | He said "hi", twice
| Chidi | Abuja | ok

```
### ✅ data.json — kind `document`, 3 ms
```text
JSON
--- page: 
{
  "b": [
    1,
    2,
    {
      "c": "d"
    }
  ],
  "a": true
}

```
### ✅ fiction.fb2 — kind `document`, 0 ms
```text
E-book (FB2)
title: FB Book
--- page: 
[h2] Part One
Once upon a _time_.

```
### ✅ legacy-table.doc — kind `document`, 3 ms
```text
Word document (97-2003)
--- page: 
This is a Word document that was created using Word 97 – SR2.  It contains a paragraph, a table consisting of 2 rows and 3 columns and a final paragraph.
| Cell 1,1 | Cell 1,2 | Cell 1,3
| Cell 2,1 | Cell 2,2 | Cell 2,3
This text is below the table.

```
### ✅ legacy.doc — kind `document`, 0 ms
```text
Word document (97-2003)
--- page: 
I am a test document
This is page 1
I am Calibri (Body) in font size 11
[hr]
This is page two
It’s Arial Black in 16 point
It’s also in blue

```
### ✅ legacy.ppt — kind `document`, 1 ms
```text
Slides (97-2003)
--- page: Slide 1
[h2] This is a test title
[bullet] This is a test subtitle
[bullet] This is on page 1
--- page: Slide 2
[h2] This is a test title
[bullet] This is a test subtitle
[bullet] This is on page 1
--- page: Slide 3
[h2] This is the title on page 2
[bullet] This is page two
[bullet] It has several blocks of text
[bullet] None of them have formattingT
--- page: Slide 4
[h2] This is a test title
[bullet] This is a test subtitle
[bullet] This is on page 1
--- page: Slide 5
[h2] This is the title on page 2
[bullet] This is page two
[bullet] It has several blocks of text
[bullet] None of them have formatting

```
### ✅ legacy.xls — kind `document`, 3 ms
```text
Spreadsheet (97-2003)
--- page: First Sheet (sheet)
| Test spreadsheet | 
| 2nd row | 2nd row 2nd column
| This one is red | 
--- page: Sheet Number 2 (sheet)
| Start of 2nd sheet |  |  | 
| Sheet 2 row 2 |  |  | 
| I'm in bold blue, on a yellow background |  |  | 
| cb=1 | cb=10 | cb=2 | cb=sum
| 1 | 10 | 2 | 13
--- page: Sheet3 (sheet)

```
### ✅ letter.rtf — kind `document`, 1 ms
```text
Rich text (RTF)
--- page: 
Dear reader,
This is bold RTF with an accent: café and unicode € euro.
Second paragraph.

```
### ✅ modern.docx — kind `document`, 29 ms
```text
Word document
--- page: 
[h1] BookNest Test Document
[h1] Chapter One
Plain start, **bold words** and _italic words_.
[bullet] First bullet
[bullet] Second bullet
| Name | Pages
| Dune | 412
[image] 72 bytes
After the table — naïve café “quotes” & <tags>.

```
### ✅ modern.odp — kind `document`, 2 ms
```text
Slides
--- page: Intro
ODP slide text

```
### ✅ modern.ods — kind `document`, 0 ms
```text
Spreadsheet
--- page: Budget (sheet)
| Item | Cost
| Books | 2500

```
### ✅ modern.odt — kind `document`, 0 ms
```text
Document
--- page: 
[h1] ODT Heading
Open document with **bold span**
[bullet] odt bullet
| k | v
| x | 1

```
### ✅ modern.pptx — kind `document`, 2 ms
```text
Slides
--- page: Slide 1
[h2] Welcome to BookNest
Slide one subtitle
--- page: Slide 2
[h2] Second slide
Point A
Point B
[image] 72 bytes

```
### ✅ modern.xlsx — kind `document`, 4 ms
```text
Spreadsheet
--- page: Readers (sheet)
| Name | Books | Joined |  | Total
| Ada | 12 | 2024-03-05 |  | 
| Chidi | 3.5 | 2025-01-31 |  | 
--- page: Second (sheet)
| hello from sheet two

```
### ✅ mystery.bin — kind `document`, 1 ms
```text
BIN file
note: No page layout for .BIN — here is the readable text found inside.
--- page: 
!"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~
!"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~
!"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~
!"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~
¡¢£¤¥¦§¨©ª«¬­®¯°±²³´µ¶·¸¹º»¼½¾¿ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖ×ØÙÚÛÜÝÞßàáâãäåæçèéêëìíîïðñòóôõö÷øùúûüýþÿReadable secret sentence inside binary
!"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~

```
### ✅ notes.md — kind `markdown`, 0 ms
```text
Text
--- page: 
# Notes
- item **one**
- item two

```
### ✅ page.html — kind `document`, 0 ms
```text
Web page
title: Page
--- page: 
[h1] HTML Title
Some _emphasis_ and a < b comparison.
Line
break

```
### ✅ single.txt.gz — kind `document`, 0 ms
```text
Text
--- page: 
gzipped plain text

```
### ✅ tiny.mobi — kind `document`, 1 ms
```text
E-book (MOBI)
title: Tiny Mobi
--- page: 
[h1] Mobi Title
Hello mobi hello mobi world.

```
### ✅ unknown.xyz — kind `document`, 0 ms
```text
Text
--- page: 
A text file with a strange extension.
Second line.

```
### ✅ utf16.txt — kind `document`, 0 ms
```text
TXT file
--- page: 
UTF-16 text ✓

```

## archive ^4.0.0 ()
```text
warning - doc_extract.dart:746:17 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:746:35 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:747:13 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:784:21 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:784:85 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:798:26 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1144:37 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1144:101 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1152:26 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1169:27 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1174:25 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1174:43 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1175:21 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1247:20 - The value of the local variable 'gridCol' isn't used. Try removing the variable or using it. - unused_local_variable
warning - doc_extract.dart:1256:15 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1256:33 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1257:11 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1283:71 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1284:74 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1286:65 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1377:44 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1378:65 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1395:32 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1401:44 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1402:32 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1406:38 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1426:76 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1427:20 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1434:45 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1435:18 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1553:17 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1553:35 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1554:13 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1659:37 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1660:65 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1672:20 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:1672:47 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:2331:9 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:2359:25 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - doc_extract.dart:2403:25 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
```
# Document viewer check — 24/24 files OK

### ✅ book.epub — kind `document`, 13 ms
```text
E-book (EPUB)
title: Tiny Epub
--- page: Chapter I
[h1] Chapter I
It was a **bright** cold day & the clocks were striking thirteen.
[image] 72 bytes
--- page: Chapter II
[h2] Chapter II
[bullet] one
[bullet] two
| a | b
| 1 | 2

```
### ✅ bundle.tar.gz — kind `document`, 4 ms
```text
Archive (.tar.gz)
entry: inner.txt (14)

```
### ✅ bundle.zip — kind `document`, 0 ms
```text
Archive (.zip)
entry: folder/data.csv (8)
entry: readme.txt (25)

```
### ✅ data.csv — kind `document`, 0 ms
```text
Spreadsheet (CSV)
--- page:  (sheet)
| name | city | quote
| Ada | Lagos | He said "hi", twice
| Chidi | Abuja | ok

```
### ✅ data.json — kind `document`, 3 ms
```text
JSON
--- page: 
{
  "b": [
    1,
    2,
    {
      "c": "d"
    }
  ],
  "a": true
}

```
### ✅ fiction.fb2 — kind `document`, 0 ms
```text
E-book (FB2)
title: FB Book
--- page: 
[h2] Part One
Once upon a _time_.

```
### ✅ legacy-table.doc — kind `document`, 3 ms
```text
Word document (97-2003)
--- page: 
This is a Word document that was created using Word 97 – SR2.  It contains a paragraph, a table consisting of 2 rows and 3 columns and a final paragraph.
| Cell 1,1 | Cell 1,2 | Cell 1,3
| Cell 2,1 | Cell 2,2 | Cell 2,3
This text is below the table.

```
### ✅ legacy.doc — kind `document`, 0 ms
```text
Word document (97-2003)
--- page: 
I am a test document
This is page 1
I am Calibri (Body) in font size 11
[hr]
This is page two
It’s Arial Black in 16 point
It’s also in blue

```
### ✅ legacy.ppt — kind `document`, 1 ms
```text
Slides (97-2003)
--- page: Slide 1
[h2] This is a test title
[bullet] This is a test subtitle
[bullet] This is on page 1
--- page: Slide 2
[h2] This is a test title
[bullet] This is a test subtitle
[bullet] This is on page 1
--- page: Slide 3
[h2] This is the title on page 2
[bullet] This is page two
[bullet] It has several blocks of text
[bullet] None of them have formattingT
--- page: Slide 4
[h2] This is a test title
[bullet] This is a test subtitle
[bullet] This is on page 1
--- page: Slide 5
[h2] This is the title on page 2
[bullet] This is page two
[bullet] It has several blocks of text
[bullet] None of them have formatting

```
### ✅ legacy.xls — kind `document`, 4 ms
```text
Spreadsheet (97-2003)
--- page: First Sheet (sheet)
| Test spreadsheet | 
| 2nd row | 2nd row 2nd column
| This one is red | 
--- page: Sheet Number 2 (sheet)
| Start of 2nd sheet |  |  | 
| Sheet 2 row 2 |  |  | 
| I'm in bold blue, on a yellow background |  |  | 
| cb=1 | cb=10 | cb=2 | cb=sum
| 1 | 10 | 2 | 13
--- page: Sheet3 (sheet)

```
### ✅ letter.rtf — kind `document`, 1 ms
```text
Rich text (RTF)
--- page: 
Dear reader,
This is bold RTF with an accent: café and unicode € euro.
Second paragraph.

```
### ✅ modern.docx — kind `document`, 30 ms
```text
Word document
--- page: 
[h1] BookNest Test Document
[h1] Chapter One
Plain start, **bold words** and _italic words_.
[bullet] First bullet
[bullet] Second bullet
| Name | Pages
| Dune | 412
[image] 72 bytes
After the table — naïve café “quotes” & <tags>.

```
### ✅ modern.odp — kind `document`, 2 ms
```text
Slides
--- page: Intro
ODP slide text

```
### ✅ modern.ods — kind `document`, 0 ms
```text
Spreadsheet
--- page: Budget (sheet)
| Item | Cost
| Books | 2500

```
### ✅ modern.odt — kind `document`, 0 ms
```text
Document
--- page: 
[h1] ODT Heading
Open document with **bold span**
[bullet] odt bullet
| k | v
| x | 1

```
### ✅ modern.pptx — kind `document`, 2 ms
```text
Slides
--- page: Slide 1
[h2] Welcome to BookNest
Slide one subtitle
--- page: Slide 2
[h2] Second slide
Point A
Point B
[image] 72 bytes

```
### ✅ modern.xlsx — kind `document`, 4 ms
```text
Spreadsheet
--- page: Readers (sheet)
| Name | Books | Joined |  | Total
| Ada | 12 | 2024-03-05 |  | 
| Chidi | 3.5 | 2025-01-31 |  | 
--- page: Second (sheet)
| hello from sheet two

```
### ✅ mystery.bin — kind `document`, 1 ms
```text
BIN file
note: No page layout for .BIN — here is the readable text found inside.
--- page: 
!"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~
!"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~
!"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~
!"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~
¡¢£¤¥¦§¨©ª«¬­®¯°±²³´µ¶·¸¹º»¼½¾¿ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖ×ØÙÚÛÜÝÞßàáâãäåæçèéêëìíîïðñòóôõö÷øùúûüýþÿReadable secret sentence inside binary
!"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~

```
### ✅ notes.md — kind `markdown`, 0 ms
```text
Text
--- page: 
# Notes
- item **one**
- item two

```
### ✅ page.html — kind `document`, 0 ms
```text
Web page
title: Page
--- page: 
[h1] HTML Title
Some _emphasis_ and a < b comparison.
Line
break

```
### ✅ single.txt.gz — kind `document`, 0 ms
```text
Text
--- page: 
gzipped plain text

```
### ✅ tiny.mobi — kind `document`, 1 ms
```text
E-book (MOBI)
title: Tiny Mobi
--- page: 
[h1] Mobi Title
Hello mobi hello mobi world.

```
### ✅ unknown.xyz — kind `document`, 0 ms
```text
Text
--- page: 
A text file with a strange extension.
Second line.

```
### ✅ utf16.txt — kind `document`, 0 ms
```text
TXT file
--- page: 
UTF-16 text ✓

```
