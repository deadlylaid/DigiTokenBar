#!/usr/bin/env python3
"""Generate Sources/PokeTokenBar/Digimon/DigimonCatalogData.swift from data/evolutions.json.

Only the MVP lines (Vital Bracelet cards listed in LINES) are emitted. Evolution data lives
here; evolution *conditions* (hidden rules, locks) live in Swift (EvolutionRules), so the two
stay separate.

    python3 -I tools/digimon/gen_catalog.py
"""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
DATA = json.loads((HERE / "data" / "evolutions.json").read_text())
OUT = ROOT / "Sources" / "PokeTokenBar" / "Digimon" / "DigimonCatalogData.swift"

# line id (a Child species key on the card), Vital Bracelet card name, egg spot color (RGB hex,
# drawn in code), and which card when several share the name (roster size).
LINES = [
    ("agumon", "Agumon", "F28C3E", None),
    ("gabumon", "Gabumon", "5496E6", None),
    ("piyomon", "BEMemory Holy Wings Dim", "F07FA6", None),
    ("tentomon", "BEMemory Forest Guardians Dim", "6DB33F", None),
    ("vmon", "Ancient Warriors", "6B5BD6", None),
    ("guilmon", "Guilmon", "D9473B", 17),
]
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
    if (e.get("requirements") or {}).get("jogress"):
        return "jogress"
    return "fallback" if e.get("isFallback") else "normal"


def research_cards():
    """{line id: [(from, to, kind), ...]}: the routes on each researched line's card."""
    out = {}
    for path in RESEARCH:
        for line_id, card in json.loads(path.read_text())["cards"].items():
            if line_id in out:
                raise SystemExit(f"{line_id}: researched twice ({path.name})")
            out[line_id] = [(e["from"], e["to"], edge_kind(e)) for e in card["edges"]
                            if e.get("onCard", True) is not False]
    return out


def is_jogress_only(edge):
    """The note starts with "Jogress with ...": only a merge evolves it. A normal route with a merge
    as an alternative is written the other way round ("0-2 Care Mistakes ... OR ... Jogress")."""
    note = (edge.get("jogress") or "").strip().lower()
    return note.startswith("jogress with")


def swift_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    nodes, edges = DATA["nodes"], DATA["edges"]
    lines, keys = [], []
    for line_id, card_name, egg, size in LINES:
        card = next(c for c in DATA["cards"] if c["name"] == card_name
                    and (size is None or len([k for k in c["roster"] if k in nodes]) == size))
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
        species.append((k, n["name"], KO_OVERRIDES.get(k) or n["ko"] or n["name"], level, ATTR.get(n.get("attribute", ""), "unknown"),
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
    for line_id, _, _, _, roster in lines:
        members = set(roster)
        if line_id in device:
            routes = [(a, b, k) for a, b, k in device[line_id] if a in members and b in members]
            for a, b, k in routes:
                if not next_level(a, b):
                    raise SystemExit(f"{line_id}: {a}>{b} skips a level")
                if (a, b) not in evo:
                    print(f"{line_id}: {a}>{b} is on the card but not in the Wikimon data, added")
                    evo[(a, b)] = (["vb"], False, False)
            steps = {(a, b) for a, b, _ in routes}
            merges = {(a, b) for a, b, k in routes if k == "jogress"}
            dropped = sorted(f"{a}>{b}" for (a, b) in wikimon if a in members and b in members and (a, b) not in steps)
            if dropped:
                print(f"{line_id}: not on the card, left out: {', '.join(dropped)}")
        else:
            steps = {(a, b) for (a, b) in wikimon if a in members and b in members}
            merges = {(a, b) for (a, b) in steps if wikimon[(a, b)][2]}
            print(f"{line_id}: no card research, using every Wikimon device route")
        steps_of[line_id], merges_of[line_id] = steps, merges

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
        out.append(f"                    mergeSteps: [{merges}]),")
    out += ["    ]", "}", ""]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(out))
    print(f"{len(species)} species, {len(used)} evolutions, {len(lines)} lines -> {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
