# MongoDB storage

| db | collection | docs | data MB | storage MB | index MB |
|---|---|---|---|---|---|
| books | chapters | 18724 | 503.77 | 353.18 | 1.02 |
| books | books | 1589 | 1.24 | 0.58 | 0.45 |
| social | book_bookmarks | 1 | 0 | 0.04 | 0.11 |
| reviews | reviews | 1 | 0 | 0.04 | 0.11 |
| chats | conversations | 4 | 0 | 0.04 | 0.11 |
| chats | messages | 20 | 0.01 | 0.04 | 0.07 |
| social | book_likes | 1 | 0 | 0.04 | 0.07 |
| social | user_stats | 2 | 0 | 0.04 | 0.07 |
| social | post_likes | 2 | 0 | 0.04 | 0.07 |
| social | follows | 1 | 0 | 0.04 | 0.07 |
| social | book_views | 3 | 0 | 0.04 | 0.07 |
| reviews | comments | 1 | 0 | 0.04 | 0.07 |
| notifications | notifications | 19 | 0 | 0.04 | 0.07 |
| users | dm_keys | 2 | 0 | 0.04 | 0.07 |
| users | profile_extras | 1 | 0 | 0.04 | 0.07 |
| users | user_prefs | 5 | 0 | 0.04 | 0.07 |
| feed | brainstorms | 1 | 0 | 0.04 | 0.07 |
| feed | post_views | 57 | 0.01 | 0.04 | 0.04 |
| books | meta | 1 | 0 | 0.04 | 0.04 |
| feed | posts | 7 | 0 | 0.04 | 0.04 |
| groups | clubs | 3 | 0 | 0.04 | 0.04 |
| groups | clubs_members | 1 | 0 | 0.04 | 0.04 |
| social | reader_progress | 0 | 0 | 0 | 0.01 |
| users | push_tokens | 0 | 0 | 0 | 0.01 |
| users | link_passes | 0 | 0 | 0 | 0.01 |
| moderation | admin_log | 0 | 0 | 0 | 0.01 |
| moderation | reports | 0 | 0 | 0 | 0.01 |
| moderation | blocks | 0 | 0 | 0 | 0.01 |
| moderation | bans | 0 | 0 | 0 | 0.01 |
| genres | genres | 0 | 0 | 0 | 0.01 |
| payments | orders | 0 | 0 | 0 | 0.01 |
| payments | subscriptions | 0 | 0 | 0 | 0.01 |

Total data+index: 508.0 MB

## Chapters

```
{
 "_id": null,
 "total": 18724,
 "inline": 18106,
 "inlineBytes": 525027187,
 "cdn": 0,
 "pointers": 618,
 "inlineMB": 500.7,
 "inlineBookCount": 1586,
 "inlineLibraryBooks": 1584
}
```
