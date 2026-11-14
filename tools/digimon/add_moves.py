#!/usr/bin/env python3
"""Add researched moves to data/moves.json (never changes an entry that is already there).

Reads tools/digimon/research/moves-*.json: [{key, ko, en, what, koSpecies, sources, note}, ...]
and picks the drawn attack shape from `what` (a few words on what the move physically is) and the
species level. Run gen_catalog.py afterwards.

    python3 -I tools/digimon/add_moves.py
"""
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATA = HERE / "data" / "moves.json"
NODES = json.loads((HERE / "data" / "evolutions.json").read_text())["nodes"]

# Checked in order: the first matching shape wins. The rules follow the 2026-11-14 review of every
# move (research/move-shape-review.json): beams, lasers, cries and songs are a straight shot (fire);
# punches, kicks, tackles and bites are melee (claw); a giant sphere, lightning from the sky or a
# huge blast is gaia. Check new moves by eye: the words only point the way.
SHAPES = [
    # Binding moves (tentacles, vines, threads, whips): a tendril that coils around the target.
    ("bind", r"\b(binds?|binding|entangl\w*|restrain\w*|wraps?|coils?|whips?|lash\w*|ensnar\w*|snares?|vines?|ivy|"
             r"threads?|silk|webs?|bandages?|tongues?)\b"),
    ("ice", r"\b(ice|icy|icicles?|freez\w*|frost\w*|snow\w*|blizzard|cold|hail|frozen|diamond dust)\b"),
    ("missile", r"\b(missiles?|rockets?|bullets?|guns?|gunfire|rifles?|revolvers?|gatling|autocannon|bombs?|torpedo\w*|"
                r"grenades?|arrows?|darts?|needles?|quills?|projectiles?|throws?|hurls?|thrown)\b"),
    ("claw", r"\b(claws?|slash\w*|blades?|swords?|cuts?|scratch\w*|kicks?|punch\w*|fists?|bites?|biting|pecks?|"
             r"tackle\w*|rams?|ramming|headbutt\w*|horns?|spears?|lances?|slams?|charges?|charging|axes?|scythes?|"
             r"hammers?|clubs?|stabs?|skewer\w*|pierc\w*|rush\w*|chops?|drills?|fangs?|talons?|lunges?|"
             r"smash\w*|crush\w*|lariat|uppercut|slaps?|knife|knives|katana|mace)\b"),
    ("fire", r"\b(beams?|lasers?|rays?|breath\w*|spits?|spew\w*|bubbles?|sparks?|static|shots?|howl\w*|bark\w*|"
             r"cry|cries|songs?|sings?|voice|shout\w*|fireballs?|flames?|fire|blaze|burn\w*)\b"),
    ("gaia", r"\b(spheres?|orbs?|explo\w*|lightning|thunder\w*|meteors?|darkness|cosmic|black hole|tornado\w*|"
             r"shockwaves?|aura|earthquake|nuclear|annihilat\w*)\b"),
]


def shape(what, level):
    text = (what or "").lower()
    for kind, pattern in SHAPES:
        if re.search(pattern, text):
            return kind
    return "fire"


def main():
    data = json.loads(DATA.read_text())
    moves = data["moves"]
    added, skipped = [], []
    for path in sorted((HERE / "research").glob("moves-*.json")):
        for row in json.loads(path.read_text()):
            key = row["key"]
            if key in moves:
                continue
            if not row.get("ko") or not row.get("en"):
                skipped.append(key)
                continue
            level = NODES.get(key, {}).get("level", "")
            entry = {"ko": row["ko"], "en": row["en"], "kind": shape(row.get("what"), level)}
            if row.get("koSpecies"):
                entry["koSpecies"] = row["koSpecies"]
            moves[key] = entry
            added.append((key, entry["kind"], row.get("what")))
    DATA.write_text(json.dumps(data, ensure_ascii=False, indent=1))
    counts = {}
    for _, kind, _ in added:
        counts[kind] = counts.get(kind, 0) + 1
    print(f"added {len(added)} moves {counts}; skipped (no name) {skipped}")
    return added


if __name__ == "__main__":
    main()
