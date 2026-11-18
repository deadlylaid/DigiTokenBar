#!/usr/bin/env python3
"""Draft research/moves-frontier.json rows from the official reference and cached Wikimon pages.

Step 11 (2026-11-19). The draft was then fixed by hand (a few English names, six descriptions) and
every attack shape was checked by eye; see docs/digimon/step11-frontier-lines.md.

    python3 -I tools/digimon/research/scripts/draft_moves.py <official.json> tools/digimon/.cache/pages <out json>
"""
import json
import re
import sys
from pathlib import Path

OFFICIAL = json.loads(Path(sys.argv[1]).read_text())
PAGES = Path(sys.argv[2])
OUT = Path(sys.argv[3])


def unwiki(s):
    s = re.sub(r"<ref[^>]*/>|<ref[^>]*>.*?</ref>", "", s or "", flags=re.S)
    s = re.sub(r"\{\{w\|[^|}]*\|([^}]*)\}\}", r"\1", s)
    s = re.sub(r"\{\{w\|([^}]*)\}\}", r"\1", s)
    s = re.sub(r"\{\{AT\|([^|}]*)(?:\|[^}]*)?\}\}", r"\1", s)
    s = re.sub(r"\[\[[^|\]]*\|([^\]]*)\]\]", r"\1", s)
    s = re.sub(r"\[\[([^\]]*)\]\]", r"\1", s)
    s = re.sub(r"\{\{(?:DD|ref|rfe|note|--|N/A|j2)[^{}]*\}\}", "", s)
    for _ in range(3):
        s = re.sub(r"\{\{[A-Za-z]+\|(?:[^{}|]*\|)*([^{}|]*)\}\}", r"\1", s)
    s = re.sub(r"\{\{[^}]*\}\}", "", s)
    s = re.sub(r"<br\s*/?>", ", ", s)
    s = re.sub(r"''+", "", s)
    return re.sub(r"\s+", " ", s).strip()


def techniques(page):
    """[{name, trans, kan, d, desc}] from the first Attack Techniques {{T ...}} template. A field's
    value runs until the next top-level "|field=" line: nested templates ({{MultiDesc |d1=...}})
    have their own "|d1=" lines, which are not the technique's dub field."""
    i = page.find("Attack Techniques")
    if i < 0:
        return []
    j = page.find("{{T", i)
    body = page[j + 3:j + 80000]
    out, field, depth = {}, None, 0
    for line in body.split("\n"):
        m = re.match(r"^\|([a-z]+)(\d*)=(.*)$", line) if depth == 0 else None
        if m:
            name, n = m.group(1), int(m.group(2) or 1)
            if name == "name" and n in out and "name" in out[n]:
                break
            field = (n, name)
            out.setdefault(n, {})[name] = m.group(3)
            value = m.group(3)
        elif field:
            out[field[0]][field[1]] += "\n" + line
            value = line
        else:
            continue
        depth += value.count("{{") - value.count("}}")
        if depth < 0:
            break   # the template closed
    return [out[n] for n in sorted(out) if "name" in out[n]]


def norm_kana(s):
    s = re.sub(r"[（(].*?[）)]", "", s or "")
    return re.sub(r"[\s・･~～〜《》≪≫「」『』]", "", s)


rows, report = [], []
for key, r in OFFICIAL.items():
    ko, en, ja = r["ko"], r["en"], r["ja"]
    page_path = PAGES / f"{key}.wiki"
    techs = techniques(page_path.read_text(encoding="utf-8")) if page_path.exists() else []
    want = norm_kana(ja["moves"][0])
    hit = next((t for t in techs if norm_kana(t.get("kan")) == want), None)
    ref_en = en["moves"][0]
    ko_species = next(x for x in ko["names"] if re.search("[가-힣]", x) and "일러스트" not in x)
    src = [f"https://digimon.net/{lang}/detail.php?directory_name={r['directory']}"
           for lang in ("reference_ko", "reference_en", "reference")]
    if hit:
        name, trans = unwiki(hit.get("name")), unwiki(hit.get("trans"))
        dubs = unwiki(hit.get("d"))
        kanji = bool(re.search(r"[一-鿿]", ja["moves"][0]))
        wiki_en = trans if (kanji and trans and trans != "--") else name
        dub = ref_en != wiki_en and ref_en.lower() in dubs.lower()
        en_name = wiki_en if (dub or kanji) else ref_en
        desc = hit.get("desc") or ""
        m = re.search(r"\|d1=(.*?)(?:\n\||\}\}\s*$)", desc, re.S) if "MultiDesc" in desc else None
        what = unwiki(m.group(1) if m else desc)
        note = (f"JP {ja['moves'][0]}. " + (
            f"reference_en uses the dub name \"{ref_en}\", so Wikimon's {'Translation' if kanji else 'name'} was used."
            if dub else (f"Kanji move: Wikimon's Translation." if kanji and en_name != ref_en else "Official ko/en/ja first move.")))
        src.append(f"https://wikimon.net/{page_path.stem}")
        flag = "" if en_name == ref_en else f"  (reference_en: {ref_en})"
    else:
        en_name, what, note, flag = ref_en, "", f"JP {ja['moves'][0]}. No matching Wikimon technique; reference_en used.", "  NO WIKIMON MATCH"
    rows.append({"key": key, "ko": ko["moves"][0], "en": en_name, "what": what, "koSpecies": ko_species,
                 "sources": src, "note": note})
    report.append(f"{key:22} {ko_species:12} {ko['moves'][0]:16} | {en_name}{flag} || {what[:90]}")

OUT.write_text(json.dumps(rows, ensure_ascii=False, indent=1) + "\n")
print("\n".join(report))
