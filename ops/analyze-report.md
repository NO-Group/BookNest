# flutter analyze — 2026-11-01T15:03Z · ff3f1cf

Flutter 3.47.9 • channel stable • https://github.com/flutter/flutter.git

Exit 1 · **17 errors · 109 warnings · 725 infos**

## Errors
```text
error • The method '_easeInCubic' isn't defined for the type '_PageFlipLoaderState'. Try correcting the name to the name of an existing method, or defining a method named '_easeInCubic' • lib/presentation/components/page_flip_loader.dart:98:18 • undefined_method
error • The method '_easeInCubic' isn't defined for the type '_PageFlipLoaderState'. Try correcting the name to the name of an existing method, or defining a method named '_easeInCubic' • lib/presentation/components/page_flip_loader.dart:103:16 • undefined_method
error • The method '_easeInCubic' isn't defined for the type '_PageFlipLoaderState'. Try correcting the name to the name of an existing method, or defining a method named '_easeInCubic' • lib/presentation/components/page_flip_loader.dart:108:19 • undefined_method
error • A value of type 'List<Offset>' can't be assigned to a variable of type 'Color'. Try changing the type of the variable, or casting the right-hand type to 'Color' • lib/presentation/components/page_flip_loader.dart:212:56 • invalid_assignment
error • A value of type 'List<Offset>' can't be assigned to a variable of type 'Color'. Try changing the type of the variable, or casting the right-hand type to 'Color' • lib/presentation/components/page_flip_loader.dart:213:56 • invalid_assignment
error • Undefined name 'air'. Try correcting the name to one that is defined, or defining the name • lib/presentation/components/page_flip_loader.dart:328:51 • undefined_identifier
error • The getter 'initialLocation' isn't defined for the type 'GoRouter'. Try importing the library that defines 'initialLocation', correcting the name to the name of an existing getter, or defining a getter or field named 'initialLocation' • test/widget_test.dart:31:22 • undefined_getter
error • Target of URI doesn't exist: 'doc_extract.dart'. Try creating the file referenced by the URI, or try using a URI for a file that does exist • tool/doc_check/check.dart:7:8 • uri_does_not_exist
error • Undefined class 'ExtractedDoc'. Try changing the name to the name of an existing class, or creating a class with the name 'ExtractedDoc' • tool/doc_check/check.dart:43:13 • undefined_class
error • Undefined name 'DocBlockType'. Try correcting the name to one that is defined, or defining the name • tool/doc_check/check.dart:54:14 • undefined_identifier
error • Undefined name 'DocBlockType'. Try correcting the name to one that is defined, or defining the name • tool/doc_check/check.dart:57:14 • undefined_identifier
error • Undefined name 'DocBlockType'. Try correcting the name to one that is defined, or defining the name • tool/doc_check/check.dart:60:14 • undefined_identifier
error • Undefined name 'DocBlockType'. Try correcting the name to one that is defined, or defining the name • tool/doc_check/check.dart:65:14 • undefined_identifier
error • Undefined name 'DocBlockType'. Try correcting the name to one that is defined, or defining the name • tool/doc_check/check.dart:68:14 • undefined_identifier
error • The function 'sniffKind' isn't defined. Try importing the library that defines 'sniffKind', correcting the name to the name of an existing function, or defining a function named 'sniffKind' • tool/doc_check/check.dart:90:18 • undefined_function
error • Undefined class 'ExtractedDoc'. Try changing the name to the name of an existing class, or creating a class with the name 'ExtractedDoc' • tool/doc_check/check.dart:92:5 • undefined_class
error • The function 'extractDocument' isn't defined. Try importing the library that defines 'extractDocument', correcting the name to the name of an existing function, or defining a function named 'extractDocument' • tool/doc_check/check.dart:95:13 • undefined_function
```

## Warnings
```text
warning • Unused import: '../presentation/screens/auth/suspend_gate_screen.dart'. Try removing the import directive • lib/config/router.dart:54:8 • unused_import
warning • The value of the field '_loaded' isn't used. Try removing the field, or using it • lib/presentation/components/booknest_keyboard.dart:69:8 • unused_field
warning • Unused import: 'package:intl/intl.dart'. Try removing the import directive • lib/presentation/components/booknest_ui.dart:7:8 • unused_import
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/presentation/components/chat_kit.dart:1320:49 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/presentation/components/chat_kit.dart:1331:45 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/presentation/components/chat_kit.dart:1340:34 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/presentation/components/chat_kit.dart:1356:45 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/presentation/components/chat_kit.dart:1358:43 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/presentation/components/chat_kit.dart:1359:36 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/presentation/components/chat_kit.dart:1360:36 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/presentation/components/chat_kit.dart:1362:32 • unnecessary_non_null_assertion
warning • The value of the local variable 'dot' isn't used. Try removing the variable or using it • lib/presentation/components/chat_kit.dart:1971:15 • unused_local_variable
warning • The declaration '_leanDeg' isn't referenced. Try removing the declaration of '_leanDeg' • lib/presentation/components/page_flip_loader.dart:101:17 • unused_element
warning • The declaration '_trail01' isn't referenced. Try removing the declaration of '_trail01' • lib/presentation/components/page_flip_loader.dart:106:17 • unused_element
warning • The value of the field 'coverL' isn't used. Try removing the field, or using it • lib/presentation/components/page_flip_loader.dart:151:22 • unused_field
warning • The value of the field 'coverR' isn't used. Try removing the field, or using it • lib/presentation/components/page_flip_loader.dart:152:22 • unused_field
warning • The operand can't be 'null', so the condition is always 'true'. Remove the condition • lib/presentation/components/page_flip_loader.dart:437:36 • unnecessary_null_comparison
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/presentation/components/page_flip_loader.dart:444:31 • unnecessary_non_null_assertion
warning • Unused import: 'dart:convert'. Try removing the import directive • lib/presentation/components/post_extras.dart:1:8 • unused_import
warning • Unused import: 'package:http/http.dart'. Try removing the import directive • lib/presentation/components/post_extras.dart:4:8 • unused_import
warning • The value of the local variable 'dark' isn't used. Try removing the variable or using it • lib/presentation/components/report_sheet.dart:99:11 • unused_local_variable
warning • Unused import: '../../config/theme.dart'. Try removing the import directive • lib/presentation/components/skeleton_kit.dart:3:8 • unused_import
warning • Unused import: 'package:go_router/go_router.dart'. Try removing the import directive • lib/presentation/screens/books/book_analytics_screen.dart:2:8 • unused_import
warning • The value of the field '_editStatus' isn't used. Try removing the field, or using it • lib/presentation/screens/books/book_editor_screen.dart:79:11 • unused_field
warning • The value of the field '_publishedChapters' isn't used. Try removing the field, or using it • lib/presentation/screens/books/book_editor_screen.dart:90:7 • unused_field
warning • The receiver can't be null, so the null-aware operator '?.' is unnecessary. Try replacing the operator '?.' with '.' • lib/presentation/screens/books/book_editor_screen.dart:878:49 • invalid_null_aware_operator
warning • The name BookNestLoader is shown, but isn't used. Try removing the name from the list of shown members • lib/presentation/screens/books/books_library_screen.dart:9:60 • unused_shown_name
warning • The name kBookNestGenres is shown, but isn't used. Try removing the name from the list of shown members • lib/presentation/screens/books/books_library_screen.dart:9:85 • unused_shown_name
warning • Unused import: '../../../services/backend_api.dart'. Try removing the import directive • lib/presentation/screens/books/chapter_manager_screen.dart:6:8 • unused_import
warning • Unnecessary cast. Try removing the cast • lib/presentation/screens/books/genre_browse_screen.dart:36:19 • unnecessary_cast
warning • Unused import: '../../../services/supabase_service.dart'. Try removing the import directive • lib/presentation/screens/books/manage_book_screen.dart:9:8 • unused_import
warning • Unused import: '../../../services/supabase_service.dart'. Try removing the import directive • lib/presentation/screens/books/publish_details_screen.dart:12:8 • unused_import
warning • The declaration '_viewerId' isn't referenced. Try removing the declaration of '_viewerId' • lib/presentation/screens/books/reviews_hub_screen.dart:22:15 • unused_element
warning • Unnecessary cast. Try removing the cast • lib/presentation/screens/books/reviews_hub_screen.dart:37:19 • unnecessary_cast
warning • The declaration '_viewerId' isn't referenced. Try removing the declaration of '_viewerId' • lib/presentation/screens/books/writer_dashboard_screen.dart:21:15 • unused_element
warning • Unnecessary cast. Try removing the cast • lib/presentation/screens/books/writer_dashboard_screen.dart:36:19 • unnecessary_cast
warning • Unused import: 'package:go_router/go_router.dart'. Try removing the import directive • lib/presentation/screens/brainstorm/brainstorm_screen.dart:2:8 • unused_import
warning • Unused import: '../../../services/backend_api.dart'. Try removing the import directive • lib/presentation/screens/chat/media_viewer_screen.dart:18:8 • unused_import
warning • The left operand can't be null, so the right operand is never executed. Try removing the operator and the right operand • lib/presentation/screens/chat/media_viewer_screen.dart:242:23 • dead_null_aware_expression
warning • Unused import: 'package:go_router/go_router.dart'. Try removing the import directive • lib/presentation/screens/chat/shared_content_screen.dart:2:8 • unused_import
warning • Unused import: '../../components/chat_kit.dart'. Try removing the import directive • lib/presentation/screens/chat/shared_content_screen.dart:7:8 • unused_import
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/presentation/screens/chat/video_preview_screen.dart:143:39 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/presentation/screens/chat/video_preview_screen.dart:144:45 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/presentation/screens/chat/video_preview_screen.dart:145:45 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/presentation/screens/chat/video_preview_screen.dart:149:43 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/presentation/screens/chat/video_preview_screen.dart:150:49 • unnecessary_non_null_assertion
warning • The value of the local variable 'client' isn't used. Try removing the variable or using it • lib/presentation/screens/clubs/club_detail_screen.dart:54:11 • unused_local_variable
warning • Unnecessary cast. Try removing the cast • lib/presentation/screens/clubs/club_detail_screen.dart:94:19 • unnecessary_cast
warning • Unused import: '../../../services/supabase_service.dart'. Try removing the import directive • lib/presentation/screens/discover/discover_screen.dart:10:8 • unused_import
warning • Unused import: '../../../config/theme.dart'. Try removing the import directive • lib/presentation/screens/discover/school_detail_screen.dart:3:8 • unused_import
warning • Unused import: '../../../services/backend_api.dart'. Try removing the import directive • lib/presentation/screens/discover/school_detail_screen.dart:4:8 • unused_import
warning • Unused import: '../../components/booknest_ui.dart'. Try removing the import directive • lib/presentation/screens/discover/school_detail_screen.dart:5:8 • unused_import
warning • The value of the field '_loading' isn't used. Try removing the field, or using it • lib/presentation/screens/discover/school_lms.dart:840:8 • unused_field
warning • Unused import: '../../components/booknest_ui.dart'. Try removing the import directive • lib/presentation/screens/dms/dm_list_screen.dart:13:8 • unused_import
warning • The value of the field '_searching' isn't used. Try removing the field, or using it • lib/presentation/screens/dms/dm_list_screen.dart:551:8 • unused_field
warning • The declaration '_viewerId' isn't referenced. Try removing the declaration of '_viewerId' • lib/presentation/screens/library/my_library_screen.dart:33:15 • unused_element
warning • Unnecessary cast. Try removing the cast • lib/presentation/screens/library/my_library_screen.dart:77:19 • unnecessary_cast
warning • Unused import: '../../components/booknest_keyboard.dart'. Try removing the import directive • lib/presentation/screens/profile/profile_screen.dart:17:8 • unused_import
warning • Unused import: '../../../services/supabase_service.dart'. Try removing the import directive • lib/presentation/screens/reader/reader_screen.dart:23:8 • unused_import
warning • The value of the field '_restoredScroll' isn't used. Try removing the field, or using it • lib/presentation/screens/reader/reader_screen.dart:58:8 • unused_field
warning • The value of the field '_pageIndex' isn't used. Try removing the field, or using it • lib/presentation/screens/reader/reader_screen.dart:72:7 • unused_field
warning • Unnecessary cast. Try removing the cast • lib/presentation/screens/reader/reader_screen.dart:161:24 • unnecessary_cast
warning • The value of the local variable 'dark' isn't used. Try removing the variable or using it • lib/presentation/screens/reader/reader_screen.dart:1462:11 • unused_local_variable
warning • The value of the field '_lastSize' isn't used. Try removing the field, or using it • lib/presentation/screens/settings/chat_backup_screen.dart:29:7 • unused_field
warning • Unused import: '../../components/report_sheet.dart'. Try removing the import directive • lib/presentation/screens/support/terms_screen.dart:4:8 • unused_import
warning • Unused import: '../config/app_config.dart'. Try removing the import directive • lib/services/avatar_uploader.dart:5:8 • unused_import
warning • The value of the field '_diskMaxEntryChars' isn't used. Try removing the field, or using it • lib/services/backend_api.dart:80:20 • unused_field
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:748:17 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:748:35 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:749:13 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:786:21 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:786:85 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:800:26 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1146:37 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1146:101 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1154:26 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1171:27 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1176:25 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1176:43 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1177:21 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1258:15 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1258:33 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1259:11 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1285:71 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1286:74 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1288:65 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1379:44 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1380:65 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1396:32 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1402:44 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1403:32 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1407:38 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1427:76 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1428:20 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1435:45 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1436:18 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1553:17 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1553:35 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1554:13 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1659:37 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1660:65 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1672:20 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:1672:47 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:2331:9 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:2359:25 • unnecessary_non_null_assertion
warning • The '!' will have no effect because the receiver can't be null. Try removing the '!' operator • lib/services/doc_extract.dart:2403:25 • unnecessary_non_null_assertion
warning • Returning a 'Future' without 'await' inside a try block. Try adding an 'await' • lib/services/google_desktop_auth.dart:199:7 • unawaited_return_in_try_block
warning • Unnecessary type check; the result is always 'true'. Try correcting the type check, or removing the type check • lib/services/inbox_watcher.dart:266:11 • unnecessary_type_check
warning • Unnecessary type check; the result is always 'false'. Try correcting the type check, or removing the type check • lib/services/typing_broadcaster.dart:44:13 • unnecessary_type_check
```

## Infos by rule
```text
    662 deprecated_member_use
     17 use_build_context_synchronously
     12 curly_braces_in_flow_control_structures
      8 unnecessary_brace_in_string_interps
      7 prefer_interpolation_to_compose_strings
      6 unnecessary_import
      6 no_leading_underscores_for_local_identifiers
      2 strict_top_level_inference
      2 prefer_final_fields
      1 unnecessary_string_interpolations
      1 prefer_iterable_wheretype
      1 prefer_contains
```

## Infos in lib/presentation/screens/discover/school_cbt*
```text
info • The import of 'dart:ui' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/material.dart'. Try removing the import directive • lib/presentation/screens/discover/school_cbt.dart:2:8 • unnecessary_import
info • 'activeColor' is deprecated and shouldn't be used. Use activeThumbColor instead. This feature was deprecated after v3.31.0-2.0.pre. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt.dart:228:25 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt.dart:286:64 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt.dart:319:58 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt.dart:346:34 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt.dart:414:28 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt.dart:417:45 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt.dart:468:54 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt.dart:482:37 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt.dart:739:63 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt.dart:888:36 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt.dart:903:48 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt.dart:906:61 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt.dart:998:35 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt.dart:999:25 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt.dart:1005:31 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt.dart:1017:64 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt.dart:1061:33 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt.dart:1086:63 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt.dart:1115:25 • deprecated_member_use
info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/presentation/screens/discover/school_cbt.dart:1186:16 • use_build_context_synchronously
info • 'activeColor' is deprecated and shouldn't be used. Use activeThumbColor instead. This feature was deprecated after v3.31.0-2.0.pre. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt.dart:1256:33 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt.dart:1273:58 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt.dart:1290:38 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt.dart:1515:34 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt.dart:1528:58 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt.dart:1563:43 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt.dart:1576:54 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt.dart:1582:58 • deprecated_member_use
info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/presentation/screens/discover/school_cbt_authoring.dart:57:11 • use_build_context_synchronously
info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/presentation/screens/discover/school_cbt_authoring.dart:180:14 • use_build_context_synchronously
info • Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check • lib/presentation/screens/discover/school_cbt_authoring.dart:193:14 • use_build_context_synchronously
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_authoring.dart:208:56 • deprecated_member_use
info • 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_authoring.dart:287:11 • deprecated_member_use
info • 'activeColor' is deprecated and shouldn't be used. Use activeThumbColor instead. This feature was deprecated after v3.31.0-2.0.pre. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_authoring.dart:336:9 • deprecated_member_use
info • 'activeColor' is deprecated and shouldn't be used. Use activeThumbColor instead. This feature was deprecated after v3.31.0-2.0.pre. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_authoring.dart:346:9 • deprecated_member_use
info • 'activeColor' is deprecated and shouldn't be used. Use activeThumbColor instead. This feature was deprecated after v3.31.0-2.0.pre. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_authoring.dart:353:9 • deprecated_member_use
info • 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_authoring.dart:360:9 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_authoring.dart:408:49 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_authoring.dart:771:64 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_authoring.dart:806:42 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_authoring.dart:826:53 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_common.dart:216:28 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_common.dart:341:48 • deprecated_member_use
info • 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_common.dart:348:31 • deprecated_member_use
info • 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_common.dart:350:31 • deprecated_member_use
info • 'activeColor' is deprecated and shouldn't be used. Use activeThumbColor instead. This feature was deprecated after v3.31.0-2.0.pre. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_common.dart:448:25 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_common.dart:581:32 • deprecated_member_use
info • 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_practice.dart:173:23 • deprecated_member_use
info • 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_practice.dart:186:23 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_practice.dart:288:66 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_practice.dart:446:56 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_practice.dart:643:36 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_practice.dart:660:46 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_practice.dart:687:57 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_practice.dart:706:28 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_practice.dart:770:30 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_practice.dart:774:38 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_practice.dart:777:31 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_practice.dart:780:34 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_practice.dart:785:34 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_practice.dart:872:67 • deprecated_member_use
info • 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement • lib/presentation/screens/discover/school_cbt_practice.dart:884:56 • deprecated_member_use
```
