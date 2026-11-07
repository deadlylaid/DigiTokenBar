#!/usr/bin/env python3
"""Count which Digimon we can raise, allowing branching evolution.

Rule: a Child is makeable if, following device-sourced edges (VB / DMC / DPC) one level at a
time, it reaches at least one Adult — and every Digimon on the way has a 64x64 Vital Bracelet
sprite (the popover / desktop image). Menu bar sprites (16x16 color) are optional.

    python3 -I tools/digimon/report.py            # summary
    python3 -I tools/digimon/report.py --cards    # Vital Bracelet card trees (MVP candidates)
"""
import json
import sys
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
D = json.loads((HERE / "data" / "evolutions.json").read_text())
N, E = D["nodes"], D["edges"]
STAGES = ["Child", "Adult", "Perfect", "Ultimate"]


def has_vb(k):
    return "vb" in N.get(k, {}).get("sprites", {})


def at(k, level):
    """Use each Digimon's primary level (Wikimon's first listed level)."""
    return N.get(k, {}).get("level") == level


nxt = defaultdict(list)
for e in E:
    nxt[e["from"]].append(e)


def branches(k, level, only=None):
    """Next-stage Digimon (with 64x64 sprite) reachable from k by device edges."""
    out = []
    for e in nxt[k]:
        t = e["to"]
        if only is not None and t not in only:
            continue
        if at(t, level) and has_vb(t) and not e.get("jogress"):
            out.append(t)
    return sorted(set(out))


def reach(k, only=None):
    """Deepest stage reachable from Child k (index into STAGES) and branch counts per stage."""
    frontier, best, counts = {k}, 0, []
    for i, level in enumerate(STAGES[1:], start=1):
        nxt_frontier = set()
        for f in frontier:
            nxt_frontier |= set(branches(f, level, only))
        if not nxt_frontier:
            break
        counts.append(len(nxt_frontier))
        frontier, best = nxt_frontier, i
    return best, counts


def name(k):
    n = N[k]
    return n["ko"] or n["name"]


def summary():
    kids = [k for k, n in N.items() if n["level"] == "Child" and has_vb(k)]
    rows = [(k,) + reach(k) for k in kids]
    ok = [r for r in rows if r[1] >= 1]
    by = defaultdict(list)
    for k, best, counts in ok:
        by[STAGES[best]].append(k)
    print(f"Child with 64x64 sprite: {len(kids)}  |  makeable (reaches Adult or later): {len(ok)}")
    for st in reversed(STAGES[1:]):
        print(f"  up to {st}: {len(by[st])}")
    pool = set()
    for k, _, _ in ok:
        frontier = {k}
        pool.add(k)
        for level in STAGES[1:]:
            frontier = {t for f in frontier for t in branches(f, level)}
            pool |= frontier
    print(f"distinct Digimon in all those trees: {len(pool)}")
    print("not makeable:", ", ".join(sorted(name(r[0]) for r in rows if r[1] == 0)))
    return ok


def cards():
    print("\nVital Bracelet cards (roster of each card, VB edges inside the card only)")
    for c in D["cards"]:
        roster = [k for k in c["roster"] if k in N]
        inside = set(roster)
        kids = [k for k in roster if N[k]["level"] == "Child"]
        trees = [(k,) + reach(k, inside) for k in kids]
        missing = [k for k in c["roster"] if not has_vb(k)]
        print(f"- {c['name']} ({c['release_jp']}): {len(c['roster'])} Digimon, Child: "
              + ", ".join(f"{name(k)}→{STAGES[b]}{counts}" for k, b, counts in trees)
              + (f"  | no 64x64: {missing}" if missing else ""))


if __name__ == "__main__":
    summary()
    if "--cards" in sys.argv:
        cards()
