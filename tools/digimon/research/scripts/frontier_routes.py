#!/usr/bin/env python3
"""Collect the six Frontier DIM cards (humulos vbdm/ex) into the research JSON format.

Wrote research/vb-conditions-frontier.json on 2026-11-19 (step 11). Kept as the record of how the
data was made and as a start for the next cards; the card list and name fixes are for these six.
Downloaded pages go to the cache dir (keep it outside the repository).

    python3 -I tools/digimon/research/scripts/frontier_routes.py <repo root> <cache dir> <out json>
"""
import html
import json
import re
import sys
import time
import urllib.request
from pathlib import Path

ROOT, CACHE, OUT = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
DATA = json.loads((ROOT / "tools/digimon/data/evolutions.json").read_text())
NODES = DATA["nodes"]
CHART_URL = "https://humulos.com/digimon/vbdm/ex/"
DETAIL_URL = "https://humulos.com/digimon/php/details.php?digimon={}&device=13"

# humulos anchor, card name in data/evolutions.json, humulos card heading and its short form (a
# detail page heads shared routes with a list of short forms: "VBe, Agni EX")
CARDS = [
    ("agni_ex", "Agnimon", "Agnimon EX", "Agni EX", "flamon"),
    ("fairi_ex", "Fairimon", "Fairimon EX", "Fairi EX", "tinkermon"),
    ("chack_ex", "Chackmon", "Chackmon EX", "Chack EX", "bearmon"),
    ("wolf_ex", "Wolfmon", "Wolfmon EX", "Wolf EX", "strabimon"),
    ("blitz_ex", "Blitzmon", "Blitzmon EX", "Blitz EX", "kokabuterimon"),
    ("louwe_ex", "Louwemon", "Louwemon EX", "Louwe EX", "liollmon"),
]
# A detail page that links a species by another humulos id than the chart's.
HUMULOS_IDS = {"metallife": "metallifekuwaga"}
DEVICE_RULES = ("Vital Bracelet DIM card (humulos '{}', Premium Bandai, Legend Spirits sets; details device 13). "
                "VB Dim rules: Trophies. Baby I -> Baby II is time-only; Baby II has a 1,200+ VV route and its "
                "0-1,199 VV fallback; each Child has one stat route and a fallback; Adults and Perfects have stat "
                "routes and attribute-Jogress routes (the device checks the backup for a partner of the same stage). "
                "Some Ultimate routes need Adventure stage 15 cleared. The Hybrid Digimon stand in the chart's stage "
                "columns like the rest of the card.")
COLUMN = {"baby": "babyI", "babyII": "babyII", "child": "child", "adult": "adult",
          "perfect": "perfect", "ultimate": "ultimate", "super": "ultimate"}
# humulos ids whose shown name differs from Wikimon's spelling -> our species key
HUMULOS_KEYS = {"snowgobli": "snowgoburimon", "panjya_x": "panjyamonxantibody", "louwe": "lowemon"}
STAGE = {"I": "babyI", "II": "babyII", "III": "child", "IV": "adult", "V": "perfect", "VI": "ultimate"}


def fetch(url, name):
    path = CACHE / name
    if not path.exists():
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (research script)"})
        with urllib.request.urlopen(req, timeout=30) as r:
            path.write_bytes(r.read())
        time.sleep(0.4)
    return path.read_text(encoding="utf-8")


def norm(s):
    s = s.replace("ö", "o").replace("Ö", "o")
    return re.sub(r"[^a-z0-9]", "", s.lower())


def text(s):
    return html.unescape(re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", s))).strip()


def chart_card(page, anchor):
    """[(humulos id, title, column stage)] in chart order."""
    i = page.index(f'id="{anchor}_anchor"')
    j = page.find('class="anchor', page.index('>', i))
    seg = page[i: j if j > 0 else len(page)]
    # "super": the column after Ultimate that shows a merge of two Ultimates (still an Ultimate).
    marks = [(m.start(), "col", COLUMN[m.group(1)]) for m in re.finditer(r'class="(baby|babyII|child|adult|perfect|ultimate|super) column', seg)]
    # Only the card's own Digimon: a Jogress partner box also links a details page.
    marks += [(m.start(), "mon", m.group(1)) for m in re.finditer(r"class=\"profile vbdm_card\" onClick=\"digimonDetailsUnified\('([a-z0-9_]+)','13'", seg)]
    marks.sort()
    out, col = [], None
    for pos, kind, val in marks:
        if kind == "col":
            col = val
        else:
            title = re.search(r'title="([^"]+)"', seg[pos:pos + 600]).group(1)
            if all(val != o[0] for o in out):
                out.append((val, title, col))
    return out


def details(hid):
    """(stage, attribute, cards listed, [(heading, to id, to name, requirement)]) from the detail page."""
    page = fetch(DETAIL_URL.format(hid), f"d_{hid}.html")
    stage = re.search(r"Stage ([IVX]+) \(", page)
    attr = re.search(r'class="attribute" attribute="([^"]*)"', page)
    cards = [text(c) for c in re.search(r'<div class="text_center">(.*?)</div>', page, re.S).group(1).split("<br>") if text(c)]
    evo = page[page.index('<div class="evo">'):]
    routes, heading = [], None
    for m in re.finditer(r'<h5[^>]*>(.*?)</h5>|digimonShinkaUnified\(\'([a-z0-9_]+)\',\'([a-z0-9_]+)\'.*?<h3 class="names">(.*?)</h3>.*?<p class="deets">(.*?)</p>(\s*<ul class="deetsList">.*?</ul>)?', evo, re.S):
        if m.group(1) is not None:
            heading = text(m.group(1))
        else:
            # digimonShinkaUnified(other, this page): under "Evolves To" the other is the target.
            assert m.group(3) == hid, (hid, m.group(3))
            raw = text(m.group(5))
            if m.group(6):   # "Choose one:" with its options listed below
                raw += " " + " OR ".join(text(li) for li in re.findall(r"<li>(.*?)</li>", m.group(6), re.S))
            routes.append((heading, m.group(2), text(m.group(4)), raw))
    return (STAGE[stage.group(1)] if stage else None), (attr.group(1) if attr else None), cards, routes


NUM = {"Trophies": "trophies", "Vital Values": "vitalValues", "Battles": "battles", "Win Ratio": "winRatio"}


def stat_reqs(s):
    """"10+ Trophies, 1,300+ Vital Values, 8+ Battles, 70%+ Win Ratio" -> requirements; None if not stats."""
    out = {}
    for m in re.finditer(r"([\d,]+)%?\+ (Trophies|Vital Values|Battles|Win Ratio)", s):
        out[NUM[m.group(2)]] = int(m.group(1).replace(",", ""))
    rest = re.sub(r"([\d,]+)%?\+ (Trophies|Vital Values|Battles|Win Ratio)", "", s)
    return out if out and not re.sub(r"[ ,]", "", rest) else None


def range_reqs(s):
    """"0-7 Trophies" -> {"trophiesMax": 7}, "Stage 2 not cleared" -> {...}; None if not a range."""
    m = re.fullmatch(r"0-([\d,]+)%? (Trophies|Vital Values|Battles|Win Ratio)", s.strip())
    if m:
        return {NUM[m.group(2)] + "Max": int(m.group(1).replace(",", ""))}
    # "0+ Battles" in a fallback's "Choose one" list: always true (humulos writes it on some cards).
    m = re.fullmatch(r"0%?\+ (Trophies|Vital Values|Battles|Win Ratio)", s.strip())
    if m:
        return {NUM[m.group(1)] + "Min": 0}
    m = re.fullmatch(r"Stage (\d+) not cleared(?:, No requirements)?", s.strip())
    return {"adventureStageNotCleared": int(m.group(1))} if m else None


def classify(raw):
    """[(kind, requirements)] for one route text. A "Choose one" of stats and a Jogress is two routes
    for the same step. An Adventure gate ("Stage 15 cleared, ...") is kept as `adventureStage`: on a
    Jogress it stays a Jogress (the partner is still needed), on stats the route is "adventure"."""
    if raw == "No requirements":
        return [("timeOnly", {})]
    body = raw[len("Choose one: "):] if raw.startswith("Choose one: ") else raw
    alts = [a.strip() for a in body.split(" OR ")]
    if all(range_reqs(a) for a in alts):
        rs = [range_reqs(a) for a in alts]
        return [("fallback", rs[0] if len(rs) == 1 else {"anyOf": rs})]
    out = []
    for a in alts:
        gate = re.match(r"Stage (\d+) cleared, ", a)
        if gate:
            a = a[gate.end():]
        if a.startswith("Jogress with "):
            partner = a[len("Jogress with "):].strip()
            m = re.fullmatch(r"((?:Vaccine|Data|Virus|Free)(?:(?:, | or )(?:Vaccine|Data|Virus|Free))*) (Child|Adult|Perfect)", partner)
            req = {"jogressPartner": partner}
            if m:
                req["jogressPartnerAttributes"] = re.findall(r"Vaccine|Data|Virus|Free", m.group(1))
                req["jogressPartnerLevel"] = m.group(2)
            kind = "jogress"
        elif stat_reqs(a) is not None:
            req, kind = stat_reqs(a), ("adventure" if gate else "normal")
        else:
            raise SystemExit(f"cannot read route text: {raw!r}")
        if gate:
            req = {"adventureStage": int(gate.group(1)), **req}
        out.append((kind, req))
    return out


def main():
    page = fetch(CHART_URL, "ex.html")
    result = {
        "system": {
            "description": "Per-card Vital Bracelet routes for the six Frontier DIM cards (Set EX3/EX4/EX5 "
                           "Legend Spirits: Agnimon, Fairimon, Chackmon, Wolfmon, Blitzmon, Louwemon). Collected "
                           "2026-11-19 by a script from the humulos.com chart (vbdm/ex) and detail pages (device 13 = "
                           "VB DIM/EX cards). `cardStages` is the stage the card's chart column puts each species in "
                           "(the Hybrid Digimon have no stage of their own on Wikimon); `cardAttributes` is the card's attribute of "
                           "each Hybrid (Wikimon: Variable). Each edge is a route between two "
                           "species of the card with its kind, the stated requirements and the source text. Third-party "
                           "quotes: review before a public release (see README).",
            "kinds": {
                "normal": "stat requirements (Vital Values, trophies, battles, win ratio)",
                "fallback": "taken when nothing else is met",
                "jogress": "needs a partner Digimon",
                "timeOnly": "baby stages: time only",
            },
        },
        "cards": {},
    }
    for anchor, card_name, heading, short, line_id in CARDS:
        card = next(c for c in DATA["cards"] if c["name"] == card_name)
        roster = [k for k in card["roster"] if k in NODES]
        by_name = {norm(NODES[k]["name"]): k for k in roster}
        chart = chart_card(page, anchor)
        ids = {}
        for hid, title, col in chart:
            key = HUMULOS_KEYS.get(hid) or by_name.get(norm(title))
            if not key:
                raise SystemExit(f"{card_name}: humulos {hid} ({title}) is not on the data card")
            ids[hid] = key
        missing = [k for k in roster if k not in ids.values()]
        if missing:
            raise SystemExit(f"{card_name}: on the data card but not on the chart: {missing}")
        stages, attributes, edges, notes = {}, {}, [], []
        for hid, title, col in chart:
            stage, attr, cards, routes = details(hid)
            key = ids[hid]
            if stage != col:
                raise SystemExit(f"{card_name}: {title} is {stage} on its page but in the {col} column")
            stages[key] = col
            # A Hybrid's attribute is "Variable" on Wikimon; the card gives it one.
            if NODES[key]["level"] == "Hybrid":
                if not attr:
                    raise SystemExit(f"{card_name}: {title} has no attribute on its page")
                attributes[key] = attr.lower()
            for h, to_hid, to_name, raw in routes:
                to_hid = HUMULOS_IDS.get(to_hid, to_hid)
                if h is not None and not {heading, short} & set(h.split(", ")):
                    notes.append(f"{title} -> {to_name or to_hid} ({raw}) is under \"{h}\", not this card")
                    continue
                if to_hid not in ids:
                    notes.append(f"{title} -> {to_name or to_hid} ({raw}) leads off this card, not listed")
                    continue
                for kind, req in classify(raw):
                    edges.append({"from": key, "to": ids[to_hid], "kind": kind, "requirements": req, "raw": raw,
                                  "source": DETAIL_URL.format(hid),
                                  "note": None if h is None else f'humulos card heading: "{h}"'})
        result["cards"][line_id] = {
            "card": card_name, "humulosCard": heading, "chart": f"{CHART_URL}#{anchor}_anchor", "device": "13",
            "deviceRules": DEVICE_RULES.format(heading),
            "cardStages": stages, "cardAttributes": attributes, "edges": edges, "notes": notes,
            "counts": {k: sum(e["kind"] == k for e in edges) for k in ("timeOnly", "normal", "fallback", "jogress")},
        }
    OUT.write_text(json.dumps(result, ensure_ascii=False, indent=1) + "\n")
    for name, c in result["cards"].items():
        print(name, c["counts"], *c["notes"], sep="\n  ")


if __name__ == "__main__":
    main()
