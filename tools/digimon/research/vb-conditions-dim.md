# Vital Bracelet evolution conditions: Agumon, Gabumon, Ancient Warriors, Guilmon DIMs

Full data: `vb_conditions_a.json` (per edge: requirements, quoted raw text, source URL or file, corroboration, disagreements, app mismatches).

## How the VB evolution system works

- **Device scope.** The evolution data is stored on the DIM card, so the same card has the same requirements on the Vital Bracelet Digital Monster (2021), Digivice -V- and Vital Hero. The devices differ only in how time and Vital Values (VV) accrue: on the Digivice -V-/Vital Hero sleep time counts toward evolution and steps earn 4 VV per 50 instead of 1. The Vital Bracelet BE reads DIMs but attribute Jogress does not work there.
- **Requirement types** (all counted within the current stage; every stat resets at each evolution except Baby I→II and II→III):
  - **Vital Values.** Earned from heart rate and steps, plus battle wins; lost on battle losses and while the device is not worn. Per-stage cap: Child 2,500, Adult 5,000, Perfect 7,500, Ultimate 9,999.
  - **Trophies.** From missions: a daily Normal Mission (1), Hard exercise missions (1-2 each, 4 per day), and Special Missions (3, from the VB Lab app, which shut down in 2023).
  - **Battles.** Wins plus losses: NFC, VS DIM, end of an Adventure Mission, VB Arena.
  - **Win ratio.** A minimum percentage within the stage.
  - **Time.** The stage timer: Baby I 1 h, Baby II 3 h, Child 16 h, Adult 24 h, Perfect 24 h. Backup and power-off pause it; on the original VB sleep pauses it too.
  - **Adventure Stage 15.** Clearing the 15th Adventure area of a DIM unlocks one hidden evolution per card. The device remembers this per DIM.
  - **Jogress.** At the Adult→Perfect and Perfect→Ultimate checks, a backup Digimon of the same stage, a different attribute, and an attribute listed for a route makes the active Digimon jogress. No stats are checked, the partner only has to be in backup when the timer ends, and Jogress has priority over normal evolution. The special Jogress War Greymon (Agumon DIM) + Metal Garurumon (Gabumon DIM) → Omegamon is checked every 3 h.
  - **No care mistakes.** The VB has no feeding or care system. Death comes from 4 injuries in a day (losing a battle while upset) or 24 h unworn.
- **Decision when the timer ends.**
  1. A valid Jogress partner wins.
  2. Otherwise, if several stat routes are met, the device takes the first one in the DIM data order. Observed pattern: the highest VV requirement, then the highest win ratio (Humulos FAQ; one Gamerch player report agrees).
  3. Child→Adult always has a fallback (e.g. Agumon→Coelamon if trophies ≤2 **or** VV ≤499), so a Child always evolves.
  4. Adult/Perfect with nothing met: no evolution. The timer resets and the check repeats after the same time (Humulos manual, Gamerch).
- **These four cards** are first-wave DIMs (2021-22) that share one template:
  - Child→Adult: 4 tiers, the lowest a fallback.
  - Each Adult: 3 stat routes (12T/3000VV/15B/70%, 10T/2500/10/50%, 6T (8T on Guilmon)/2000/10/50%) plus 2 Jogress routes (3 on Guilmon).
  - Perfect→Ultimate thresholds are per target: 20T/5000/20/70%, 15T/4500/15/70%, 10T/4500/15/50%, and the Stage 15 unlock at 20T/7000/25/70%.
  - Exceptions: Ancient Warriors uses 8T for V-dramon. Guilmon EX2 Child tiers are 10T/1300VV/8B, 8T/900/5, 5T/600/3, fallback ≤4T or ≤599VV or ≤2B. Metal Greymon→War Greymon needs only 10T (other parents need 20T).
  - Other cards differ: Dinosaur Roar/Wolf Howl have 1,200 VV at Baby II and Omegamon by stats (30T/8500/30B/70%, 24 h). GP cards mix stats and Jogress in "choose one" lists. The BE uses its own system.

## Coverage (app edges with a stated condition / total)

| Card (DIM) | Stated | 2nd source agrees | Single-source | Disagreements | App lock mismatches | Card routes missing from app |
|---|---|---|---|---|---|---|
| Agumon (EX) | **44 / 44** | 44 | 0 | 0 | 3 | 1 |
| Gabumon (EX) | **44 / 44** | 44 | 0 | 0 | 1 | 1 |
| Ancient Warriors | **23 / 23** | 23 | 0 | 0 | 2 | 27 |
| Guilmon (EX2) | **54 / 54** | 25 | 29 | 0 | 3 | 0 |

Every app edge exists on its card per Humulos, so none is marked unknown. Guilmon EX2 has no second source for its 29 stat, fallback and time-only edges (Gamerch and the JP sheet do not cover EX2). Its 23 Jogress edges agree with Wikimon's partner notes, and its 2 time-only edges also match Wikimon's general time table.

## Findings for the app

- **9 edges are Jogress-only on the device but `lockedAsMerge=false` in the app:**
  - Agumon: Coelamon → Metal Tyranomon (partner: Virus Attribute Adult in the backup slot)
  - Agumon: Greymon → Andromon (partner: Data or Free Attribute Adult in the backup slot)
  - Agumon: Mamemon → War Greymon (partner: Vaccine or Free Attribute Perfect in the backup slot)
  - Gabumon: Big Mamemon → Metal Garurumon (partner: Vaccine or Free Attribute Perfect in the backup slot)
  - Ancient Warriors: Paildramon → Ulforce V-dramon (partner: Vaccine or Virus Attribute Perfect in the backup slot)
  - Ancient Warriors: XV-mon → Aero V-dramon (partner: Vaccine or Data Attribute Adult in the backup slot)
  - Guilmon: Megalo Growmon → Dukemon (X-Antibody) (partner: Vaccine or Data or Free Attribute Perfect in the backup slot)
  - Guilmon: Megalo Growmon (Orange) → Dukemon (partner: Vaccine or Free Attribute Perfect in the backup slot)
  - Guilmon: Megalo Growmon (Orange) → Megidramon (partner: Virus Attribute Perfect in the backup slot)
  - Cause: the Wikimon line says "(with or without …)" because it merges other games (Digimon Story, Pendulum, card games, DWNO), and `build_data.py` treats "with or without" as optional.
- **Omegamon is missing from the card edge lists.** `vb_lines_a.json` has no War Greymon/Metal Garurumon → Omegamon edge. The app data `evolutions.json` has both as Jogress, and `EvolutionEngine.swift:59` locks Omegamon on purpose. On the device this is a cross-card special Jogress: War Greymon from the Agumon DIM with Metal Garurumon from the Gabumon DIM in backup (or the reverse), checked every 3 h, no Adventure clear needed. The source says it is the *only* way to Omegamon on these two cards.
- **Ancient Warriors is incomplete in the app.** It lacks Fladramon, Lighdramon, Sagittarimon, Gold V-dramon and Magnamon, which means 27 card routes. V-mon's two lowest tiers (Fladramon 3T/500VV, fallback Lighdramon) are among them, so in the app a V-mon that misses XV-mon has no Adult to become.
- Wikimon Evolves notes for Growmon→Megalo Growmon and Megalo Growmon→Dukemon describe the **Guilmon GP** card. On EX2 both are stat routes, and the app correctly leaves them unlocked.

## Routes per source species, in the order the device tries them

Jogress first; then stat routes; then fallback. T = trophies, B = battles. Routes the app lacks are marked.

### Agumon: Agumon (Dim Card Set EX: Digimon Adventure:, JP 2021-03-13; Wikimon prose calls it "Agumon EX DIM")

- **Agumon**: Greymon (VV≥1200, T≥5, B≥8) › Algomon (Adult) (VV≥800, T≥5, B≥3) › Orgemon (VV≥500, T≥3) › fallback: Coelamon (trophies<=2 OR vitalValues<=499)
- **Algomon (Adult)**: Jogress: Vaccine or Free Attribute Adult -> Andromon › Jogress: Data Attribute Adult -> Anomalocarimon › Metal Greymon (VV≥3000, T≥12, B≥15, win≥70%) › Mamemon (VV≥2500, T≥10, B≥10, win≥50%) › Metal Tyranomon (VV≥2000, T≥6, B≥10, win≥50%)
- **Andromon**: Jogress: Data or Free Attribute Perfect -> Blitz Greymon › Done Devimon (VV≥7000, T≥20, B≥25, win≥70%) [needs Adventure Stage 15 cleared] › War Greymon (VV≥5000, T≥20, B≥20, win≥70%)
- **Anomalocarimon**: Jogress: Virus Attribute Perfect -> Done Devimon [needs Adventure Stage 15 cleared] › War Greymon (VV≥5000, T≥20, B≥20, win≥70%) › Blitz Greymon (VV≥4500, T≥15, B≥15, win≥70%)
- **Botamon**: Koromon (time only)
- **Coelamon**: Jogress: Vaccine or Free Attribute Adult -> Metal Greymon › Jogress: Virus Attribute Adult -> Metal Tyranomon › Andromon (VV≥3000, T≥12, B≥15, win≥70%) › Anomalocarimon (VV≥2500, T≥10, B≥10, win≥50%) › Neo Devimon (VV≥2000, T≥6, B≥10, win≥50%)
- **Greymon**: Jogress: Data or Free Attribute Adult -> Andromon › Jogress: Virus Attribute Adult -> Neo Devimon › Metal Greymon (VV≥3000, T≥12, B≥15, win≥70%) › Anomalocarimon (VV≥2500, T≥10, B≥10, win≥50%) › Metal Tyranomon (VV≥2000, T≥6, B≥10, win≥50%)
- **Koromon**: Agumon (time only)
- **Mamemon**: Jogress: Vaccine or Free Attribute Perfect -> War Greymon › Done Devimon (VV≥7000, T≥20, B≥25, win≥70%) [needs Adventure Stage 15 cleared] › Blitz Greymon (VV≥4500, T≥15, B≥15, win≥70%)
- **Metal Greymon**: Jogress: Virus Attribute Perfect -> Done Devimon [needs Adventure Stage 15 cleared] › War Greymon (VV≥5000, T≥10, B≥20, win≥70%) › Blitz Greymon (VV≥4500, T≥15, B≥15, win≥70%)
- **Metal Tyranomon**: Jogress: Data Attribute Perfect -> Done Devimon [needs Adventure Stage 15 cleared] › War Greymon (VV≥5000, T≥20, B≥20, win≥70%) › Blitz Greymon (VV≥4500, T≥15, B≥15, win≥70%)
- **Neo Devimon**: Jogress: Vaccine or Free Attribute Perfect -> War Greymon › Done Devimon (VV≥7000, T≥20, B≥25, win≥70%) [needs Adventure Stage 15 cleared] › Blitz Greymon (VV≥4500, T≥15, B≥15, win≥70%)
- **Orgemon**: Jogress: Data Attribute Adult -> Anomalocarimon › Jogress: Vaccine or Free Attribute Adult -> Metal Greymon › Andromon (VV≥3000, T≥12, B≥15, win≥70%) › Mamemon (VV≥2500, T≥10, B≥10, win≥50%) › Neo Devimon (VV≥2000, T≥6, B≥10, win≥50%)
- **War Greymon**: Jogress: Metal Garurumon from the Gabumon DIM -> Omegamon *(not in app)*

### Gabumon: Gabumon (Dim Card Set EX: Digimon Adventure:, JP 2021-03-13; "Gabumon EX DIM")

- **Algomon (Adult)**: Jogress: Vaccine or Free Attribute Adult -> Parrotmon › Jogress: Data Attribute Adult -> Valvemon › Were Garurumon (VV≥3000, T≥12, B≥15, win≥70%) › Big Mamemon (VV≥2500, T≥10, B≥10, win≥50%) › Waru Seadramon (VV≥2000, T≥6, B≥10, win≥50%)
- **Big Mamemon**: Jogress: Vaccine or Free Attribute Perfect -> Metal Garurumon › Nidhoggmon (VV≥7000, T≥20, B≥25, win≥70%) [needs Adventure Stage 15 cleared] › Cres Garurumon (VV≥4500, T≥15, B≥15, win≥70%)
- **Dokugumon**: Jogress: Data Attribute Adult -> Valvemon › Jogress: Vaccine or Free Attribute Adult -> Were Garurumon › Parrotmon (VV≥3000, T≥12, B≥15, win≥70%) › Big Mamemon (VV≥2500, T≥10, B≥10, win≥50%) › Orochimon (VV≥2000, T≥6, B≥10, win≥50%)
- **Gabumon**: Garurumon (VV≥1200, T≥5, B≥8) › Gorimon (VV≥800, T≥5, B≥3) › Dokugumon (VV≥500, T≥3) › fallback: Algomon (Adult) (trophies<=2 OR vitalValues<=499)
- **Garurumon**: Jogress: Virus Attribute Adult -> Orochimon › Jogress: Data or Free Attribute Adult -> Parrotmon › Were Garurumon (VV≥3000, T≥12, B≥15, win≥70%) › Valvemon (VV≥2500, T≥10, B≥10, win≥50%) › Waru Seadramon (VV≥2000, T≥6, B≥10, win≥50%)
- **Gorimon**: Jogress: Virus Attribute Adult -> Waru Seadramon › Jogress: Vaccine or Free Attribute Adult -> Were Garurumon › Parrotmon (VV≥3000, T≥12, B≥15, win≥70%) › Valvemon (VV≥2500, T≥10, B≥10, win≥50%) › Orochimon (VV≥2000, T≥6, B≥10, win≥50%)
- **Orochimon**: Jogress: Vaccine or Free Attribute Perfect -> Metal Garurumon › Nidhoggmon (VV≥7000, T≥20, B≥25, win≥70%) [needs Adventure Stage 15 cleared] › Cres Garurumon (VV≥4500, T≥15, B≥15, win≥70%)
- **Parrotmon**: Jogress: Data or Free Attribute Perfect -> Cres Garurumon › Nidhoggmon (VV≥7000, T≥20, B≥25, win≥70%) [needs Adventure Stage 15 cleared] › Metal Garurumon (VV≥5000, T≥20, B≥20, win≥70%)
- **Punimon**: Tunomon (time only)
- **Tunomon**: Gabumon (time only)
- **Valvemon**: Jogress: Virus Attribute Perfect -> Nidhoggmon [needs Adventure Stage 15 cleared] › Metal Garurumon (VV≥5000, T≥20, B≥20, win≥70%) › Cres Garurumon (VV≥4500, T≥15, B≥15, win≥70%)
- **Waru Seadramon**: Jogress: Data Attribute Perfect -> Nidhoggmon [needs Adventure Stage 15 cleared] › Metal Garurumon (VV≥5000, T≥20, B≥20, win≥70%) › Cres Garurumon (VV≥4500, T≥15, B≥15, win≥70%)
- **Were Garurumon**: Jogress: Virus Attribute Perfect -> Nidhoggmon [needs Adventure Stage 15 cleared] › Metal Garurumon (VV≥5000, T≥20, B≥20, win≥70%) › Cres Garurumon (VV≥4500, T≥15, B≥15, win≥70%)
- **Metal Garurumon**: Jogress: War Greymon from the Agumon DIM -> Omegamon *(not in app)*

### Ancient Warriors: Ancient Warriors (JP 2021-03-13, bundled with Vital Bracelet Digital Monster ver.SPECIAL via Premium Bandai)

- **Aero V-dramon**: Jogress: Virus Attribute Perfect -> Imperialdramon: Fighter Mode [needs Adventure Stage 15 cleared] › Jogress: Data or Free Attribute Perfect -> Magnamon *(not in app)* › Ulforce V-dramon (VV≥5000, T≥20, B≥20, win≥70%) › Imperialdramon: Dragon Mode (VV≥4500, T≥15, B≥15, win≥70%)
- **Chibimon**: V-mon (time only)
- **Chicomon**: Chibimon (time only)
- **Digitamamon**: Jogress: Vaccine or Free Attribute Perfect -> Imperialdramon: Dragon Mode › Jogress: Virus Attribute Perfect -> Imperialdramon: Fighter Mode [needs Adventure Stage 15 cleared] › Ulforce V-dramon (VV≥5000, T≥20, B≥20, win≥70%) › Magnamon (VV≥4500, T≥10, B≥15, win≥50%) *(not in app)*
- **Dinobeemon**: Jogress: Vaccine or Virus Attribute Perfect -> Ulforce V-dramon › Jogress: Data Attribute Perfect -> Magnamon *(not in app)* › Imperialdramon: Fighter Mode (VV≥7000, T≥20, B≥25, win≥70%) [needs Adventure Stage 15 cleared] › Imperialdramon: Dragon Mode (VV≥4500, T≥15, B≥15, win≥70%)
- **Paildramon**: Jogress: Vaccine or Virus Attribute Perfect -> Ulforce V-dramon › Jogress: Data Attribute Perfect -> Magnamon *(not in app)* › Imperialdramon: Fighter Mode (VV≥7000, T≥20, B≥25, win≥70%) [needs Adventure Stage 15 cleared] › Imperialdramon: Dragon Mode (VV≥4500, T≥15, B≥15, win≥70%)
- **V-dramon**: Jogress: Virus Attribute Adult -> Digitamamon › Jogress: Data or Free Attribute Adult -> Dinobeemon › Aero V-dramon (VV≥3000, T≥12, B≥15, win≥70%) › Sagittarimon (VV≥2500, T≥10, B≥10, win≥50%) *(not in app)* › Gold V-dramon (VV≥2000, T≥6, B≥10, win≥50%) *(not in app)*
- **V-mon**: V-dramon (VV≥1200, T≥8, B≥8) › XV-mon (VV≥800, T≥5, B≥3) › Fladramon (VV≥500, T≥3) *(not in app)* › fallback: Lighdramon (trophies<=2 OR vitalValues<=499) *(not in app)*
- **XV-mon**: Jogress: Vaccine or Data Attribute Adult -> Aero V-dramon › Jogress: Virus Attribute Adult -> Digitamamon › Paildramon (VV≥3000, T≥12, B≥15, win≥70%) › Dinobeemon (VV≥2500, T≥10, B≥10, win≥50%) › Gold V-dramon (VV≥2000, T≥6, B≥10, win≥50%) *(not in app)*
- **Fladramon**: Jogress: Virus Attribute Adult -> Gold V-dramon *(not in app)* › Jogress: Vaccine or Data Attribute Adult -> Paildramon *(not in app)* › Aero V-dramon (VV≥3000, T≥12, B≥15, win≥70%) *(not in app)* › Sagittarimon (VV≥2500, T≥10, B≥10, win≥50%) *(not in app)* › Digitamamon (VV≥2000, T≥6, B≥10, win≥50%) *(not in app)*
- **Gold V-dramon**: Jogress: Data Attribute Perfect -> Imperialdramon: Dragon Mode *(not in app)* › Jogress: Virus or Free Attribute Perfect -> Ulforce V-dramon *(not in app)* › Imperialdramon: Fighter Mode (VV≥7000, T≥20, B≥25, win≥70%) [needs Adventure Stage 15 cleared] *(not in app)* › Magnamon (VV≥4500, T≥10, B≥15, win≥50%) *(not in app)*
- **Lighdramon**: Jogress: Vaccine or Data Attribute Adult -> Aero V-dramon *(not in app)* › Jogress: Virus Attribute Adult -> Sagittarimon *(not in app)* › Paildramon (VV≥3000, T≥12, B≥15, win≥70%) *(not in app)* › Dinobeemon (VV≥2500, T≥10, B≥10, win≥50%) *(not in app)* › Digitamamon (VV≥2000, T≥6, B≥10, win≥50%) *(not in app)*
- **Sagittarimon**: Jogress: Vaccine or Data Attribute Perfect -> Imperialdramon: Dragon Mode *(not in app)* › Jogress: Virus Attribute Perfect -> Imperialdramon: Fighter Mode [needs Adventure Stage 15 cleared] *(not in app)* › Ulforce V-dramon (VV≥5000, T≥20, B≥20, win≥70%) *(not in app)* › Magnamon (VV≥4500, T≥10, B≥15, win≥50%) *(not in app)*

### Guilmon: Guilmon (Dim Card EX2: Digimon Tamers, JP 2022-02-19; 17 species; not the 8-species Dim Card GP Guilmon)

- **Devidramon**: Jogress: Free Attribute Adult -> Megalo Growmon › Jogress: Vaccine Attribute Adult -> Megalo Growmon (Orange) › Jogress: Data Attribute Adult -> Mihiramon › Vajramon (VV≥3000, T≥12, B≥15, win≥70%) › Majiramon (VV≥2500, T≥10, B≥10, win≥50%) › Sandiramon (VV≥2000, T≥8, B≥10, win≥50%)
- **Gigimon**: Guilmon (time only)
- **Growmon**: Jogress: Data Attribute Adult -> Majiramon › Jogress: Free Attribute Adult -> Mihiramon › Jogress: Vaccine Attribute Adult -> Vajramon › Megalo Growmon (VV≥3000, T≥12, B≥15, win≥70%) › Megalo Growmon (Orange) (VV≥2500, T≥10, B≥10, win≥50%) › Sandiramon (VV≥2000, T≥8, B≥10, win≥50%)
- **Growmon (Orange)**: Jogress: Vaccine Attribute Adult -> Majiramon › Jogress: Virus Attribute Adult -> Sandiramon › Jogress: Free Attribute Adult -> Vajramon › Megalo Growmon (VV≥3000, T≥12, B≥15, win≥70%) › Megalo Growmon (Orange) (VV≥2500, T≥10, B≥10, win≥50%) › Mihiramon (VV≥2000, T≥8, B≥10, win≥50%)
- **Guilmon**: Growmon (VV≥1300, T≥10, B≥8) › Growmon (Orange) (VV≥900, T≥8, B≥5) › Siesamon (VV≥600, T≥5, B≥3) › fallback: Devidramon (trophies<=4 OR vitalValues<=599 OR battles<=2)
- **Jyarimon**: Gigimon (time only)
- **Majiramon**: Jogress: Vaccine or Free Attribute Perfect -> Dukemon: Crimson Mode [needs Adventure Stage 15 cleared] › Jogress: Virus Attribute Perfect -> Dukemon (X-Antibody) › Megidramon (VV≥4500, T≥15, B≥15, win≥70%) › Dukemon (VV≥4500, T≥10, B≥15, win≥50%)
- **Megalo Growmon**: Jogress: Vaccine or Data or Free Attribute Perfect -> Dukemon (X-Antibody) › Dukemon: Crimson Mode (VV≥7000, T≥20, B≥25, win≥70%) [needs Adventure Stage 15 cleared] › Megidramon (VV≥4500, T≥15, B≥15, win≥70%) › Dukemon (VV≥4500, T≥10, B≥15, win≥50%)
- **Megalo Growmon (Orange)**: Jogress: Vaccine or Free Attribute Perfect -> Dukemon › Jogress: Virus Attribute Perfect -> Megidramon › Dukemon: Crimson Mode (VV≥7000, T≥20, B≥25, win≥70%) [needs Adventure Stage 15 cleared] › Dukemon (X-Antibody) (VV≥5000, T≥20, B≥20, win≥70%)
- **Mihiramon**: Jogress: Virus Attribute Perfect -> Dukemon: Crimson Mode [needs Adventure Stage 15 cleared] › Jogress: Vaccine or Free Attribute Perfect -> Megidramon › Dukemon (X-Antibody) (VV≥5000, T≥20, B≥20, win≥70%) › Dukemon (VV≥4500, T≥10, B≥15, win≥50%)
- **Sandiramon**: Jogress: Data Attribute Perfect -> Dukemon › Jogress: Vaccine or Free Attribute Perfect -> Megidramon › Dukemon: Crimson Mode (VV≥7000, T≥20, B≥25, win≥70%) [needs Adventure Stage 15 cleared] › Dukemon (X-Antibody) (VV≥5000, T≥20, B≥20, win≥70%)
- **Siesamon**: Jogress: Free Attribute Adult -> Megalo Growmon › Jogress: Data Attribute Adult -> Megalo Growmon (Orange) › Jogress: Virus Attribute Adult -> Sandiramon › Vajramon (VV≥3000, T≥12, B≥15, win≥70%) › Majiramon (VV≥2500, T≥10, B≥10, win≥50%) › Mihiramon (VV≥2000, T≥8, B≥10, win≥50%)
- **Vajramon**: Jogress: Virus Attribute Perfect -> Dukemon: Crimson Mode [needs Adventure Stage 15 cleared] › Jogress: Data or Free Attribute Perfect -> Dukemon (X-Antibody) › Megidramon (VV≥4500, T≥15, B≥15, win≥70%) › Dukemon (VV≥4500, T≥10, B≥15, win≥50%)

## Sources, and where they disagree

- **Wikimon, local cache** (`tools/digimon/.cache/pages`): VB prose exists only for Coelamon, Done Devimon, Blitz Greymon (Agumon EX) and Omegamon (Agumon EX + Gabumon EX); it agrees with Humulos. The Evolves-list notes give Jogress partner attributes. The other 57 unique species on these cards have no VB conditions (Nidhoggmon has one sentence with no condition).
- **Wikimon, web:** [Vital Bracelet Digital Monster](https://wikimon.net/Vital_Bracelet_Digital_Monster) (time table, Jogress priority, missions), [Memory Cards](https://wikimon.net/Vital_Bracelet_Series/Memory_Cards) (card identity), [Attributes and Levels](https://wikimon.net/Digital_Monster_Vital_Bracelet_Attributes_and_Levels).
- **Humulos (primary per-edge source for all 4 cards):** [EX charts](https://humulos.com/digimon/vbdm/ex/), [VBDM charts + FAQ](https://humulos.com/digimon/vbdm/), [manual](https://humulos.com/digimon/vbdm/manual), [differences](https://humulos.com/digimon/vbdm/differences). I read the per-species detail endpoint `https://humulos.com/digimon/php/details.php?digimon=<id>&device=13`, which groups routes by DIM.
- **Gamerch バイタルブレス攻略 wiki (JP, independent):** [Agumon](https://gamerch.com/digimonvb/entry/237926), [Gabumon](https://gamerch.com/digimonvb/entry/237545), [Ancient Warriors](https://gamerch.com/digimonvb/entry/237425), [Jogress results](https://gamerch.com/digimonvb/entry/241339), [rules](https://gamerch.com/digimonvb/entry/238937). There is no Guilmon EX2 page.
- **JP community sheet "バイタルブレス各種一覧表"** ([htmlview](https://docs.google.com/spreadsheets/d/1xfpRbL86lKuFOex1JiUbv461BZqOh-ewx6L333pnFp0/htmlview); CSV export returns 401): per-target requirements for the Agumon EX, Gabumon EX and Ancient Warriors cards.
- **Disagreements:**
  - Sagittarimon→Magnamon win ratio: Gamerch 70% vs Humulos and the sheet 50%. Likely a Gamerch typo; neither species is in the app.
  - Wikimon "VV exceeding N" vs "N+"/"N以上" elsewhere: encoded as ≥N.
  - Metal Greymon→War Greymon at 10T is confirmed by three sources, so it is not a typo.
- No Bandai primary source with per-route numbers was found.

## Open questions

- The tie-break among several met stat routes is the DIM data order. "Highest VV, then win ratio" is an observed pattern, not a documented rule.
- Stage-15-gated Jogress (e.g. Anomalocarimon + Virus Perfect → Done Devimon) before Stage 15 is cleared: no source says what happens. Most likely the Jogress is skipped and the stat routes apply, but this is unverified.
- Guilmon EX2 stat thresholds rest on Humulos alone.
