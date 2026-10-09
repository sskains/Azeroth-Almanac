# Changelog

What changed in each version, newest first. Collected from the old task list (now `docs/DESIGN.md`) on 2026-10-07; from now on each release adds its own section at the top.

Testing status isn't tracked here: see `docs/TEST_CHECKLIST.md` and the Issues board on GitHub.

## Unreleased

- **A new Wild Gambit icon** (`Media\Icon_WildGambit.tga`, 256 x 256): three glowing cards fanned out with a gold coin and purple-flowered vines, painted for the job, replacing the blurry 64 px crop of the logo. Shows in the minimap button's menu. A replaced texture: `/reload` is enough.

## 0.68.9

- **The Almanac's new logo** (the closed crimson journal with its gold compass, `Media\Logo_Almanac`) replaces the game's red book everywhere: the AddOns list, the minimap button (whole, not cut round) and its menu title, the addon compartment, the window's fallback portrait, Settings > General, the "Almanac" line in other players' tooltips, the update quest's portrait, and any icon the game can't find.
- **The journal badge** (the open journal, a page burning with gold writing, `Media\Badge_Journal`):
  - the Journal page's icon (tab, window portrait, the minimap menu's Journal row);
  - toasts: the old "Almanac" tag (red word on a dark strip) is gone; toasts that write a journal entry (discoveries, levels, milestones, fully explored) wear the badge as a seal over the top right corner, half over the gold frame, its page glowing as the toast arrives. Tier ups don't write an entry, so they don't wear it;
  - every entry on the Journal page has a small seal on its icon's corner (the icon still shows what the entry is about).
- Issues 24 and 25.

## 0.68.8

- Fixed: a Lua error hovering "Pin last kill" on a creature from `/aa seeddungeons` (the seeder stored the last kill as a time, not a spot). The seeder no longer sets it, and the button only shows for a kill with a spot.

## 0.68.7

- **Boss names on the Dungeons page** come from the creature's own record once the game has named it; the dungeon's entry for a boss could still say "Boss #1696" from before (pins, lists, the boss's header, loot notes).

## 0.68.6

- Dungeon cards: the parchment rim over the arch's top is a sliver now (the sides and foot unchanged).

## 0.68.5

- **Dungeon cards: the arch fills the card**, the parchment only a thin rim round it, the same width on every side (as the creature cards' art fills theirs). The dungeon's name stays on the arch's plaque; nothing else is written on the card.
- **Under the card:** "5-man · levels 13-20", then "Bosses killed: 3 of 4 met".
- **Group size in its tier colour** (item quality): 5-man green, 10-man blue, 20-man purple, 40-man orange; under the cards, in the dungeon's header, its Overview and a boss's Where.

## 0.68.4

- **Dungeon cards look like cards.** A parchment face edge to edge (as on the creature cards) with a drop shadow and a thin dark edge; the stone arch is smaller, inside it, and the group size and levels are inked on the parchment under it ("5-man · levels 13-20"). Under the card: bosses killed of those met.
- **Group size instead of "Dungeon" / "Raid"**: on the cards, the dungeon's header, its Overview (Group size) and a boss's Where. The size is what the game says inside (recorded each time you enter), else the usual one: 5 for dungeons, 10 for Blackrock Spire, 20 for Zul'Gurub and Ruins of Ahn'Qiraj, 40 for the other raids.

## 0.68.3

- **Dungeon maps: no black band.** Blizzard's map picture fills only the top left 1002 × 668 of its 1024 × 768 tile grid; only that part shows now (boss spots unchanged).
- **A boss's "Where"** names its dungeon (click to open it there), since inside a dungeon the game doesn't say which map you're on; it used to say "?".
- **`/aa seeddungeons` fills everything** (development only): real boss names (a new dev file, `Modules\DevSeedNames.lua`, from AtlasLoot Revival's data), every boss at Master Hunter or beyond (3 to 200 kills), and the facts a fight would record: health samples, a self-heal on some, abilities that hit you with damage figures, a debuff, casts, every drop with counts, money and skinning. Running it again refills the seeded bosses; your own records are left alone.

## 0.68.2

- **Dungeon floor maps.** This client's `C_Map` has no dungeon maps (and inside one, the game doesn't say which map you're on), but Blizzard's own dungeon map art is still in the game files. The Dungeons page now draws each floor from those pictures (`Interface\WorldMap\<dungeon>\`, 12 tiles in a 4 × 3 grid), as Plus Everything's dungeon journal did.
  - Bosses you've met stand on the map as round portraits at their spot from AtlasLoot Revival's data (MIT, already credited in `Licenses\`). Unmet bosses still aren't drawn.
  - Dungeons with several floors get a floor picker (arrows and the floor's name); choosing a boss turns to its floor, and bosses met on the other floors are listed under the map.
  - 27 dungeons and raids have maps; Hall of Thanes and Ruins of Lordaeron keep their journal art and a boss list.
- `tools/build_dungeons.py` now keeps each dungeon's map folder and floors and each boss's floor and spot; the loot and boss data are unchanged.
- The 0.68.1 "floors found by name" lookup is gone (it found nothing on this client), and `/aa seeddungeons` no longer makes up boss spots.

## 0.68.1

- **Dungeon cards: the scene fills the arch.** The game's journal backgrounds only fill the top left of their texture (the rest fades to nothing), so the cards showed a dark band; now only the picture's own part is used, reaching under the stone. The same fix is on Wild Gambit's dungeon event cards.
- **Back** on a dungeon returns to the collection.
- **Floors found by name:** a dungeon with no floors recorded (inside, the game may not say which map you're on) now looks its floors up by its name among the client's maps.
- Polish:
  - the bosses are listed once, on the left (the Overview now shows met / defeated / mastered);
  - shorter notes ("3 kills");
  - a chosen boss's subtitle shows its level, type, research tier and kills;
  - the count is out of 28 (Lower and Upper Blackrock Spire are one instance).

## 0.68.0

- **The Dungeons page, redesigned** (design: `docs/DESIGN.md` section 73).
  - **Collection:** every dungeon and raid you've found is a card (the stone arch, its journal art, flickering torches), four to a row, dungeons then raids by level. Hovering grows a card; under each are its levels and the bosses killed of those met; the header counts how many of the 29 you've found.
  - **The dungeon** (click a card):
    - its floors on the game's map art, with a round portrait where you met each boss. Click a portrait to choose the boss; bosses with no spot are listed under the map.
    - on the right, the dungeon's **Overview**: facts, bosses met (unmet ones only counted), other creatures recorded inside, loot from its bosses, your characters' runs and its Wild Gambit event.
    - for the chosen boss, **Abilities**, **Loot** and **Other**, as far as its research tier unlocks them: 1 kill for every ability, 3 for the full loot table, immunities and resistances.
  - A dungeon whose floors can't be drawn shows its journal art.
- **Developer: `/aa seeddungeons`** (with `/aa debug` on) fills your Almanac with every dungeon and raid, their bosses at assorted kill counts, loot and runs, for testing; `/aa seeddungeons clear` takes it all out again. Nothing you recorded yourself is changed. Bosses still called "Boss #…" get their names the next time you change zone outside an instance.
- New files: **full game restart**.

## 0.67.4

Fixes from the WoW Forever addon developer guide (wowforeverguides.com/addons, beta build 69913):
- **Profession skill levels are read again.** The skill list now comes from `C_SkillInfo`; the old `GetNumSkillLines` / `GetSkillLineInfo` don't exist on WoW Forever, so the Trainers page's profession bars and gathering's skill check had nothing to read. Shared helpers: `ns.NumSkillLines()`, `ns.SkillLine(i)`.
- **Waypoints no longer trip "Interface action failed because of an AddOn".** The extra `C_SuperTrack.SetSuperTrackedUserWaypoint` call is protected on WoW Forever and is gone; the waypoint itself is set as before.
- **Nameplates are read a frame later** (Creatures, Townsfolk, Quest Targeter, the hidden interact nameplate): the event comes before the plate's unit is filled in, so creatures and NPCs seen only on nameplates were sometimes missed. Party Plates already did this.

## 0.67.3

- **Dungeon cards: no washed-out scenes.** Some journal pictures fade out toward their edges, and the parchment showed through them (Maraudon looked pale and misty). The scene now sits on a dark backing.

## 0.67.2

- **Dungeon cards look like the other cards:** the Almanac's parchment sits behind the stone frame, and the event's name is in dark ink on it.
- **A bigger scene in the arch:** the journal art is closer in and reaches under the stone.
- **More drama:** the card holds the stage longer, then steps aside, and the event plays out in full view (every effect runs about 60% slower).

## 0.67.1

- **Developer: a dungeon events debug panel** (removed once the events are done; `QoL/WildGambitDebug.lua`). With `/aa debug` on, `/aa wgdebug` or the **Dungeons** button on the Wild Gambit table opens it:
  - one button per event (raids in orange, WoW Forever's in blue), each with the rules in its tooltip, greyed while it would change nothing;
  - **Random event**, **New practice game** and **Show the table**;
  - a status line: whose turn it is and which event has fired.

## 0.67.0

- **Wild Gambit dungeon events** (practice games; design: `docs/DESIGN.md` section 72). Each time a card leaves your hand (a card played or your spell cast) there's a 5% chance, once a match, that a dungeon you've entered sets off its event at once. The dungeon's card rises over the board on a violet portal, with flickering torches, its journal art and "Triggered by" whoever set it off, and the event hits both players. All 29 dungeons and raids have one, among them:
  - **Shadowfang Keep:** no magic, both spell cards gone under an anti-magic dome.
  - **Gnomeregan:** every card placed may blow up (1 in 4); its player gets a new card and goes again.
  - **Molten Core:** fire and meteors wipe the board, and both players get a new hand.
  - **Onyxia:** a row is breathed away.
  - **Naxxramas:** a square freezes over.
  - **Uldaman:** the board's cards turn to stone.
  - **Ruins of Lordaeron:** every card changes sides.

  Lasting events keep their card small at the board's corner (hover it for the rules). An event that would change nothing is never chosen.
- New cards come from your whole collection once the three reserve cards are spent.
- Developer: `/aa wgdungeon [dungeon]` (with `/aa debug` on) fires an event now in a practice game; `/aa wgdungeon list` lists them.
- New textures and new files: **full game restart** (not /reload).

## 0.66.4

- **Murloc Tac Toe: the Bombay Cat is offered in the Hallow's End line-up.** It was looked for only among your companions, and this client's companion lookup never found it; it now loads from its own creature (NPC 7385), so you don't need to own the pet.
- **Murloc Tac Toe: the line under each player card fits.** The champion and the record ("Plagued Cockroaches   Mudfin") are now one centred line the width of the card, ending in "..." if too long (a long champion name used to run off the card's left edge).
- **Murloc Tac Toe: the "Your turn" ribbon sits lower,** clear of that line, with the board 12 px further down to make room (the window is 837 x 699).

## 0.66.3

Asia's work, merged 2026-10-07: the wg-spell-cursor and murloc-tactoe-restyle branches. (Also: the dungeon cards' design moved to DESIGN section 72, since 70 was already Gem Match's board.)

- **Murloc Tac Toe in the mini games' look** (Asia): the dark window background, the carved-oak buttons with gold lettering, the shared gold dragon frame round a murloc-head corner icon (the empty black circle is gone) and Wild Gambit's carved VS shield.
- **Murloc Tac Toe, a painted swamp board** (Asia): a carved mossy-oak board with vines, mushrooms and a lily pad round nine sockets (`MurlocTacToe_Board.tga`), with Gem Match's carved side panel and carved pop-ups, a murloc badge as the corner icon, a swamp ribbon carrying the result, and mossy carved arrows to choose your champion. The window is 837 x 687. New textures: full game restart.
- **Murloc Tac Toe, refined** (Asia): carved rings round the pieces instead of the neon ones, a glowing winning line with a light that leads it, soft round glows, the status line on the green ribbon, fireflies over the board, and the idle banner as the swamp ribbon.
- **Murloc Tac Toe, a win to remember** (Asia): fireflies burst up from the winning line, and the winner's card glows while its creature celebrates.
- **One soft click on every wooden button** (Asia): Wild Gambit, Gem Match and Murloc Tac Toe, each following its own Sound setting.
- **Murloc Tac Toe, whole creatures** (Asia): the camera stands further back and the model frames have headroom, so tall creatures keep their heads; `/aa mtt cam <champion> <zoom>` tunes one.
- **Cleaner art edges** (Asia): the magenta tint left in the loops of the rope divider (Gem Match and Murloc Tac Toe) is gone, and the other cut-out pieces were converted again with the same fix. New textures: full game restart.
- **Murloc Tac Toe, choosing after a game** (Asia): changing your champion (or the computer's) after a game now changes the cards at once, and the sound you hear is the new champion's, not always the murloc's.
- **Murloc Tac Toe plays swamp music** (Asia): the game's light Jungle day tracks, one after another at random while the window is open (they replace the zone music until it closes), with a Music on/off button beside Sound.
- **Murloc Tac Toe: stumps and champion pickers** (Asia): each creature stands on a mossy stump in a pool (the cards are taller), and a Champions block in the side panel chooses your champion and, for a practice game, the computer's (or Random).
- **Murloc Tac Toe comes alive** (Asia): your champions are the pieces: small animated 3D models standing in the sockets (they act on being placed, the winner's cheer and the loser's slump); each player card has a carved nameplate with the creature standing behind it, and a gem lights on the nameplate of whoever's turn it is. Voices and swamp ambience can be set in game (`/aa mtt voice`, `/aa mtt ambient`, `/aa mtt sound`) until their sound IDs are built in.
- **Hallow's End champions** (Asia): the Sinister Squashling, the Bombay Cat and the Plagued Cockroach join Murloc Tac Toe's champions from 18 Oct to 1 Nov (the same dates as Wild Gambit's Hallow's End board). The Squashling and the cockroach are found by their creature IDs a few seconds after login; the cat from the Bombay pet among your companions (you need to own it), or set it by targeting a Bombay cat and typing `/aa mtt champion bombay`. The holiday calendar check is now shared between the two games.
- **No repeats in Murloc Tac Toe's sounds** (Asia): a champion's voice (and the ambient sounds) never plays the same sound twice in a row where there is a choice; the music already avoided it.
- **A crunch for the Plagued Cockroach** (Asia): one sound (the cockroach's death, file ID 559315) plays for placing a piece, winning and losing. Change it with `/aa mtt voice`.
- **Squish sounds for the Sinister Squashling** (Asia): placing a piece, winning and losing play eight squelchy Azure Span decay sounds (file IDs 4555783-4555797). Change them with `/aa mtt voice`.
- **Cat sounds for the Bombay Cat** (Asia): placing a piece, winning and losing play the cat mount's meows (file IDs 3598605-3598623). Change them with `/aa mtt voice`.
- **A Hallow's End look for Murloc Tac Toe** (Asia): from 18 Oct to 1 Nov the board is a darker oak one with pumpkins, candles and cobwebs, the side panel's dividers become bat-and-pumpkin ones, a heap of pumpkins and sweets sits at its foot and the drifting fireflies turn to embers. Same dates as the seasonal champions (`/aa mtt season` shows it early).
- **Champions** (Asia): choose who you play as with the arrows beside your creature; your opponent sees it. The Sprite Darter (with the Sprite Darter Egg's icon) and the Excitable Slime are found by their creature IDs a few seconds after login and join the choice (`/aa mtt champions` lists what was found). Challenge, accept and rematch messages carry the champion; older versions still play (murloc against gnoll). Details: `docs/DESIGN.md` section 71.
- **Wild Gambit, an aimed spell glows at the cursor** (Asia): once you click your spell card and it is waiting for a target, the cursor wears a pulsing blue glow and sheds sparkles until the spell lands or you put it back. Picking a card from your hand while a spell is chosen also puts the spell back (and takes that card).

## 0.66.2

- **Developer: `/aa ejscan`** (with `/aa debug` on) checks which dungeons and raids have the game's dungeon journal art on this client: backgrounds, lore pictures, journal buttons, group-finder art and loading screens, trying several spellings of each dungeon's name. Results are saved to `AzerothAlmanacDB.ejscan` on `/reload`. For the Wild Gambit dungeon cards (DESIGN section 72).

## 0.66.1

- **Fix: a dungeon creature's journal line showed where you were when it got its name** (e.g. Orgrimmar), not the dungeon. The corpse's spot is now kept until the creature is named, and the journal line uses it. Lines already written by 0.66.0 are moved to the dungeon once, the first time you're outside after updating.

## 0.66.0

- **Dungeon creatures are recorded from their corpses.** Inside instances the game hides every creature's GUID and name from addons (in and out of combat), and the combat log is closed to addons, but the loot window still gives each corpse's real GUID. Looting a corpse now makes its Creatures record if it has none: the kill is counted, the loot recorded, and the dungeon's map logged. Its rank comes from the Classic records.
- **Names arrive on the way out.** The game only answers "what is NPC 11320 called?" outside instances, so a creature first met in a dungeon shows as "Unknown creature #11320" until you leave. Then it gets its name, its journal line and its discovery alert. Seeing it anywhere its name can be read also names it.
- **Groupmates' loot counts.** When someone else in the group loots a corpse inside an instance and runs the Almanac (0.66.0 or later, with "share" on), their Almanac tells yours, so the kill still counts for you. Loot statistics still count only corpses you looted.
- **Boss stand-ins fold into the real creature.** Once a boss's corpse is looted and named, its 0.65.4 encounter stand-in (e.g. Oggleflint under -2732) merges into the real record, keeping the larger kill count, and the Dungeons page points at the real one. A boss counted by its encounter isn't counted a second time when you loot it.

## 0.65.4

- **Dungeon bosses reach Creatures.** Inside instances the game hides a creature's GUID and name from addons, so a boss like Oggleflint was counted on the Dungeons page but never made a Creatures record. Now the boss encounter makes that record: the boss's name, level, rank and type, where it was fought, and kills that count toward its research tiers. Where its NPC ID can't be read, it's kept under the encounter's number. Bosses killed before this update get their record (with their kills) the first time you log in. The Dungeons page now links them to Creatures. Ordinary creatures inside instances still can't be identified (the game hides their names too).
- **Healer Assist pets on the game's pet frames:** a party pet's icons now start in the same column as its owner's, and its paw print is hidden, because the pet frame already shows it's a pet. Tip: party pet frames show after `/run SetCVar("showPartyPets",1)` and a `/reload`.

## 0.65.3

- **Healer Assist beside the portraits:** with "right", the icons now start under the name plate, level with the health bar (they used to start level with the name). A pet with no frame of its own (party pet frames are often hidden) now gets its line of icons just under its owner's, a little indented, instead of being left out (needs "Group members' pets" on; your own pet keeps its pet frame).

## 0.65.2

- **Healer Assist: icons on party members' frames.** This client's party frames have no global names (the old `PartyMemberFrame1` ... don't exist), so a party member's icons went to the Healer Assist window instead of under their portrait. The frames are now also found as children of the party frame (and the raid-style party frame), pets included. `/aa heal debug` now lists which frame each member's icons are on.

## 0.65.1

- **Fix: opening Wild Gambit could throw "attempt to perform string conversion on a secret string value"** when a nameplate or your target belonged to a unit the game keeps secret (enemy nameplates in combat). Every unit Wild Gambit reads (opponent nearby, Play Wild Gambit on a unit, challenge by target, portraits, your pet) now goes through `Readable`: a secret counts as unknown, so that unit is simply skipped.

## 0.65.0

Asia's `gem-match-wood-board` branch merged into main (with everything up to 0.64.2).

- **Gem Match, a painted wooden board** (Asia): a carved-oak board with the gems in its sockets (`GemMatch_Board.tga`), a carved side panel with a score plaque, rope divider and gem pouch, a "Well played!" game-over panel with a ribbon and spilling gems, flying gem shards when gems clear, a louder hint (only from the Hint button), a gold glow on the picked gem, and a "Choose your game" mode switch. Best scores now come from your guild, group and online friends. The window is 918 x 620. New textures: full game restart.
- **Shared window pieces** (Asia): the wooden buttons, their gold lettering, the gold elite corner frame and the gold headings moved from `WildGambit.lua` into `QoL/WindowUtil.lua`, so Gem Match and Wild Gambit share them (Wild Gambit looks the same).
- `tools/art_convert.py` gains `board` and `cut` modes. Details: `docs/DESIGN.md` section 70; checks: `STATUS.md` (Gem Match items).

## 0.64.2

- Minimap button menu: the mini games sit under their own "Mini Games" plate (a dark band between gold rules), Z to A: Wild Gambit, Murloc Tac Toe, Gem Match; a thin gold rule closes the section before Settings. Menus can now have section plates (`section = true`) and thin dividers (`divider = true`).

## 0.64.1

- **Friendly NPCs no longer get a nameplate and health bar when friendly nameplates are off.** The cause: the gathering highlight turns on the game's interact nameplates (it needs them for nodes), and the game gives the NPC you face one too. That NPC plate is now made invisible unless your friendly nameplates are on; a gathering node's plate is untouched. Settings > Gathering > Game display: "Nameplates on friendly NPCs I face" brings them back if you liked them.

## 0.64.0

The last part of the review: speed, clearing out what's no longer used, and polish.

- **Faster:** minimap gathering pins only look at the continent you're on; an open Almanac page refreshes only when something it shows changes; milestones are counted in one pass over each kind; the journal is trimmed in chunks past its cap instead of on every entry; "x of y areas" answers are kept for 30 seconds (dropped when you explore somewhere); Healer Assist in a raid works every other tick.
- **Removed:** the game-art Wild Gambit board, card ornaments and talent-painting card backgrounds (the painted ones replaced them long ago); the board "eyes" and "crest" support; the Grounding Totem code (no class has it); the old spell buttons by the portraits; unused helpers (`WL.Synced`, the old card tooltip, a duplicate chat helper, a never-read tutorial flag); the old Merchants page (merchants live in People); `UI/Pages/Placeholders.lua`; `/aa setkills` and the art recording session (`/aa artlog`). Saved data drops what nothing reads any more (each character's "firsts" lists, two old exploration fields, an art recording), and a merchant's price history keeps only changes from the last 30 days for items still on sale.
- **Developer commands** (`/aa maptest`, `art`, `toast`, `atlascheck`, `whatis`, `cards`) answer only with `/aa debug` on.
- **Polish:** a Wild Gambit card with no kills shows no skull and 0; closing the Wild Gambit window mid-game (Escape, the close button) keeps the game in the bar, one click back; the pick note no longer lingers on the lobby; trainers in Places and the journal open their People page; the minimap button's menu lists every page; a zone or place counts a visit when you arrive, not at every subzone and indoor change; "Your characters" lists sort by name (not by class colour); Reset window positions also puts back the alerts and the gathering button; stale comments brought up to date.

## 0.63.0

The second part of the review fixes: the character-only Almanac, settings profiles, Healer Assist and smaller polish.

- **"This character only" fills its gaps:** something new to the character you're playing now gets its alert and journal line even when another character found it first; milestones are counted per character as well (a "Milestone reached (this character)" alert, and the journal's milestone list is that character's own); gathering totals, kill-based tiers and boss kills in milestones follow the character; gathering pins on the maps, people on the world map, mailboxes and "sold by" lists show only what this character has found; zone links skip zones this character hasn't been to.
- **Settings profiles hold choices only:** what's saved is the list of settings the defaults (and the Settings window) define, never what a helper has learned or one-off upgrade flags. Switching profile replaces every choice it covers (one the profile lacks goes back to its default). Copy from... and Delete keep where your windows are. A character new to the Almanac opens every window in its default spot instead of where the last character left it. The character key is the same from the first moment of loading (the realm name read the normalised way).
- **Healer Assist:** the screen-edge alert now works in combat while the game hides health (a red edge per member under attack below the danger level, following the game's health curve; no sound in that case, as the number can't be read); the red throb on buttons uses your Danger level setting instead of a fixed 30%; out-of-range or out-of-mana buttons grey out in combat too; a newly learned rank updates the existing buttons; a pet no longer pushes a more urgent member off the panel, and the line joining a pet only links it to its own master; combat starting mid-drag drops the panel where it is; the opacity setting changes only the opacity (no full re-layout).
- **Threat monitor:** "Pulling aggro at %" goes up to 100 (the game's figure never passes 100, so higher settings never warned); saved values above 100 count as 100.
- **Gathering highlight:** "The game's own" search direction is kept as a real choice (it survives profiles and reloads).
- **Quest Targeter:** mobs your group members' pets are fighting count as yours.
- **Hollow minimap rings:** a game not restarted since the ring art was added shows the pin see-through instead of nothing.
- **Exploration:** "x of y areas" finds zones whose achievement wasn't loaded yet the first time it looked (it checks again, at most once a minute).
- **Slash commands:** `/aa help`; `/aa gathering` (also herbs, ore, fishing) opens Gathering; `/aa people check` works again; `/aa tf` opens the people-on-the-map settings; an unknown command says so before the list; the list matches today's pages.

## 0.62.0

Fixes from the review of everything since the dungeon module, and player-match safety. **Protocol 11**: both players need 0.62.0.

- **Wild Gambit, the pick cap:** your picked card still plays at full strength, unless the two hands would end more than 3 spikes apart even with every other card at its lowest. Then it drops a tier at a time (never below its floor), only as far as needed, and you're told: a line in chat, a note on the table, and the red down arrow on the card. The pick note says it may be downgraded. In matched-collection tests this happens in about 1 game in 400.
- **Player matches hold up when messages go missing:** every whisper goes out through one paced queue (retried when the game turns it away); a setup with cards missing after 15 seconds is sent again and asked for again, and called off after 40; a "still here" every 15 seconds during a game, a note after a minute of silence (End, not counted / Keep waiting), and the game is called off after five minutes. A move this screen can't play now cancels the game instead of leaving it stuck.
- **Cancelled games** show a "Cancelled · Not counted" banner (out of step, a card the other Almanac couldn't accept, an opponent who stopped answering).
- **Games end even when the window is hidden:** the result counts the moment the last card is placed; tucked away, docked or closed with Escape, the game still finishes.
- **No more abandoned games:** starting something else during a practice game (Play Wild Gambit on a unit, `/aa gambit new`, the lobby, the tutorial, a challenge) asks to forfeit it first; during a player match you're asked to finish or Leave. Accepting a challenge mid-practice says it forfeits the practice game. The tutorial is set aside quietly.
- **Tutorial:** the coach waits while the window is tucked away and carries on when it's back; after the tutorial, "Play for real" starts a game against a creature (it could re-challenge your last player).
- Started in combat: the game is paused from the first move (and the other player told). Combat flickering on and off sends one pause message, a second later.
- Received hands are checked against the table's spike budget; skull cards (level unknown) are no longer refused.
- Freezing Trap: only your own traps rule a square out (the other player's hidden traps no longer show by being untargetable).
- Another version challenging you gets a reply naming your version, and you see theirs; only the player you challenged can call off your challenge. Matchmaking across realms compares full names, so exactly one of two lookers sends the challenge.
- **Almanac:** resetting the Almanac keeps settings profiles and the blocked-action log; a merchant's stock refreshing while you shop (a purchase, a buyback) no longer counts as another visit or finds every item again; map pins left over from a longer list no longer come back with Places' pin toggle.
- **Quest Targeter:** no nameplate scan while it's off; an item name found nowhere and each drop list are remembered for a short while (fewer full searches several times a second); a target listed twice counts once.

## 0.61.1

- Places map: hovering a place that has no outline (pinned places) shows its pin on the map the same way: temporarily, with the selected place's own pin stepping aside, and put back on leaving.

## 0.61.0

- **Wild Gambit: your picked card always plays at full strength.** Hands are still built to the shared spike budget, but the pick is never capped or lowered (not when building the hand, not when the two hands are evened out); the other four cards fill what's left and, when needed, drop below their usual floor tier (an elite may play at Sighted). Both players' picks are protected; the practice gambler's Easy setting may still weaken its own. Weakened supporting cards show a small red down arrow on their tier badge; a note under the pick heading says the card plays at full strength. **Protocol 10** (the lowered mark travels with each card): both players need 0.61.0. Tested: 400 random hands with a legendary pick never lowered it; with matched budgets 99% of hand pairs end within 1 spike.
- **Places map:** the place outline is 25% stronger (wider gold rim, brighter glow). Hovering a place in the list outlines it on the map shown; moving off puts back the selected place's outline (or none for a zone).

## 0.60.1

- Toasts 20% larger (331 x 115, icon 62): longer titles and names fit before shortening.
- Wild Gambit kill strip about 15% smaller (skull 7.5, number 7.3).

## 0.60.0

- **Toasts** carry the Almanac's mark: its icon (a quarter of the big icon's size) and "Almanac" in red, on a small dark tag at the top right.
- **Wild Gambit kill count, a trophy on every card:** the raid skull and the kills (account or character, as "Almanac shows" is set; companions their kills together; never the hero or a sheep) on the strip between the art and the name panel, placed per tier from each frame's measured strip; 1.2k / 15k for big numbers. Shown on both sides in player matches: **protocol 9**, both players need 0.60.0.

## 0.59.0

- **Settings profiles** (Settings > General > Settings profile, new `Modules/Profiles.lua`): every character uses Shared unless you pick This character or a named profile (New profile..., Copy from..., Delete this profile). A profile holds every choice of the Almanac and the helpers (on / off, colours, sizes, opacity); recorded data, prices, flight times, bags, Wild Gambit records and the "Almanac shows" choice are never in it. Each character now keeps its own window and button positions. Your current settings became the Shared profile. Switching reloads the interface.

## 0.58.0

- **Account or character Almanac** (Settings > General > Almanac shows): *My whole account* (as before) or *This character only*: every page, count, the journal, creature tiers and gathering ranks show only what the character you're playing has found, killed and gathered, and Wild Gambit plays that character's own cards. The window title names the character. Recording is unchanged; each creature and node now also keeps per-character kills / gathers (from this version on: earlier kills count for the account only). Prices, flight times and other characters' bags stay account-wide.
- **Minimap gathering pins** about 40% smaller (default 7, existing sizes scaled once; the size setting now goes down to 4).

## 0.57.0

- **Places:** zones are indented under their continent (places further in). Each zone shows how much of it this character has explored, from WoW Forever's exploration achievements: "7/12" on its row, an Exploration section with the areas still to find, and a "Fully explored" alert and journal line when the last one is found (the one exception to ground rule 9).
- **Creature abilities** show what one use does, from the spell's own tooltip ("15 - 25 per hit", "45 over 15 sec", or both); melee per hit from the Classic records once fought. The per-fight total moved to the tooltip.
- **Minimap button menu:** Places uses the new Places art, Characters your own portrait, Murloc Tac Toe the murloc-costume chihuahua, Wild Gambit a square cut of its logo (`Media/Icon_WildGambit.tga`).
- **Gathering highlight colours** (applied once): herbs #00FF00, ore #FFFFFF, chests #FF0030, quests #FFD130.
- **Minimap gathering pins:** while your Find Herbs / Find Minerals / Find Treasure is on, pins of that kind become hollow rings (`Media/Ring_Hollow.tga`), so the game's own dot for a live node shows inside.

## 0.56.0

- **Healer Assist:** "Show the icons" offers Beside the portraits (below / right) or The Healer Assist window. The window has a see-through dark mesh background (`Media/Panel_Mesh.tga`) in a thin gold border, with a Window opacity setting. Buttons not needed are fainter; a recommended spell is fully visible with a yellow throb, which turns red when the member is under 30% health (also in combat, where health is hidden, through the health curves). Pets sit indented under their master's row, joined by a thin line.
- **Threat Monitor and the flight bar** use the same mesh box and border, each with its own opacity setting.
- **People** now holds merchants too: a merchant's page shows your standing and their full stock with prices. The Merchants tab is gone (links and `/aa merchants` open People). The Trainers tab is renamed **Spells & Recipes**; the trainers themselves are on People.
- **Places:** zones are grouped under their continent (each folds); places sit under their zone. A place's page shows its zone map with the place outlined in gold (its own uncovered-area shape, a gold rim and a soft glow), or a pin where you first entered it when the game has no shape for it.

## 0.55.0

- **New menu icons** (`Media/Tab_*.tga`, painted): Characters, Creatures, Items, Quests, Gathering, Places, Dungeons, People. Characters shows the journal icon instead of your portrait.
- **Creatures page:** your Wild Gambit card grows 30% while the mouse is over it (no tooltip any more). Alliance and Horde creatures wear their faction crest at the bottom right of their portrait, on their list row, and on their Wild Gambit card (recorded from the next time you see them). Tier badge rings are half as thick.
- **Quests:** the page opens on "In your quest log". A quest in your log gets a yellow ! (Show in quest log, opens the game's quest log at it) and a Share button (offers it to your group; greyed when solo or not shareable).
- **Records:** "Print what's recorded" now summarises blocked actions (one line per function, how often, the latest) and only for the current version; older reports are cleared at login. New "Clear blocked log" button.
- **Quest Targeter:** creature health is secret on this client, so "already hurt" never worked: a mob fighting someone outside your group now counts as taken whatever its health, as does one tagged by another player; with taken mobs in sight, out of combat only the nearest untaken nameplate is targeted (no fallback to the closest by name).
- **Gathering highlight defaults** (applied once to existing settings): sparkle 32, reach 15, all around me, all kinds on (herbs #00A025, ore #3F837E, chests #FFD133, quests white), chime, the game's interact icon and object name off. Search direction is a full-width dropdown.

## 0.54.0

Asia's branch `wg-shuffle-dealer-button` merged into `main`.

- **Wild Gambit pick screen, Asia's rework:**
  - The Shuffle button is the goblin dealer in his carved ring (`Media/Dealer_Shuffle.tga`), captioned "Deal a new hand" ("Dealing..." while the cards move), over Begin; he says one of three lines each deal, never the same twice running.
  - Begin is larger, with a breathing glow, a sweeping light streak and gold sparkles; the Back arrow is painted (`Media/Back_Arrow.tga`), larger and ringless.
  - The hand trays are a wooden coin tray (`Media/Tray_Coins.tga`); "Choose a card" / "Choose your class" headings with gold rules and diamonds; the Your spell card enlarges on hover; the corner icon in a gold dragon ring.
  - Aquatic creatures (School of Fish, Saltspittle murlocs) on the underwater scene.
  - `tools/art_convert.py` additions for the new art.
  - Full notes: Wild Gambit pick screen: the Shuffle button is now the goblin dealer in his carved ring (`Media/Dealer_Shuffle.tga`, 256 px, round, source `docs/art_source/Dealer_Shuffle.png`) with its "Deal a new hand" caption on a small carved wooden plank (`Button_Wood`, like Back / Begin) across its lower edge; the lettering brightens on hover and reads "Dealing..." while the cards move. It sits bottom left, over the board's painted coin pile (the deck the cards fly to and from, `shuffle.dx/dy` = -265, -498), same `WG:Shuffle()`; Back is now the plank's width (128) and sits directly under it, centred on the same line. Pick screen headings: "Pick your card and class." is now "Choose a card" and "Play as" is "Choose your class", centred above the nine class rings (the ring row is centred on the board); both in gold Morpheus lettering with a deep shadow and a thin gold rule and diamond each side (`WG.Ornament`). Back and Begin use the dealer caption's lettering (13 pt gold Morpheus with a shadow; dimmer gold when Begin is disabled): `WG.WoodLettering`. The "Your spell" card on the pick screen enlarges on hover like the pick cards (`WG:PickSpellZoom`: a copy at the pick zoom, 1.7x, grows where it lies, kept inside the window, the original fades under it; the full rules stay in the tooltip beside it). Round 3: Begin also gets a streak of light that sweeps across it every 2.6 s and a few small gold sparkles that kindle round the plank, drift up and fade (both only while it can be pressed; a gold border was tried and dropped as too hard-edged); the spell card 20 px to the right of where Round 2 left it (further in from the felt's left edge); the Back arrow lost its gold ring and socket and is bigger (56 px, 62 on hover). Round 2 of the pick-screen layout: the spell card 12 px further left; Begin is bigger (172 x 32, 18 pt lettering) with a gold glow that breathes while it can be pressed, the dealer button still centred over it (`WG.BEGIN_W`); the Back arrow is now the painted red arrow (`Media/Back_Arrow.tga`, source `docs/art_source/Back_Arrow.png`, from a baked checkerboard: new `arrow` mode in `tools/art_convert.py`); the boxes that hold each player's hand are the new wooden coin tray (`Media/Tray_Coins.tga`, source `docs/art_source/Hand_Tray.png`: the landscape tray turned a quarter turn, the coin-pile ends kept and only the middle stretched into a 128 x 512 texture, new `tray` mode in `art_convert.py`; slice margins 40 / 81; the older oak tray `Tray_Hand.tga` stays in Media and the swap is one line, `Frame.trays` in `Build`). The board's own slots keep the stone `Slot_Board`. New textures need a full game restart. Pick-screen layout swap: the "Your spell" card (and its label, under it) moves to the bottom left, mirroring Begin; the dealer button moves to the bottom right over Begin on Begin's centre line (computed from the panel size: `shuffle.dx/dy`); Back is no longer a wooden button but a red arrow in a gold ring in the board's top left corner (the game's `common-icon-backarrow` atlas where it exists, else the spellbook's page arrow, desaturated and tinted red; glow, press and tooltip); the last card on the table lies up and in a little (`SCATTER[10]`), and the spell close look is kept on the felt on the left as well as the right. The "Your spell" label sits under the card (the lower row of cards overlapped it above) in 14 pt gold Morpheus. The "Your spell" card is a little smaller (0.9) and moved in from the board's carved edge so it lies wholly on the felt, and its close look is kept on the felt too. "Let fate decide" is centred on the board (the die and its words centred as a group, `WG:LayoutFate`, also when the words change). The window's corner icon is bigger (74 px) in the gold elite frame (the boss portrait's gold dragon ring, `UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold`) over a dark socket that covers the template's small portrait (`WG.AddEmblem`). The dealer talks: each click on his button plays one of three goblin lines (`WG.DEALER_LINES` = file IDs 550816 / 550811 / 550810, GoblinMaleZanyNPCPissed01 / 03 / 04), chosen at random, never the same one twice running, on the Dialog channel, off with the Wild Gambit sound setting. Longer online-match messages stay plain 15 pt gold sentences ("Pick" became "Choose" in them too). The pick-screen cards sit closer together (column step 106 → 96, rows 272/404 → 282/408) to free the top-left corner, and the whole set of cards is centred on the board (shifted 32 px right; was 40 px left of centre to leave room for the spell card). The Wild Gambit logo on the pick and lobby screens is bigger (310 → 370 px wide) and sits higher (62 → 36 px from the top); the hint line under it follows. Glows on hover, dips on press, glows, pulses and rocks while the cards are shuffled and dealt. Card scenes: "School of Fish" (a Critter with no family) showed the meadow because the habitat rules had no fish words; `HABITAT_WORDS` Underwater now also matches fish (whole word, so "Fisherman" stays on land), "school of", jellyfish, starfish, piranha, squid, octopus, frenzy, thresher, manta, whale, dolphin, and the murloc tribes (Saltspittle, Bluegill, Greymist, Coastrunner, Puddlejumper). That also fixes Saltspittle Puddlejumper / Warrior / Oracle (no scene) and Muckdweller (Swamp). Checked against every creature in the saved Almanac and a list of land lookalikes. New `round` mode in `tools/art_convert.py` (round medallion on a flat dark background: outside the ring transparent, squared). New texture: needs a full game restart.
- **Merged with 0.52's shuffle:** the dealer's voice line now plays on every shuffle, including the opening deal when the pick screen opens, and the riffle sounds play during the riffle animation instead of all at once at the start.
- Housekeeping: `docs/TASKS.md` (replaced by `docs/DESIGN.md`) and the unused `Board_DarkPortal.tga` removed.

## 0.53.1

- Wild Gambit: a card in a new hand could still wear the last game's Divine Shield bubble (or another spell's mark): card frames are reused, and now start each game clean.
- Progression page: the Your progress rows sat on top of the section heading (they were placed upwards); Creatures now first, then Gathering, then the hero line. The last card's name ("Legendary Hunter") no longer runs past the edge, and less empty space under the cards.

## 0.53.0

- **Progression page** (Settings, was "Research tiers"; `/aa settings progression` or `tiers`):
  - Creatures: a ladder of the six tiers with their badges joined by a line in the tier colours; for each, the kills needed (and for rares and bosses), what it reveals, the alert it earns, and the Wild Gambit spike bonus on a small card in that tier's frame.
  - Gathering and fishing: the same ladder for the six ranks (gathers needed, what each reveals, the rank alert such as "Expert Miner").
  - Wild Gambit: level base + tier bonus = card spikes, the same level 30 creature drawn at every tier (4 to 12 spikes), frame flourishes, head starts for elites, rares and bosses, and how your hero card climbs.
  - Your progress: how many creatures sit at each tier and nodes at each rank, and your hero card's tier with how many more mastered creatures reach the next.
  - Every number is read from the modules, so the page follows any change to the thresholds.

## 0.52.1

- Dark Portal test done: the board and its art are taken out and Forest glade is the default again (it returns later with new art; the glowing-eyes and no-vs-shield support stays, driven by a board's `eyes` / `crest` fields).

## 0.52.0

- header: the score coin sits inside the nameplate's round end (smaller, font 19) and the spell and portrait move out 6, so the plate starts clear of the portrait frame.
- shuffle: the pick table always opens face down and shuffles in front of you (gathered, riffled twice in two halves, dealt one by one face up); "Shuffling the deck..." and a glow under the deck while it runs; Begin waits for the deal. Refreshes while open don't reshuffle.
- new board: The Dark Portal (Media/Board_DarkPortal.tga, arch foreshortened above the board), the default board for testing (a board picked before is reset once); the dragon's red eyes and the four corner creatures' fel green eyes glow and pulse; no vs shield on this board (the dragon stands between the players). Needs a full restart (new texture).

## 0.51.1

- the turn glow round the nameplate is twice as strong (two glow layers) and reaches twice as far.

## 0.51.0

- Wild Gambit:
  - Opponent in combat: a note over the board (they're in combat, the game waits) with "Tuck it away" (into the bar, docked as set) or "Wait here"; when they're back, the table returns if it was tucked away for them, with a ready-check chime and a line in chat.
  - Shuffle on the pick screen (above the first card): the cards are swept into the deck, riffled and dealt again one by one, turning over as they land (paper and page sounds). You and your companions always come back; the rest are drawn at random (favourites a little likelier). The picked card stays picked if it comes back.
  - Let fate decide is a die between Back and Begin (Interface\Icons\INV_Misc_Dice_01 in a gold ring): it glows on hover, pulses and rocks while fate has the choice, with a dice sound. Fate now picks your class too (the class picker and spell card grey out; a class or card clicked takes the choice back).

## 0.50.0

- player matches (first real 1v1 test), protocol 8 (both players need 0.50.0):
  - The opponent's portrait is never a card any more (it was their first card: their hidden one). Their live portrait when they're in sight (target, focus, group, nameplate), else their race's portrait (race and sex now travel with the setup message). Same on the cards' owner clasp.
  - Whose turn: a warm glow round that player's nameplate (with the arrow). Nameplates taller; the score on a bigger bronze coin over the frames, outlined.
  - A card taking several lunges clearly at each in turn (bigger lunge, a little slower).
  - Pick Pocket: the hint says "click one of your cards on the board" (a click in the hand no longer selects a hand card while choosing a target); the status line is short enough not to be cut off.
  - In combat the game pauses for both players (P|gid|1/0); the practice gambler waits too. The window tucks into a small bar (Settings, Wild Gambit, In combat: dock top / left / right, float, or leave open) and comes back when combat ends. A "-" button on the window tucks it away by hand (floating, movable); click the bar to come back.
  - The "forfeits" at Ready: a game the other screen called off (a card it rejected, or out of step) now says so on both screens and isn't counted. The creature level check against the database is gone (WoW Forever's levels don't always match it; it rejected cards on one screen only). A first move that arrives before this screen has begun is kept and played.
  - Grey (Poor) cards keep their scene in colour.
  - Settings: the practice difficulty, table, board, holiday boards and card back pickers now change the Wild Gambit settings (they were writing to the Gem Match settings).

## 0.49.1

- fix: "AzerothAlmanac has been blocked from an action" (SpellStopCasting / SpellStopTargeting, on Escape and logout). Cause: QoL/WildGambit.lua reassigned the game's StaticPopupDialogs table ("StaticPopupDialogs = StaticPopupDialogs or {}", added in 0.42.2 and 0.44.2), which taints it; the game menu then refuses its own protected calls. Both lines removed; only our keys are added to the table. Traced from the blocked-action log (db.diag).

## 0.49.0

- holiday boards: Hallow's End (Media\Board_HallowsEnd: pumpkins, skull, bat and cat, ember runes) and the Feast of Winter Veil (Board_WinterVeil: yetis, reindeer, holly, frost runes), in the Board picker; with "Holiday boards" on (the default) the board dresses for the season by itself during Hallow's End (18 Oct - 1 Nov) and Winter Veil (16 Dec - 2 Jan), whichever board you picked.

## 0.48.3

- the turn arrow points back along the nameplate at the name whose turn it is (it pointed away).

## 0.48.2

- the hidden card's badge moved left to the frame's edge.

## 0.48.1

- fix: the tutorial errored at the deal (the Tutor's icon face went to SetPortraitTextureFromCreatureDisplayID in the card clasp); icon faces are drawn as textures.

## 0.48.0

- the players' header dressed: a carved nameplate (Media\Header_Nameplate, mirrored for the opponent) from each portrait towards the vs, the name along it over an inlay of the class colour, the score on a bronze coin (Header_ScoreCoin) in its round end, and a gold arrow (Header_TurnGem) at its far end nudging towards the board on that player's turn.

## 0.47.1

- the close look at your hidden card keeps its stealth look (smoke, shimmer, frame tint, hooded badge).

## 0.47.0

- How to play: a guided match against The Gambit Tutor (15 steps on a parchment note over the board's bottom row, a gold glow on what it talks about). Your hand, spikes, your hidden card, your spell; the Tutor plays first (scripted), you capture its card (6 against 1), it takes yours back (7 against 2), you win it back (5 against 3); only the asked-for card and square work until then, and your spell waits. Then "Play on": the rest of the match against an easy Tutor that casts no spell. Not counted in your record ("Tutorial complete!"). Offered once in the lobby (Play the tutorial / Got it, for everyone, old players included), then a How to play button under the record; /aa gambit tutorial. Skip the tutorial any time.

## 0.46.10

- the hidden card loses its violet outline (the cloaked frame, badge, smoke and shimmer stay).

## 0.46.9

- hands size themselves: each card is as big as its row allows with its spikes clear of its neighbours (six in hand about 0.69, five 0.83), never wider, spikes and all, than the plank (0.88 at most); as cards leave, the rest spread out and grow; the flight to the board starts from the card's current size. The hidden card's hooded badge moved down onto the band under the art.

## 0.46.8

- the blocked-action record keeps the latest 30 (it had filled with the old map-pin blocks of 0.17.6 and stopped recording), so a new "blocked from an action" popup can be traced from SavedVariables.

## 0.46.7

- hidden card art: Media\Badge_Hidden (the hooded figure with violet eyes, replacing the eye icon) and Media\FX_Stealth (violet smoke on black) in two layers that rise and fade in turn across the art window; choosing a card on the Prepare screen plays the rogue Stealth sound.

## 0.46.6

- the close look at a hovered card in a match is 35% smaller (1.56x, was 2.4x).

## 0.46.5

- the hidden card is unmistakable: a pulsing violet stealth outline round the whole card, its frame cloaked a dark violet (spikes and number stay bright), and a hooded-eye badge at the bottom left of the art (an eye icon until Media\Badge_Hidden is painted), on top of the shimmer and haze. The haze now always uses the placeholder until FX_Stealth arrives (a missing file would have drawn nothing).

## 0.46.4

- lobby: the Challenge and Find a match icons (and Practice's question mark) zoomed in so their square edges stay inside the round frames.

## 0.46.3

- prepare screen: the Play as row and "...or let fate decide" moved down clear of the lower cards; a hovered pick card grows less (1.7x, was 2.4x); the elite/rare plate dragons no longer show on the painted frames (they read as stray rings on the narrow name panel).

## 0.46.2

- practice difficulty: Easy (misses the best move about half the time, ignores what your hand could do, uses its spell less, and its two strongest cards play a tier lower), Normal (the default, a little gentler than before) and Hard (the old near-perfect play). Set on the Practice tile (Difficulty: X >) or in Settings, Wild Gambit, Practice difficulty. The hidden chosen card now looks stealthed instead of the Shadowmeld icon: the model shimmers half-seen under a drifting haze over the art window (spikes stay readable); uses Media\FX_Stealth when that art arrives, a tinted glow until then.

## 0.46.0

- a three-step flow. 1) Who will you play? (the lobby on the felt): Practice (the creature near you, or the best your Almanac knows; "Someone else" picks again), Challenge a player (name box, My target), Find a match (search clock on the tile); what you played last glows; your practice and player records; a first-time tip (three lines, Got it). 2) Prepare: the opponent already in the seat; the ten cards with "...or let fate decide" under them; Play as with your spell shown as its card (hover: full rules); Back, and Begin / Ready (greyed until a card is picked or fate chosen); against a player the line says waiting / accepted / they're ready. 3) The match; the result offers Play again (same opponent: back to step 2, or a new challenge) and New opponent (step 1). Challengers and match-made players now press Ready when they've chosen (no more sending the card the moment the other side accepts). Portrait "Play Wild Gambit" and accepting a challenge go straight to step 2. Creatures page: the favourite heart moved to the top left of the card box.

## 0.45.4

- flights offer a game, not just Gem Match: Wild Gambit (its logo as the button), Murloc Tac Toe and Gem Match side by side, one recommended each flight (a different one from last time, glowing gold, named in the prompt). In the prompt at the top of the screen and on its own line in the talking-portrait panel.

## 0.45.1

- spell cards carry a short rules line (WL.ABILITIES[..].short); the full rules show in a tooltip beside the close look and on the class picker. The shrink-to-fit now measures with a set width (it measured before layout and didn't shrink).

## 0.45.0

- Freezing Trap rule: the card played onto a trap is frozen solid: nobody's card, takes nothing, can't be taken or targeted, its square out of the game (8 cards count, so 4-4 draws can happen); Reincarnation still saves it. Look: frost over the card (Media\FX_FrozenCard, added as light), ice round the creature's feet (Media\Mark_IceShackles), the model paused and lit cold blue, ice-blue owner tab with no face or gems. The practice gambler hides its trap beside its own cards. PvP protocol 7.

## 0.44.4

- fix: spell effects (frost on a trap, Banish, Execute ...) were drawn on the window itself, under the card frames, so they never showed; they're on their own layer above the cards now. Creatures page tier filter wide enough for "Legendary Hunter".

## 0.44.3

- favourites wear a ruby heart (Media\Badge_Favorite) on the Creatures page button, in the creature list and on the card. Settings: a search box over the page list; every page is built the first time you search, and every heading, option and its tip is indexed; results (option and page) replace the list, and clicking one opens its page scrolled to it with the row flashing gold.

## 0.44.2

- end-of-match sounds: quest complete (win), quest failed (loss), quest accepted (draw), stopped by 2.8 s. Forfeit button (bottom right, practice and against players; confirm first): a loss for you; your opponent sees "X forfeits the match" and the win is theirs.

## 0.44.0

- habitat scenes (Media\Scene_Habitat_Underwater / Shore / Desert / Snow / Swamp / Cave): a card's scene follows where the creature lives before its type: words at the start of a word in its name or family (shark, crab, murloc, naga, makrura -> Underwater; pirate, privateer, crocolisk -> Shore; frost, yeti -> Snow; sand, scorpid, silithid -> Desert; kobold, trogg, tunnel -> Cave; bog, mire, ooze -> Swamp), else its home zone (Tanaris, Silithus, Desolace, Badlands, Thousand Needles desert; Winterspring, Dun Morogh, Alterac snow; Swamp of Sorrows, Dustwallow, Wetlands swamp); else the type scene as before. Companions by species; heroes keep their capital.

## 0.43.3

- an opponent who wanders out of sight keeps its face: its appearance is learnt from the unit while in sight, else from its creature ID (SetCreature), kept on the creature's record, and shown in the seat and owner tabs once the live portrait is gone (a few retries if it isn't known yet).

## 0.43.2

- cards fly from the hand to their square (0.42 s, eased arc, growing from hand size to board size with a little extra mid-flight, then a 0.18 s settle); the place sound, captures, traps and Reincarnation follow the landing; the opponent's hidden card turns over in the air; clicks wait while a card is in the air. A cast spell card glides toward its target as it fades. Spell rules text (and a long name) shrinks to fit the card's panel.

## 0.43.1

- practice opponents: a random creature near you (nameplates, target, mouseover, focus; not dead, not your pet), else one from your Almanac by rank (dungeon boss > named / rare > elite > any); its name and portrait in the seat (the unit's own portrait while in sight, its appearance learnt and kept). Right-click any portrait (target, focus, party, raid, boss, players, friends): "Play Wild Gambit": a creature becomes the next practice opponent (shown in the empty seat on the pick table), a player is challenged.

## 0.43.0

- spell cards: each player's class spell is a sixth card at the end of their hand (Frame_Spell, Gem_Spell tinted by kind, Spell_<Name> painting, name and rules in the panel), face up for both; click it to cast (targeting as before), it fades from the hand once used; hover for a large view; the header spell box is gone. Shaman: Reincarnation replaces Grounding Totem (the next card of yours taken by a capture, trap, Mind Control or Pick Pocket, or removed by Banish / Polymorph / Execute, stays yours; one use; ankh by the portrait while waiting). Effects: FX_* paintings grow, turn and fade over the target (Banish, Execute, Polymorph, Divine Shield, Mind Control, frost on a trap, coins on Pick Pocket, spirits on Reincarnation); Divine Shield's bubble and Barkskin's mark painted. PvP protocol 6.

## 0.42.2

- companion cards: the pet that's out is drawn from the unit itself (model), and its appearance is learnt (a near-invisible on-screen model read back while it loads, or the card's own model) and kept for when it's dismissed and for the other player's screen; its level follows UNIT_LEVEL / UNIT_PET; right-click the pet again: "Discard its Wild Gambit card" (confirm; kills together are lost). Levels: the hero card is rebuilt from your level and Master Hunter count every time the pick table opens; a companion's level and kills update as it levels and fights.

## 0.42.0

- pick table of ten: your hero card first, then your favourites, your companions, then your strongest (no separate hero slot). Favourites: a star on the Creatures page card box (top right); up to 5 (WG.FAV_MAX), a sixth asks which to replace; starred creatures show a gold star on their card and in the Creatures list, are always on the pick table, and are three times as likely (WL.FAV_WEIGHT) to be among the four cards drawn with yours (your own hand only; the practice gambler draws evenly). Kept account-wide (wildGambit.favorites).

## 0.41.4

- add-on policy check (Blizzard UI Add-On Development Policy, 2009: free, visible code, no realm impact, no ads, no donation asks, T-rated, ToS, Blizzard's discretion): all clear. Addon messages paced to the game's per-prefix allowance (10, then about 1 a second): auction sharing 0.3 s -> 1.1 s, Almanac-player hellos 0.35 s -> 1.1 s, Wild Gambit's match whispers 0.3 s -> 1.1 s and at most 20, travel sharing 1 s -> 2 s (two channels each).

## 0.41.1

- hero art in (crest, six capital scenes, nine class medallions, paw badge). 0.41.2 the Skyborne (WoW Forever's new race: Windshaper Horde, High Order Alliance, starting on Zephras Isle): recognised by race name, their spikes lean toward Zephras Isle (its map found by name and remembered) and their scene is Scene_Hero_ZephrasIsle once painted; heroes now travel with their home scene ("hero:CLASS:Home").

## 0.41.0

- hero and companion cards. Hero: your character (name, level, race), Fought, then Hunted / Master Hunter / Epic / Legendary at 10 / 25 / 50 / 100 creatures at Master Hunter or above (WL.HeroTier); shape by class (Warrior, Paladin: front and back; Rogue, Hunter: flanks; casters even), leaning toward the race's capital; only ever the chosen card (its own slot on the pick screen, "You"); your screen shows your character's model, the opponent's their class medallion. Companions (Hunter, Warlock): right-click the pet's portrait > Add to Wild Gambit deck (or /aa gambit pet; /aa gambit pet remove Name), kept per character with its species, level and face; Fought, then by kills with it out (5 / 15 / 50 / 200, WL.PetTier); in your deck like any card (the practice gambler doesn't draw them). PvP protocol 5: heroes travel as class "hero:CLASS:Race", companions "pet:Kind"; both skip the wild-level check but keep the spike rules. Art hooks: HERO_ART (crest, capital scenes, class crests, paw badge).

## 0.40.1

- ranks: Sighted (seen, never gathered), Apprentice 1, Journeyman 5 (everything it can hold), Expert 15 (how likely each is), Artisan 50, Master 200; the creature tiers' colours and badges (Apprentice wears the profession's icon); the blue skills bar like a creature's ("9 / 15 · 6 to Expert", rolling on past Master); toasts "Expert Miner", "Journeyman Herbalist", "Artisan Angler" (chests: the rank alone). Tier counts for creatures and gathering are fixed in code (Bestiary.TIER_KILLS, Gathering.AT); Settings > Research tiers only lists them, and old saved tier settings are dropped (Store migration 4).
- the chosen card is hidden: the opponent's stays face down in their hand (no glow, no hover) until played, turning over as it lands (or at the end if never played); yours carries a stealth mark. The practice gambler hides its strongest card the same way and no longer counts yours when it plans. No protocol change (the chosen card already travels first).

## 0.40.0

- class abilities reworked into removal / protection / swap (see the rules line above). Targets glow by kind (red removal, gold protection, purple swap; Pick Pocket: your card, then theirs). A removed card shrinks and fades (Polymorph: it turns into the sheep and trots off; Execute: your card strikes first); its owner is dealt the reserve closest in spikes (lowered a tier or more if that's closer), face down with the page-turn flip; a sixth hand card closes the gaps up. Removal frees a square, so the board still ends at nine. Each spell plays its class sound (Banish: Dimensional Rift, Polymorph: the sheep, Execute, Divine Shield, Barkskin, Grounding: wind cast, Mind Control: shadow whisper, Pick Pocket: coins, Freezing Trap: trap set; the trap's snap on the catch). PvP protocol 4: three reserves travel as K 6..8 and are checked like the hand; U carries Pick Pocket's second square; a target the other screen's rules don't allow cancels the game. Tested offline: rules per spell, practice with every class, two clients ending on the same board for every pairing (including two removals).

## 0.28.1

- "Find a match" overlapped "My target" on the pick screen: it now sits above Practice (same width), clear of the challenge row.

## 0.28.0

- Find a match: a "Find a match" button on the pick screen (Stop looking to cancel; a running clock). Q|-|best goes to the guild, the group, the Almanac players met this week (whispers, from Peers:Recent) and, only while looking, a hidden realm channel AzAlmGambit (joined and left automatically, kept out of every chat tab, its notices filtered; Settings > Wild Gambit "Find a match across the realm" to turn it off). Two lookers pair up: the name that sorts first sends C|gid|q, the other accepts by itself, both set up with the card and class already chosen. Simulated pairing tested.
- card frames: a gold hairline inside the stroke from Studied; comets (sparks with a trail) running round the edge: one Mastered, two Epic, three Legendary, in the tier colour; the tier glow breathes; Epic gets the shine sweep (violet), Legendary's is faster and gold, and embers rise off Legendary cards; pick-screen cards animate too.
- polish: the turn's portrait glows; the hand that isn't playing dims; a spell's valid targets glow (cards and empty squares); the result panel is slimmer and sits low on the board so the final board shows; dead code removed; class list from the rules module.

## 0.27.0

- class abilities: "Play as" row of the nine class emblems on the pick screen (your class by default, remembered); the round's spell as a button in your header (the opponent's shown too), once per match, not using up the turn: Charge (next card wins ties), Divine Shield (a card can't be taken or touched; gold bubble + icon), Freezing Trap (hidden square; the next enemy card there is frozen and yours; only the trapper sees the mark), Pick Pocket (random hand swap), Polymorph (an enemy card becomes a sheep 1/1/1/1, sheep model), Drain Soul (up to 3 spikes from an enemy card to your neighbouring card's facing side, takes it if stronger), Mind Control (an enemy card of 8 spikes or fewer), Chain Lightning (next card's captures chain on), Shapeshift (a quarter turn, takes what it now beats). Targeting mode with hints; the practice gambler uses its spell when it pays. Rules in WildGambitLogic (WL.ABILITIES, CanTarget, Use, BotAbility; traps / shields / chains in Place); tested offline for every class.
- player against player: pick a card (click to choose) then Practice, or Challenge (name box / My target / "/aa gambit Name"). Prefix AzAlmWG: challenge popup, accept, both send best-five spikes + class + half the dice; budget = the lower best; each builds a hand and sends its five cards; every card checked (spikes = level base + tier bonus, side caps, level against the creature data) and the hand against the budget, else the game is cancelled; the dice decide who starts and Pick Pocket identically on both screens; numbered moves and spells, out of step = cancelled; Leave button; records per opponent. Two simulated clients played full games with every class pairing and ended on the same board.

## 0.26.0

- spikes 50% bigger (18 px), 42 px between slots, 30 px board margin; the window on the Almanac's dark panel (LIST_BG); the header like the player frame: round portrait (yours; the gambler wears one of its deck's creatures) in the follower portrait ring, the round's class emblem round in a class-coloured ring at its bottom right, name and cards owned; the tier name on each card is now the tier's icon (the Creatures page icons; beast upgrade stones for Epic / Legendary) in a tier-coloured ring; more ornament by tier: covenant sanctum borders round the name plate (Kyrian Mastered, Night Fae Epic, Venthyr Legendary) and gryphons at a Legendary's foot; captures play out: the new card lunges at the loser (attack animation), the loser is knocked back and squashed with a shake (flinch animation), flashes and turns colour at the hit, one capture after another; card tooltips (level, tier, spikes per side).

## 0.25.2

- the pick screen showed two blank white circles in the header (no game yet): now your emblem and name, and "An empty seat" with a question mark across the table.

## 0.25.1

- from the first screenshots: board cards were zoomed onto the creature's chest (a model's camera doesn't follow a scale change): models now show the whole creature and are refitted after every move between hand, board and hover; the tier glow was a big coloured block bleeding over the roots: tighter (9 px) and fainter; round gems are now masked round (diamonds stay turned squares); the fireflies were square (bags-glow-white): soft round dots; the turn line overlapped the opponent's score: moved under the board; spikes 12 px (were 10) with a 28 px gap between slots.

## 0.25.0

- prototype (practice only): QoL/WildGambitLogic.lua (card spikes, hands and spike budget, captures, the practice bot; tested offline: totals always match, symmetric shapes stay symmetric, bot beats a sloppier bot ~72%) and QoL/WildGambit.lua (the table). Cards: profession card face by creature type, 3D creature (or type icon), name banner, tier tag, tier frame (stroke -> quest-log frame + filigree -> diamond corners -> metal corners + sparkles -> gold winged dragon + shine sweep), bags-glow in the tier colour, gold arrowhead spikes on the edges, class-coloured gems (round = you, diamond = opponent). Board: the druid talent painting cropped and dimmed, bark-and-moss roots, four herb blossoms, mossy slots, fireflies, forest ambience. Pick screen (your 10 best, or let fate choose); practice opponent from your own collection at 80% of your best-5 budget; hover a hand card to enlarge it; Gambit won / lost / stalemate with a practice record. /aa gambit, minimap menu, Settings > Fun > Wild Gambit. Not yet: class abilities, playing other Almanac players.

## 0.24.2

- /aa atlascheck tests ~400 candidate atlases and texture files (quality card borders, vine / covenant frames, class and forest paintings, herb / nature icons, Darkmoon card icons) and saves AzerothAlmanacDB.atlascheck. Run in game: 127 of 465 atlases, 60 of 64 files (quality borders loottoast/auctionhouse/bags-glow in all colours, all nine talent-background-<class> and UI-Character-Info-<Class>-BG paintings, Profession-background-card-Herbalism/Skinning/Leatherworking/Alchemy, covenant sanctum borders, Boss-Gold-Winged / Rare-Silver dragons, gryphon and wyvern, classicon-* for all nine, talents-arrow-head/line yellow; no vine frames).

## 0.24.1

- Characters list rows roomier: 60 px rows (was 50), portrait kept at 46, 4 px between the name / race-class / money lines (was 2).

## 0.24.0

- **Almanac players and the update quest**

## 0.23.2

- / 0.23.3: player cards kept plain (CARD_PLAIN: no frame, background or stage painting; the models stand on the window), models 5 px higher.

## 0.23.1

- **Gentler mouse-wheel scrolling**

## 0.23.0

- **Creatures page: dragons, Sighted colour, counts, rename**

## 0.22.9

- Bestiary page icon is now Icon_UpgradeStone_Beast_Legendary (falls back to the old creature icon). Creature toasts and fallbacks keep the old icon.

## 0.22.8

- in combat the aggro glow drew a big red box round the player frame (a 2 px rectangle on the 232x100 frame, much bigger than its 198x71 picture). On portrait frames (player, party) the glow is now the game's own status glow (UI-HUD-UnitFrame-Player-PortraitOn-Status, or the frame atlas + "-Status") laid over the frame's picture and tinted by threat level; other frames (raid) keep the rectangle.

## 0.22.7

- the border too. The slot is part of the player frame's single texture (UI-HUD-UnitFrame-Player-PortraitOn, 198x71); from the /aa art layout snapshot the health bar sits at x 68..192, y 26.5..45.5 in it. Cut in three (right end with the frame edge, a stretched middle, the right end mirrored for the left since the real left end meets the portrait ring), scaled to the bar's height, drawn under the bar like the game does. Cut numbers in SLOT (HealAssist.lua) if it needs nudging.

## 0.22.6

- **Healer Assist: the player frame's health bar**

## 0.22.5

- polish: bigger window portrait (74 px murloc face) in the classic elite target frame's gold dragon (UI-TargetingFrame-Elite, cut and mirrored to wrap the window's outside); player cards and board in the quest page's map-box look (dark list background, QuestLog-frame border, filigree); QuestLog-frame-devider dividers in the side panel; "VS" in the game's big Friz font (Morpheus made "vs" read "V8").

## 0.22.4

- live test got stuck: the game started on the accepting side but the challenger never saw the accept. Cause: Forever surnames ("Zipporah Olaris", typed "Zipporah-Olaris"): the Almanac squashed spaces and added a realm, so the sender name never matched the opponent. Names are now sent exactly as given and compared loosely (case / spaces / hyphens ignored, own realm dropped, a bare first name matches the same first name with a surname). A new challenge to / from the same player, or once the other side is quiet, replaces the stuck game; `/aa mtt leave` ends one with no record. Simulated with surname names in both sender formats.

## 0.22.3

- `/aa version` prints the loaded version.

## 0.22.2

- the game writes an offline Name-Realm as "Name Realm" in its "No player named" message, so offline players weren't caught and the challenge sat "waiting" (blocking new ones). Now matched without spaces / hyphens; a new challenge also replaces one still waiting. Realm part capitalised. (The "PingZipporah" challenge came from 0.22.0 still being loaded: no /reload after the update.)

## 0.22.1

- first live test, the challenge got no answer (and "the game blocked UNKNOWN() while meeting townsfolk"). Added `/aa mtt ping Name` (asks the other Almanac to answer with its version and whether it takes challenges), `/aa mtt debug` (prints every message sent / received), and a chat warning when the game refuses to send (SendAddonMessage result code). Townsfolk: CheckInteractDistance no longer called in combat (restricted there).

## 0.22.0

- **Murloc Tac Toe**

## 0.21.4

- **Talent Planner: unspent counter and native node look**

## 0.21.3

- most quests had no map: they were read from the quest log (taken before the Almanac, or never seen at the giver), so they have no giver / ender position (only 22 of the records do). The map now falls back to: people the quest names whom you've met (QuestDB starters / enders, their recorded positions, pinned as "!" / "?"), then the zone named by its quest log heading (`rec.cat`, matched to your discovered zones by name), then where you killed its targets.

## 0.21.2

- **Quest map at the top of the quest page**

## 0.21.1

- **Quest page layout like the quest log**

## 0.21.0

- **Talent Planner**

## 0.20.5

- **/aa whatis saves its output**

## 0.20.4

- **Item tooltip card on the Items page**

## 0.20.3

- **Gear tab: class emblem for other characters**

## 0.20.2

- **Taller window**

## 0.20.1

- **Almanac and Journal icon**

## 0.20.0

- **Quest log look on more lists**

## 0.19.9

- polish from a side-by-side with the quest log: headings were blank (the heading box frame drew over the row's text; now box, then words on a layer above); everything scaled down (quest titles GameFontNormal, headings GameFontHighlightMedium, rows 24 px, no spacer rows before headings: `W.List{ spacers = false }`); icons on the log's round button `UI-QuestPoi-QuestNumber` (captured) with "?" when ready to turn in (C_QuestLog.IsComplete), "..." in progress, the log's yellow tick `QuestLog-icon-checkmark-yellow` for done, "!" offered, red cross abandoned.

## 0.19.8

- **Quests list in the quest log's look**

## 0.19.7

- **Recipe-list row highlights**

## 0.19.6

- **Page order, Townsfolk renamed People**

## 0.19.5

- **Skinning by what you skinned**

## 0.19.4

- **Townsfolk icon**

## 0.19.3

- **Places icon**

## 0.19.2

- **Mastered icon**

## 0.19.1

- **Chest icon, second pick**

## 0.19.0

- **Characters tab shows your portrait**

## 0.18.9

- **Quests icon**

## 0.18.8

- **Bestiary icon**

## 0.18.7

- **Dungeons icon**

## 0.18.6

- **Items icon**

## 0.18.5

- **Gathering icon**

## 0.18.4

- **Best vendor reward at quest turn-in**

## 0.18.3

- **Dark panel background**

## 0.18.2

- the page still came up empty: Build stopped at the tab strip because `W.Detail` never exposed its scroll frame (`detail.scroll` was nil). Now `holder.scroll` is set.

## 0.18.1

- error on first open ("attempt to index upvalue 'invScroll'"): the search box fired a change while the page was still being built, so Refresh ran before the tabs and inventory scroll existed. Refresh now waits for Build to finish, and the search only redraws when its text really changes.

## 0.18.0

- **My Characters merged into Characters**

## 0.17.9

- Battered Chest showed Ice Cold Milk (its most common drop). Chests and objects that give more than one kind of item now always use the chest icon (page portrait, list row, Show on map pin, world map / minimap pins); one-item objects (Farm Chicken Egg) still show their item.

## 0.17.8

- **Chest icon**

## 0.17.5

- **World map pins not showing**

## 0.17.4

- **My Characters profession bars**

## 0.17.3

- **Dressing room on Ctrl-click**

## 0.17.2

- in game the button was not visible; at a fixed 225° it sat under the Almanac's button (moved to ~235°). Now first placed 55° clockwise of wherever the Almanac button is, drawn one level above it, `/aa nodes button` resets it, and a failure to build it prints in chat.

## 0.17.1

- **Gathering toggle on the minimap**

## 0.17.0

- **Spell ranks**

## 0.16.1

- **Bug check and polish**

## 0.16.0

- **Gathering nodes on the maps**

## 0.15.0

- **Toast tiers**

## 0.14.0

- **Overview: the adventurer's journal**
- **Gathering and fishing**

## 0.13.0

- **NPCs and flight paths**

## 0.11.0

- **Townsfolk on the world map**

## 0.10.1

- **My Characters look across the Almanac**

## 0.10.0

- **Quality-of-life helpers and the settings window**

## 0.9.0

- **Dungeons and raids**

## 0.7.0

- **Trainers: spells and recipes**

## 0.6.0

- **Zones and exploration**

## 0.5.0

- **Quests**

## 0.4.0

- **Items**
- **Merchants**

## 0.3.0

- **Hidden database (build tools)**

## 0.2.1

- **Bestiary – creatures**
- plurals ("1 kill", "once", "twice"), debuff merged into its ability line, critter icon (wolf, grey).

## 0.1.1

- **Foundation**
- fixed: tainting `StaticPopupDialogs` (caused the "blocked" popup), missing icon files (candidate lists), continents recorded as zones (skipped + cleaned up), class-colored names on parchment, "also found by", scrollbars only when needed. Blocked-action recorder added (`/aa stats`).
