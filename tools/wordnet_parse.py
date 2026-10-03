"""WordNet 3.1 → BookNest dictionary entries.

Reads the classic WordNet database files and emits one entry per
(word, part-of-speech): merged senses, first example found, synonyms
from shared synsets. Honest parsing — no scraping, no guessing.
"""
import json, os, sys, re

DICT = sys.argv[1] if len(sys.argv) > 1 else 'node_modules/wordnet-db/dict'
OUT = sys.argv[2] if len(sys.argv) > 2 else '/tmp/wn/entries.jsonl'

POS_NAME = {'noun': 'noun', 'verb': 'verb', 'adj': 'adjective', 'adv': 'adverb'}
MAX_SENSES = 6
MAX_SYN = 10
MAX_DEF_CHARS = 1200

def parse_index(pos):
    """lemma -> list of synset offsets."""
    out = {}
    with open(os.path.join(DICT, f'index.{pos}'), encoding='utf-8', errors='replace') as f:
        for line in f:
            if line.startswith(' '):
                continue
            fields = line.split()
            if len(fields) < 9:
                continue
            lemma = fields[0].lower()
            try:
                synset_cnt = int(fields[2])
                p_cnt = int(fields[3])
            except ValueError:
                continue
            # layout: lemma pos cnt p_cnt [p_cnt pointers] sense_cnt tagsense_cnt offsets…
            offsets_at = 4 + p_cnt + 2     # skip pointers, sense_cnt, tagsense_cnt
            offsets = fields[offsets_at:offsets_at + synset_cnt]
            try:
                out[lemma] = [int(o) for o in offsets]
            except ValueError:
                continue
    return out

LEX_TASK = re.compile(r'";\s*"(.+?)"')  # example sentences inside gloss

def parse_data(pos):
    """offset -> (words, definition, example)."""
    out = {}
    with open(os.path.join(DICT, f'data.{pos}'), encoding='utf-8', errors='replace') as f:
        for line in f:
            if line.startswith('  '):
                continue
            try:
                offset = int(line.split(' ', 1)[0])
            except ValueError:
                continue
            bar = line.find('| ')
            if bar < 0:
                continue
            head = line[:bar]
            gloss = line[bar + 2:].strip()
            fields = head.split()
            try:
                w_cnt = int(fields[3])
            except ValueError:
                continue
            words = []
            idx = 4
            for _ in range(w_cnt):
                words.append(fields[idx].replace('_', ' '))
                idx += 2  # word + lex_id
            example = ''
            m = LEX_TASK.search(gloss)
            if m:
                example = m.group(1).strip()
            definition = LEX_TASK.sub('', gloss).split(';')[0].strip().rstrip(';').strip()
            out[offset] = (words, definition, example)
    return out

def main():
    total_new, total_senses, entries = 0, 0, []
    for pos in ('noun', 'verb', 'adj', 'adv'):
        index = parse_index(pos)
        data = parse_data(pos)
        print(f'{pos}: {len(index)} lemmas, {len(data)} synsets', flush=True)
        for lemma, offsets in index.items():
            senses, syns, example = [], [], ''
            for off in offsets:
                rec = data.get(off)
                if not rec:
                    continue
                words, definition, ex = rec
                if definition and definition not in senses:
                    senses.append(definition)
                    total_senses += 1
                for w in words:
                    if w.lower() != lemma and w not in syns:
                        syns.append(w)
                if not example and ex:
                    example = ex
                if len(senses) >= MAX_SENSES:
                    break
            if not senses:
                continue
            definition = ' '.join(f'{i+1}. {d}' for i, d in enumerate(senses))
            if len(definition) > MAX_DEF_CHARS:
                definition = definition[:MAX_DEF_CHARS - 3].rstrip() + '…'
            entries.append({'w': lemma.replace('_', ' '), 'p': POS_NAME[pos],
                            'd': definition, 'e': example[:300],
                            's': syns[:MAX_SYN]})
            total_new += 1
    entries.sort(key=lambda e: e['w'])
    with open(OUT, 'w', encoding='utf-8') as f:
        for e in entries:
            f.write(json.dumps(e, ensure_ascii=False) + '\n')
    words = len({e['w'] for e in entries})
    print(f'ENTRIES: {total_new} ({words} distinct words, {total_senses} senses)')

if __name__ == '__main__':
    main()
