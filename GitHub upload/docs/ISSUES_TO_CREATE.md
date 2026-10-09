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
Designed 2026-10-07: docs/DESIGN.md section 72.
5% chance per card leaving a hand that its replacement is a dungeon card (one per player per match, only dungeons in your Almanac, never a 6th card). Played onto an empty square as your placement: a neutral, unscored, out-of-play square carrying the dungeon's effect. No spikes, one design, never upgrades. Scenery from the game's dungeon journal art; stone-archway frame.
Steps: 1) scan which dungeons have journal art; 2) review the effects table; 3) card art and frame (Media/), new texture = full restart; 4) rules in WildGambitLogic (seeded deal, neutral square, effects, bot scoring, offline tests); 5) UI (hand, board square, tooltip, sounds); 6) player matches: protocol 12.
```

### 28. Healer Assist with hidden health values
**Labels:** `healer-assist` `bug` `wow-forever`
```
Added 2026-10-08 (wowforeverguides.com pitfalls, build 69913): UnitHealth / UnitHealthMax can be secret values on WoW Forever. The health bars are safe (they pass the raw values to StatusBar:SetMinMaxValues / SetValue), but the "in danger" edge, greying and other health maths read them through Readable, which turns a secret into nil, so they may quietly stop working.
Step 1, probe in a group:
/run local s=issecretvalue for _,u in ipairs({"player","party1","partypet1"}) do local h=UnitHealth(u) print(u, h==nil and "none" or (s and s(h)) and "hidden" or "readable") end
Step 2 if hidden: drive danger and greying from what the client allows (the bar's own fill, UnitHealthPercent / curve APIs if present, or threat and debuff state), never maths on the secret.
```

### 29. Dungeons page redesign: a card collection, then the dungeon's map and bosses
**Labels:** `almanac` `ui` `enhancement`
```
Asked 2026-10-08; plan in docs/DESIGN.md section 73.
Tab 1 Collection: a card for each dungeon found (the stone-arch dungeon card), 4 per row, hover to enlarge like the creature cards; click opens it in tab 2.
Tab 2 Dungeon: the floor map on the left with each spotted boss as a clickable portrait pin; on the right a pane with tabs for the dungeon (Overview) or the chosen boss (Abilities, Loot, Other).
```

### 30. Journey: a time lapse of where your characters have walked
**Labels:** `almanac` `feature` `ui`
```
Designed 2026-10-08: docs/DESIGN.md section 74 (supersedes section 34, Travels).
The journey draws itself on the world map as a gold, sparkling line, in the order you walked it. Time frames: today, this week (from Monday), this month (from the 1st), all time. Character mode: the character you're playing, gold. Account mode: every character at once in its class colour, on one shared clock, with a legend to show / hide each.
Jumps: flight path = dotted line + gryphon / wyvern pins; boat / zeppelin = pins at both docks + dashed line (Travel.lua's ride detection); hearthstone = hearth pin; dungeon in / out = the swirl at the entrance; death = skull, ghost run faint; anything else = the portal swirl (Media/FX_DungeonPortal) at both ends. Journal moments (first visits, level-ups, dungeons) as markers with hover.
Steps:
1) Probe: is the hearthstone / teleport cast readable (UNIT_SPELLCAST_SUCCEEDED for the player)?
2) Recorder (ship early on its own): a point every 5 s after ~15 yd of movement; time, map, x, y; jump events tagged; thinned at logout (~20 KB per 4 h).
3) Drawing: line segments and pins on the world map canvas (as /aa maptest), continent and zone maps.
4) Time lapse: ~20-30 s whatever the range, idle skipped, glowing head with time and zone, play / pause, slider, 1x / 2x / 4x; follows the line across continents.
5) Where: a Journey tab on the Characters page; a footprints button on the world map (left: today, right: options).
6) Account mode and legend; settings (recorder on / off, markers, forget a day / all).
```

### 20. Remove dev/AlmanacProbe
**Labels:** `chore`
```
The probe addon in dev/AlmanacProbe can go once the probe leftovers issue is done.
```

---

## Added 2026-10-08 (plans for approval in docs/PLANS_2026-10-08.md)

Each issue's plan, art prompts and open questions are in `docs/PLANS_2026-10-08.md` under the same number. Copy the summary below as the body and add "Plan: docs/PLANS_2026-10-08.md #NN".

### 31. Dungeon card: word-art dungeon names
**Labels:** `wild-gambit` `art` `feature`
```
Show each dungeon's name in WoW-logo-style word art (gold gradient, bronze outline, bevel, shadow) instead of plain text. The logo lettering isn't a game font, so names are pre-rendered in the LifeCraft font (dafont, donationware; the font file is not shipped) to textures by tools/wordart.py; long names on two lines. Shows on the Dungeons page cards, Wild Gambit's event card and the dungeon's header. Plan: docs/PLANS_2026-10-08.md #31.
```

### 32. Dungeon card: a carved name plate
**Labels:** `wild-gambit` `art`
```
The box the dungeon name sits in looks plain. New carved stone name plate with gold filigree and a dark recessed centre for the gold word art (Media/Plate_DungeonName.tga), over the arch's plaque; Gemini prompt in the plan. New texture: full game restart. Plan: docs/PLANS_2026-10-08.md #32.
```

### 33. Dungeon card: parchment background
**Labels:** `wild-gambit`
```
The creature cards' parchment is the worn, torn-edged border painted into their frames; the dungeon cards use the game's flat quest parchment. Cut the painted border from Frame_2_Common as a nine-slice (Media/Card_Parchment.tga) and draw it round the arch on UI/DungeonCard.lua and the event card; Gemini fallback prompt in the plan. Plan: docs/PLANS_2026-10-08.md #33.
```

### 34. Toasts use our own art
**Labels:** `almanac` `art` `feature`
```
Each toast uses the matching painted icon (new herb -> Tab_Gathering, new creature -> Tab_Creatures ...), with the game icon as a fallback; item, tier and milestone toasts keep their own icons (decided). Mapping table in the plan. Goes with issues 24 and 25. Plan: docs/PLANS_2026-10-08.md #34.
```

### 35. Journal landing page: three panes and the Journey
**Labels:** `almanac` `feature`
```
Left list narrower (400 -> 300 px); new large top-right pane showing the Journey (issue 30) for today, with its own controls and a button to open it large; details move to the bottom-right pane. Until the Journey recorder exists it draws from the journal's points. Plan: docs/PLANS_2026-10-08.md #35.
```

### 36. Gathering: skill needed to gather
**Labels:** `almanac` `data` `feature`
```
Show the Herbalism / Mining level each node needs (list rows, node page, map pins), coloured by the current character's skill. Data from the hidden database's lock table, corrected from the game's node tooltip. Plan: docs/PLANS_2026-10-08.md #36.
```

### 37. Rogues: lockpicking
**Labels:** `almanac` `data` `feature`
```
Follows the Almanac shows setting (character: rogues only; account: everyone when a rogue is on the account). The Lockpicking level for locked chests and lockboxes; record Lockpicking skill, Pick Lock casts (what was inside) and "too low" failures; a Locks group on Gathering. Plan: docs/PLANS_2026-10-08.md #37.
```

### 38. "New" entries on every page, with counts on the tabs
**Labels:** `almanac` `feature`
```
Entries found since you last looked at a page show in a "New" group at the top with a breathing gold glow and a separator; a gold count badge on each side tab. New = since you last opened that tab (stamped when you leave it). Plan: docs/PLANS_2026-10-08.md #38.
```

### 39. Journal entry icons match the new art
**Labels:** `almanac` `art`
```
Journal rows, the Overview and entry details use the same painted icons as the toasts. Full list of every log icon, with matches and missing art, in the plan. Plan: docs/PLANS_2026-10-08.md #39.
```

### 40. Characters > Professions: icons open the right page
**Labels:** `almanac` `feature`
```
Clicking a profession opens its page with only its category expanded (Mining -> Gathering, Ore and stone; Enchanting -> Recipes, Enchanting). New page helper ShowOnly(group). Plan: docs/PLANS_2026-10-08.md #40.
```

### 41. Spells & Recipes becomes Recipes; blue bars
**Labels:** `almanac` `feature`
```
The page keeps only profession recipes and is renamed Recipes; class spells, weapon skills and riding move to the trainer's Training tab on People (only what that trainer teaches; no separate class-spell list); links and slash commands redirected. One standard blue progress bar (the Characters page one) used here and everywhere. Builds toward issue 22. Plan: docs/PLANS_2026-10-08.md #41.
```

### 42. People page: a condensed name plate, then Training and For sale
**Labels:** `almanac` `feature`
```
Replaces issue 21. No tabs. The General block goes: roles on the title line, place without coordinates, faction crest on the portrait ring, first met / also met by (and merchant standing, visits, stock checked) in the portrait's tooltip. Below the plate: Training (name, level, cost with coins, coloured for this character, spell tooltip on hover; replaces the "What they teach" badge), then For sale as today. Plan: docs/PLANS_2026-10-08.md #42.
```

### 43. New art: Recipes, Training and Wild Gambit icons (and the missing set)
**Labels:** `art`
```
Gemini prompts in the plan for Tab_Recipes, Icon_Training and a new painted Icon_WildGambit (replacing the blurry 64 px crop of the logo), plus optional Merchant, Flight path, Fishing and Level up icons for toasts and the journal. Plan: docs/PLANS_2026-10-08.md #43.
```

### 44. Bug: herbs show no icon on the Gathering page
**Labels:** `almanac` `bug`
```
Seen-only herbs have no loot, so the row falls back to "Trade_Herbalism", which draws blank. Fix: use the node's loot from the hidden database (as the map pins do) and a file ID first for the Herbs icon (also fixes the herb Apprentice badge). Plan: docs/PLANS_2026-10-08.md #44.
```

### 45. Dungeons page: the portal swirl
**Labels:** `almanac` `feature`
```
FX_DungeonPortal swirls over a dungeon card's arch on the Dungeons page on hover, and stays on the card of the dungeon you're in until you leave (plus one behind the name in its header). Built into UI/DungeonCard.lua. Setting to turn it off. Plan: docs/PLANS_2026-10-08.md #45.
```

---

## Next up (added 2026-10-08, end of session)

Issues #31 to #45 are built in 0.69.0 (commit 23a4a83) and need the in-game test pass (`docs/TEST_CHECKLIST.md`).

### 46. Journey: a full-size Journey tab on Characters
**Labels:** `almanac` `feature`
```
The Journal's Journey pane at full size as its own tab on the Characters page, for the selected character (or everyone).
```

### 47. Journey: scrub slider and playback speed
**Labels:** `almanac` `feature`
```
A slider to scrub through the time lapse, 1x / 2x / 4x speed, and the time and zone shown at the line's head.
```

### 48. Journey: Everyone-mode name legend
**Labels:** `almanac` `feature`
```
In Everyone mode, a legend of character names in their colours; click a name to hide or show that character's line.
```

### 49. Journey: flight and boat lines, the line's head, effects and sounds
**Labels:** `almanac` `feature`
```
Flights drawn as dotted lines, boats and zeppelins as dashed lines (the recorder already marks F/f take-off and landing and b for rides; z added for zeppelins).
The line's head: the live face of the character you're on, else the round class icon (Almanac logo as last fallback). Every portrait, icon and pin round with a circle mask: smooth edges, no blocky corners.
Effects, icons and sounds for every trigger (travel marks, discoveries by toast tier, playback controls), a sound limit, Journey sounds / effects settings and /aa journey sounds to audition them. Full table: DESIGN.md section 74, "Effects, sounds and icons" (approved 2026-10-09).
```

### 50. Wild Gambit: a game in progress survives /reload
**Labels:** `wild-gambit` `feature`
```
Today a /reload drops the match (not counted); a PvP opponent waits up to 5 minutes before it cancels. Quick fix: answer moves for an unknown game with "gone" so their side cancels at once. Full fix: save the match as it's played and resume it on login (PvP asks for missed moves with the existing resend).
```

### 51. More painted art (optional)
**Labels:** `art` `parked`
```
Painted icons for the remaining milestones (merchants, flights, fishing, level, creatures); hippogryph and bat flight mounts; painted cards for Herbs picked, Veins mined and Skinned.
```

### 52. Creatures: category cards
**Labels:** `almanac` `feature`
```
The Creatures page's left pane as cards (default) or the list, switched at the top. Show all (full list, searchable), Creature Mastery (tier icon and name), Creature Types (painted Wild Gambit scenes), Zones (map-art banners with the name in Morpheus, grouped by continent, current zone first, dungeons apart). A card opens the list filtered, with a back arrow; the Tier / Type / Zone dropdowns are removed. DESIGN.md section 78.
```

### 53. Bug: detail pane scrolls back to the top
**Labels:** `almanac` `bug`
```
Creatures (and likely Quests, Dungeons, Trainers): the right-hand detail pane jumps to the top while item names load. Keep the scroll when the same entry is redrawn (W.Detail SetBlocks). DESIGN.md section 78.
```

### 54. Wild Gambit: cards are earned (kills and wins), the card toast
**Labels:** `wild-gambit` `feature`
```
No card for seeing a creature: Fought is the first card tier; seen-only creatures show an iron ring with their 3D model ("Slay this creature to earn its card"); starter critters as Fought "Starter" cards. A new card toast that is the card itself (flip for new, crack-away for upgrades), held in combat, stacked, replacing the research toast. Friendly NPCs earn their card by Wild Gambit wins (1 / 3 / 5 / 10 / 20, from their starting tier), neutral by win or kill, enemy by kill (wins count too); the card on the People page. DESIGN.md section 79.
```

### 55. Items: cards, a Type > Slot tree, upgrade arrows
**Labels:** `almanac` `feature`
```
Cards (default) or a tree like Gathering's: Show all, By kind, By quality, On my characters; dropdowns removed, back arrow, search opens matching branches. Tree by item class (Armor by type, then slot), junk folded at the bottom. "Can't use" tint. Green arrow: upgrade for you (spec from talents, stat weights, vs worn gear); gold arrow: upgrade for a same-faction alt from an unbound copy you own; tooltip names them. DESIGN.md section 80.
```

### 56. Quick fixes: Follow button, Healer Assist, Dungeons boss tab, Shift+J
**Labels:** `almanac` `bug`
```
Follow button only on eligible targets. Healer Assist: more room between its icons and the name plate / health bars so the aggro count reads clearly, buttons' top level with the health bar's top; spells that can't be cast greyed out (mana, nothing to cleanse, range, cooldown). Dungeons: switching boss keeps the current tab instead of going back to Abilities. Default key Shift+J to open the Almanac, with guard rails (DESIGN.md section 83).
```

### 57. Quest giver tooltip: the quests they offer
**Labels:** `almanac` `feature`
```
"! Quest name" lines on a quest giver's tooltip for the quests the Almanac has seen them offer.
```

### 58. Mini game challenge forms and the wisp Tutor
**Labels:** `art` `feature`
```
Challenge requests for Wild Gambit, Murloc Tac Toe and Gem Match as proper forms with each game's logo and art. Wild Gambit's Tutor becomes a wisp (3D model, face as fallback). Needs Asia's new assets.
```

### 59. Mini games across versions
**Labels:** `almanac` `feature`
```
Protocol ranges, features switched off per match (stability first), opponent's version shown before a challenge with the update quest offered, both sides told, board checksum desync guard, release rule, old-vs-new tests. DESIGN.md section 81.
```

### 60. Auction House: Alt+Right-click bag to auction
**Labels:** `almanac` `feature`
```
Alt+Right-click a bag item on the Auctions tab: into the sell slot with stack and price from Auction Prices; Enter or a second Alt+Right-click posts. DESIGN.md section 82.
```
