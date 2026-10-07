#!/usr/bin/env python3
"""BookNest library importer: Standard Ebooks + GITenberg, both on GitHub.

No book text is stored anywhere new. For every chapter the server keeps a
pointer to the public source, pinned to an exact commit:

  se  Standard Ebooks: one XHTML file per chapter (the best-edited
      public-domain editions there are; CC0 + public domain)
  gt  GITenberg: a byte range inside the original Project Gutenberg plain
      text (header/footer licence boilerplate excluded by the range)

The edge function reads the pointer when someone opens the chapter.

Copyright rule: BookNest is used in Nigeria and worldwide, so a book is
only imported when every author AND translator died in or before
CUTOFF_DEATH_YEAR (life + 70 years, the term in Nigeria, the EU, the UK
and most of the world). US-only public domain is not enough. Unknown
death year = not imported.

Environment
  FN_URL, ANON         edge function endpoint + public anon key
  IMPORT_TOKEN         fresh per run (minted by the workflow)
  GH_TOKEN             GitHub token (GraphQL listing of standardebooks)
  PHASES               "se,gt" (default) | "se" | "gt"
  TARGET_TOTAL         library size to reach with the GT phase (3200)
  DRY_RUN              "true" = build everything, post nothing
  REPORT_DIR           where the JSON/markdown reports go
"""
from __future__ import annotations

import concurrent.futures as cf
import datetime as dt
import gzip
import hashlib
import html
import json
import math
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path

HERE = Path(__file__).resolve().parent
FN_URL = os.environ.get('FN_URL', '').rstrip('/')
ANON = os.environ.get('ANON', '')
TOKEN = os.environ.get('IMPORT_TOKEN', '')
GH_TOKEN = os.environ.get('GH_TOKEN', '')
PHASES = [p.strip() for p in os.environ.get('PHASES', 'se,gt').split(',') if p.strip()]
TARGET_TOTAL = int(os.environ.get('TARGET_TOTAL') or 3200)
DRY_RUN = os.environ.get('DRY_RUN', 'false').lower() == 'true'
LIMIT = int(os.environ.get('LIMIT') or 0)  # testing: cap books per phase
REPORT_DIR = Path(os.environ.get('REPORT_DIR') or (HERE / 'reports'))
CUTOFF_DEATH_YEAR = dt.date.today().year - 71  # 2026 → died 1955 or earlier
UA = 'BookNest-library/2.0 (https://github.com/NO-Group/BookNest)'
RAW = 'https://raw.githubusercontent.com'

report: dict = {'started': dt.datetime.utcnow().isoformat() + 'Z', 'cutoff': CUTOFF_DEATH_YEAR,
                'se': {}, 'gt': {}, 'excluded_copyright': [], 'errors': []}


def log(*a):
    print(*a, flush=True)


# ── http ────────────────────────────────────────────────────────────────────

def http_get(url: str, timeout: int = 40, tries: int = 4, headers: dict | None = None) -> bytes | None:
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': UA, **(headers or {})})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code in (404, 410, 451):
                return None
            if e.code == 429:
                time.sleep(20 * (attempt + 1))
                continue
        except Exception:
            pass
        time.sleep(1.5 * (attempt + 1))
    return None


def http_json(url: str, **kw):
    raw = http_get(url, **kw)
    if raw is None:
        return None
    try:
        return json.loads(raw.decode('utf-8', 'replace'))
    except Exception:
        return None


def graphql(query: str, variables: dict) -> dict:
    body = json.dumps({'query': query, 'variables': variables}).encode()
    for attempt in range(8):
        req = urllib.request.Request('https://api.github.com/graphql', data=body, method='POST',
                                     headers={'Authorization': f'bearer {GH_TOKEN}', 'User-Agent': UA,
                                              'Content-Type': 'application/json'})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                out = json.loads(r.read().decode())
            if out.get('data'):
                return out['data']
            log('graphql error', str(out)[:300])
        except Exception as e:
            log('graphql retry', attempt, repr(e)[:200])
        time.sleep(4 * (attempt + 1))
    raise RuntimeError('GitHub GraphQL unavailable')


def api(action: str, payload: dict, timeout: int = 240):
    body = json.dumps({'action': action, 'importToken': TOKEN, **payload}).encode()
    last = None
    for attempt in range(5):
        req = urllib.request.Request(FN_URL, data=body, method='POST',
                                     headers={'Content-Type': 'application/json',
                                              'Authorization': 'Bearer ' + ANON})
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
        log(f'  {action} attempt {attempt + 1}: {last}')
        time.sleep(3 * (attempt + 1))
    raise RuntimeError(f'{action} failed: {last}')


# ── shared helpers ──────────────────────────────────────────────────────────

GENRES = [
    # (keywords, BookNest genre) — first match wins; fiction-specific first.
    (('detective', 'mystery', 'crime--fiction', 'murder--fiction', 'police', 'thieves--fiction', 'mystery fiction'), 'Mystery & Crime'),
    (('science fiction', 'utopias', 'dystopias', 'time travel', 'interplanetary', 'end of the world', 'imaginary wars'), 'Science Fiction'),
    (('horror', 'ghost', 'vampire', 'gothic', 'supernatural', 'werewolves', 'haunted'), 'Horror'),
    (('fantasy', 'fairy tales', 'fairies', 'magic--fiction', 'mythology', 'legends', 'dragons', 'arthurian', 'folklore'), 'Fantasy'),
    (('western stories', 'frontier and pioneer life--fiction', 'cowboys', 'ranch life'), 'Westerns'),
    (('love stories', 'romance', 'courtship', 'man-woman relationships'), 'Romance'),
    (('spy stories', 'suspense', 'thriller', 'adventure stories', 'sea stories', 'pirates', 'adventure and adventurers', 'treasure', 'survival'), 'Thriller & Suspense'),
    (('juvenile fiction', "children's", 'children--', 'school stories', 'boys--', 'girls--', 'juvenile literature'), 'Young Adult (YA)'),
    (('historical fiction', 'war stories', '--history--', 'kings and rulers--fiction'), 'Historical Fiction'),
    (('biography', 'autobiograph', 'memoir', 'diaries', 'correspondence', 'letters'), 'Biographies & Memoirs'),
    (('murder--case studies', 'trials (murder)', 'criminals--biography', 'true crime'), 'True Crime'),
    (('conduct of life', 'self-help', 'success', 'self-culture', 'happiness', 'health', 'hygiene'), 'Self-Help & Wellness'),
    (('economics', 'finance', 'money', 'wealth', 'banks and banking', 'commerce'), 'Finance & Economics'),
    (('mathematics', 'physics', 'astronomy', 'chemistry', 'biology', 'natural history', 'evolution', 'science', 'botany', 'geology', 'zoology', 'engineering', 'medicine'), 'STEM'),
    (('language', 'grammar', 'linguistics', 'rhetoric'), 'Languages & Linguistics'),
    (('dictionaries', 'encyclopedias', 'glossaries'), 'Lexicons'),
    (('history', 'politics', 'political science', 'government', 'world war', 'revolution', 'constitutional', 'military'), 'History & Politics'),
    (('philosophy', 'ethics', 'religion', 'psychology', 'sociology', 'essays', 'theology', 'christianity', 'anthropology'), 'Humanities & Social Sciences'),
]


def genre_of(subjects: list[str]) -> str:
    blob = ' | '.join(s.lower() for s in subjects)
    for keys, genre in GENRES:
        if any(k in blob for k in keys):
            return genre
    return 'Literary Fiction'


def norm_title(t: str) -> str:
    t = t.lower()
    t = re.sub(r'\([^)]*\)', ' ', t)
    t = re.split(r'[:;]|\bor,\s', t)[0]
    t = re.sub(r'^(the|a|an)\s+', '', t.strip())
    return re.sub(r'[^a-z0-9]+', '', t)


def surname(author: str) -> str:
    a = author or ''
    # The first importer stored "Jane, 1775-1817 Austen" (catalog dates
    # leaked into the name): the surname is then the last word.
    broken = re.search(r',\s*\??-?\d', a) is not None
    a = re.sub(r'\([^)]*\)|\d+|\b(BCE?|AD)\b', ' ', a)
    a = re.sub(r',?\s*\b(jr|sr|junior|senior)\.?\s*$', '', a, flags=re.I)
    if not broken and ',' in a:
        a = a.split(',')[0]
    words = re.findall(r"[A-Za-zÀ-ÿ']+", a)
    return words[-1].lower() if words else ''


def book_key(title: str, author: str) -> str:
    return norm_title(title) + '|' + surname(author)


def slug_id(title: str, author: str) -> str:
    """Mirrors the server's id derivation (admin.importBooks)."""
    slug = (title.strip()[:200] + '|' + author.strip()[:120]).lower()
    slug = re.sub(r'[^a-z0-9|]+', '-', slug).strip('-')[:90]
    return 'bulk-' + slug


def clean_text(s: str) -> str:
    s = html.unescape(re.sub(r'<[^>]+>', ' ', html.unescape(s or '')))
    return re.sub(r'\s+', ' ', s).strip()


def sentence_cut(s: str, limit: int) -> str:
    if len(s) <= limit:
        return s
    cut = s[:limit]
    end = max(cut.rfind('. '), cut.rfind('! '), cut.rfind('? '))
    return (cut[:end + 1] if end > limit * 0.5 else cut.rsplit(' ', 1)[0] + '…').strip()


def first_last(name: str) -> str:
    """Gutenberg "Last, First, title" → "First Last"."""
    n = re.sub(r'\([^)]*\)', '', name or '').strip()
    parts = [p.strip() for p in n.split(',') if p.strip()]
    if len(parts) >= 2 and not re.match(r'^(jr|sr)\.?$', parts[1].lower()):
        return re.sub(r'\s+', ' ', f'{parts[1]} {parts[0]}').strip()
    return re.sub(r'\s+', ' ', n).strip()


# ── copyright (life + 70) ───────────────────────────────────────────────────

class Lifespans:
    """Death years via Wikipedia → Wikidata (P570 death, P569 birth)."""

    def __init__(self):
        self.by_wiki: dict[str, tuple[int | None, int | None]] = {}

    def resolve(self, wiki_urls: set[str]):
        titles = {}
        for u in wiki_urls:
            m = re.match(r'https?://en\.wikipedia\.org/wiki/(.+)$', u)
            if m:
                titles[urllib.parse.unquote(m.group(1)).replace('_', ' ')] = u
        names = sorted(titles)
        qid_of: dict[str, str] = {}
        for i in range(0, len(names), 50):
            chunk = names[i:i + 50]
            q = urllib.parse.urlencode({'action': 'query', 'format': 'json', 'redirects': 1,
                                        'prop': 'pageprops', 'ppprop': 'wikibase_item',
                                        'titles': '|'.join(chunk)})
            data = http_json('https://en.wikipedia.org/w/api.php?' + q) or {}
            query = data.get('query', {})
            alias = {}
            for key in ('normalized', 'redirects'):
                for r in query.get(key, []):
                    alias[r['to']] = alias.get(r['from'], r['from'])
            for page in query.get('pages', {}).values():
                qid = (page.get('pageprops') or {}).get('wikibase_item')
                t = page.get('title', '')
                orig = t
                while orig in alias:
                    orig = alias[orig]
                if qid:
                    qid_of[orig] = qid
                    qid_of[t] = qid
            time.sleep(0.2)
        qids = sorted(set(qid_of.values()))
        years: dict[str, tuple[int | None, int | None]] = {}
        for i in range(0, len(qids), 50):
            q = urllib.parse.urlencode({'action': 'wbgetentities', 'format': 'json',
                                        'props': 'claims', 'ids': '|'.join(qids[i:i + 50])})
            data = http_json('https://www.wikidata.org/w/api.php?' + q) or {}
            for qid, ent in (data.get('entities') or {}).items():
                years[qid] = (self._year(ent, 'P569'), self._year(ent, 'P570'))
            time.sleep(0.2)
        for title, url in titles.items():
            qid = qid_of.get(title)
            if qid and qid in years:
                self.by_wiki[url] = years[qid]

    @staticmethod
    def _year(ent: dict, prop: str) -> int | None:
        try:
            claims = ent['claims'][prop]
            vals = []
            for c in claims:
                t = c['mainsnak']['datavalue']['value']['time']  # "+1817-07-18T00:00:00Z"
                vals.append(int(re.match(r'([+-]\d+)', t).group(1)))
            return max(vals) if prop == 'P570' else min(vals)
        except Exception:
            return None


def person_ok(birth: int | None, death: int | None) -> bool:
    if death is not None:
        return death <= CUTOFF_DEATH_YEAR
    # No recorded death: only safe for people born long enough ago.
    return birth is not None and birth <= 1840


# ── Standard Ebooks ─────────────────────────────────────────────────────────

NS = {'opf': 'http://www.idpf.org/2007/opf', 'dc': 'http://purl.org/dc/elements/1.1/'}
SE_SKIP = re.compile(r'(^|/)(titlepage|imprint|halftitlepage|colophon|uncopyright|toc|endnotes|loi|lot|copyright)\.xhtml$')
SE_CONTAINER = re.compile(r'(^|/)(book|part|volume|division|act|canto-group)-[\d-]+\.xhtml$')
NUMERAL = re.compile(r'^([IVXLCDM]+|\d+)\.?$')


def list_se_repos() -> list[tuple[str, str]]:
    q = '''query($c:String){ organization(login:"standardebooks"){ repositories(first:50, after:$c){
      pageInfo{endCursor hasNextPage} nodes{ name isArchived isPrivate defaultBranchRef{ target{ oid } } } } } }'''
    out, cursor = [], None
    while True:
        data = graphql(q, {'c': cursor})
        r = data['organization']['repositories']
        for n in r['nodes']:
            oid = ((n.get('defaultBranchRef') or {}).get('target') or {}).get('oid')
            if '_' in n['name'] and oid and not n['isPrivate']:
                out.append((n['name'], oid))
        if not r['pageInfo']['hasNextPage']:
            return out
        cursor = r['pageInfo']['endCursor']


class TocParser(HTMLParser):
    """Reads the nested <nav epub:type="toc"> into (href, label, ancestors)."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.in_toc = False
        self.nav_depth = 0
        self.li_depth = 0
        self.in_a = False
        self.href = ''
        self.buf: list[str] = []
        self.stack: list[tuple[str, str]] = []  # (href, label) per li depth
        self.entries: list[tuple[str, str, list[tuple[str, str]]]] = []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == 'nav':
            if self.in_toc:
                self.nav_depth += 1
            elif 'toc' in (a.get('epub:type') or ''):
                self.in_toc, self.nav_depth = True, 1
        if not self.in_toc:
            return
        if tag == 'li':
            self.li_depth += 1
        elif tag == 'a':
            self.in_a, self.href, self.buf = True, (a.get('href') or '').split('#')[0], []

    def handle_endtag(self, tag):
        if not self.in_toc:
            return
        if tag == 'nav':
            self.nav_depth -= 1
            if self.nav_depth == 0:
                self.in_toc = False
        elif tag == 'li':
            self.li_depth -= 1
            del self.stack[self.li_depth:]
        elif tag == 'a' and self.in_a:
            self.in_a = False
            label = re.sub(r'\s+', ' ', ''.join(self.buf)).strip()
            del self.stack[max(self.li_depth - 1, 0):]
            self.entries.append((self.href, label, list(self.stack)))
            self.stack.append((self.href, label))

    def handle_data(self, data):
        if self.in_a:
            self.buf.append(data)


def parse_opf(xml_text: str) -> dict:
    root = ET.fromstring(xml_text)
    md = root.find('opf:metadata', NS)
    metas = md.findall('opf:meta', NS)

    def refined(ident: str, prop: str) -> list[str]:
        return [m.text or '' for m in metas if m.get('refines') == '#' + ident and m.get('property') == prop]

    def links(ident: str) -> list[str]:
        return [l.get('href') for l in md.findall('opf:link', NS)
                if l.get('refines') == '#' + ident and 'wikipedia.org' in (l.get('href') or '')]

    people = []
    for tag in ('dc:creator', 'dc:contributor'):
        for el in md.findall(tag, NS):
            ident = el.get('id') or ''
            roles = refined(ident, 'role') or (['aut'] if tag == 'dc:creator' else [])
            if tag == 'dc:creator' or 'trl' in roles:
                people.append({'name': (el.text or '').strip(),
                               'role': 'aut' if tag == 'dc:creator' else 'trl',
                               'wiki': (links(ident) or [None])[0]})
    title_el = md.find("dc:title[@id='title']", NS)
    if title_el is None:
        title_el = md.find('dc:title', NS)
    manifest = {i.get('id'): i.get('href') for i in root.find('opf:manifest', NS)}
    spine = [manifest.get(ir.get('idref')) for ir in root.find('opf:spine', NS)
             if ir.get('linear') != 'no']
    subjects = [s.text.strip() for s in md.findall('dc:subject', NS) if s.text]
    subjects += [m.text.strip() for m in metas if m.get('property') == 'se:subject' and m.text]
    sources = [s.text or '' for s in md.findall('dc:source', NS)]
    abstract = next((m.text for m in metas if m.get('property') == 'schema:abstract'), '') or ''
    return {
        'title': (title_el.text or '').strip() if title_el is not None else '',
        'people': people,
        'subjects': subjects,
        'description': clean_text((md.find('dc:description', NS).text or '') if md.find('dc:description', NS) is not None else ''),
        'abstract': clean_text(abstract),
        'language': (md.find('dc:language', NS).text or '') if md.find('dc:language', NS) is not None else '',
        'gutenberg_ids': [int(m.group(1)) for s in sources for m in [re.search(r'gutenberg\.org/ebooks/(\d+)', s)] if m],
        'spine': [h for h in spine if h],
    }


def se_chapters(repo: str, sha: str, opf: dict, toc_html: str) -> list[dict] | None:
    base = f'{RAW}/standardebooks/{repo}/{sha}/src/epub/'
    toc = TocParser()
    toc.feed(toc_html)
    label_of: dict[str, tuple[str, list[tuple[str, str]]]] = {}
    for href, label, anc in toc.entries:
        label_of.setdefault(href, (label, anc))
    items = [h for h in opf['spine'] if not SE_SKIP.search(h)]
    if not items:
        return None

    def nice(label: str) -> str:
        return f'Chapter {label.rstrip(".")}' if NUMERAL.match(label) else label

    chapters, pending = [], []  # pending = container pages awaiting a chapter
    for href in items:
        label, anc = label_of.get(href, ('', []))
        if SE_CONTAINER.search(href) and href != items[-1]:
            pending.append(href)
            continue
        parts = [nice(l) for h, l in anc if l and not SE_SKIP.search(h)]
        own = nice(label) if label else href.rsplit('/', 1)[-1].rsplit('.', 1)[0].replace('-', ' ').title()
        title = ' · '.join(parts + [own]) if parts and NUMERAL.match(label or '') else own
        chapters.append({'title': title[:160], 'files': pending + [href]})
        pending = []
    if not chapters:
        return None
    if len(chapters) > 300:
        group = math.ceil(len(chapters) / 300)
        merged = []
        for i in range(0, len(chapters), group):
            g = chapters[i:i + group]
            files = [f for c in g for f in c['files']]
            title = g[0]['title'] if len(g) == 1 else f"{g[0]['title']} – {g[-1]['title'].split(' · ')[-1]}"
            merged.append({'title': title[:160], 'files': files})
        chapters = merged
    out = []
    for n, c in enumerate(chapters, 1):
        urls = [base + urllib.parse.quote(f) for f in c['files']]
        if len(urls) > 6:
            return None
        src = {'kind': 'se', 'url': urls[0]}
        if len(urls) > 1:
            src['more'] = urls[1:]
        out.append({'chapterNumber': n, 'title': c['title'], 'content': '', 'source': src})
    return out


def se_phase(existing_by_key: dict, lifespans: Lifespans) -> tuple[list[dict], set[str]]:
    log('SE: listing standardebooks repositories…')
    repos = list_se_repos()
    if LIMIT:
        repos = repos[:LIMIT]
    log(f'SE: {len(repos)} ebook repositories')

    def load(item):
        repo, sha = item
        opf_raw = http_get(f'{RAW}/standardebooks/{repo}/{sha}/src/epub/content.opf')
        toc_raw = http_get(f'{RAW}/standardebooks/{repo}/{sha}/src/epub/toc.xhtml')
        if not opf_raw or not toc_raw:
            return repo, sha, None, None
        try:
            return repo, sha, parse_opf(opf_raw.decode('utf-8')), toc_raw.decode('utf-8')
        except Exception as e:
            return repo, sha, {'error': repr(e)}, None

    loaded = []
    with cf.ThreadPoolExecutor(16) as pool:
        for i, res in enumerate(pool.map(load, repos), 1):
            loaded.append(res)
            if i % 200 == 0:
                log(f'  SE metadata {i}/{len(repos)}')
    wiki = {p['wiki'] for _, _, opf, _ in loaded if opf and 'people' in opf for p in opf['people'] if p['wiki']}
    log(f'SE: resolving {len(wiki)} lifespans via Wikidata…')
    lifespans.resolve(wiki)
    gid_people = gutendex_people({g for _, _, opf, _ in loaded if opf and 'gutenberg_ids' in opf
                                  for g in opf['gutenberg_ids'][:1]})

    books, keys = [], set()
    stats = {'repos': len(repos), 'unreadable': 0, 'copyright': 0, 'no_chapters': 0, 'ok': 0}
    for repo, sha, opf, toc_html in loaded:
        if not opf or 'error' in opf or not toc_html:
            stats['unreadable'] += 1
            continue
        authors = [p for p in opf['people'] if p['role'] == 'aut']
        if not opf['title'] or not authors:
            stats['unreadable'] += 1
            continue
        # Copyright: every author and translator must be life+70 clear.
        verdicts = []
        fallback = gid_people.get(opf['gutenberg_ids'][0]) if opf['gutenberg_ids'] else None
        for p in opf['people']:
            if p['name'].lower() in ('anonymous', 'unknown'):
                verdicts.append(True)
                continue
            years = lifespans.by_wiki.get(p['wiki']) if p['wiki'] else None
            if years is None and fallback:
                years = fallback.get(surname(p['name']))
            verdicts.append(years is not None and person_ok(*years))
        if not all(verdicts):
            stats['copyright'] += 1
            report['excluded_copyright'].append({'source': 'se', 'repo': repo, 'title': opf['title'],
                                                 'people': [p['name'] for p in opf['people']]})
            continue
        chapters = se_chapters(repo, sha, opf, toc_html)
        if not chapters:
            stats['no_chapters'] += 1
            continue
        author = authors[0]['name']
        title = opf['title']
        key = book_key(title, author)
        existing = existing_by_key.get(key)
        description = sentence_cut(opf['description'], 1000) or opf['abstract']
        books.append({
            **({'id': existing['id']} if existing else {}),
            'title': title, 'author': author, 'edition': 'se',
            'description': description or None,
            'genre': genre_of(opf['subjects']),
            'subjects': opf['subjects'][:8],
            'chapters': chapters,
            '_repo': repo,
        })
        keys.add(key)
        stats['ok'] += 1
    stats['replacing_existing'] = sum(1 for b in books if 'id' in b)
    report['se'] = stats
    log('SE:', stats)
    return books, keys


# ── Gutendex (popularity, summaries, lifespans for Gutenberg ids) ──────────

def gutendex_people(ids: set[int]) -> dict[int, dict[str, tuple]]:
    """Gutenberg id → {surname: (birth, death)} for authors+translators."""
    out: dict[int, dict[str, tuple]] = {}
    ids = sorted(ids)
    for i in range(0, len(ids), 32):
        chunk = ids[i:i + 32]
        data = http_json('https://gutendex.com/books/?ids=' + ','.join(map(str, chunk)), timeout=60, tries=3)
        for b in (data or {}).get('results', []):
            people = {}
            for p in b.get('authors', []) + b.get('translators', []):
                people[surname(p.get('name', ''))] = (p.get('birth_year'), p.get('death_year'))
            out[int(b['id'])] = people
    return out


def gutendex_popular(max_books: int):
    url = 'https://gutendex.com/books/?languages=en&copyright=false&mime_type=text%2Fplain&sort=popular'
    seen = 0
    while url and seen < max_books:
        data = http_json(url, timeout=90, tries=6)
        if data is None:
            log('Gutendex page failed:', url)
            return
        for b in data.get('results', []):
            seen += 1
            yield b
        url = data.get('next')


# ── GITenberg ───────────────────────────────────────────────────────────────

HEAD_RX = [re.compile(rb'\*\*\*\s*START OF (?:THE|THIS) PROJECT GUTENBERG[^\n]*\n', re.I),
           re.compile(rb'\*END\*THE SMALL PRINT[^\n]*\n', re.I)]
FOOT_RX = [re.compile(rb'\*\*\*\s*END OF (?:THE|THIS) PROJECT GUTENBERG', re.I),
           re.compile(rb'\n[ \t]*End of (?:the |this )?Project Gutenberg', re.I),
           re.compile(rb'\n[ \t]*End of the Project Gutenberg', re.I)]
# Same chapter pattern as the original importer, on bytes, so books that
# already exist keep their chapter numbers when they move to pointers.
CHAP = re.compile(rb'^(?:(CHAPTER|Chapter|BOOK|Book|PART|Part|STAVE|Canto)\s+[\w]+(?:[.:-]|\xe2\x80[\x92\x94])?)\s*$'
                  rb'|^(?:(?:CHAPTER|Chapter)\s+[A-Z][^\n]{0,60})$', re.M)
PARA = re.compile(rb'\r?\n[ \t]*\r?\n')


def load_gitenberg_index() -> dict[int, str]:
    """Gutenberg id → GITenberg repo name (snapshot of the org listing)."""
    idx = {}
    with gzip.open(HERE / 'gitenberg_index.tsv.gz', 'rt') as f:
        for line in f:
            if line.startswith('#'):
                continue
            gid, repo = line.rstrip('\n').split('\t')[:2]
            idx[int(gid)] = repo
    return idx


def head_sha(owner: str, repo: str) -> str | None:
    """Pins a repo to its current commit (git protocol: no API quota)."""
    for attempt in range(3):
        try:
            out = subprocess.run(['git', 'ls-remote', f'https://github.com/{owner}/{repo}.git', 'HEAD'],
                                 capture_output=True, text=True, timeout=40,
                                 env={**os.environ, 'GIT_TERMINAL_PROMPT': '0'})
            m = re.match(r'([0-9a-f]{40})\s+HEAD', out.stdout)
            if m:
                return m.group(1)
        except Exception:
            pass
        time.sleep(2 * (attempt + 1))
    return None


def gt_chapters(gid: int, repo: str, sha: str) -> tuple[list[dict] | None, str]:
    for fname, enc in ((f'{gid}-0.txt', 'utf-8'), (f'{gid}.txt', None), (f'{gid}-8.txt', 'latin1')):
        url = f'{RAW}/GITenberg/{urllib.parse.quote(repo)}/{sha}/{fname}'
        data = http_get(url, timeout=60, tries=3)
        if data and len(data) > 2000:
            break
    else:
        return None, 'no text file'
    if enc is None:
        try:
            data.decode('utf-8')
            enc = 'utf-8'
        except UnicodeDecodeError:
            enc = 'latin1'
    head = next((m for rx in HEAD_RX for m in [rx.search(data)] if m), None)
    if not head:
        return None, 'no Gutenberg header'
    start = head.end()
    ends = [m.start() for rx in FOOT_RX for m in [rx.search(data, start)] if m]
    end = min(ends) if ends else len(data)
    body = data[start:end]
    if len(body) < 3000:
        return None, 'text too short'
    marks = list(CHAP.finditer(body))
    ranges = []
    for i, m in enumerate(marks):
        stop = marks[i + 1].start() if i + 1 < len(marks) else len(body)
        if len(body[m.end():stop].strip()) < 40:
            continue
        title = re.sub(r'\s+', ' ', m.group(0).decode(enc, 'replace')).strip()[:100]
        ranges.append([m.start(), stop, title])
    if ranges and ranges[0][0] > 6_000:
        # Substantial text before the first heading (Frankenstein's letters,
        # prologues, prefaces) is part of the book — keep it.
        ranges.insert(0, [0, ranges[0][0], 'Opening pages'])
    if len(marks) < 3 or not ranges:
        ranges = []
        pos = 0
        while pos < len(body):
            target = pos + 30_000
            if target >= len(body) - 8_000:
                cut = len(body)
            else:
                m = PARA.search(body, target)
                cut = m.end() if m else len(body)
            ranges.append([pos, cut, f'Part {len(ranges) + 1}'])
            pos = cut
        if len(ranges) == 1:
            ranges[0][2] = 'Full text'
    if len(ranges) > 300:
        group = math.ceil(len(ranges) / 300)
        ranges = [[ranges[i][0], ranges[min(i + group, len(ranges)) - 1][1],
                   f'{ranges[i][2]} – {ranges[min(i + group, len(ranges)) - 1][2]}'[:160]]
                  for i in range(0, len(ranges), group)]
    url = f'{RAW}/GITenberg/{urllib.parse.quote(repo)}/{sha}/{fname}'
    chapters = []
    for n, (a, b, title) in enumerate(ranges, 1):
        if b - a > 2_900_000:
            return None, 'chapter too large'
        chapters.append({'chapterNumber': n, 'title': title, 'content': '',
                         'source': {'kind': 'gt', 'url': url, 'start': start + a, 'end': start + b, 'enc': enc}})
    return chapters, 'ok'


def gt_phase(existing: list[dict], existing_by_key: dict, se_keys: set[str], se_new: int) -> list[dict]:
    idx = load_gitenberg_index()
    log(f'GT: GITenberg index has {len(idx)} books')
    library_now = len(existing) + se_new
    need_new = max(0, TARGET_TOTAL - library_now)
    log(f'GT: library after SE ≈ {library_now}; new books needed for {TARGET_TOTAL}: {need_new}')
    migrate_keys = {k for k, b in existing_by_key.items() if b.get('edition') != 'se' and k not in se_keys}
    stats = {'scanned': 0, 'no_repo': 0, 'copyright': 0, 'dup': 0, 'text_fail': 0,
             'migrated': 0, 'new': 0, 'fail_reasons': {}}
    chosen, chosen_keys = [], set()
    chosen_new = 0
    want_new = int(need_new * 1.25) + 60  # headroom for texts that fail
    max_scan = 20000 if not LIMIT else LIMIT * 4
    for b in gutendex_popular(max_scan):
        stats['scanned'] += 1
        gid = int(b['id'])
        if b.get('media_type') != 'Text' or 'en' not in b.get('languages', []):
            continue
        authors = b.get('authors') or []
        title = re.sub(r'\s+', ' ', re.sub(r'\s*\([^)]{0,60}\)', '', b.get('title') or '')).strip(' ;:,')
        author = first_last(authors[0]['name']) if authors else 'Anonymous'
        key = book_key(title, author)
        if not title or key in chosen_keys or key in se_keys:
            stats['dup'] += 1
            continue
        is_migration = key in migrate_keys
        if not is_migration and chosen_new >= want_new:
            # Existing books all came from the most-read ~2,000; past
            # 8,000 the rest are not on GITenberg.
            if not (migrate_keys - chosen_keys) or stats['scanned'] > 8000:
                break
            continue
        if gid not in idx:
            stats['no_repo'] += 1
            continue
        people = authors + (b.get('translators') or [])
        if not people or not all(person_ok(p.get('birth_year'), p.get('death_year')) for p in people):
            stats['copyright'] += 1
            report['excluded_copyright'].append({'source': 'gt', 'id': gid, 'title': title,
                                                 'people': [p.get('name') for p in people]})
            continue
        subjects = (b.get('subjects') or []) + (b.get('bookshelves') or [])
        summary = next(iter(b.get('summaries') or []), '')
        summary = re.sub(r'\s*\(This is an automatically generated summary\.\)\s*', '', summary).strip()
        row = {'title': title, 'author': author, 'edition': 'gt', 'genre': genre_of(subjects),
               'subjects': subjects[:8], 'description': sentence_cut(summary, 1000) or None,
               '_gid': gid}
        if is_migration:
            ex = existing_by_key[key]
            row['id'] = ex['id']
            row['title'] = ex['title'] or title
            if ex.get('authorName') and not re.search(r'\d', ex['authorName']):
                row['author'] = ex['authorName']
            # Keep hand-written blurbs; replace only the old generic line.
            if not str(ex.get('description') or '').startswith('A beloved ') or not row['description']:
                row['description'] = None
        elif not row['description']:
            row['description'] = (f'{title} by {author} — a public-domain {row["genre"].lower()} '
                                  f'classic, presented in full.')
        chosen.append(row)
        chosen_keys.add(key)
        if not is_migration:
            chosen_new += 1
        if LIMIT and len(chosen) >= LIMIT:
            break
    log(f'GT: {len(chosen)} candidates selected; fetching texts…')

    def build(row):
        gid = row['_gid']
        repo = idx[gid]
        sha = head_sha('GITenberg', repo)
        if not sha:
            return row, None, 'repo unreachable'
        try:
            chapters, why = gt_chapters(gid, repo, sha)
        except Exception as e:
            chapters, why = None, repr(e)[:80]
        return row, chapters, why

    books = []
    new_target_left = need_new
    with cf.ThreadPoolExecutor(12) as pool:
        for i, (row, chapters, why) in enumerate(pool.map(build, chosen), 1):
            if i % 250 == 0:
                log(f'  GT texts {i}/{len(chosen)}')
            if not chapters:
                stats['text_fail'] += 1
                stats['fail_reasons'][why] = stats['fail_reasons'].get(why, 0) + 1
                continue
            if 'id' in row:
                stats['migrated'] += 1
            else:
                if new_target_left <= 0:
                    continue
                new_target_left -= 1
                stats['new'] += 1
            row['chapters'] = chapters
            books.append(row)
    stats['existing_not_matched'] = len(migrate_keys - chosen_keys)
    report['gt'] = stats
    report['still_on_cdn'] = sorted(existing_by_key[k]['id'] for k in migrate_keys - chosen_keys)[:3000]
    log('GT:', {k: v for k, v in stats.items() if k != 'fail_reasons'})
    return books


# ── main ────────────────────────────────────────────────────────────────────

def library_index() -> list[dict]:
    rows, after = [], None
    while True:
        out = api('admin.libraryIndex', {'limit': 1000, **({'after': after} if after else {})})
        rows += out.get('books', [])
        after = out.get('next')
        if not after:
            return rows


def post_books(books: list[dict], phase: str):
    sent = imported = skipped = 0
    batch, size = [], 0
    def flush():
        nonlocal batch, size, sent, imported, skipped
        if not batch:
            return
        payload = [{k: v for k, v in b.items() if not k.startswith('_')} for b in batch]
        if DRY_RUN:
            imported += len(payload)
        else:
            out = api('admin.importBooks', {'books': payload})
            imported += int(out.get('imported', 0))
            skipped += int(out.get('skipped', 0))
        sent += len(batch)
        if sent % 200 < len(batch):
            log(f'  {phase}: posted {sent}/{len(books)} (imported {imported}, unchanged/skipped {skipped})')
        batch, size = [], 0
    for b in books:
        est = len(json.dumps(b))
        if batch and (len(batch) >= 40 or size + est > 1_500_000):
            flush()
        batch.append(b)
        size += est
    flush()
    report[phase]['posted'] = sent
    report[phase]['imported'] = imported
    report[phase]['unchanged_or_skipped'] = skipped


def verify(books: list[dict]):
    """Opens chapter 1 of a few imported books through the live server."""
    checks = []
    for b in books:
        bid = b.get('id') or slug_id(b['title'], b['author'])
        for n in (1, len(b['chapters'])):
            t = time.time()
            try:
                out = api('books.chapter', {'bookId': bid, 'chapterNumber': n}, timeout=60)
                text = out.get('content') or ''
                checks.append({'book': bid, 'chapter': n, 'chars': len(text), 'ms': int((time.time() - t) * 1000),
                               'start': text[:160]})
            except Exception as e:
                checks.append({'book': bid, 'chapter': n, 'error': repr(e)[:200]})
    report['verify'] = checks
    log('verify:', json.dumps(checks, ensure_ascii=False)[:3000])


def write_report():
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    report['finished'] = dt.datetime.utcnow().isoformat() + 'Z'
    (REPORT_DIR / 'import-report.json').write_text(json.dumps(report, indent=1, ensure_ascii=False))
    lines = ['# Library import report', '',
             f"- Started {report['started']} · finished {report['finished']}",
             f"- Copyright rule: every author/translator died ≤ {CUTOFF_DEATH_YEAR} (life + 70)", '']
    for ph in ('se', 'gt'):
        if report.get(ph):
            lines.append(f'## {ph.upper()}')
            for k, v in report[ph].items():
                lines.append(f'- {k}: {v}')
            lines.append('')
    lines.append(f"Excluded for copyright: {len(report['excluded_copyright'])}")
    for e in report['excluded_copyright'][:60]:
        lines.append(f"- {e.get('title')} — {', '.join(str(p) for p in e.get('people', []))}")
    if report.get('verify'):
        lines += ['', '## Live read-through check']
        for c in report['verify']:
            lines.append(f"- {c['book']} ch {c['chapter']}: " + (c.get('error') or
                         f"{c['chars']} chars in {c['ms']} ms — {c['start'][:90]!r}"))
    if report.get('errors'):
        lines += ['', '## Errors'] + [f'- {e}' for e in report['errors'][:40]]
    (REPORT_DIR / 'import-report.md').write_text('\n'.join(lines) + '\n')


def main():
    if not DRY_RUN and (not FN_URL or not TOKEN):
        sys.exit('FN_URL and IMPORT_TOKEN are required (or DRY_RUN=true)')
    existing = library_index() if TOKEN else []
    log(f'Library now: {len(existing)} books')
    existing_by_key = {}
    for b in existing:
        if b['id'].startswith('bulk-'):
            existing_by_key.setdefault(book_key(b['title'], b['authorName']), b)
    report['library_before'] = len(existing)
    lifespans = Lifespans()
    se_books, se_keys, gt_books = [], set(), []
    try:
        if 'se' in PHASES:
            se_books, se_keys = se_phase(existing_by_key, lifespans)
            post_books(se_books, 'se')
        if 'gt' in PHASES:
            se_new = sum(1 for b in se_books if 'id' not in b)
            gt_books = gt_phase(existing, existing_by_key, se_keys, se_new)
            post_books(gt_books, 'gt')
    except Exception as e:
        report['errors'].append(repr(e)[:500])
        write_report()
        raise
    if TOKEN:
        report['library_after'] = len(library_index())
        if not DRY_RUN:
            verify(se_books[:3] + (gt_books[:3] if 'gt' in PHASES else []))
    write_report()
    log('Done:', json.dumps({k: report.get(k) for k in ('library_before', 'library_after')}))


if __name__ == '__main__':
    main()
