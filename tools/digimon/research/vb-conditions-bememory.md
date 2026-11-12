# Vital Bracelet BE evolution conditions: Holy Wings and Forest Guardians

Data: `vb_conditions_b.json`, next to this file. The numbers come from humulos.com, the only source that gives them per edge. Wikimon confirms the routes and Jogress partners but gives no numbers.

## How BE evolution works

- Evolution is timer-driven: when the current stage timer ends the device checks the requirements of every unlocked next form; if one is met it evolves, otherwise the timer restarts and is re-checked after the same interval (humulos manual).
- Stage timers on BE Memories: Baby I 1h, Baby II 3h, Child 12h (16h for original Dim cards), Adult 24h, Perfect 24h, Ultimate->Super Ultimate via Jogress 3h (humulos FAQ). Sleep counts toward the timer; backup and power-off do not.
- Requirement types on BE Memories: PP (renamed Trophies; earned only by Squat training: Great=2, Good=1), Vital Values (heart rate + steps; 4 VV per 50 miles, x2 when Happy, x0.5 when Upset/injured, +/- from battle wins/losses, -20 per 5 min unworn while awake), Battles (NFC-triggered or Adventure boss battles; app battles do not count), Win Ratio (%), Adventure Mode stage cleared (one-time unlock stored per card), Jogress partner (specific named Digimon from a specific card in backup set as Support).
- Only listed stats matter; N/A means no minimum. A form whose four stats are all N/A is the default/failure evolution, which is expressed in the detail popup as Choose one of ranges (e.g. 0-2 PP OR 0-499 VV) = below the minimum of the other options.
- If several options are met: you usually get the option with the highest Vital Value requirement, then highest Win Ratio; the true rule is the order in the card code (humulos FAQ). Ties on VV and win ratio are not resolved by any source.
- Stats reset: PP, Battles and Win Ratio reset after every evolution; Vital Values reset after every evolution except I->II and II->III; BP/HP/AP training gains carry over. Training stats can only be gained during a 100-hour Limit per Digimon (PP too), after which unmet PP requirements can never be met.
- Training (Squat=PP, Crunch=HP, Punch=AP, Dash=BP) raises battle stats only on BE Memories; with original Dim cards any training only gives PP. Training/Traits/personality are not evolution requirements on these cards (each Digimon has an Activity Type that only controls its battle Super Hit).
- Adventure Mode: 12 stages per BE Memory; stages walk a step count then fight a boss. On these two cards Stage 2, 5, 8, 11, 12 clears unlock specific forms (the device hides locked forms).
- Death: 4 injuries in one day or 24h unworn. Injury = losing a battle while Upset.

### How BE differs from the original Vital Bracelet

- Trophies (earned by completing missions, max 4 trainings/hard missions per day) became PP (Squat training, no daily limit; 100h Limit).
- Training raises BP/HP/AP only on BE (original devices: training gives no stat growth).
- Original Dim cards allowed attribute-based Jogress at Stage IV/V (any different-attribute Digimon in backup); BE only supports Jogress with a specific named Digimon from a specific card.
- Original Dims have 1 Adventure unlock (Area 15 of 15); BE Memories have multiple unlocks across 12 stages.
- Evolution timer runs while asleep on BE (not on the original VB Digital Monster); Child timer 12h on BE Memories vs 16h on original Dims.
- Original VB: all stats reset on evolution (except I->II, II->III); BE keeps BP/HP/AP gains.
- Activity Type: on earlier Vital Bracelets it "had a few other purposes" (Digimon preferred specific exercise types); on BE all Digimon react to exercise the same way and Activity Type only sets the Super Hit turn (humulos manual).
- BE has no device PvP (no VS Memory); backup Digimon from the same franchise can assist in NFC battles; up to 23 Digimon per card vs 17.

### Where the sources disagree

- Wikimon (Vital_Bracelet_BE) says "Completing Stages 2, 3, 6, 9, 11 and 12 Unlock more Digimon evolutions"; humulos lists the unlock stages for these two cards as 2, 5, 8, 11, 12. Wikimon's sentence is generic (not card-specific); humulos is per card.
- humulos chart graphic draws Hououmon only from Garudamon, but its detail popups (and Wikimon) also list Arkhai Angemon->Hououmon and Jazarichmon->Hououmon with the same requirement; the chart image omits those connector lines, the data does not.
- humulos manual table says Ultimate evolves "3 Hours via Jogress, otherwise 24 Hours", while the same text says Jogress "takes the same amount of time as normal evolutions do"; the FAQ table says 3 hours for Stage VI.
- humulos BE FAQ says a Digimon is guaranteed to reach Stage III; Child->Adult has a default form only for some Child lines on these cards (Luxmon/Falcomon->Xiquemon, Tentomon/Funbeemon->Kuwagamon). Piyomon, Jazamon, Lalamon, Morphomon have no default form, so they can stall if no requirement is met.

## BEMemory Holy Wings Dim (`piyomon`)

Coverage: **35/35** app edges have a stated condition, and 0 are unknown. The card also has 6 edges that are not in the app's edge list. They are marked with an asterisk below.

| From | To | Requirement (humulos) | Timer |
|---|---|---|---|
| Nyokimon | Pyocomon | No stat requirements (time-only evolution) | 1h |
| Pyocomon | Falcomon (2006 Anime Version) | Default (fallback): 0-2 PP OR 0-499 VV | 3h |
| Pyocomon | Jazamon | Adventure Stage 2 cleared, 5+ PP, 1,000+ VV | 3h |
| Pyocomon | Luxmon | 5+ PP, 500+ VV | 3h |
| Pyocomon | Piyomon | 3+ PP, 500+ VV | 3h |
| Falcomon (2006 Anime Version) | Peckmon | 5+ PP, 1,000+ VV, 3+ Battles | 12h |
| Falcomon (2006 Anime Version) | Xiquemon | Default (fallback): 0-4 PP OR 0-999 VV OR 0-2 Battles | 12h |
| Falcomon (2006) | Thunderbirmon * | Adventure Stage 5 cleared, 12+ PP, 1,500+ VV, 10+ Battles | 12h |
| Jazamon | Birdramon | 8+ PP, 1,000+ VV, 5+ Battles | 12h |
| Jazamon | Thunderbirmon * | Adventure Stage 5 cleared, 12+ PP, 1,500+ VV, 10+ Battles | 12h |
| Luxmon | Birdramon | 8+ PP, 1,000+ VV, 5+ Battles | 12h |
| Luxmon | Pidmon | 10+ PP, 1,000+ VV, 8+ Battles | 12h |
| Luxmon | Xiquemon | Default (fallback): 0-7 PP OR 0-999 VV OR 0-4 Battles | 12h |
| Piyomon | Birdramon | 8+ PP, 1,000+ VV, 5+ Battles | 12h |
| Piyomon | Peckmon | 5+ PP, 1,000+ VV, 3+ Battles | 12h |
| Piyomon | Pidmon | 10+ PP, 1,000+ VV, 8+ Battles | 12h |
| Birdramon | Arkhai Angemon | 12+ PP, 2,500+ VV, 12+ Battles, 50%+ Win | 24h |
| Birdramon | Garudamon | 10+ PP, 2,500+ VV, 10+ Battles, 50%+ Win | 24h |
| Peckmon | Jazarichmon | Adventure Stage 8 cleared, 12+ PP, 3,000+ VV, 15+ Battles, 60%+ Win | 24h |
| Peckmon | Yatagaramon (2006 Anime Version) | 10+ PP, 2,500+ VV, 10+ Battles, 50%+ Win | 24h |
| Pidmon | Arkhai Angemon | 12+ PP, 2,500+ VV, 12+ Battles, 50%+ Win | 24h |
| Pidmon | Garudamon | 10+ PP, 2,500+ VV, 10+ Battles, 50%+ Win | 24h |
| Pidmon | Huankunmon | 8+ PP, 2,000+ VV, 10+ Battles, 50%+ Win | 24h |
| Thunderbirmon | Garudamon * | 10+ PP, 2,500+ VV, 10+ Battles, 50%+ Win | 24h |
| Thunderbirmon | Jazarichmon * | Adventure Stage 8 cleared, 12+ PP, 3,000+ VV, 15+ Battles, 60%+ Win | 24h |
| Xiquemon | Huankunmon | 8+ PP, 2,000+ VV, 10+ Battles, 50%+ Win | 24h |
| Xiquemon | Yatagaramon (2006 Anime Version) | 10+ PP, 2,500+ VV, 10+ Battles, 50%+ Win | 24h |
| Arkhai Angemon | Dominimon | 30+ PP, 3,500+ VV, 20+ Battles, 60%+ Win | 24h |
| Arkhai Angemon | Hououmon | 30+ PP, 3,000+ VV, 15+ Battles, 60%+ Win | 24h |
| Arkhai Angemon | Xiangpengmon | 20+ PP, 2,500+ VV, 15+ Battles, 50%+ Win | 24h |
| Garudamon | Dominimon | 30+ PP, 3,500+ VV, 20+ Battles, 60%+ Win | 24h |
| Garudamon | Hououmon | 30+ PP, 3,000+ VV, 15+ Battles, 60%+ Win | 24h |
| Huankunmon | Ravmon | 25+ PP, 3,000+ VV, 15+ Battles, 50%+ Win | 24h |
| Huankunmon | Xiangpengmon | 20+ PP, 2,500+ VV, 15+ Battles, 50%+ Win | 24h |
| Jazarichmon | Hououmon | 30+ PP, 3,000+ VV, 15+ Battles, 60%+ Win | 24h |
| Jazarichmon | Metallicdramon | Adventure Stage 12 cleared, 35+ PP, 3,500+ VV, 20+ Battles, 60%+ Win | 24h |
| Yatagaramon (2006 Anime Version) | Metallicdramon | Adventure Stage 12 cleared, 30+ PP, 3,500+ VV, 20+ Battles, 60%+ Win | 24h |
| Yatagaramon (2006 Anime Version) | Ravmon | 25+ PP, 3,000+ VV, 15+ Battles, 50%+ Win | 24h |
| Yatagaramon (2006 Anime Version) | Ravmon: Burst Mode | Adventure Stage 11 cleared, 35+ PP, 3,500+ VV, 20+ Battles, 70%+ Win | 24h |
| Dominimon | Shakamon * | Jogress with Xiangpengmon in backup (Support) | 3h |
| Xiangpengmon | Shakamon * | Jogress with Dominimon in backup (Support) | 3h |

Options with the same VV and win-ratio requirement, so no source says which one wins:
- from `pyocomon`: piyomon = luxmon
- from `piyomon`: birdramon = pidmon; pidmon = peckmon
- from `luxmon`: birdramon = pidmon
- from `birdramon`: garudamon = arkhaiangemon
- from `pidmon`: garudamon = arkhaiangemon

## BEMemory Forest Guardians Dim (`tentomon`)

Coverage: **40/40** app edges have a stated condition, and 0 are unknown. The card also has 2 edges that are not in the app's edge list. They are marked with an asterisk below.

| From | To | Requirement (humulos) | Timer |
|---|---|---|---|
| Bubbmon | Mochimon | No stat requirements (time-only evolution) | 1h |
| Mochimon | Funbeemon | Default (fallback): 0-2 PP OR 0-499 VV | 3h |
| Mochimon | Lalamon | 5+ PP, 500+ VV | 3h |
| Mochimon | Morphomon | Adventure Stage 2 cleared, 5+ PP, 1,000+ VV | 3h |
| Mochimon | Tentomon | 3+ PP, 500+ VV | 3h |
| Funbeemon | Kabuterimon | 8+ PP, 1,000+ VV, 5+ Battles | 12h |
| Funbeemon | Kuwagamon | Default (fallback): 0-4 PP OR 0-999 VV OR 0-2 Battles | 12h |
| Funbeemon | Waspmon | 5+ PP, 1,000+ VV, 3+ Battles | 12h |
| Lalamon | Hudiemon | Adventure Stage 5 cleared, 12+ PP, 1,500+ VV, 10+ Battles | 12h |
| Lalamon | Sunflowmon | 10+ PP, 1,000+ VV, 8+ Battles | 12h |
| Lalamon | Waspmon | 5+ PP, 1,000+ VV, 3+ Battles | 12h |
| Morphomon | Hudiemon | Adventure Stage 5 cleared, 12+ PP, 1,500+ VV, 10+ Battles | 12h |
| Morphomon | Waspmon | 5+ PP, 1,000+ VV, 3+ Battles | 12h |
| Tentomon | Kabuterimon | 8+ PP, 1,000+ VV, 5+ Battles | 12h |
| Tentomon | Kuwagamon | Default (fallback): 0-7 PP OR 0-999 VV OR 0-4 Battles | 12h |
| Tentomon | Sunflowmon | 10+ PP, 1,000+ VV, 8+ Battles | 12h |
| Hudiemon | Cannonbeemon | 10+ PP, 2,000+ VV, 10+ Battles, 50%+ Win | 24h |
| Hudiemon | Eosmon (Perfect) | Adventure Stage 8 cleared, 12+ PP, 3,000+ VV, 15+ Battles, 60%+ Win | 24h |
| Kabuterimon | Atlur Kabuterimon (Red) | 10+ PP, 2,500+ VV, 12+ Battles, 50%+ Win | 24h |
| Kabuterimon | Lilamon | 12+ PP, 2,500+ VV, 15+ Battles, 50%+ Win | 24h |
| Kuwagamon | Cannonbeemon | 10+ PP, 2,000+ VV, 10+ Battles, 50%+ Win | 24h |
| Kuwagamon | Okuwamon | 8+ PP, 2,000+ VV, 10+ Battles, 40%+ Win | 24h |
| Sunflowmon | Cannonbeemon | 10+ PP, 2,000+ VV, 10+ Battles, 50%+ Win | 24h |
| Sunflowmon | Eosmon (Perfect) | Adventure Stage 8 cleared, 12+ PP, 3,000+ VV, 15+ Battles, 60%+ Win | 24h |
| Sunflowmon | Lilamon | 12+ PP, 2,500+ VV, 15+ Battles, 50%+ Win | 24h |
| Waspmon | Atlur Kabuterimon (Red) | 12+ PP, 2,500+ VV, 12+ Battles, 50%+ Win | 24h |
| Waspmon | Cannonbeemon | 10+ PP, 2,000+ VV, 10+ Battles, 50%+ Win | 24h |
| Waspmon | Okuwamon | 8+ PP, 2,000+ VV, 10+ Battles, 40%+ Win | 24h |
| Atlur Kabuterimon (Red) | Herakle Kabuterimon | 30+ PP, 3,000+ VV, 15+ Battles, 60%+ Win | 24h |
| Atlur Kabuterimon (Red) | Rosemon | 30+ PP, 3,500+ VV, 20+ Battles, 60%+ Win | 24h |
| Cannonbeemon | Gran Kuwagamon | 20+ PP, 2,500+ VV, 15+ Battles, 50%+ Win | 24h |
| Cannonbeemon | Herakle Kabuterimon | 30+ PP, 3,000+ VV, 15+ Battles, 60%+ Win | 24h |
| Cannonbeemon | Tiger Vespamon | 25+ PP, 3,000+ VV, 15+ Battles, 50%+ Win | 24h |
| Eosmon (Perfect) | Bancho Lilimon | Adventure Stage 12 cleared, 35+ PP, 3,500+ VV, 20+ Battles, 60%+ Win | 24h |
| Eosmon (Perfect) | Tiger Vespamon | 25+ PP, 3,000+ VV, 15+ Battles, 50%+ Win | 24h |
| Lilamon | Bancho Lilimon | Adventure Stage 12 cleared, 30+ PP, 3,500+ VV, 20+ Battles, 60%+ Win | 24h |
| Lilamon | Rosemon | 25+ PP, 3,500+ VV, 20+ Battles, 60%+ Win | 24h |
| Lilamon | Rosemon: Burst Mode | Adventure Stage 11 cleared, 35+ PP, 3,500+ VV, 20+ Battles, 70%+ Win | 24h |
| Okuwamon | Gran Kuwagamon | 20+ PP, 2,500+ VV, 15+ Battles, 50%+ Win | 24h |
| Okuwamon | Tiger Vespamon | 25+ PP, 3,000+ VV, 15+ Battles, 50%+ Win | 24h |
| Gran Kuwagamon | Tyrant Kabuterimon * | Jogress with Herakle Kabuterimon in backup (Support) | 3h |
| Herakle Kabuterimon | Tyrant Kabuterimon * | Jogress with Gran Kuwagamon in backup (Support) | 3h |

Options with the same VV and win-ratio requirement, so no source says which one wins:
- from `mochimon`: tentomon = lalamon
- from `tentomon`: kabuterimon = sunflowmon
- from `funbeemon`: kabuterimon = waspmon
- from `lalamon`: sunflowmon = waspmon
- from `kabuterimon`: atlurkabuterimonred = lilamon
- from `lilamon`: rosemon = bancholilimon

## Sources

- humulos.com VB BE Evolution Guide (Special Selection page: Holy Wing / Forest Guardian charts): https://humulos.com/digimon/vbbe/special/. Used for: per-edge requirements (chart values) + legend + FAQ (priority, resets, timers)
- humulos.com detail popups: https://humulos.com/digimon/php/details.php?digimon=<id>&device=14. Used for: complete Evolves From/To lists with requirement text per edge (includes edges the chart graphic does not draw)
- humulos.com VB BE manual: https://humulos.com/digimon/vbbe/manual/. Used for: timers, VV earning, PP/training, 100h limit, Jogress mechanics, adventure, death
- humulos.com Vital Series differences table: https://humulos.com/digimon/vbdm/differences. Used for: BE vs original VB
- humulos.com original VB Evolution Guide FAQ/legend: https://humulos.com/digimon/vbdm/. Used for: original VB trophies, 16h child timer, attribute Jogress, Area 15 unlock
- Wikimon Vital Bracelet BE: https://wikimon.net/Vital_Bracelet_BE. Used for: general description (training types, adventure, evolution requirements not standardized, time standardized)
- Wikimon Vital Bracelet Series Memory Cards (local cache): tools/digimon/.cache/pages/vitalbraceletseriesmemorycards.wiki. Used for: card rosters, adventure unlockables chosen by Evolution Vote vol.2
- Wikimon species pages (local cache, 923 pages): tools/digimon/.cache/pages/<key>.wiki. Used for: route corroboration only; every "Vital Bracelet BE" section in the relevant pages is empty, no conditions

Tried, but gave no conditions:
- Local Wikimon cache: all 50 relevant species pages have empty "==={{hdr|Vital Bracelet BE}}===" sections.
- Wikimon has no separate BEMemory card pages (API search for Holy Wings / Forest Guardians returns nothing).
- digimon.fandom.com/wiki/Holy_Wings returned HTTP 402 to automated fetch (not retried).
- Bandai official English VB BE pages (toy.bandai.co.jp/series/en_vitalbraceletbe/..., toy.bandai.co.jp/special/vb/digitalmonster) returned 404; no official per-card requirement material found.
- Web searches (EN/JP) found no independent per-card requirement chart besides humulos.
