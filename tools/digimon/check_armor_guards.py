"""Break the armor research and check that gen_catalog.py stops each time (steps 13 and 16).

Breaks research/armor-routes.json (the cards' Armor routes) and research/digimental-chart-routes.json
(the Digimental chart routes no card has) one way at a time. Restores both and the generated files
afterwards.

    python3 -I tools/digimon/check_armor_guards.py <repo root>
"""
import json, subprocess, sys
from pathlib import Path
ROOT = Path(sys.argv[1])
P = ROOT / "tools/digimon/research/armor-routes.json"
C = ROOT / "tools/digimon/research/digimental-chart-routes.json"
backup, chart_backup = P.read_text(), C.read_text()
cat = ROOT / "Sources/PokeTokenBar/Digimon/DigimonCatalogData.swift"
moves = ROOT / "Sources/PokeTokenBar/Digimon/DigimonMovesData.swift"
cat_backup, moves_backup = cat.read_text(), moves.read_text()
def run(name, mutate, expect, chart=None):
    d, c = json.loads(backup), json.loads(chart_backup)
    if mutate:
        mutate(d)
    if chart:
        chart(c, d)
    P.write_text(json.dumps(d, ensure_ascii=False))
    C.write_text(json.dumps(c, ensure_ascii=False))
    r = subprocess.run([sys.executable, "-I", str(ROOT / "tools/digimon/gen_catalog.py")], capture_output=True, text=True)
    out = (r.stdout + r.stderr).strip().splitlines()[-1]
    ok = r.returncode != 0 and expect in out
    print(("OK  " if ok else "FAIL"), name, "->", out)
    if not ok:
        failed.append(name)
failed = []
try:
    run("(a) no Digimental on V-mon > Fladramon", lambda d: d["cards"]["vmon"]["digimentals"].pop("vmon>fladramon"),
        "goes into an Armor Digimon without a Digimental")
    def no_way_on(d):
        c = d["cards"]["blucomon"]
        c["edges"] = [e for e in c["edges"] if e["from"] != "moosemon"]
    run("(b) Moosemon loses its routes on", no_way_on, "no way on")
    def unknown(d):
        d["cards"]["vmon"]["digimentals"]["vmon>fladramon"]["digimental"] = "bravery"
    run("(c) unknown Digimental", unknown, "unknown Digimental")
    # Only a Child armor-evolves with a Digimental (user decision 2026-11-21); an Adult's route into an
    # Armor Digimon is an ordinary card route.
    def adult(d):
        d["cards"]["vmon"]["digimentals"]["vdramon>sagittarimon"] = {"digimental": "hope", "rule": "pair"}
    run("(d) a Digimental on V-dramon > Sagittarimon (an Adult)", adult, "does not start at a Child")

    # Step 16: the Digimental chart routes (they skip stages, so only their own guards hold them).
    def wrong_pair(c, d):
        c["cards"]["vmon"]["routes"][0]["digimentals"] = ["fate"]   # V-mon / fate is Gold V-dramon, not Magnamon
    run("(e) V-mon > Magnamon with Fate (not a chart pair)", None, "not a pair of the Digimental chart", wrong_pair)
    def off_line(c, d):
        # The chart has Terriermon / miracles / Magnamon, but Magnamon is not on the Terriermon card.
        c["cards"]["terriermon"]["routes"].append({"from": "terriermon", "to": "magnamon", "digimentals": ["miracles"]})
    run("(f) Terriermon > Magnamon (Magnamon is not on the line)", None, "off the line", off_line)
    def from_adult(c, d):
        d["system"]["digimentalChart"]["pairs"].append({"base": "V-dramon", "digimental": "miracles", "armor": "Magnamon"})
        c["cards"]["vmon"]["routes"].append({"from": "vdramon", "to": "magnamon", "digimentals": ["miracles"]})
    run("(g) a chart route from V-dramon (an Adult)", None, "does not start at a Child", from_adult)
    def card_route(c, d):
        c["cards"]["wormmon"]["routes"].append({"from": "wormmon", "to": "shadramon", "digimentals": ["courage"]})
    run("(h) a chart route the card already has (Wormmon > Shadramon)", None, "already a card route", card_route)
    def gold_stuck(c, d):
        v = d["cards"]["vmon"]
        v["edges"] = [e for e in v["edges"] if e["from"] != "goldvdramon"]
    run("(i) Gold V-dramon (a Perfect Armor) loses its routes on", None, "no way on", gold_stuck)
    def twice(c, d):
        c["cards"]["terriermon"]["routes"][0]["digimentals"] = ["fate", "fate"]
    run("(j) the same Digimental twice on one step", None, "one twice", twice)
finally:
    P.write_text(backup)
    C.write_text(chart_backup)
    cat.write_text(cat_backup)
    moves.write_text(moves_backup)
if failed:
    sys.exit(f"guards that did not stop: {failed}")
