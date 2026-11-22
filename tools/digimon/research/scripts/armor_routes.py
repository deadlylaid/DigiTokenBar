#!/usr/bin/env python3
"""Collect the Armor Digimon routes of eleven Vital Bracelet cards into research/armor-routes.json.

Step 13 (Digimentals and Armor evolution, docs/digimon/step13-digimental-armor.md). The first card
research left the Armor Digimon out ("they need Digimentals"); this script brings back, for the
cards whose roster has them, every route with an Armor Digimon at either end that stays on the card,
the stage column each Armor Digimon stands in, and the Digimental each Child -> Armor step asks for.
Only a Child's step takes a Digimental; an Adult's or a Perfect's route into an Armor Digimon is an
ordinary card route (user decision 2026-11-21).

Downloaded pages go to the cache dir (keep it outside the repository). The charts must be in it
already (vbdm.html, vbdm_ex.html, vbdm_vol.html, vbbe_anime.html, vbbe_special.html); detail pages
are fetched as needed (network).

    python3 -I tools/digimon/research/scripts/armor_routes.py <repo root> <cache dir> <chart json> <out json> [<official json>...]

<chart json>: Wikimon's Digimental Evolution Chart (Template:DigimentalEvoList1) as the wikitext API
returns it (`{"parse": {"wikitext": ...}}`).
<official json>: output of official_reference.py for the Armor Digimon. Each English profile names its
Digi-Egg ("Digivolved with the Digi-Egg of Courage"); the script stops if that differs from the
Digimental given here, and records the check.
"""
import html
import json
import re
import sys
import time
import urllib.request
from pathlib import Path

ROOT, CACHE, CHART, OUT = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]), Path(sys.argv[4])
OFFICIAL = {}
for p in sys.argv[5:]:
    OFFICIAL.update(json.loads(Path(p).read_text()))
# The English reference's Digi-Egg names -> Digimental raw values. "Sincerity" is the English name of
# 純真 (Shurimon's), "Reliability" of 誠実 (Submarimon's), "Destiny" of 運命.
DIGI_EGG = {"Courage": "courage", "Friendship": "friendship", "Love": "love", "Knowledge": "knowledge",
            "Sincerity": "purity", "Reliability": "reliability", "Hope": "hope", "Light": "light",
            "Kindness": "kindness", "Miracles": "miracles", "Destiny": "fate"}
DATA = json.loads((ROOT / "tools/digimon/data/evolutions.json").read_text())
NODES = DATA["nodes"]
DETAIL_URL = "https://humulos.com/digimon/php/details.php?digimon={}&device={}"
CHART_URLS = {
    "vbdm.html": "https://humulos.com/digimon/vbdm/",
    "vbdm_ex.html": "https://humulos.com/digimon/vbdm/ex/",
    "vbdm_vol.html": "https://humulos.com/digimon/vbdm/vol/",
    "vbbe_anime.html": "https://humulos.com/digimon/vbbe/anime/",
    "vbbe_special.html": "https://humulos.com/digimon/vbbe/special/",
}
# line id, card name in data/evolutions.json (as gen_catalog.LINES), roster size when several cards
# share the name, chart page, anchor, device (13 = VB DIM, 14 = VB BE), and the card's heading on
# humulos detail pages (a Digimon on several cards of a device lists each card's routes under it)
CARDS = [
    ("vmon", "Ancient Warriors", None, "vbdm.html", "awa", "13", "Ancient Warriors"),
    ("wormmon", "Primeval Warriors", None, "vbdm.html", "pwa", "13", "Primeval Warriors"),
    ("hawkmon", "BEMemory D-3 White and Red Dim", None, "vbbe_anime.html", "dwr", "14", "D-3 White and Red"),
    ("armadimon", "BEMemory D-3 White and Yellow Dim", None, "vbbe_anime.html", "dwy", "14", "D-3 White and Yellow"),
    ("renamon", "Renamon", 17, "vbdm_ex.html", "rena_ex", "13", "Renamon EX"),
    ("terriermon", "Terriermon", 17, "vbdm_ex.html", "terrier_ex", "13", "Terriermon EX"),
    ("blucomon", "Blizzard Fang", None, "vbdm_vol.html", "bfa", "13", "Blizzard Fang"),
    # Not the Jellymon card: its chart (vbbe/anime#jelly) has no Armor Digimon. Wikimon's
    # Jellymon -> Manbomon route is from another device.
    ("sunarizamon", "Titan of Dust", None, "vbdm_vol.html", "tdu", "13", "Titan of Dust"),
    ("piyomon", "BEMemory Holy Wings Dim", None, "vbbe_special.html", "hwi", "14", "Holy Wing"),
    # Added 2026-11-21 (user decision): Peacockmon on the Fairimon EX card and Rhinomon on the
    # Gabumon (Black) card, both reached from an Adult by the card's own routes.
    ("tinkermon", "Fairimon", None, "vbdm_ex.html", "fairi_ex", "13", ("Fairimon EX", "Fairi EX")),
    ("gabumonblack", "Dim Card Set vol. 0.5: Mad Black Roar & True Shadow Howl", None, "vbdm_vol.html", "tsh", "13",
     "True Shadow Howl"),
]
COLUMN = {"baby": "babyI", "babyII": "babyII", "child": "child", "adult": "adult",
          "perfect": "perfect", "ultimate": "ultimate", "super": "ultimate"}
STAGE = {"I": "babyI", "II": "babyII", "III": "child", "IV": "adult", "V": "perfect", "VI": "ultimate"}
# humulos titles that do not match a Wikimon name on the data card -> species key
HUMULOS_KEYS = {"tail_c": "tailmonchild", "archne": "archnemon", "rapid_a": "rapidmonarmor", "rapid": "rapidmonperfect",
                "sakuya_x": "sakuyamonxantibody", "tuno": "tunomon", "weregaruru_s": "weregarurumonsagittariusmode",
                "jaegerdorulu": "yaegerdorulumon"}
# The chart's column names -> Digimental raw values (Sources/PokeTokenBar/Digimon/Digimental.swift)
DIGIMENTALS = ["courage", "friendship", "love", "knowledge", "purity", "reliability", "hope", "light",
               "kindness", "miracles", "fate"]


def fetch(url, name):
    path = CACHE / name
    if not path.exists():
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (research script)"})
        with urllib.request.urlopen(req, timeout=30) as r:
            path.write_bytes(r.read())
        time.sleep(0.6)
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
    marks = [(m.start(), "col", COLUMN[m.group(1)]) for m in re.finditer(r'class="(baby|babyII|child|adult|perfect|ultimate|super) column', seg)]
    marks += [(m.start(), "mon", m.group(1)) for m in re.finditer(r"class=\"profile vbdm_card\" onClick=\"digimonDetailsUnified\('([a-z0-9_]+)','\d+'", seg)]
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


def details(hid, device):
    """(stage, [(heading, to id, to name, requirement)]) from the detail page."""
    page = fetch(DETAIL_URL.format(hid, device), f"d{device}_{hid}.html")
    stage = re.search(r"Stage ([IVX]+) \(", page)
    evo = page[page.index('<div class="evo">'):] if '<div class="evo">' in page else ""
    routes, heading = [], None
    for m in re.finditer(r'<h5[^>]*>(.*?)</h5>|digimonShinkaUnified\(\'([a-z0-9_]+)\',\'([a-z0-9_]+)\'.*?<h3 class="names">(.*?)</h3>.*?<p class="deets">(.*?)</p>(\s*<ul class="deetsList">.*?</ul>)?', evo, re.S):
        if m.group(1) is not None:
            heading = text(m.group(1))
        else:
            assert m.group(3) == hid, (hid, m.group(3))
            raw = text(m.group(5))
            if m.group(6):
                raw += " " + " OR ".join(text(li) for li in re.findall(r"<li>(.*?)</li>", m.group(6), re.S))
            routes.append((heading, m.group(2), text(m.group(4)), raw))
    return (STAGE[stage.group(1)] if stage else None), routes


# "PP" is the BE cards' name for Trophies.
NUM = {"Trophies": "trophies", "PP": "pp", "Vital Values": "vitalValues", "Battles": "battles", "Win Ratio": "winRatio"}
STAT = r"([\d,]+)%?\+ (Trophies|PP|Vital Values|Battles|Win Ratio)"


def stat_reqs(s):
    out = {}
    for m in re.finditer(STAT, s):
        out[NUM[m.group(2)]] = int(m.group(1).replace(",", ""))
    rest = re.sub(STAT, "", s)
    return out if out and not re.sub(r"[ ,]", "", rest) else None


def range_reqs(s):
    m = re.fullmatch(r"0-([\d,]+)%? (Trophies|PP|Vital Values|Battles|Win Ratio)", s.strip())
    if m:
        return {NUM[m.group(2)] + "Max": int(m.group(1).replace(",", ""))}
    m = re.fullmatch(r"0%?\+ (Trophies|PP|Vital Values|Battles|Win Ratio)", s.strip())
    if m:
        return {NUM[m.group(1)] + "Min": 0}
    m = re.fullmatch(r"Stage (\d+) not cleared(?:, No requirements)?", s.strip())
    return {"adventureStageNotCleared": int(m.group(1))} if m else None


def classify(raw):
    """[(kind, requirements)] for one route text (see frontier_routes.classify)."""
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


def digimental_chart():
    """[(base name, digimental, armor name)] from Wikimon's Digimental Evolution Chart."""
    t = json.loads(CHART.read_text())["parse"]["wikitext"]
    t = t if isinstance(t, str) else t["*"]
    cols = re.findall(r"Image:Digimental_(\w+)\.jpg", t.split("|-", 2)[1])
    if cols != DIGIMENTALS:
        raise SystemExit(f"unexpected chart columns {cols}")
    pairs = []
    for row in t.split("\n|-"):
        cells = [c.strip() for c in row.split("\n|")[1:]]
        if not cells or "bgcolor" not in cells[0] or "[[" not in cells[0]:
            continue
        base = re.search(r"\[\[([^\]|]+)", cells[0]).group(1)
        for i, c in enumerate(cells[1:len(cols) + 1]):
            for armor in re.findall(r"\[\[([^\]|]+)", c):
                pairs.append((base, cols[i], armor))
    return pairs


def main():
    pages = {f: fetch(url, f) for f, url in CHART_URLS.items()}
    name_key = {norm(n["name"]): k for k, n in NODES.items()}
    chart = digimental_chart()
    # The Armor's representative Digimental: the first chart column it appears in.
    representative = {}
    for _, d, armor in sorted(chart, key=lambda p: DIGIMENTALS.index(p[1])):
        k = name_key.get(norm(armor))
        if k:
            representative.setdefault(k, d)
    pair_digimental = {}
    for base, d, armor in chart:
        b, a = name_key.get(norm(base)), name_key.get(norm(armor))
        if b and a:
            pair_digimental.setdefault((b, a), d)
    result = {
        "system": {
            "description": "Armor Digimon routes on eleven Vital Bracelet cards (step 13). Collected 2026-11-21 by "
                           "tools/digimon/research/scripts/armor_routes.py from the humulos.com charts and detail pages "
                           "(device 13 = VB DIM, 14 = VB BE; BE cards count PP where DIM cards count Trophies). For each "
                           "card: `cardStages` is the chart column each Armor Digimon stands in; `edges` are the card's "
                           "routes with an Armor Digimon at either end that stay on the card, in the format of the "
                           "vb-conditions-*.json files; `digimentals` gives each Child -> Armor step the Digimental that "
                           "opens it in the app. A route into an Armor Digimon from an Adult or a Perfect is an ordinary "
                           "card route without a Digimental (user decision 2026-11-21: the anime and the D-3 toy "
                           "armor-evolve a Child only). Third-party quotes: review before a public release (see README).",
            "kinds": {"normal": "stat requirements", "fallback": "taken when nothing else is met",
                      "jogress": "needs a partner Digimon", "adventure": "stat requirements after an Adventure stage"},
            "digimentalRule": "pair: Wikimon's Digimental Evolution Chart lists that Digimon with that Armor under "
                              "this Digimental. representative: the chart has no such pair, so the Armor's first "
                              "chart column (courage, friendship, love, knowledge, purity, reliability, hope, light, "
                              "kindness, miracles, fate) is used.",
            "digimentalChart": {
                "source": "https://wikimon.net/Template:DigimentalEvoList1 (shown on https://wikimon.net/Digimental_Evolution_Chart), "
                          "fetched 2026-11-21. Text licensed CC BY-SA 3.0.",
                "columns": DIGIMENTALS,
                "pairs": [{"base": b, "digimental": d, "armor": a} for b, d, a in chart],
            },
        },
        "cards": {},
    }
    for line_id, card_name, size, chart_file, anchor, device, heading in CARDS:
        card = next(c for c in DATA["cards"] if c["name"] == card_name
                    and (size is None or len([k for k in c["roster"] if k in NODES]) == size))
        roster = [k for k in card["roster"] if k in NODES]
        by_name = {norm(NODES[k]["name"]): k for k in roster}
        ids, col_of = {}, {}
        for hid, title, col in chart_card(pages[chart_file], anchor):
            key = HUMULOS_KEYS.get(hid) or by_name.get(norm(title))
            if not key:
                # "Falcomon (2006)" is "Falcomon (2006 Anime Version)" on Wikimon: one roster name that
                # starts with the title is the same Digimon.
                starts = [k for n, k in by_name.items() if n.startswith(norm(title))]
                key = starts[0] if len(starts) == 1 else None
            if not key:
                raise SystemExit(f"{card_name}: humulos {hid} ({title}) is not on the data card")
            ids[hid] = key
            col_of[key] = col
        armor_on_card = [k for k in ids.values() if NODES.get(k, {}).get("level") == "Armor"]
        stages, edges, notes, digimentals = {}, [], [], {}
        for hid, key in ids.items():
            stage, routes = details(hid, device)
            if key in armor_on_card:
                if stage != col_of[key]:
                    raise SystemExit(f"{card_name}: {key} is {stage} on its page but in the {col_of[key]} column")
                stages[key] = col_of[key]
            for h, to_hid, to_name, raw in routes:
                to_key = ids.get(to_hid)
                if key not in armor_on_card and to_key not in armor_on_card:
                    continue
                headings = (heading,) if isinstance(heading, str) else heading
                if h is not None and not set(headings) & {p.strip() for p in h.split(",")}:
                    notes.append(f"{key} -> {to_name} ({raw}) is under \"{h}\", not this card")
                    continue
                if to_key is None:
                    notes.append(f"{key} -> {to_name or to_hid} ({raw}) leads off this card, not listed")
                    continue
                kinds = classify(raw)
                for kind, req in kinds:
                    edges.append({"from": key, "to": to_key, "kind": kind, "requirements": req, "raw": raw,
                                  "source": DETAIL_URL.format(hid, device),
                                  "note": None if h is None else f'humulos card heading: "{h}"'})
                # Into an Armor Digimon from a Child: a Digimental opens it in the app (the anime and the
                # D-3 toy armor-evolve a Child only). From an Adult or a Perfect it is an ordinary route
                # with the card's requirements, as on the Vital Bracelet (user decision 2026-11-21). A
                # Jogress needs its partner instead.
                if (key not in armor_on_card and to_key in armor_on_card and col_of.get(key) == "child"
                        and any(k != "jogress" for k, _ in kinds)):
                    d, rule = pair_digimental.get((key, to_key)), "pair"
                    if d is None:
                        d, rule = representative.get(to_key), "representative"
                    if d is None:
                        raise SystemExit(f"{card_name}: no Digimental for {key}>{to_key}")
                    digimentals[f"{key}>{to_key}"] = {"digimental": d, "rule": rule}
        for step, d in digimentals.items():
            armor = step.split(">")[1]
            profile = ((OFFICIAL.get(armor) or {}).get("en") or {}).get("profile") or ""
            m = re.search(r"Digi-Egg of (\w+)", profile)
            if m:
                official = DIGI_EGG.get(m.group(1))
                if official != d["digimental"]:
                    raise SystemExit(f"{card_name}: {step} gives {d['digimental']} but the official profile says Digi-Egg of {m.group(1)}")
                d["official"] = f"Digi-Egg of {m.group(1)} ({OFFICIAL[armor]['directory']}, digimon.net/reference_en)"
            elif OFFICIAL:
                d["official"] = None
        result["cards"][line_id] = {
            "card": card_name, "chart": f"{CHART_URLS[chart_file]}#{anchor}_anchor", "device": device,
            "armorOnCard": armor_on_card, "cardStages": stages, "edges": edges, "digimentals": digimentals,
            "notes": notes,
        }
    OUT.write_text(json.dumps(result, ensure_ascii=False, indent=1) + "\n")
    for line_id, c in result["cards"].items():
        print(line_id, c["cardStages"])
        for e in c["edges"]:
            d = c["digimentals"].get(f"{e['from']}>{e['to']}")
            print(f"  {e['from']}>{e['to']} {e['kind']} {e['raw']}" + (f"  [{d['digimental']}, {d['rule']}]" if d else ""))
        for n in c["notes"]:
            print("  note:", n)


if __name__ == "__main__":
    main()
