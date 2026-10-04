# Azeroth Almanac – Development Tasks

Game: WoW Forever beta (`_classic_beta_`, interface 16001). Addon folder: `Interface\AddOns\AzerothAlmanac`.
Slash command: `/aa`. Saved variables: `AzerothAlmanacDB` (account-wide).

Azeroth Almanac turns WoW Forever into a game of discovery. It records what the player meets in the world (creatures, items, quests, merchants, trainers, zones, dungeons, NPCs, flight paths) and shows it as a catalogue: an adventurer's journal that grows as you explore. There is no completion percentage; the goal is the adventure, not finishing a list.

## Status key
- [ ] not started  ·  [~] planning / in progress  ·  [x] done  ·  [?] needs in-game testing

---

## Ground rules (decided 2026-10-03)

1. **Forever only.** Every feature and decision follows WoW Forever. No code or fallbacks for other Classic versions.
2. **Natural discovery.** The player is never shown more than they have met in their own game. Everything shown comes from something that happened in the game: a creature fought or seen, an item looted or owned, a quest offered, a merchant or trainer window opened, a zone entered. Names, icons and descriptions come from the game's own API, and only for things already discovered.
3. **Outside data is hidden until earned** (revised 2026-10-03). Mined data is built into a **hidden database** that ships with the addon and fills in **full records** as the player unlocks them, by **evidence** seen in game or by a **research tier** (section 2c). Until then the page shows the field as unknown ("? abilities not yet seen", "3 more unknown drops"). Stored compactly by ID; names, icons and descriptions come from the game's API at reveal time. In-game observations (and the optional combat-log companion) always override the database, because WoW Forever differs from Classic. Forever-only content (new quests, creatures, dungeons) has no record and fills in from observation alone.
4. **Account-wide discovery.** One shared record for all characters on the account, so alts start with everything found before. Each discovery remembers which character found it first, and when. Things a character *does* stay per character: quests completed, spells and recipes learned. Discoveries can be viewed for the account or filtered to one character.
5. **Spells and recipes come from trainers.** Each time a trainer window opens, a snapshot of everything it lists is saved. No class spell or recipe datasets are shown.
6. **No sharing.** No guild or group sharing of discoveries (Plus Everything's sharing code is not brought over). A "guild almanac" view could be a separate idea later.
7. **Native look.** Every window follows WoW Forever's own styling and uses the game's art and assets wherever possible: portrait frames, title bars, native tabs, quest parchment, the game's icons, borders, quality colors, fonts and sounds, Blizzard's dungeon map tiles and class emblems. No custom-drawn panels. When an art file may be missing on this client, check for it and fall back to another of the game's textures, never a flat color.
   **Style guide (from Forever's own windows, 2026-10-04):** facts go on dark panels like the character sheet and Skills window: gold banner section headers ("General", "Weapons"), stat rows with a gold label left and a white value right, skill-style bars for progress (research tiers), collapsible category rows with a blue band and +/- (zones), white body text, grey notes. Story text goes on parchment like the Map & Quest Log: dark serif headings ("Description") and quest font (journal entries, lore, quest text). Items and abilities are shown like quest rewards: icon slot plus name plate, two to a row, with the game's tooltip on hover. Red native buttons. Pages are switched with square icon tabs down the right edge (spellbook side-tab frame), the name on hover.
   **Lists and the quest page (2026-10-04, from the profession window and the quest log):** list categories are gold-edged dark heading boxes with large gold text and a gold - / +, a little space above each; entries are plain names; the selected entry has a gold glow fading right with gold rules above and below, hover a faint one. A quest page reads like the quest log: title, objectives straight under it with "0/10 ..." lines, "Description"; then the dark reward band with light serif headings between gold rules ("Rewards", then the Almanac's own facts), reward name boxes (dark box, bronze edge), XP and money as reward slots. **Money and currencies** (2026-10-04): always the game's way, each amount followed by its coin art (gold, silver, copper icons, empty coins left out); other costs as amount + the item's or currency's icon (`ns.MoneyText`, `ns.CostText`). Never "g / s / c" letters or words like "tokens".
   **The game's own art, read with `/aa art` (2026-10-04):** quest parchment `QuestDetailsBackgrounds`; reward band `QuestLog-reward-tile-vertical` + `QuestLog-reward-header-top` (55) + `QuestLog-reward-bottom` (87); "Rewards" in `QuestFont_Huge` (0.9, 0.79, 0.67), "You will receive:" in `QuestMapRewardsFont`; reward item = 30 px icon + `WhiteIconFrame` (651080) tinted by quality + `QuestItemBorder` name frame, name `GameFontHighlightSmall`, count `NumberFontNormalSmall`; XP icon file 894556 with `NumberFontNormal`; title `QuestTitleFont` (black), body `QuestFont` (0.18, 0.12, 0.06), objectives `QuestFontNormalSmall`. Scroll bars: `minimal-scrollbar-*`. Side tabs: `common-sidetab`, `-selected`, `-hover` (55 x 60). Skill bars: `Profession-ProgressBar-BG` / `-frame`, fill `Skillbar_Fill_Flipbook_<Profession>`, flare `Skillbar_Flare_<Profession>`, text `Number12FontOutline`. Window frame: `UI-Frame-Metal*` (PortraitFrameTemplate). Profession cards: `Profession-overview-Card-<Profession>`.
8. **Standalone.** Azeroth Almanac is never installed alongside Plus Everything, so no conflict handling is needed. It borrows code from Plus Everything (`D:\Plus Everything`) but has its own files and data.
9. **No completionism** (decided 2026-10-03). No completion percentages, progress bars or "x of y" totals anywhere. Progress is shown only through what has been found: running counts ("214 creatures discovered"), research tiers per creature, milestones based on your own discoveries, and a journal of discoveries. Nothing implies a fixed amount left to find. (This also means the database doesn't need complete or Forever-exact totals, and Questie isn't needed.)

---

## 0. Combat log test – do first [ ]
How much the Bestiary can record on its own depends on what this client lets addons read. Plus Everything's recorder already has a test for this.
- [ ] Log in with Plus Everything, run `/ep bestiary probe`, fight 2-3 mobs (at least one spellcaster). The probe runs 60 seconds, or run the command again to see the result sooner.
- [ ] Then run `/ep bestiary` for the counters since login.
- Evidence so far (2026-10-03, from `PlusEverythingDB` saved data): Plus Everything's Bestiary recorder has been installed and switched on since 2026-10-02 15:04, across several characters playing to level 24, and `beastLog` is **completely empty**. Neither the combat log nor the spell-cast fallback saved a single creature. In the same period `learning` saved quest givers, finishers and positions, plus loot drops with NPC IDs and mob names. So loot, quest and unit reads work; combat reads look blocked or secret. The probe will confirm which.
- [x] **Result (2026-10-03): in-game combat log is off-limits, the text combat log is complete.** Addons get an error registering `COMBAT_LOG_EVENT_UNFILTERED` on this engine (WoW Forever's own damage meter uses `C_DamageMeter` for that reason). But `/combatlog` writes everything to `Logs\WoWCombatLog-<date>.txt` (version 22, build 1.60.1). Test: 3 fights in Ashenvale (Wildthorn Stalker, Thistlefur Shaman, Thistlefur Avenger), 1,436 lines, nothing hidden. With Advanced Combat Logging on, each event carries the unit's current/max health, attack power, spell power, armor, power, world position, uiMapID, facing and level; damage events carry amount, pre-mitigation amount, overkill, school, resisted/blocked/absorbed and crit. Got: health (642 / 863 / 803), levels (20 / 24 / 23), armor, attack power, melee ranges, abilities (Web, Bloodlust, Healing Wave cast time from START→SUCCESS), damage shield (Coat of Thistlefur), debuffs applied, deaths, dodge/parry/miss against us, totems summoned, positions.
- Notes: the client writes the file in chunks (it was header-only until flushed), so read it after logging stops or keep a reader tailing it. Advanced Combat Logging must be on (`ADVANCED_LOG_ENABLED,1` in the header). Positions are world coordinates; convert to map 0-1 coordinates with the UiMapAssignment DB2 or in game.
- [x] **Almanac Probe results (2026-10-03, same fights in the combat log for comparison, Ashenvale, 3 creature kinds, 16 kills):**
  - Blocked for addons (popups): registering `COMBAT_LOG_EVENT_UNFILTERED` (no events arrive) and `LoggingCombat(true)`.
  - Readable in and out of combat: creature GUID / NPC ID, name, level, classification, type, family, reaction, dead or alive (target, mouseover, nameplates); tooltip lines; loot with source GUID; `UNIT_COMBAT` on the player (every hit, miss, parry, dodge, block on you with amount and school, but no attacker).
  - Readable after combat: `C_DamageMeter` damage taken per attacker name and spell (per-fight totals, classification), damage dealt per enemy name; debuffs on you with their source unit (Web), only if still on you when combat ends.
  - Always secret: creature health and max health (even out of combat), power; enemy cast spell ID and the whole cast bar (name, times, interruptible). Casts can be counted per caster, not identified.
  - In combat, `C_UnitAuras.GetAuraDataByIndex` errors ("Auras cannot be accessed when secret while tainted").
  - Only in the text log: max health (803/863/691), armor, attack power, non-damage abilities (Bloodlust, Healing Wave) and their cast times, interrupts, per-hit ranges and crits by ability, creature positions, your misses against them.
  - Only in game: loot, creature type/family/classification, tooltip text.
- [x] **Enemy heals test (2026-10-03, probe 0.2, all 11 damage meter views saved after each fight):** no view names an enemy heal. Healing Done / HPS / Absorbs list only the group. Enemy Damage Taken gives each enemy's total damage taken per fight (by name and creature ID, no spell breakdown). Interrupts stayed empty: the cast was stopped with a stun, which isn't an interrupt (a real kick/pummel still to test).
  - Indirect method that works: in a fight with one creature of a kind that dies without healing, damage taken ≈ its max health (Thistlefur Shaman 863 / 864 vs 863 in the log, 842 vs 803 at level 23, overkill included). When it takes much more than that, it healed: one shaman took 1,426 = 803 health + 580 healed (Healing Wave 281 + 299 in the log) + overkill. Combined with "started a cast" (caster readable, spell hidden), the Almanac can say "heals itself, about 580 in one fight" and learn approximate health, without the companion.
  - Limits: the meter groups by name, so mixed levels of one name blur the estimate; overkill adds up to ~60; the heal spell's name and cast time stay unknown.
- **Decision needed:** a companion app on the player's PC reads the text log and writes a data file the addon loads (see section 2b).
- [ ] Old checklist (superseded):
  - Combat log registers? (`registered` / `REFUSED to register` / `not available`)
  - Combat log events: total vs readable
  - Damage events from creatures: total vs amount readable
  - Enemy spell casts: total vs spell readable
- Outcomes:
  - **Combat log readable with amounts:** full Bestiary (abilities, damage ranges, crits, DoTs, debuffs, immunities).
  - **Readable but amounts are secret:** abilities, effects and immunities only. Damage ranges are left out, or estimated from the player's health change if we decide that's worth it.
  - **Blocked:** spell-cast events and enemy cast-bar polling only (abilities, cast times, interruptible). No damage.

---

## 1. Foundation [x] (verified in game 2026-10-03, version 0.1.1; built 2026-10-03, `D:\Azeroth Almanac\AzerothAlmanac`, installed in AddOns)
Built: `Core.lua` (modules, message bus, shared event frame, helpers, `/aa` and `/almanac`), `Locale.lua` (string table), `Modules\Store.lua` (saved data v1 with migrations, account-wide `found[kind][id]` with first/by/last/count/characters, capped journal, stats and size), `Modules\Characters.lua` (registry, level history with place), `Modules\Places.lua` (zones, subzones, dungeons and raids; explored map areas), `UI\Widgets.lua` (inset, parchment, search, virtual list, detail pane, addon-drawn menu), `UI\Toast.lua`, `UI\Window.lua` (portrait frame, bottom tabs, Esc, saved position/scale/page), pages Journal / Places / Characters plus placeholders, `UI\MinimapButton.lua`, `UI\Options.lua` (game's AddOns settings), `Bindings.xml`.
Tested against a simulated client (normal run, missing templates, hidden values, journal cap, alt login, reset).
- [x] 0.1.1 fixed: tainting `StaticPopupDialogs` (caused the "blocked" popup), missing icon files (candidate lists), continents recorded as zones (skipped + cleaned up), class-colored names on parchment, "also found by", scrollbars only when needed. Blocked-action recorder added (`/aa stats`).
- [x] Verified in game: loads after a fresh login with no errors; `/aa`, minimap button and keybinding open it; tabs, Esc, position; options panel; places, journal entries and toasts; an alt sees the same places with "first discovered by".
- Not yet: time played per character (asking the game prints it in chat; needs a quiet way).
- Original checklist:
Taken from Plus Everything, renamed and trimmed.
- [ ] `Core.lua`: module system (`ns:NewModule`), defaults merge, `ns.Readable` (secret-value guard), `ns.Print`, money and quality-color helpers. Slash `/aa` (with `/almanac` as an alias).
- [ ] `AzerothAlmanac.toc`: interface 16001, `SavedVariables: AzerothAlmanacDB`.
- [ ] `WindowUtil.lua`: collapsible windows, class emblems.
- [ ] `MinimapButton.lua`: left-click opens the Almanac, right-click a quick menu, addon compartment entry.
- [ ] Settings: a small settings page using the pattern in Plus Everything's `Settings.lua` (much less than its 95 KB), plus the game's AddOns options entry.
- [ ] Main window shell: portrait frame with native tabs, one tab per catalogue plus the Overview (hub).
- [ ] Character registry from Plus Everything's `Inventory.lua` (name, realm, class, race, level, last seen). Inventory's bag/bank/mail tracking only where it feeds item discovery (see 4).

## 2. Discovery recorder [ ]
One recorder feeds every catalogue. Built from Plus Everything's `Learning.lua` and `BestiaryLog.lua`, with guild sharing removed.
- [ ] Shared record: `db.found[kind][id] = { first = time, by = "Name-Realm", last = time, ... }` for every kind (creature, item, quest, merchant, trainer, npc, zone, subzone, dungeon, boss, flightpath, spell, recipe).
- [ ] Per character: `db.chars[key].quests` (completed), `.spells`, `.recipes` (learned), `.flightpaths` (known).
- [ ] A "New discovery" toast in native style (the game's alert frame art and sound), each kind can be switched off.
- [?] Events to verify on this client: `COMBAT_LOG_EVENT_UNFILTERED`, `UNIT_SPELLCAST_*`, `NAME_PLATE_UNIT_ADDED`, `PLAYER_TARGET_CHANGED`, `UPDATE_MOUSEOVER_UNIT`, `LOOT_READY`/`LOOT_OPENED`, `CHAT_MSG_LOOT`, `BAG_UPDATE_DELAYED`, `QUEST_DETAIL`/`QUEST_ACCEPTED`/`QUEST_TURNED_IN`, `GOSSIP_SHOW`, `MERCHANT_SHOW`/`MERCHANT_UPDATE`, `TRAINER_SHOW`/`TRAINER_UPDATE`, `TRADE_SKILL_SHOW`, `TAXIMAP_OPENED`, `ZONE_CHANGED*`, `ENCOUNTER_START`/`ENCOUNTER_END`, `PLAYER_ENTERING_WORLD`. Read every value through `ns.Readable`.

## 2b. Combat Journal companion (proposed 2026-10-03) [~]
Addons can't read combat events in game, so a small program on the player's PC reads `Logs\WoWCombatLog-*.txt` and writes `Interface\AddOns\AzerothAlmanac\Journal\CombatJournal.lua`, which the addon loads (picked up on `/reload` or login).
- [ ] Parser for combat log version 22 with the advanced block (19 fields: info GUID, owner GUID, health, max health, attack power, spell power, armor, 3 unknown, power type, power, max power, cost, x, y, uiMapID, facing, level).
- [ ] Only creatures (`Creature-` GUIDs, NPC ID is part 6); skip players, player pets and totems a player summoned.
- [ ] Per creature: max health and levels, armor, attack power, abilities with counts and cast times, damage per ability (low/high/average, crits, DoTs, pre-mitigation), auras applied, summons, heals, deaths, our misses (dodge/parry/miss/immune/resist), positions.
- [ ] Remembers how far it has read each log file, so each run only adds new lines; merges into the existing journal.
- [?] Addon side: `LoggingCombat(true)` to switch logging on at login (check it's allowed on this client) and a reminder to turn on Advanced Combat Logging.
- [?] Confirm `/reload` re-reads a changed Lua file listed in the TOC on this client.
- Open: how the companion is delivered (a small .exe / Node script / tray app) and how it runs (on demand, at Windows start, watching the folder).

## 2c. Unlock rules: evidence and research tiers (decided 2026-10-03) [ ]
Both kinds of trigger apply. A field is revealed by whichever comes first.

**Evidence** (something the addon can see in game confirms a fact):

| In game | Reveals from the hidden database |
|---|---|
| Seen (target, mouseover, nameplate) | Name, level range, creature type, family, rarity |
| An ability hits you (damage meter spell ID) | That ability, with its description |
| A debuff it put on you (readable after combat) | That debuff / ability |
| It starts a cast (spell hidden) | One of its cast-time abilities: the only one if it has one; otherwise the next unrevealed one, after enough casts |
| Takes clearly more damage than its health (heal estimate) | Its heal ability |
| Killed | Health, armor |
| Looted an item from it | That item in its loot table (others shown only as a count) |
| Seen in a zone | That spawn area on its map |

**Research tiers** (by kills, account-wide; the page shows the tier and the kills needed for the next):

| Tier | Needs | Unlocks |
|---|---|---|
| Sighted | Seen once | The basics (as above) |
| Fought | 1 kill | Health, armor, damage range |
| Studied | 5 kills | Every ability, including buffs and heals never seen (Bloodlust, Vengeance) |
| Mastered | 10 kills | Immunities, resistances, full loot table with drop rates, all spawn areas |

- [x] Bosses (decided 2026-10-03): Studied at 3 kills, Mastered at 5. Normal creatures: Studied 5, Mastered 10.
- [ ] Thresholds are settings (defaults above). Rares: decide (suggest the boss counts).
- [ ] When a tier is reached: a native-style toast ("Thistlefur Shaman: Studied").
- [ ] Observed values beat database values: health learned from damage taken, abilities seen, own drop rates.
- [ ] The same idea for other catalogues: quests (next step of a chain revealed on completing the current one), items (each source revealed as you meet it), dungeons (boss list revealed boss by boss), zones (subzones as you enter them).

## 3. Bestiary – creatures [x] (phase 2 verified in game 2026-10-03, version 0.2.1)
Built: `Modules\Bestiary.lua` (seen from target / mouseover / nameplates / boss frames: name, NPC id, levels, type, family, rarity, zones; friendly NPCs and player pets skipped. Kills from death checks and lootable corpses, ignoring creatures tapped by others. After each fight, Blizzard's damage meter: abilities that hit you per fight, and Enemy Damage Taken for clean kills = health samples per level (median shown); a sample over 125% of the known health = heal, recorded as count and largest heal. Casts started (spell hidden), debuffs left on you (read out of combat), loot per corpse with drop rates, money per corpse, skinning / gathering via the gathering cast. Research tiers with toasts at Studied and Mastered. Tooltip line "Almanac: Studied - 7 kills (3 to Mastered)"). `UI\Pages\Bestiary.lua` (list with search, rarity / type filter, this zone only; parchment page with the 3D model by NPC id (drag to turn), level, rarity, tier and kills to next, health, heals, abilities with the game's icons and descriptions, casts, debuffs, loot with %, money, gathering, zones, who met it). `/aa bestiary <name>`.
- Finding: the damage meter's Current session holds the last fight only (probe captures: 37 / 19 / 72 / 20 s, totals for that fight), so it's read once per fight, without differencing.
- [x] Verified in game: creature records, tiers (Defias Bandit reached Mastered), health from a lone kill (Defias Rogue Wizard 184), Frostbolt with icon and description, loot %, money, rare color, model, tooltip line.
- [x] 0.2.1: plurals ("1 kill", "once", "twice"), debuff merged into its ability line, critter icon (wolf, grey).
- [ ] Still to see: heal detection on a healer, skinning results, filters.
- Original plan:
From Plus Everything: `BestiaryLog.lua` (recorder, ~1,000 lines) and `Bestiary.lua` (tooltip). `BestiaryData.lua` and `BossData.lua` are **not** shipped for display.
- [ ] Discovered when a creature is targeted, moused over, seen on a nameplate or fought (decide which counts: seen vs fought, maybe both as two levels).
- [ ] Recorded per creature (NPC ID): name, creature type and family, classification (normal / elite / rare / rare elite / boss), level range, health seen, zones and positions where met, times killed, abilities used (count, cast time, interruptible, health % when cast), damage per ability and melee (low / high / average, crits and DoTs separately, depending on 0), debuffs applied, summons, self-heals, immunities and resists to your spells, and loot (see 4).
- [ ] Own drop rates: kills vs drops for each item, so the Almanac shows "dropped 3 times in 41 kills" instead of outside drop chances.
- [ ] Tooltip: only what has been observed for that creature. Undiscovered abilities are not listed.
- [ ] Bestiary tab: browse by zone, creature type and family; detail page with the game's 3D model (`PlayerModel`/`DressUpModel` with `SetCreature` where the client allows it, else the portrait), stats, abilities, loot, where met.
- Commands: `/aa bestiary probe | stats` (kept from Plus Everything for testing).

## 4. Items [?] (phase 4 built 2026-10-04, version 0.4.0)
Built: `Modules\Items.lua` (looted, with the source: creature, object, container, fishing; received and crafted from the game's own loot messages; bought; on a merchant; offered as a quest reward; carried in bags, bank or worn; per-character belongings for "owned by"; uncommon+ items you actually got go in the journal, the rest quietly; rare+ get an alert), `Data\Items.lua` + `Modules\ItemDB.lua` from `tools\build_items.py` (11,889 items: Classic droppers with chances, vendors, quest rewards, chests / herbs / veins; names of lootable objects, shown only once looted; world drops counted, not listed), `UI\Pages\Items.lua` (search, quality filter, owned by this character; page with icon (game tooltip on hover, shift-click links), type, level, sell price, first found, owners, dropped by with your rate and Classic chance at Mastered, sold by with price and place, quest rewards, objects, containers, fishing, crafting; unmet sources only counted).
- [?] Verify in game.

From Plus Everything: `Encyclopedia.lua` (UI and item pages). `ItemDB.lua`, `ItemData.lua` and `ItemSources.lua` are **not** shipped for display.
- [ ] Discovered when looted, seen in loot, received (quest reward, mail, trade, crafted), bought or seen on a merchant, owned in bags/bank, seen as a quest reward choice, or hovered in a tooltip (decide whether hovering another player's link counts).
- [ ] Recorded: item ID, how it was found, sources seen (creature, object, quest, merchant, crafted, container), and which characters have owned it.
- [ ] Item pages use the game's own tooltip and item info for discovered items only.
- [ ] **Remove** the "search by item ID" from the Encyclopedia: the game would answer it for items never found.
- [ ] Quality and type filters; counts of items found per type and slot.

## 5. Merchants [?] (phase 4 built 2026-10-04, version 0.4.0)
Built: `Modules\Merchants.lua` (on opening a vendor: name, title from the tooltip, position, your standing, full stock with price, stack, limited quantity, special costs; price changes kept; purchases recorded), `UI\Pages\Merchants.lua` (by zone; search by merchant or by anything they sell; page with place and coordinates, "Show on map" sets the game's waypoint, standing, stock with icons and prices, earlier prices). Alerts for new merchants.
- [?] Verify in game.

Every vendor opened is saved, account-wide. Page reading comes from Plus Everything's `MerchantList.lua` (reads the whole stock, all pages).
- [ ] Who: NPC name, title (for example "Weaponsmith"), NPC ID, faction reaction.
- [ ] Where: zone, subzone and map position (from where the player stands when the window opens), shown as a pin on the map from the merchant's page.
- [ ] Stock: every item, with price, stack size, alternate currency / item costs (`GetMerchantItemCostInfo`), and limited-stock items with the quantity seen.
- [ ] Prices include the reputation discount, so the snapshot also saves the player's standing with the vendor's faction. Each visit updates the snapshot and the "last checked" date; earlier prices are kept if they differ.
- [ ] Items on sale count as seen in Items (source: "sold by"); recipes on sale count toward Recipes.
- [ ] Merchants tab: by zone, search by item ("who sells this" among merchants you've met).

## 6. Quests [?] (phase 5 built 2026-10-04, version 0.5.0)
From Plus Everything: `Questopedia.lua` + `QuestopediaLogic.lua` (UI and status logic). `QuestData`, `QuestopediaData`, `QuestRewards` and `QuestieLive` are **not** shipped or used in game.
- [?] Recorder `Modules\Quests.lua`: offered (`QUEST_DETAIL`: title, description, objectives, rewards, choices, money, XP, giver NPC / object / item with position), progress (`QUEST_PROGRESS`: text, items to bring, ender), completion (`QUEST_COMPLETE`: text, ender), handed in (`QUEST_TURNED_IN`: done, times, level, journal "Completed: ..."). Quest log scan (heading, level, objectives; description of quests taken before install by briefly selecting them). Abandoned = gone from the log and not flagged completed for 3 s.
- [?] Quests each character finished before install (`C_QuestLog.GetAllCompletedQuestIDs`), titles from the game (`GetTitleForQuestID`, `RequestLoadQuestByID` + `QUEST_DATA_LOAD_RESULT`), quiet, marked "done before the Almanac began".
- [?] Per character: `chars[key].q[questID] = { s = o/a/d/x, t, c, lv }`. Quest givers and enders kept quietly as `found.npc` / `found.object` (groundwork for section 10).
- [?] Chains: a quest offered within 60 s of a turn-in is linked when the database says it follows; for quests the database doesn't know (Forever's own), when the same NPC offers it within 20 s.
- [?] Hidden database `Data\Quests.lua` (tools\build_quests.py, VMaNGOS, 4,433 quests, 240 KB): level, min level, zone, starters, enders, follow-ups, creatures / objects / items asked for, race and class masks. No text. Reveals: the ender's name once a character has taken it and you've met them; creatures it asks for that are in your Bestiary (others counted); follow-ups only after a character completes it (count + "X may have more for you" when you've met the giver), filtered to the playing character's race and class.
- [?] Quests page: list by quest log heading (collapsible), status icons (done check, ?, !, abandoned), difficulty colours, filter (all / in log / done by this character / not done / offered / abandoned), search (title, objectives, giver). Parchment detail like the quest log: objectives, description, rewards (reward slots), progress and completion text, quest givers (click = waypoint), what it asks for (click = Bestiary / Items), the story (before / after), your characters.
- [?] Cross-links: Bestiary "Wanted for quests", Items "Quest rewards" as clickable slots + "Wanted for quests", Characters "Quests done". Toast "New quest found" (option).

## 7. Zones and exploration [?] (phase 6 built 2026-10-04, version 0.6.0)
- [x] Discovered on entering a zone or subzone (`ZONE_CHANGED*`, `GetSubZoneText`, `C_Map.GetBestMapForUnit`) (since 0.1).
- [?] Exploration: the game's "Discovered X: N experience gained" message (`ERR_ZONE_EXPLORED_XP` / `ERR_ZONE_EXPLORED`) records the place for that character (`chars[key].explored[id] = { t, xp }`), creating the place if the message comes first. Map areas uncovered kept per character (`chars[key].mapAreas[map]`).
- [?] Zone page: the zone's own map drawn from the game's map art (`C_Map.GetMapArtLayers` / `GetMapArtLayerTextures` base tiles + `C_MapExplorationInfo.GetExploredMapTextures` overlays for the character you're playing, laid out like the world map's exploration pins), pins for merchants (vendor icon, click = Merchants) and quest givers (!) met there, and an arrow where you stand. Then General (continent, creature levels met, first discovered, visits), places found (with "explored, N experience"), creatures (click = Bestiary), merchants, quests, and each character's exploration.
- [?] Place page: explored by (date, experience), merchants and quests offered there.
- [?] Bestiary "Where" zones are slots that open the zone in Places. Detail panes keep their scroll position when the page refreshes.

## 8. Dungeons and raids [?] (phase 8 built 2026-10-04, version 0.9.0)
- [?] Recorder `Modules\Dungeons.lua`: runs per character (entering to leaving: visits, time inside, last visit; journal "Deadmines: 4 bosses in 38 min"; quickest run with a kill), the floors' maps (uiMapID + name), bosses from the game's `ENCOUNTER_START` / `ENCOUNTER_END` (kills, wipes, NPC from boss1, where met) and, for bosses without encounters, from the Bestiary's kills of NPCs the records list as that dungeon's bosses (`ns:Fire("KILL")`, new). Dungeon floors no longer recorded as zones.
- [?] Hidden database `Data\Dungeons.lua` (tools\build_dungeons.py, from Plus Everything's AtlasLoot Revival data, MIT, `Licenses\AtlasLootRevival-LICENSE.txt`; Forever's new dungeons by boss name): map ID, levels, entrance zone, raid, bosses (NPC, kind, loot with chances). Wowhead-derived BossData not used.
- [?] Dungeons page (replaces the empty Lore tab; lore will come into the Journal): dungeons and raids entered, by level; floors on the game's map art with a skull where each boss was met; General (kind, entrance, levels, first entered, visits, quickest run); bosses met (kills, wipes, tier; click = Bestiary) and a count of the rest; loot you've had from them and a count of what they carry; your characters' visits, boss kills, time inside. Places' dungeon entries open it.

## 9. Trainers: spells and recipes [?] (phase 7 built 2026-10-04, version 0.7.0)
Replaces Plus Everything's `ClassSpells` (Wowhead data) and `Recipedia` (`RecipeData.lua`) with trainer snapshots. Their trainer-reading and profession-window logic is reused.
- [?] `TRAINER_SHOW`: every service the trainer lists, with the filters cleared and put back (spell ID from `C_TooltipInfo.GetTrainerService`), name, rank, required level, required skill, cost, item made; "used" marks it learned for this character. Trainer recorded like a merchant (name, title, position, group, what it teaches); journal line and "New trainer met" toast. Groups: `class:<CLASS>`, `skill:<Profession>`, `other:<title>` (weapon masters, riding).
- [?] Profession window (`TRADE_SKILL_SHOW` / `LIST_UPDATE` / `NEW_RECIPE_LEARNED`): learned recipes with reagents, item made, category, and the profession's skill level. Skills list (`GetSkillLineInfo`) keeps every character's profession levels. `LEARNED_SPELL_IN_TAB` marks new spells learned.
- [?] Trainers page (one page for spells and recipes, to keep the side tabs fitting): groups by class and profession (yours first), an Overview per group (each character's profession skill bar in that profession's own bar art, or level and spells learned; trainers met; recipe items found in Items, by the item's recipe kind), then spells / recipes coloured as a trainer colours them for the character you're playing (green now, red not yet, grey learned). Spell page: requirements, cost (coins), makes, reagents (click = Items), taught by (click = waypoint), your characters' status.
- [?] Rank details (0.7.1): each spell's own tooltip lines (mana, cast time, cooldown, range, description with its amounts) from `C_TooltipInfo.GetTrainerService` at the trainer (kept) or `GetSpellByID` (live); "All ranks" lists every rank trainers have shown, with level, cost and what each does.
- [?] Items: "Made by" and "Reagent for" from recipes you've seen. Places: trainers in the zone (list and map pins).

## 10. NPCs and flight paths [?] (built 2026-10-04, version 0.13.0)
- [?] Townsfolk page (`UI\Pages\Townsfolk.lua`, side tab after Trainers): everyone met - townsfolk records, merchants, trainers and quest givers merged by NPC ID - listed under their Townsfolk group (Innkeepers, Flight masters, Warrior trainers ... Quest givers), with faces. Filter: everyone / trainers / services / vendors / quest givers / flight paths; search by name, title or place. Page: portrait, title, where (talked-to spot, else their database spawn near where you met them), who they serve, first met / also met by, links to their stock (Merchants), their training (Trainers), their flight path, quests they give and take in. Show on map (Places with their face pinned; Places:ShowZone takes a generic pin now) and Set waypoint.
- [?] Flight paths (`Modules\Flights.lua`): every node on the flight map when it opens, per character (`known[char]`); the node you stand at gets your exact position and its flight master; others get their zone from the node name and a position converted from the flight map where the client can. New node learned = journal entry and a "New flight path" alert. Node page: zone, known by, flight master, flights timed from and to it (the travel helper's times).
- Side tabs shrink to fit when there are more pages than the window's height holds.

## 11. Hidden database (build tools) [?] (phase 3, creatures built 2026-10-04, version 0.3.0)
- Built: `tools\build_creatures.py` reads the VMaNGOS SQLite snapshot (release db_latest, db-sqlite-4641790.zip, downloaded from github.com/vmangos/core) and writes `Data\Creatures.lua`: 10,376 creatures, 1.8 MB (levels, rank, type, family, Classic health range from class/level stats x multiplier, armor, melee per hit, spell list, loot with chances (groups and references resolved, quest drops marked), money range, skinning table, immunity masks, resistances). Credit and license: `Licenses\VMaNGOS.txt` (GPL-2.0).
- `Modules\CreatureDB.lua` decodes it and decides what's unlocked: Fought = Classic health / armor / melee / money; Studied = every ability; Mastered = immunities, resistances, full loot table with Classic chances, skinning. Evidence: abilities that hit you, debuffs, named casts, a lone ability when seen casting, items looted. Before a tier: counts only ("2 more abilities not yet seen", "6 more common drops and 33 rare ones").
- Finding: Forever's creatures have more health than the Classic formula (Thistlefur Shaman 863 vs 582 at level 24, 803 vs 544 at 23; Wildthorn Stalker 691 vs 531; Defias Rogue Wizard 184 vs 160). Observed health is always shown first; Classic is labelled "Classic records".
- [?] Verify in game: tier reveals on the Bestiary page, the 1.8 MB file's load time.
- [ ] Next for the database: Forever cache overlay (names, ranks, Forever-only creatures), CMaNGOS gap fill, spawn zones, items / quests / vendors / trainers tables for the later catalogues.

### Research (2026-10-03)
- **VMaNGOS** (github.com/vmangos/core, GPL-2.0): patches 1.2-1.12.1, every row tagged with the patch it belongs to, focus on accuracy; ships one MySQL world-database snapshot. creature_template (levels, health, armor, damage, resistances, mechanic / school immunities, loot, skinning loot, gold), creature_spells (each creature's spells with chances and timers), spawns, loot tables with chances, quests, vendors, trainers.
- **CMaNGOS classic-db** (github.com/cmangos/classic-db, GPL-3.0): 1.12; Full_DB + updates. creature_template with the same fields (health / damage as multipliers), creature_spell_list (spells, chances, timers, health conditions) + EventAI scripts, spawns, loot, quests, vendors, trainers.
- AzerothCore / TrinityCore: Wrath of the Lich King era, not used.
- **Forever's own cache on your PC** (`Cache\WDB\enUS`, build 70205, binary but readable): creaturecache 1,838 creatures (178 with Forever-only IDs above 200000, e.g. Highland Lurker, Maddened Rotclaw, High Priestess Mims), gameobjectcache 1,121 objects, questcache 72 quests. Creature records hold name, title, type, family, rank, model, health / mana multipliers (relative, not absolute health), quest items. No abilities or loot.
- Recommendation: VMaNGOS as the baseline (single snapshot, patch tags let us take the 1.12 state, per-creature spell lists), CMaNGOS to fill gaps; Forever cache for exact names / types / ranks and to spot Forever-only creatures; your play (and testers') for everything Forever changed. GPL: ship the data file under GPL-compatible terms and credit both projects in `Licenses\` (not legal advice).
- Fetch: github pages are blocked from the cloud workspace's web reader; the snapshot may need downloading on your PC into `D:\Azeroth Almanac\sources`.


Revised 2026-10-03: full records only, no totals (rule 9). Node scripts adapted from Plus Everything's `tools\gen-*.js`.
- [ ] Layers (decided 2026-10-03):
  1. **Client tables** (spells for players and NPCs, items, zones/areas/maps, factions, skills, creature types): WoW Forever's own client data for the current build (wago.tools CSV for build 1.60.1, already used by `gen-itemdb.js`, or extracted from the local install). Exact for every build; rebuilt each patch.
  2. **An open-source Classic server database** (creatures: levels, health, rank, armor, damage, abilities, immunities, resistances; spawns; loot with drop rates; quests): the Classic baseline. Check the chosen project's license, credit it in `Licenses\`.
  3. **What players discover in Forever**, which replaces or adds to the baseline. Forever-only content comes only from here. For the shipped database: probe saved data and combat logs from your characters (and testers who agree), development-side only.
  4. **Questie, optional at runtime:** if QuestieDB is installed, read it through LibQuestieDB while the game runs to fill gaps (as Plus Everything's QuestieLive does). Nothing from Questie is shipped.
- [ ] No Wowhead scraping for anything shipped (Plus Everything's `gen-bestiary.js`, `gen-bossinfo.js`, `gen-items.js` fetch Wowhead pages; replace those sources).
- [ ] AtlasLoot Revival (MIT) for dungeon boss lists and loot, credited as in Plus Everything.
- [ ] Spell IDs only for abilities; the game supplies name, icon and description at reveal time.
- [ ] Size target: a few MB at most (Plus Everything ships ~6 MB of data); compact arrays keyed by ID.

## 12. Overview: the adventurer's journal [?] (built 2026-10-04, version 0.14.0)
Revised 2026-10-03: no percentages or totals (rule 9).
- [?] Overview: the Journal page's home (right pane, Overview button in the header) rather than a new tab - each catalogue's count with "+n this session", research (creatures studied / mastered, kills, quests completed, gathering), the latest milestones, recent discoveries, and (account view) who was first to find things, per character.
- [?] Journal: timeline grouped by day (Today / Yesterday / date, collapsible), filters by character, kind and zone, search.
- [?] Milestones (`Modules\Milestones.lua`): firsts (first elite, rare, boss slain, mastery, dungeon, flight path, epic, catch, herb, vein, pelt, second character) and count series (creatures, mastered, kills, zones, places, dungeons, items, rare items, quests done, merchants, trainers, townsfolk, flight paths, herbs, veins, catches, pelts, characters). Earned once per account with character and date; a toast (orange, loot-toast style) and a journal entry. Milestones already met on first run are recorded quietly ("before milestones").
- [?] Per character view versus account view: the character filter switches the overview, milestones and timeline.

## 13. Gathering and fishing [?] (built 2026-10-04, version 0.14.0)
- [?] Nodes (`Modules\Gathering.lua`): herbs, veins, chests and other objects by name (object ID from the loot source GUID, named from the hidden item database), kind from the gathering cast, where (zone counts and spots), your skill when gathered, what came out (times and quantity).
- [?] Fishing per zone: catches, your fishing skill, pools fished (pool name from the loot source).
- [x] Skinning yields per creature: already on the creature's Bestiary page.
- [?] Research tiers by times gathered: Studied (5) reveals everything a node can hold from the Classic records (greyed until found), Mastered (15) adds the Classic chances. Tier-up toasts.
- [?] Gathering page (`UI\Pages\Gathering.lua`, side tab after Places): Herbs, Ore and stone, Chests and objects, Fishing, Skinning; Show on map pins every spot in Places (Places pins take a list of spots now).
- The Lore placeholder tab is gone until section 14 is built (room for the Gathering tab).

## 14. Lore and books [ ] (added 2026-10-03)
- [ ] Library: every book, letter, plaque and scroll read (`ITEM_TEXT_READY`: title, pages, text, material), where it was found.
- [ ] Quest text archive: the text of each quest as you read it (offer, progress, completion), kept with the quest's page.
- [ ] NPC dialogue: gossip text of NPCs you talk to, kept with the NPC's page.
- [ ] A reading view on the game's book/parchment art.

## 15. Rares [ ] (added 2026-10-03)
- [ ] Every sighting of a rare or rare elite (classification from the unit): time, place, character. Kills and loot as in the Bestiary.
- [ ] Learned respawn windows from repeated sightings at one spot ("seen here 3 times, about every 40-60 minutes").
- [ ] Optional alert when a rare you've met before is on a nameplate.

## 16. Factions [ ] (added 2026-10-03)
- [ ] Factions met (as they appear in the reputation list) per character, with standing over time (a dated history, kept small).
- [ ] What raised it, where the game says (quest turn-ins, kills).

## 17. Places and services [ ] (added 2026-10-03)
- [ ] Inns (and where each character's hearthstone is set), graveyards / spirit healers, banks, auction houses, mailboxes, stable masters, guild masters, battlemasters, dungeon entrances. From the interaction windows (`PLAYER_INTERACTION_MANAGER_FRAME_SHOW` type) and gossip, with position.
- [ ] Boats, zeppelins and the Deeprun Tram: routes ridden and trip times (Plus Everything's Travel / Boats learning).

## 18. Character stories [ ] (added 2026-10-03)
- [ ] Per character: where and when each level was reached, first visits to zones, first kill of each creature kind, deaths (where, when, and what killed you from the damage meter's Deaths view, to verify), time played.
- [ ] Shown as part of the journal (section 12), filterable by character.

## 19. More on items [ ] (added 2026-10-03)
- [ ] Item sets: pieces found per set (set ID from the item info, to verify), revealed set bonuses as pieces are found.
- [ ] Random suffixes seen ("of the Bear") per item.
- [ ] Containers opened (clams, lockboxes, bags from quests) and what was inside.
- [ ] Things you crafted (and first crafts), linked to Recipes.

## 20. World events [ ] (added 2026-10-03)
- [ ] Holidays and world events taken part in (event quests, event vendors, event items), by year.
- [?] How to read the active event on this client (calendar API) – to check.

## 21. Data plumbing [ ] (added 2026-10-03)
- [ ] Creature models and portraits: show the 3D model by NPC ID (`SetCreature`) for creatures already seen (probe 0.3 `/aap model`, `/aap model2 <id>`).
- [ ] Names: creatures can't be looked up by ID offline, so names (and other text) are saved when met; the hidden database only reveals records of creatures already discovered.
- [ ] Positions: the addon knows only the player's position; pins mean "met around here". Store rounded positions, a few per creature per zone.
- [ ] Forever-true source: the game's own cache (`Cache\WDB\enUS\creaturecache.wdb`, `gameobjectcache.wdb`, `questcache.wdb`, `pagetextcache.wdb`, and `Cache\ADB\enUS\DBCache.bin` hotfixes) holds the server's records of everything the client has seen. A build tool reads these from your PC and from testers who agree (development side) to correct the hidden database for Forever.
- [ ] Classic server database choice (license, quality, closeness to Forever).
- [ ] Saved-data growth: caps and summaries (positions, journal entries, faction history, kill samples), with a size check and a cleanup routine.
- [ ] Saved-data version number and migrations when the format changes; hidden database rebuilt each Forever patch, with its build number stored.
- [ ] Localization: game-supplied names follow the client language; the Almanac's own text goes through a string table (English first).

## 22. Probe 0.3 – world checks (2026-10-03) [?]
Installed in `Interface\AddOns\AlmanacProbe` (verified on disk). `/aap world` lists what was saved.
- [?] Gossip text and options, quest text (offer / progress / completion), books (`ITEM_TEXT_READY`).
- [?] Merchant stock (price, limited quantity, alternate costs) and trainer services (name, rank, level, cost).
- [?] Profession window recipes, flight map nodes, zone and subzone changes with map exploration functions.
- [?] Factions list, interaction windows (inn, bank, mailbox, spirit healer ...), level-ups, deaths (and the damage meter's Deaths view).
- [?] Loot sources by kind: creatures, objects (herbs, ore, chests), items (containers), fishing; item set IDs.
- [?] Creature 3D model by NPC ID with the creature present (`/aap model`) and gone (`/aap model2 <id>`).
- [?] A real interrupt (Kick / Pummel / Earth Shock) in the damage meter's Interrupts view.
- [x] **Results (2026-10-03), nothing hidden in any of these:**
  - Gossip: full NPC text and options (Raene Wolfrunner, flight master Daelyshia), NPC GUID and name, position.
  - Quest text: title, offer / progress / completion text and objectives, giver, position.
  - Books: title, text, page, material ("Archbishop Alonsus Faol" plaque, Bronze), object GUID, position.
  - Merchants: 3 vendors, 47 items, all fields readable (price, limited stock, alternate cost, link).
  - Trainers: one visit lists every service to 60 (paladin trainer 110, first aid 7) with name, status (available / unavailable / used), icon, required level and cost. No rank text: `GetTrainerServiceInfo` returns name, status, icon here.
  - Profession window: `GetNumTradeSkills` returns 0 on this client; use `C_TradeSkillUI` (`GetAllRecipeIDs`, `GetRecipeInfo`, `GetRecipeSchematic`) as Plus Everything's Recipedia and Crafting already do.
  - Flight map: all 19 nodes with name and status (current / reachable / distant).
  - Factions: name, standing and points (7).
  - Zones: zone, subzone, map and position on each change; `C_MapExplorationInfo` explored textures and area IDs work.
  - Interaction windows: type number + NPC/object GUID, name, position (17 mailbox, 5 merchant, 3 gossip; more types to map).
  - Loot sources: Creature, GameObject (Copper Vein 1731 → Copper Ore, Rough Stone), fishing (source is the bobber object 35591, so fish are recorded per zone), item set IDs readable. Money slots have no item link.
  - Models: `SetCreature(npcID)` works with the creature targeted **and** later by ID alone (NPC 6887, model file 921844) once the client has seen it.
  - Forever-only content seen: flight nodes Summit of Eternity and Tainted Foothills (Mount Hyjal), "zzOLD Powderfuse Port, Riverglades"; faction Azeroth Commerce Authority.
- [ ] Still to see during the build: level-up, death and the damage meter's Deaths view, a real interrupt, the active world event.
- Note for the build: per-source damage meter calls errored in some sessions ("bad argument #3/#4"); the all-views capture (try guid + creature ID, then guid only, then creature ID only) always worked, so use that pattern.

---

## 23. Quality-of-life helpers and the settings window [?] (built 2026-10-04, version 0.10.0)
- Ported from Plus Everything into `QoL\` (tools: scratchpad `port_qol.py` renames frames, popups, addon-message prefixes and `/ep` to the Almanac's). Own namespace `A.QoL` with Plus Everything's defaults; settings and data in `AzerothAlmanacDB.qol` (kept by `/aa reset`).
- Data rule kept: no Questie or Wowhead data. `QoL\Core.lua` serves the Quest Targeter and the gathering highlight from the Almanac (quest enders and objects from the hidden quest database, names only for NPCs and creatures this account has met; quest-item drop sources = met creatures the item database says drop it). `Data\QoLData.lua` (tools\build_qol_data.py, VMaNGOS): 99 vendor materials, 301 disenchant groups.
- `UI\Settings.lua`: the game's Settings panel look (Options_CategoryHeader_1, Options_List_Hover / Options_List_Active, GameFontHighlightHuge title over Options_HorizontalDivider, checkbox-minimal, common-dropdown-icon-back / -next steppers) in the portrait frame. Pages: General, Discovery alerts, Research tiers, Records; Quest Targeter, Gathering; Auction House, Crafting, Disenchanting, Merchants; Flights, Wings & Whispers; My Characters; Group Settings, Healer Assist; Gem Match.
- `UI\Options.lua` is now a short AddOns-panel entry with "Open Almanac settings". Slash: `/aa settings [page]`, `scan`, `inv`, `games`, `heal`, `threat`, `wings`, `node`, `/qt`. Key bindings: settings, My Characters, Gem Match, quest target / clear marks.
- To check in game: every page builds; tooltips (prices, disenchant, crafting cost, who has it); the AH scan; profit card; merchant repair/sell and list view; flight bar; quest tracker buttons; gathering sparkle; My Characters window; Gem Match; Healer Assist test. Plus Everything must be disabled (both would repair, sell and add buttons twice).

## 24. My Characters look across the Almanac [?] (built 2026-10-04, version 0.10.1)
- The user picked My Characters (the ported inventory window) as the Almanac's style. Applied in `UI\Widgets.lua`: list headings in small grey capitals with a grey - / +; entries with a faint hover and a flat gold selection (0.45, 0.33, 0.12, 0.5); round ringed icons for people and creatures (`round = true` on Bestiary, Characters, Merchants, Dungeons, Places), square edged icons elsewhere.
- Detail panes with a top area are now two insets: a header card and the body. Names in Morpheus (`W.HeroFont`); `W.Portrait` ring portraits (Characters: class icon in the class-coloured ring, name in class colour, "Level n race class - realm").
- Section headings ("banner" blocks) are My Characters headings: icon, gold title, grey count taken from a trailing "(n)", thin bronze rule. Stat rows without stripes. Item and spell slots on dark panes: bag empty-slot art, quality edge, count.
- Settings window: the same sidebar (grey capital categories, round icons, flat gold selection), a Morpheus page title with a round icon, gold section headings.
- Parchment kept for Quests and the Journal (the native quest log look asked for earlier).

## 25. Townsfolk on the world map [?] (built 2026-10-04, version 0.11.0)
- Plus Everything's Townsfolk (trainers, services, vendors, mailboxes on the world map; same groups, orb icons, coloured rims option, tooltips "Name (Title)", click for a waypoint, spyglass button top-right of the map: left-click show/hide, right-click checklist) rebuilt without its Questie data.
- Hidden database `Data\Townsfolk.lua` (tools\build_townsfolk.py, VMaNGOS): 1550 townsfolk NPCs with groups from npc flags, trainer type/class, the skills their spells teach and vendor titles; faction from faction_template; world spawns. 55 mailboxes.
- Discovery: `found.townsfolk[npc]` when targeted, moused over, nameplate seen or talked to (name and title from the game, uiMaps and world positions where met); `found.mailbox` when a mailbox is opened. Only spawns within 250 yards of where an NPC was met are shown (spirit healers).
- Map positions: world -> map through C_Map.GetWorldPosFromMapPos (as HereBeDragons does). Without it, the spot where you talked to the NPC. `/aa townsfolk check` reports the distance between the database position of the NPC you're talking to and you.
- Settings: World > Townsfolk (faction, own class trainers only, continent maps, rims, pin size, every group). Minimap pins not done (Plus Everything drew them through Map Pins, not ported).

## 26. Toast tiers [?] (built 2026-10-04, version 0.15.0)
- [?] Every alert has a tier in the item-quality colours: Common (white) routine finds (places, creatures, merchants, quests, nodes, fishing waters); Uncommon (green) zones, trainers, flight paths, elites, Studied, level-ups; Rare (blue) dungeons, rare creatures, bosses met, Mastered, every 10th level; Epic (purple) rare elites, "first" milestones; Legendary (orange) level 60, world bosses. Milestone series climb from Uncommon (first step) to Legendary (last step). Items keep their own quality.
- [?] The tier sets the icon border and name colour, the frame (LootToast-LessAwesome below Rare), the flash strength, the sound (none / chime / quest complete / epic fanfare / legendary) and time on screen (3 s to 6 s).
- [?] Common finds within 1.5 s merge into one alert ("Goldshire and 5 more").
- [?] Settings (Discovery alerts): show alerts for (everything ... legendary only; below it the journal only), sound for (tier). /aa toast and the Test button show one of each tier.

## 27. Gathering nodes on the maps [?] (built 2026-10-04, version 0.16.0)
- [?] Sighted nodes: the soft interact target (what the gathering highlight sparkles) is recorded as sighted with your position, even when you can't gather it; quest objects and non-nodes left out.
- [?] `Modules\NodePins.lua`: every gathered and sighted spot on the world map (map canvas provider, herb button left of the townsfolk spyglass: left-click show / hide, right-click settings) and on the minimap (placed from your world position; zoom, indoors / outdoors and rotating minimap). Pins: the node's main item in a rim by kind (green herb, copper ore, gold chest); sighted-only dimmer and greyed. Hover: node, times gathered / sighted; click: waypoint; shift-click: Gathering page.
- [?] Settings (Gathering page): world map, minimap, herbs / ore / chests, sighted spots, pin sizes.

## 28. Bug check and polish (2026-10-04, version 0.16.1)
- Fixed: skinning counted twice when the loot window fired twice; a corpse looted right after picking a herb counted as skinned; repeat swings at a vein lost their ore; quest-object cleanup left pins on the maps; milestone checks ran every 3 s (now at most every 10 s); the object contents index built during the first sighting (now after login); minimap pins redrawn every tick (now only when they change) and sighted pins doubled on gathered spots; session tables trimmed.
- Fixed: Journal overview tiles did nothing (page links now always open the page); Back on Places returned to the first row; clicking a day heading dropped the entry being read; item names stuck as "item 1234" on Journal / Gathering / Townsfolk / Places / Merchants / Items (window-level refresh when names arrive); Bestiary header controls overlapped the tier badges; an open dropdown outlived the window; blank strip above lists without the collapse toggle; a toast error could stop all later toasts, and hovering a fading toast froze it half-transparent; opening a zone from another page while a Places search hid it; first click on a focused zone folded it; right-click showed a record without selecting it; ArtScan used an undefined L.
- Polish: item and record slots on dark pages use the loot window's item card (Looting_ItemCard_BG / _Stroke_Normal / _Stroke_ClickState on hover) with a quality-coloured rarity stripe (Looting_RarityTag_Frame); coins use the bags' Coin-Gold / -Silver / -Copper atlases; the collapse toggle sits on the Skills list's divider (UI-Character-Info-ScrollLine-Long).

## 29. Spell ranks (2026-10-04, version 0.17.0) [?]
- [?] Plus Everything's Spell Ranker ported (`QoL\SpellRanker.lua`): action buttons (spells and macros) on an older rank than the highest known glow gold with a green arrow; tooltip line "Rank n available". "Check action bars" button at the top of the spellbook (modern PlayerSpellsFrame or classic SpellBookFrame; shift-click also updates); checks on opening the book and after learning a new rank. /aa ranks, /aa rankignore <spell>.
- [?] New: training a new rank replaces the older rank on your bars (spell buttons only, macros left alone; out of combat, waits for combat to end; waits while something is on the cursor). Settings page Spell Ranks (Characters): auto-replace, check after learning, check on opening, Check now / Update all now.

## What comes from Plus Everything

| Plus Everything | Azeroth Almanac |
|---|---|
| `Core.lua`, `WindowUtil.lua`, `MinimapButton.lua`, `Settings.lua` pattern | Foundation (1) |
| `Inventory.lua` (character records, owned items) | Characters (1), item discovery (4) |
| `Learning.lua` | Discovery recorder (2) |
| `BestiaryLog.lua`, `Bestiary.lua` | Bestiary (3) |
| `Encyclopedia.lua` | Items UI (4), ID search removed |
| `MerchantList.lua` (stock reading) | Merchants (5) |
| `Questopedia.lua`, `QuestopediaLogic.lua` | Quests UI (6) |
| `DungeonJournal.lua` | Dungeons UI (8) |
| `ClassSpells.lua`, `ClassSpellsLogic.lua`, `Recipedia.lua`, `RecipediaLogic.lua` | Trainers UI and logic (9), data replaced by snapshots |
| `Travel.lua` (flight learning) | Flight paths (10) |
| `tools\gen-*.js`, `tools\wago-cache` | Hidden database build tools (11) |

Quality-of-life helpers brought over in 0.10.0 (see section 23): Quest Targeter, Node Highlight (Gathering), Auction Prices, Auction Volume, Crafting, Disenchant, Merchant (auto repair/sell), MerchantList (vendor window), Travel (flights), Wings & Whispers, Inventory + Inventory window + Bag/Bank (My Characters), Social, Unit Frames, Party Plates, Threat Monitor, Follow Button, Heal Assist, Gem Match, WindowUtil, FlightCrew data.

Still not brought over: Quest Givers, SoftProbe, Spell Ranker, Talent Planner, Armory, Map Pins (Townsfolk map rebuilt, section 25), NPC Plates, Boats, Bar Watch, spells-viewer, QuestieLive. Plus Everything's `Data\` files as shipped (rebuilt into the hidden database, section 11; VendorData and DisenchantData rebuilt from VMaNGOS).

---

## Open questions
- Items: does hovering a link someone posts in chat count as discovered?
- Which open-source Classic server database to use (license and how close it is to Forever); add a `Licenses\` folder as Plus Everything has.
- Rares: research tier counts (suggest the boss counts).
- Companion app: build it as an optional extra, and how it runs (tray app vs run by hand).
- Order of building after Foundation and the recorder. Suggested: Bestiary, Items, Merchants, Quests, Zones, Trainers, Dungeons, NPCs and flight paths, then the Overview / journal, then sections 13-20.

## Art recording (0.7.2, development tool)
- `/aa artlog start | stop` (status with no word): records every atlas (with size, file, tiling), texture file, font object (with colour and a text sample) and flip-book (rows, columns, frames) the game's interface uses during a play session, by hooking SetAtlas / SetTexture and sweeping every open window every 3 s; plus layout snapshots (sizes, anchors, layers) of named windows in each new state. Saved in `AzerothAlmanacDB.artlog`. Carries on across /reload until stopped.
- [x] Session 1 (2026-10-04): 615 atlases, 56 fonts, 6 flip-books, 52 window layouts from 82 windows; catalogue in `ArtCatalogue.md`. Texture files hit the 12,000 cap (11,446 were spell icons from the macro icon picker; pickers are now skipped). Finding: `Skillbar_Fill_Flipbook_*` sheets are 1712 x 1020 (a grid, not one column) - the skill bar now cuts the first frame from a 4 x 60 grid (0.7.4). Recorder now also reads animations owned by textures.
- [ ] Use next: `common-button-list-minus` / `-plus` (list headings), `128-RedButton-*` three-slice buttons, `common-search-border-*` + magnifying glass (search boxes), `common-dropdown-b-button` (filter buttons), `Coin-Gold/Silver/Copper` atlases, `Tooltip-NineSlice-*`, `common-insideframe` (stat panes), `common-stat-bar-BG` / `-blue` (skills bars), `QuestLog-main-background` (quest list), `checkbox-minimal` / `checkmark-minimal`.
- [x] Session 2 (2026-10-04): 694 atlases, 70 fonts in total; new: auction house, class trainer, dressing room, flight map frame (`UI-Frame-*` tiles), loot frame (`Looting_ItemCard_BG` / `_Stroke_Normal` / `_Stroke_ClickState`, `Looting_RarityTag_Frame`), chat bubbles, casting bar, `recipetoast-bg` (toast art). Layout snapshots hit their cap of 60, texture files stayed at the 12,000 cap from session 1 (raise / reset the caps before another session).
- [x] Polish pass 0.8.0 (from the recorded layouts): detail section titles = the stats pane's `UI-Character-Info-Title` at 40 px, centred, GameFontHighlight; stat rows 23 px (label +11 GameFontNormal, value -8 GameFontHighlight) with `UI-Character-Info-Line-Bounce2` on every other row; list headings = the Skills list's `common-button-list-collapseExpand` with `common-button-list-minus` / `-plus`; entry hover = `charactercreate-customize-dropdown-linemouseover-*`; lists edged top and bottom with `UI-Character-Info-ScrollLine-Long`; search boxes = `common-search-border-*` + `common-search-magnifyingglass`; checkboxes = `checkbox-minimal` / `checkmark-minimal`; filter buttons = `common-dropdown-b-button` with gold text and an arrow; toasts on `recipetoast-bg`.
- [ ] Use: `recipetoast-bg` for the Almanac's discovery toasts; `Looting_ItemCard_*` + `Looting_RarityTag_Frame` for item cards (Items list, loot sections); `auctionhouse-nav-button*` for category lists; `auctionhouse-rowstripe-1/2` for striped tables (merchant stock, ranks); `auctionhouse-ui-row-select` / `-highlight` for row selection.

## Backlog
_(add new ideas here)_
