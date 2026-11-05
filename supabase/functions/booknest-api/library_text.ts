// ============================================================================
// Library texts — read-through from public GitHub sources (no storage).
// ============================================================================
// Imported classics keep only metadata in MongoDB. Each chapter stores a
// `source` pointer, pinned to an exact commit so the text can never change
// under a reader:
//   • se → a Standard Ebooks XHTML chapter (one file per chapter)
//   • gt → a byte range inside a GITenberg plain-text file (the original
//          Project Gutenberg text; header/footer already excluded by range)
// The edge function resolves the pointer when a reader opens the chapter,
// converts it to the reader's text format and returns it inline — so every
// app version (old APKs included) reads it with no app change.
// When the R2 bucket arrives, a one-off job copies these texts and rewrites
// the pointers; nothing else changes.
// ============================================================================

import { AwsClient } from 'npm:aws4fetch@1.0.20';

export type ChapterSource = {
  kind: 'se' | 'gt' | 'r2';
  url?: string; // se / gt
  key?: string; // r2: object key inside the BookNest bucket
  more?: string[]; // se: up to 5 following files read as one chapter
  start?: number; // gt: first byte (inclusive)
  end?: number; // gt: last byte (exclusive)
  enc?: 'utf-8' | 'latin1';
};

// Only these public repos may ever be fetched (no SSRF through a pointer).
const ALLOWED = /^https:\/\/raw\.githubusercontent\.com\/(standardebooks|GITenberg)\/[\w.-]+\/[0-9a-f]{40}\/[\w./%-]+$/;

const R2_KEY = /^(?!.*\.\.)[A-Za-z0-9][\w./|%-]{0,299}$/;

export function isLibrarySource(value: unknown): value is ChapterSource {
  if (!value || typeof value !== 'object') return false;
  const s = value as Record<string, unknown>;
  if (s.kind === 'r2') return typeof s.key === 'string' && R2_KEY.test(s.key);
  if (s.kind !== 'se' && s.kind !== 'gt') return false;
  if (typeof s.url !== 'string' || !ALLOWED.test(s.url)) return false;
  if (s.more !== undefined) {
    if (s.kind !== 'se' || !Array.isArray(s.more) || s.more.length > 5) return false;
    if (!s.more.every((u) => typeof u === 'string' && ALLOWED.test(u))) return false;
  }
  if (s.kind === 'gt') {
    const start = Number(s.start), end = Number(s.end);
    if (!Number.isInteger(start) || !Number.isInteger(end)) return false;
    if (start < 0 || end <= start || end - start > 3_000_000) return false;
  }
  return true;
}

/** Normalizes an untrusted source object to exactly the stored fields. */
export function cleanSource(value: unknown): ChapterSource | null {
  if (!isLibrarySource(value)) return null;
  const s = value as ChapterSource;
  if (s.kind === 'r2') return { kind: 'r2', key: s.key };
  const out: ChapterSource = { kind: s.kind, url: s.url };
  if (s.kind === 'se' && Array.isArray(s.more) && s.more.length) out.more = [...s.more];
  if (s.kind === 'gt') {
    out.start = Number(s.start);
    out.end = Number(s.end);
    out.enc = s.enc === 'latin1' ? 'latin1' : 'utf-8';
  }
  return out;
}

/** jsDelivr mirrors any public GitHub file — the fallback when raw is slow. */
function mirrorUrl(raw: string): string | null {
  const m = raw.match(/^https:\/\/raw\.githubusercontent\.com\/([^/]+)\/([^/]+)\/([0-9a-f]{40})\/(.+)$/);
  return m ? `https://cdn.jsdelivr.net/gh/${m[1]}/${m[2]}@${m[3]}/${m[4]}` : null;
}

// Small in-memory cache: popular chapters answer without leaving the edge.
const CACHE_LIMIT_BYTES = 24 * 1024 * 1024;
const textCache = new Map<string, string>();
let cacheBytes = 0;

function cachePut(key: string, text: string) {
  if (text.length > CACHE_LIMIT_BYTES / 4) return;
  if (textCache.has(key)) return;
  textCache.set(key, text);
  cacheBytes += text.length;
  while (cacheBytes > CACHE_LIMIT_BYTES && textCache.size) {
    const oldest = textCache.keys().next().value as string;
    cacheBytes -= textCache.get(oldest)?.length ?? 0;
    textCache.delete(oldest);
  }
}

function cacheGet(key: string): string | undefined {
  const hit = textCache.get(key);
  if (hit !== undefined) {
    // refresh LRU position
    textCache.delete(key);
    textCache.set(key, hit);
  }
  return hit;
}

async function fetchBytes(
  url: string,
  range?: { start: number; end: number },
): Promise<Uint8Array> {
  const urls = [url, mirrorUrl(url)].filter(Boolean) as string[];
  let lastError: unknown = null;
  for (const target of urls) {
    try {
      const headers: Record<string, string> = { 'User-Agent': 'BookNest-library' };
      if (range) headers.Range = `bytes=${range.start}-${range.end - 1}`;
      const res = await fetch(target, {
        headers,
        signal: AbortSignal.timeout(12_000),
      });
      if (!res.ok && res.status !== 206) {
        lastError = new Error(`HTTP ${res.status}`);
        continue;
      }
      const buf = new Uint8Array(await res.arrayBuffer());
      if (range && res.status !== 206) {
        // Host ignored the Range header — slice the full file ourselves.
        return buf.slice(range.start, range.end);
      }
      return buf;
    } catch (e) {
      lastError = e;
    }
  }
  throw lastError instanceof Error ? lastError : new Error('Library source unreachable');
}

// ── Cloudflare R2 (private bucket, signed reads) ─────────────────────────────
let r2Client: AwsClient | null = null;

function r2(): { client: AwsClient; base: string } {
  const account = Deno.env.get('R2_ACCOUNT_ID') ?? '';
  const bucket = Deno.env.get('R2_BUCKET') ?? '';
  const accessKeyId = Deno.env.get('R2_ACCESS_KEY_ID') ?? '';
  const secretAccessKey = Deno.env.get('R2_SECRET_ACCESS_KEY') ?? '';
  if (!account || !bucket || !accessKeyId || !secretAccessKey) {
    throw new Error('R2 is not configured on the server');
  }
  r2Client ??= new AwsClient({ accessKeyId, secretAccessKey, service: 's3', region: 'auto' });
  return { client: r2Client, base: `https://${account}.r2.cloudflarestorage.com/${bucket}/` };
}

async function fetchR2(key: string): Promise<string> {
  const { client, base } = r2();
  const url = base + key.split('/').map(encodeURIComponent).join('/');
  let last: unknown = null;
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const res = await client.fetch(url, { signal: AbortSignal.timeout(10_000) });
      if (res.ok) return await res.text();
      last = new Error(`R2 HTTP ${res.status}`);
      if (res.status === 404) break;
    } catch (e) {
      last = e;
    }
  }
  throw last instanceof Error ? last : new Error('R2 unreachable');
}

/** Resolves a chapter pointer to reader-ready text (cached). */
export async function resolveSourceText(source: ChapterSource): Promise<string> {
  if (source.kind === 'r2') {
    const cacheKey = `r2:${source.key}`;
    const hit = cacheGet(cacheKey);
    if (hit !== undefined) return hit;
    const text = await fetchR2(source.key ?? '');
    cachePut(cacheKey, text);
    return text;
  }
  const key = source.kind === 'gt'
    ? `${source.url}#${source.start}-${source.end}`
    : [source.url ?? '', ...(source.more ?? [])].join('|');
  const cached = cacheGet(key);
  if (cached !== undefined) return cached;
  let text: string;
  if (source.kind === 'se') {
    const files = await Promise.all(
      [source.url ?? '', ...(source.more ?? [])].map((u) => fetchBytes(u)));
    text = files
      .map((bytes) => seXhtmlToText(new TextDecoder('utf-8').decode(bytes)))
      .filter((t) => t.length > 0)
      .join('\n\n');
  } else {
    const bytes = await fetchBytes(source.url ?? '', {
      start: source.start ?? 0,
      end: source.end ?? 0,
    });
    const decoder = new TextDecoder(source.enc === 'latin1' ? 'latin1' : 'utf-8');
    text = gutenbergToText(decoder.decode(bytes));
  }
  cachePut(key, text);
  return text;
}

// ── converters ──────────────────────────────────────────────────────────────

const NAMED_ENTITIES: Record<string, string> = {
  amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: '\u00a0',
  mdash: '—', ndash: '–', hellip: '…', lsquo: '‘', rsquo: '’',
  ldquo: '“', rdquo: '”', shy: '',
};

export function decodeEntities(s: string): string {
  return s.replace(/&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);/g, (whole, code: string) => {
    if (code[0] === '#') {
      const n = code[1] === 'x' || code[1] === 'X'
        ? parseInt(code.slice(2), 16)
        : parseInt(code.slice(1), 10);
      return Number.isFinite(n) && n > 0 && n < 0x110000 ? String.fromCodePoint(n) : whole;
    }
    return NAMED_ENTITIES[code] ?? whole;
  });
}

const HARD_BREAK = '\u2028'; // sentinel → markdown hard break at the end

/**
 * Standard Ebooks XHTML → the reader's text format: paragraphs separated by
 * blank lines, `## ` headings, `> ` quotes, `***` scene breaks, and verse
 * lines ending in a markdown hard break. No emphasis markers on purpose —
 * the paged reader shows text literally.
 */
export function seXhtmlToText(xhtml: string): string {
  const bodyStart = xhtml.search(/<body[\s>]/i);
  let s = bodyStart >= 0 ? xhtml.slice(bodyStart) : xhtml;
  s = s.replace(/<\/body>[\s\S]*$/i, '');
  // Footnote markers point at endnotes we do not ship.
  s = s.replace(/<a\b[^>]*epub:type="[^"]*noteref[^"]*"[^>]*>[\s\S]*?<\/a>/gi, '');
  s = s.replace(/<img\b[^>]*>/gi, '');
  // Whitespace in XHTML source is not meaningful — collapse it first.
  s = s.replace(/\s+/g, ' ');
  // Subtitles inside a heading group read as sub-headings.
  s = s.replace(/<hgroup\b[^>]*>([\s\S]*?)<\/hgroup>/gi, (_m, inner: string) =>
    inner.replace(/<p\b[^>]*>([\s\S]*?)<\/p>/gi, '\n\n### $1\n\n'));
  s = s.replace(/<h([1-6])\b[^>]*>([\s\S]*?)<\/h\1>/gi, (_m, _l, inner: string) =>
    `\n\n## ${inner.replace(/<br\s*\/?>/gi, ' ')}\n\n`);
  s = s.replace(/<br\s*\/?>/gi, HARD_BREAK);
  s = s.replace(/<hr\b[^>]*\/?>/gi, '\n\n***\n\n');
  s = s.replace(/<li\b[^>]*>/gi, '\n- ').replace(/<\/li>/gi, '\n');
  s = s.replace(/<\/?(p|div|section|article|header|footer|table|tbody|thead|ul|ol|figure|figcaption|aside|nav|dl)\b[^>]*>/gi, '\n\n');
  s = s.replace(/<tr\b[^>]*>/gi, '\n').replace(/<\/t[dh]>/gi, '  ');
  s = s.replace(/<dt\b[^>]*>/gi, '\n\n').replace(/<dd\b[^>]*>/gi, '\n');
  // Block quotes: mark the region, then prefix its lines after tag removal.
  s = s.replace(/<blockquote\b[^>]*>/gi, '\n\n\u0001').replace(/<\/blockquote>/gi, '\u0002\n\n');
  s = s.replace(/<[^>]+>/g, '');
  s = decodeEntities(s);
  s = s.replace(/\u0001([\s\S]*?)\u0002/g, (_m, inner: string) =>
    inner.split('\n').map((line) => {
      const t = line.trim();
      return t ? `> ${t}` : '';
    }).join('\n'));
  s = s.replace(/[\u0001\u0002]/g, '');
  // Tidy lines; verse breaks become "line␠␠\n".
  const lines = s.split('\n').map((line) =>
    line.split(HARD_BREAK).map((part) => part.replace(/[ \t\u00a0]+/g, ' ').trim())
      .filter((part, i, all) => part.length > 0 || (i > 0 && i < all.length - 1))
      .join('  \n'));
  return lines.join('\n').replace(/\n{3,}/g, '\n\n').trim();
}

/** Gutenberg plain text slice → reader text (paragraphs kept, CRLF gone). */
export function gutenbergToText(raw: string): string {
  let s = raw.replace(/\r\n?/g, '\n').replace(/^\uFEFF/, '');
  // No trailing spaces (they would read as verse breaks) and no
  // typewriter double spaces after full stops.
  s = s.split('\n').map((line) => line.replace(/[ \t]+$/, '').replace(/([^ ]) {2,}/g, '$1 ')).join('\n');
  // _italics_ markers read as noise in the paged reader.
  s = s.replace(/(^|[\s(\[“"‘'—-])_([^_\n][^_]{0,300}?)_(?=$|[\s.,;:!?)\]”"’'—-])/gm, '$1$2');
  const blocks = s.split(/\n[ \t]*\n/).map((b) => b.trim()).filter(Boolean);
  if (blocks.length > 1) {
    // The chapter heading the importer split on becomes a real heading.
    const head = blocks[0].replace(/\s+/g, ' ');
    if (head.length <= 90 && blocks[0].split('\n').length <= 2) blocks[0] = `## ${head}`;
  }
  return blocks.join('\n\n');
}
