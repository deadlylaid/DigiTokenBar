# Vital Bracelet evolution conditions (research, 2026-11-12)

What the devices require for each evolution, per Vital Bracelet card, and the moves and official
Korean names of the species. `gen_catalog.py` uses the routes (which evolutions a card has, and
which are a Jogress); the numbers (Vital Values, trophies, battles, win ratio, Adventure stages) are
not used by the app yet. `add_moves.py` copies the moves into `data/moves.json`.

| File | Cards |
|---|---|
| `vb-conditions-dim.*` | Agumon EX, Gabumon EX, Ancient Warriors, Guilmon EX2 (Vital Bracelet DIM cards) |
| `vb-conditions-bememory.*` | BEMemory Holy Wings, BEMemory Forest Guardians (Vital Bracelet BE) |
| `vb-conditions-step7.json` | The 28 cards added in step 7 (DIM, DIM vol. 0.5, Primeval Warriors, BEMemory) |
| `moves-step7.json` | Moves and official Korean names of the 421 species added in step 7 |
| `move-shape-review.json` | Review of every move's drawn shape (2026-11-14): verdict per move and the changes applied. New moves from `add_moves.py` get the same review. |
| `moves-restored.json` | Moves and official Korean names of the 7 species restored to the data on 2026-11-13 |
| `vb-conditions-frontier.json` | The six Frontier DIM cards added in step 11 (Agnimon, Fairimon, Chackmon, Wolfmon, Blitzmon, Louwemon), with `cardStages` and `cardAttributes` for the Hybrid Digimon |
| `moves-frontier.json` | Moves and official Korean names of the 82 species on the Frontier cards; `kind`/`tint` set by eye |
| `armor-routes.json` | Step 13: the Armor Digimon routes of nine cards (V-mon, Wormmon, Hawkmon, Armadimon, Renamon, Terriermon, Blucomon, Sunarizamon, Piyomon lines), with `cardStages`, the Digimental each step into an Armor Digimon needs and how it was chosen, the official check, and Wikimon's Digimental Evolution Chart |
| `moves-armor.json` | Moves and official Korean names of the 20 Armor Digimon; `kind`/`tint` set by eye |

- Per-edge numbers come mainly from humulos.com (a fan site that documents the devices). For
  Agumon, Gabumon and Ancient Warriors they were checked against Gamerch (JP wiki) and a JP
  community sheet; Guilmon EX2 and the BEMemory cards rest on humulos alone. No Bandai source with
  per-route numbers was found.
- The JSON keeps short quotes of the sources (`raw`) for checking. They are third-party text:
  review before making this repository public.
- Step 7 (2026-11-13): five research agents, humulos detail pages per card for the routes and the
  official Korean reference (digimon.net/reference_ko, reference_en, reference) for the moves.
  A "Choose one: <stats> / Jogress" route is written as two routes for the same step; only a step
  with nothing but Jogress routes is locked.
- Step 11 (2026-11-19): collected by script instead of agents. Routes from the humulos chart
  (`vbdm/ex`, which also gives each species' stage column) and detail pages (device 13); moves from
  the official reference (ko/en/ja) and the cached Wikimon pages (`.cache/pages`) for the Japanese
  original where reference_en uses a dub name. A "Stage 15 cleared, Jogress with ..." route is a
  Jogress (2026-11-19 fix: eleven such routes in `vb-conditions-step7.json` had been Adventure routes).
- Step 13 (2026-11-21): `scripts/armor_routes.py` collects the Armor routes from the humulos charts
  and detail pages (device 13 = DIM, 14 = BE; BE cards count PP instead of trophies). A step into
  an Armor Digimon from another level gets a Digimental (Wikimon's chart pair, else the Armor
  Digimon's first chart column) and is checked against the official profile ("Digi-Egg of ...").
- `scripts/`: the step 11 collection scripts (`frontier_routes.py` for the humulos routes,
  `official_reference.py` for the official reference, `draft_moves.py` for the move draft) and the
  step 13 `armor_routes.py`. They are a record of the method, not part of the build.
