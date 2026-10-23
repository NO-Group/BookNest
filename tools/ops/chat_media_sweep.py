#!/usr/bin/env python3
"""Deletes chat media older than 30 days from Cloudinary (WhatsApp model).

Chat photos, videos, voice notes and files are only *relayed* through
Cloudinary: after 30 days they live on readers' phones and in each reader's
own Google Drive backup (Settings → Chat backup → media), not on BookNest's
storage. Text messages are backed up separately (sealed) in MongoDB.

ONLY these folders are touched — never avatars, profile covers, book covers,
club images or manuscripts:
    booknest/chat/    (chat photos)
    booknest/files/   (files, videos, voice notes, smoke-test files)

Env: CLOUDINARY_CLOUD_NAME (default deqdmwlt7), CLOUDINARY_API_KEY,
CLOUDINARY_API_SECRET. Optional: RETENTION_DAYS (default 30), DRY_RUN=1.
Writes ops/chat-media-sweep.md (counts only, no secrets, no file names).
"""
from __future__ import annotations

import base64
import datetime as dt
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

CLOUD = os.environ.get('CLOUDINARY_CLOUD_NAME') or 'deqdmwlt7'
KEY = os.environ.get('CLOUDINARY_API_KEY', '')
SECRET = os.environ.get('CLOUDINARY_API_SECRET', '')
DAYS = int(os.environ.get('RETENTION_DAYS') or 30)
DRY = os.environ.get('DRY_RUN') == '1'
PREFIXES = ('booknest/chat/', 'booknest/files/')
TYPES = ('image', 'video', 'raw')
REPORT = Path('ops/chat-media-sweep.md')
lines: list[str] = []


def note(t: str):
    print(t, flush=True)
    lines.append(t)


def call(method: str, path: str, params: list[tuple[str, str]] | None = None):
    url = f'https://api.cloudinary.com/v1_1/{CLOUD}/{path}'
    data = None
    q = urllib.parse.urlencode(params or [])
    url += ('?' + q) if q else ''
    auth = base64.b64encode(f'{KEY}:{SECRET}'.encode()).decode()
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={'Authorization': f'Basic {auth}'})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read().decode() or '{}')
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode() or '{}')
        except Exception:  # noqa: BLE001
            return e.code, {}


def finish(code: int):
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text('\n'.join(lines) + '\n')
    sys.exit(code)


def main():
    now = dt.datetime.now(dt.timezone.utc)
    cutoff = now - dt.timedelta(days=DAYS)
    note(f'# Chat media sweep — {now:%Y-%m-%d %H:%M} UTC')
    note('')
    note(f'Deletes Cloudinary chat media older than **{DAYS} days** from `booknest/chat/` and '
         '`booknest/files/` only. Readers keep their media on their phones and in their own '
         'Google Drive backup.' + (' **Dry run — nothing deleted.**' if DRY else ''))
    note('')
    if not KEY or not SECRET:
        note('⚠️ **Not configured.** Add GitHub secrets `CLOUDINARY_API_KEY` and '
             '`CLOUDINARY_API_SECRET` (Cloudinary → Settings → API Keys). Nothing was deleted.')
        finish(0)
    total_del = 0
    total_keep = 0
    failed = False
    for rtype in TYPES:
        for prefix in PREFIXES:
            cursor = ''
            old_ids: list[str] = []
            kept = 0
            while True:
                params = [('type', 'upload'), ('prefix', prefix), ('max_results', '500')]
                if cursor:
                    params.append(('next_cursor', cursor))
                status, body = call('GET', f'resources/{rtype}', params)
                if status == 401:
                    note('❌ Cloudinary refused the API key/secret (HTTP 401). Check the two secrets.')
                    finish(1)
                if status != 200:
                    note(f'- ⚠️ list {rtype} `{prefix}` → HTTP {status}: {str(body.get("error", ""))[:120]}')
                    failed = True
                    break
                # With a prefix Cloudinary sorts by public id, not date —
                # check every asset's created_at.
                for res in body.get('resources', []):
                    try:
                        created = dt.datetime.fromisoformat(
                            str(res.get('created_at', '')).replace('Z', '+00:00'))
                    except ValueError:
                        kept += 1
                        continue
                    if created < cutoff:
                        old_ids.append(res['public_id'])
                    else:
                        kept += 1
                cursor = body.get('next_cursor') or ''
                if not cursor:
                    break
            deleted = 0
            for i in range(0, len(old_ids), 100):
                batch = old_ids[i:i + 100]
                if DRY:
                    deleted += len(batch)
                    continue
                status, body = call('DELETE', f'resources/{rtype}/upload',
                                    [('public_ids[]', pid) for pid in batch] + [('invalidate', 'true')])
                if status != 200:
                    note(f'- ⚠️ delete {rtype} batch → HTTP {status}: {str(body.get("error", ""))[:120]}')
                    failed = True
                    break
                deleted += sum(1 for v in (body.get('deleted') or {}).values() if v == 'deleted')
            if old_ids or kept:
                note(f'- {rtype:5} `{prefix}` — deleted **{deleted}**, newer than {DAYS} days kept: {kept}')
            total_del += deleted
            total_keep += kept
    note('')
    note(f'**{"Would delete" if DRY else "Deleted"} {total_del} chat files older than {DAYS} days.**')
    status, body = call('GET', 'usage')
    if status == 200:
        st = body.get('storage', {}) or {}
        used = st.get('usage')
        if isinstance(used, (int, float)):
            note(f'Cloudinary storage now: {used / 1048576:.1f} MB.')
    finish(1 if failed else 0)


if __name__ == '__main__':
    main()
