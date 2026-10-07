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
docs/DESIGN.md section 15: sightings of rares and rare elites, learned respawn windows, optional alert when a known rare is on a nameplate. Decide the research tier counts (suggestion: the boss counts).
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

### 17. Combat Journal companion
**Labels:** `data` `feature` `decision`
```
docs/DESIGN.md section 2b: a small program reads the text combat log and writes a data file the addon loads. Decide first: is it worth building, and how it's delivered and run (script, .exe or tray app; on demand or watching the folder).
```

### 18. Rivals: PvP encounters
**Labels:** `almanac` `feature` `parked`
```
docs/DESIGN.md section 31, parked. Build order starts with a probe (31a). Open: the final name, and whether Forever has the honor system and battlegrounds at launch.
```

---

## Decisions and housekeeping

### 19. Open design questions
**Labels:** `decision`
```
From docs/DESIGN.md "Open questions":
- Items: does hovering a link someone posts in chat count as discovered?
- Rares: research tier counts.
- Companion app: build it, and how it runs (see the companion issue).
Record each answer in docs/DESIGN.md, then close this.
```

### 20. Remove dev/AlmanacProbe
**Labels:** `chore`
```
The probe addon in dev/AlmanacProbe can go once the probe leftovers issue is done.
```
