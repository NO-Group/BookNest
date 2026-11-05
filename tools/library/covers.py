#!/usr/bin/env python3
"""BookNest library covers: one unique AI-painted cover per library book.

Pipeline per book
  1. Prompt: genre art style + palette + a scene from the book's own
     description (title/author give the model context). No text in art.
  2. Art: Pollinations (FLUX), seed derived from the book id → stable,
     different for every book.
  3. Uniqueness: perceptual hash (pHash) of the art; anything within
     DUP_DISTANCE bits of another cover is repainted with a new seed.
  4. Typography: title + author set with open-licence (OFL/Apache)
     Google Fonts, layout varied per book, readable scrim + shadow.
  5. Hosting: Cloudinary (images only), then admin.setCovers.

Modes (MODE env)
  index     write books.json — every library book still needing an AI cover
  shard     paint covers for shard SHARD of SHARDS → manifest-<shard>.jsonl
  finalize  cross-shard duplicate check, then record covers on the server
  probe     paint PROBE_COUNT samples into samples/ (quality check)
"""
from __future__ import annotations

import hashlib
import io
import json
import os
import random
import re
import sys
import textwrap
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageStat

try:
    import imagehash
except Exception:  # pragma: no cover - installed in CI
    imagehash = None

HERE = Path(__file__).resolve().parent
FN_URL = os.environ.get('FN_URL', '').rstrip('/')
ANON = os.environ.get('ANON', '')
TOKEN = os.environ.get('IMPORT_TOKEN', '')
POLLI = os.environ.get('POLLINATIONS_TOKEN', '').strip()
MODE = os.environ.get('MODE', 'probe')
SHARD = int(os.environ.get('SHARD') or 0)
SHARDS = int(os.environ.get('SHARDS') or 1)
WORK = Path(os.environ.get('WORK_DIR') or (HERE / 'work'))
FORCE = os.environ.get('FORCE', 'false').lower() == 'true'
TIME_BUDGET = float(os.environ.get('TIME_BUDGET_MIN') or 320) * 60
RATE = float(os.environ.get('RATE_SECONDS') or (5.5 if POLLI else 16))
DUP_DISTANCE = 6
W, H = 768, 1152
CLOUD, PRESET = 'deqdmwlt7', 'BookNest'
UA = 'BookNest-covers/1.0 (https://github.com/NO-Group/BookNest)'
STYLE_TAG = 'ai-v1'
T0 = time.time()


def log(*a):
    print(*a, flush=True)


def h32(s: str) -> int:
    return int(hashlib.sha1(s.encode()).hexdigest()[:8], 16)


# ── art direction ───────────────────────────────────────────────────────────

STYLES = {
    'Romance': ['soft romantic watercolor painting', 'impressionist oil painting with warm dappled light',
                'pre-Raphaelite painting, lush and luminous', 'delicate gouache illustration, pastel tones'],
    'Mystery & Crime': ['film noir ink and wash illustration, dramatic shadows', 'art deco travel-poster style',
                        'moody oil painting, gaslight and fog', 'vintage pulp magazine painting'],
    'Horror': ['dark gothic oil painting, candlelight and deep shadow', 'eerie woodcut print, stark contrast',
               'unsettling symbolist painting', 'misty victorian etching with crimson accents'],
    'Science Fiction': ['retro-futurist gouache illustration', 'vintage 1950s science fiction pulp painting',
                        'luminous cosmic matte painting', 'bold mid-century modern screen print'],
    'Fantasy': ['enchanted storybook illustration, glowing light', 'art nouveau illustration with ornate flowing lines',
                'epic romantic landscape painting', 'jewel-toned medieval illuminated style painting'],
    'Thriller & Suspense': ['cinematic oil painting, stormy and kinetic', 'bold linocut print, high contrast',
                            'vintage adventure poster painting', 'dramatic chiaroscuro painting'],
    'Westerns': ['sun-bleached western oil painting', 'vintage western poster, dusty earth tones',
                 'plein-air painting of the frontier'],
    'Historical Fiction': ['classical oil painting in the manner of a museum masterpiece',
                           'rich baroque painting', 'faded fresco style painting', 'romantic era history painting'],
    'Young Adult (YA)': ['charming golden-age picture book illustration', 'bright whimsical gouache illustration',
                         'vintage children’s book lithograph'],
    'Biographies & Memoirs': ['dignified painterly portrait-style scene', 'sepia-toned engraving style illustration',
                              'warm muted oil sketch'],
    'History & Politics': ['monumental neoclassical painting', 'antique engraving with hand tinting',
                           'bold constructivist poster style'],
    'Humanities & Social Sciences': ['contemplative symbolist painting', 'minimal ink illustration with a single motif',
                                     'serene classical still life painting'],
    'STEM': ['antique scientific illustration plate', 'elegant blueprint-style illustration',
             'naturalist watercolor study'],
    'Self-Help & Wellness': ['calm luminous landscape painting', 'minimal zen ink painting'],
    'Finance & Economics': ['vintage industrial age engraving', 'bold art deco illustration'],
    'Languages & Linguistics': ['ornamental antique typographic-free engraving', 'illuminated manuscript inspired painting'],
    'Literary Fiction': ['expressive impressionist oil painting', 'quiet atmospheric watercolor',
                         'post-impressionist painting with bold brushwork', 'elegant mid-century illustration',
                         'tonalist landscape painting', 'modernist gouache illustration'],
}
PALETTES = ['deep teal and burnt orange', 'midnight blue and gold', 'crimson and charcoal', 'sage green and cream',
            'plum and copper', 'ochre and slate blue', 'emerald and ivory', 'rose and dusky violet',
            'sepia and amber', 'ink black and scarlet', 'sky blue and sand', 'forest green and rust',
            'lavender and silver', 'indigo and coral', 'olive and mustard', 'storm grey and lemon',
            'turquoise and terracotta', 'wine red and bone white', 'peacock blue and bronze', 'moss and blush pink']

FONTS = {  # (title font, author font) — google/fonts paths (OFL/Apache)
    'Romance': [('ofl/playfairdisplay/PlayfairDisplay[wght].ttf', 'ofl/cormorantgaramond/CormorantGaramond[wght].ttf'),
                ('ofl/greatvibes/GreatVibes-Regular.ttf', 'ofl/lora/Lora[wght].ttf')],
    'Mystery & Crime': [('ofl/bebasneue/BebasNeue-Regular.ttf', 'ofl/oswald/Oswald[wght].ttf'),
                        ('apache/specialelite/SpecialElite-Regular.ttf', 'ofl/oswald/Oswald[wght].ttf')],
    'Horror': [('ofl/unifrakturmaguntia/UnifrakturMaguntia-Book.ttf', 'ofl/cormorantgaramond/CormorantGaramond[wght].ttf'),
               ('ofl/cinzel/Cinzel[wght].ttf', 'ofl/ebgaramond/EBGaramond[wght].ttf')],
    'Science Fiction': [('ofl/orbitron/Orbitron[wght].ttf', 'ofl/josefinsans/JosefinSans[wght].ttf'),
                        ('ofl/anton/Anton-Regular.ttf', 'ofl/montserrat/Montserrat[wght].ttf')],
    'Fantasy': [('ofl/cinzel/Cinzel[wght].ttf', 'ofl/marcellus/Marcellus-Regular.ttf'),
                ('ofl/imfellenglish/IMFeENrm28P.ttf', 'ofl/cormorantgaramond/CormorantGaramond[wght].ttf')],
    'Westerns': [('ofl/rye/Rye-Regular.ttf', 'ofl/oswald/Oswald[wght].ttf')],
    'Thriller & Suspense': [('ofl/anton/Anton-Regular.ttf', 'ofl/oswald/Oswald[wght].ttf'),
                            ('ofl/bebasneue/BebasNeue-Regular.ttf', 'ofl/montserrat/Montserrat[wght].ttf')],
    '_default': [('ofl/playfairdisplay/PlayfairDisplay[wght].ttf', 'ofl/sourcesans3/SourceSans3[wght].ttf'),
                 ('ofl/librebaskerville/LibreBaskerville[wght].ttf', 'ofl/josefinsans/JosefinSans[wght].ttf'),
                 ('ofl/dmserifdisplay/DMSerifDisplay-Regular.ttf', 'ofl/montserrat/Montserrat[wght].ttf'),
                 ('ofl/abrilfatface/AbrilFatface-Regular.ttf', 'ofl/lora/Lora[wght].ttf'),
                 ('ofl/ebgaramond/EBGaramond[wght].ttf', 'ofl/spectral/Spectral-Regular.ttf'),
                 ('ofl/cinzel/Cinzel[wght].ttf', 'ofl/sourcesans3/SourceSans3[wght].ttf'),
                 ('ofl/marcellus/Marcellus-Regular.ttf', 'ofl/spectral/Spectral-Regular.ttf')],
}
FONT_DIR = WORK / 'fonts'


def font_file(path: str) -> Path:
    FONT_DIR.mkdir(parents=True, exist_ok=True)
    local = FONT_DIR / path.replace('/', '__')
    if not local.exists():
        url = 'https://raw.githubusercontent.com/google/fonts/main/' + urllib.parse.quote(path)
        data = get(url, timeout=60)
        if not data:
            raise RuntimeError(f'font unavailable: {path}')
        local.write_bytes(data)
    return local


def load_font(path: str, size: int, weight: int | None = None) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(font_file(path)), size)
    if weight and '[' in path:
        try:
            axes = f.get_variation_axes()
            f.set_variation_by_axes([max(a['minimum'], min(a['maximum'], weight)) if i == 0 else a.get('default', a['minimum'])
                                     for i, a in enumerate(axes)])
        except Exception:
            pass
    return f


def scene_of(book: dict) -> str:
    d = re.sub(r'\s+', ' ', book.get('description') or '').strip()
    d = re.sub(r'["“”]', '', d)
    d = re.sub(r'^(A|An|The) beloved [^,]+ classic by [^,]+, among the most-read .*$', '', d)
    first = re.split(r'(?<=[.!?])\s', d)[0] if d else ''
    if len(first) < 40 and d:
        first = d[:260]
    return first[:260]


def build_prompt(book: dict, salt: int = 0) -> tuple[str, int]:
    g = book.get('genre') or 'Literary Fiction'
    key = book['id'] + (f'#{salt}' if salt else '')
    styles = STYLES.get(g, STYLES['Literary Fiction'])
    style = styles[h32(key + 's') % len(styles)]
    palette = PALETTES[h32(key + 'p') % len(PALETTES)]
    scene = scene_of(book)
    subject = f"the classic book {book['title']} by {book.get('authorName') or 'an unknown author'}"
    prompt = (f'Cover artwork evoking {subject}. ' + (f'Scene: {scene} ' if scene else '') +
              f'Style: {style}, palette of {palette}. One striking focal image, rich detail, '
              f'cinematic composition with calm uncluttered space near the top and bottom. '
              f'No text, no letters, no words, no title, no typography, no watermark, no signature, no border.')
    seed = h32(key + 'seed') % 2_000_000_000
    return prompt[:900], seed


# ── network ─────────────────────────────────────────────────────────────────

def get(url: str, timeout: int = 60, tries: int = 3, headers: dict | None = None) -> bytes | None:
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': UA, **(headers or {})})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            if e.code == 429:
                time.sleep(15 * (attempt + 1))
        except Exception:
            pass
        time.sleep(2 * (attempt + 1))
    return None


def api(action: str, payload: dict, timeout: int = 120):
    body = json.dumps({'action': action, 'importToken': TOKEN, **payload}).encode()
    last = None
    for attempt in range(5):
        req = urllib.request.Request(FN_URL, data=body, method='POST',
                                     headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + ANON})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                out = json.loads(r.read().decode())
            return out.get('data', out)
        except urllib.error.HTTPError as e:
            last = f'HTTP {e.code}: {e.read().decode("utf-8", "replace")[:200]}'
            if e.code in (401, 403):
                raise RuntimeError(last)
        except Exception as e:
            last = repr(e)
        time.sleep(3 * (attempt + 1))
    raise RuntimeError(f'{action} failed: {last}')


_last_call = [0.0]
stats = {'requests': 0, 'ok': 0, 'http_errors': {}, 'seconds': []}


def paint(prompt: str, seed: int) -> Image.Image | None:
    wait = RATE - (time.time() - _last_call[0])
    if wait > 0:
        time.sleep(wait)
    params = {'width': W, 'height': H, 'seed': seed, 'model': 'flux', 'nologo': 'true',
              'private': 'true', 'enhance': 'false', 'safe': 'true'}
    url = 'https://image.pollinations.ai/prompt/' + urllib.parse.quote(prompt, safe='') + '?' + urllib.parse.urlencode(params)
    headers = {'User-Agent': UA}
    if POLLI:
        headers['Authorization'] = f'Bearer {POLLI}'
    for attempt in range(4):
        t = time.time()
        _last_call[0] = t
        stats['requests'] += 1
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=180) as r:
                data = r.read()
                ctype = r.headers.get('Content-Type', '')
            if not ctype.startswith('image/') or len(data) < 10_000:
                stats['http_errors']['not-image'] = stats['http_errors'].get('not-image', 0) + 1
                time.sleep(RATE)
                continue
            img = Image.open(io.BytesIO(data)).convert('RGB')
            stats['ok'] += 1
            stats['seconds'].append(round(time.time() - t, 1))
            return img
        except urllib.error.HTTPError as e:
            stats['http_errors'][str(e.code)] = stats['http_errors'].get(str(e.code), 0) + 1
            time.sleep(RATE * (3 if e.code == 429 else 1) * (attempt + 1))
        except Exception as e:
            stats['http_errors'][type(e).__name__] = stats['http_errors'].get(type(e).__name__, 0) + 1
            time.sleep(RATE * (attempt + 1))
    return None


def upload(jpeg: bytes, public_id: str) -> str | None:
    boundary = 'bn' + hashlib.md5(public_id.encode()).hexdigest()[:16]
    parts = []
    for name, value in (('upload_preset', PRESET), ('folder', 'booknest/covers'), ('public_id', public_id)):
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode())
    parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{public_id}.jpg"\r\n'
                 f'Content-Type: image/jpeg\r\n\r\n'.encode() + jpeg + b'\r\n')
    parts.append(f'--{boundary}--\r\n'.encode())
    req = urllib.request.Request(f'https://api.cloudinary.com/v1_1/{CLOUD}/image/upload', data=b''.join(parts),
                                 method='POST', headers={'Content-Type': f'multipart/form-data; boundary={boundary}',
                                                         'User-Agent': UA})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                url = json.loads(r.read().decode()).get('secure_url')
            if isinstance(url, str) and url.startswith('https://res.cloudinary.com/'):
                return url
        except Exception as e:
            log('  upload retry', attempt, repr(e)[:160])
        time.sleep(3 * (attempt + 1))
    return None


# ── typography ──────────────────────────────────────────────────────────────

def fit_title(draw, text, font_path, max_w, max_h, start, minimum, weight):
    size = start
    while size >= minimum:
        font = load_font(font_path, size, weight)
        avg = max(1, font.getlength('abcdefghijklmnopqrstuvwxyz') / 26)
        width_chars = max(6, int(max_w / avg))
        lines = textwrap.wrap(text, width=width_chars, break_long_words=False) or [text]
        widths = [draw.textlength(l, font=font) for l in lines]
        line_h = int(size * 1.12)
        if max(widths) <= max_w and line_h * len(lines) <= max_h and len(lines) <= 5:
            return font, lines, line_h
        size -= 4
    font = load_font(font_path, minimum, weight)
    lines = textwrap.wrap(text, width=max(8, int(max_w / (minimum * 0.5))))[:5]
    return font, lines, int(minimum * 1.12)


def compose(art: Image.Image, book: dict) -> Image.Image:
    img = art.resize((W, H)) if art.size != (W, H) else art.copy()
    key = book['id']
    genre = book.get('genre') or ''
    pairs = FONTS.get(genre, FONTS['_default'])
    title_font, author_font = pairs[h32(key + 'f') % len(pairs)]
    layout = ['top', 'bottom', 'band', 'frame'][h32(key + 'l') % 4]
    title = re.sub(r'\s+', ' ', book['title']).strip()
    if title_font.endswith(('BebasNeue-Regular.ttf', 'Anton-Regular.ttf', 'Orbitron[wght].ttf', 'Cinzel[wght].ttf')):
        title = title.upper()
    author = (book.get('authorName') or '').strip()
    margin = 56
    draw = ImageDraw.Draw(img)
    zone_h = 380 if layout != 'band' else 330
    if layout in ('top', 'frame'):
        zone = (0, 0, W, zone_h + 40)
    elif layout == 'bottom':
        zone = (0, H - zone_h - 120, W, H)
    else:
        zone = (0, int(H * 0.56), W, int(H * 0.56) + zone_h)
    region = img.crop(zone)
    bright = ImageStat.Stat(region.convert('L')).mean[0]
    dark_text = layout == 'band' and h32(key + 'b') % 2 == 0
    overlay = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    if layout == 'band':
        fill = (245, 240, 230, 225) if dark_text else (15, 15, 20, 190)
        od.rectangle(zone, fill=fill)
    else:
        top, bottom = zone[1], zone[3]
        strength = 200 if bright > 120 else 150
        for y in range(top, bottom):
            t = (y - top) / max(1, bottom - top)
            a = int(strength * ((1 - t) if layout in ('top', 'frame') else t) ** 1.3)
            od.line([(0, y), (W, y)], fill=(8, 8, 12, a))
    if layout == 'frame':
        od.rectangle((22, 22, W - 22, H - 22), outline=(255, 255, 255, 170), width=3)
    img = Image.alpha_composite(img.convert('RGBA'), overlay)
    draw = ImageDraw.Draw(img)
    ink = (28, 24, 22) if dark_text else (255, 252, 245)
    shadow = None if dark_text else (0, 0, 0)
    font, lines, line_h = fit_title(draw, title, title_font, W - 2 * margin, zone_h - 130, 96, 40, 800)
    block_h = line_h * len(lines)
    if layout in ('top', 'frame'):
        y = margin + 10
    elif layout == 'bottom':
        y = H - margin - 90 - block_h
    else:
        y = zone[1] + 40
    for line in lines:
        w_ = draw.textlength(line, font=font)
        x = (W - w_) / 2
        if shadow:
            sh = Image.new('RGBA', img.size, (0, 0, 0, 0))
            ImageDraw.Draw(sh).text((x + 3, y + 4), line, font=font, fill=(0, 0, 0, 200))
            img = Image.alpha_composite(img, sh.filter(ImageFilter.GaussianBlur(4)))
            draw = ImageDraw.Draw(img)
        draw.text((x, y), line, font=font, fill=ink)
        y += line_h
    if author:
        af = load_font(author_font, 34, 600)
        label = author.upper() if h32(key + 'a') % 2 else author
        while draw.textlength(label, font=af) > W - 2 * margin and af.size > 20:
            af = load_font(author_font, af.size - 2, 600)
        aw = draw.textlength(label, font=af)
        if layout == 'bottom':
            ay = H - margin - 44
        elif layout == 'band':
            ay = min(y + 22, zone[3] - 50)
        else:
            ay = y + 18
        draw.line([((W - 60) / 2, ay - 14), ((W + 60) / 2, ay - 14)], fill=ink, width=2)
        if shadow:
            draw.text(((W - aw) / 2 + 2, ay + 2), label, font=af, fill=(0, 0, 0))
        draw.text(((W - aw) / 2, ay), label, font=af, fill=ink)
    return img.convert('RGB')


def phash(img: Image.Image) -> str:
    if imagehash is None:
        return hashlib.sha1(img.resize((16, 16)).tobytes()).hexdigest()[:16]
    return str(imagehash.phash(img))


def distance(a: str, b: str) -> int:
    try:
        return bin(int(a, 16) ^ int(b, 16)).count('1')
    except Exception:
        return 64


def public_id(book: dict, ph: str) -> str:
    base = re.sub(r'[^a-z0-9-]+', '-', book['id'].lower().replace('|', '-'))[:70].strip('-')
    return f'ai-{base}-{ph[:8]}'


def make_cover(book: dict, known: list[str]) -> dict | None:
    for salt in range(3):
        prompt, seed = build_prompt(book, salt)
        art = paint(prompt, seed)
        if art is None:
            continue
        ph = phash(art)
        if any(distance(ph, k) <= DUP_DISTANCE for k in known):
            log(f'  near-duplicate art for {book["id"]} — repainting')
            continue
        cover = compose(art, book)
        buf = io.BytesIO()
        cover.save(buf, 'JPEG', quality=86, optimize=True, progressive=True)
        return {'id': book['id'], 'phash': ph, 'jpeg': buf.getvalue(), 'prompt': prompt, 'seed': seed}
    return None


# ── modes ───────────────────────────────────────────────────────────────────

def mode_index():
    WORK.mkdir(parents=True, exist_ok=True)
    rows, after = [], None
    while True:
        out = api('admin.libraryIndex', {'limit': 1000, **({'after': after} if after else {})})
        rows += out.get('books', [])
        after = out.get('next')
        if not after:
            break
    todo = [b for b in rows if FORCE or b.get('coverStyle') != STYLE_TAG]
    known = [b['coverHash'] for b in rows if b.get('coverStyle') == STYLE_TAG and b.get('coverHash')]
    (WORK / 'books.json').write_text(json.dumps({'todo': todo, 'known': known}))
    log(f'library {len(rows)} · need covers {len(todo)} · already AI {len(rows) - len(todo)}')
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with open(summary, 'a') as f:
            f.write(f'## Covers index\n\n- Library books: {len(rows)}\n- Need an AI cover: {len(todo)}\n')


def mode_shard():
    data = json.loads((WORK / 'books.json').read_text())
    mine = [b for b in data['todo'] if h32(b['id']) % SHARDS == SHARD]
    known = list(data['known'])
    out_path = WORK / f'manifest-{SHARD}.jsonl'
    done = 0
    log(f'shard {SHARD}/{SHARDS}: {len(mine)} books · rate {RATE}s · budget {TIME_BUDGET / 60:.0f} min')
    with out_path.open('a') as out:
        for i, book in enumerate(mine, 1):
            if time.time() - T0 > TIME_BUDGET:
                log('time budget reached — the next run continues from here')
                break
            try:
                c = make_cover(book, known)
                if not c:
                    continue
                url = upload(c['jpeg'], public_id(book, c['phash']))
                if not url:
                    continue
                known.append(c['phash'])
                out.write(json.dumps({'id': book['id'], 'coverUrl': url, 'coverHash': c['phash']}) + '\n')
                out.flush()
                done += 1
            except Exception as e:
                log(f'  {book["id"]}: {repr(e)[:200]}')
            if i % 25 == 0:
                avg = sum(stats['seconds']) / max(1, len(stats['seconds']))
                log(f'  {i}/{len(mine)} · covers {done} · avg paint {avg:.1f}s · errors {stats["http_errors"]}')
    log(f'shard {SHARD} done: {done} covers · {stats}')


def mode_finalize():
    manifests = sorted(WORK.glob('**/manifest-*.jsonl'))
    rows = []
    for m in manifests:
        rows += [json.loads(l) for l in m.read_text().splitlines() if l.strip()]
    data = json.loads((WORK / 'books.json').read_text()) if (WORK / 'books.json').exists() else {'known': []}
    accepted, hashes, dropped = [], list(data.get('known', [])), 0
    for r in rows:
        if any(distance(r['coverHash'], k) <= DUP_DISTANCE for k in hashes):
            dropped += 1  # left for the next run, which repaints it
            continue
        hashes.append(r['coverHash'])
        accepted.append(r)
    updated = 0
    for i in range(0, len(accepted), 100):
        batch = [{**r, 'coverStyle': STYLE_TAG} for r in accepted[i:i + 100]]
        res = api('admin.setCovers', {'covers': batch})
        updated += int(res.get('updated', 0))
    msg = f'covers painted {len(rows)} · cross-shard duplicates held back {dropped} · recorded {updated}'
    log(msg)
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with open(summary, 'a') as f:
            f.write(f'## Covers recorded\n\n- {msg}\n')


def mode_probe():
    out = HERE / 'samples'
    out.mkdir(parents=True, exist_ok=True)
    books = []
    if (WORK / 'books.json').exists():
        todo = json.loads((WORK / 'books.json').read_text())['todo']
        random.Random(7).shuffle(todo)
        books = todo
    if not books:
        books = [
            {'id': 'bulk-pride-and-prejudice|jane-austen', 'title': 'Pride and Prejudice', 'authorName': 'Jane Austen',
             'genre': 'Romance', 'description': 'A country family swirls into uproar when a wealthy, proud stranger moves into the neighbourhood.'},
            {'id': 'bulk-dracula|bram-stoker', 'title': 'Dracula', 'authorName': 'Bram Stoker', 'genre': 'Horror',
             'description': 'A young lawyer travels to Count Dracula’s castle and unleashes an ancient hunger on modern Europe.'},
            {'id': 'bulk-the-time-machine|h-g-wells', 'title': 'The Time Machine', 'authorName': 'H. G. Wells',
             'genre': 'Science Fiction', 'description': 'A Victorian inventor travels to the year 802,701 and finds humanity divided.'},
            {'id': 'bulk-the-hound-of-the-baskervilles|arthur-conan-doyle', 'title': 'The Hound of the Baskervilles',
             'authorName': 'Arthur Conan Doyle', 'genre': 'Mystery & Crime',
             'description': 'Sherlock Holmes investigates a spectral hound haunting a family on the moors of Devon.'},
            {'id': 'bulk-treasure-island|robert-louis-stevenson', 'title': 'Treasure Island', 'authorName': 'Robert Louis Stevenson',
             'genre': 'Thriller & Suspense', 'description': 'An innkeeper’s son finds a treasure map and sails with a dangerous crew.'},
            {'id': 'bulk-the-picture-of-dorian-gray|oscar-wilde', 'title': 'The Picture of Dorian Gray', 'authorName': 'Oscar Wilde',
             'genre': 'Literary Fiction', 'description': 'A beautiful young man stays young while his portrait grows old and wicked in the attic.'},
        ]
    count = int(os.environ.get('PROBE_COUNT') or 6)
    lines = ['# Cover probe', '', f'- rate {RATE}s · token: {"yes" if POLLI else "no (anonymous)"}', '']
    known: list[str] = []
    for book in books[:count]:
        t = time.time()
        c = make_cover(book, known)
        if not c:
            lines.append(f'- FAILED {book["title"]}')
            continue
        known.append(c['phash'])
        name = re.sub(r'[^a-z0-9]+', '-', book['title'].lower()).strip('-')[:40] + '.jpg'
        (out / name).write_bytes(c['jpeg'])
        lines.append(f'- {name}: {time.time() - t:.1f}s · seed {c["seed"]} · phash {c["phash"]}')
        lines.append(f'  - prompt: {c["prompt"][:300]}')
    lines += ['', f'stats: {json.dumps(stats)}']
    (out / 'probe.md').write_text('\n'.join(lines) + '\n')
    log('\n'.join(lines))


if __name__ == '__main__':
    {'index': mode_index, 'shard': mode_shard, 'finalize': mode_finalize, 'probe': mode_probe}[MODE]()
