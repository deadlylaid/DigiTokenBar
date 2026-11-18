#!/usr/bin/env python3
"""Fetch the official Digimon reference (ko/en/ja) for species keys and extract the fields.

Used on 2026-11-19 (step 11) for the 82 Frontier species. A key whose reference directory differs
is given as key=directory (found with the reference search, request.php?digimon_name=...).

    python3 -I tools/digimon/research/scripts/official_reference.py <cache dir> <out json> key[=directory] ...
"""
import html
import json
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

CACHE, OUT = Path(sys.argv[1]), Path(sys.argv[2])
CACHE.mkdir(parents=True, exist_ok=True)
URL = "https://digimon.net/{}/detail.php?directory_name={}"
LANGS = {"ko": "reference_ko", "en": "reference_en", "ja": "reference"}
LABELS = {
    "ko": ("등급", "유형", "속성", "필살기", "프로필"),
    "en": ("Level", "Type", "Attribute", "Special Move", "Profile"),
    "ja": ("レベル", "タイプ", "属性", "必殺技", "プロフィール"),
}


def fetch(lang, directory):
    path = CACHE / f"{directory}.{lang}.html"
    if not path.exists():
        req = urllib.request.Request(URL.format(LANGS[lang], directory), headers={"User-Agent": "Mozilla/5.0"})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                path.write_bytes(r.read())
        except urllib.error.HTTPError as e:
            path.write_text(f"HTTP {e.code}")
        time.sleep(0.3)
    return path.read_text(encoding="utf-8")


def flat(page):
    t = re.sub(r"<script.*?</script>|<style.*?</style>", "", page, flags=re.S)
    t = html.unescape(re.sub(r"<[^>]+>", " | ", t))
    t = re.sub(r"\s+", " ", t)
    return re.sub(r"( \| )+", " | ", t)


def fields(page, lang):
    t = flat(page)
    level, kind, attr, move, profile = LABELS[lang]
    i = t.find(f"| {level} |")
    if i < 0:
        return None
    t = t[i:]
    def between(a, b):
        m = re.search(re.escape(f"| {a} |") + r"(.*?)" + re.escape(f"| {b} |"), t)
        return m.group(1).strip(" |") if m else None
    head = flat(page)[:i]
    names = [x.strip() for x in head.split("|") if x.strip()][-3:]
    moves = between(move, profile)
    prof = re.search(re.escape(f"| {profile} |") + r"[\s|]*([^|]+)", t)
    return {
        "names": names,
        "level": between(level, kind),
        "attribute": between(attr, move),
        # one list item per move ("・A | ・B"); a name may hold its own middle dot (リヒト・ナーゲル)
        "moves": [m.strip(" |") for m in re.split(r"(?:^|\s\|\s*)・", moves or "") if m.strip(" |")],
        "profile": prof.group(1).strip() if prof else None,
    }


def main():
    out = json.loads(OUT.read_text()) if OUT.exists() else {}
    for arg in sys.argv[3:]:
        key, _, directory = arg.partition("=")
        directory = directory or key
        row = {"directory": directory}
        for lang in LANGS:
            row[lang] = fields(fetch(lang, directory), lang)
        out[key] = row
        print(key, directory, "ok" if row["ko"] else "MISSING", (row["ko"] or {}).get("moves"), (row["en"] or {}).get("moves"))
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n")


if __name__ == "__main__":
    main()
