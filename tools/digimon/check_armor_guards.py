"""Break research/armor-routes.json four ways and check that gen_catalog.py stops each time (step 13).

Restores the research and the generated files afterwards.

    python3 -I tools/digimon/check_armor_guards.py <repo root>
"""
import json, subprocess, sys
from pathlib import Path
ROOT = Path(sys.argv[1])
P = ROOT / "tools/digimon/research/armor-routes.json"
backup = P.read_text()
cat = ROOT / "Sources/PokeTokenBar/Digimon/DigimonCatalogData.swift"
moves = ROOT / "Sources/PokeTokenBar/Digimon/DigimonMovesData.swift"
cat_backup, moves_backup = cat.read_text(), moves.read_text()
def run(name, mutate, expect):
    d = json.loads(backup)
    mutate(d)
    P.write_text(json.dumps(d, ensure_ascii=False))
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
finally:
    P.write_text(backup)
    cat.write_text(cat_backup)
    moves.write_text(moves_backup)
if failed:
    sys.exit(f"guards that did not stop: {failed}")
