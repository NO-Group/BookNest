#!/usr/bin/env python3
"""Moves library book texts out of MongoDB (and old Cloudinary raw files)
into the private Cloudflare R2 bucket, leaving tiny pointer rows behind.

Safe by construction
  • Library books only (no member author). Members' manuscripts stay put.
  • Every text is uploaded AND verified (size check) before its MongoDB row
    is touched; a manifest of every chapter is stored in R2 as well.
  • When the free cluster is over quota only deletes work, so rows are
    deleted and re-inserted as pointers — largest books first, which gets
    the cluster back under quota fastest. Pointer rows that cannot be
    written yet are retried, and any later run repairs them from the
    manifests (rows missing from MongoDB but listed in a manifest).

Environment: FN_URL ANON IMPORT_TOKEN CLOUDFLARE_ACCOUNT_ID R2_ACCESS_KEY_ID
R2_SECRET_ACCESS_KEY R2_BUCKET; MODE=plan|migrate; LIMIT_BOOKS (trial runs);
REPORT_DIR.
"""
from __future__ import annotations

import concurrent.futures as cf
import datetime as dt
import hashlib
import json
import os
import random
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

import boto3
from botocore.config import Config

FN_URL = os.environ['FN_URL'].rstrip('/')
ANON = os.environ['ANON']
TOKEN = os.environ['IMPORT_TOKEN']
MODE = os.environ.get('MODE', 'plan')
LIMIT_BOOKS = int(os.environ.get('LIMIT_BOOKS') or 0)
REPORT_DIR = Path(os.environ.get('REPORT_DIR') or 'ops')
BUCKET = os.environ['R2_BUCKET']
s3 = boto3.client('s3', endpoint_url=f"https://{os.environ['CLOUDFLARE_ACCOUNT_ID']}.r2.cloudflarestorage.com",
                  aws_access_key_id=os.environ['R2_ACCESS_KEY_ID'],
                  aws_secret_access_key=os.environ['R2_SECRET_ACCESS_KEY'], region_name='auto',
                  config=Config(retries={'max_attempts': 6, 'mode': 'standard'}, max_pool_connections=32))
report: dict = {'started': dt.datetime.now(dt.timezone.utc).isoformat(), 'mode': MODE, 'errors': []}
T0 = time.time()


def log(*a):
    print(f'[{time.time() - T0:7.0f}s]', *a, flush=True)


def api(action: str, payload: dict, timeout: int = 180):
    body = json.dumps({'action': action, 'importToken': TOKEN, **payload}).encode()
    last = None
    for attempt in range(6):
        req = urllib.request.Request(FN_URL, data=body, method='POST',
                                     headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + ANON,
                                              # Run next to the database (CI runners sit in the US).
                                              'x-region': os.environ.get('EDGE_REGION', 'eu-west-1')})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                out = json.loads(r.read().decode())
            return out.get('data', out)
        except urllib.error.HTTPError as e:
            last = f'HTTP {e.code}: {e.read().decode("utf-8", "replace")[:300]}'
            if e.code in (401, 403):
                raise RuntimeError(last)
        except Exception as e:
            last = repr(e)
        time.sleep(3 * (attempt + 1))
    raise RuntimeError(f'{action} failed: {last}')


def paged(action: str, key: str, limit: int) -> list[dict]:
    rows, after = [], None
    while True:
        out = api(action, {'limit': limit, **({'after': after} if after else {})})
        rows += out.get(key, [])
        after = out.get('next')
        if not after:
            return rows


def r2_key(book_id: str, n: int) -> str:
    safe = re.sub(r'[^a-z0-9-]+', '-', book_id.lower()).strip('-')[:90]
    return f'library/{safe}-{hashlib.sha1(book_id.encode()).hexdigest()[:8]}/{n:04d}.md'


def r2_size(key: str) -> int | None:
    try:
        return int(s3.head_object(Bucket=BUCKET, Key=key)['ContentLength'])
    except Exception:
        return None


def load_manifests() -> dict[tuple[str, int], dict]:
    entries: dict[tuple[str, int], dict] = {}
    token = None
    while True:
        kw = {'Bucket': BUCKET, 'Prefix': 'manifests/library-chapters-'}
        if token:
            kw['ContinuationToken'] = token
        res = s3.list_objects_v2(**kw)
        for obj in sorted(res.get('Contents', []), key=lambda o: o['Key']):
            body = s3.get_object(Bucket=BUCKET, Key=obj['Key'])['Body'].read().decode()
            for line in body.splitlines():
                if line.strip():
                    e = json.loads(line)
                    entries[(e['bookId'], int(e['chapterNumber']))] = e
        if not res.get('IsTruncated'):
            return entries
        token = res.get('NextContinuationToken')


def http_text(url: str) -> str | None:
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'BookNest-storage/1.0'})
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read().decode('utf-8', 'replace')
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
        except Exception:
            pass
        time.sleep(2 * (attempt + 1))
    return None


def put_verified(key: str, text: str, book_id: str, n: int) -> int:
    data = text.encode('utf-8')
    s3.put_object(Bucket=BUCKET, Key=key, Body=data, ContentType='text/markdown; charset=utf-8',
                  Metadata={'book': book_id.encode('ascii', 'replace').decode()[:200], 'chapter': str(n)})
    size = r2_size(key)
    if size != len(data):
        raise RuntimeError(f'verify failed for {key}: {size} != {len(data)}')
    return len(data)


def main():
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    library = {b['id']: b for b in paged('admin.libraryIndex', 'books', 1000)}
    log(f'library books: {len(library)}')
    scan = paged('admin.chapterScan', 'chapters', 2000)
    log(f'chapter rows: {len(scan)}')
    present = {(c['bookId'], c['chapterNumber']) for c in scan}
    lib_rows = [c for c in scan if c['bookId'] in library]
    kinds = {'inline': [], 'cdn': [], 'r2': [], 'github': [], 'empty': []}
    for c in lib_rows:
        src = c.get('source') or {}
        if c['inlineBytes'] > 0:
            kinds['inline'].append(c)
        elif src.get('kind') == 'r2':
            kinds['r2'].append(c)
        elif src.get('kind') in ('se', 'gt'):
            kinds['github'].append(c)
        elif (c.get('contentUrl') or '').startswith('https://res.cloudinary.com/'):
            kinds['cdn'].append(c)
        else:
            kinds['empty'].append(c)
    manifests = load_manifests()
    missing = [e for k, e in manifests.items() if k not in present and e['bookId'] in library]
    plan = {k: len(v) for k, v in kinds.items()}
    plan['inline_MB'] = round(sum(c['inlineBytes'] for c in kinds['inline']) / 1048576, 1)
    plan['member_rows_untouched'] = len(scan) - len(lib_rows)
    plan['manifest_entries'] = len(manifests)
    plan['missing_rows_to_repair'] = len(missing)
    report['plan'] = plan
    log('plan:', plan)
    if MODE != 'migrate':
        return finish()

    # Order: biggest books first (frees the most space soonest).
    per_book: dict[str, int] = {}
    for c in kinds['inline']:
        per_book[c['bookId']] = per_book.get(c['bookId'], 0) + c['inlineBytes']
    books_order = sorted(per_book, key=lambda b: -per_book[b])
    cdn_books = sorted({c['bookId'] for c in kinds['cdn']})
    if LIMIT_BOOKS:
        books_order = books_order[:LIMIT_BOOKS]
        cdn_books = cdn_books[:LIMIT_BOOKS]
    chosen = set(books_order) | set(cdn_books)
    todo = [c for c in kinds['inline'] + kinds['cdn'] if c['bookId'] in chosen]
    log(f'copying {len(todo)} chapters from {len(chosen)} books to R2…')

    # 1) Copy to R2 (inline via batched reads, cdn via download), verified.
    new_entries: list[dict] = []
    copy_fail = 0
    inline_todo = [c for c in todo if c['inlineBytes'] > 0]
    cdn_todo = [c for c in todo if c['inlineBytes'] == 0]

    def copy_inline(batch: list[dict]) -> list[dict]:
        out = api('admin.dumpChapters', {'ids': [c['id'] for c in batch]}, timeout=240)
        texts = {r['id']: r['content'] for r in out.get('chapters', [])}
        done = []
        for c in batch:
            text = texts.get(c['id'])
            if not text:
                continue
            key = r2_key(c['bookId'], c['chapterNumber'])
            size = put_verified(key, text, c['bookId'], c['chapterNumber'])
            done.append({'bookId': c['bookId'], 'chapterNumber': c['chapterNumber'], 'title': c['title'],
                         'key': key, 'bytes': size, 'from': 'inline'})
        return done

    def copy_cdn(c: dict) -> list[dict]:
        text = http_text(c['contentUrl'])
        if not text:
            return []
        key = r2_key(c['bookId'], c['chapterNumber'])
        size = put_verified(key, text, c['bookId'], c['chapterNumber'])
        return [{'bookId': c['bookId'], 'chapterNumber': c['chapterNumber'], 'title': c['title'],
                 'key': key, 'bytes': size, 'from': 'cdn', 'contentUrl': c['contentUrl']}]

    batches, cur, cur_bytes = [], [], 0
    order_index = {b: i for i, b in enumerate(books_order)}
    for c in sorted(inline_todo, key=lambda c: (order_index.get(c['bookId'], 10 ** 9), c['chapterNumber'])):
        if cur and (len(cur) >= 40 or cur_bytes + c['inlineBytes'] > 4_000_000):
            batches.append(cur)
            cur, cur_bytes = [], 0
        cur.append(c)
        cur_bytes += c['inlineBytes']
    if cur:
        batches.append(cur)
    with cf.ThreadPoolExecutor(12) as pool:
        futs = [pool.submit(copy_inline, b) for b in batches] + [pool.submit(copy_cdn, c) for c in cdn_todo]
        for i, f in enumerate(cf.as_completed(futs), 1):
            try:
                new_entries += f.result()
            except Exception as e:
                copy_fail += 1
                if len(report['errors']) < 30:
                    report['errors'].append(f'copy: {repr(e)[:200]}')
            if i % 50 == 0:
                log(f'  copy progress {i}/{len(futs)} · chapters in R2 {len(new_entries)}')
    report['copied'] = len(new_entries)
    report['copy_failures'] = copy_fail
    log(f'copied+verified {len(new_entries)} chapters ({copy_fail} failed batches)')

    # 2) Manifest in R2 (before any row is touched).
    if new_entries:
        stamp = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
        body = '\n'.join(json.dumps(e, ensure_ascii=False) for e in new_entries) + '\n'
        s3.put_object(Bucket=BUCKET, Key=f'manifests/library-chapters-{stamp}.jsonl', Body=body.encode(),
                      ContentType='application/x-ndjson')
        report['manifest'] = f'manifests/library-chapters-{stamp}.jsonl'

    # 3) Repoint rows: repairs first, then inline (reinsert, biggest first), then cdn (replace).
    pending: list[dict] = []
    stats = {'written': 0, 'deleted': 0, 'rejected': 0}

    def repoint(items: list[dict], mode: str):
        for i in range(0, len(items), 400):
            chunk = items[i:i + 400]
            out = api('admin.repointChapters', {'mode': mode, 'items': chunk}, timeout=240)
            stats['written'] += int(out.get('written', 0))
            stats['deleted'] += int(out.get('deleted', 0))
            stats['rejected'] += int(out.get('rejected', 0))
            failed = {(f['bookId'], f['chapterNumber']) for f in out.get('failed', [])}
            pending.extend(e for e in chunk if (e['bookId'], e['chapterNumber']) in failed)
            for err in out.get('errors', []):
                if len(report['errors']) < 30:
                    report['errors'].append(f'repoint: {err}')

    if missing:
        log(f'repairing {len(missing)} rows from earlier manifests…')
        repoint(missing, 'reinsert')
    inline_entries = sorted((e for e in new_entries if e['from'] == 'inline'),
                            key=lambda e: (order_index.get(e['bookId'], 10 ** 9), e['chapterNumber']))
    repoint(inline_entries, 'reinsert')
    log(f'inline repointed: {stats} · pending {len(pending)}')
    for attempt in range(20):
        if not pending:
            break
        retry, pending[:] = list(pending), []
        time.sleep(60)
        repoint(retry, 'reinsert')
        log(f'  retry {attempt + 1}: pending {len(pending)}')
    repoint([e for e in new_entries if e['from'] == 'cdn'], 'replace')
    report['repoint'] = {**stats, 'still_pending': len(pending)}
    report['pending_sample'] = pending[:20]
    log('repoint done:', report['repoint'])

    # 4) Verify a sample through the live server.
    checks = []
    for e in random.Random(1).sample(new_entries, min(8, len(new_entries))):
        try:
            out = api('books.chapter', {'bookId': e['bookId'], 'chapterNumber': e['chapterNumber']}, timeout=60)
            got = (out.get('content') or '').encode('utf-8')
            want = s3.get_object(Bucket=BUCKET, Key=e['key'])['Body'].read()
            checks.append({'book': e['bookId'], 'ch': e['chapterNumber'], 'match': got == want, 'bytes': len(want)})
        except Exception as ex:
            checks.append({'book': e['bookId'], 'ch': e['chapterNumber'], 'error': repr(ex)[:160]})
    report['verify'] = checks
    log('verify:', checks)
    finish()


def finish():
    try:
        st = api('admin.dbStats', {})
        rows = [c for c in st.get('collections', []) if 'dataMB' in c]
        report['mongo_total_MB'] = round(sum(c['dataMB'] + c['indexMB'] for c in rows), 1)
        report['mongo_top'] = sorted(rows, key=lambda c: -(c['dataMB'] + c['indexMB']))[:8]
        report['chapters_after'] = st.get('chapters')
    except Exception as e:
        report['errors'].append(f'stats: {repr(e)[:200]}')
    report['finished'] = dt.datetime.now(dt.timezone.utc).isoformat()
    (REPORT_DIR / 'r2-migration.json').write_text(json.dumps(report, indent=1, ensure_ascii=False))
    lines = ['# Book texts → R2', '', f"- mode: {MODE} · {report['started']} → {report['finished']}"]
    for k in ('plan', 'copied', 'copy_failures', 'manifest', 'repoint', 'mongo_total_MB'):
        if k in report:
            lines.append(f'- {k}: {json.dumps(report[k], ensure_ascii=False)}')
    if report.get('mongo_top'):
        lines += ['', '| db | collection | docs | data MB | index MB |', '|---|---|---|---|---|']
        lines += [f"| {c['db']} | {c['collection']} | {c['count']} | {c['dataMB']} | {c['indexMB']} |" for c in report['mongo_top']]
    if report.get('verify'):
        lines += ['', '## Live check'] + [f'- {json.dumps(c)}' for c in report['verify']]
    if report.get('errors'):
        lines += ['', '## Errors'] + [f'- {e}' for e in report['errors']]
    (REPORT_DIR / 'r2-migration.md').write_text('\n'.join(lines) + '\n')
    print('\n'.join(lines))


if __name__ == '__main__':
    main()
