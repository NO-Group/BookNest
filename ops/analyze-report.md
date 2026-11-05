# flutter analyze — 2026-11-05T17:34Z · f69a747

Flutter 3.47.9 • channel stable • https://github.com/flutter/flutter.git

Exit 0 · **0 errors · 11 warnings · 82 infos**

## Errors
```text
```

## Warnings
```text
warning • The value of the field '_loaded' isn't used. Try removing the field, or using it • lib/presentation/components/booknest_keyboard.dart:69:8 • unused_field
warning • The value of the field '_editStatus' isn't used. Try removing the field, or using it • lib/presentation/screens/books/book_editor_screen.dart:79:11 • unused_field
warning • The value of the field '_publishedChapters' isn't used. Try removing the field, or using it • lib/presentation/screens/books/book_editor_screen.dart:90:7 • unused_field
warning • The left operand can't be null, so the right operand is never executed. Try removing the operator and the right operand • lib/presentation/screens/chat/media_viewer_screen.dart:241:23 • dead_null_aware_expression
warning • The value of the field '_loading' isn't used. Try removing the field, or using it • lib/presentation/screens/discover/school_lms.dart:605:8 • unused_field
warning • The value of the field '_searching' isn't used. Try removing the field, or using it • lib/presentation/screens/dms/dm_list_screen.dart:573:8 • unused_field
warning • The value of the field '_restoredScroll' isn't used. Try removing the field, or using it • lib/presentation/screens/reader/reader_screen.dart:57:8 • unused_field
warning • The value of the field '_pageIndex' isn't used. Try removing the field, or using it • lib/presentation/screens/reader/reader_screen.dart:71:7 • unused_field
warning • The value of the field '_lastSize' isn't used. Try removing the field, or using it • lib/presentation/screens/settings/chat_backup_screen.dart:29:7 • unused_field
warning • The value of the field '_diskMaxEntryChars' isn't used. Try removing the field, or using it • lib/services/backend_api.dart:80:20 • unused_field
warning • Unnecessary type check; the result is always 'true'. Try correcting the type check, or removing the type check • lib/services/inbox_watcher.dart:266:11 • unnecessary_type_check
```

## Infos by rule
```text
     26 deprecated_member_use
     12 use_build_context_synchronously
     12 curly_braces_in_flow_control_structures
      8 unnecessary_brace_in_string_interps
      7 prefer_interpolation_to_compose_strings
      6 no_leading_underscores_for_local_identifiers
      5 unnecessary_import
      2 strict_top_level_inference
      2 prefer_final_fields
      1 unnecessary_string_interpolations
      1 prefer_iterable_wheretype
```

## Infos in lib/presentation/screens/discover/school_cbt*
```text
```

## flutter test (exit 0)
```text
00:00 +0: loading /home/runner/work/BookNest/BookNest/test/widget_test.dart
00:00 +0: Brand theme dark theme: near-black background, cyan accents
00:00 +1: Brand theme light theme: white background, same brand colours
00:00 +2: CBT import (Excel / CSV paste) tab-separated rows from Excel, header skipped
00:00 +3: CBT import (Excel / CSV paste) CSV with quotes, commas inside a cell, answer given as text
00:00 +4: CBT import (Excel / CSV paste) empty options + empty answer = theory question
00:00 +5: CBT import (Excel / CSV paste) bad rows are reported, good rows kept
00:00 +6: countdown formatting
00:00 +7: All tests passed!
```
