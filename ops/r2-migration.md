# Book texts → R2

- mode: migrate · 2026-10-21T20:08:16.884676+00:00 → 2026-10-21T20:20:30.650204+00:00
- plan: {"inline": 18722, "cdn": 0, "r2": 0, "github": 0, "empty": 0, "inline_MB": 507.9, "member_rows_untouched": 2, "manifest_entries": 0, "missing_rows_to_repair": 0}
- copied: 618
- copy_failures: 0
- manifest: "manifests/library-chapters-20261021T201325Z.jsonl"
- repoint: {"written": 618, "deleted": 618, "rejected": 0, "still_pending": 0}
- mongo_total_MB: 507.9

| db | collection | docs | data MB | index MB |
|---|---|---|---|---|
| books | chapters | 18724 | 503.77 | 1.02 |
| books | books | 1589 | 1.24 | 0.45 |
| social | book_bookmarks | 1 | 0 | 0.11 |
| reviews | reviews | 1 | 0 | 0.11 |
| chats | conversations | 4 | 0 | 0.11 |
| chats | messages | 20 | 0.01 | 0.07 |
| social | book_likes | 1 | 0 | 0.07 |
| social | user_stats | 2 | 0 | 0.07 |

## Live check
- {"book": "bulk-don-quixote|miguel-de-1547-1616-ormsby-john-1829-1895-translator-cervantes-saavedra", "ch": 188, "match": true, "bytes": 19323}
- {"book": "bulk-les-mis-rables|victor-1802-1885-hapgood-isabel-florence-1850-1928-translator-hugo", "ch": 265, "match": true, "bytes": 6203}
- {"book": "bulk-don-quixote|miguel-de-1547-1616-ormsby-john-1829-1895-translator-cervantes-saavedra", "ch": 115, "match": true, "bytes": 25716}
- {"book": "bulk-les-mis-rables|victor-1802-1885-hapgood-isabel-florence-1850-1928-translator-hugo", "ch": 112, "match": true, "bytes": 4043}
- {"book": "bulk-don-quixote|miguel-de-1547-1616-ormsby-john-1829-1895-translator-cervantes-saavedra", "ch": 171, "match": true, "bytes": 14452}
- {"book": "bulk-les-mis-rables|victor-1802-1885-hapgood-isabel-florence-1850-1928-translator-hugo", "ch": 190, "match": true, "bytes": 4033}
- {"book": "bulk-don-quixote|miguel-de-1547-1616-ormsby-john-1829-1895-translator-cervantes-saavedra", "ch": 43, "match": true, "bytes": 46}
- {"book": "bulk-les-mis-rables|victor-1802-1885-hapgood-isabel-florence-1850-1928-translator-hugo", "ch": 166, "match": true, "bytes": 17383}

## Errors
- repoint: you are over your space quota, using 513 MB of 512 MB. Writes are blocked on your cluster. Free up storage by deleting unnecessary data or add storage by updating cluster tier. Add a payment method an
- repoint: you are over your space quota, using 513 MB of 512 MB. Writes are blocked on your cluster. Free up storage by deleting unnecessary data or add storage by updating cluster tier. Add a payment method an
- repoint: you are over your space quota, using 513 MB of 512 MB. Writes are blocked on your cluster. Free up storage by deleting unnecessary data or add storage by updating cluster tier. Add a payment method an
