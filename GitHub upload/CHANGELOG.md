# Changelog

What changed in each version, newest first. Collected from the old task list (now `docs/DESIGN.md`) on 2026-10-07; from now on each release adds its own section at the top.

Testing status isn't tracked here: see `docs/TEST_CHECKLIST.md` and the Issues board on GitHub.

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
