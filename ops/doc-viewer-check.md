# Document viewer check — 2026-11-01 15:09 UTC · Dart SDK version: 3.13.7 (stable) (Thu Oct 22 14:28:57 2026 -0700) on "linux_x64"

## archive ^3.6.1 ()
# Document viewer check — 24/24 files OK

### ✅ book.epub — kind `document`, 18 ms
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
### ✅ bundle.tar.gz — kind `document`, 10 ms
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
### ✅ data.json — kind `document`, 5 ms
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
### ✅ legacy-table.doc — kind `document`, 4 ms
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
### ✅ modern.docx — kind `document`, 39 ms
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
### ✅ modern.xlsx — kind `document`, 5 ms
```text
Spreadsheet
--- page: Readers (sheet)
| Name | Books | Joined |  | Total
| Ada | 12 | 2024-03-05 |  | 
| Chidi | 3.5 | 2025-01-31 |  | 
--- page: Second (sheet)
| hello from sheet two

```
### ✅ mystery.bin — kind `document`, 2 ms
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
### ✅ tiny.mobi — kind `document`, 2 ms
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
# Document viewer check — 24/24 files OK

### ✅ book.epub — kind `document`, 20 ms
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
### ✅ bundle.tar.gz — kind `document`, 9 ms
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
### ✅ data.json — kind `document`, 4 ms
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
### ✅ legacy-table.doc — kind `document`, 4 ms
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
[h2] This is the title on page 2
[bullet] This is page two
[bullet] It has several blocks of text
[bullet] None of them have formatting

```
### ✅ legacy.xls — kind `document`, 5 ms
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
### ✅ modern.docx — kind `document`, 47 ms
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
### ✅ modern.odp — kind `document`, 3 ms
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
### ✅ modern.odt — kind `document`, 1 ms
```text
Document
--- page: 
[h1] ODT Heading
Open document with **bold span**
[bullet] odt bullet
| k | v
| x | 1

```
### ✅ modern.pptx — kind `document`, 4 ms
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
### ✅ modern.xlsx — kind `document`, 6 ms
```text
Spreadsheet
--- page: Readers (sheet)
| Name | Books | Joined |  | Total
| Ada | 12 | 2024-03-05 |  | 
| Chidi | 3.5 | 2025-01-31 |  | 
--- page: Second (sheet)
| hello from sheet two

```
### ✅ mystery.bin — kind `document`, 3 ms
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
### ✅ tiny.mobi — kind `document`, 2 ms
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
