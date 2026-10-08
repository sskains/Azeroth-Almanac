# Issues to create on GitHub

One-time setup list: create these issues, then delete this file. For each one, copy the **title**, add the **labels**, and paste the **body**.

First create the labels (Issues → Labels → New label): `wild-gambit`, `almanac`, `qol`, `data`, `feature`, `bug`, `testing`, `art`, `decision`, `chore`, `parked`.

Then the board: Projects → New project → **Board**, name it "Azeroth Almanac", rename the columns to **To do / In progress / Needs testing / Done**, and add the issues.

---

## Testing

### 1. In-game test pass: Wild Gambit
**Labels:** `testing` `wild-gambit`
```
Work through the Wild Gambit section of docs/TEST_CHECKLIST.md on the latest build (0.52.1 or later). Tick items in the file as they pass; open a separate `bug` issue for each failure and note its number next to the item.

Priority: the 0.50–0.52 changes (player matches, combat pause and dock, opening shuffle, nameplate coin, Let fate decide).
```

### 2. In-game test pass: Almanac pages
**Labels:** `testing` `almanac`
```
Work through the Almanac sections of docs/TEST_CHECKLIST.md: Items, Merchants, Quests, Places and exploration, Dungeons, Trainers, Townsfolk and flight paths, Journal and milestones, Gathering, hidden-database reveals, toasts, icons and layout. Tick items as they pass; failures become `bug` issues.
```

### 3. In-game test pass: quality-of-life helpers
**Labels:** `testing` `qol`
```
Work through the QoL sections of docs/TEST_CHECKLIST.md: settings window pages, auction prices and scan, crafting and disenchant tooltips, merchant repair/sell, flights, Spell Ranker, Talent Planner, Healer Assist, Murloc Tac Toe, Gem Match, dressing room, map and minimap pins. Tick items as they pass; failures become `bug` issues.
```

### 4. Probe leftovers: level-up, death, interrupt, world event
**Labels:** `testing` `almanac`
```
Still unseen on this client (docs/DESIGN.md section 22):
- a level-up
- a death, and the damage meter's Deaths view (who killed you)
- a real interrupt (Kick / Pummel / Earth Shock) in the Interrupts view
- reading the active world event (calendar API)

The Character stories and Rivals issues depend on the death and Deaths view results.
```

---

## Wild Gambit

### 5. Dark Portal board: new art
**Labels:** `wild-gambit` `art` `feature`
```
The 0.52.0 test showed the board needs art made for the window. The code support stays in place (a board's `eyes` and `crest` fields in BOARDS).

Art needs:
- Top-down or steep view; the arch must fit in the ~170 px above the grid (nothing above the window's top edge).
- The vs shield sits at the top centre over the arch: either leave that spot clear or keep `crest = true` (hides the shield).
- Convert with tools/art_convert.py `full` to a 1024x1024 TGA; measure the inner edges for BOARDS.
- Eye positions as fractions of the picture for the glow.
Needs a full game restart (new texture file).
```

### 6. Tutor portrait art
**Labels:** `wild-gambit` `art`
```
The tutorial's coach uses a dice icon as a stand-in portrait. Make a proper portrait in the game's style (round, fits Frame_Portrait).
```

### 7. Murloc Tac Toe and Gem Match logos for the flight prompt
**Labels:** `qol` `art`
```
The flight prompt shows Wild Gambit's logo; the other two games need Logo_MurlocTacToe and Logo_GemMatch in the same style.
```

---

## Features

### 8. Travels: your trail on the map
**Labels:** `almanac` `feature`
```
Design done and the draw test passed (docs/DESIGN.md section 34). Build order: 34a trail recorder, 34b drawing, 34c Travels view and world-map button, 34d replay, 34e settings.
```

### 9. Lore and books
**Labels:** `almanac` `feature`
```
docs/DESIGN.md section 14: library of books, letters, plaques and scrolls read; quest text archive; NPC dialogue; a reading view on the game's book art. Probe confirmed all of it is readable.
```

### 10. Rares
**Labels:** `almanac` `feature`
```
docs/DESIGN.md section 15: sightings of rares and rare elites, learned respawn windows, optional alert when a known rare is on a nameplate. Research tiers: the boss counts (decided).
```

### 11. Factions
**Labels:** `almanac` `feature`
```
docs/DESIGN.md section 16: factions met per character with a small dated standing history, and what raised it where the game says.
```

### 12. Places and services
**Labels:** `almanac` `feature`
```
docs/DESIGN.md section 17: inns (and each character's hearthstone), graveyards, banks, auction houses, mailboxes, stable/guild/battle masters, dungeon entrances; boats, zeppelins and the tram with trip times.
```

### 13. Character stories
**Labels:** `almanac` `feature`
```
docs/DESIGN.md section 18: per character, where and when each level was reached, first zone visits, first kills by kind, deaths (and what killed you), time played; shown in the journal. Depends on the probe leftovers issue for deaths.
```

### 14. More on items
**Labels:** `almanac` `feature`
```
docs/DESIGN.md section 19: item sets (pieces found, bonuses revealed), random suffixes seen, containers opened and their contents, things you crafted.
```

### 15. World events
**Labels:** `almanac` `feature`
```
docs/DESIGN.md section 20: holidays and world events taken part in (event quests, vendors, items), by year. Needs the world-event reading from the probe leftovers issue.
```

### 16. Data plumbing
**Labels:** `data` `feature`
```
docs/DESIGN.md section 21. Split into separate issues when picked up:
- Forever cache overlay (creature/object/quest cache from the client) to correct the hidden database
- saved-data caps, size check and cleanup
- saved-data version number and migrations; hidden database rebuilt per Forever patch
- localization through the string table
```

---

## Decisions and housekeeping

### 21. People page: show what they teach or sell you
**Labels:** `almanac` `feature`
```
Redesign the People page's detail panel and its sub-panel around what this person can do for you: what they can teach you (spells, recipes) and what they sell. The facts about the person (title, where, standing, visits, first met ...) move to the name plate panel, or to a tab of their own.
Decide first: name plate panel or a separate tab.
```

### 22. Spells & Recipes becomes Professions
**Labels:** `almanac` `feature`
```
Rename the Spells & Recipes page to Professions and turn it into a tree list: each profession, and its specialisations underneath, with every recipe the player has come across. Each recipe shows whether this character has learned it or has only found it (seen at a trainer, on a merchant, as an item) and not yet got it. Keep the natural-discovery rule: only recipes you've encountered are listed, never the full list.
Open: where class spells go (they're on this page today), and whether "learned" is per character (it should follow "Almanac shows").
```

### 23. Characters page: player portraits look too small in their rings
**Labels:** `almanac` `bug`
```
On the Characters page (list rows and the big name plate) a character's portrait sits small inside its class-coloured ring: a Skyborne (worgen-like) face shows a wide margin of dark between the face and the ring, so it reads as a picture pasted into a frame. Fix: zoom the portrait in (crop its texture coordinates) so the face fills the opening, or make the ring thinner, so face and ring meet naturally. Check every race's portrait (some have more empty space round the head than others), the list rows and the big plate, and the class badge at the bottom right still clear.
Seen 2026-10-07 on Genie (Windshaper Skyborne Shaman).
```

### 24. Journal-entry badge on the Almanac toasts
**Labels:** `almanac` `art` `feature`
```
New art (saved 2026-10-07): docs/art_source/Badge_Journal.png - an open crimson journal, a gold compass emblem on the left page, molten-gold writing burning into the right page with sparks (Gemini, on magenta).
Use it as the Almanac's mark on its toasts for journal entries, replacing the current top-right tag (the red "Almanac" word on its dark strip and the small book icon), which goes entirely.
Decided 2026-10-07: it overlaps the toast's top-right corner like a seal (half over the gold frame), and goes on every toast that also writes a journal entry (discoveries, tiers, milestones, fully explored).
Steps: convert to Media/Badge_Journal.tga with tools/art_convert.py (key out the magenta, keep the sparks); about 30 px; check it reads at that size (the left page's compass may need dimming so the burning page reads first); optionally a short soft pulse on the glowing page when the toast appears. New texture: full game restart.
```

### 25. New Azeroth Almanac logo everywhere
**Labels:** `almanac` `art` `chore`
```
New logo (saved 2026-10-07): docs/art_source/Logo_Almanac.png - a closed crimson leather journal with a gold compass-rose emblem, gold corner guards and clasp, a red ribbon (Gemini, on magenta). It replaces the game's red book icon (file ID 133742, ns.ICON in Core.lua) as the Almanac's own mark.
Convert to Media/Logo_Almanac.tga (magenta keyed out; a square version for icon slots), set ns.ICON to it, then check every place the old icon shows:
- the AddOns list icon (## IconTexture in the .toc)
- the minimap button, its menu's title row and the Journal row
- the Almanac window's corner portrait and page icons that fall back to ns.ICON (Window.lua)
- Settings > General's tab icon
- the toasts' fallback icon (Toast.lua; the old corner badge goes with issue 24)
- the Journal page's icon and the toast test icon (both list 133742)
- the "Almanac" line in player tooltips (Peers.lua) and the update quest's portrait (UpdateQuest.lua)
- W.FindIcon's last-resort fallback (Widgets.lua)
Round slots (minimap button, window portrait) use a circular mask, so check the book still reads when cut round. New texture: full game restart.
```

### 26. Quest kill credit counts dungeon kills
**Labels:** `almanac` `enhancement`
```
Added 2026-10-07. Inside instances the game hides creatures' GUIDs and names, so a kill only counts when a corpse is looted by you or a groupmate's Almanac (0.66.0). Quest progress still reaches you when someone else loots ("Earthborer slain: 3/8").
Count it: on a quest objective's kill progress (QUEST_WATCH_UPDATE / UI_INFO_MESSAGE / the quest log's objective counts going up), match the objective to its target NPC through the hidden quest database (QuestDB: the quest's kill targets), then count one kill for that NPC (Bestiary CorpseKill-style, so a corpse looted the same moment isn't counted twice: key by NPC + time window, as the encounter kills are). No record yet: make it like a looted corpse (name from the objective text if readable, else "Unknown creature #ID" until named outside).
Check first in game: is the objective text / progress readable (not secret) inside instances?
```

### 27. Wild Gambit dungeon cards
**Labels:** `wild-gambit` `enhancement` `art`
```
Designed 2026-10-07: docs/DESIGN.md section 70.
5% chance per card leaving a hand that its replacement is a dungeon card (one per player per match, only dungeons in your Almanac, never a 6th card). Played onto an empty square as your placement: a neutral, unscored, out-of-play square carrying the dungeon's effect. No spikes, one design, never upgrades. Scenery from the game's dungeon journal art; stone-archway frame.
Steps: 1) scan which dungeons have journal art; 2) review the effects table; 3) card art and frame (Media/), new texture = full restart; 4) rules in WildGambitLogic (seeded deal, neutral square, effects, bot scoring, offline tests); 5) UI (hand, board square, tooltip, sounds); 6) player matches: protocol 12.
```

### 20. Remove dev/AlmanacProbe
**Labels:** `chore`
```
The probe addon in dev/AlmanacProbe can go once the probe leftovers issue is done.
```
