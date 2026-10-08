# In-game test checklist

Everything built but not yet confirmed in game, grouped by area. Tick a box once it works. If it doesn't, open a GitHub issue labelled `bug` and note the issue number next to the item.

Before testing: install the latest build, note the version (AddOns list), and copy any red Lua error text exactly.

Suggested order: Wild Gambit first (it changes the most), then the Almanac pages, then the quality-of-life helpers.

## Unreleased (/reload)

- [ ] Follow button, footsteps (full game restart): target a friendly player: a pair of gold footprints at the target frame's top right, no glow until you click: then the game prints "Following <name>.", the prints glow and breathe, and the tooltip says "Following <name>"; move (or /follow another way) and the game prints "You stop following <name>." and the glow stops; targeting someone else while following shows no glow on them; clicking right on the prints follows (and shows the tooltip), a click just outside them (about a sixth of their size) does too, and the portrait next to them still targets as usual (the margin is FB.HIT_GROW, 0.15); windows opened over the button (Almanac, a mini game, the bags) still cover it; the mouse-over highlight is the prints' shape; a far-off or enemy target greys them; Settings > Follow button > Icon shows "Footsteps" while the prints are on the button (also after a /reload), and picking Winged boot sticks across a /reload; Footsteps, Winged boot and Running cat all work and switch back and forth cleanly (the framed ones get their frame back), Size changes the footsteps too; Reset position works.
- [ ] Follow button: target a friendly player, then open the Almanac, a mini game or your bags over the target frame: the window covers the button (it doesn't float on top); with the windows closed it still shows, greys out and follows as before, also in combat.

## 0.66.3 (/reload; the Murloc Tac Toe items marked "full game restart" need one)

- [ ] Murloc Tac Toe, new look (`/reload`): the dark window background; the wooden buttons (text fits: "Challenge", "My target", "Practice game", "Resign", "Sound: on"); the corner icon in the gold dragon frame with a murloc head, not a black circle, and the byline beside it; the VS shield.
- [ ] Murloc Tac Toe board (full game restart): the nine sockets under the nine cells (a piece sits in the middle of its socket, faces not cut off or overlapping the rim), the cards as wide as the board, the carved side panel with nothing overlapping (heading, name box, three buttons, titles, eight rival rows, Resign and Sound at the bottom), the waiting and game-over pop-ups inside their panels with the buttons fitting, the winning line and bursts still lined up with the cells, the window on your screen (837 x 687).
- [ ] A win to remember (`/reload`): win a game: the line draws, then fireflies burst up from the three squares and across the board (lots on a win, a few when you lose, none on a draw), your card (or theirs, if they won) glows gold for a few seconds, nothing stays after the next game starts; not too busy over the pieces.
- [ ] Wooden button click (`/reload`): every wooden button in Wild Gambit, Gem Match and Murloc Tac Toe makes the same soft click, and it is silent when that game's Sound is off (Wild Gambit: its Sound setting; Gem Match and Murloc Tac Toe: the Sound button); no double clicks on a button that also plays its own sound.
- [ ] Murloc Tac Toe, whole creatures (`/reload`): on the cards every champion shows from feet to head (none cut off at the top) with the feet on the stump, and not so small that it looks lost; the same for the pieces in the sockets and the half see-through one under the mouse; a champion that is still wrong: `/aa mtt cam <champion> <card zoom> [piece zoom]` (bigger shows more; send me the numbers you settle on); the heads don't run into the title bar; the byline is bottom left.
- [ ] Cut-out art edges (full game restart): the rope dividers in Gem Match and Murloc Tac Toe have no magenta in their loops; the gems in the Gem Match game-over scatter, the pause cover and the empty best-scores list still have their highlights (no dark holes in the purple gems); the pouch, plaque, ribbons, arrows, icon and stump have no pink fringe.
- [ ] Murloc Tac Toe, choosing after a game (`/reload`): finish a game, then change your champion with the arrows (beside your creature, or in the Champions block): the card changes at once, you hear the new champion's sound (silent if it has none), and the next game or rematch plays as it; the same for the computer's pick after a practice game (Random picks one).
- [ ] Murloc Tac Toe music (`/reload`): opening the window starts one of the three jungle tracks (if your game's music is on) and the zone music stops; the next track follows when one ends (no gap, no overlap; the long one is about 99 s), never the same twice running; closing the window (or Music: off, or `/aa mtt music`) stops it and the game's zone music comes back; the Sound and Music buttons side by side fit their text.
- [ ] Murloc Tac Toe stumps and pickers (full game restart for the stump): each creature stands on its stump with its feet on the top and the nameplate over the stump's foot (the model's feet line up with the top; any creature that sinks or floats), no hard rectangle of water round the stump; the Champions block: the You row and the Computer row change the champions (arrows only between games; in a game the rows show who is playing), Random for the computer picks a different one each practice game, the opponent card shows the computer's pick before a game; every name fits between the arrows ("Plagued Cockroaches" is the longest); the side panel has no overlaps (Rivals shows 5 rows now); the window fits your screen (723 high).
- [ ] Murloc Tac Toe, champions as pieces (`/reload`): each placed piece is the champion's model standing in its socket (size right for the socket, not cut off at the top, facing in; try each champion: the slime, the Sprite Darter, the cat and the cockroach are very different sizes, and `SetCamDistanceScale` is `camScale` on a champion if one needs adjusting), it acts when placed, a half see-through copy follows the mouse over empty sockets on your turn, the winner's pieces cheer and the loser's slump, nothing left standing after a new game; nine models and two cards: any slowdown? Nameplates: the creature stands behind the carved plate, name fits on it (long names), the champion's name and the record under it, the gem lights on whoever's turn it is (and nowhere after the game); voices: `/aa mtt sound <id>` plays, `/aa mtt voice <champion> place <ids>` then place a piece; ambience: `/aa mtt ambient add <ids>` and wait up to a minute.
- [ ] Murloc Tac Toe, the Hallow's End champions (the Sinister Squashling, the Bombay Cat and the Plagued Cockroach): `/aa mtt champions` lists them as "[Hallow's End only]" with what it found (the Squashling and the roach are found by their creature IDs, 23909 and 271913, a few seconds after login; the Bombay cat from the pet among your companions, which you must own: if it doesn't appear, target a Bombay cat and `/aa mtt champion bombay`); `/aa mtt season` makes them choosable out of season (toggle back afterwards); they join the arrows only in season (18 Oct - 1 Nov) or with that toggle; a game against someone playing one shows it for you too whatever the date; Wild Gambit's Hallow's End board still switches on the same dates (the calendar check moved to `WindowUtil.lua`).
- [ ] Murloc Tac Toe, no repeats: placing many pieces as a champion with several sounds (murloc, gnoll, slime, Sprite Darter, Bombay, Squashling) never plays the same one twice running; the cockroach, with one sound, can't help it;
- [ ] Murloc Tac Toe, the Plagued Cockroach's sound: playing as it, every piece, win and loss makes the same crunch; say if it gets tiresome and we can drop it for placing pieces;
- [ ] Murloc Tac Toe, the Sinister Squashling's sounds: playing as it, each piece, a win and a loss squelch (four place sounds, two win, two lose); they are ambient decay noises, so say if any is too quiet, long or odd;
- [ ] Murloc Tac Toe, the Bombay Cat's sounds: playing as the cat, each piece, a win and a loss meow (the three place sounds, then 04, then 10); if one sounds wrong for its moment, swap it with `/aa mtt voice`;
- [ ] Murloc Tac Toe, the Hallow's End look: with `/aa mtt season` on (or 18 Oct - 1 Nov) the board is the dark pumpkin one, its nine cells line up with the pieces exactly as on the swamp board, the dividers in the side panel are bat-and-pumpkin ones, the pumpkin heap sits under the Sound / Music buttons without touching them and the drifting lights are orange; toggling it off puts the swamp look back at once;
- [ ] Murloc Tac Toe polish (`/reload`): the status ribbon (text fits on it, also the long notices, and it hides when there is no text); the cards, the VS shield and the arrows no longer overlap; the idle "Mrgl mrgl!" ribbon with the button under it; fireflies drifting behind the pieces (not too bright); the carved rings round the pieces and the small faces in their tints; a win: the glowing line draws across, a light leads it and stays pulsing at the end, the winning cells glow softly; the hover glow on an empty cell.
- [ ] Murloc Tac Toe art (full game restart): the murloc badge sits centred in the gold dragon frame (not cut off, no square corners showing); the swamp ribbon on the game-over panel with the result readable in gold on it ("Mrglglglgl!" and the others), the champion-coloured line under it, the buttons below; the two mossy arrows beside your creature (size, the glow on hover, a dim press, hidden during a game).
- [ ] Murloc Tac Toe champions: the two arrows beside your creature (only while no game is on) change the creature and the name under it; after login (a few seconds) a message says the Excitable Slimes and the Sprite Darters are ready, and both join the cycle (if one doesn't, `/aa mtt champions` says why; the Sprite Darter's model has been confirmed in game); a challenge between two of you shows each other's champion; a game against someone on the old version still works (murloc against gnoll); the practice game plays a different champion; a rematch keeps both champions; the round faces (are they still black? say so).
- [ ] Wild Gambit: click your spell card (one that needs a target): the cursor gets a blue glow with drifting sparkles, also when it leaves the window; it goes when the spell lands, when you click the card again to put it back, and when the game ends or the window closes. A spell with no target (cast at once) shows no glow. Spell chosen, then click a card in your hand: the spell is put back (glow gone, its card no longer aimed) and that card is the held one, ready for a square. The glow sits above every window and never blocks clicks.

## 0.66.1 (/reload)

- [ ] Outside after updating: the Molten Elemental journal line now shows Ragefire Chasm (not Orgrimmar).
- [ ] Loot a new dungeon creature, leave: its journal line shows the dungeon and the spot of the corpse.

## 0.66.0 (/reload)

- [ ] In RFC, loot a trash mob you've never recorded: it appears in Creatures as "Unknown creature #ID" with 1 kill and its loot. No alert yet.
- [ ] Leave the dungeon: within a few seconds each unknown creature gets its name, a journal line and a discovery alert.
- [ ] Loot Oggleflint (or another boss), then leave: one Oggleflint record (not two) with the right kills, and the Dungeons page opens it. Killing and looting a boss counts one kill, not two.
- [ ] Grouped with another 0.66.0 Almanac: a corpse they loot inside counts as a kill for you, and the creature appears for you as well.

## 0.65.4 (/reload)

- [ ] After login: Oggleflint (and any other boss killed inside a dungeon) shows on the Creatures page with your kills, and its row on the Dungeons page opens it in Creatures.
- [ ] Kill a dungeon boss: its Creatures record appears (or its kills go up), with no duplicate boss row on the Dungeons page and no Lua error.
- [ ] Party pet frames on: the pet's Healer Assist icons line up under its owner's icons, and there's no green paw. With pet frames off, the indented line under the owner still has its paw.

## 0.65.3 (/reload)

- [ ] Healer Assist "Beside the portraits: right": the icons' top lines up with the bottom of the name plate (party and your own frame).
- [ ] With "Group members' pets" on: a party member's pet gets an indented line under its owner's icons; your own pet's icons stay on your pet frame.

## 0.65.2 (/reload)

- [ ] In a party, Healer Assist "Beside the portraits": each party member's icons sit under (or right of) their party portrait, not in the window. `/aa heal debug` shows a frame for each member.

## 0.65.1 (/reload)

- [ ] In combat with enemy nameplates showing, open Wild Gambit from the minimap menu: no Lua error; the lobby offers a creature (from your Almanac if none nearby can be read).

## 0.65.0 (full game restart: new Gem Match textures)

- [ ] Gem Match: the painted board, side panel, game-over panel, hint, shards and group/friend scores (the full list is under "Gem Match" in `STATUS.md`, "Needs checking in game first").
- [ ] Wild Gambit's buttons, headings and corner icon look exactly as before (their code now lives in `WindowUtil.lua`).

## 0.64.2 (/reload)

- [ ] Minimap button right-click: "Mini Games" plate, then Wild Gambit, Murloc Tac Toe, Gem Match, a thin rule, Settings. The plate isn't clickable; other dropdown menus look as before.

## 0.64.1 (/reload)

- [ ] Friendly nameplates off in the game's options: walk up to a vendor or quest giver: no name or health bar over them. The gathering highlight still sparkles on herbs and ore.
- [ ] Friendly nameplates on: NPC plates as normal. The new checkbox (Gathering > Game display) shows them even with friendly nameplates off.

## 0.64.0 batch (/reload)

- [ ] Wild Gambit looks the same as before: board, card frames, scenes, the ankh by the portrait after Reincarnation.
- [ ] A card of a creature you haven't killed: no skull strip.
- [ ] Press Escape mid-game: the Wild Gambit bar appears; clicking it brings the game back.
- [ ] Lobby after a game: no "Your card plays at full strength..." line.
- [ ] Minimap button right-click: every page listed, each opens.
- [ ] Places: a trainer opens their People page. Zone "visits" count arrivals only.
- [ ] Settings > General > Reset window positions also moves the alerts and the gathering button back.
- [ ] `/aa whatis` without debug says it's a developer command; after `/aa debug` it works.
- [ ] Minimap gathering pins still show and follow you; Healer Assist in a raid still keeps up.

## 0.63.0 batch (/reload)

- [ ] "This character only": on an alt, meet a creature your main already knows: alert and journal line for the alt. Gathering pins and people on the map show only the alt's finds.
- [ ] Milestones on an alt in "This character only": the journal's list is the alt's; reaching one says "(this character)".
- [ ] Settings profiles: switch profile, check a few choices changed and Wild Gambit's tutorial isn't offered again; Copy from... keeps the Healer Assist window where it was.
- [ ] A brand-new character: Almanac and helper windows open in their default spots.
- [ ] Healer Assist in a group fight: with "Flash the screen edges red" on, the edges glow when someone under attack drops below the danger level; buttons out of range grey out in combat; the red throb starts at your Danger level.
- [ ] Healer Assist panel with pets on and few rows: the most urgent people stay; a pet's line only joins its own master.
- [ ] Threat: "Pulling aggro at %" stops at 100 and warns.
- [ ] Gathering > Search direction "The game's own": still selected after /reload.
- [ ] `/aa help`, `/aa gathering`, `/aa people check` (talking to an NPC), `/aa foo` (says unknown, then the list).

## 0.62.0 batch (/reload)

- [ ] Pick note reads "...unless the hands would end too uneven: then it may be downgraded."
- [ ] Practice: start a game, then `/aa gambit new` (or Play Wild Gambit on a creature): the forfeit question appears; Yes goes to the lobby with no result banner left over; No keeps the game.
- [ ] Tutorial: tuck the window away (combat or "-") mid-script, bring it back: the coach carries on. Skip still works. After finishing, the button reads "Play for real" and opens the pick screen against a creature.
- [ ] Play the last card and press Escape at once: the game still ends and counts (record in the lobby).
- [ ] Player match (both 0.62.0): plays through as before; no chat spam; a pick downgraded on one screen shows the same on the other.
- [ ] Player match: one player goes offline mid-game: after a minute the other sees the "Nothing from ..." note; End shows "Cancelled · Not counted"; the record doesn't change.
- [ ] Challenge a player on 0.61.x: you're told their version; they're told yours.
- [ ] Start a practice game in combat: it's paused until combat ends.
- [ ] Merchant: buy something with the window open: the merchant's "seen" count doesn't go up per purchase.
- [ ] Settings > reset the Almanac: your settings profile is still selected after the reload.
- [ ] Quest Targeter off: no change in frame rate with many nameplates (and counts still right when on).

## 0.61.0 batch (/reload)

- [ ] Pick a Legendary with many spikes: in the match it keeps its tier and spikes; weakened supporting cards show the red down arrow.
- [ ] Pick note under "Choose a card" once a card is picked (not with Let fate decide).
- [ ] Player match (both 0.61.0): both picks at full strength; the arrows match on both screens.
- [ ] Places: outline stronger; hovering places in the list outlines each on the map, leaving restores the selected one.

## 0.60.0 batch (/reload)

- [ ] Toasts: "Almanac" in red with the small icon at the top right, readable over the rim, not covering the title.
- [ ] Kill strip on all six tiers (Poor .. Legendary): skull + number centred on the strip between art and panel; a Sighted card shows 0; big numbers as 1.2k.
- [ ] Readable on hand cards, board, pick table, the close look and the Creatures page card; hidden on the hero, a sheep and face-down cards.
- [ ] Player match (both on 0.60.0): the opponent's cards show their kill counts.

## 0.59.0 batch (/reload)

- [ ] Settings > General > Settings profile shows Shared; picking This character asks, reloads, and keeps the same settings (a copy).
- [ ] Change something (e.g. Healer Assist off) on one character; log another character on Shared: it's unchanged there.
- [ ] Window positions (Almanac, settings, Healer Assist, threat meter, flight bar, minimap button) are per character.
- [ ] New profile..., Copy from..., Delete this profile work; deleting returns to Shared.
- [ ] Nothing recorded (creatures, prices, flight times, bags) changes when switching.

## 0.58.0 batch (/reload is enough)

- [ ] Settings > General > Almanac shows: switching to This character only filters Creatures, Items, Quests, Places, People, Gathering, Journal; the title shows the character; switching back restores everything.
- [ ] Character mode: creature tiers and kills count only this character's kills since 0.58.0; Wild Gambit pick table and cards follow.
- [ ] Minimap gathering pins smaller; the size stepper goes to 4.

## 0.57.0 batch — full game restart (new textures)

- [ ] Places: zones indented under continents, places further in.
- [ ] Zone rows show "done/total"; zone page Exploration section lists areas still to find (needs the client's exploration achievements; if they're missing, rows show the place count as before).
- [ ] "Fully explored" alert when the last area of a zone is found.
- [ ] Creature abilities: "x - y per hit" / "n over t sec" from tooltips; melee per hit after a kill; per-fight total in the tooltip.
- [ ] Minimap button menu icons: Places art, your portrait, murloc chihuahua, Wild Gambit cards.
- [ ] Highlight colours: herbs green, ore white, chests red, quests gold.
- [ ] With Find Herbs on, herb pins on the minimap are hollow rings and the game's dot shows inside; turning tracking off restores them (within a second).

## 0.56.0 batch — full game restart (new mesh texture)

- [ ] Healer Assist window: mesh background and gold border; Window opacity changes it; "Beside the portraits" still places buttons by the party frames.
- [ ] Buttons: faint when not needed, full + yellow throb when recommended, red throb under 30% (test with /aa heal test, and in combat).
- [ ] Pets indented under their master in the window, with the joining line.
- [ ] Threat meter and flight bar in the mesh box; their opacity settings work.
- [ ] People: a merchant shows "As a merchant" with standing and stock; no Merchants tab; links from Items / Places / Journal open People; Spells & Recipes tab name.
- [ ] Places: continents fold; zones and places nested; a place's page shows the zone map with the place outlined in gold (e.g. Mirror Lake in Elwynn), else a pin.

## 0.55.0 batch — full game restart (new icon textures)

- [ ] Side tabs show the eight painted icons, crisp at tab size; Characters no longer shows your portrait.
- [ ] Creatures page: card grows 30% on hover (over the page, not clipped), shrinks back; no tooltip; drag to turn still works.
- [ ] Faction crest on a guard / faction NPC (portrait bottom right, list row, card art) after seeing it again.
- [ ] Tier rings thinner (list rows, detail badge, filter button, Progression page).
- [ ] Quests opens on "In your quest log"; ! opens the game's quest log at the quest; Share works in a group, greyed solo.
- [ ] Settings > Records > Print: summary lines only; Clear blocked log works.
- [ ] Quest Targeter skips mobs fighting other players and tagged mobs; still targets your own in combat.
- [ ] Gathering settings show the new defaults; direction dropdown reads whole.

## Pick screen rework (0.54.0, Asia's branch) — needs a full game restart (new textures)

- [ ] Goblin dealer button: bottom right over Begin, clear of the last card; hover glow, press dip, rocking and pulse while dealing; "Deal a new hand" / "Dealing..." caption plank fits.
- [ ] Dealer voice lines (550816 / 550811 / 550810): right lines, audible against the card sounds, never the same twice running, silent with sound off. They now also play on the opening deal: check that isn't too much.
- [ ] The opening shuffle (riffle animation) runs at the dealer's new spot: the two halves split and merge inside the felt, cards deal out cleanly.
- [ ] Begin: size, lettering, breathing glow, light streak inside the plank, sparkles not too busy.
- [ ] Back arrow: painted, ringless, larger; hover and press; goes back to the opponent screen.
- [ ] Coin tray under each hand: ends not distorted, cards sit inside it.
- [ ] "Choose a card" / "Choose your class" headings: lettering, rules and diamonds; class heading centred over the rings; long online messages still fit.
- [ ] Your spell card: sits on the felt, enlarges on hover, tooltip beside it.
- [ ] Corner icon in the gold dragon ring: centred, nothing cut off.
- [ ] Aquatic creatures (murlocs, School of Fish, sharks, turtles) on the underwater scene.

## Progression page (0.53.0) ✅ confirmed in game 0.53.1

- [x] `/aa settings progression` opens the page (sidebar: Progression); `/aa settings tiers` still works.
- [x] Creatures and Gathering ladders: badges in their coloured rings, the joining line shades between tiers, no text overlapping between rows, numbers right.
- [x] Mini cards show the tier frames with the spike numbers readable.
- [x] Wild Gambit formula boxes and the six level-30 cards fit the width; tier names under the cards don't overlap.
- [x] Your progress: the counts match the Creatures and Gathering pages; hovering a badge names the tier; the hero line is right.

## 69. Wild Gambit, a creature card game (design agreed 2026-10-05; prototype 0.25.0)

- [ ] 0.24.2: /aa atlascheck tests ~400 candidate atlases and texture files (quality card borders, vine / covenant frames, class and forest paintings, herb / nature icons, Darkmoon card icons) and saves AzerothAlmanacDB.atlascheck. Run in game: 127 of 465 atlases, 60 of 64 files (quality borders loottoast/auctionhouse/bags-glow in all colours, all nine talent-background-<class> and UI-Character-Info-<Class>-BG paintings, Profession-background-card-Herbalism/Skinning/Leatherworking/Alchemy, covenant sanctum borders, Boss-Gold-Winged / Rare-Silver dragons, gryphon and wyvern, classicon-* for all nine, talents-arrow-head/line yellow; no vine frames).
- [ ] 0.25.0 prototype (practice only): QoL/WildGambitLogic.lua (card spikes, hands and spike budget, captures, the practice bot; tested offline: totals always match, symmetric shapes stay symmetric, bot beats a sloppier bot ~72%) and QoL/WildGambit.lua (the table). Cards: profession card face by creature type, 3D creature (or type icon), name banner, tier tag, tier frame (stroke -> quest-log frame + filigree -> diamond corners -> metal corners + sparkles -> gold winged dragon + shine sweep), bags-glow in the tier colour, gold arrowhead spikes on the edges, class-coloured gems (round = you, diamond = opponent). Board: the druid talent painting cropped and dimmed, bark-and-moss roots, four herb blossoms, mossy slots, fireflies, forest ambience. Pick screen (your 10 best, or let fate choose); practice opponent from your own collection at 80% of your best-5 budget; hover a hand card to enlarge it; Gambit won / lost / stalemate with a practice record. /aa gambit, minimap menu, Settings > Fun > Wild Gambit. Not yet: class abilities, playing other Almanac players.
- [ ] 0.25.1 from the first screenshots: board cards were zoomed onto the creature's chest (a model's camera doesn't follow a scale change): models now show the whole creature and are refitted after every move between hand, board and hover; the tier glow was a big coloured block bleeding over the roots: tighter (9 px) and fainter; round gems are now masked round (diamonds stay turned squares); the fireflies were square (bags-glow-white): soft round dots; the turn line overlapped the opponent's score: moved under the board; spikes 12 px (were 10) with a 28 px gap between slots.
- [ ] 0.25.2: the pick screen showed two blank white circles in the header (no game yet): now your emblem and name, and "An empty seat" with a question mark across the table.
- [ ] 0.26.0: spikes 50% bigger (18 px), 42 px between slots, 30 px board margin; the window on the Almanac's dark panel (LIST_BG); the header like the player frame: round portrait (yours; the gambler wears one of its deck's creatures) in the follower portrait ring, the round's class emblem round in a class-coloured ring at its bottom right, name and cards owned; the tier name on each card is now the tier's icon (the Creatures page icons; beast upgrade stones for Epic / Legendary) in a tier-coloured ring; more ornament by tier: covenant sanctum borders round the name plate (Kyrian Mastered, Night Fae Epic, Venthyr Legendary) and gryphons at a Legendary's foot; captures play out: the new card lunges at the loser (attack animation), the loser is knocked back and squashed with a shake (flinch animation), flashes and turns colour at the hit, one capture after another; card tooltips (level, tier, spikes per side).
- [ ] 0.27.0 class abilities: "Play as" row of the nine class emblems on the pick screen (your class by default, remembered); the round's spell as a button in your header (the opponent's shown too), once per match, not using up the turn: Charge (next card wins ties), Divine Shield (a card can't be taken or touched; gold bubble + icon), Freezing Trap (hidden square; the next enemy card there is frozen and yours; only the trapper sees the mark), Pick Pocket (random hand swap), Polymorph (an enemy card becomes a sheep 1/1/1/1, sheep model), Drain Soul (up to 3 spikes from an enemy card to your neighbouring card's facing side, takes it if stronger), Mind Control (an enemy card of 8 spikes or fewer), Chain Lightning (next card's captures chain on), Shapeshift (a quarter turn, takes what it now beats). Targeting mode with hints; the practice gambler uses its spell when it pays. Rules in WildGambitLogic (WL.ABILITIES, CanTarget, Use, BotAbility; traps / shields / chains in Place); tested offline for every class.
- [ ] 0.27.0 player against player: pick a card (click to choose) then Practice, or Challenge (name box / My target / "/aa gambit Name"). Prefix AzAlmWG: challenge popup, accept, both send best-five spikes + class + half the dice; budget = the lower best; each builds a hand and sends its five cards; every card checked (spikes = level base + tier bonus, side caps, level against the creature data) and the hand against the budget, else the game is cancelled; the dice decide who starts and Pick Pocket identically on both screens; numbered moves and spells, out of step = cancelled; Leave button; records per opponent. Two simulated clients played full games with every class pairing and ended on the same board.
- [ ] 0.28.0 Find a match: a "Find a match" button on the pick screen (Stop looking to cancel; a running clock). Q|-|best goes to the guild, the group, the Almanac players met this week (whispers, from Peers:Recent) and, only while looking, a hidden realm channel AzAlmGambit (joined and left automatically, kept out of every chat tab, its notices filtered; Settings > Wild Gambit "Find a match across the realm" to turn it off). Two lookers pair up: the name that sorts first sends C|gid|q, the other accepts by itself, both set up with the card and class already chosen. Simulated pairing tested.
- [ ] 0.28.0 card frames: a gold hairline inside the stroke from Studied; comets (sparks with a trail) running round the edge: one Mastered, two Epic, three Legendary, in the tier colour; the tier glow breathes; Epic gets the shine sweep (violet), Legendary's is faster and gold, and embers rise off Legendary cards; pick-screen cards animate too.
- [ ] 0.28.0 polish: the turn's portrait glows; the hand that isn't playing dims; a spell's valid targets glow (cards and empty squares); the result panel is slimmer and sits low on the board so the final board shows; dead code removed; class list from the rules module.
- [ ] 0.28.1: "Find a match" overlapped "My target" on the pick screen: it now sits above Practice (same width), clear of the challenge row.
- [ ] 0.40.0 class abilities reworked into removal / protection / swap (see the rules line above). Targets glow by kind (red removal, gold protection, purple swap; Pick Pocket: your card, then theirs). A removed card shrinks and fades (Polymorph: it turns into the sheep and trots off; Execute: your card strikes first); its owner is dealt the reserve closest in spikes (lowered a tier or more if that's closer), face down with the page-turn flip; a sixth hand card closes the gaps up. Removal frees a square, so the board still ends at nine. Each spell plays its class sound (Banish: Dimensional Rift, Polymorph: the sheep, Execute, Divine Shield, Barkskin, Grounding: wind cast, Mind Control: shadow whisper, Pick Pocket: coins, Freezing Trap: trap set; the trap's snap on the catch). PvP protocol 4: three reserves travel as K 6..8 and are checked like the hand; U carries Pick Pocket's second square; a target the other screen's rules don't allow cancels the game. Tested offline: rules per spell, practice with every class, two clients ending on the same board for every pairing (including two removals).
- [ ] 0.40.1 the chosen card is hidden: the opponent's stays face down in their hand (no glow, no hover) until played, turning over as it lands (or at the end if never played); yours carries a stealth mark. The practice gambler hides its strongest card the same way and no longer counts yours when it plans. No protocol change (the chosen card already travels first).
- [ ] 0.41.0 hero and companion cards. Hero: your character (name, level, race), Fought, then Hunted / Master Hunter / Epic / Legendary at 10 / 25 / 50 / 100 creatures at Master Hunter or above (WL.HeroTier); shape by class (Warrior, Paladin: front and back; Rogue, Hunter: flanks; casters even), leaning toward the race's capital; only ever the chosen card (its own slot on the pick screen, "You"); your screen shows your character's model, the opponent's their class medallion. Companions (Hunter, Warlock): right-click the pet's portrait > Add to Wild Gambit deck (or /aa gambit pet; /aa gambit pet remove Name), kept per character with its species, level and face; Fought, then by kills with it out (5 / 15 / 50 / 200, WL.PetTier); in your deck like any card (the practice gambler doesn't draw them). PvP protocol 5: heroes travel as class "hero:CLASS:Race", companions "pet:Kind"; both skip the wild-level check but keep the spike rules. Art hooks: HERO_ART (crest, capital scenes, class crests, paw badge).
- [ ] 0.41.1 hero art in (crest, six capital scenes, nine class medallions, paw badge). 0.41.2 the Skyborne (WoW Forever's new race: Windshaper Horde, High Order Alliance, starting on Zephras Isle): recognised by race name, their spikes lean toward Zephras Isle (its map found by name and remembered) and their scene is Scene_Hero_ZephrasIsle once painted; heroes now travel with their home scene ("hero:CLASS:Home").
- [ ] 0.42.0 pick table of ten: your hero card first, then your favourites, your companions, then your strongest (no separate hero slot). Favourites: a star on the Creatures page card box (top right); up to 5 (WG.FAV_MAX), a sixth asks which to replace; starred creatures show a gold star on their card and in the Creatures list, are always on the pick table, and are three times as likely (WL.FAV_WEIGHT) to be among the four cards drawn with yours (your own hand only; the practice gambler draws evenly). Kept account-wide (wildGambit.favorites).
- [ ] 0.43.0 spell cards: each player's class spell is a sixth card at the end of their hand (Frame_Spell, Gem_Spell tinted by kind, Spell_<Name> painting, name and rules in the panel), face up for both; click it to cast (targeting as before), it fades from the hand once used; hover for a large view; the header spell box is gone. Shaman: Reincarnation replaces Grounding Totem (the next card of yours taken by a capture, trap, Mind Control or Pick Pocket, or removed by Banish / Polymorph / Execute, stays yours; one use; ankh by the portrait while waiting). Effects: FX_* paintings grow, turn and fade over the target (Banish, Execute, Polymorph, Divine Shield, Mind Control, frost on a trap, coins on Pick Pocket, spirits on Reincarnation); Divine Shield's bubble and Barkskin's mark painted. PvP protocol 6.
- [ ] 0.43.1 practice opponents: a random creature near you (nameplates, target, mouseover, focus; not dead, not your pet), else one from your Almanac by rank (dungeon boss > named / rare > elite > any); its name and portrait in the seat (the unit's own portrait while in sight, its appearance learnt and kept). Right-click any portrait (target, focus, party, raid, boss, players, friends): "Play Wild Gambit": a creature becomes the next practice opponent (shown in the empty seat on the pick table), a player is challenged.
- [ ] 0.43.2 cards fly from the hand to their square (0.42 s, eased arc, growing from hand size to board size with a little extra mid-flight, then a 0.18 s settle); the place sound, captures, traps and Reincarnation follow the landing; the opponent's hidden card turns over in the air; clicks wait while a card is in the air. A cast spell card glides toward its target as it fades. Spell rules text (and a long name) shrinks to fit the card's panel.
- [ ] 0.43.3 an opponent who wanders out of sight keeps its face: its appearance is learnt from the unit while in sight, else from its creature ID (SetCreature), kept on the creature's record, and shown in the seat and owner tabs once the live portrait is gone (a few retries if it isn't known yet).
- [ ] 0.44.0 habitat scenes (Media\Scene_Habitat_Underwater / Shore / Desert / Snow / Swamp / Cave): a card's scene follows where the creature lives before its type: words at the start of a word in its name or family (shark, crab, murloc, naga, makrura -> Underwater; pirate, privateer, crocolisk -> Shore; frost, yeti -> Snow; sand, scorpid, silithid -> Desert; kobold, trogg, tunnel -> Cave; bog, mire, ooze -> Swamp), else its home zone (Tanaris, Silithus, Desolace, Badlands, Thousand Needles desert; Winterspring, Dun Morogh, Alterac snow; Swamp of Sorrows, Dustwallow, Wetlands swamp); else the type scene as before. Companions by species; heroes keep their capital.
- [ ] 0.44.2 end-of-match sounds: quest complete (win), quest failed (loss), quest accepted (draw), stopped by 2.8 s. Forfeit button (bottom right, practice and against players; confirm first): a loss for you; your opponent sees "X forfeits the match" and the win is theirs.
- [ ] 0.44.3 favourites wear a ruby heart (Media\Badge_Favorite) on the Creatures page button, in the creature list and on the card. Settings: a search box over the page list; every page is built the first time you search, and every heading, option and its tip is indexed; results (option and page) replace the list, and clicking one opens its page scrolled to it with the row flashing gold.
- [ ] 0.44.4 fix: spell effects (frost on a trap, Banish, Execute ...) were drawn on the window itself, under the card frames, so they never showed; they're on their own layer above the cards now. Creatures page tier filter wide enough for "Legendary Hunter".
- [ ] 0.45.0 Freezing Trap rule: the card played onto a trap is frozen solid: nobody's card, takes nothing, can't be taken or targeted, its square out of the game (8 cards count, so 4-4 draws can happen); Reincarnation still saves it. Look: frost over the card (Media\FX_FrozenCard, added as light), ice round the creature's feet (Media\Mark_IceShackles), the model paused and lit cold blue, ice-blue owner tab with no face or gems. The practice gambler hides its trap beside its own cards. PvP protocol 7.
- [ ] 0.45.1 spell cards carry a short rules line (WL.ABILITIES[..].short); the full rules show in a tooltip beside the close look and on the class picker. The shrink-to-fit now measures with a set width (it measured before layout and didn't shrink).
- [ ] 0.42.2 companion cards: the pet that's out is drawn from the unit itself (model), and its appearance is learnt (a near-invisible on-screen model read back while it loads, or the card's own model) and kept for when it's dismissed and for the other player's screen; its level follows UNIT_LEVEL / UNIT_PET; right-click the pet again: "Discard its Wild Gambit card" (confirm; kills together are lost). Levels: the hero card is rebuilt from your level and Master Hunter count every time the pick table opens; a companion's level and kills update as it levels and fights.
- [ ] 0.45.4 flights offer a game, not just Gem Match: Wild Gambit (its logo as the button), Murloc Tac Toe and Gem Match side by side, one recommended each flight (a different one from last time, glowing gold, named in the prompt). In the prompt at the top of the screen and on its own line in the talking-portrait panel.
- [ ] 0.46.0 a three-step flow. 1) Who will you play? (the lobby on the felt): Practice (the creature near you, or the best your Almanac knows; "Someone else" picks again), Challenge a player (name box, My target), Find a match (search clock on the tile); what you played last glows; your practice and player records; a first-time tip (three lines, Got it). 2) Prepare: the opponent already in the seat; the ten cards with "...or let fate decide" under them; Play as with your spell shown as its card (hover: full rules); Back, and Begin / Ready (greyed until a card is picked or fate chosen); against a player the line says waiting / accepted / they're ready. 3) The match; the result offers Play again (same opponent: back to step 2, or a new challenge) and New opponent (step 1). Challengers and match-made players now press Ready when they've chosen (no more sending the card the moment the other side accepts). Portrait "Play Wild Gambit" and accepting a challenge go straight to step 2. Creatures page: the favourite heart moved to the top left of the card box.
- [ ] 0.46.2 practice difficulty: Easy (misses the best move about half the time, ignores what your hand could do, uses its spell less, and its two strongest cards play a tier lower), Normal (the default, a little gentler than before) and Hard (the old near-perfect play). Set on the Practice tile (Difficulty: X >) or in Settings, Wild Gambit, Practice difficulty. The hidden chosen card now looks stealthed instead of the Shadowmeld icon: the model shimmers half-seen under a drifting haze over the art window (spikes stay readable); uses Media\FX_Stealth when that art arrives, a tinted glow until then.
- [ ] 0.46.3 prepare screen: the Play as row and "...or let fate decide" moved down clear of the lower cards; a hovered pick card grows less (1.7x, was 2.4x); the elite/rare plate dragons no longer show on the painted frames (they read as stray rings on the narrow name panel).
- [ ] 0.46.4 lobby: the Challenge and Find a match icons (and Practice's question mark) zoomed in so their square edges stay inside the round frames.
- [ ] 0.46.5 the hidden card is unmistakable: a pulsing violet stealth outline round the whole card, its frame cloaked a dark violet (spikes and number stay bright), and a hooded-eye badge at the bottom left of the art (an eye icon until Media\Badge_Hidden is painted), on top of the shimmer and haze. The haze now always uses the placeholder until FX_Stealth arrives (a missing file would have drawn nothing).
- [ ] 0.46.6 the close look at a hovered card in a match is 35% smaller (1.56x, was 2.4x).
- [ ] 0.46.7 hidden card art: Media\Badge_Hidden (the hooded figure with violet eyes, replacing the eye icon) and Media\FX_Stealth (violet smoke on black) in two layers that rise and fade in turn across the art window; choosing a card on the Prepare screen plays the rogue Stealth sound.
- [ ] 0.46.8 the blocked-action record keeps the latest 30 (it had filled with the old map-pin blocks of 0.17.6 and stopped recording), so a new "blocked from an action" popup can be traced from SavedVariables.
- [ ] 0.46.9 hands size themselves: each card is as big as its row allows with its spikes clear of its neighbours (six in hand about 0.69, five 0.83), never wider, spikes and all, than the plank (0.88 at most); as cards leave, the rest spread out and grow; the flight to the board starts from the card's current size. The hidden card's hooded badge moved down onto the band under the art.
- [ ] 0.46.10 the hidden card loses its violet outline (the cloaked frame, badge, smoke and shimmer stay).
- [ ] 0.47.0 How to play: a guided match against The Gambit Tutor (15 steps on a parchment note over the board's bottom row, a gold glow on what it talks about). Your hand, spikes, your hidden card, your spell; the Tutor plays first (scripted), you capture its card (6 against 1), it takes yours back (7 against 2), you win it back (5 against 3); only the asked-for card and square work until then, and your spell waits. Then "Play on": the rest of the match against an easy Tutor that casts no spell. Not counted in your record ("Tutorial complete!"). Offered once in the lobby (Play the tutorial / Got it, for everyone, old players included), then a How to play button under the record; /aa gambit tutorial. Skip the tutorial any time.
- [ ] 0.47.1 the close look at your hidden card keeps its stealth look (smoke, shimmer, frame tint, hooded badge).
- [ ] 0.48.0 the players' header dressed: a carved nameplate (Media\Header_Nameplate, mirrored for the opponent) from each portrait towards the vs, the name along it over an inlay of the class colour, the score on a bronze coin (Header_ScoreCoin) in its round end, and a gold arrow (Header_TurnGem) at its far end nudging towards the board on that player's turn.
- [ ] 0.48.2 the hidden card's badge moved left to the frame's edge.
- [ ] 0.48.3 the turn arrow points back along the nameplate at the name whose turn it is (it pointed away).
- [ ] 0.49.0 holiday boards: Hallow's End (Media\Board_HallowsEnd: pumpkins, skull, bat and cat, ember runes) and the Feast of Winter Veil (Board_WinterVeil: yetis, reindeer, holly, frost runes), in the Board picker; with "Holiday boards" on (the default) the board dresses for the season by itself during Hallow's End (18 Oct - 1 Nov) and Winter Veil (16 Dec - 2 Jan), whichever board you picked.
- [ ] 0.49.1 fix: "AzerothAlmanac has been blocked from an action" (SpellStopCasting / SpellStopTargeting, on Escape and logout). Cause: QoL/WildGambit.lua reassigned the game's StaticPopupDialogs table ("StaticPopupDialogs = StaticPopupDialogs or {}", added in 0.42.2 and 0.44.2), which taints it; the game menu then refuses its own protected calls. Both lines removed; only our keys are added to the table. Traced from the blocked-action log (db.diag).
- [ ] 0.50.0 player matches (first real 1v1 test), protocol 8 (both players need 0.50.0):
  - The opponent's portrait is never a card any more (it was their first card: their hidden one). Their live portrait when they're in sight (target, focus, group, nameplate), else their race's portrait (race and sex now travel with the setup message). Same on the cards' owner clasp.
  - Whose turn: a warm glow round that player's nameplate (with the arrow). Nameplates taller; the score on a bigger bronze coin over the frames, outlined.
  - A card taking several lunges clearly at each in turn (bigger lunge, a little slower).
  - Pick Pocket: the hint says "click one of your cards on the board" (a click in the hand no longer selects a hand card while choosing a target); the status line is short enough not to be cut off.
  - In combat the game pauses for both players (P|gid|1/0); the practice gambler waits too. The window tucks into a small bar (Settings, Wild Gambit, In combat: dock top / left / right, float, or leave open) and comes back when combat ends. A "-" button on the window tucks it away by hand (floating, movable); click the bar to come back.
  - The "forfeits" at Ready: a game the other screen called off (a card it rejected, or out of step) now says so on both screens and isn't counted. The creature level check against the database is gone (WoW Forever's levels don't always match it; it rejected cards on one screen only). A first move that arrives before this screen has begun is kept and played.
  - Grey (Poor) cards keep their scene in colour.
  - Settings: the practice difficulty, table, board, holiday boards and card back pickers now change the Wild Gambit settings (they were writing to the Gem Match settings).
- [ ] 0.51.0 Wild Gambit:
  - Opponent in combat: a note over the board (they're in combat, the game waits) with "Tuck it away" (into the bar, docked as set) or "Wait here"; when they're back, the table returns if it was tucked away for them, with a ready-check chime and a line in chat.
  - Shuffle on the pick screen (above the first card): the cards are swept into the deck, riffled and dealt again one by one, turning over as they land (paper and page sounds). You and your companions always come back; the rest are drawn at random (favourites a little likelier). The picked card stays picked if it comes back.
  - Let fate decide is a die between Back and Begin (Interface\Icons\INV_Misc_Dice_01 in a gold ring): it glows on hover, pulses and rocks while fate has the choice, with a dice sound. Fate now picks your class too (the class picker and spell card grey out; a class or card clicked takes the choice back).
- [ ] 0.51.1 the turn glow round the nameplate is twice as strong (two glow layers) and reaches twice as far.
- [ ] 0.52.0 header: the score coin sits inside the nameplate's round end (smaller, font 19) and the spell and portrait move out 6, so the plate starts clear of the portrait frame.
- [ ] 0.52.0 shuffle: the pick table always opens face down and shuffles in front of you (gathered, riffled twice in two halves, dealt one by one face up); "Shuffling the deck..." and a glow under the deck while it runs; Begin waits for the deal. Refreshes while open don't reshuffle.

## 2. Discovery recorder

- [ ] Events to verify on this client: `COMBAT_LOG_EVENT_UNFILTERED`, `UNIT_SPELLCAST_*`, `NAME_PLATE_UNIT_ADDED`, `PLAYER_TARGET_CHANGED`, `UPDATE_MOUSEOVER_UNIT`, `LOOT_READY`/`LOOT_OPENED`, `CHAT_MSG_LOOT`, `BAG_UPDATE_DELAYED`, `QUEST_DETAIL`/`QUEST_ACCEPTED`/`QUEST_TURNED_IN`, `GOSSIP_SHOW`, `MERCHANT_SHOW`/`MERCHANT_UPDATE`, `TRAINER_SHOW`/`TRAINER_UPDATE`, `TRADE_SKILL_SHOW`, `TAXIMAP_OPENED`, `ZONE_CHANGED*`, `ENCOUNTER_START`/`ENCOUNTER_END`, `PLAYER_ENTERING_WORLD`. Read every value through `ns.Readable`.

## 4. Items (phase 4 built 2026-10-04, version 0.4.0)

- [ ] Verify in game.

## 5. Merchants (phase 4 built 2026-10-04, version 0.4.0)

- [ ] Verify in game.

## 6. Quests (phase 5 built 2026-10-04, version 0.5.0)

- [ ] Recorder `Modules\Quests.lua`: offered (`QUEST_DETAIL`: title, description, objectives, rewards, choices, money, XP, giver NPC / object / item with position), progress (`QUEST_PROGRESS`: text, items to bring, ender), completion (`QUEST_COMPLETE`: text, ender), handed in (`QUEST_TURNED_IN`: done, times, level, journal "Completed: ..."). Quest log scan (heading, level, objectives; description of quests taken before install by briefly selecting them). Abandoned = gone from the log and not flagged completed for 3 s.
- [ ] Quests each character finished before install (`C_QuestLog.GetAllCompletedQuestIDs`), titles from the game (`GetTitleForQuestID`, `RequestLoadQuestByID` + `QUEST_DATA_LOAD_RESULT`), quiet, marked "done before the Almanac began".
- [ ] Per character: `chars[key].q[questID] = { s = o/a/d/x, t, c, lv }`. Quest givers and enders kept quietly as `found.npc` / `found.object` (groundwork for section 10).
- [ ] Chains: a quest offered within 60 s of a turn-in is linked when the database says it follows; for quests the database doesn't know (Forever's own), when the same NPC offers it within 20 s.
- [ ] Hidden database `Data\Quests.lua` (tools\build_quests.py, VMaNGOS, 4,433 quests, 240 KB): level, min level, zone, starters, enders, follow-ups, creatures / objects / items asked for, race and class masks. No text. Reveals: the ender's name once a character has taken it and you've met them; creatures it asks for that are in your Bestiary (others counted); follow-ups only after a character completes it (count + "X may have more for you" when you've met the giver), filtered to the playing character's race and class.
- [ ] Quests page: list by quest log heading (collapsible), status icons (done check, ?, !, abandoned), difficulty colours, filter (all / in log / done by this character / not done / offered / abandoned), search (title, objectives, giver). Parchment detail like the quest log: objectives, description, rewards (reward slots), progress and completion text, quest givers (click = waypoint), what it asks for (click = Bestiary / Items), the story (before / after), your characters.
- [ ] Cross-links: Bestiary "Wanted for quests", Items "Quest rewards" as clickable slots + "Wanted for quests", Characters "Quests done". Toast "New quest found" (option).

## 7. Zones and exploration (phase 6 built 2026-10-04, version 0.6.0)

- [ ] Exploration: the game's "Discovered X: N experience gained" message (`ERR_ZONE_EXPLORED_XP` / `ERR_ZONE_EXPLORED`) records the place for that character (`chars[key].explored[id] = { t, xp }`), creating the place if the message comes first. Map areas uncovered kept per character (`chars[key].mapAreas[map]`).
- [ ] Zone page: the zone's own map drawn from the game's map art (`C_Map.GetMapArtLayers` / `GetMapArtLayerTextures` base tiles + `C_MapExplorationInfo.GetExploredMapTextures` overlays for the character you're playing, laid out like the world map's exploration pins), pins for merchants (vendor icon, click = Merchants) and quest givers (!) met there, and an arrow where you stand. Then General (continent, creature levels met, first discovered, visits), places found (with "explored, N experience"), creatures (click = Bestiary), merchants, quests, and each character's exploration.
- [ ] Place page: explored by (date, experience), merchants and quests offered there.
- [ ] Bestiary "Where" zones are slots that open the zone in Places. Detail panes keep their scroll position when the page refreshes.

## 8. Dungeons and raids (phase 8 built 2026-10-04, version 0.9.0)

- [ ] Recorder `Modules\Dungeons.lua`: runs per character (entering to leaving: visits, time inside, last visit; journal "Deadmines: 4 bosses in 38 min"; quickest run with a kill), the floors' maps (uiMapID + name), bosses from the game's `ENCOUNTER_START` / `ENCOUNTER_END` (kills, wipes, NPC from boss1, where met) and, for bosses without encounters, from the Bestiary's kills of NPCs the records list as that dungeon's bosses (`ns:Fire("KILL")`, new). Dungeon floors no longer recorded as zones.
- [ ] Hidden database `Data\Dungeons.lua` (tools\build_dungeons.py, from Plus Everything's AtlasLoot Revival data, MIT, `Licenses\AtlasLootRevival-LICENSE.txt`; Forever's new dungeons by boss name): map ID, levels, entrance zone, raid, bosses (NPC, kind, loot with chances). Wowhead-derived BossData not used.
- [ ] Dungeons page (replaces the empty Lore tab; lore will come into the Journal): dungeons and raids entered, by level; floors on the game's map art with a skull where each boss was met; General (kind, entrance, levels, first entered, visits, quickest run); bosses met (kills, wipes, tier; click = Bestiary) and a count of the rest; loot you've had from them and a count of what they carry; your characters' visits, boss kills, time inside. Places' dungeon entries open it.

## 9. Trainers: spells and recipes (phase 7 built 2026-10-04, version 0.7.0)

- [ ] `TRAINER_SHOW`: every service the trainer lists, with the filters cleared and put back (spell ID from `C_TooltipInfo.GetTrainerService`), name, rank, required level, required skill, cost, item made; "used" marks it learned for this character. Trainer recorded like a merchant (name, title, position, group, what it teaches); journal line and "New trainer met" toast. Groups: `class:<CLASS>`, `skill:<Profession>`, `other:<title>` (weapon masters, riding).
- [ ] Profession window (`TRADE_SKILL_SHOW` / `LIST_UPDATE` / `NEW_RECIPE_LEARNED`): learned recipes with reagents, item made, category, and the profession's skill level. Skills list (`GetSkillLineInfo`) keeps every character's profession levels. `LEARNED_SPELL_IN_TAB` marks new spells learned.
- [ ] Trainers page (one page for spells and recipes, to keep the side tabs fitting): groups by class and profession (yours first), an Overview per group (each character's profession skill bar in that profession's own bar art, or level and spells learned; trainers met; recipe items found in Items, by the item's recipe kind), then spells / recipes coloured as a trainer colours them for the character you're playing (green now, red not yet, grey learned). Spell page: requirements, cost (coins), makes, reagents (click = Items), taught by (click = waypoint), your characters' status.
- [ ] Rank details (0.7.1): each spell's own tooltip lines (mana, cast time, cooldown, range, description with its amounts) from `C_TooltipInfo.GetTrainerService` at the trainer (kept) or `GetSpellByID` (live); "All ranks" lists every rank trainers have shown, with level, cost and what each does.
- [ ] Items: "Made by" and "Reagent for" from recipes you've seen. Places: trainers in the zone (list and map pins).

## 10. NPCs and flight paths (built 2026-10-04, version 0.13.0)

- [ ] Townsfolk page (`UI\Pages\Townsfolk.lua`, side tab after Trainers): everyone met - townsfolk records, merchants, trainers and quest givers merged by NPC ID - listed under their Townsfolk group (Innkeepers, Flight masters, Warrior trainers ... Quest givers), with faces. Filter: everyone / trainers / services / vendors / quest givers / flight paths; search by name, title or place. Page: portrait, title, where (talked-to spot, else their database spawn near where you met them), who they serve, first met / also met by, links to their stock (Merchants), their training (Trainers), their flight path, quests they give and take in. Show on map (Places with their face pinned; Places:ShowZone takes a generic pin now) and Set waypoint.
- [ ] Flight paths (`Modules\Flights.lua`): every node on the flight map when it opens, per character (`known[char]`); the node you stand at gets your exact position and its flight master; others get their zone from the node name and a position converted from the flight map where the client can. New node learned = journal entry and a "New flight path" alert. Node page: zone, known by, flight master, flights timed from and to it (the travel helper's times).

## 11. Hidden database (build tools) (phase 3, creatures built 2026-10-04, version 0.3.0)

- [ ] Verify in game: tier reveals on the Bestiary page, the 1.8 MB file's load time.

## 12. Overview: the adventurer's journal (built 2026-10-04, version 0.14.0)

- [ ] Overview: the Journal page's home (right pane, Overview button in the header) rather than a new tab - each catalogue's count with "+n this session", research (creatures studied / mastered, kills, quests completed, gathering), the latest milestones, recent discoveries, and (account view) who was first to find things, per character.
- [ ] Journal: timeline grouped by day (Today / Yesterday / date, collapsible), filters by character, kind and zone, search.
- [ ] Milestones (`Modules\Milestones.lua`): firsts (first elite, rare, boss slain, mastery, dungeon, flight path, epic, catch, herb, vein, pelt, second character) and count series (creatures, mastered, kills, zones, places, dungeons, items, rare items, quests done, merchants, trainers, townsfolk, flight paths, herbs, veins, catches, pelts, characters). Earned once per account with character and date; a toast (orange, loot-toast style) and a journal entry. Milestones already met on first run are recorded quietly ("before milestones").
- [ ] Per character view versus account view: the character filter switches the overview, milestones and timeline.

## 13. Gathering and fishing (built 2026-10-04, version 0.14.0)

- [ ] Nodes (`Modules\Gathering.lua`): herbs, veins, chests and other objects by name (object ID from the loot source GUID, named from the hidden item database), kind from the gathering cast, where (zone counts and spots), your skill when gathered, what came out (times and quantity).
- [ ] Fishing per zone: catches, your fishing skill, pools fished (pool name from the loot source).
- [ ] Research tiers by times gathered: Studied (5) reveals everything a node can hold from the Classic records (greyed until found), Mastered (15) adds the Classic chances. Tier-up toasts.
- [ ] Gathering page (`UI\Pages\Gathering.lua`, side tab after Places): Herbs, Ore and stone, Chests and objects, Fishing, Skinning; Show on map pins every spot in Places (Places pins take a list of spots now).
- [ ] 0.40.1 ranks: Sighted (seen, never gathered), Apprentice 1, Journeyman 5 (everything it can hold), Expert 15 (how likely each is), Artisan 50, Master 200; the creature tiers' colours and badges (Apprentice wears the profession's icon); the blue skills bar like a creature's ("9 / 15 · 6 to Expert", rolling on past Master); toasts "Expert Miner", "Journeyman Herbalist", "Artisan Angler" (chests: the rank alone). Tier counts for creatures and gathering are fixed in code (Bestiary.TIER_KILLS, Gathering.AT); Settings > Research tiers only lists them, and old saved tier settings are dropped (Store migration 4).

## 20. World events (added 2026-10-03)

- [ ] How to read the active event on this client (calendar API) – to check.

## 22. Probe 0.3 – world checks (2026-10-03)

- [ ] Gossip text and options, quest text (offer / progress / completion), books (`ITEM_TEXT_READY`).
- [ ] Merchant stock (price, limited quantity, alternate costs) and trainer services (name, rank, level, cost).
- [ ] Profession window recipes, flight map nodes, zone and subzone changes with map exploration functions.
- [ ] Factions list, interaction windows (inn, bank, mailbox, spirit healer ...), level-ups, deaths (and the damage meter's Deaths view).
- [ ] Loot sources by kind: creatures, objects (herbs, ore, chests), items (containers), fishing; item set IDs.
- [ ] Creature 3D model by NPC ID with the creature present (`/aap model`) and gone (`/aap model2 <id>`).
- [ ] A real interrupt (Kick / Pummel / Earth Shock) in the damage meter's Interrupts view.

## 23. Quality-of-life helpers and the settings window (built 2026-10-04, version 0.10.0)

- [ ] Works in game as described in this section of `docs/DESIGN.md`.

## 24. My Characters look across the Almanac (built 2026-10-04, version 0.10.1)

- [ ] Works in game as described in this section of `docs/DESIGN.md`.

## 25. Townsfolk on the world map (built 2026-10-04, version 0.11.0)

- [ ] Works in game as described in this section of `docs/DESIGN.md`.

## 26. Toast tiers (built 2026-10-04, version 0.15.0)

- [ ] Every alert has a tier in the item-quality colours: Common (white) routine finds (places, creatures, merchants, quests, nodes, fishing waters); Uncommon (green) zones, trainers, flight paths, elites, Studied, level-ups; Rare (blue) dungeons, rare creatures, bosses met, Mastered, every 10th level; Epic (purple) rare elites, "first" milestones; Legendary (orange) level 60, world bosses. Milestone series climb from Uncommon (first step) to Legendary (last step). Items keep their own quality.
- [ ] The tier sets the icon border and name colour, the frame (LootToast-LessAwesome below Rare), the flash strength, the sound (none / chime / quest complete / epic fanfare / legendary) and time on screen (3 s to 6 s).
- [ ] Common finds within 1.5 s merge into one alert ("Goldshire and 5 more").
- [ ] Settings (Discovery alerts): show alerts for (everything ... legendary only; below it the journal only), sound for (tier). /aa toast and the Test button show one of each tier.

## 27. Gathering nodes on the maps (built 2026-10-04, version 0.16.0)

- [ ] Sighted nodes: the soft interact target (what the gathering highlight sparkles) is recorded as sighted with your position, even when you can't gather it; quest objects and non-nodes left out.
- [ ] `Modules\NodePins.lua`: every gathered and sighted spot on the world map (map canvas provider, herb button left of the townsfolk spyglass: left-click show / hide, right-click settings) and on the minimap (placed from your world position; zoom, indoors / outdoors and rotating minimap). Pins: the node's main item in a rim by kind (green herb, copper ore, gold chest); sighted-only dimmer and greyed. Hover: node, times gathered / sighted; click: waypoint; shift-click: Gathering page.
- [ ] Settings (Gathering page): world map, minimap, herbs / ore / chests, sighted spots, pin sizes.

## 29. Spell ranks (2026-10-04, version 0.17.0)

- [ ] Plus Everything's Spell Ranker ported (`QoL\SpellRanker.lua`): action buttons (spells and macros) on an older rank than the highest known glow gold with a green arrow; tooltip line "Rank n available". "Check action bars" button at the top of the spellbook (modern PlayerSpellsFrame or classic SpellBookFrame; shift-click also updates); checks on opening the book and after learning a new rank. /aa ranks, /aa rankignore <spell>.
- [ ] New: training a new rank replaces the older rank on your bars (spell buttons only, macros left alone; out of combat, waits for combat to end; waits while something is on the cursor). Settings page Spell Ranks (Characters): auto-replace, check after learning, check on opening, Check now / Update all now.

## 30. Gathering toggle on the minimap (2026-10-04, version 0.17.1)

- [ ] Herb button on the minimap's rim, styled like the Almanac's minimap button (tracking border, Trade_Herbalism icon, greyed when off). Left-click shows / hides gathering pins on the minimap, right-click opens the Gathering settings, drag moves it around the edge (`nodes.mmPos`). Tooltip shows how many pins are nearby. Setting "Herb button on the minimap" (`nodes.mmButton`); `/aa nodes` toggles the minimap pins. Both map buttons stay in sync with the settings.
- [ ] 0.17.2: in game the button was not visible; at a fixed 225° it sat under the Almanac's button (moved to ~235°). Now first placed 55° clockwise of wherever the Almanac button is, drawn one level above it, `/aa nodes button` resets it, and a failure to build it prints in chat.

## 32. Dressing room on Ctrl-click (2026-10-04, version 0.17.3)

- [ ] Shared helpers in `UI\Widgets.lua`: `W.ItemModifiedClick(item)` (the game's DRESSUP binding, Ctrl by default: `DressUpItemLink` for wearable items; CHATLINK / Shift: chat link, only swallowing the click when a chat box took it), `W.IsDressable(item)`, `W.ItemCursor(frame, getItem)` (the inspect magnifier while Ctrl is held over a wearable, follows `MODIFIER_STATE_CHANGED`).
- [ ] Used by every item slot (loot, rewards, merchant stock, gathering, trainers, journal blocks ...; runs before the slot's own click, so Ctrl-click no longer opens the Items page), the Items list rows and detail icon, Journal item entries, and lists via `W.List{ itemOf = fn }`. My Characters, bag / bank and the vendor window already use the game's `HandleModifiedItemClick`.

## 33. My Characters profession bars (2026-10-04, version 0.17.4)

- [ ] The gold bars on the Professions tab (and the generic row bar) replaced with the character sheet Skills window's rank bar: `common-stat-bar-BG` frame cut into left / middle / right from the atlas coordinates (10 source px caps), `common-stat-bar-blue` fill inset a sixth of the height and cropped by tex coords to the rank (not squashed), count in white GameFontHighlight centred. Fallback: dark box + blue status bar. Helper `SkillBar(parent, height)` in `QoL\InventoryWindow.lua`.

## 35. World map pins not showing (2026-10-04, version 0.17.5 → 0.17.6) (verified in game 2026-10-04)

- [ ] Likely cause: the XML pin templates name `AzerothAlmanacNodePinMixin` / `AzerothAlmanacTownsfolkPinMixin`, which were only created at login, after the XML loaded. Both mixins now exist from file load and get the map's pin methods mixed in later. Townsfolk pins (never confirmed in game) use the same fix.
- [ ] **0.17.7:** with pins drawing, combat spammed "the game blocked Frame:SetPassThroughButtons()": the map canvas sets mouse pass-through on each pin it places, which is protected in combat. Both pin mixins now override `SetPassThroughButtons` / `SetPropagateMouseClicks` / `SetPropagateMouseMotion` with no-ops (the HandyNotes / TomTom fix; our pins hand the mouse to a child button). The blocked-action warning now prints once per function per session (still recorded in `AzerothAlmanacDB.diag`).
- [ ] The node provider's refresh is now caught: errors are kept and shown by `/aa maptest` with the spot / pin counts for the open map (records, asked for, actually on the map) and the townsfolk pin count.

## 36. Chest icon (2026-10-04, version 0.17.8)

- [ ] Chests and objects use icon file 132594 (picked in game with `/aa whatis` from the macro icon picker) for the Gathering category, its list rows and portrait, and map / minimap pins with no loot icon yet (INV_Box_02 kept as fallback).
- [ ] 0.17.9: Battered Chest showed Ice Cold Milk (its most common drop). Chests and objects that give more than one kind of item now always use the chest icon (page portrait, list row, Show on map pin, world map / minimap pins); one-item objects (Farm Chicken Egg) still show their item.

## 37. My Characters merged into Characters (2026-10-04, version 0.18.0)

- [ ] The separate My Characters window is gone; the Almanac's Characters page holds both.
  - **List:** 50 px rows: portrait (yours from the game's 2D portrait, the others' class emblem) in a class-coloured ring with the Alliance / Horde banner, name and level ("(you)"), race / class / zone, gold, last played, rested %. Right-click: hide / show, remove saved data (removes the Almanac record too). "Show hidden characters" under the list.
  - **Page header:** search across every character's items (bags, bank, gear, mail, auctions) and account gold.
  - **Name plate:** My Characters' header (live 3D model for you, class emblem for others, faction banner; name, class line; chips in two rows: gold + rest, last location (click: world map there) + hearthstone; data freshness top right; XP / rested bar along the bottom with the login checks on hover). Average item level under the freshness on the Gear tab.
  - **Tabs** in a strip between the plate and the body, the Settings panel's tab art (`Options_Tab_*` / `Options_Tab_Active_*`) with a game icon each: Story (the page's old content: general, first to discover, levels), Gear, Bags, Bank, Auctions (count), Professions. Mail left out as asked (still recorded, and found by search).
- [ ] 0.18.1: error on first open ("attempt to index upvalue 'invScroll'"): the search box fired a change while the page was still being built, so Refresh ran before the tabs and inventory scroll existed. Refresh now waits for Build to finish, and the search only redraws when its text really changes.
- [ ] 0.18.2: the page still came up empty: Build stopped at the tab strip because `W.Detail` never exposed its scroll frame (`detail.scroll` was nil). Now `holder.scroll` is set.

## 38. Dark panel background (2026-10-04, version 0.18.3)

- [ ] Every plain dark panel (`W.Inset`, and the QoL windows' `ns.NativeInset`) is filled with the profession window's recipe list background (`Professions-background-summarylist`, falling back to the auction house's `auctionhouse-background-summarylist`, else the inset's own). Panels with a painting show it on top. If the art doesn't appear, hover the recipe list background in the profession window and run `/aa whatis` for its real name.

## 39. Best vendor reward at quest turn-in (2026-10-04, version 0.18.4)

- [ ] At a quest turn-in with two or more reward choices, the choice that sells to a vendor for the most (sell price x count) gets a gold coin (`Coin-Gold`, else the money frame's gold icon) in the bottom right of its icon; ties all get one. Item info still loading: checks again a moment later. Cleared when the quest frame moves on or closes, and never left on the map's quest details (same buttons). Part of the Merchant helper (`QoL\Merchant.lua`), setting Merchants > Quest turn-ins (`merchant.bestReward`, on by default).

## 40. Gathering icon (2026-10-04, version 0.18.5)

- [ ] Gathering uses icon file 237271 (picked with `/aa whatis` in the macro icon picker): the Gathering side tab and page portrait, its Settings page, gathering discoveries in the journal and toasts, and the herb buttons on the world map and minimap. The Herbs category itself keeps Trade_Herbalism.

## 41. Items icon (2026-10-04, version 0.18.6)

- [ ] Items use icon file 515958 (picked with `/aa whatis` on the macro window's selected icon): the Items side tab and page portrait, and item discoveries in the journal, toasts and wherever the item kind icon shows.

## 42. Dungeons icon (2026-10-04, version 0.18.7)

- [ ] Dungeons use icon file 655958 (picked with `/aa whatis`): the Dungeons side tab and page portrait (the page takes the dungeon kind's icon), dungeon discoveries in the journal and toasts.

## 43. Bestiary icon (2026-10-04, version 0.18.8)

- [ ] The Bestiary uses icon file 656556 (picked with `/aa whatis`): its side tab and page portrait (the page takes the creature kind's icon), creature discoveries in the journal and toasts, and the stand-in face for a creature the game can't draw.

## 44. Quests icon (2026-10-04, version 0.18.9)

- [ ] Quests use icon file 979575 (picked with `/aa whatis`): the Quests side tab and page portrait, quest discoveries in the journal and toasts.

## 45. Characters tab shows your portrait (2026-10-04, version 0.19.0)

- [ ] The Characters side tab and the window portrait on that page show the character you're playing (the game's own portrait, `SetPortraitTexture`), kept current on `UNIT_PORTRAIT_UPDATE` and after loading screens. Any page can ask for this with `portraitUnit` in its definition. The character kind icon stays as it was for the journal and toasts.

## 46. Chest icon, second pick (2026-10-04, version 0.19.1)

- [ ] Chests and objects now use icon file 1450989 (picked with `/aa whatis`) instead of 132594, everywhere section 36 / 0.17.9 put the chest icon (Gathering category, list rows, portrait, Show on map pin, world map / minimap pins). 132594 and INV_Box_02 stay as fallbacks.

## 47. Mastered icon (2026-10-04, version 0.19.2)

- [ ] The Mastered research tier uses icon file 4238797 (picked with `/aa whatis`; the old 4622480 stays as fallback): tier badges, tier filter buttons and bar marks in the Bestiary and Gathering, tooltip lines, tier toasts.

## 48. Places icon (2026-10-04, version 0.19.3)

- [ ] Places use icon file 4624629 (picked with `/aa whatis`): the Places side tab and page portrait (the page takes the zone kind's icon), zone rows and zone discoveries in the journal, toasts and the minimap menu.

## 49. Townsfolk icon (2026-10-04, version 0.19.4)

- [ ] Townsfolk use icon file 8197123 (picked with `/aa whatis`): the Townsfolk side tab and page portrait, its Settings page, the button at the top right of the world map, townsfolk discoveries in the journal and toasts, and townsfolk milestones.

## 50. Skinning by what you skinned (2026-10-04, version 0.19.5)

- [ ] The Gathering page's Skinning group lists the skinned items (leather, hides, scraps: item icon, quality colour, how many skins gave it) instead of creatures. Search also finds an item by a creature it came from.
- [ ] An item's page: kind, times skinned, how many creatures, first found (from the item record); **Came from**: each creature with its research tier, "n of m skins" and, once that creature is Mastered, its Classic chance; click opens it in the Bestiary. **Where**: zones where those creatures were killed (creature names listed); click / Show on map pins every kill spot in Places, each named for its creature. Link to the item in Items.

## 51. Page order, Townsfolk renamed People (2026-10-04, version 0.19.6)

- [ ] Side tabs in this order: Journal, Characters, Bestiary, Items, Quests, Gathering, Places, Dungeons (not in the list given; placed after Places), People, Trainers, Merchants.
- [ ] Townsfolk is called **People** everywhere the player sees it (page and tab, settings page, world map button and its menu, journal filter and links, milestones "Met 25 people", chat help). Internal keys stay `townsfolk` so saved data and settings carry over; `/aa people` works alongside `/aa townsfolk` / `/aa tf`.

## 52. Recipe-list row highlights (2026-10-04, version 0.19.7)

- [ ] Every list row (all page lists via `W.List`, and the Settings sidebar) uses the profession window's recipe list look: grey glow under the mouse (`Professions_Recipe_Hover`, captured with `/aa whatis`, file 4417031) and the gold bar on the selected entry (`Professions_Recipe_Active`, name expected, not captured; flat gold fill if missing). Headings show no row glow. Helpers `W.RowHover`, `W.RowSelected`.

## 53. Quests list in the quest log's look (2026-10-04, version 0.19.8)

- [ ] The Quests page list now draws its own rows (`QuestRow` in `UI\Pages\Quests.lua`): headings in the quest log's gold-edged box (`common-button-list-collapseExpand`, 3-sliced by the new `W.Slice3` so the ends don't stretch) with large light text, a gold - / + and the count; quests as "[18] Reading Room" in the difficulty colour, quest log title font (GameFontNormalMed2), the log's yellow glow (`QuestLog-quest-glow-yellow`, captured) under the mouse and on the quest being read. Rows 30 px.
- [ ] 0.19.9 polish from a side-by-side with the quest log: headings were blank (the heading box frame drew over the row's text; now box, then words on a layer above); everything scaled down (quest titles GameFontNormal, headings GameFontHighlightMedium, rows 24 px, no spacer rows before headings: `W.List{ spacers = false }`); icons on the log's round button `UI-QuestPoi-QuestNumber` (captured) with "?" when ready to turn in (C_QuestLog.IsComplete), "..." in progress, the log's yellow tick `QuestLog-icon-checkmark-yellow` for done, "!" offered, red cross abandoned.

## 54. Quest log look on more lists (2026-10-04, version 0.20.0)

- [ ] `W.List{ style = "log" }` gives any list the Quests page's Map & Quest Log look (shared in `DefaultRow`): gold-edged heading boxes (3-sliced `common-button-list-collapseExpand`) with light GameFontHighlightMedium text as written and a gold - / +, entries in the quest titles' font, `QuestLog-quest-glow-yellow` on hover (soft) and selection (full), no spacer rows, the box on its own layer under the row's words and icons. Used by Merchants, Trainers, People, Places, Dungeons and Gathering (rows 24 px). Other lists keep the recipe-list look (section 52).

## 55. Almanac and Journal icon (2026-10-04, version 0.20.1)

- [ ] The Almanac's own icon is now file 133742 (picked with `/aa whatis`): `ns.ICON` (minimap button, its menu title, the addon compartment, the window portrait fallback, toasts without their own icon), the AddOns list (`## IconTexture`), the Journal side tab / portrait, the Journal entry in the minimap menu, the General settings page.

## 56. Taller window (2026-10-04, version 0.20.2)

- [ ] The Almanac window is 680 px tall (was 580), so the Characters page's Gear tab (paper doll rows tightened to SLOT + 5, about 400 px) and Professions tab fit without a scroll bar (body area about 420 px). The side tabs still shrink to fit if there are many. The window stays clamped to the screen and follows the Scale setting.

## 57. Gear tab: class emblem for other characters (2026-10-04, version 0.20.3)

- [ ] The middle of the Characters page's Gear tab shows the class emblem (round, 160 px, as on their portraits) for characters you're not playing, instead of the race portrait / custom-race model. Your own character keeps the live 3D model.

## 58. Item tooltip card on the Items page (2026-10-04, version 0.20.4)

- [ ] An item's page opens with its own tooltip card (a separate GameTooltip, `AzerothAlmanacItemCard`, so the mouse-over tooltip is untouched), laid into the page above General and scrolling with it; other addons' tooltip lines show on it too. Filled from the item link (or ID), refreshed with the page when item info arrives.

## 60. Talent Planner (2026-10-04, version 0.21.0)

- [ ] A **Planner** tab on the game's Talents window after Primary / Secondary (`/aa talents`, Settings > Talent Planner): any class, any level, click to add / right-click to remove, save / load / delete / follow builds, talentsforever.com links in and out, "My talents", Reset, **Stage in game** (adds the plan's points in order to your real talents; you check and press Apply Changes), level-up hint and glow on the next followed talent.
- [ ] Fixing Plus Everything's flaws (wrong placements, 185 talents not found when staging, text from outside the game): every class's tree is **read from the game** (yours from your config, others through the view loadout) and laid over the data (`TL.Merge`): each talent takes the game's row, column, ranks, prerequisite, node, entry, spell and icon, matched by name then place; game-only talents are added, data-only ones hidden. Staging uses the game's node IDs directly. Tooltips show the game's own trait tooltip (`SetTraitEntry`) when available, else the data's Forever text. Reads are saved per class (`qol.talentPlanner.trees`).
- [ ] Look from `/aa whatis` on the talent window (PlayerSpellsFrame.TalentsFrame.ButtonsParent): nodes with `talents-node-square-shadow`, icon, then `talents-node-square-locked` / `-gray` / `-green` / `-yellow` by state, `talents-sheen-node` on takeable nodes; arrows `talents-arrow-head-*` (and `talents-arrow-line-*` if present); node size, icon inset and spend-count font copied from a real node.

## 61. Quest page layout like the quest log (2026-10-04, version 0.21.1)

- [ ] A quest's page: parchment (title, objectives, Description, Progress, Completion), then the Almanac's own facts on the standard dark panel (new `{ "dark" }` block: the recipe-list background edge to edge with a bronze rule; Quest Givers, What it asks for, The Story, Your Characters, first found), then at the very bottom the quest log's brown reward band with only Rewards in it (no band when a quest has no rewards).
- [ ] Slots on quest pages use the quest log's reward box size everywhere: about 170 wide, 34 a row (they were half the page wide, 36 / 44 high).

## 62. Quest map at the top of the quest page (2026-10-04, version 0.21.2)

- [ ] The quest's zone map (the Almanac's ZoneMap: the game's map tiles and explored areas) heads the quest page: where it's turned in once it's in your log, else where it's given, else where you killed most of what it asks for. Pins: giver ("!"), who takes it in ("?"), skulls where you killed its targets (up to 30 per creature), you. Click a giver / ender pin for a waypoint, a skull for the creature.
- [ ] 0.21.3: most quests had no map: they were read from the quest log (taken before the Almanac, or never seen at the giver), so they have no giver / ender position (only 22 of the records do). The map now falls back to: people the quest names whom you've met (QuestDB starters / enders, their recorded positions, pinned as "!" / "?"), then the zone named by its quest log heading (`rec.cat`, matched to your discovered zones by name), then where you killed its targets.
- [ ] Framed like the quest log: dark backing, `QuestLog-frame` border (sliced; double bronze line if missing), `QuestLog-frame-filigree` on top, `QuestLog-frame-devider` between the map and the parchment (both from the quest log's own art, `/aa whatis` 2026-10-04).

## 63. Talent Planner: unspent counter and native node look (2026-10-04, version 0.21.4)

- [ ] "Unspent Talents" label with a large green number in a box at the top right of the Planner, like the native tab (grey at 0).
- [ ] Node states from /aa whatis: takeable = talents-node-square-green with the greenglow, part / fully ranked = green / yellow, out of points = gray, locked = locked; only the rank number shows.
- [ ] Prerequisite arrows: thin 2px lines (gold when met, dark otherwise) with talents-arrow-head-yellow / -locked heads. Tree headers: points in a small dark badge on the icon, name in the large white font.

## 64. Murloc Tac Toe (2026-10-04, version 0.22.0)

- [ ] New QoL/MurlocTacToe.lua: tic-tac-toe, Murlocs against Gnolls, against another player running Azeroth Almanac (hidden addon whispers, prefix AzAlmMTT, protocol 1: challenge / accept / decline / move with sequence numbers / resign / leave / rematch, plus a board resync if the two get out of step). Challenger plays Murlocs and moves first; sides swap on every rematch.
- [ ] Art: each side's 3D model on its player card (display 506 Murloc Flesheater, 175 Riverpaw Gnoll, both seen on Forever), the creatures' round faces as pieces in the talent window's circle rings (minimap ring fallback), shaman Restoration painting behind the board, dialog gold border, gold grid lines, drop-in animation, star / ping bursts, a winning line that draws itself, attack / cheer / dead animations on the cards.
- [ ] Sounds: the creatures' own voice files (murloc aggro A/B/C and the classic AggroOld on a win, gnoll aggro 1-3), ready check on a challenge, PvP victory / quest failed / water splash.
- [ ] Ways in: /aa mtt [name | target | practice], "Murloc Tac Toe" on player right-click menus (the game's Menu system, when present), the minimap menu, Settings > Fun > Murloc Tac Toe. Popup for incoming challenges (30 s); offline players detected from the system message; Resign becomes "Leave (no penalty)" after the other player is quiet for 60 s on their turn.
- [ ] Records per opponent (W / L / D), a title from total wins (Tadpole, Mudfin, Tidehunter, Coral Champion, King of the Shoals; "Undefeated" with no losses), practice record kept apart. Settings: accept challenges, only from friends / guild / group, menu entry, sounds, erase records.
- [ ] 0.22.1: first live test, the challenge got no answer (and "the game blocked UNKNOWN() while meeting townsfolk"). Added `/aa mtt ping Name` (asks the other Almanac to answer with its version and whether it takes challenges), `/aa mtt debug` (prints every message sent / received), and a chat warning when the game refuses to send (SendAddonMessage result code). Townsfolk: CheckInteractDistance no longer called in combat (restricted there).
- [ ] 0.22.2: the game writes an offline Name-Realm as "Name Realm" in its "No player named" message, so offline players weren't caught and the challenge sat "waiting" (blocking new ones). Now matched without spaces / hyphens; a new challenge also replaces one still waiting. Realm part capitalised. (The "PingZipporah" challenge came from 0.22.0 still being loaded: no /reload after the update.)
- [ ] 0.22.3: `/aa version` prints the loaded version.
- [ ] 0.22.4: live test got stuck: the game started on the accepting side but the challenger never saw the accept. Cause: Forever surnames ("Zipporah Olaris", typed "Zipporah-Olaris"): the Almanac squashed spaces and added a realm, so the sender name never matched the opponent. Names are now sent exactly as given and compared loosely (case / spaces / hyphens ignored, own realm dropped, a bare first name matches the same first name with a surname). A new challenge to / from the same player, or once the other side is quiet, replaces the stuck game; `/aa mtt leave` ends one with no record. Simulated with surname names in both sender formats.
- [ ] 0.22.5 polish: bigger window portrait (74 px murloc face) in the classic elite target frame's gold dragon (UI-TargetingFrame-Elite, cut and mirrored to wrap the window's outside); player cards and board in the quest page's map-box look (dark list background, QuestLog-frame border, filigree); QuestLog-frame-devider dividers in the side panel; "VS" in the game's big Friz font (Morpheus made "vs" read "V8").
- [ ] 0.23.2 / 0.23.3: player cards kept plain (CARD_PLAIN: no frame, background or stage painting; the models stand on the window), models 5 px higher.

## 65. Healer Assist: the player frame's health bar (2026-10-04, version 0.22.6)

- [ ] The queue panel's health bars use the player frame's own fill (atlas UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health, from /aa whatis), untinted, over a near-black empty part; incoming heals and the hover preview use its -Status fill tinted teal. Dead / absent members: the same fill desaturated and greyed. Falls back to the classic UI-StatusBar in green where the atlas is missing.
- [ ] 0.22.7: the border too. The slot is part of the player frame's single texture (UI-HUD-UnitFrame-Player-PortraitOn, 198x71); from the /aa art layout snapshot the health bar sits at x 68..192, y 26.5..45.5 in it. Cut in three (right end with the frame edge, a stretched middle, the right end mirrored for the left since the real left end meets the portrait ring), scaled to the bar's height, drawn under the bar like the game does. Cut numbers in SLOT (HealAssist.lua) if it needs nudging.
- [ ] 0.22.8: in combat the aggro glow drew a big red box round the player frame (a 2 px rectangle on the 232x100 frame, much bigger than its 198x71 picture). On portrait frames (player, party) the glow is now the game's own status glow (UI-HUD-UnitFrame-Player-PortraitOn-Status, or the frame atlas + "-Status") laid over the frame's picture and tinted by threat level; other frames (raid) keep the rectangle.
- [ ] 0.22.9: Bestiary page icon is now Icon_UpgradeStone_Beast_Legendary (falls back to the old creature icon). Creature toasts and fallbacks keep the old icon.

## 66. Creatures page: dragons, Sighted colour, counts, rename (2026-10-05, version 0.23.0)

- [ ] Bestiary renamed Creatures everywhere it shows (page / window title, sidebar, "Click to open in Creatures.", help, settings text). Code keys stay "bestiary"; /aa bestiary and /aa creatures both work.
- [ ] The Sighted tier icon keeps its colours everywhere (filter button, row badge, detail badge); its coloured ring stays. Filter buttons only grey out when switched off.
- [ ] Tier filter counts sit beside each badge with room for 4 digits (34 px), buttons spaced 40 px apart.
- [ ] Target frame dragons (W.SetDragon / W.DragonFor in Widgets): gold UI-TargetingFrame-Elite for elites and bosses, UI-TargetingFrame-Rare for rares, -Rare-Elite for rare elites, cut x 146..256, y 0..100 and wrapped round the right side of a round portrait. On the detail page a 44 px face portrait now sits left of the name (ring gold / silver / orange by class) with the dragon; list rows get the dragon round their small face and the name moves over 8 px.

## 67. Gentler mouse-wheel scrolling (2026-10-05, version 0.23.1)

- [ ] The scroll template jumped half the visible height per wheel notch (~250 px on the quest page). Every Almanac scroll area (W.SkinScroll -> W.WheelScroll) now moves a fixed step: lists 3 rows (78 px at 26 px rows), pages 40 px, times Settings > General "Scroll speed %" (50-200, default 100), gliding there when "Smooth scrolling" is on (default). Quick notches add up; Shift + wheel keeps the half-page jump. Covers all pages, the Characters inventory, settings and the People list.

## 68. Almanac players and the update quest (2026-10-05, version 0.24.0)

- [ ] New Modules/Peers.lua: finds other players running Azeroth Almanac with hidden addon messages (prefix AzAlmHi; H|version = hello, answered once by whisper with I|version). Hello goes to the guild at login, the group when it changes (30 s throttle), online friends (spaced 0.35 s apart, max 60), and a same-faction player you target or mouse over (once per 10 min each). No realm-wide channel. Answers jittered 0.5-3.5 s, at most once a minute per player. Known players kept in AzerothAlmanacDB.peers (name, version, via guild / friend / group / seen, last seen), forgotten after 30 days.
- [ ] Tooltip badge on players who have it: the Almanac icon and "Almanac" in red.
- [ ] New UI/UpdateQuest.lua: when someone's copy is newer, a pretend quest "New Version Available" from "Azeroth Almanac" in the quest giver window's style (portrait, parchment, Quest Objectives, Rewards with two joke items in quest-reward name frames and tooltips, Accept / Decline, the quest window sounds). Accept = "Quest accepted" message, no repeats for that version; Decline = asks again next login. Waits for combat to end. /aa version quest previews it; /aa version also shows how many Almanac players are known.
- [ ] Settings > General > Almanac players: let others see me (off = never says hello or answers), tooltip badge, update quest, count.
- [ ] 0.24.1: Characters list rows roomier: 60 px rows (was 50), portrait kept at 46, 4 px between the name / race-class / money lines (was 2).

## Also flagged in STATUS.md

- [ ] **Art and layout:**
  - Item cards on dark slots: the loot-window card may look squashed at slot height.
  - Coin atlases: fixed at 14 px.
  - Journal painted background: brightness.
  - Small loot-toast frame below Rare: whether the client has it.
- [ ] **Positions:**
  - Minimap pin scale: the standard yards per zoom level.
  - Flight paths you aren't standing at: converted from the flight map.
  - Gathering minimap button: default spot (55° clockwise of the Almanac button; `/aa nodes button` puts it back) and whether it clashes with other minimap buttons.
- [ ] **Spell Ranker:**
  - Button placement in this client's spellbook.
  - Auto-replace with `PickupSpell` / `PlaceAction` out of combat.
- [ ] **Talent Planner (0.21.0):** Planner tab on the Talents window; placements, arrows, tooltips, Stage + Apply.
- [ ] **Skinning by item (0.19.5):** list of leathers / hides, item page with Came from and Where, Show on map kill spots.
- [ ] **Quest reward coin (0.18.4):** gold coin on the best-selling reward choice at turn-in; position on the icon.
- [ ] **Dark panels (0.18.3):** the recipe list background shows in plain dark panels (list panes, detail bodies without a painting).
- [ ] **Characters page (0.18.0):** list rows, name plate fit (chips in two rows, XP bar), tab art and icons, each tab's contents at the narrower width (bag rows, paper doll, profession cards), search, right-click hide / remove.
- [ ] **No more "blocked SetPassThroughButtons" in combat** (0.17.7), with the world map open or after opening it.
- [ ] **Townsfolk pins on zone maps** after the 0.17.6 layer fix (gathering pins confirmed).
- [ ] **My Characters professions:** blue rank bars built from `common-stat-bar-BG` cut into three pieces (10 px caps guessed) - check the corners aren't stretched or clipped.
- [ ] **Dressing room:**
  - Ctrl-click on item slots, the Items list and icon, and Journal item entries opens the dressing room; the magnifier shows while Ctrl is held over wearables.
- [ ] **Gathering:**
  - Sightings depend on soft-interact targeting, which the gathering highlight turns on.
  - Skill is not recorded when the Professions heading is folded.
- [ ] **Wild Gambit (0.46-0.49), from the latest screenshots:**
  - Header nameplates came out short and the score coin didn't show (0.48.0): make the plates taller, let the name run to the vs, score on the coin.
  - Holiday boards (0.49.0): the slots sit inside each board's stone frame (inner edges measured from the art).
  - Tutorial (0.47.0): the coach note over the bottom row, the gold glow following the cards, every step reachable.
  - Hand sizing (0.46.9): six cards at about 0.69 keep their spikes clear; growth as cards leave.
  - Stealth look: smoke layers rise, badge at the frame's left edge; the zoomed hidden card keeps it.
  - "Blocked from an action" popup (SpellStopCasting on Escape / logout): fixed in 0.49.1 (StaticPopupDialogs was being reassigned). Confirm it no longer appears; db.diag keeps the latest 30 blocks.
