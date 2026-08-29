#!/usr/bin/env python3
"""
Convert words.csv to words.json for the WordsM app.
Each word gets an auto-incrementing integer ID starting from 1.
"""
import csv
import json
import sys
from pathlib import Path


def convert(csv_path: Path, json_path: Path) -> None:
    words = []
    with open(csv_path, encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for idx, row in enumerate(reader, start=1):
            words.append(
                {
                    "id": idx,
                    "word": row["单词"].strip(),
                    "phonetic": row["发音"].strip(),
                    "pos": row["词性"].strip(),
                    "meaning": row["中文词义"].strip(),
                }
            )

    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(words, f, ensure_ascii=False, indent=2)

    print(f"Converted {len(words)} words to {json_path}")


if __name__ == "__main__":
    base = Path(__file__).parent
    csv_file = base / "words.csv"
    json_file = base / "words.json"

    if not csv_file.exists():
        print(f"Error: {csv_file} not found", file=sys.stderr)
        sys.exit(1)

    convert(csv_file, json_file)
    print(f"Output: {json_file}")
