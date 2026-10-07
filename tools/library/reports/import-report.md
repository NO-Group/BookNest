# Library import report

- Started 2026-10-07T06:05:05.302184Z · finished 2026-10-07T06:18:11.983022Z
- Copyright rule: every author/translator died ≤ 1955 (life + 70)

## SE
- repos: 5
- unreadable: 0
- copyright: 2
- no_chapters: 0
- ok: 3
- replacing_existing: 2
- posted: 3
- imported: 0
- unchanged_or_skipped: 3

## GT
- scanned: 5
- no_repo: 0
- copyright: 0
- dup: 0
- text_fail: 0
- migrated: 5
- new: 0
- fail_reasons: {}
- existing_not_matched: 1566
- posted: 5
- imported: 0
- unchanged_or_skipped: 5

Excluded for copyright: 2
- Siddhartha — Hermann Hesse, Gunther Olesch, Anke Dreher, Amy Coulter, Stefan Langer, Semyon Chaichenets
- The Mysterious Affair at Styles — Agatha Christie

## Live read-through check
- bulk-dubliners|james-joyce ch 1: RuntimeError('books.chapter failed: HTTP 404: {"ok":false,"error":"Chapter not found"}')
- bulk-dubliners|james-joyce ch 15: RuntimeError('books.chapter failed: HTTP 404: {"ok":false,"error":"Chapter not found"}')
- bulk-the-strange-case-of-dr-jekyll-and-mr-hyde|robert-louis-1850-1894-stevenson ch 1: 139222 chars in 4047 ms — '[Illustration]\n\n\nThe Strange Case of\nDr. Jekyll and Mr. Hyde\n\nby Robert Louis Stevenson\n\n\n'
- bulk-the-strange-case-of-dr-jekyll-and-mr-hyde|robert-louis-1850-1894-stevenson ch 10: RuntimeError('books.chapter failed: HTTP 404: {"ok":false,"error":"Chapter not found"}')
- bulk-the-lost-world|arthur-conan-1859-1930-doyle ch 1: 380000 chars in 4064 ms — 'THE LOST WORLD\n\n                   I have wrought my simple plan\n                    If I '
- bulk-the-lost-world|arthur-conan-1859-1930-doyle ch 18: RuntimeError('books.chapter failed: HTTP 404: {"ok":false,"error":"Chapter not found"}')
- bulk-pride-and-prejudice|jane-1775-1817-austen ch 1: 4742 chars in 3325 ms — 'It is a truth universally acknowledged, that a single man in possession\nof a good fortune '
- bulk-pride-and-prejudice|jane-1775-1817-austen ch 61: 7417 chars in 3309 ms — '[Illustration]\n\nHappy for all her maternal feelings was the day on which Mrs. Bennet got\nr'
- bulk-moby-dick-or-the-whale|herman-1819-1891-melville ch 1: 380000 chars in 5921 ms — 'MOBY-DICK;\n                                   OR,\n                               THE WHALE'
- bulk-moby-dick-or-the-whale|herman-1819-1891-melville ch 41: RuntimeError('books.chapter failed: HTTP 404: {"ok":false,"error":"Chapter not found"}')
- bulk-frankenstein-or-the-modern-prometheus|mary-wollstonecraft-1797-1851-shelley ch 1: 10142 chars in 3290 ms — 'I am by birth a Genevese, and my family is one of the most\ndistinguished of that republic.'
- bulk-frankenstein-or-the-modern-prometheus|mary-wollstonecraft-1797-1851-shelley ch 25: RuntimeError('books.chapter failed: HTTP 404: {"ok":false,"error":"Chapter not found"}')
