#!/usr/bin/env python3
"""将 words.pdf（词汇表）转换为 CSV 文件。"""

import csv
import re
import sys
import pdfplumber

PDF_PATH = "/Volumes/SSD/home/shuzhongliu/Projects/WordsM/words.pdf"
CSV_PATH = "/Volumes/SSD/home/shuzhongliu/Projects/WordsM/words.csv"

ENTRY_RE = re.compile(r"^([A-Za-z][\w\-=&\.']*)\s*\[([^\]]+)\]\s+(.*)")

KNOWN_POS = {
    'n.', 'v.', 'a.', 'adv.', 'prep.', 'conj.', 'pron.', 'interj.', 'art.',
    'num.', 'vt.', 'vi.', 'phr.', 'int.', 'idiom.', 'adj.', 'ad.',
    'a./n.', 'v./n.', 'n./v.', 'a./ad.', 'n./v./adj.', 'a./ad./n.',
    'ad./prep.', 'prep./ad.', 'conj./ad.', 'n./ad.',
    'a./ad./n./v.', 'int./n./ad.',
}

PURE_POS_NO_A = {'n', 'v', 'adv', 'prep', 'conj', 'pron', 'art', 'num',
                 'vt', 'vi', 'phr', 'int', 'idiom', 'adj', 'ad'}


def split_pos_and_meaning(rest):
    rest = rest.strip()
    if not rest:
        return '', ''
    for pos in sorted(KNOWN_POS, key=len, reverse=True):
        if rest.startswith(pos):
            meaning = rest[len(pos):].strip()
            if meaning.startswith('.'):
                meaning = meaning[1:].strip()
            return pos, meaning
    m = re.match(r'^([a-z]\.)\s*(.*)', rest)
    if m:
        return m.group(1), m.group(2).strip()
    return '', rest


def is_valid_word(word):
    if word == 'a':
        return True
    if word in PURE_POS_NO_A:
        return False
    if word.endswith('.') and len(word) <= 4:
        return False
    if word.isupper() and len(word) <= 4:
        return True
    return True


def parse_pdf(path):
    records = []
    current = None
    with pdfplumber.open(path) as pdf:
        for page in pdf.pages:
            text = page.extract_text()
            if not text:
                continue
            lines = text.split('\n')
            if lines and '单词' in lines[0]:
                lines = lines[1:]
            for line in lines:
                line = line.strip()
                if not line:
                    continue
                m = ENTRY_RE.match(line)
                if m:
                    if current is not None:
                        records.append(current)
                    word = m.group(1)
                    phonetic = m.group(2)
                    rest = m.group(3)
                    if not is_valid_word(word):
                        continue
                    pos, meaning = split_pos_and_meaning(rest)
                    current = {
                        '单词': word,
                        '发音': phonetic,
                        '词性': pos,
                        '中文词义': meaning,
                    }
                else:
                    if current is not None and line:
                        current['中文词义'] += ' ' + line
            if current is not None:
                records.append(current)
                current = None
    return records


def main():
    records = parse_pdf(PDF_PATH)
    print(f"共解析 {len(records)} 条词条", file=sys.stderr)
    with open(CSV_PATH, 'w', newline='', encoding='utf-8-sig') as f:
        writer = csv.DictWriter(f, fieldnames=['单词', '发音', '词性', '中文词义'])
        writer.writeheader()
        writer.writerows(records)
    print(f"已写入 {CSV_PATH}", file=sys.stderr)
    empty_ph = sum(1 for r in records if not r['发音'])
    empty_pos = sum(1 for r in records if not r['词性'])
    empty_meaning = sum(1 for r in records if not r['中文词义'])
    print(f"质量检查: 空发音={empty_ph}, 空词性={empty_pos}, 空释义={empty_meaning}", file=sys.stderr)


if __name__ == '__main__':
    main()
