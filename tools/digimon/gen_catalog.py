#!/usr/bin/env python3
"""Generate Sources/PokeTokenBar/Digimon/DigimonCatalogData.swift from data/evolutions.json.

Only the MVP lines (Vital Bracelet cards listed in LINES) are emitted. Evolution data lives
here; evolution *conditions* (hidden rules, locks) live in Swift (EvolutionRules), so the two
stay separate.

    python3 -I tools/digimon/gen_catalog.py
"""
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
DATA = json.loads((HERE / "data" / "evolutions.json").read_text())
OUT = ROOT / "Sources" / "PokeTokenBar" / "Digimon" / "DigimonCatalogData.swift"
MOVES = json.loads((HERE / "data" / "moves.json").read_text())["moves"]
MOVES_OUT = ROOT / "Sources" / "PokeTokenBar" / "Digimon" / "DigimonMovesData.swift"

# line id (a Child species key on the card), Vital Bracelet card name, egg spot color (RGB hex,
# drawn in code), and which card when several share the name (roster size).
LINES = [
    ("agumon", "Agumon", "F28C3E", None),
    ("gabumon", "Gabumon", "5496E6", None),
    ("piyomon", "BEMemory Holy Wings Dim", "F07FA6", None),
    ("tentomon", "BEMemory Forest Guardians Dim", "6DB33F", None),
    ("vmon", "Ancient Warriors", "6B5BD6", None),
    ("guilmon", "Guilmon", "D9473B", 17),
    # Step 7: more DIM and BEMemory cards (research: research/vb-conditions-step7.json).
    ("pulsemon", "Impulse City", "F7D23E", None),
    ("vorvomon", "Volcanic Beat", "E2572B", None),
    ("blucomon", "Blizzard Fang", "7FC8F0", None),
    ("sangomon", "Infinite Tide", "2E9BB5", None),
    ("sunarizamon", "Titan of Dust", "C49A5A", None),
    ("impmon", "Impmon", "5A3E8C", None),
    ("monodramon", "Monodramon", "B07BD8", None),
    ("palmon", "Hermit in the Jungle", "8FCB5B", None),
    ("hagurumon", "Nu Metal Empire", "8A96A3", None),
    ("ghostmon", "Dynasty of the Evil", "4B4F6B", None),
    ("agumonblack", "Mad Black Roar", "4A4038", None),
    ("gabumonblack", "Dim Card Set vol. 0.5: Mad Black Roar & True Shadow Howl", "2F4A6B", None),
    ("terriermon", "Terriermon", "9BCB7A", 17),
    ("renamon", "Renamon", "E8A33D", 17),
    ("wormmon", "Primeval Warriors", "6FAE7A", None),
    ("espimon", "Espimon", "35506E", None),
    ("ryudamon", "Ryudamon", "B88A3E", None),
    ("gammamon", "BEMemory Gammamon Dim", "62B6E8", None),
    ("angoramon", "BEMemory Angoramon Dim", "E9A9C8", None),
    ("jellymon", "BEMemory Jellymon Dim", "6AD6C6", None),
    ("agumon2006animeversion", "BEMemory Dragonic Blaze Dim", "F07A2A", None),
    ("gaomon", "BEMemory Rampage of The Beast Dim", "3D6FC9", None),
    ("loogamon", "BEMemory Digimon Seekers Loogamon Dim", "5C4A9E", None),
    ("commandramon", "BEMemory Digimon Seekers Ryudamon Dim", "6B7F4A", None),
    ("dorumon", "BEMemory Digimon Seekers DORUmon Dim", "7B5FB0", None),
    ("armadimon", "BEMemory D-3 White and Yellow Dim", "E6C84A", None),
    ("hawkmon", "BEMemory D-3 White and Red Dim", "E06A5A", None),
    ("kudamon", "BEMemory Digimon Seekers Pulsemon Dim", "F2E6A0", None),
]
# Card roster entries that are not a species of their own.
NOT_SPECIES = {
    "jellymonbattle": "Jellymon's battle sprite on the Jellymon cards",
}
# Named Jogress between two Ultimates that the research does not list as a route (the first DIM
# research left it out): War Greymon + Metal Garurumon = Omegamon. Others come from the research.
EXTRA_SPECIAL = [("wargreymon", "metalgarurumon", "omegamon")]
LEVEL = {"Baby I": "babyI", "Baby II": "babyII", "Child": "child", "Adult": "adult",
         "Perfect": "perfect", "Ultimate": "ultimate"}
ORDER = ["babyI", "babyII", "child", "adult", "perfect", "ultimate"]
ATTR = {"Vaccine": "vaccine", "Data": "data", "Virus": "virus", "Free": "free"}
# Korean names missing from data/evolutions.json, taken from the official Korean reference
# (digimon.net/reference_ko, checked 2026-11-10).
KO_OVERRIDES = {
    "punimon": "푸니몬",
    # checked 2026-11-12
    "nyokimon": "새싹몬",
    "falcomon2006animeversion": "팔코몬(2006)",
    "eosmonperfect": "에오스몬",
    "chicomon": "치코몬",
    "jyarimon": "쟈리몬",
    "megalogrowmonorange": "메가로그라우몬(황)",
    "dukemonxantibody": "듀크몬(X항체)",
}


# Per-card device research (tools/digimon/research). Where a card has it, the card decides: its
# routes are the line's evolutions and its Jogress routes are locked on that line only. Wikimon's
# notes mix devices and games ("with or without ..."), so they are used only for cards without it.
RESEARCH = sorted((HERE / "research").glob("vb-conditions-*.json"))


def edge_kind(e):
    if e.get("kind"):
        return e["kind"]
    if (e.get("requirements") or {}).get("jogress") or "jogress with" in (e.get("raw") or "").lower():
        return "jogress"
    return "fallback" if e.get("isFallback") else "normal"


CONDITIONS = {}   # line id -> {(from, to): (vital values, trophies, battles, win ratio %, fallback)}
PARTNERS = {}     # line id -> {(from, to): [partner, ...]}: who a Jogress route merges with (see jogress_partner)

PARTNER_LEVELS = {"child": "child", "rookie": "child", "adult": "adult", "champion": "adult", "perfect": "perfect"}
ATTRIBUTES = ("vaccine", "data", "virus", "free")


def jogress_partner(e, names):
    """Who a Jogress route merges with: ("kind", level, (attributes...)) for "Jogress with Vaccine or
    Free Adult", or ("species", key) for a named Digimon. Adventure conditions in the same note
    ("Stage 15 cleared") are not used. None when the note cannot be read."""
    j = (e.get("requirements") or {}).get("jogress")
    if isinstance(j, dict) and j.get("partnerAttributes") and j.get("partnerStage"):
        return ("kind", PARTNER_LEVELS[j["partnerStage"].lower()], tuple(sorted(a.lower() for a in j["partnerAttributes"])))
    if isinstance(j, dict) and j.get("partner") and not j.get("partnerAttributes"):
        text = j["partner"]
    else:
        m = re.search(r"[Jj]ogress with (?:an? )?(.+)", j if isinstance(j, str) else (e.get("raw") or ""))
        if not m:
            return None
        text = m.group(1)
    text = re.split(r" from the | after |\.|\"", text)[0].strip()
    words = [w.lower() for w in re.findall(r"[A-Za-z]+", text)]
    attrs = tuple(sorted({w for w in words if w in ATTRIBUTES}))
    levels = [PARTNER_LEVELS[w] for w in words if w in PARTNER_LEVELS]
    if attrs and levels:
        return ("kind", levels[0], attrs)
    key = re.sub(r"[^a-z0-9]", "", text.lower())
    return ("species", names[key]) if key in names else None


def req_number(value):
    """A requirement as a number: 800, "800+", {"min": 800} or {"minPercent": 60}; None when absent."""
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return int(value)
    if isinstance(value, dict):
        for k in ("min", "minPercent", "value"):
            if isinstance(value.get(k), (int, float)):
                return int(value[k])
        return None
    m = re.search(r"[\d,]+", str(value))
    return int(m.group().replace(",", "")) if m else None


def step_conditions(edges):
    """The card's requirements per step. A step written as several routes ("Choose one: <stats> /
    Jogress") keeps its easiest stat route; it is a fallback only when every route for it is one."""
    routes = {}
    for e in edges:
        if e.get("onCard", True) is False:
            continue
        kind = edge_kind(e)
        if kind == "jogress":
            continue
        r = e.get("requirements") or {}
        get = lambda *names: next((req_number(r[n]) for n in names if n in r and req_number(r[n]) is not None), None)
        routes.setdefault((e["from"], e["to"]), []).append(
            (kind, get("vitalValues"), get("trophies", "pp"), get("battles"), get("winRatio")))
    out = {}
    for step, rs in routes.items():
        stat = [x for x in rs if x[0] != "fallback"]
        if stat:
            kind, vv, tr, bt, wr = min(stat, key=lambda x: (x[1] or 0, x[2] or 0))
            out[step] = (vv or 0, tr or 0, bt or 0, wr or 0, False)
        else:
            out[step] = (0, 0, 0, 0, True)
    return out


# Names as research notes write them ("Metal Garurumon (Black)") -> species keys.
NAME_KEYS = {re.sub(r"[^a-z0-9]", "", n["name"].lower()): k for k, n in DATA["nodes"].items()}


def research_cards():
    """{line id: [(from, to, kind), ...]}: the routes on each researched line's card."""
    out = {}
    for path in RESEARCH:
        for line_id, card in json.loads(path.read_text())["cards"].items():
            if line_id in out:
                raise SystemExit(f"{line_id}: researched twice ({path.name})")
            # `extraEdges`: routes on the card the first research found missing from the app data.
            out[line_id] = [(e["from"], e["to"], edge_kind(e)) for e in card["edges"] + card.get("extraEdges", [])
                            if e.get("onCard", True) is not False]
            CONDITIONS[line_id] = step_conditions(card["edges"] + card.get("extraEdges", []))
            partners = PARTNERS.setdefault(line_id, {})
            for e in card["edges"] + card.get("extraEdges", []):
                if e.get("onCard", True) is not False and edge_kind(e) == "jogress":
                    p = jogress_partner(e, NAME_KEYS)
                    if p is None:
                        raise SystemExit(f"{line_id}: {e['from']}>{e['to']}: cannot read the Jogress partner")
                    if p not in partners.setdefault((e["from"], e["to"]), []):
                        partners[(e["from"], e["to"])].append(p)
    return out


def is_jogress_only(edge):
    """The note starts with "Jogress with ...": only a merge evolves it. A normal route with a merge
    as an alternative is written the other way round ("0-2 Care Mistakes ... OR ... Jogress")."""
    note = (edge.get("jogress") or "").strip().lower()
    return note.startswith("jogress with")


def js_str(s):
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'"


def write_moves(keys):
    """The scene's move table (a JS object body, interpolated into DigimonSceneHTML.page)."""
    missing = [k for k in keys if k not in MOVES]
    if missing:
        print(f"no move yet for {len(missing)} species: {', '.join(missing[:8])}{' ...' if len(missing) > 8 else ''}")
    rows = []
    for k in keys:
        m = MOVES.get(k)
        if m:
            tint = f", tint: {js_str(m['tint'])}" if m.get("tint") else ""
            rows.append(f"  {k}: {{ko: {js_str(m['ko'])}, en: {js_str(m['en'])}, kind: {js_str(m['kind'])}{tint}}},")
    body = "\n".join(rows)
    if '"""#' in body or "\\#(" in body:
        raise SystemExit("a move name would break the Swift raw string")
    MOVES_OUT.write_text("\n".join([
        "// Generated by tools/digimon/gen_catalog.py from tools/digimon/data/moves.json. Do not edit.",
        "// Korean from the official Korean Digimon reference (digimon.net/reference_ko), English from the",
        "// Japanese originals (digimon.net/reference_en, or Wikimon where reference_en uses a dub name).",
        "",
        "enum DigimonMovesData {",
        "    /// Body of the scene's `MOVES` object: `key: {ko, en, kind}`; kind picks the drawn attack shape.",
        '    static let js = #"""',
        body,
        '"""#',
        "}",
        "",
    ]))


def swift_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    nodes, edges = DATA["nodes"], DATA["edges"]
    lines, keys = [], []
    for line_id, card_name, egg, size in LINES:
        card = next(c for c in DATA["cards"] if c["name"] == card_name
                    and (size is None or len([k for k in c["roster"] if k in nodes]) == size))
        # A card species missing from the data used to be skipped without a word (Huckmon, Kodokugumon):
        # stop instead, so a new card shows its gaps. Fix the match in fetch_wikimon.SPRITE_TITLES or
        # build_data.CARD_ONLY_SPECIES, or list a roster entry that is not a species here.
        unknown = [k for k in card["roster"] if k not in nodes and k not in NOT_SPECIES]
        if unknown:
            raise SystemExit(f"{line_id}: card species missing from data/evolutions.json: {', '.join(unknown)}")
        # Armor Digimon need Digimentals, not growth: they are left out.
        skipped = [k for k in card["roster"] if k in nodes and nodes[k]["level"] not in LEVEL]
        if skipped:
            print(f"{line_id}: leaving out {', '.join(skipped)} (level not raised by growth)")
        roster = [k for k in card["roster"] if k in nodes and nodes[k]["level"] in LEVEL]
        if line_id not in roster:
            raise SystemExit(f"{line_id}: the line id must be a species on its card")
        baby1 = next(k for k in roster if nodes[k]["level"] == "Baby I")
        lines.append((line_id, card_name, egg, baby1, roster))
        keys += [k for k in roster if k not in keys]

    species = []
    for k in keys:
        n = nodes[k]
        level = LEVEL.get(n["level"])
        if not level:
            raise SystemExit(f"{k}: unsupported level {n['level']!r}")
        sp = n["sprites"]
        if "vb" not in sp:
            raise SystemExit(f"{k}: no 64x64 Vital Bracelet sprite")
        # Korean name: a checked override, then the official reference name found with the move.
        ko = KO_OVERRIDES.get(k) or MOVES.get(k, {}).get("koSpecies") or n["ko"] or n["name"]
        species.append((k, n["name"], ko, level, ATTR.get(n.get("attribute", ""), "unknown"),
                        sp["vb"], sp.get("dmc") or sp.get("dpc") or ""))

    level_of = {s[0]: s[3] for s in species}
    keyset = set(keys)
    next_level = lambda a, b: ORDER.index(level_of[b]) == ORDER.index(level_of[a]) + 1
    wikimon = {}
    for e in edges:
        a, b = e["from"], e["to"]
        if a in keyset and b in keyset and next_level(a, b):  # warps and skips are not used
            srcs = sorted({s.split(":")[0].lower() for s in e["sources"]})
            wikimon[(a, b)] = (srcs, bool(e.get("canon")), is_jogress_only(e))

    # Each line's own evolutions ("steps") and the ones only a Jogress takes on its card.
    device = research_cards()
    evo = dict(wikimon)
    steps_of, merges_of = {}, {}
    special = {}   # result -> {from, ...}: Ultimates that merge into another Ultimate
    for line_id, _, _, _, roster in lines:
        members = set(roster)
        if line_id in device:
            routes = [(a, b, k) for a, b, k in device[line_id] if a in members and b in members]
            # "Choose one: <stats> / Jogress with ..." is written as two routes for the same step; the
            # step is a merge only when every route for it is a Jogress.
            kinds = {}
            for a, b, k in routes:
                kinds.setdefault((a, b), set()).add(k)
            steps, merges = set(), set()
            for a, b, k in routes:
                up = ORDER.index(level_of[b]) - ORDER.index(level_of[a])
                if up == 0 and k == "jogress":
                    special.setdefault(b, set()).add(a)   # a full Ultimate merges instead of graduating
                    continue
                if up <= 0:
                    raise SystemExit(f"{line_id}: {a}>{b} does not go up a level")
                if up > 1:
                    print(f"{line_id}: {a}>{b} skips {up - 1} level(s) on the card, kept")
                if (a, b) not in evo:
                    print(f"{line_id}: {a}>{b} is on the card but not in the Wikimon data, added")
                    evo[(a, b)] = (["vb"], False, False)
                steps.add((a, b))
                if kinds[(a, b)] == {"jogress"}:
                    merges.add((a, b))
            dropped = sorted(f"{a}>{b}" for (a, b) in wikimon if a in members and b in members and (a, b) not in steps)
            if dropped:
                print(f"{line_id}: not on the card, left out: {', '.join(dropped)}")
        else:
            steps = {(a, b) for (a, b) in wikimon if a in members and b in members}
            merges = {(a, b) for (a, b) in steps if wikimon[(a, b)][2]}
            print(f"{line_id}: no card research, using every Wikimon device route")
        steps_of[line_id], merges_of[line_id] = steps, merges
    for a, partner, b in EXTRA_SPECIAL:
        special.setdefault(b, set()).update({a, partner})
    jogress = []   # (from, partner, to), both directions
    for b, froms in sorted(special.items()):
        if len(froms) != 2:
            raise SystemExit(f"{b}: a named Jogress needs exactly two partners, got {sorted(froms)}")
        x, y = sorted(froms)
        jogress += [(x, y, b), (y, x, b)]

    # A Digimon the card can never reach (no route in from the egg, not even a merge) is left out
    # of the line, so the dex does not show one that cannot be met there.
    pruned = []
    for i, (line_id, card_name, egg, baby1, roster) in enumerate(lines):
        reach, grew = {baby1}, True
        while grew:
            grew = False
            for a, b in steps_of[line_id]:
                if a in reach and b not in reach:
                    reach.add(b); grew = True
            for a, partner, b in jogress:
                if a in reach and b in roster and b not in reach:
                    reach.add(b); grew = True
        gone = [k for k in roster if k not in reach]
        if gone:
            print(f"{line_id}: no route reaches {', '.join(gone)} on this card, left out of the line")
        # A Digimon below Ultimate with no way on (its next forms are missing from the Wikimon data,
        # e.g. Arresterdramon -> Savior Hackmon) would end the line early: left out too, and so is a
        # Digimon whose only way on led there.
        merging = {a for a, _, b in jogress if b in roster}
        while True:
            alive = reach - set(gone)
            dead = [k for k in roster if k in alive and level_of[k] != "ultimate" and k not in merging
                    and not any(a == k and b in alive and (a, b) not in merges_of[line_id] for a, b in steps_of[line_id])]
            if not dead:
                break
            print(f"{line_id}: {', '.join(dead)} cannot grow on (next forms missing), left out of the line")
            gone += dead
        if gone:
            reach -= set(gone)
            steps_of[line_id] = {(a, b) for (a, b) in steps_of[line_id] if a in reach and b in reach}
            merges_of[line_id] &= steps_of[line_id]
        # Without its first baby the egg has nothing to hatch into, and the engine would try forever.
        if baby1 not in reach:
            raise SystemExit(f"{line_id}: its first baby {baby1} cannot grow up to an Ultimate on this card; "
                             "fix the data or leave the line out")
        pruned.append((line_id, card_name, egg, baby1, [k for k in roster if k in reach]))
    lines = pruned
    # A card route above the baby stages always asks for something (stats, or a fallback when nothing
    # else is met). One with no requirement at all is a research slip: "Stage 15 cleared, Jogress with
    # ..." was written as an Adventure route, so growth took a merge-only Ultimate for free.
    for line_id, *_ in lines:
        for a, b in sorted(steps_of[line_id] - merges_of[line_id]):
            if level_of[a] not in ("babyI", "babyII") and CONDITIONS.get(line_id, {}).get((a, b)) == (0, 0, 0, 0, False):
                raise SystemExit(f"{line_id}: {a}>{b} is a card route with no requirement; "
                                 "check its kind in the research (a Jogress written as another kind?)")
    keep = {k for *_, roster in lines for k in roster}
    species = [sp for sp in species if sp[0] in keep]
    keys = [k for k in keys if k in keep]

    out = [
        "// Generated by tools/digimon/gen_catalog.py from tools/digimon/data/evolutions.json and the",
        "// per-card research in tools/digimon/research. Do not edit.",
        "// Evolution data source: Wikimon (https://wikimon.net), text licensed CC BY-SA 3.0.",
        "// Sprites are not bundled; only their Wikimon file names are referenced.",
        "",
        "enum DigimonCatalogData {",
        "    static let species: [DigimonSpecies] = [",
    ]
    for k, name, ko, level, attr, vb, color in species:
        out.append(f"        DigimonSpecies(key: {swift_str(k)}, name: {swift_str(name)}, koreanName: {swift_str(ko)}, "
                   f"level: .{level}, attribute: .{attr}, vbSprite: {swift_str(vb)}, colorSprite: {swift_str(color)}),")
    out += ["    ]", "", "    static let evolutions: [DigimonEvolution] = ["]
    used = set().union(*steps_of.values())
    for (a, b) in sorted(used, key=lambda ab: (keys.index(ab[0]), keys.index(ab[1]))):
        srcs, canon, _ = evo[(a, b)]
        src = ", ".join("." + {"vb": "vitalBracelet", "dmc": "digitalMonsterColor", "dpc": "pendulumColor"}[s]
                        for s in srcs)
        out.append(f"        DigimonEvolution(from: {swift_str(a)}, to: {swift_str(b)}, sources: [{src}], canon: {str(canon).lower()}),")
    out += ["    ]", "",
            "    /// Named Jogress between two Ultimates: with the partner raised before, a full stage merges",
            "    /// instead of graduating (EvolutionRules.specialJogress). Both directions are listed.",
            "    static let specialJogress: [EvolutionRules.SpecialJogress] = ["]
    for a, partner, b in jogress:
        out.append(f"        .init(from: {swift_str(a)}, partner: {swift_str(partner)}, to: {swift_str(b)}),")
    out += ["    ]", "", "    static let lines: [DigimonLine] = ["]
    step = lambda ab: swift_str(f"{ab[0]}>{ab[1]}")
    for line_id, card_name, egg, baby1, roster in lines:
        members = ", ".join(swift_str(k) for k in roster)
        order = lambda ab: (roster.index(ab[0]), roster.index(ab[1]))
        steps = ", ".join(step(ab) for ab in sorted(steps_of[line_id], key=order))
        merges = ", ".join(step(ab) for ab in sorted(merges_of[line_id], key=order))
        out.append(f"        DigimonLine(id: {swift_str(line_id)}, card: {swift_str(card_name)}, eggColorHex: {swift_str(egg)},")
        out.append(f"                    firstBaby: {swift_str(baby1)}, members: [{members}],")
        out.append(f"                    steps: [{steps}],")
        out.append(f"                    mergeSteps: [{merges}],")
        rows = []
        for ab in sorted(steps_of[line_id], key=order):
            for p in PARTNERS.get(line_id, {}).get(ab, []):
                if p[0] == "species":
                    if p[1] not in keyset:
                        print(f"{line_id}: {ab[0]}>{ab[1]}: partner {p[1]} is not in the catalog, left out")
                        continue
                    rows.append(f".init({step(ab)}, species: {swift_str(p[1])})")
                else:
                    attrs = ", ".join("." + a for a in p[2])
                    rows.append(f".init({step(ab)}, level: .{p[1]}, attributes: [{attrs}])")
        out.append(f"                    jogress: [{', '.join(rows)}],")
        conds = CONDITIONS.get(line_id, {})
        rows = []
        for ab in sorted(steps_of[line_id], key=order):
            if ab in conds and ab not in merges_of[line_id]:
                vv, tr, bt, wr, fb = conds[ab]
                rows.append(f".init({step(ab)}, vital: {vv}, trophies: {tr}, battles: {bt}, winRatio: {wr}, fallback: {str(fb).lower()})")
        out.append(f"                    conditions: [{', '.join(rows)}]),")
    out += ["    ]", "}", ""]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(out))
    write_moves(keys)
    print(f"{len(species)} species, {len(used)} evolutions, {len(lines)} lines -> {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
