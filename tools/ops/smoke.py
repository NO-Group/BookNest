#!/usr/bin/env python3
"""End-to-end production smoke test against the LIVE BookNest backend.

Creates two throw-away accounts, then:
  • reads the library (books.list + a chapter served from Cloudflare R2),
  • DM: A opens a chat with B, sends messages, B reads them, both list chats,
  • calls: asks the server for ICE servers (TURN relay must be present) and
    proves the relay really allocates and carries packets (coturn's
    turnutils_uclient over UDP, TCP and TLS/443),
  • deletes both accounts through the app's own account.delete action.

Env: FN_URL ANON SUPABASE_URL SERVICE_KEY. Writes ops/smoke-report.md.
Nothing here prints tokens or passwords.
"""
from __future__ import annotations

import base64
import gzip
import json
import os
import random
import re
import secrets
import shutil
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

FN = os.environ['FN_URL']
ANON = os.environ['ANON']
SUPA = os.environ['SUPABASE_URL'].rstrip('/')
SERVICE = os.environ['SERVICE_KEY']
lines: list[str] = []
results: dict[str, bool] = {}


def note(text: str):
    print(text, flush=True)
    lines.append(text)


def check(name: str, ok: bool, detail: str = ''):
    results[name] = ok
    note(f"- {'✅' if ok else '❌'} **{name}**{' — ' + detail if detail else ''}")


def http(method: str, url: str, body=None, headers=None, timeout=40):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        'Content-Type': 'application/json', **(headers or {})})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw else {}), time.time() - t0
    except urllib.error.HTTPError as e:
        raw = e.read().decode('utf-8', 'replace')
        try:
            return e.code, json.loads(raw), time.time() - t0
        except Exception:
            return e.code, {'raw': raw[:300]}, time.time() - t0


def api(token: str | None, action: str, payload: dict | None = None):
    status, body, secs = http('POST', FN, {'action': action, 'payload': payload or {}}, {
        'Authorization': f'Bearer {token or ANON}', 'apikey': ANON, 'x-region': 'eu-west-1'})
    return status, body, secs


def raw_api(token: str, body: dict):
    """Like the app's HTTP client: asks for gzip, returns wire size too."""
    req = urllib.request.Request(FN, data=json.dumps(body).encode(), method='POST', headers={
        'Content-Type': 'application/json', 'Accept-Encoding': 'gzip',
        'Authorization': f'Bearer {token}', 'apikey': ANON, 'x-region': 'eu-west-1'})
    with urllib.request.urlopen(req, timeout=60) as r:
        wire = r.read()
        enc = (r.headers.get('Content-Encoding') or '').lower()
    plain = gzip.decompress(wire) if enc == 'gzip' else wire
    return json.loads(plain), len(wire), len(plain), enc


def kb(n: int) -> str:
    return f'{n / 1024:.1f} KB' if n >= 1024 else f'{n} B'


def make_user(tag: str):
    email = f'smoke-{int(time.time())}-{tag}-{secrets.token_hex(3)}@example.com'
    password = secrets.token_urlsafe(18)
    s, b, _ = http('POST', f'{SUPA}/auth/v1/admin/users',
                   {'email': email, 'password': password, 'email_confirm': True,
                    'user_metadata': {'username': f'smoke_{tag}_{secrets.token_hex(2)}'}},
                   {'apikey': SERVICE, 'Authorization': f'Bearer {SERVICE}'})
    if s not in (200, 201):
        raise RuntimeError(f'create user {tag}: HTTP {s} {str(b)[:200]}')
    uid = b.get('id') or b.get('user', {}).get('id')
    s, b, _ = http('POST', f'{SUPA}/auth/v1/token?grant_type=password',
                   {'email': email, 'password': password}, {'apikey': ANON})
    if s != 200:
        raise RuntimeError(f'sign in {tag}: HTTP {s} {str(b)[:200]}')
    return uid, b['access_token']


def admin_delete(uid: str):
    http('DELETE', f'{SUPA}/auth/v1/admin/users/{uid}', None,
         {'apikey': SERVICE, 'Authorization': f'Bearer {SERVICE}'})


def turn_probe(servers: list[dict]):
    """Allocate a relay and push packets through it (client-to-client)."""
    if not shutil.which('turnutils_uclient'):
        check('TURN relay carries traffic', False, 'turnutils_uclient not installed')
        return
    def pick(pattern):
        return next((s for s in servers if re.search(pattern, s.get('urls', ''))), None)
    probes = [('UDP 3478', r'^turn:.*:3478\?transport=udp', []),
              ('TCP 3478', r'^turn:.*:3478\?transport=tcp', ['-t']),
              ('TLS 443', r'^turns:.*:443', ['-t', '-S'])]
    for label, pattern, flags in probes:
        s = pick(pattern)
        if not s:
            note(f'  - {label}: no such relay offered')
            continue
        m = re.match(r'^turns?:([^:?]+):(\d+)', s['urls'])
        host, port = m.group(1), m.group(2)
        cmd = ['turnutils_uclient', *flags, '-y', '-n', '20', '-m', '1', '-l', '120',
               '-u', s['username'], '-w', s['credential'], '-p', port, host]
        try:
            out = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            text = out.stdout + out.stderr
        except subprocess.TimeoutExpired:
            text = 'timeout'
        lost = re.search(r'Total lost packets (\d+) \(([\d.]+)%\)', text)
        good = bool(lost) and float(lost.group(2)) < 50
        detail = (f'lost {lost.group(1)} packets ({lost.group(2)}%)' if lost
                  else (re.findall(r'.*(?:error|ERROR|fail).*', text)[:2] or [text.strip()[-160:]]))
        check(f'TURN relay carries traffic ({label})', good, str(detail)[:220])


def relay_roundtrip(token: str, name: str, data: bytes, mime: str):
    """Sends a chat file exactly like the app (2.38+): the server signs an
    upload to the private R2 relay (relay.sign), the file goes straight to
    R2, and the signed download link — what the message carries — must give
    the same bytes back. Chat files never touch Cloudinary."""
    s, b, _ = api(token, 'relay.sign', {'name': name, 'size': len(data)})
    d = b.get('data') or {}
    if s != 200 or not d.get('putUrl'):
        return False, f"relay.sign HTTP {s} {b.get('error') or ''}"[:200]
    try:
        req = urllib.request.Request(d['putUrl'], data=data, method='PUT', headers={'Content-Type': mime})
        with urllib.request.urlopen(req, timeout=60) as r:
            put = r.status
    except urllib.error.HTTPError as e:
        return False, f"upload HTTP {e.code}: {e.read().decode('utf-8', 'replace')[:160]}"
    try:
        with urllib.request.urlopen(d['getUrl'], timeout=60) as r:
            got = r.read()
            ctype = r.headers.get('Content-Type')
    except urllib.error.HTTPError as e:
        return False, f'download HTTP {e.code}'
    host = d['getUrl'].split('/')[2].split('.')[1:3]
    return got == data, (f"upload HTTP {put}, download {len(got)} bytes ({ctype}), {'.'.join(host)}, "
                         f"expires {d.get('expiresAt', '?')[:10]}") + ('' if got == data else ' (content differs)')


def tiny_files():
    import io
    import zipfile
    pdf = (b'%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n'
           b'3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n')
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>')
        z.writestr('word/document.xml', '<?xml version="1.0"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>BookNest smoke</w:t></w:r></w:p></w:body></w:document>')
    return pdf, buf.getvalue()


def main():
    note(f"# Production smoke test — {time.strftime('%Y-%m-%d %H:%M', time.gmtime())} UTC")
    note('')
    note('Two throw-away accounts exercise the live backend exactly like the app does, then delete themselves.')
    note('')
    users: list[tuple[str, str]] = []
    try:
        a_id, a_tok = make_user('a')
        users.append((a_id, a_tok))
        b_id, b_tok = make_user('b')
        users.append((b_id, b_tok))
        check('Sign-up and sign-in', True, 'two accounts created and signed in')
    except Exception as e:
        check('Sign-up and sign-in', False, str(e)[:240])
        return finish(users)

    # ── server + library ──
    s, b, secs = api(None, 'ping')
    d = b.get('data', {})
    check('Server answers', s == 200 and d.get('mongo') == 'ready',
          f"server {d.get('server')}, database {d.get('mongo')}, {secs:.2f}s, region {d.get('timing', {}).get('fnRegion')}")
    s, b, secs = api(a_tok, 'books.list', {'limit': 20})
    books = b.get('data', {}).get('books', [])
    check('Library loads', s == 200 and len(books) > 0, f'{len(books)} books in {secs:.2f}s')
    lib = [x for x in books if str(x.get('id', '')).startswith('bulk-')] or books
    if lib:
        book = random.choice(lib)
        s, b, secs = api(a_tok, 'books.chapter', {'bookId': book['id'], 'chapterNumber': 1})
        text = b.get('data', {}).get('content', '') or ''
        check('Book chapter opens (text from Cloudflare R2)', s == 200 and len(text) > 50,
              f"“{book.get('title', '')[:40]}” ch.1: {len(text):,} chars in {secs:.2f}s")

    # ── messaging ──
    s, b, _ = api(a_tok, 'dm.ensure', {'peerId': b_id})
    conv = b.get('data', {}).get('conversation', {}).get('id')
    check('Start a chat', s == 200 and bool(conv), f'HTTP {s}' + ('' if conv else f" {b.get('error')}"))
    if conv:
        sent_ok = 0
        for i, msg in enumerate(['Hello from the smoke test 👋', 'Second message — order check']):
            s, b, secs = api(a_tok, 'dm.send', {'conversationId': conv, 'text': msg, 'type': 'text'})
            sent_ok += s == 200
            if s != 200:
                note(f"  - send {i + 1}: HTTP {s} {b.get('error')}")
            time.sleep(0.6)
        check('Send messages', sent_ok == 2, f'{sent_ok}/2 stored (MongoDB writes work)')
        s, b, secs = api(b_tok, 'dm.messages', {'conversationId': conv, 'limit': 20})
        msgs = b.get('data', {}).get('messages', [])
        texts = [str(m.get('text', '')) for m in msgs]
        check('Other person receives them', s == 200 and len(msgs) >= 2,
              f'{len(msgs)} messages read by the recipient in {secs:.2f}s')
        s, b, _ = api(b_tok, 'dm.list')
        convs = b.get('data', {}).get('conversations', [])
        check('Chat list shows the conversation', s == 200 and any(c.get('id') == conv for c in convs),
              f'{len(convs)} conversation(s)')
        s, b, _ = api(b_tok, 'dm.send', {'conversationId': conv, 'text': 'Reply ✔', 'type': 'text'})
        check('Reply', s == 200, f'HTTP {s}')

    # ── data saving (egress) ──
    try:
        body, wire, plain, enc = raw_api(a_tok, {'action': 'books.list', 'payload': {'limit': 50}})
        check('Answers are compressed (gzip)', enc == 'gzip' and body.get('ok') is True and wire < plain,
              f'books.list {kb(plain)} → {kb(wire)} on the wire ({enc or "no encoding"})')
        if lib:
            body, wire, plain, enc = raw_api(a_tok, {'action': 'books.chapter',
                                                     'payload': {'bookId': book['id'], 'chapterNumber': 1}})
            note(f"  - chapter text: {kb(plain)} → {kb(wire)} on the wire")
        if conv:
            payload = {'conversationId': conv}
            first, w1, p1, _ = raw_api(a_tok, {'action': 'dm.messages', 'payload': payload, 'wantRev': True})
            rev = first.get('rev')
            again, w2, p2, _ = raw_api(a_tok, {'action': 'dm.messages', 'payload': payload,
                                               'wantRev': True, 'ifRev': rev})
            same = again.get('data', {}).get('unchanged') is True and again.get('rev') == rev
            check('Unchanged chat costs a few bytes (rev check)', bool(rev) and same,
                  f'full page {kb(w1)}, unchanged answer {kb(w2)}')
    except Exception as e:
        check('Data-saving checks', False, str(e)[:200])

    # ── calls ──
    s, b, _ = api(a_tok, 'calls.ice')
    d = b.get('data', {})
    servers = d.get('iceServers', []) if s == 200 else []
    turns = [x for x in servers if str(x.get('urls', '')).startswith(('turn:', 'turns:'))]
    check('Call relay offered to the app (TURN)', bool(turns),
          f"relay={d.get('relay')}, {len(turns)} TURN entries: " +
          ', '.join(sorted({re.sub(r'^(turns?):[^:]+:(\d+).*?(transport=(\w+))?$', r'\1 \2 \4', x['urls']) for x in turns}))[:200])
    if turns:
        turn_probe(turns)
    # ── push notifications (server side: Firebase key works) ──
    s, b, _ = api(a_tok, 'push.status')
    d = b.get('data', {}) if s == 200 else {}
    check('Push notifications ready on the server (Firebase)', bool(d.get('configured') and d.get('auth')),
          f"HTTP {s}, configured={d.get('configured')}, google sign-in={d.get('auth')}, project={d.get('project')}")
    # ── text chat backup (sealed blob in MongoDB; media goes to Google Drive) ──
    try:
        blob = base64.b64encode(b'BNBK' + bytes([2]) + secrets.token_bytes(3000)).decode()
        s, b, _ = api(a_tok, 'backup.put', {'blob': blob})
        put_ok = s == 200 and bool(b.get('data', {}).get('saved'))
        s2, b2, _ = api(a_tok, 'backup.get')
        same = s2 == 200 and b2.get('data', {}).get('blob') == blob
        api(a_tok, 'backup.delete')
        s3, b3, _ = api(a_tok, 'backup.status')
        gone = s3 == 200 and not b3.get('data', {}).get('exists')
        check('Text chat backup: save, restore, delete', put_ok and same and gone,
              f"put HTTP {s} {b.get('error') or ''}, restore identical={same}, deleted={gone}")
    except Exception as e:
        check('Text chat backup: save, restore, delete', False, str(e)[:200])
    # ── profile cover photo (profiles.cover_url) ──
    try:
        url = 'https://res.cloudinary.com/deqdmwlt7/image/upload/booknest/profile_covers/smoke.jpg'
        s, b, _ = http('PATCH', f'{SUPA}/rest/v1/profiles?id=eq.{a_id}', {'cover_url': url},
                       {'apikey': ANON, 'Authorization': f'Bearer {a_tok}', 'Prefer': 'return=representation'})
        s2, b2, _ = http('GET', f'{SUPA}/rest/v1/profiles?id=eq.{a_id}&select=cover_url', None,
                         {'apikey': ANON, 'Authorization': f'Bearer {b_tok}'})
        rows = b2 if isinstance(b2, list) else []
        seen = bool(rows) and rows[0].get('cover_url') == url
        check('Profile cover photo saves and others see it', s in (200, 204) and seen,
              f'save HTTP {s}, visible to another reader={seen} {str(b)[:120] if s >= 300 else ""}')
    except Exception as e:
        check('Profile cover photo saves and others see it', False, str(e)[:200])
    # ── chat files travel through the private R2 relay (never Cloudinary) ──
    pdf, docx = tiny_files()
    for fname, blob, mime in (('smoke.pdf', pdf, 'application/pdf'),
                              ('smoke.docx', docx, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document')):
        ok, detail = relay_roundtrip(a_tok, fname, blob, mime)
        check(f'Chat file sends and opens (R2 relay, 3 days): {fname}', ok, detail)
    # ── clubs / communities / organizations / schools ──
    try:
        s2, b2, _ = api(a_tok, 'books.list', {'limit': 50, 'search': 'the'})
        ids = [str(x.get('id')) for x in (b2.get('data', {}) or {}).get('books', [])] + \
            [str(x.get('id')) for x in books]
        groups_suite(a_id, a_tok, b_id, b_tok, ids)
    except Exception as e:
        check('Group features', False, str(e)[:240])
    finish(users)


def groups_suite(a_id, a_tok, b_id, b_tok, book_ids):
    """Every group feature the app offers, for all four kinds, the way the
    group screens call them. Books are imported classics ('bulk-…' slugs)
    and user books (UUIDs) — the ids that used to be refused."""
    def ok(r):
        return r[0] == 200 and r[1].get('ok') is True

    def err(r):
        return '' if ok(r) else f"HTTP {r[0]} {str(r[1].get('error') or r[1])[:120]}"

    # someone else's reader profile must be theirs, not mine
    api(b_tok, 'users.profile.save', {'country': 'Ghana', 'countryCode': 'GH'})
    api(a_tok, 'users.profile.save', {'country': 'Nigeria', 'countryCode': 'NG'})
    r = api(a_tok, 'users.profile.get', {'userId': b_id})
    prof = ((r[1].get('data', {}) or {}).get('profile', {}) or {})
    check("Viewing another reader's profile shows theirs", ok(r) and prof.get('countryCode') == 'GH',
          err(r) or f"country shown: {prof.get('countryCode')} (theirs is GH, mine NG)")
    book = next((b for b in book_ids if b.startswith('bulk-')), book_ids[0] if book_ids else '')
    for kind in ('clubs', 'communities', 'organizations', 'schools'):
        label = kind[:-1].capitalize() if kind != 'communities' else 'Community'
        r = api(a_tok, 'groups.create', {'kind': kind, 'name': f'Smoke {label} {secrets.token_hex(2)}',
                                         'description': 'smoke test'})
        gid = (r[1].get('data', {}) or {}).get('group', {}).get('_id') or \
            (r[1].get('data', {}) or {}).get('id') or (r[1].get('data', {}) or {}).get('group', {}).get('id')
        if not ok(r) or not gid:
            check(f'{label}: create', False, err(r) or str(r[1])[:160])
            continue
        steps = []

        def step(name, res):
            steps.append((name, ok(res), err(res)))
            return res
        step('join', api(b_tok, 'groups.join', {'kind': kind, 'groupId': gid}))
        step('get', api(b_tok, 'groups.get', {'kind': kind, 'groupId': gid}))
        if book:
            step('add book to reading list', api(a_tok, 'schools.readinglist.add',
                                                 {'kind': kind, 'groupId': gid, 'bookId': book}))
            g = api(b_tok, 'groups.get', {'kind': kind, 'groupId': gid})
            listed = any(e.get('bookId') == book for e in
                         ((g[1].get('data', {}) or {}).get('group', {}) or {}).get('readingList', []) or [])
            steps.append(('reading list shows the book', listed, '' if listed else 'not on the list'))
            step('remove book', api(a_tok, 'schools.readinglist.remove',
                                    {'kind': kind, 'groupId': gid, 'bookId': book}))
            step('pick of the month', api(a_tok, 'clubs.potm.set', {'kind': kind, 'groupId': gid, 'bookId': book}))
        step('post announcement', api(a_tok, 'groups.announcements.post',
                                      {'kind': kind, 'groupId': gid, 'title': 'Hello', 'body': 'Smoke'}))
        a = step('read announcements', api(b_tok, 'groups.announcements.list', {'kind': kind, 'groupId': gid}))
        step('create channel', api(a_tok, 'groups.channels.create', {'kind': kind, 'groupId': gid, 'name': 'general-2'}))
        step('list channels', api(b_tok, 'groups.channels.list', {'groupId': gid}))
        ev = step('schedule event', api(a_tok, 'groups.events.create', {
            'kind': kind, 'groupId': gid, 'title': 'Smoke night',
            'at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time() + 86400))}))
        evid = ((ev[1].get('data', {}) or {}).get('event', {}) or {}).get('id') or \
            ((ev[1].get('data', {}) or {}).get('event', {}) or {}).get('_id')
        if evid:
            step('RSVP', api(b_tok, 'groups.events.rsvp', {'eventId': str(evid), 'status': 'going'}))
        step('list events', api(b_tok, 'groups.events.list', {'groupId': gid}))
        step('create department', api(a_tok, 'groups.units.create', {'kind': kind, 'groupId': gid, 'name': 'Smoke unit'}))
        step('list departments', api(b_tok, 'groups.units.list', {'kind': kind, 'groupId': gid}))
        step('set rules', api(a_tok, 'groups.rules.set', {'kind': kind, 'groupId': gid, 'rules': ['Be kind']}))
        if kind == 'schools':
            c = step('create class', api(a_tok, 'schools.class.create', {'schoolId': gid, 'name': 'Smoke 101'}))
            cid = ((c[1].get('data', {}) or {}).get('class', {}) or {}).get('id') or \
                ((c[1].get('data', {}) or {}).get('class', {}) or {}).get('_id')
            step('list classes', api(b_tok, 'schools.class.list', {'schoolId': gid}))
            if cid:
                step('assignment with a book', api(a_tok, 'schools.assignment.create', {
                    'classId': str(cid), 'title': 'Read chapter 1', 'bookId': book}))
            step('schedule exam', api(a_tok, 'schools.exam.create', {'schoolId': gid, 'title': 'Smoke test', 'subject': 'English'}))
            step('leaderboard', api(b_tok, 'schools.leaderboard', {'kind': kind, 'groupId': gid}))
            cbt_suite(a_tok, b_tok, gid)
        step('delete group (owner)', api(a_tok, 'groups.delete', {'kind': kind, 'groupId': gid}))
        bad = [f'{n}: {e}' for n, good, e in steps if not good]
        check(f'{label}: every feature works ({len(steps) - len(bad)}/{len(steps)})', not bad,
              '; '.join(bad)[:400] if bad else ', '.join(n for n, _, _ in steps))


def cbt_suite(a_tok, b_tok, gid):
    """School CBT the way a real school uses it: the teacher (a) sets
    questions, the student (b) is locked out before the start time, sits
    the exam once, can't come back in, and gets a server-marked score."""
    def ok(r):
        return r[0] == 200 and r[1].get('ok') is True

    def data(r):
        return r[1].get('data', {}) or {}

    def iso(offset):
        return time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time() + offset))
    steps = []

    def step(name, good, detail=''):
        steps.append((name, bool(good), detail))
    qs = [
        {'type': 'mcq', 'text': 'What is 2 + 2?', 'options': ['3', '4', '5', '6'], 'answer': 1,
         'explanation': '2 + 2 = 4', 'subject': 'Mathematics', 'topic': 'Arithmetic', 'year': '2025'},
        {'type': 'mcq', 'text': 'The capital of Nigeria is', 'options': ['Lagos', 'Abuja', 'Kano'], 'answer': 1,
         'subject': 'Civic Education', 'year': '2024'},
    ]
    r = api(a_tok, 'cbt.bank.add', {'schoolId': gid, 'questions': qs})
    step('teacher adds questions to the bank', ok(r) and data(r).get('added') == 2, str(r[1])[:120])
    r = api(b_tok, 'cbt.bank.add', {'schoolId': gid, 'questions': qs})
    step('student cannot add questions', r[0] == 403, f'HTTP {r[0]}')
    r = api(b_tok, 'cbt.bank.subjects', {'schoolId': gid})
    step('student sees practice subjects', ok(r) and len(data(r).get('subjects', [])) == 2, str(r[1])[:120])
    r = api(b_tok, 'cbt.practice.questions', {'schoolId': gid, 'subject': 'Mathematics', 'count': 10})
    pq = data(r).get('questions', [])
    step('practice gives questions with answers', ok(r) and pq and pq[0].get('answer') == 1, str(r[1])[:120])
    api(b_tok, 'cbt.practice.record', {'schoolId': gid, 'subject': 'Mathematics', 'score': 1, 'total': 1,
                                       'seconds': 12, 'mode': 'mock'})
    r = api(b_tok, 'cbt.practice.history', {'schoolId': gid})
    step('practice history', ok(r) and len(data(r).get('recent', [])) == 1, str(r[1])[:120])
    paper = qs + [{'type': 'theory', 'text': 'Explain photosynthesis.', 'marks': 5}]
    base = {'schoolId': gid, 'subject': 'General', 'durationMin': 30, 'published': True,
            'questions': paper, 'settings': {'results': 'instant', 'strictExit': True}}
    r = api(a_tok, 'cbt.exam.save', {**base, 'title': 'Locked', 'startsAt': iso(3600)})
    locked_id = data(r).get('exam', {}).get('id')
    r = api(b_tok, 'cbt.exam.start', {'examId': locked_id or ''})
    step('questions locked before the start time', r[0] == 423, f'HTTP {r[0]} {r[1].get("error")}')
    r = api(a_tok, 'cbt.exam.save', {**base, 'title': 'Live', 'startsAt': iso(-60)})
    live_id = data(r).get('exam', {}).get('id')
    r = api(b_tok, 'cbt.exam.list', {'schoolId': gid})
    listed = {e.get('id'): e for e in data(r).get('exams', [])}
    step('student sees both exams, no questions in the list',
         ok(r) and live_id in listed and locked_id in listed and 'questions' not in listed.get(live_id, {}),
         str(r[1])[:160])
    r = api(b_tok, 'cbt.exam.start', {'examId': live_id or ''})
    paper_out = data(r).get('questions', [])
    att = data(r).get('attempt', {}).get('id')
    leak = any('answer' in q or 'explanation' in q for q in paper_out)
    step('enter live exam: 3 questions, no answers sent', ok(r) and len(paper_out) == 3 and not leak,
         str(r[1])[:160])
    answers = {}
    for q in paper_out:
        if q['type'] == 'theory':
            answers[q['id']] = 'Plants make food from light.'
        elif q['text'].startswith('What is'):
            answers[q['id']] = next(o['k'] for o in q['options'] if o['t'] == '4')
        else:
            answers[q['id']] = next(o['k'] for o in q['options'] if o['t'] == 'Lagos')
    r = api(b_tok, 'cbt.attempt.save', {'attemptId': att or '', 'answers': answers})
    step('autosave', ok(r), str(r[1])[:120])
    r = api(b_tok, 'cbt.attempt.submit', {'attemptId': att or '', 'answers': answers, 'reason': 'manual'})
    res = data(r).get('result') or {}
    step('submit: server marks 1/7 (theory pending)',
         ok(r) and res.get('score') == 1 and res.get('total') == 7 and res.get('theoryPending') == 1, str(r[1])[:160])
    r = api(b_tok, 'cbt.exam.start', {'examId': live_id or ''})
    step('no second attempt', r[0] == 409, f'HTTP {r[0]}')
    r = api(a_tok, 'cbt.exam.save', {**base, 'title': 'Strict', 'startsAt': iso(-60)})
    strict_id = data(r).get('exam', {}).get('id')
    api(b_tok, 'cbt.exam.start', {'examId': strict_id or ''})
    r = api(b_tok, 'cbt.exam.start', {'examId': strict_id or ''})
    step('leaving and coming back auto-submits', r[0] == 409 and 'automatically' in str(r[1].get('error')),
         f'HTTP {r[0]} {r[1].get("error")}')
    r = api(a_tok, 'cbt.results', {'examId': strict_id or ''})
    rows = data(r).get('attempts', [])
    step('teacher sees the auto-submission', ok(r) and rows and rows[0].get('reason') == 'reentered', str(r[1])[:160])
    r = api(a_tok, 'cbt.results', {'examId': live_id or ''})
    rows = data(r).get('attempts', [])
    r = api(a_tok, 'cbt.attempt.view', {'attemptId': rows[0]['id'] if rows else ''})
    theory = next((q for q in data(r).get('questions', []) if q.get('type') == 'theory'), {})
    r = api(a_tok, 'cbt.attempt.grade', {'attemptId': rows[0]['id'] if rows else '', 'marks': {theory.get('id', 'x'): 4}})
    step('teacher marks theory: 5/7', ok(r) and data(r).get('score') == 5, str(r[1])[:120])
    r = api(b_tok, 'cbt.results', {'examId': live_id or ''})
    step('students cannot open the results sheet', r[0] == 403, f'HTTP {r[0]}')
    step('release results', ok(api(a_tok, 'cbt.exam.release', {'examId': live_id or ''})))
    r = api(b_tok, 'cbt.exam.list', {'schoolId': gid})
    mine = next((e for e in data(r).get('exams', []) if e.get('id') == live_id), {}).get('myAttempt') or {}
    step('student sees final score', mine.get('score') == 5, str(mine)[:120])
    for eid in (locked_id, live_id, strict_id):
        if eid:
            api(a_tok, 'cbt.exam.delete', {'examId': eid})
    bad = [f'{n}: {e}' for n, good, e in steps if not good]
    check(f'School CBT exams: every step works ({len(steps) - len(bad)}/{len(steps)})', not bad,
          '; '.join(bad)[:500] if bad else ', '.join(n for n, _, _ in steps))


def finish(users):
    # ── account deletion (the app's own flow), admin fallback ──
    deleted = 0
    for uid, tok in users:
        s, b, _ = api(tok, 'account.delete')
        if s == 200:
            deleted += 1
        else:
            note(f"  - account.delete HTTP {s} {b.get('error')} — removing via admin")
            admin_delete(uid)
    if users:
        check('Delete account (Settings → Delete my account)', deleted == len(users),
              f'{deleted}/{len(users)} removed by the in-app flow')
    note('')
    passed = sum(results.values())
    note(f'**{passed}/{len(results)} checks passed.**')
    Path('ops').mkdir(exist_ok=True)
    Path('ops/smoke-report.md').write_text('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main()
