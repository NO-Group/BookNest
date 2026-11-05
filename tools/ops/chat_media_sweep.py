#!/usr/bin/env python3
"""Daily chat media housekeeping — runs ON THE SERVER (ops.mediaSweep).

The edge function uses its own Supabase secrets (CLOUDINARY_API_KEY /
CLOUDINARY_API_SECRET, R2_*), so no Cloudinary keys live in GitHub:
  • Cloudinary: chat photos (booknest/chat) and pre-2.38 chat files
    (booknest/files) older than 30 days. Avatars, covers, profile covers and
    book images are in other folders and never touched.
  • Cloudflare R2: chat files in relay/ older than 3 days (documents, PDFs,
    videos, voice notes), and makes sure the bucket's 3-day lifecycle rule
    exists.
Readers keep their media on their devices and in their own Google Drive.
Writes ops/chat-media-sweep.md (counts only).
"""
from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request

FN = os.environ['FN_URL']
ANON = os.environ['ANON']
SERVICE = os.environ['SERVICE_KEY']
DRY = os.environ.get('DRY_RUN', '') == '1'


def call(body: dict, timeout: int = 160):
    req = urllib.request.Request(FN, data=json.dumps(body).encode(), method='POST', headers={
        'Content-Type': 'application/json', 'apikey': ANON, 'Authorization': f'Bearer {SERVICE}'})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read() or b'{}')
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b'{}')
        except Exception:
            return e.code, {}


def main():
    lines = [f"# Chat media sweep — {time.strftime('%Y-%m-%d %H:%M', time.gmtime())} UTC", '',
             'Runs on the server with its own Cloudinary and R2 keys. Chat **photos** leave Cloudinary after **30 days**; '
             'chat **files, voice notes and videos** leave the private R2 relay after **3 days**. '
             'Readers keep them on their devices and in their own Google Drive.', '']
    status, body = call({'action': 'ops.mediaSweep', 'payload': {'dryRun': DRY}})
    data = body.get('data') or {}
    if status != 200 or not body.get('ok'):
        lines.append(f"❌ Server answered HTTP {status}: {body.get('error') or body}")
        open('ops/chat-media-sweep.md', 'w').write('\n'.join(lines) + '\n')
        print('\n'.join(lines))
        raise SystemExit(1)
    if DRY:
        lines.append('_Dry run — nothing deleted._')
    relay = data.get('relay') or {}
    lines.append('## Cloudflare R2 relay (3 days)')
    if not relay.get('configured'):
        lines.append('- ⚠️ R2 is not configured on the server')
    else:
        lines.append(f"- lifecycle rule: {relay.get('lifecycle')}")
        lines.append(f"- files scanned: {relay.get('scanned')}, expired: {relay.get('expired')}, deleted: {relay.get('deleted')}")
        lines.append(f"- live relay size: {round((relay.get('bytesLive') or 0) / 1048576, 1)} MB")
        if relay.get('error'):
            lines.append(f"- error: {relay['error']}")
    cl = data.get('cloudinary') or {}
    lines.append('')
    lines.append('## Cloudinary (chat folders only, 30 days)')
    if not cl.get('configured'):
        lines.append('- ⚠️ CLOUDINARY_API_KEY / CLOUDINARY_API_SECRET missing on the server')
    else:
        for name, s in (cl.get('folders') or {}).items():
            extra = f" — {s['error']}" if s.get('error') else ''
            part = ' (continues tomorrow)' if s.get('partial') else ''
            lines.append(f"- `{name}`: scanned {s.get('scanned')}, older than 30 days {s.get('old')}, deleted {s.get('deleted')}{part}{extra}")
    open('ops/chat-media-sweep.md', 'w').write('\n'.join(lines) + '\n')
    print('\n'.join(lines))


if __name__ == '__main__':
    main()
