# Project status

**Version 0.51.0** · 2026-10-06 · WoW Forever beta (interface 16001)

Status key: ✅ verified in game · 🧪 built, needs in-game testing · ⏳ not started

## Built

| # | Area | State | Version |
|---|---|---|---|
| 1 | Foundation: saved data, window, side tabs, settings | ✅ | 0.1.1 |
| 3 | Bestiary: creatures, research tiers, abilities, loot, spots, tooltip line | ✅ (core) / 🧪 (later additions) | 0.2.1 → 0.12 |
| 4 | Items | 🧪 | 0.4.0 |
| 5 | Merchants (stock, prices, portraits, map) | 🧪 | 0.4.0 |
| 6 | Quests | 🧪 | 0.5.0 |
| 7 | Zones and exploration (Places, in-page map) | 🧪 | 0.6.0 |
| 8 | Dungeons and raids | 🧪 | 0.9.0 |
| 9 | Trainers: spells and recipes | 🧪 | 0.7.0 |
| 10 | Townsfolk page and flight paths | 🧪 | 0.13.0 |
| 11 | Hidden databases and build tools (creatures, items, quests, dungeons, townsfolk, QoL data) | 🧪 | 0.3.0 → |
| 12 | Journal overview, day timeline and filters, milestones, account / character view | 🧪 | 0.14.0 |
| 13 | Gathering and fishing (nodes, sightings, research tiers, quest objects filtered) | 🧪 | 0.14.0 → 0.15.1 |
| 23 | Quality-of-life helpers from Plus Everything and the settings window | 🧪 | 0.10.0 |
| 24 | "My Characters" look across the Almanac | 🧪 | 0.10.1 |
| 25 | Townsfolk on the world map | 🧪 | 0.11.0 |
| 26 | Toast tiers (Common → Legendary, batching, minimum tier and sound settings) | 🧪 | 0.15.0 |
| 27 | Gathering nodes on the world map and minimap | ✅ (0.17.6 fix) | 0.16.0 → 0.17.6 |
| 28 | Bug check and polish pass (22 fixes, loot-card slots, coin art) | 🧪 | 0.16.1 |
| 29 | Spell Ranker (spellbook button, checks on open, auto-replace on training) | 🧪 | 0.17.0 |
| 30 | Gathering toggle button on the minimap rim | 🧪 | 0.17.1 → 0.17.2 |
| 32 | Ctrl-click items to try them on in the dressing room, everywhere | 🧪 | 0.17.3 |
| 37 | My Characters merged into the Characters page (tabs, name plate, list) | 🧪 | 0.18.0 |
| 33 | My Characters profession bars in the Skills window's blue style | 🧪 | 0.17.4 |
| WG | Wild Gambit card game: practice (Easy/Normal/Hard), player matches, class spells, hidden card, guided tutorial, holiday boards, header nameplates | 🧪 | → 0.49.0 |

## Not started

| # | Area |
|---|---|
| 0 | Combat log test |
| 2 / 2c | Discovery recorder and unlock rules (partly covered by the Bestiary's tiers) |
| 2b | Combat Journal companion (proposed) |
| 14 | Lore and books (the Lore tab returns with it) |
| 15 | Rares: sightings, respawn windows, alerts |
| 16 | Factions and standing history |
| 17 | Places and services: inns, hearthstones, graveyards, boats and zeppelins |
| 18 | Character stories: levels, first visits, deaths |
| 19 | More on items: sets, suffixes, containers, crafts |
| 20 | World events |
| 21 | Data plumbing: Forever cache overlay, saved-data caps and migrations, localization |
| 34 | Travels: your trail drawn on the map over time (planned; draw test passed: lines and dots both work) |
| 60 | Talent Planner (from Plus Everything, trees read from the game) | built, needs testing | 0.21.0 |
| 31 | Rivals: PvP encounters, wins and deaths, labels instead of tiers (planned, parked) |

## Needs checking in game first

- **Art and layout:**
  - Item cards on dark slots: the loot-window card may look squashed at slot height.
  - Coin atlases: fixed at 14 px.
  - Journal painted background: brightness.
  - Small loot-toast frame below Rare: whether the client has it.
- **Positions:**
  - Minimap pin scale: the standard yards per zoom level.
  - Flight paths you aren't standing at: converted from the flight map.
  - Gathering minimap button: default spot (55° clockwise of the Almanac button; `/aa nodes button` puts it back) and whether it clashes with other minimap buttons.
- **Spell Ranker:**
  - Button placement in this client's spellbook.
  - Auto-replace with `PickupSpell` / `PlaceAction` out of combat.
- **Talent Planner (0.21.0):** Planner tab on the Talents window; placements, arrows, tooltips, Stage + Apply.
- **Skinning by item (0.19.5):** list of leathers / hides, item page with Came from and Where, Show on map kill spots.
- **Quest reward coin (0.18.4):** gold coin on the best-selling reward choice at turn-in; position on the icon.
- **Dark panels (0.18.3):** the recipe list background shows in plain dark panels (list panes, detail bodies without a painting).
- **Characters page (0.18.0):** list rows, name plate fit (chips in two rows, XP bar), tab art and icons, each tab's contents at the narrower width (bag rows, paper doll, profession cards), search, right-click hide / remove.
- **No more "blocked SetPassThroughButtons" in combat** (0.17.7), with the world map open or after opening it.
- **Townsfolk pins on zone maps** after the 0.17.6 layer fix (gathering pins confirmed).
- **My Characters professions:** blue rank bars built from `common-stat-bar-BG` cut into three pieces (10 px caps guessed) - check the corners aren't stretched or clipped.
- **Dressing room:**
  - Ctrl-click on item slots, the Items list and icon, and Journal item entries opens the dressing room; the magnifier shows while Ctrl is held over wearables.
- **Gathering:**
  - Sightings depend on soft-interact targeting, which the gathering highlight turns on.
  - Skill is not recorded when the Professions heading is folded.

- **Wild Gambit shuffle button (goblin dealer, `Dealer_Shuffle.tga`; needs a full game restart):** on the pick screen: position bottom right over Begin on its centre line (and its clearance from the last card and the coins); the red Back arrow in the top left corner (which art the client used - the back-arrow atlas or the spellbook page arrow - that it reads as a red arrow, sits on the board's corner and goes back to the opponent screen; the first request said top right, the circle showed top left - say if it should be the other corner); the Your spell card bottom left and its label; "Choose a card" and "Choose your class" headings (lettering, rules and diamonds; the class heading centred over the class rings; the long online messages still fit; lobby "Who will you play?"), the wooden caption plank fits and reads well, "Dealing..." while shuffling, the pick cards now closer together (top-left corner less busy, the spell card on the right still clear), the "Deal a new hand" plaque fits the ring and doesn't cover the first card, ring edge is clean (no dark fringe), hover glow, press dip, rock and pulse while dealing, tooltip; the corner icon in its gold elite frame (size, the dark socket fully hiding the old portrait and its ring, ring and icon centred on each other, nothing cut off at the screen's corner); "Let fate decide" centred, also with the longer "Fate decides!" words; the "Your spell" card sits wholly on the felt and enlarges on hover (fits the felt at the bottom right, the original comes back on leaving, the tooltip sits beside it, still right while Fate has the choice); the goblin's three voice lines play (file IDs 550816 / 550811 / 550810 - confirm they are the right ones and audible, volume against the card sounds, no repeat twice running, silent with the sound setting off).
- **Wild Gambit card scenes:** School of Fish and the Saltspittle murlocs now sit on the underwater painting (Puddlejumper, Warrior, Oracle, Muckdweller); other aquatic creatures (sharks, turtles, jellyfish, other murloc tribes) should too. Report any water creature still on a land scene.
- **Wild Gambit (0.46-0.49), from the latest screenshots:**
  - Header nameplates came out short and the score coin didn't show (0.48.0): make the plates taller, let the name run to the vs, score on the coin.
  - Holiday boards (0.49.0): the slots sit inside each board's stone frame (inner edges measured from the art).
  - Tutorial (0.47.0): the coach note over the bottom row, the gold glow following the cards, every step reachable.
  - Hand sizing (0.46.9): six cards at about 0.69 keep their spikes clear; growth as cards leave.
  - Stealth look: smoke layers rise, badge at the frame's left edge; the zoomed hidden card keeps it.
  - "Blocked from an action" popup (SpellStopCasting on Escape / logout): fixed in 0.49.1 (StaticPopupDialogs was being reassigned). Confirm it no longer appears; db.diag keeps the latest 30 blocks.
- **Open:** GitHub push of the local commits; Tutor portrait art (a dice icon now); Logo_MurlocTacToe / Logo_GemMatch art for the flight prompt.

## Housekeeping

- `dev/AlmanacProbe` can be removed once nothing needs it.
- The detailed plan, decisions and per-version history live in `docs/TASKS.md`.
