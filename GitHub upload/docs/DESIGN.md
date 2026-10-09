# Azeroth Almanac – Design notes

> **This was `docs/TASKS.md` until 2026-10-07.** It's kept as the design record: the ground rules, research findings and decisions behind each feature. Its checkboxes are historical; don't update them.
> - What to work on, and who: GitHub Issues and the project board (`docs/ROADMAP.md` explains it).
> - What changed in each version: `CHANGELOG.md`.
> - What still needs testing in game: `docs/TEST_CHECKLIST.md`.
>
> Add to this file when a design decision is made (a new rule, a finding, the agreed design for a feature).

Game: WoW Forever beta (`_classic_beta_`, interface 16001). Addon folder: `Interface\AddOns\AzerothAlmanac`.
Slash command: `/aa`. Saved variables: `AzerothAlmanacDB` (account-wide).

Azeroth Almanac turns WoW Forever into a game of discovery. It records what the player meets in the world (creatures, items, quests, merchants, trainers, zones, dungeons, NPCs, flight paths) and shows it as a catalogue: an adventurer's journal that grows as you explore. There is no completion percentage; the goal is the adventure, not finishing a list.

## Status key
- [ ] not started  ·  [~] planning / in progress  ·  [x] done  ·  [?] needs in-game testing

---

## Ground rules (decided 2026-10-03)

1. **Forever only.** Every feature and decision follows WoW Forever. No code or fallbacks for other Classic versions.
2. **Natural discovery.** The player is never shown more than they have met in their own game. Everything shown comes from something that happened in the game: a creature fought or seen, an item looted or owned, a quest offered, a merchant or trainer window opened, a zone entered. Names, icons and descriptions come from the game's own API, and only for things already discovered.
3. **Outside data is hidden until earned** (revised 2026-10-03). Mined data is built into a **hidden database** that ships with the addon and fills in **full records** as the player unlocks them, by **evidence** seen in game or by a **research tier** (section 2c). Until then the page shows the field as unknown ("? abilities not yet seen", "3 more unknown drops"). Stored compactly by ID; names, icons and descriptions come from the game's API at reveal time. In-game observations always override the database, because WoW Forever differs from Classic. Forever-only content (new quests, creatures, dungeons) has no record and fills in from observation alone.
4. **Account-wide discovery.** One shared record for all characters on the account, so alts start with everything found before. Each discovery remembers which character found it first, and when. Things a character *does* stay per character: quests completed, spells and recipes learned. Discoveries can be viewed for the account or filtered to one character.
5. **Spells and recipes come from trainers.** Each time a trainer window opens, a snapshot of everything it lists is saved. No class spell or recipe datasets are shown.
6. **No sharing.** No guild or group sharing of discoveries (Plus Everything's sharing code is not brought over). A "guild almanac" view could be a separate idea later.
7. **Native look.** Every window follows WoW Forever's own styling and uses the game's art and assets wherever possible: portrait frames, title bars, native tabs, quest parchment, the game's icons, borders, quality colors, fonts and sounds, Blizzard's dungeon map tiles and class emblems. No custom-drawn panels. When an art file may be missing on this client, check for it and fall back to another of the game's textures, never a flat color.
   **Style guide (from Forever's own windows, 2026-10-04):** facts go on dark panels like the character sheet and Skills window: gold banner section headers ("General", "Weapons"), stat rows with a gold label left and a white value right, skill-style bars for progress (research tiers), collapsible category rows with a blue band and +/- (zones), white body text, grey notes. Story text goes on parchment like the Map & Quest Log: dark serif headings ("Description") and quest font (journal entries, lore, quest text). Items and abilities are shown like quest rewards: icon slot plus name plate, two to a row, with the game's tooltip on hover. Red native buttons. Pages are switched with square icon tabs down the right edge (spellbook side-tab frame), the name on hover.
   **Lists and the quest page (2026-10-04, from the profession window and the quest log):** list categories are gold-edged dark heading boxes with large gold text and a gold - / +, a little space above each; entries are plain names; the selected entry has a gold glow fading right with gold rules above and below, hover a faint one. A quest page reads like the quest log: title, objectives straight under it with "0/10 ..." lines, "Description"; then the dark reward band with light serif headings between gold rules ("Rewards", then the Almanac's own facts), reward name boxes (dark box, bronze edge), XP and money as reward slots. **Money and currencies** (2026-10-04): always the game's way, each amount followed by its coin art (gold, silver, copper icons, empty coins left out); other costs as amount + the item's or currency's icon (`ns.MoneyText`, `ns.CostText`). Never "g / s / c" letters or words like "tokens".
   **The game's own art, read with `/aa art` (2026-10-04):** quest parchment `QuestDetailsBackgrounds`; reward band `QuestLog-reward-tile-vertical` + `QuestLog-reward-header-top` (55) + `QuestLog-reward-bottom` (87); "Rewards" in `QuestFont_Huge` (0.9, 0.79, 0.67), "You will receive:" in `QuestMapRewardsFont`; reward item = 30 px icon + `WhiteIconFrame` (651080) tinted by quality + `QuestItemBorder` name frame, name `GameFontHighlightSmall`, count `NumberFontNormalSmall`; XP icon file 894556 with `NumberFontNormal`; title `QuestTitleFont` (black), body `QuestFont` (0.18, 0.12, 0.06), objectives `QuestFontNormalSmall`. Scroll bars: `minimal-scrollbar-*`. Side tabs: `common-sidetab`, `-selected`, `-hover` (55 x 60). Skill bars: `Profession-ProgressBar-BG` / `-frame`, fill `Skillbar_Fill_Flipbook_<Profession>`, flare `Skillbar_Flare_<Profession>`, text `Number12FontOutline`. Window frame: `UI-Frame-Metal*` (PortraitFrameTemplate). Profession cards: `Profession-overview-Card-<Profession>`.
8. **Standalone.** Azeroth Almanac is never installed alongside Plus Everything, so no conflict handling is needed. It borrows code from Plus Everything (`D:\Plus Everything`) but has its own files and data.
9. **No completionism** (decided 2026-10-03). No completion percentages, progress bars or "x of y" totals anywhere. Progress is shown only through what has been found: running counts ("214 creatures discovered"), research tiers per creature, milestones based on your own discoveries, and a journal of discoveries. Nothing implies a fixed amount left to find. (This also means the database doesn't need complete or Forever-exact totals, and Questie isn't needed.)
   **Exception (2026-10-07): zone exploration.** WoW Forever's legacy exploration achievements already show every area of a zone, so the Places page shows "x of y areas explored" per zone (from those achievements, for the character you're playing) and a "Fully explored" alert. Nowhere else.

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
- (Decided 2026-10-07: no combat-log companion; see section 2b.)
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

## 2b. Combat Journal companion: dropped (decided 2026-10-07)
No longer needed: the Almanac learns what it needs in game (tooltips, casts seen, the damage-taken method in section 2). The proposal (a PC program reading the text combat log into a data file) is not being built.

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
- [ ] Thresholds are settings (defaults above). Rares: the boss counts (decided 2026-10-07).
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
- [?] 0.40.1 ranks: Sighted (seen, never gathered), Apprentice 1, Journeyman 5 (everything it can hold), Expert 15 (how likely each is), Artisan 50, Master 200; the creature tiers' colours and badges (Apprentice wears the profession's icon); the blue skills bar like a creature's ("9 / 15 · 6 to Expert", rolling on past Master); toasts "Expert Miner", "Journeyman Herbalist", "Artisan Angler" (chests: the rank alone). Tier counts for creatures and gathering are fixed in code (Bestiary.TIER_KILLS, Gathering.AT); Settings > Research tiers only lists them, and old saved tier settings are dropped (Store migration 4).

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

## 30. Gathering toggle on the minimap (2026-10-04, version 0.17.1) [?]
- [?] Herb button on the minimap's rim, styled like the Almanac's minimap button (tracking border, Trade_Herbalism icon, greyed when off). Left-click shows / hides gathering pins on the minimap, right-click opens the Gathering settings, drag moves it around the edge (`nodes.mmPos`). Tooltip shows how many pins are nearby. Setting "Herb button on the minimap" (`nodes.mmButton`); `/aa nodes` toggles the minimap pins. Both map buttons stay in sync with the settings.
- [?] 0.17.2: in game the button was not visible; at a fixed 225° it sat under the Almanac's button (moved to ~235°). Now first placed 55° clockwise of wherever the Almanac button is, drawn one level above it, `/aa nodes button` resets it, and a failure to build it prints in chat.

## 71. Murloc Tac Toe in the mini-games' look, and champions to choose (2026-10-07)
Phase 1 (no new art needed), then phase 2: the board, the murloc badge for the corner icon (`MurlocTacToe_Icon.tga`, a square murloc face cut to a circle by the gold frame), the olive swamp ribbon across the result panel's top edge with the result in gold on it (`MurlocTacToe_Ribbon.tga`; the champion's colour goes on the line under it), and the champion arrows, mossy carved oak (`MurlocTacToe_ArrowL` / `_ArrowR`, split from one picture). All painted in Gemini on magenta, sources in `docs/art_source/MurlocTacToe_*.png`, converted with the `cut` mode of `art_convert.py`.
- Board: the painted swamp board (`Media/MurlocTacToe_Board.tga`, source `docs/art_source/MurlocTacToe_Board.png`, made in Gemini on magenta: carved mossy oak with knotwork, vines, mushrooms and a lily pad round nine recessed sockets), converted with `art_convert.py board` darkened (playfield 60%, frame 85%). Shown 461 px square; the sockets are 90 px apart there (cells 90 px, faces 60 px, was 100 / 66) and the grid starts 97.2 / 92.7 px in (`INSET_X`, `INSET_Y`), measured from the art. The old shaman painting, the gold dialog frame and the drawn grid lines are gone (the grooves are in the picture). The window is 837 x 687 now; the player cards are as wide as the board.
- Polish: the status line sits on Wild Gambit's green turn ribbon (`Banner_Turn`) under the cards, with a taller band for it (board 44 px lower; window 837 x 701); the cards are narrower with a wider gap so the VS shield sits clear and the champion arrows sit inside the left card's edges; the idle banner is the swamp ribbon with "Mrgl mrgl!" on it and the practice button under it (no black box); fireflies drift over the board behind the pieces; the thick neon talent-node rings are replaced by Wild Gambit's carved ring (`Ring_Class`) tinted by role (moss for the first mover, copper for the second); the winning line is a wide soft glow in the winner's colour, a gold body and a bright core with a light that leads the draw and stays at the end pulsing; the hover and win glows on the cells are soft round light (`GenericGlow64`) instead of the action button's square.
- Alive: (1) the pieces are the champions themselves: a small 3D model of the champion standing in each socket, on a shadow and a soft glow in the role's tint, playing its attack animation as it is placed, cheering (winner's pieces) or slumping (loser's) at the end, with a half see-through copy of your champion showing where it would stand under the mouse; the round-face portraits are gone from the board (the small faces on the nameplates stay). (3) each player card has Wild Gambit's carved nameplate (`Header_Nameplate`, mirrored for the opponent) with the name on it, the creature standing behind it, the champion's round face in its socket, the champion's name and the record on one line under it, and the turn gem (`Header_TurnGem`) lights on the nameplate of whoever's move it is, nudging and pulsing, over a soft glow in the role's tint. (4) voices: each champion's `place` / `win` / `lose` sounds can be built in (`CHAMPS`) or set in game: `/aa mtt voice <champion> <place|win|lose> <file IDs>` (several IDs: one is picked at random; `clear` removes), `/aa mtt sound <file ID>` plays an ID to find the right one; saved in `db.voices`, which wins over the built-in. (5) the quiet swamp: `/aa mtt ambient add <file IDs>` (also `clear`, and with no word a list): while the window is open and sound is on, one of them plays every 20 to 45 s on the Ambience channel; saved in `db.ambient`, none built in yet. (2) a mossy tree stump in a pool under each creature on the cards (`MurlocTacToe_Stage.tga`, source `docs/art_source/MurlocTacToe_Stage.png`, converted with the new `stage` mode of `art_convert.py`, which fades the picture's rectangle of water into transparency round the stump): the cards are 140 px tall now (`CARD_H`; the window 723 high) so the feet stand on the stump's top above the nameplate, which covers the stump's foot. Champions are chosen in a new Champions block in the side panel as well as by the arrows beside your creature: a row for you and a row for the computer in a practice game (`db.botChamp`; Random by default, `MT:CycleBot`); the arrows show between games only, and in a game the rows show the champions playing; the opponent's card shows the computer's pick before a practice game. The side panel is re-laid out for it (Rivals shows 5 rows). Built-in voices: the slime's FX_Slime_Whoosh_Short_01 - 10 (file IDs 4276904 - 4276922; wowhead's sound=188260 is their sound kit, not a file) and the Sprite Darter's PET_SpriteDarterHatchling_Clickable01 - 10 (file IDs 560814 - 560823; sound kit 23652), each split between place, win and lose by guess until heard. The dragon whelps were dropped.
- Art converter, enclosed background: `art_convert.py cut` keys out all the flat background magenta, including loops the art encloses (the rope divider's loops used to keep a magenta tint); only with the `keep` word does it keep a pink patch enclosed by the art (the highlights inside the purple gems: the gem scatter is the one piece converted with `keep`). Gem Match's divider, pouch, plaque, panel, ribbon and gem textures, and Murloc Tac Toe's ribbon, arrows, icon and stump were all converted again with it, and the single-gem sheet (`GemMatch_Shards.tga`) rebuilt.
- After a game: the cards and the Champions rows used to keep the champions that played it, so choosing another looked like it did nothing, and the choosing sound was always the first mover's champion's. Now, after a game, choosing puts the new champion on your side of the cards at once (and, in a practice game, the computer's pick on its side), and the sound is the new champion's.
- A win to remember: when a game is won, once the glowing line has drawn across (0.45 s) fireflies burst up from the three winning sockets and 16 more across the board (a smaller burst when you lose; none on a draw), in the winner's colour warmed towards gold, drifting up with a sway and fading over 1.4 - 2.6 s (`frame:Sparkle`, pooled glow textures); and the winning player's card glows gold, pulsing, for 4 s while its creature plays its victory animation. Both stop with the next game.
- One click sound on every wooden button: `ns.WoodButton(b, allow)` in `WindowUtil.lua` hooks the click (`SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON`, 856), so Wild Gambit, Gem Match and Murloc Tac Toe buttons all click alike; `allow` is each game's own sound setting (`db.sound`), so "Sound: off" silences the clicks in that game. The painted arrows, the Back arrow and the gem-picking clicks are not wooden buttons and keep their own sounds.
- Heads cut off: a creature was framed too close for the room the stump leaves, and a model is clipped by its frame. The camera now stands further back (`CamScale`: cards 1.55, board pieces 1.5; a champion's own `cardCam` / `pieceCam`, or a value set in game with `/aa mtt cam <champion> <card zoom> [piece zoom]`, saved in `db.cam`, comes first), and the model frames reach 34 px above the cards and 28 px above the sockets, so a tall creature isn't cut off; the "Azeroth Almanac" byline moved to the bottom left (as in Wild Gambit) out of the heads' way.
- Music: while the window is open, the game's own light Jungle day tracks play one after another at random (`Sound\Music\ZoneMusic\Jungle\DayJungle01-03.mp3`, 46, 99 and 48 s long: lengths measured from copies of the files, the game plays them by path, no IDs needed; chosen from the 27 tracks on the Swamp of Sorrows page for being light rather than foreboding). They replace the zone music (`PlayMusic`) until the window closes (`StopMusic`: the game resumes its own). A Music on/off button beside Sound in the side panel (and `/aa mtt music`), saved as `db.music` (on unless switched off); the game's own music volume applies. The sound-ID ambience (`/aa mtt ambient`) stays as an option.
- Seasonal champions, Hallow's End: the Sinister Squashling (item 33154, spell 42609, whose summoned creature is NPC 23909 per its Wowhead page; found by that ID like the roach; it was tried and dropped once, then asked for again), the Bombay cat (item 8485, Cat Carrier (Bombay); no creature ID is known, so its model comes from the pet among your companions: you need to own it (looked up as "Bombay" or "Bombay Cat"), else target a Bombay cat and `/aa mtt champion bombay`; looked for 6 s and 25 s after login and whenever the window opens) and the Plagued Cockroach (WoW Forever creature 271913, Undercity; found by its ID like the slime). The Sinister Squashling (item 33154) was tried and dropped. They are offered only while Hallow's End is on (18 Oct - 1 Nov, the same calendar check as Wild Gambit's holiday board: `ns.HolidayNow()` in `WindowUtil.lua`, which `WG:HolidayBoard` now calls); `/aa mtt season` shows seasonal champions all year for trying them out. An opponent who plays it is shown with it whatever the date here (Known vs Playable in the code); if the season ends while you have it chosen, you fall back to the murloc. More holidays: `season = "WinterVeil"` on a champion.
- Side panel and pop-ups: Gem Match's carved oak panel, cut in nine (`Carved()`); the Challenge a player heading uses the shared gold heading; rope dividers; the waiting and game-over pop-ups are carved panels too. Rivals shows 8 rows (was 9) to fit.
- Look: the window uses the shared dark background; every button is the carved-oak plank with gold lettering (`ns.WoodButton`, `ns.WoodLettering`); the corner icon is the shared gold dragon frame (`ns.GoldEmblem`) with a murloc-head icon for now (the old hand-made `ElitePortrait` and its black, empty circle are gone); the byline moved right of the icon; the "VS" sits on Wild Gambit's carved shield (`Plaque_VS`). The two practice buttons say "Practice game".
- Champions: you play as a champion of your choice and the other player sees it. The sides are now `CHAMPS` (murloc, gnoll, faerie, slime, squashling, bombay, roach). The first mover is still the role "murloc" and the second "gnoll" in the code: `SIDES[role]` looks up the champion in that role, so existing code reads the same. The ring colours follow the role; the names, colours, voices and models follow the champion. Choose with the two arrows either side of your creature (hidden while a game is on); saved in `db.champion`.
- Messages carry the champion: `C|gid|champ`, `A|gid|champ`, `N|gid|newgid|champ`. An older Almanac sends none and plays its role's classic champion (protocol still "1": the extra field is ignored by old versions). The computer plays a champion other than yours.
- A new champion stays hidden until it has a model. Two have an NPC to look it up from: the "faerie" champion, now the Sprite Darter (its pet is the Sprite Darter Egg, item 11474, whose icon is its face fallback; creatures tried in turn for the model: NPC 5278 Sprite Darter, then 206792 Baby Faerie Dragon, a retail creature), and the Excitable Slime (NPC 266735, WoW Forever, Undercity). NPC 5278 is confirmed working in game. A few seconds after login each such creature is loaded into a hidden model by its ID (as the Bestiary does for faces), one at a time, up to 3 tries, and the display ID it ends up with is kept in `db.display`. If it doesn't resolve, set one by hand: target the creature and type `/aa mtt champion <key>`; or give a display ID (`/aa mtt champion faerie 12345`) or a different NPC (`/aa mtt champion faerie npc 12345`). `/aa mtt champions` lists them. Keys: faerie, slime, squashling, bombay, roach. Their voices are not set (silent for now): `place` / `win` / `lose` file IDs go in `CHAMPS`.

## 70. Gem Match: a painted wooden board (2026-10-07) [?]
- [?] The board behind the gems is a painted carved-oak frame with knotwork, bronze rivets, a little vine and a stack of coins round an 8 x 8 grid of shallow sockets (`Media/GemMatch_Board.tga`, 1024 x 1024; source `docs/art_source/GemMatch_Board.png`, made in Gemini on flat magenta). Replaces the dialog's gold border and the frost talent painting. The playfield is darkened to 55% and the frame to 85% when converted (first 72% / 92%, then darker on request) (`tools/art_convert.py board`, so it can be re-darkened without repainting). The picture is shown 542 px square and the gems' grid starts 73.5 / 68.5 px in, measured so the 50 px cells fall in the sockets; the window grew to 838 x 620 to fit. The faint chequer under the gems is lighter (0.16 / 0.04). A plain wooden-plank backup is in `docs/art_source/GemMatch_Wood_Plain.png` (unused). New texture: full game restart.
- [?] Gem Match side panel rebuilt from the new art (all from Gemini on magenta, `docs/art_source/GemMatch_*.png`, converted with the new `cut` mode of `tools/art_convert.py`): a carved-oak panel cut in nine (`GemMatch_Panel.tga`, margins 58; the window is 918 wide now, the panel 330), the score on a carved plaque (`GemMatch_Plaque`), a rope divider above the best scores (`GemMatch_Divider`), the gem pouch spilling beside moves / best (`GemMatch_Pouch`). The scatter of gems (`GemMatch_Gems.tga`, converted, not used yet) is for the game-over panel with a "Well played" ribbon, when that art comes. Five best-score rows instead of eight (room). `cut` keys only the magenta joined to the outside, so pink-purple highlights inside a gem stay solid.
- [?] Gem Match game-over panel: the carved panel (nine-slice, 360 x 250) with a green "Well played!" ribbon across its top edge (`GemMatch_Ribbon.tga`, source `docs/art_source/GemMatch_Ribbon.png`) and the scatter of gems (`GemMatch_Gems.tga`) spilling out from under its bottom edge; "Time's up!" / "Out of moves!", the score, the best line and Play again sit inside. Two overlaps fixed: the best-scores title is short ("Best  Timed") so the colour key no longer runs into it, and the "Azeroth Almanac" byline moved to the right of the bigger corner icon (it was behind it).
- [?] Gem Match, the gem scatter put to work and a louder hint: (1) a faint scatter behind the "No scores yet" text, gone once the list has a score; (2) the pause cover shows the scatter under "Paused"; (3) on a new personal best the game-over gems drop out from under the panel (0.7 s) and gold sparkles rise for about 3 s; (4) the single gems cut from the scatter (`GemMatch_Shards.tga`, a 4 x 2 sheet of 128 px cells: green, orange, purple, pale blue, yellow, red, prism, matching the gem kinds) fly out of every cleared gem (2, and 4 where a power gem or crystal is made) with gravity and spin; (5) the hint: both gems of the move glow cyan-white (the selection glow's texture, swelling), lift over their neighbours and bob 12%, instead of the faint square; picking a gem or starting a swap takes the hint away (`ClearHint`). The hint now only comes from the Hint button: the 10-second idle hint is gone (`HINT_AFTER` and the idle timer removed).
- [?] Gem Match mode buttons (Timed / 30 Moves) now read as one switch: the two halves touch, the mode being played is bright with its gold glow and the other is dimmed (60%) until the mouse is over it, and each has a tooltip saying what the mode is and whether clicking starts a new game. Second pass (it still read as two plain buttons): a caption "Game mode (pick one)" above them, words on the buttons that say what each is ("Timed  2:00", "30 Moves"), a gold diamond on the mode being played, the other dimmed to 50%; the panel below shifted down 14 px (gaps tightened so the help text still fits). Third pass (it looked lost): room round it - the caption became a "Choose your game" heading in Wild Gambit's gold lettering with a rule and diamond each side (`ns.Ornament`, now shared from `WindowUtil.lua`; Wild Gambit calls it as before), the switch is taller (28), the whole panel below moved down about 26 px; a streak of light sweeps across the switch each time the window opens or the mode changes; the glow of the mode that is on breathes slowly. To make the room the best-scores list shows 4 rows (was 5). The "Cascade x3!" pop-up moved under the best score: it used to be drawn over the moves number.
- [?] Gem Match: the gem picked for your move glows gold (the action-button glow, breathing; the gem lifted over its neighbours). Best scores now come from guild, group (party / raid / instance) and online friends: bests go to all three on a new personal best; opening the game asks all three (at most every 5 minutes; friends one by one 0.35 s apart, at most 40, by addon whisper, and whispers are only believed from friends); replies go back the way the question came; heard scores kept in `db.circle` (guild ones stay in `db.guild`). The list merges them by name (highest score, friend over group over guild) and colours names: guild white, party blue, friends green, you gold; the title is "Best scores" with a small colour legend. The Gem Match sharing option now covers all three.
- [?] Gem Match now looks like Wild Gambit's window: the same dark recipe-list background behind everything; the corner icon bigger in the same gold elite frame (`ns.GoldEmblem`); and every button (mode, New game, Hint, Pause, Sound, Play again) is the carved-oak plank with gold lettering (`ns.WoodButton`, `ns.WoodLettering`), the mode that is on shown by a gold glow behind it (the old highlight lock doesn't show on the plank). The wooden-button and gold-frame code moved out of `WildGambit.lua` into `QoL/WindowUtil.lua` so both games share it; Wild Gambit now calls the shared versions (same look).

## 69. Wild Gambit, a creature card game (design agreed 2026-10-05; prototype 0.25.0) [?]
- (0.61.0) The picked card is never lowered. Supporting cards even the hands out, below their floor tier when needed. Hands may stay uneven only when both picks are huge against a tiny budget.
- (0.63.0) Character-only Almanac: "new to this character" counts as a discovery (alert, journal) and milestones are kept per character too (db.chars[key].milestones) alongside the account's.
- (0.62.0, decided 2026-10-07) The pick cap: when the hands would still end more than 3 spikes apart (WL.PICK_GAP) with every supporting card at tier 1, the picked card drops a tier at a time within its floor, only as far as needed, and the player is told (chat line, table note, red arrow). Deterministic on both screens (part of WL.Equalize), so it needs no extra message.
Skystones (Skylanders: Giants) rules with Almanac creature cards. No trading or looting.
- Cards: one per creature you've Sighted. Total spikes = level base (floor(level/10)+1, capped at 6) + tier bonus (replaces, not stacks): Sighted grey +0, Fought white +1, Studied green +2, Mastered blue +3, Epic purple +5 (50 kills), Legendary orange +8 (200 kills). Max 14. (0.30.0; was +4/+8/+10. Mastered now 15 kills of a normal creature.)
- Tier floors: elites and non-elite rares start green (Studied); rare elites and dungeon bosses start blue (Mastered). Level sync never drops a card below its floor.
- Fair hands (0.29.3, protocol 2): PvP budget = 80% of the lower best five; after both hands are known the higher one plays its strongest cards a tier lower (shape kept: spikes come off the biggest sides) until within a spike (WL.Equalize, same on both screens). Draws that can't sync down (elites at their floor) are avoided; failing that, the lowest-floor cards are taken. Practice uses the same equalize.
- Sides: weights per side from (1) the home zone's direction from the continent centre (up to 3), (2) where in the zone it was first seen (up to 1.5), (3) creature type shape (Beast pounce, Humanoid flank, Undead back, Elemental even, Dragonkin E/W, Giant N/S, Mechanical mirrored, Demon fang, Critter even), (4) rank (elites stack higher; rares +1 on the weakest side). Largest-remainder distribution; per-side cap max(2, ceil(total/2)) (+1 elite); the side opposite the strongest is weakest; ties by npcID hash. Upgrades re-run with the new total, same shape.
- Play: 3x3 board, 5-card open hands (1 picked, 4 random), random first player, capture when your touching side has more spikes, no chains, most cards owned wins. Spike budget = the lower of both players' best-5 totals; random fill within 1 of it; a pick that's too big plays tier-synced down.
- Class ability once per match (own class or chosen), a free action before placing (reworked 0.40.0): removal - Warlock Banish (any enemy card), Mage Polymorph (enemy card <= 10 spikes, wanders off as a sheep), Warrior Execute (enemy card next to one of yours with more spikes in total); protection - Paladin Divine Shield (can't be taken, removed or swapped), Druid Barkskin (+1 spike every side), Shaman Grounding Totem (your cards can't be taken or targeted through their next turn); swap - Priest Mind Control (enemy card <= 8 spikes), Rogue Pick Pocket (trade one of your board cards for one of theirs), Hunter Freezing Trap (hidden square). A removed card's owner is dealt a new card: the closest in spikes of three reserves held back at setup.
- Look: card shape like the Bastion Golem reference: gold spikes on the outside edges (one per spike, centred, shrink to fit), name banner, 3D creature art, tier banner, frame more ornate by tier (stroke -> quest-log filigree -> diamond-metal corners -> metal corners + sparkles -> gold dragon + gryphons + shine sweep), corner gems in the owner's class colour (same class: opponent gold, else blue/red; round vs diamond gems).
- Board: forest clearing (druid / hunter talent paintings), mossy slabs, root dividers, herb blossoms at the crossings, fireflies and falling leaves, nature sounds (Entangling Roots on capture, Thorns on big wins, Force of Nature on a win, forest ambience).
- Network: hidden addon whispers like Murloc Tac Toe; incoming cards validated against the rules and the creature data (tier on trust); shared dice from both players' random numbers; numbered moves, resync, same rules version required (else the update quest).
- [?] 0.24.2: /aa atlascheck tests ~400 candidate atlases and texture files (quality card borders, vine / covenant frames, class and forest paintings, herb / nature icons, Darkmoon card icons) and saves AzerothAlmanacDB.atlascheck. Run in game: 127 of 465 atlases, 60 of 64 files (quality borders loottoast/auctionhouse/bags-glow in all colours, all nine talent-background-<class> and UI-Character-Info-<Class>-BG paintings, Profession-background-card-Herbalism/Skinning/Leatherworking/Alchemy, covenant sanctum borders, Boss-Gold-Winged / Rare-Silver dragons, gryphon and wyvern, classicon-* for all nine, talents-arrow-head/line yellow; no vine frames).
- [?] 0.25.0 prototype (practice only): QoL/WildGambitLogic.lua (card spikes, hands and spike budget, captures, the practice bot; tested offline: totals always match, symmetric shapes stay symmetric, bot beats a sloppier bot ~72%) and QoL/WildGambit.lua (the table). Cards: profession card face by creature type, 3D creature (or type icon), name banner, tier tag, tier frame (stroke -> quest-log frame + filigree -> diamond corners -> metal corners + sparkles -> gold winged dragon + shine sweep), bags-glow in the tier colour, gold arrowhead spikes on the edges, class-coloured gems (round = you, diamond = opponent). Board: the druid talent painting cropped and dimmed, bark-and-moss roots, four herb blossoms, mossy slots, fireflies, forest ambience. Pick screen (your 10 best, or let fate choose); practice opponent from your own collection at 80% of your best-5 budget; hover a hand card to enlarge it; Gambit won / lost / stalemate with a practice record. /aa gambit, minimap menu, Settings > Fun > Wild Gambit. Not yet: class abilities, playing other Almanac players.
- [?] 0.25.1 from the first screenshots: board cards were zoomed onto the creature's chest (a model's camera doesn't follow a scale change): models now show the whole creature and are refitted after every move between hand, board and hover; the tier glow was a big coloured block bleeding over the roots: tighter (9 px) and fainter; round gems are now masked round (diamonds stay turned squares); the fireflies were square (bags-glow-white): soft round dots; the turn line overlapped the opponent's score: moved under the board; spikes 12 px (were 10) with a 28 px gap between slots.
- [?] 0.25.2: the pick screen showed two blank white circles in the header (no game yet): now your emblem and name, and "An empty seat" with a question mark across the table.
- [?] 0.26.0: spikes 50% bigger (18 px), 42 px between slots, 30 px board margin; the window on the Almanac's dark panel (LIST_BG); the header like the player frame: round portrait (yours; the gambler wears one of its deck's creatures) in the follower portrait ring, the round's class emblem round in a class-coloured ring at its bottom right, name and cards owned; the tier name on each card is now the tier's icon (the Creatures page icons; beast upgrade stones for Epic / Legendary) in a tier-coloured ring; more ornament by tier: covenant sanctum borders round the name plate (Kyrian Mastered, Night Fae Epic, Venthyr Legendary) and gryphons at a Legendary's foot; captures play out: the new card lunges at the loser (attack animation), the loser is knocked back and squashed with a shake (flinch animation), flashes and turns colour at the hit, one capture after another; card tooltips (level, tier, spikes per side).
- [?] 0.27.0 class abilities: "Play as" row of the nine class emblems on the pick screen (your class by default, remembered); the round's spell as a button in your header (the opponent's shown too), once per match, not using up the turn: Charge (next card wins ties), Divine Shield (a card can't be taken or touched; gold bubble + icon), Freezing Trap (hidden square; the next enemy card there is frozen and yours; only the trapper sees the mark), Pick Pocket (random hand swap), Polymorph (an enemy card becomes a sheep 1/1/1/1, sheep model), Drain Soul (up to 3 spikes from an enemy card to your neighbouring card's facing side, takes it if stronger), Mind Control (an enemy card of 8 spikes or fewer), Chain Lightning (next card's captures chain on), Shapeshift (a quarter turn, takes what it now beats). Targeting mode with hints; the practice gambler uses its spell when it pays. Rules in WildGambitLogic (WL.ABILITIES, CanTarget, Use, BotAbility; traps / shields / chains in Place); tested offline for every class.
- [?] 0.27.0 player against player: pick a card (click to choose) then Practice, or Challenge (name box / My target / "/aa gambit Name"). Prefix AzAlmWG: challenge popup, accept, both send best-five spikes + class + half the dice; budget = the lower best; each builds a hand and sends its five cards; every card checked (spikes = level base + tier bonus, side caps, level against the creature data) and the hand against the budget, else the game is cancelled; the dice decide who starts and Pick Pocket identically on both screens; numbered moves and spells, out of step = cancelled; Leave button; records per opponent. Two simulated clients played full games with every class pairing and ended on the same board.
- [?] 0.28.0 Find a match: a "Find a match" button on the pick screen (Stop looking to cancel; a running clock). Q|-|best goes to the guild, the group, the Almanac players met this week (whispers, from Peers:Recent) and, only while looking, a hidden realm channel AzAlmGambit (joined and left automatically, kept out of every chat tab, its notices filtered; Settings > Wild Gambit "Find a match across the realm" to turn it off). Two lookers pair up: the name that sorts first sends C|gid|q, the other accepts by itself, both set up with the card and class already chosen. Simulated pairing tested.
- [?] 0.28.0 card frames: a gold hairline inside the stroke from Studied; comets (sparks with a trail) running round the edge: one Mastered, two Epic, three Legendary, in the tier colour; the tier glow breathes; Epic gets the shine sweep (violet), Legendary's is faster and gold, and embers rise off Legendary cards; pick-screen cards animate too.
- [?] 0.28.0 polish: the turn's portrait glows; the hand that isn't playing dims; a spell's valid targets glow (cards and empty squares); the result panel is slimmer and sits low on the board so the final board shows; dead code removed; class list from the rules module.
- [?] 0.28.1: "Find a match" overlapped "My target" on the pick screen: it now sits above Practice (same width), clear of the challenge row.
- [?] 0.40.0 class abilities reworked into removal / protection / swap (see the rules line above). Targets glow by kind (red removal, gold protection, purple swap; Pick Pocket: your card, then theirs). A removed card shrinks and fades (Polymorph: it turns into the sheep and trots off; Execute: your card strikes first); its owner is dealt the reserve closest in spikes (lowered a tier or more if that's closer), face down with the page-turn flip; a sixth hand card closes the gaps up. Removal frees a square, so the board still ends at nine. Each spell plays its class sound (Banish: Dimensional Rift, Polymorph: the sheep, Execute, Divine Shield, Barkskin, Grounding: wind cast, Mind Control: shadow whisper, Pick Pocket: coins, Freezing Trap: trap set; the trap's snap on the catch). PvP protocol 4: three reserves travel as K 6..8 and are checked like the hand; U carries Pick Pocket's second square; a target the other screen's rules don't allow cancels the game. Tested offline: rules per spell, practice with every class, two clients ending on the same board for every pairing (including two removals).
- [?] 0.40.1 the chosen card is hidden: the opponent's stays face down in their hand (no glow, no hover) until played, turning over as it lands (or at the end if never played); yours carries a stealth mark. The practice gambler hides its strongest card the same way and no longer counts yours when it plans. No protocol change (the chosen card already travels first).
- [?] 0.41.0 hero and companion cards. Hero: your character (name, level, race), Fought, then Hunted / Master Hunter / Epic / Legendary at 10 / 25 / 50 / 100 creatures at Master Hunter or above (WL.HeroTier); shape by class (Warrior, Paladin: front and back; Rogue, Hunter: flanks; casters even), leaning toward the race's capital; only ever the chosen card (its own slot on the pick screen, "You"); your screen shows your character's model, the opponent's their class medallion. Companions (Hunter, Warlock): right-click the pet's portrait > Add to Wild Gambit deck (or /aa gambit pet; /aa gambit pet remove Name), kept per character with its species, level and face; Fought, then by kills with it out (5 / 15 / 50 / 200, WL.PetTier); in your deck like any card (the practice gambler doesn't draw them). PvP protocol 5: heroes travel as class "hero:CLASS:Race", companions "pet:Kind"; both skip the wild-level check but keep the spike rules. Art hooks: HERO_ART (crest, capital scenes, class crests, paw badge).
- [?] 0.41.1 hero art in (crest, six capital scenes, nine class medallions, paw badge). 0.41.2 the Skyborne (WoW Forever's new race: Windshaper Horde, High Order Alliance, starting on Zephras Isle): recognised by race name, their spikes lean toward Zephras Isle (its map found by name and remembered) and their scene is Scene_Hero_ZephrasIsle once painted; heroes now travel with their home scene ("hero:CLASS:Home").
- [?] 0.42.0 pick table of ten: your hero card first, then your favourites, your companions, then your strongest (no separate hero slot). Favourites: a star on the Creatures page card box (top right); up to 5 (WG.FAV_MAX), a sixth asks which to replace; starred creatures show a gold star on their card and in the Creatures list, are always on the pick table, and are three times as likely (WL.FAV_WEIGHT) to be among the four cards drawn with yours (your own hand only; the practice gambler draws evenly). Kept account-wide (wildGambit.favorites).
- [?] 0.43.0 spell cards: each player's class spell is a sixth card at the end of their hand (Frame_Spell, Gem_Spell tinted by kind, Spell_<Name> painting, name and rules in the panel), face up for both; click it to cast (targeting as before), it fades from the hand once used; hover for a large view; the header spell box is gone. Shaman: Reincarnation replaces Grounding Totem (the next card of yours taken by a capture, trap, Mind Control or Pick Pocket, or removed by Banish / Polymorph / Execute, stays yours; one use; ankh by the portrait while waiting). Effects: FX_* paintings grow, turn and fade over the target (Banish, Execute, Polymorph, Divine Shield, Mind Control, frost on a trap, coins on Pick Pocket, spirits on Reincarnation); Divine Shield's bubble and Barkskin's mark painted. PvP protocol 6.
- [?] 0.43.1 practice opponents: a random creature near you (nameplates, target, mouseover, focus; not dead, not your pet), else one from your Almanac by rank (dungeon boss > named / rare > elite > any); its name and portrait in the seat (the unit's own portrait while in sight, its appearance learnt and kept). Right-click any portrait (target, focus, party, raid, boss, players, friends): "Play Wild Gambit": a creature becomes the next practice opponent (shown in the empty seat on the pick table), a player is challenged.
- [?] 0.43.2 cards fly from the hand to their square (0.42 s, eased arc, growing from hand size to board size with a little extra mid-flight, then a 0.18 s settle); the place sound, captures, traps and Reincarnation follow the landing; the opponent's hidden card turns over in the air; clicks wait while a card is in the air. A cast spell card glides toward its target as it fades. Spell rules text (and a long name) shrinks to fit the card's panel.
- [?] 0.43.3 an opponent who wanders out of sight keeps its face: its appearance is learnt from the unit while in sight, else from its creature ID (SetCreature), kept on the creature's record, and shown in the seat and owner tabs once the live portrait is gone (a few retries if it isn't known yet).
- [?] 0.44.0 habitat scenes (Media\Scene_Habitat_Underwater / Shore / Desert / Snow / Swamp / Cave): a card's scene follows where the creature lives before its type: words at the start of a word in its name or family (shark, crab, murloc, naga, makrura -> Underwater; pirate, privateer, crocolisk -> Shore; frost, yeti -> Snow; sand, scorpid, silithid -> Desert; kobold, trogg, tunnel -> Cave; bog, mire, ooze -> Swamp), else its home zone (Tanaris, Silithus, Desolace, Badlands, Thousand Needles desert; Winterspring, Dun Morogh, Alterac snow; Swamp of Sorrows, Dustwallow, Wetlands swamp); else the type scene as before. Companions by species; heroes keep their capital.
- [?] 0.44.2 end-of-match sounds: quest complete (win), quest failed (loss), quest accepted (draw), stopped by 2.8 s. Forfeit button (bottom right, practice and against players; confirm first): a loss for you; your opponent sees "X forfeits the match" and the win is theirs.
- [?] 0.44.3 favourites wear a ruby heart (Media\Badge_Favorite) on the Creatures page button, in the creature list and on the card. Settings: a search box over the page list; every page is built the first time you search, and every heading, option and its tip is indexed; results (option and page) replace the list, and clicking one opens its page scrolled to it with the row flashing gold.
- [?] 0.44.4 fix: spell effects (frost on a trap, Banish, Execute ...) were drawn on the window itself, under the card frames, so they never showed; they're on their own layer above the cards now. Creatures page tier filter wide enough for "Legendary Hunter".
- [?] 0.45.0 Freezing Trap rule: the card played onto a trap is frozen solid: nobody's card, takes nothing, can't be taken or targeted, its square out of the game (8 cards count, so 4-4 draws can happen); Reincarnation still saves it. Look: frost over the card (Media\FX_FrozenCard, added as light), ice round the creature's feet (Media\Mark_IceShackles), the model paused and lit cold blue, ice-blue owner tab with no face or gems. The practice gambler hides its trap beside its own cards. PvP protocol 7.
- [?] 0.45.1 spell cards carry a short rules line (WL.ABILITIES[..].short); the full rules show in a tooltip beside the close look and on the class picker. The shrink-to-fit now measures with a set width (it measured before layout and didn't shrink).
- [?] 0.42.2 companion cards: the pet that's out is drawn from the unit itself (model), and its appearance is learnt (a near-invisible on-screen model read back while it loads, or the card's own model) and kept for when it's dismissed and for the other player's screen; its level follows UNIT_LEVEL / UNIT_PET; right-click the pet again: "Discard its Wild Gambit card" (confirm; kills together are lost). Levels: the hero card is rebuilt from your level and Master Hunter count every time the pick table opens; a companion's level and kills update as it levels and fights.
- [x] 0.41.4 add-on policy check (Blizzard UI Add-On Development Policy, 2009: free, visible code, no realm impact, no ads, no donation asks, T-rated, ToS, Blizzard's discretion): all clear. Addon messages paced to the game's per-prefix allowance (10, then about 1 a second): auction sharing 0.3 s -> 1.1 s, Almanac-player hellos 0.35 s -> 1.1 s, Wild Gambit's match whispers 0.3 s -> 1.1 s and at most 20, travel sharing 1 s -> 2 s (two channels each).

- [?] 0.45.4 flights offer a game, not just Gem Match: Wild Gambit (its logo as the button), Murloc Tac Toe and Gem Match side by side, one recommended each flight (a different one from last time, glowing gold, named in the prompt). In the prompt at the top of the screen and on its own line in the talking-portrait panel.
- [?] 0.46.0 a three-step flow. 1) Who will you play? (the lobby on the felt): Practice (the creature near you, or the best your Almanac knows; "Someone else" picks again), Challenge a player (name box, My target), Find a match (search clock on the tile); what you played last glows; your practice and player records; a first-time tip (three lines, Got it). 2) Prepare: the opponent already in the seat; the ten cards with "...or let fate decide" under them; Play as with your spell shown as its card (hover: full rules); Back, and Begin / Ready (greyed until a card is picked or fate chosen); against a player the line says waiting / accepted / they're ready. 3) The match; the result offers Play again (same opponent: back to step 2, or a new challenge) and New opponent (step 1). Challengers and match-made players now press Ready when they've chosen (no more sending the card the moment the other side accepts). Portrait "Play Wild Gambit" and accepting a challenge go straight to step 2. Creatures page: the favourite heart moved to the top left of the card box.
- [?] 0.46.2 practice difficulty: Easy (misses the best move about half the time, ignores what your hand could do, uses its spell less, and its two strongest cards play a tier lower), Normal (the default, a little gentler than before) and Hard (the old near-perfect play). Set on the Practice tile (Difficulty: X >) or in Settings, Wild Gambit, Practice difficulty. The hidden chosen card now looks stealthed instead of the Shadowmeld icon: the model shimmers half-seen under a drifting haze over the art window (spikes stay readable); uses Media\FX_Stealth when that art arrives, a tinted glow until then.
- [?] 0.46.3 prepare screen: the Play as row and "...or let fate decide" moved down clear of the lower cards; a hovered pick card grows less (1.7x, was 2.4x); the elite/rare plate dragons no longer show on the painted frames (they read as stray rings on the narrow name panel).
- [?] 0.46.4 lobby: the Challenge and Find a match icons (and Practice's question mark) zoomed in so their square edges stay inside the round frames.
- [?] 0.46.5 the hidden card is unmistakable: a pulsing violet stealth outline round the whole card, its frame cloaked a dark violet (spikes and number stay bright), and a hooded-eye badge at the bottom left of the art (an eye icon until Media\Badge_Hidden is painted), on top of the shimmer and haze. The haze now always uses the placeholder until FX_Stealth arrives (a missing file would have drawn nothing).
- [?] 0.46.6 the close look at a hovered card in a match is 35% smaller (1.56x, was 2.4x).
- [?] 0.46.7 hidden card art: Media\Badge_Hidden (the hooded figure with violet eyes, replacing the eye icon) and Media\FX_Stealth (violet smoke on black) in two layers that rise and fade in turn across the art window; choosing a card on the Prepare screen plays the rogue Stealth sound.
- [?] 0.46.8 the blocked-action record keeps the latest 30 (it had filled with the old map-pin blocks of 0.17.6 and stopped recording), so a new "blocked from an action" popup can be traced from SavedVariables.
- [?] 0.46.9 hands size themselves: each card is as big as its row allows with its spikes clear of its neighbours (six in hand about 0.69, five 0.83), never wider, spikes and all, than the plank (0.88 at most); as cards leave, the rest spread out and grow; the flight to the board starts from the card's current size. The hidden card's hooded badge moved down onto the band under the art.
- [?] 0.46.10 the hidden card loses its violet outline (the cloaked frame, badge, smoke and shimmer stay).
- [?] 0.47.0 How to play: a guided match against The Gambit Tutor (15 steps on a parchment note over the board's bottom row, a gold glow on what it talks about). Your hand, spikes, your hidden card, your spell; the Tutor plays first (scripted), you capture its card (6 against 1), it takes yours back (7 against 2), you win it back (5 against 3); only the asked-for card and square work until then, and your spell waits. Then "Play on": the rest of the match against an easy Tutor that casts no spell. Not counted in your record ("Tutorial complete!"). Offered once in the lobby (Play the tutorial / Got it, for everyone, old players included), then a How to play button under the record; /aa gambit tutorial. Skip the tutorial any time.
- [?] 0.47.1 the close look at your hidden card keeps its stealth look (smoke, shimmer, frame tint, hooded badge).
- [?] 0.48.0 the players' header dressed: a carved nameplate (Media\Header_Nameplate, mirrored for the opponent) from each portrait towards the vs, the name along it over an inlay of the class colour, the score on a bronze coin (Header_ScoreCoin) in its round end, and a gold arrow (Header_TurnGem) at its far end nudging towards the board on that player's turn.
- [x] 0.48.1 fix: the tutorial errored at the deal (the Tutor's icon face went to SetPortraitTextureFromCreatureDisplayID in the card clasp); icon faces are drawn as textures.
- [?] 0.48.2 the hidden card's badge moved left to the frame's edge.
- [?] 0.48.3 the turn arrow points back along the nameplate at the name whose turn it is (it pointed away).
- [?] 0.49.0 holiday boards: Hallow's End (Media\Board_HallowsEnd: pumpkins, skull, bat and cat, ember runes) and the Feast of Winter Veil (Board_WinterVeil: yetis, reindeer, holly, frost runes), in the Board picker; with "Holiday boards" on (the default) the board dresses for the season by itself during Hallow's End (18 Oct - 1 Nov) and Winter Veil (16 Dec - 2 Jan), whichever board you picked.
- [?] 0.49.1 fix: "AzerothAlmanac has been blocked from an action" (SpellStopCasting / SpellStopTargeting, on Escape and logout). Cause: QoL/WildGambit.lua reassigned the game's StaticPopupDialogs table ("StaticPopupDialogs = StaticPopupDialogs or {}", added in 0.42.2 and 0.44.2), which taints it; the game menu then refuses its own protected calls. Both lines removed; only our keys are added to the table. Traced from the blocked-action log (db.diag).
- [?] 0.50.0 player matches (first real 1v1 test), protocol 8 (both players need 0.50.0):
  - The opponent's portrait is never a card any more (it was their first card: their hidden one). Their live portrait when they're in sight (target, focus, group, nameplate), else their race's portrait (race and sex now travel with the setup message). Same on the cards' owner clasp.
  - Whose turn: a warm glow round that player's nameplate (with the arrow). Nameplates taller; the score on a bigger bronze coin over the frames, outlined.
  - A card taking several lunges clearly at each in turn (bigger lunge, a little slower).
  - Pick Pocket: the hint says "click one of your cards on the board" (a click in the hand no longer selects a hand card while choosing a target); the status line is short enough not to be cut off.
  - In combat the game pauses for both players (P|gid|1/0); the practice gambler waits too. The window tucks into a small bar (Settings, Wild Gambit, In combat: dock top / left / right, float, or leave open) and comes back when combat ends. A "-" button on the window tucks it away by hand (floating, movable); click the bar to come back.
  - The "forfeits" at Ready: a game the other screen called off (a card it rejected, or out of step) now says so on both screens and isn't counted. The creature level check against the database is gone (WoW Forever's levels don't always match it; it rejected cards on one screen only). A first move that arrives before this screen has begun is kept and played.
  - Grey (Poor) cards keep their scene in colour.
  - Settings: the practice difficulty, table, board, holiday boards and card back pickers now change the Wild Gambit settings (they were writing to the Gem Match settings).
- [?] 0.51.0 Wild Gambit:
  - Opponent in combat: a note over the board (they're in combat, the game waits) with "Tuck it away" (into the bar, docked as set) or "Wait here"; when they're back, the table returns if it was tucked away for them, with a ready-check chime and a line in chat.
  - Shuffle on the pick screen (above the first card): the cards are swept into the deck, riffled and dealt again one by one, turning over as they land (paper and page sounds). You and your companions always come back; the rest are drawn at random (favourites a little likelier). The picked card stays picked if it comes back.
  - Let fate decide is a die between Back and Begin (Interface\Icons\INV_Misc_Dice_01 in a gold ring): it glows on hover, pulses and rocks while fate has the choice, with a dice sound. Fate now picks your class too (the class picker and spell card grey out; a class or card clicked takes the choice back).
- [?] 0.51.1 the turn glow round the nameplate is twice as strong (two glow layers) and reaches twice as far.
- [?] 0.52.0 header: the score coin sits inside the nameplate's round end (smaller, font 19) and the spell and portrait move out 6, so the plate starts clear of the portrait frame.
- [?] 0.52.0 shuffle: the pick table always opens face down and shuffles in front of you (gathered, riffled twice in two halves, dealt one by one face up); "Shuffling the deck..." and a glow under the deck while it runs; Begin waits for the deal. Refreshes while open don't reshuffle.
- [?] 0.52.0 new board: The Dark Portal (Media/Board_DarkPortal.tga, arch foreshortened above the board), the default board for testing (a board picked before is reset once); the dragon's red eyes and the four corner creatures' fel green eyes glow and pulse; no vs shield on this board (the dragon stands between the players). Needs a full restart (new texture).
- [x] 0.52.1 Dark Portal test done: the board and its art are taken out and Forest glade is the default again (it returns later with new art; the glowing-eyes and no-vs-shield support stays, driven by a board's `eyes` / `crest` fields).

## 68. Almanac players and the update quest (2026-10-05, version 0.24.0) [?]
- [?] New Modules/Peers.lua: finds other players running Azeroth Almanac with hidden addon messages (prefix AzAlmHi; H|version = hello, answered once by whisper with I|version). Hello goes to the guild at login, the group when it changes (30 s throttle), online friends (spaced 0.35 s apart, max 60), and a same-faction player you target or mouse over (once per 10 min each). No realm-wide channel. Answers jittered 0.5-3.5 s, at most once a minute per player. Known players kept in AzerothAlmanacDB.peers (name, version, via guild / friend / group / seen, last seen), forgotten after 30 days.
- [?] Tooltip badge on players who have it: the Almanac icon and "Almanac" in red.
- [?] New UI/UpdateQuest.lua: when someone's copy is newer, a pretend quest "New Version Available" from "Azeroth Almanac" in the quest giver window's style (portrait, parchment, Quest Objectives, Rewards with two joke items in quest-reward name frames and tooltips, Accept / Decline, the quest window sounds). Accept = "Quest accepted" message, no repeats for that version; Decline = asks again next login. Waits for combat to end. /aa version quest previews it; /aa version also shows how many Almanac players are known.
- [?] Settings > General > Almanac players: let others see me (off = never says hello or answers), tooltip badge, update quest, count.
- Protocol tested with two simulated clients (hello / answer, throttles, update quest once, share off, version compare).
- [?] 0.24.1: Characters list rows roomier: 60 px rows (was 50), portrait kept at 46, 4 px between the name / race-class / money lines (was 2).

## 67. Gentler mouse-wheel scrolling (2026-10-05, version 0.23.1) [?]
- [?] The scroll template jumped half the visible height per wheel notch (~250 px on the quest page). Every Almanac scroll area (W.SkinScroll -> W.WheelScroll) now moves a fixed step: lists 3 rows (78 px at 26 px rows), pages 40 px, times Settings > General "Scroll speed %" (50-200, default 100), gliding there when "Smooth scrolling" is on (default). Quick notches add up; Shift + wheel keeps the half-page jump. Covers all pages, the Characters inventory, settings and the People list.

## 66. Creatures page: dragons, Sighted colour, counts, rename (2026-10-05, version 0.23.0) [?]
- [?] Bestiary renamed Creatures everywhere it shows (page / window title, sidebar, "Click to open in Creatures.", help, settings text). Code keys stay "bestiary"; /aa bestiary and /aa creatures both work.
- [?] The Sighted tier icon keeps its colours everywhere (filter button, row badge, detail badge); its coloured ring stays. Filter buttons only grey out when switched off.
- [?] Tier filter counts sit beside each badge with room for 4 digits (34 px), buttons spaced 40 px apart.
- [?] Target frame dragons (W.SetDragon / W.DragonFor in Widgets): gold UI-TargetingFrame-Elite for elites and bosses, UI-TargetingFrame-Rare for rares, -Rare-Elite for rare elites, cut x 146..256, y 0..100 and wrapped round the right side of a round portrait. On the detail page a 44 px face portrait now sits left of the name (ring gold / silver / orange by class) with the dragon; list rows get the dragon round their small face and the name moves over 8 px.

## 65. Healer Assist: the player frame's health bar (2026-10-04, version 0.22.6) [?]
- [?] The queue panel's health bars use the player frame's own fill (atlas UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health, from /aa whatis), untinted, over a near-black empty part; incoming heals and the hover preview use its -Status fill tinted teal. Dead / absent members: the same fill desaturated and greyed. Falls back to the classic UI-StatusBar in green where the atlas is missing.
- [?] 0.22.7: the border too. The slot is part of the player frame's single texture (UI-HUD-UnitFrame-Player-PortraitOn, 198x71); from the /aa art layout snapshot the health bar sits at x 68..192, y 26.5..45.5 in it. Cut in three (right end with the frame edge, a stretched middle, the right end mirrored for the left since the real left end meets the portrait ring), scaled to the bar's height, drawn under the bar like the game does. Cut numbers in SLOT (HealAssist.lua) if it needs nudging.
- [?] 0.22.8: in combat the aggro glow drew a big red box round the player frame (a 2 px rectangle on the 232x100 frame, much bigger than its 198x71 picture). On portrait frames (player, party) the glow is now the game's own status glow (UI-HUD-UnitFrame-Player-PortraitOn-Status, or the frame atlas + "-Status") laid over the frame's picture and tinted by threat level; other frames (raid) keep the rectangle.
- [?] 0.22.9: Bestiary page icon is now Icon_UpgradeStone_Beast_Legendary (falls back to the old creature icon). Creature toasts and fallbacks keep the old icon.

## 64. Murloc Tac Toe (2026-10-04, version 0.22.0) [?]
- [?] New QoL/MurlocTacToe.lua: tic-tac-toe, Murlocs against Gnolls, against another player running Azeroth Almanac (hidden addon whispers, prefix AzAlmMTT, protocol 1: challenge / accept / decline / move with sequence numbers / resign / leave / rematch, plus a board resync if the two get out of step). Challenger plays Murlocs and moves first; sides swap on every rematch.
- [?] Art: each side's 3D model on its player card (display 506 Murloc Flesheater, 175 Riverpaw Gnoll, both seen on Forever), the creatures' round faces as pieces in the talent window's circle rings (minimap ring fallback), shaman Restoration painting behind the board, dialog gold border, gold grid lines, drop-in animation, star / ping bursts, a winning line that draws itself, attack / cheer / dead animations on the cards.
- [?] Sounds: the creatures' own voice files (murloc aggro A/B/C and the classic AggroOld on a win, gnoll aggro 1-3), ready check on a challenge, PvP victory / quest failed / water splash.
- [?] Ways in: /aa mtt [name | target | practice], "Murloc Tac Toe" on player right-click menus (the game's Menu system, when present), the minimap menu, Settings > Fun > Murloc Tac Toe. Popup for incoming challenges (30 s); offline players detected from the system message; Resign becomes "Leave (no penalty)" after the other player is quiet for 60 s on their turn.
- [?] Records per opponent (W / L / D), a title from total wins (Tadpole, Mudfin, Tidehunter, Coral Champion, King of the Shoals; "Undefeated" with no losses), practice record kept apart. Settings: accept challenges, only from friends / guild / group, menu entry, sounds, erase records.
- [?] 0.22.1: first live test, the challenge got no answer (and "the game blocked UNKNOWN() while meeting townsfolk"). Added `/aa mtt ping Name` (asks the other Almanac to answer with its version and whether it takes challenges), `/aa mtt debug` (prints every message sent / received), and a chat warning when the game refuses to send (SendAddonMessage result code). Townsfolk: CheckInteractDistance no longer called in combat (restricted there).
- [?] 0.22.2: the game writes an offline Name-Realm as "Name Realm" in its "No player named" message, so offline players weren't caught and the challenge sat "waiting" (blocking new ones). Now matched without spaces / hyphens; a new challenge also replaces one still waiting. Realm part capitalised. (The "PingZipporah" challenge came from 0.22.0 still being loaded: no /reload after the update.)
- [?] 0.22.3: `/aa version` prints the loaded version.
- [?] 0.22.4: live test got stuck: the game started on the accepting side but the challenger never saw the accept. Cause: Forever surnames ("Zipporah Olaris", typed "Zipporah-Olaris"): the Almanac squashed spaces and added a realm, so the sender name never matched the opponent. Names are now sent exactly as given and compared loosely (case / spaces / hyphens ignored, own realm dropped, a bare first name matches the same first name with a surname). A new challenge to / from the same player, or once the other side is quiet, replaces the stuck game; `/aa mtt leave` ends one with no record. Simulated with surname names in both sender formats.
- [?] 0.22.5 polish: bigger window portrait (74 px murloc face) in the classic elite target frame's gold dragon (UI-TargetingFrame-Elite, cut and mirrored to wrap the window's outside); player cards and board in the quest page's map-box look (dark list background, QuestLog-frame border, filigree); QuestLog-frame-devider dividers in the side panel; "VS" in the game's big Friz font (Morpheus made "vs" read "V8").
- [?] 0.23.2 / 0.23.3: player cards kept plain (CARD_PLAIN: no frame, background or stage painting; the models stand on the window), models 5 px higher.
- Protocol tested offline with two simulated clients (challenge, moves, draw, win, rematch both ways, simultaneous rematch, resign, decline).

## 63. Talent Planner: unspent counter and native node look (2026-10-04, version 0.21.4) [?]
- [?] "Unspent Talents" label with a large green number in a box at the top right of the Planner, like the native tab (grey at 0).
- [?] Node states from /aa whatis: takeable = talents-node-square-green with the greenglow, part / fully ranked = green / yellow, out of points = gray, locked = locked; only the rank number shows.
- [?] Prerequisite arrows: thin 2px lines (gold when met, dark otherwise) with talents-arrow-head-yellow / -locked heads. Tree headers: points in a small dark badge on the icon, name in the large white font.
- Not captured as atlases (yet): the per-tree background paintings and the Apply Changes button glow.

## 62. Quest map at the top of the quest page (2026-10-04, version 0.21.2) [?]
- [?] The quest's zone map (the Almanac's ZoneMap: the game's map tiles and explored areas) heads the quest page: where it's turned in once it's in your log, else where it's given, else where you killed most of what it asks for. Pins: giver ("!"), who takes it in ("?"), skulls where you killed its targets (up to 30 per creature), you. Click a giver / ender pin for a waypoint, a skull for the creature.
- [?] 0.21.3: most quests had no map: they were read from the quest log (taken before the Almanac, or never seen at the giver), so they have no giver / ender position (only 22 of the records do). The map now falls back to: people the quest names whom you've met (QuestDB starters / enders, their recorded positions, pinned as "!" / "?"), then the zone named by its quest log heading (`rec.cat`, matched to your discovered zones by name), then where you killed its targets.
- [?] Framed like the quest log: dark backing, `QuestLog-frame` border (sliced; double bronze line if missing), `QuestLog-frame-filigree` on top, `QuestLog-frame-devider` between the map and the parchment (both from the quest log's own art, `/aa whatis` 2026-10-04).

## 61. Quest page layout like the quest log (2026-10-04, version 0.21.1) [?]
- [?] A quest's page: parchment (title, objectives, Description, Progress, Completion), then the Almanac's own facts on the standard dark panel (new `{ "dark" }` block: the recipe-list background edge to edge with a bronze rule; Quest Givers, What it asks for, The Story, Your Characters, first found), then at the very bottom the quest log's brown reward band with only Rewards in it (no band when a quest has no rewards).
- [?] Slots on quest pages use the quest log's reward box size everywhere: about 170 wide, 34 a row (they were half the page wide, 36 / 44 high).

## 60. Talent Planner (2026-10-04, version 0.21.0) [?]
Ported from Plus Everything (`TalentPlanner.lua`, `TalentPlannerLogic.lua`, data `TalentData.lua` / `TalentText.lua` from talentsforever.com, CC BY 4.0 - `Licenses\TalentsForever-CC-BY-4.0.txt`), now in `QoL\`.
- [?] A **Planner** tab on the game's Talents window after Primary / Secondary (`/aa talents`, Settings > Talent Planner): any class, any level, click to add / right-click to remove, save / load / delete / follow builds, talentsforever.com links in and out, "My talents", Reset, **Stage in game** (adds the plan's points in order to your real talents; you check and press Apply Changes), level-up hint and glow on the next followed talent.
- [?] Fixing Plus Everything's flaws (wrong placements, 185 talents not found when staging, text from outside the game): every class's tree is **read from the game** (yours from your config, others through the view loadout) and laid over the data (`TL.Merge`): each talent takes the game's row, column, ranks, prerequisite, node, entry, spell and icon, matched by name then place; game-only talents are added, data-only ones hidden. Staging uses the game's node IDs directly. Tooltips show the game's own trait tooltip (`SetTraitEntry`) when available, else the data's Forever text. Reads are saved per class (`qol.talentPlanner.trees`).
- [?] Look from `/aa whatis` on the talent window (PlayerSpellsFrame.TalentsFrame.ButtonsParent): nodes with `talents-node-square-shadow`, icon, then `talents-node-square-locked` / `-gray` / `-green` / `-yellow` by state, `talents-sheen-node` on takeable nodes; arrows `talents-arrow-head-*` (and `talents-arrow-line-*` if present); node size, icon inset and spend-count font copied from a real node.
- [ ] Check in game: tree placements per class (Paladin, Mage, Hunter, Shaman alts), arrows, tooltips (game vs data), Stage then Apply. `/aa talents probe` saves the raw node data if a tree reads wrong.

## 59. /aa whatis saves its output (2026-10-04, version 0.20.5) [x]
- Every `/aa whatis` run is saved to `AzerothAlmanacDB.whatis` (last 20 runs, up to 6000 lines each) so long output can be read from SavedVariables after /reload.
- `/aa whatis window`: the whole window under the mouse (climbs to the frame below UIParent, 12 levels deep): every shown frame (name, type, size), texture (atlas, file, size, layer) and font string (font object, face, size, colour, text). Saved only; chat gets a line count. `/aa whatis clear` forgets the runs.

## 58. Item tooltip card on the Items page (2026-10-04, version 0.20.4) [?]
- [?] An item's page opens with its own tooltip card (a separate GameTooltip, `AzerothAlmanacItemCard`, so the mouse-over tooltip is untouched), laid into the page above General and scrolling with it; other addons' tooltip lines show on it too. Filled from the item link (or ID), refreshed with the page when item info arrives.

## 57. Gear tab: class emblem for other characters (2026-10-04, version 0.20.3) [?]
- [?] The middle of the Characters page's Gear tab shows the class emblem (round, 160 px, as on their portraits) for characters you're not playing, instead of the race portrait / custom-race model. Your own character keeps the live 3D model.

## 56. Taller window (2026-10-04, version 0.20.2) [?]
- [?] The Almanac window is 680 px tall (was 580), so the Characters page's Gear tab (paper doll rows tightened to SLOT + 5, about 400 px) and Professions tab fit without a scroll bar (body area about 420 px). The side tabs still shrink to fit if there are many. The window stays clamped to the screen and follows the Scale setting.

## 55. Almanac and Journal icon (2026-10-04, version 0.20.1) [?]
- [?] The Almanac's own icon is now file 133742 (picked with `/aa whatis`): `ns.ICON` (minimap button, its menu title, the addon compartment, the window portrait fallback, toasts without their own icon), the AddOns list (`## IconTexture`), the Journal side tab / portrait, the Journal entry in the minimap menu, the General settings page.

## 54. Quest log look on more lists (2026-10-04, version 0.20.0) [?]
- [?] `W.List{ style = "log" }` gives any list the Quests page's Map & Quest Log look (shared in `DefaultRow`): gold-edged heading boxes (3-sliced `common-button-list-collapseExpand`) with light GameFontHighlightMedium text as written and a gold - / +, entries in the quest titles' font, `QuestLog-quest-glow-yellow` on hover (soft) and selection (full), no spacer rows, the box on its own layer under the row's words and icons. Used by Merchants, Trainers, People, Places, Dungeons and Gathering (rows 24 px). Other lists keep the recipe-list look (section 52).

## 53. Quests list in the quest log's look (2026-10-04, version 0.19.8) [?]
- [?] The Quests page list now draws its own rows (`QuestRow` in `UI\Pages\Quests.lua`): headings in the quest log's gold-edged box (`common-button-list-collapseExpand`, 3-sliced by the new `W.Slice3` so the ends don't stretch) with large light text, a gold - / + and the count; quests as "[18] Reading Room" in the difficulty colour, quest log title font (GameFontNormalMed2), the log's yellow glow (`QuestLog-quest-glow-yellow`, captured) under the mouse and on the quest being read. Rows 30 px.
- [?] 0.19.9 polish from a side-by-side with the quest log: headings were blank (the heading box frame drew over the row's text; now box, then words on a layer above); everything scaled down (quest titles GameFontNormal, headings GameFontHighlightMedium, rows 24 px, no spacer rows before headings: `W.List{ spacers = false }`); icons on the log's round button `UI-QuestPoi-QuestNumber` (captured) with "?" when ready to turn in (C_QuestLog.IsComplete), "..." in progress, the log's yellow tick `QuestLog-icon-checkmark-yellow` for done, "!" offered, red cross abandoned.

## 52. Recipe-list row highlights (2026-10-04, version 0.19.7) [?]
- [?] Every list row (all page lists via `W.List`, and the Settings sidebar) uses the profession window's recipe list look: grey glow under the mouse (`Professions_Recipe_Hover`, captured with `/aa whatis`, file 4417031) and the gold bar on the selected entry (`Professions_Recipe_Active`, name expected, not captured; flat gold fill if missing). Headings show no row glow. Helpers `W.RowHover`, `W.RowSelected`.

## 51. Page order, Townsfolk renamed People (2026-10-04, version 0.19.6) [?]
- [?] Side tabs in this order: Journal, Characters, Bestiary, Items, Quests, Gathering, Places, Dungeons (not in the list given; placed after Places), People, Trainers, Merchants.
- [?] Townsfolk is called **People** everywhere the player sees it (page and tab, settings page, world map button and its menu, journal filter and links, milestones "Met 25 people", chat help). Internal keys stay `townsfolk` so saved data and settings carry over; `/aa people` works alongside `/aa townsfolk` / `/aa tf`.

## 50. Skinning by what you skinned (2026-10-04, version 0.19.5) [?]
- [?] The Gathering page's Skinning group lists the skinned items (leather, hides, scraps: item icon, quality colour, how many skins gave it) instead of creatures. Search also finds an item by a creature it came from.
- [?] An item's page: kind, times skinned, how many creatures, first found (from the item record); **Came from**: each creature with its research tier, "n of m skins" and, once that creature is Mastered, its Classic chance; click opens it in the Bestiary. **Where**: zones where those creatures were killed (creature names listed); click / Show on map pins every kill spot in Places, each named for its creature. Link to the item in Items.
- Built from the creatures' existing records (`gathered`, `gather[item]`), so past skinning carries over; no new saved data. Quantities per skin aren't recorded (only whether a skin gave the item). Creatures keep their own skinning loot in the Bestiary; research tiers stay per creature.

## 49. Townsfolk icon (2026-10-04, version 0.19.4) [?]
- [?] Townsfolk use icon file 8197123 (picked with `/aa whatis`): the Townsfolk side tab and page portrait, its Settings page, the button at the top right of the world map, townsfolk discoveries in the journal and toasts, and townsfolk milestones.

## 48. Places icon (2026-10-04, version 0.19.3) [?]
- [?] Places use icon file 4624629 (picked with `/aa whatis`): the Places side tab and page portrait (the page takes the zone kind's icon), zone rows and zone discoveries in the journal, toasts and the minimap menu.

## 47. Mastered icon (2026-10-04, version 0.19.2) [?]
- [?] The Mastered research tier uses icon file 4238797 (picked with `/aa whatis`; the old 4622480 stays as fallback): tier badges, tier filter buttons and bar marks in the Bestiary and Gathering, tooltip lines, tier toasts.

## 46. Chest icon, second pick (2026-10-04, version 0.19.1) [?]
- [?] Chests and objects now use icon file 1450989 (picked with `/aa whatis`) instead of 132594, everywhere section 36 / 0.17.9 put the chest icon (Gathering category, list rows, portrait, Show on map pin, world map / minimap pins). 132594 and INV_Box_02 stay as fallbacks.

## 45. Characters tab shows your portrait (2026-10-04, version 0.19.0) [?]
- [?] The Characters side tab and the window portrait on that page show the character you're playing (the game's own portrait, `SetPortraitTexture`), kept current on `UNIT_PORTRAIT_UPDATE` and after loading screens. Any page can ask for this with `portraitUnit` in its definition. The character kind icon stays as it was for the journal and toasts.

## 44. Quests icon (2026-10-04, version 0.18.9) [?]
- [?] Quests use icon file 979575 (picked with `/aa whatis`): the Quests side tab and page portrait, quest discoveries in the journal and toasts.

## 43. Bestiary icon (2026-10-04, version 0.18.8) [?]
- [?] The Bestiary uses icon file 656556 (picked with `/aa whatis`): its side tab and page portrait (the page takes the creature kind's icon), creature discoveries in the journal and toasts, and the stand-in face for a creature the game can't draw.

## 42. Dungeons icon (2026-10-04, version 0.18.7) [?]
- [?] Dungeons use icon file 655958 (picked with `/aa whatis`): the Dungeons side tab and page portrait (the page takes the dungeon kind's icon), dungeon discoveries in the journal and toasts.

## 41. Items icon (2026-10-04, version 0.18.6) [?]
- [?] Items use icon file 515958 (picked with `/aa whatis` on the macro window's selected icon): the Items side tab and page portrait, and item discoveries in the journal, toasts and wherever the item kind icon shows.

## 40. Gathering icon (2026-10-04, version 0.18.5) [?]
- [?] Gathering uses icon file 237271 (picked with `/aa whatis` in the macro icon picker): the Gathering side tab and page portrait, its Settings page, gathering discoveries in the journal and toasts, and the herb buttons on the world map and minimap. The Herbs category itself keeps Trade_Herbalism.

## 39. Best vendor reward at quest turn-in (2026-10-04, version 0.18.4) [?]
- [?] At a quest turn-in with two or more reward choices, the choice that sells to a vendor for the most (sell price x count) gets a gold coin (`Coin-Gold`, else the money frame's gold icon) in the bottom right of its icon; ties all get one. Item info still loading: checks again a moment later. Cleared when the quest frame moves on or closes, and never left on the map's quest details (same buttons). Part of the Merchant helper (`QoL\Merchant.lua`), setting Merchants > Quest turn-ins (`merchant.bestReward`, on by default).

## 38. Dark panel background (2026-10-04, version 0.18.3) [?]
- [?] Every plain dark panel (`W.Inset`, and the QoL windows' `ns.NativeInset`) is filled with the profession window's recipe list background (`Professions-background-summarylist`, falling back to the auction house's `auctionhouse-background-summarylist`, else the inset's own). Panels with a painting show it on top. If the art doesn't appear, hover the recipe list background in the profession window and run `/aa whatis` for its real name.
- Style guide: dark list / fact panels use this background.

## 37. My Characters merged into Characters (2026-10-04, version 0.18.0) [?]
- [?] The separate My Characters window is gone; the Almanac's Characters page holds both.
  - **List:** 50 px rows: portrait (yours from the game's 2D portrait, the others' class emblem) in a class-coloured ring with the Alliance / Horde banner, name and level ("(you)"), race / class / zone, gold, last played, rested %. Right-click: hide / show, remove saved data (removes the Almanac record too). "Show hidden characters" under the list.
  - **Page header:** search across every character's items (bags, bank, gear, mail, auctions) and account gold.
  - **Name plate:** My Characters' header (live 3D model for you, class emblem for others, faction banner; name, class line; chips in two rows: gold + rest, last location (click: world map there) + hearthstone; data freshness top right; XP / rested bar along the bottom with the login checks on hover). Average item level under the freshness on the Gear tab.
  - **Tabs** in a strip between the plate and the body, the Settings panel's tab art (`Options_Tab_*` / `Options_Tab_Active_*`) with a game icon each: Story (the page's old content: general, first to discover, levels), Gear, Bags, Bank, Auctions (count), Professions. Mail left out as asked (still recorded, and found by search).
- Code: `QoL\InventoryWindow.lua` is now a renderer (`IW:BuildHeader`, `IW:SetHeader`, `IW:Draw(content, c, tab, width, summary)`, `IW:DrawSearch`, `IW:Find` maps an Almanac key to the inventory record by name + realm / class; Almanac characters now also save `realmName`). `/aa inv`, the key binding and Settings open the page on the Bags tab; the minimap menu's separate entry is gone (Characters covers it).

- [?] 0.18.1: error on first open ("attempt to index upvalue 'invScroll'"): the search box fired a change while the page was still being built, so Refresh ran before the tabs and inventory scroll existed. Refresh now waits for Build to finish, and the search only redraws when its text really changes.
- [?] 0.18.2: the page still came up empty: Build stopped at the tab strip because `W.Detail` never exposed its scroll frame (`detail.scroll` was nil). Now `holder.scroll` is set.

## 36. Chest icon (2026-10-04, version 0.17.8) [?]
- [?] Chests and objects use icon file 132594 (picked in game with `/aa whatis` from the macro icon picker) for the Gathering category, its list rows and portrait, and map / minimap pins with no loot icon yet (INV_Box_02 kept as fallback).
- [?] 0.17.9: Battered Chest showed Ice Cold Milk (its most common drop). Chests and objects that give more than one kind of item now always use the chest icon (page portrait, list row, Show on map pin, world map / minimap pins); one-item objects (Farm Chicken Egg) still show their item.

## 35. World map pins not showing (2026-10-04, version 0.17.5 → 0.17.6) [x] (verified in game 2026-10-04)
- Report: three new nodes showed on the minimap but not on the world map. Saved data confirms the nodes are recorded with the right map keys (Barrens ore under 1413), and the minimap draws from the same records, so the world map side is at fault.
- [?] Likely cause: the XML pin templates name `AzerothAlmanacNodePinMixin` / `AzerothAlmanacTownsfolkPinMixin`, which were only created at login, after the XML loaded. Both mixins now exist from file load and get the map's pin methods mixed in later. Townsfolk pins (never confirmed in game) use the same fix.
- [x] **Real cause found in game (0.17.6):** pins only showed on city maps. Pins without a frame level type sit at the bottom of the canvas, under a zone map's exploration overlay (cities have none). Both pin kinds now take `PIN_FRAME_LEVEL_AREA_POI` (then VIGNETTE / TOPMOST, else a raised frame level) via `ns.LiftMapPin`. `/aa maptest` also prints a pin's frame level against the canvas.
- [?] **0.17.7:** with pins drawing, combat spammed "the game blocked Frame:SetPassThroughButtons()": the map canvas sets mouse pass-through on each pin it places, which is protected in combat. Both pin mixins now override `SetPassThroughButtons` / `SetPropagateMouseClicks` / `SetPropagateMouseMotion` with no-ops (the HandyNotes / TomTom fix; our pins hand the mouse to a child button). The blocked-action warning now prints once per function per session (still recorded in `AzerothAlmanacDB.diag`).
- [?] The node provider's refresh is now caught: errors are kept and shown by `/aa maptest` with the spot / pin counts for the open map (records, asked for, actually on the map) and the townsfolk pin count.

## 33. My Characters profession bars (2026-10-04, version 0.17.4) [?]
- [?] The gold bars on the Professions tab (and the generic row bar) replaced with the character sheet Skills window's rank bar: `common-stat-bar-BG` frame cut into left / middle / right from the atlas coordinates (10 source px caps), `common-stat-bar-blue` fill inset a sixth of the height and cropped by tex coords to the rank (not squashed), count in white GameFontHighlight centred. Fallback: dark box + blue status bar. Helper `SkillBar(parent, height)` in `QoL\InventoryWindow.lua`.

## 32. Dressing room on Ctrl-click (2026-10-04, version 0.17.3) [?]
- [?] Shared helpers in `UI\Widgets.lua`: `W.ItemModifiedClick(item)` (the game's DRESSUP binding, Ctrl by default: `DressUpItemLink` for wearable items; CHATLINK / Shift: chat link, only swallowing the click when a chat box took it), `W.IsDressable(item)`, `W.ItemCursor(frame, getItem)` (the inspect magnifier while Ctrl is held over a wearable, follows `MODIFIER_STATE_CHANGED`).
- [?] Used by every item slot (loot, rewards, merchant stock, gathering, trainers, journal blocks ...; runs before the slot's own click, so Ctrl-click no longer opens the Items page), the Items list rows and detail icon, Journal item entries, and lists via `W.List{ itemOf = fn }`. My Characters, bag / bank and the vendor window already use the game's `HandleModifiedItemClick`.

## 34. Travels: your trail on the map (proposed 2026-10-04, draw test passed) [~] (superseded by section 74, Journey)
A spaghetti map of where your characters have been: every position over time drawn as a line on the continent / zone map, so you can see your movement over a play session or your whole history.
- **Data now:** every journal entry has time, character, map, x, y (334 positioned entries on 2026-10-04: Zaphenat 85 Barrens, 57 Stranglethorn, 34 Ashenvale ...). Dense at discoveries, sparse while grinding or travelling known roads, so it gives a rough trail only.
- **34a Trail recorder:** a point every 5 s once you've moved ~15 yards (standing / AFK adds nothing): time, map, x, y. Grouped per character and session. Segments break on loading screens, continent change, hearth / portal, death, any jump over ~200 yards; flights recorded as their own (dotted) segments. Thinned at session end (drop points that don't change the shape), per-character cap, oldest thinned first (~20 KB per 4 h).
- **34b Drawing:** line objects on the map art; zone points converted to the continent with the maps' world corners (as townsfolk pins). Colour by age (old faded / dark, recent bright, today stands out) or by class colour for comparing alts. Journal events as markers along the line (first visits, flight paths, levels, deaths as a skull, dungeons) with hover and click.
- **34c Where:** a Travels view on the Characters page (character, range: session / today / day picker / all, continent), and a footprints button on the world map beside the herb and spyglass buttons (left-click: today's trail, right-click: settings).
- **34d Replay:** play button and time slider; the line draws in time order with a marker moving along it (1 min / 10 min / 1 h per second), time, zone and level shown.
- **34e Settings:** recorder on / off and rate, thickness, colour mode, flights, markers, forget session / all, cap.
- Fits the rules: your own journey only, no "% of the world walked".
- [x] **Draw test passed (verified in game 2026-10-04): lines and dots both draw on the world map canvas.** `/aa maptest` with the world map open draws your journal points as a time-coloured line with a dot per point and reports whether line objects exist, how many points fit the map, line / dot counts. `/aa maptest all` = every character in class colours, `dots` = the dot fallback, `off`. Try a zone map and a continent map, zoom in and out (the drawing lives on the map canvas, so it should pan / zoom with it). Decide from the result whether to build 34a-e.

## 31. Rivals: PvP encounters (proposed 2026-10-04, parked for later) [ ]
Enemy players you meet, fight, beat or die to. Same rules as everything else: only players you have actually met, no totals. Research tiers don't apply; each record gets a relationship label instead.
- **Record** (account-wide, keyed by name-realm; wins / deaths also per character): name, realm, class, race, faction, guild (as last seen), class emblem as portrait. Every encounter: time, zone and spot, their level and yours ("??" kept as "??"), outcome (seen / fought / won / died / fled). Running counts: seen, fights, wins, deaths, duels won / lost, battlegrounds together. From the damage meter: damage each way and the spells they hit you with. First seen, last seen, which character met them first.
- **Labels instead of Studied / Mastered:** Stranger (seen) · Foe (fought) · Rival (5+ fights, mixed) · Prey (3+ wins, no losses) · Nemesis (killed you 3+ times). Labels follow your history and can change.
- **Sources** (combat log is blocked):
  - Seen: target / mouseover / nameplate name, level, class, race, guild, faction (proven for creatures; check for players).
  - Fight start / end: regen events plus player units seen during the fight (proven).
  - Damage and spells: damage meter per attacker name (proven for creatures).
  - Win: their unit seen dead after you hit them, or the honorable-kill chat message naming them (probe). Without the combat log a nearby death isn't proof, so honor message and scoreboard first; "seen dead after you hit them" counts as a likely win.
  - Death: player death + damage meter Deaths view for the killer (Deaths view still unseen, see 22).
  - Duels: "X has defeated Y in a duel" system message (probe).
  - Battlegrounds: scoreboard names, class, race, kills, deaths, honor (probe).
- **UI:** new side tab "Rivals": list grouped by label or class, search, collapse-all. Player page: dark stat panel (class / race, guild, last seen, wins / deaths), parchment timeline of encounters, their spells as icon slots like Bestiary abilities. Tooltip line on enemy players ("Rival · 4 fights, you won 3 · last met 2 days ago at level 22"). Toasts: first meeting Common, first win Uncommon, new Nemesis Rare; journal entries; milestones from your own counts (first honorable kill, 10 wins). Optional last-seen map pins for Nemeses.
- **Settings:** on / off, include same-faction duels, include scoreboard-only players, tooltip line, toast tiers, ignore list, forget a player, pruning (drop Strangers not seen in N days, always keep anyone fought).
- **Build order:**
  - [ ] 31a Probe: read enemy players, die to one, win one, a duel, a battleground; confirm each source above.
  - [ ] 31b Recorder: records, encounter log, win / death credit, pruning.
  - [ ] 31c Rivals page and player page.
  - [ ] 31d Tooltip line, toasts, journal, milestones.
  - [ ] 31e Duels, battleground scoreboards, Nemesis map pins.
  - [ ] Bug check, then in-game test.
- Open: final name (Rivals / Adversaries); whether Forever has the honor system and battlegrounds at launch.

## 72. Wild Gambit dungeon cards (designed 2026-10-07, reworked 2026-10-08) [?] (practice: built 0.67.0; debug panel 0.67.1; player matches: 0.69.0)
Decided with Shannon (2026-10-08 rework: dungeon cards are events that hit both players, not cards you play):
- [ ] **Triggered, not played.** Each time a card leaves a player's hand, 5% chance a dungeon event fires at once (no warning), at most one per match. It's drawn only from the *triggering* player's entered dungeons (found.instance); the card appears showing that player as its owner ("Triggered by <name>", their colour), and they get the credit. Rolled with a seeded generator of its own (both screens agree in player matches).
- [ ] **Only if it does something.** A dungeon whose event would change nothing right now (no Undead on the board for Purge, fewer than 3 moves left for Nightmare...) is passed over for another from that player's list.
- [ ] **Running out of new cards:** a player whose 3 reserves are spent draws from their whole collection for the rest of the match. New cards are never spell cards.
- [ ] **Card look:** the stone-arch frame (Frame_Dungeon) with the dungeon's journal art, flickering torches (FX_TorchGlow), the event's name and rules on the plaque, the owner's name; the portal swirl (FX_DungeonPortal) as it appears. Lasting events keep the card beside the board while they hold.
- [ ] Dev: `/aa wgdungeon [dungeon]` fires that event (or a random one) as yours in a practice match. Code mostly in QoL/WildGambitDungeons.lua.

Events ("each player" = both; replaced cards come from reserves, then the collection):
| # | Dungeon | Event | Kind | What happens | Effect art |
|---|---|---|---|---|---|
| 1 | Ragefire Chasm | Uppercut | Instant | The board is slammed: the cards in the top row are shuffled among the top row's squares (owners unchanged). | board shake (code) + dust |
| 2 | Wailing Caverns | Nightmare Sleep | 1 turn | One random card in each player's hand falls asleep and can't be played on that player's next turn. Not with fewer than 3 moves left. | game's sleep icon (Spell_Nature_Sleep), card greyed, gentle bob |
| 3 | The Deadmines | Van Cleef's Plunder | Instant | One random card is pirated from each player's hand (decided: the hand); a fresh, weaker card is dealt in its place. | FX_PickPocket (existing) |
| 4 | Shadowfang Keep | Worgen Curse | Lasting | No magic: both players' spell cards are removed for the rest of the match. | NEW: anti-magic bubble over the board |
| 5 | The Stockade | Prison Riot | Instant | Two random cards, one from each player, swap sides. | FX_MindControl / pick-pocket swap (existing) |
| 6 | Blackfathom Deeps | Rising Tide | Instant | The top row floats away (owners get new cards), the middle row rises to the top, the bottom row to the middle; the bottom row is left empty. | NEW: bubbles, floating cards |
| 7 | Gnomeregan | Backfire | Lasting | Every card placed has a 25% chance to self-destruct; its player gets a new card and plays again (no limit). | NEW: explosion with smoke |
| 8 | Razorfen Kraul | Thorns | Lasting | Equal sides capture too. | thorn glow (Spike_Thorn, existing) |
| 9 | Scarlet Monastery | Purge | Instant | Every Undead and Demon card on the board is banished; owners get new cards. | FX_Banish (existing) |
| 10 | Razorfen Downs | Death's Head | Instant | Every Undead card on the board gets +2 spikes on every side. | spike gain (existing) |
| 11 | Uldaman | Petrify | Lasting | Every card now on the board turns to stone and can never be captured. | greyed card + stone texture, rock sound |
| 12 | Zul'Farrak | Gahz'rilla | Instant | Each player's strongest card on the board loses 2 spikes on every side. | spike loss (existing) |
| 13 | Maraudon | Earthquake | Instant | The cards on the board are shuffled between their squares (owners unchanged); the whole board shakes violently. | board shake (code) + dust |
| 14 | Temple of Atal'Hakkar | Dreamer's Call | Instant | Every Dragonkin card on the board gets +2 spikes on every side. | spike gain (existing) |
| 15 | Blackrock Depths | Dark Iron Forge | Instant | Every card on the board gets +1 spike on every side. | spike gain (existing) |
| 16 | Lower Blackrock Spire | Rallying Cry | Next card | Each player's next card gets +2 spikes on every side. | glow on hands |
| 17 | Upper Blackrock Spire | Rend's Rampage | Instant | Rend executes each player's strongest card on the board (decided 2026-10-08); each player draws a new card. | FX_Execute (existing) |
| 18 | Dire Maul | Gordok Tribute | Instant | Each player's strongest card on the board is taken as tribute (removed); each gets a new card. | FX_Banish (existing) |
| 19 | Scholomance | Raise Dead | Instant | Each player takes back the last card the other captured from them. | ankh (Mark_Ankh / FX_Reincarnation, existing) |
| 20 | Stratholme | The Plague | Instant | Every non-Undead card on the board loses 1 spike on every side. | spike loss (existing) |
| 21 | Molten Core | By Fire Be Purged! | Instant | Fire engulfs the board and meteors fall: the board is wiped and both players get a new shuffle and a full hand of 5 (matched as at the start; no new spell cards). Play goes on from whoever's turn it is. | NEW: fire wall, meteors |
| 22 | Onyxia's Lair | Deep Breath | Instant | Onyxia breathes fire along a random row: every card there is removed; owners get new cards. | NEW: fire breath across a row |
| 23 | Blackwing Lair | Chromatic Mutation | Instant | Every card on the board swaps its strongest and weakest sides. | sparkles (Interface/Cooldown/star4, in game) |
| 24 | Zul'Gurub | Corrupted Blood | Instant | The last card placed and every card touching it lose 1 spike on every side. | spike loss (existing) |
| 25 | Ruins of Ahn'Qiraj | Sandstorm | Instant | Every card on the board turns 180 degrees. | sand swirl (optional) |
| 26 | Temple of Ahn'Qiraj | Executioner Gore | Instant | One board card and one hand card of each player are sacrificed; each is replaced (decided 2026-10-08). | FX_Execute (existing) |
| 27 | Naxxramas | Frost Breath | Lasting | A random empty square freezes over: out of play for the rest of the match. | NEW: frost breath, ice-covered square |
| 28 | Hall of Thanes | Anvil Oath | Instant | Every card's weakest side gets +2 spikes. | spike gain (existing) |
| 29 | Ruins of Lordaeron | Betrayal | Instant | Every card on the board changes sides. | FX_MindControl (existing) |

## 73. Dungeons page redesign (built 0.68.0) [?]
Asked by Shannon 2026-10-08; replaces the page from section 8. Two tabs:
- [ ] **Collection** (landing): a card per dungeon / raid found (the Wild Gambit dungeon card's look: stone arch, parchment, journal art, torches), 4 per row, scrolling; hover enlarges like the creature cards; under each: name, levels, bosses killed (x of y met), dungeon or raid. Only found dungeons show (hidden until earned); a counter says how many are found. Clicking one opens tab 2 on it.
- [ ] **Dungeon** (detail): header (name, levels, entrance zone, size, first entered and by whom, visits, time inside, quickest run with a kill). Left pane: the floor map (floor buttons when there are several) with each boss you've met as a round portrait pin where you met it; hover = name and kills, click = select. Bosses met without a position are listed under the map. Right pane, tabs:
  - with no boss chosen, **Overview**: bosses met / still to find (counts only), other creatures recorded inside (from loot, 0.66.0), loot you've had here, your characters' runs, the dungeon's Wild Gambit event card.
  - with a boss chosen, **Abilities** (seen, plus what its research tier unlocks from the hidden data), **Loot** (your drops with rates; the database's table as the tier allows; "N more items" otherwise), **Other** (kills, wipes, first kill by whom and when, research tier and the next step, health observed, immunities / resistances when unlocked, its Wild Gambit card, open in Creatures).
- [?] (0.68.2) The floor map is Blizzard's dungeon map art (`Interface\WorldMap\<folder>\<folder><floor>_1..12`, 4 × 3 tiles; C_Map has no dungeon maps on this client and no map ID inside), one floor at a time with a picker; boss spots come from AtlasLoot Revival's data (`f`, `x`, `y` in `Data\Dungeons.lua`), not from where you met them.
- [ ] Fallbacks: a dungeon with no map art shows its journal art in the left pane with the boss list; a boss with no face yet shows its creature-type icon.
- [x] Decided 2026-10-08: unfound dungeons hidden (a "found x of 29" counter only); unmet bosses stay off the map until discovered; built before the Wild Gambit player matches (now 0.69.0).
- [ ] **Cobweb placement (Shannon, 2026-10-09, from the in-game look at the abandoned cards):** the webs stay, but no longer sit in the same two spots on every card. Today they are baked into `Card_Ruin` (`art_convert.py ruin`), so every card has them halfway down both sides of the doorway.
  - Always inside the arch's doorway, in one of its four corners: top left, top right, bottom left, bottom right (the top ones tucked into the curve where the arch meets the pillar).
  - **1 to 3 webs per card**, in different corners, staggered so it looks organic: each a different size (about 18-32% of the doorway's width), a slight turn (±10°), a small offset from the corner and its own transparency (0.75-0.95), so no two cards match.
  - The choice is seeded from the dungeon's key, so a card keeps the same webs every time you open it.
  - Art: `Card_Ruin` is regenerated without webs, under a new file name (art rule: no replacing in place); a new `FX_Cobweb` texture holds one corner web (two or three shapes on one sheet for variety), mirrored by texture coordinates for the other corners and drawn over the scene, under the stone.
  - Wild Gambit's dungeon event card uses the same overlay, so it follows the same rule.
- [ ] Discovery of a boss (inside, names and GUIDs are hidden): the game's encounter starting (ENCOUNTER_START, the pin where you stood at the pull), its corpse looted (the corpse's spot), or, outside instances, seeing it as now. Walking past an unfought boss doesn't count.

## 74. Journey: where your hero has walked (noted 2026-10-08, details being settled) [ ]
Supersedes section 34 (Travels). Keeps its recorder (34a) and its draw test (lines and dots draw on the world map canvas, verified 2026-10-04).

**Concept (Shannon, 2026-10-08)**
- A **time lapse** on the map: the journey draws itself as a **gold, sparkling line**, following the order you walked it, through every place the character went in the chosen time frame.
- **Time frames:** today's journey, this week's, this month's, all time.
- **Character mode** (default): the character you're playing only, in gold.
- **Account mode:** all your characters at once, each line in its **class colour** (paladin pink, mage light blue ...) instead of gold.
- **Jumps** (the character is suddenly somewhere else): work out what happened.
  - **Boat or zeppelin:** a pin on the map showing a boat or a zeppelin was taken (at the dock you left from and the one you arrived at).
  - **Can't tell:** a portal on the map at both ends, using the dungeon cards' swirl (Media\FX_DungeonPortal).

**What we already have**
- Positions: each journal entry has time, character, map, x, y (too sparse for a line: dense at discoveries, empty while grinding or on known roads). A trail recorder (34a) is needed.
- Boats and zeppelins: QoL\Travel.lua already notices a ride (you're carried while standing still), with the port you left and the port you arrived at, and knows the classic and Forever routes (Boat / Zeppelin).
- Flight paths: Travel.lua knows when you're on a taxi and the from / to nodes.
- Art: FX_DungeonPortal (the swirl), the map line and dot test (/aa maptest).

**Proposed details (to confirm)**
- **Recorder:** a point every 5 s once you've moved about 15 yards (standing / AFK adds nothing); time, map, x, y. Thinned when you log out (points that don't change the shape are dropped). About 20 KB per 4 hours; oldest days thinned further, never deleted.
- **Telling jumps apart** (the gap between two points, in order of certainty):
  1. Flight path (on a taxi): the flight drawn as a dotted line from node to node, a gryphon / wyvern pin at each end.
  2. Boat / zeppelin (Travel.lua's ride): a boat or zeppelin pin at both docks, a dashed line across the water.
  3. Hearthstone (your own cast, if the game lets us read it): a hearth pin where you arrived.
  4. Dungeon in / out (an instance starts or ends): the dungeon swirl at its entrance.
  5. Death (ghost to the graveyard): a skull where you died; the run back drawn faint.
  6. Anything else (mage portal, summon, teleport, unknown): the portal swirl at both ends.
- **Time lapse:** the same length whatever the time frame (about 20 seconds for today, 30 for longer), idle time skipped, a glowing head on the line with the time and zone; play / pause, a slider to scrub, speed 1x / 2x / 4x. The line stays drawn when it ends.
- **Map:** the world map. The time lapse turns to the continent the line is on (it follows a boat across); a zone map shows that zone's part.
- **Account mode:** all characters play back together on one shared clock, so you see who was where at the same time; a legend of names in class colours; click a name to show or hide that character.
- **Where it lives:** a Journey tab on the Characters page, and a footprints button on the world map (left-click: today, right-click: the options).
- **Rules kept:** only your own characters; nothing is shared with other players; no "% of the world walked".

**Open questions**
- Flight paths: drawn as their own dotted line (as above), or pins only?
- Hearthstone: its own pin, or the portal like any unknown jump?
- Week and month: the calendar ones (week from Monday, month from the 1st), or the last 7 / 30 days?
- Account mode: one shared clock (above), or each character's journey played from its own start?
- Markers on the line from the journal (first visits, level-ups, deaths): keep, or the line and jump pins only?

**Effects, sounds and icons (approved by Shannon 2026-10-09, issue #49)**
Goal: the time lapse should dazzle the viewer. Every trigger below gets its effect, icon and sound.

*The line's head*
- The character you're logged in on: their live face (`SetPortraitTexture(tex, "player")`), round.
- Other characters, or no face available: the game's round class icon (`Interface\TargetingFrame\UI-Classes-Circles` with `CLASS_ICON_TCOORDS`); `Media\Crest_<CLASS>` is the alternative if it reads better. Last fallback: the Almanac logo.
- A gold ring around it (class colour in Everyone mode), a soft pulsing glow, and a short comet trail of fading dots behind it.
- **Smooth round edges everywhere:** every portrait, icon and pin gets a circle mask (`CreateMaskTexture` with `TempPortraitAlphaMask`, as `Modules/NodePins.lua` does), never a trimmed square. This replaces the texcoord trim the hearth and skull pins use today.

*Ways you travelled (recorder marks)*
| Trigger | Effect | Icon | Sound |
|---|---|---|---|
| Flight take-off (F) | Head lifts and grows; the dotted flight line draws dot by dot | Gryphon (Alliance) / wind rider (Horde), round frame | Gryphon wing flaps |
| Flight landing (f) | Dust puff (`FX_Dust`); head settles with a small bounce | Same mount | Soft landing thump |
| Boat ride (b) | Dashed line; head bobs on waves; bubbles (`FX_Bubbles`) at both docks | Anchor | Ship's bell, then waves |
| Zeppelin ride (new mark z) | Dashed line; head sways gently | Zeppelin | Engine hum |
| Hearthstone (h) | Blue rune flash where you left; light pillar and sparkles where you arrived | Hearthstone | Hearthstone cast sound |
| Dungeon in / out (i) | Portal swirl spins up, head shrinks into it (grows back coming out) | Portal swirl | Portal whoosh |
| Death (d) | Small map shake, red ripple, head turns grey | Skull | Low drum hit |
| Ghost run (g) | Faint pale-blue line; head becomes a see-through spirit | Wisp | Soft spirit wind |
| Resurrected (worked out: g followed by a plain point) | Burst of light (`FX_Reincarnation`); colour returns | Ankh | Resurrection chime |
| A jump nothing explains | Purple flash and sparkles at both ends | Portal swirl | Arcane teleport |
| First visit to a zone (worked out) | The zone's name fades in over the map, like the game's zone text | - | Discovery chime |
| New day / gap over 2 hours (worked out) | Line fades out, next stretch fades in like dawn | Sun / moon | - |

- Zeppelin vs boat: the recorder can't tell them apart today; Travel's ride knows the dock it left from, so the recorder writes a new mark `z` for zeppelins. Resurrected, first visit and new day need no recording.

*Discoveries passed during playback (by toast tier)*
- Common (creatures, merchants, people, nodes): the dot pops with a small ring ripple. Silent.
- Uncommon (quests, new items, flight paths): pop, and the kind's icon floats up and fades. Soft chime.
- Rare (new zones, dungeons, every 10th level, Studied): ring burst in the tier colour, brighter icon. Clearer chime.
- Epic (epic items, Mastered): sparkle burst and a short glow over the map. Quest-complete sound.
- Legendary (level 60, the biggest milestones): a column of golden light, fanfare, the head flashes.

*Playback*
| Trigger | Effect | Sound |
|---|---|---|
| Play | Map fades in from parchment | Page turn |
| Zone change (full-size tab only) | Map cross-fades to follow the head | Map open |
| Scrub slider | Effects skipped while dragging; head jumps to the spot | Faint tick |
| Speed button 1x / 2x / 4x | Button flashes | Click |
| Legend name clicked | That character's line fades out / in | Checkbox click |
| Playback ends | Three gold ripples, then a summary line (zones, flights, deaths, discoveries) | Closing chord |
| Hover a pin | Pin grows and glows; tooltip with the time | - |

*Rules*
- At most one sound every 0.4 s; when triggers coincide, the bigger tier wins.
- At 4x, only Rare and above play sounds.
- Settings: "Journey sounds" (on / off) and "Journey effects" (full / light / off); sound also follows the toasts' sound setting.
- Exact sounds are picked by ear: `/aa journey sounds` plays each candidate before they're fixed in the code.

## 75. Requests of 2026-10-08 (plans for approval) [ ]
Fifteen requests (issues 31 to 45); each one's plan, art prompts and open questions are in `docs/PLANS_2026-10-08.md`. Decided with Shannon 2026-10-08:
- [x] The Journal's new top-right pane shows the Journey (section 74, issue 30).
- [x] The People tab for trainers is called **Training**; it replaces the "What they teach" badge.
- [x] Dungeon names in the **LifeCraft** font (dafont, donationware, Eliot Truelove), rendered gold and bevelled to textures by `tools/wordart.py`; the font file is not shipped; credit in `Licenses/LifeCraft.txt`. Sample: `docs/art_source/WordArt_Sample.png`.
- [x] **New** = found since you last opened that tab (stamped when you leave it); a count badge on each side tab.
- [x] No separate class-spell list: class, weapon and riding spells show only on each trainer's Training tab, only what that trainer teaches. Spells & Recipes becomes Recipes.
- [x] Lockpicking follows **Almanac shows** (character: rogues only; account: everyone when a rogue is on the account).
- [x] Raids' word-art names in a deeper red-gold; dungeons in bright gold.
- [x] Lockpicking gets research tiers and toasts, counted like gathering.
- [x] People: no tabs. The General block goes: roles join the title line, place without coordinates, faction as a crest on the portrait ring, first met / also met by (and merchant standing, visits, stock checked) in the portrait's tooltip. Below: Training, then For sale, in the same two-column slots.
- [x] Toasts: item, research-tier and milestone toasts keep their own icons; the rest use the painted page art.
- [?] Built (Unreleased, 2026-10-08): #38 New marks (UI/NewMarks.lua): the page's "last looked" time (db.newSeen[page]) is stamped when you leave the page or close the window; the first time a page is asked about it starts at that moment (nothing new on first use); a person is new by their first meeting in any role; a new zone stays in the Places tree too (it holds its places), a new place leaves its zone's list; clicked New rows stop glowing for the session.
- [?] Built (Unreleased, 2026-10-08): #34 / #39 painted art: `W.KIND[kind].art` names a `Media\Tab_*` painting, `W.KindArt(kind)` returns it (the game icon when a kind has none); toasts, Journal rows, entry details and the Overview's Discoveries use it, and `W.SetArtCoord` shows painted art whole (game icons keep their 8% trim). Item, tier and milestone icons unchanged. The Icon_Merchant / Training / Flight / Fishing / Level art from #43 only needs the `art` names changed.
- [?] Built (Unreleased, 2026-10-08): #40 profession cards: the card is the button (hover highlight, tooltip; no hand cursor); `page:ShowOnly(group)` on Gathering ("herb", "ore", "chest", "fish", "skin") and Recipes ("skill:<name>"); the list's new `ScrollTop()`. Lockpicking joins with #37.
- [?] Built (Unreleased, 2026-10-08): #31 to #33 dungeon cards: `tools/wordart.py` (LifeCraft, 60 px, thicker outline for small use) writes `Media\DungeonNames_1.tga` and `Data\DungeonNames.lua`; `W.NameArt` / `W.SetNameArt(tex, name, maxW, maxH)`; `W.NamePlate` (drawn stand-in for #32's art); `art_convert.py parchment` -> `Media\Card_Parchment.tga`; the card's side rim 0.035 -> 0.05 of the width to show it (the arch overlaps it at the top, as the gem does on the creature cards).
- [?] Built (Unreleased, 2026-10-08): #45 portal swirl: `W.PortalSwirl(frame, layer, sublevel)` (SetWanted 0 / 1 / 1.25, Step from the owner's OnUpdate; rotation one turn in 6 s, fade about 0.2 s), on every `W.DungeonCard` (BORDER 3: over the scene, under the stone) and behind the Dungeons page's name; `Dungeons:Current()` (the open run, else GetInstanceInfo), read twice a second by `W.CurrentDungeon()`. Setting `window.portalSwirl`.
- [?] Built (Unreleased, 2026-10-08): Journal rearranged (Shannon, 2026-10-08): overview left (330 px, `W.Detail` painted, slots two to a row), Journey top right (300), the list bottom right. Cards = journal kinds present (`CARDS`), `page:SetKind(k)` filters the list (again: all); tooltips from `EntryTooltip` (replaces the entry details view), clicks through `OpenEntry` (Subject's onClick; level -> Characters; milestone none), hover focuses the Journey (back after 0.35 s off the list). Decided with Shannon: default list = everything; hover lights the map; Journey 360 -> 300; left keeps Research, Milestones, First to find; Recent discoveries dropped.
- [?] Built (Unreleased, 2026-10-08): abandoned dungeon cards: `Card_Ruin` over the arch (ARTWORK 1), the scene's vertex colour 0.9 / 0.86 / 0.8, distressed word art, stained parchment. One card per dungeon: `Found()` drops a seeded or negative-key record when a real record has the same `Dungeons.NameKey`; `Dungeons:Entries` and `W.NameArt` look names up by NameKey too.
- [?] Built (Unreleased, 2026-10-08): dungeon card edges: `UI/DungeonCard.lua` SIDE 0.012 (the arch art has a 2.7% clear margin, so its stone overlaps the 5% border), BOTTOM 0.036, RIM_TOP 0.004, the flat parchment inset 3% (only behind the arch, so the worn edge is see-through), one `Card_Shadow` texture (pad 0.08, offset 3, -5) replacing the two box shadows. Wild Gambit's event card: border 2.6% out, the same shadow.
- [?] Built (Unreleased, 2026-10-08): flight art by faction: `W.KIND.flight.artByFaction` (Alliance = Icon_Flight_Gryphon, Horde = Icon_Flight_WindRider), read by `W.KindArt` from UnitFactionGroup("player") when shown (toasts now ask KindArt at show time, not at load).
- [x] Tried and set aside (2026-10-08): flight art read off the client's action bar end cap (`MainActionBar.EndCaps.*EndCap.Texture`, Blizzard_ActionBar/Camelot/MainMenuBarEndCaps.xml; `W.EndCapArt()`, and `W.SetTex` for specs, kept). At icon size it looked poor; flights stay on the Places painting until a painted `Icon_Flight` (or the per-faction mounts) arrives.
- [x] Decided 2026-10-08: "Mark all seen" on the New header (`ns.New:HeaderButton`, called by `W.List` for every row); gathering journal entries show the node's own item (`Gathering:TopItem` / `NodeIcon`, moved from the page); lockpicking only for things with loot, no doors.
- [?] Built (Unreleased, 2026-10-08): section 74 recorder: `Modules/JourneyRecorder.lua`. Every 5 s, a point once you've moved 15 yards (UnitPosition; 0.4 map percent when the game won't give it) or at once on a map change; `ns.db.trail[char][day]` = "dt:map:x:y[:k];" (k: F take-off, f landing, b boat or zeppelin from Travel's ride, h hearth (spell 8690), i instance in / out, d death, g ghost). Days older than 7 thinned once (every third plain point; marks kept; `db.trailThinned`). `JR:Points(from, char)` feeds `ns.Journey.Points`, merged with the journal's points (the clickable dots). Line breaks at f / h / i and the graveyard after a death; a gap the marks don't explain gets the swirl at both ends. Setting `window.journey`. Decided by default (open questions in 74): flights as pins only, a hearth pin of its own, markers from the journal kept as the dots.
- [?] Built (Unreleased, 2026-10-08): #35 Journal panes: `UI/Journey.lua` (`W.JourneyPane`, `ns.Journey.Points(from, char)` the one reader of positions, so the recorder (section 74) only has to feed it). Plan questions settled by default, to revisit: the time lapse plays every time the Journal opens (8 s in the pane); the Overview stays in the bottom pane; Week / Month are the last 7 / 30 days; "Larger" fills the Journal's right side until a Journey tab exists on Characters. Not yet: the recorder, jump pins (boats, flights, portals), scrubbing and speed, the legend of names.
- [?] Built (Unreleased, 2026-10-08): #36 / #37 locks: `tools/build_items.py` takes the client's `Lock.dbc` as a third argument (VMaNGOS doesn't ship client tables; the 3.3.5 file from github.com/Torrer/TrinityCore-3.3.5-data has the same Classic lock IDs and levels, checked against Peacebloom 1, Mageroyal 50, Iron Deposit 125, Black Lotus 300, the lockboxes 1 / 25 / 70 / 125 / 175 / 225) and writes `ns.DB.objectLock[object] = { skill, level }` (138 objects: 53 herbs, 43 veins, 42 locked chests) and `ns.DB.itemLock[item] = level` (24 lockboxes); the rest of `Data\Items.lua` rebuilt byte-identical. `Gathering:Needs(rec)` (object IDs, then by name, a game-tooltip `rec.need` wins), `NeedText`, `NeedColor` (red / orange +25 / yellow +50 / green +100 / grey), `LockRogue` (who sees and colours locks), `CharSkill(skill, key)` (saved ranks; the live `SkillRank(name)` is unchanged). Lockpicking is read with the skills (Trainers and the Professions scan, skill 633) under any heading. Pick Lock: UNIT_SPELLCAST_SUCCEEDED on the soft-interact chest (`rec.picked`, `pc[char]`, `pickSkill`, ranks and toasts by picks as `PickTier`), UNIT_SPELLCAST_FAILED with the skill below the level (`rec.hard[char]`). Not done: lockbox picks (only the contents, on the item page), doors (the question in the plan stays open).
- [?] Built (Unreleased, 2026-10-08): #41 Recipes (page key stays "trainers"; a class spell's link goes to the trainer who teaches it, the one checked most recently) and #42 People (name plate, portrait tooltip, Training, For sale). Coordinates left out of the portrait tooltip too. Recipes and Training sort recipes by skill, spells by level.

## 78. Creatures page: category cards (agreed with Shannon 2026-10-09) [ ]
The Creatures page's left pane gets the Journal's card overview (Asia's fading-icon cards, section 77). The right pane and the detail pane stay as they are.

**Views**
- **Cards** (the new default) and **List**, switched at the top of the left pane; the choice is remembered.
- The header's Tier, Type and Zone dropdowns are **removed**: the cards replace them.
- **Show all**: a card (first) that opens the full list with search, every creature.
- Picking a category card opens the list with that filter, under a title line with the painted back arrow (`Media\Back_Arrow`): "← Creatures › Beasts". Back clears the filter and returns to the cards. A list opened with the switch or Show all is the plain list, no back arrow.
- Typing in search from the card view jumps to the full list, searching every creature.
- Links from other pages (the Journal's research cards, `page:ShowTier`, `page:ShowCreature`) land in the list with that filter and the back arrow, not on the cards.
- The right pane keeps the last creature picked while you browse the cards.

**Card sets** (each under a banner, as on the Journal; each card shows its count and a green +N for creatures new since you last looked)
1. **Creature Mastery**: one card per research tier you have reached, its tier icon and name (e.g. the Legendary Hunter icon, "Legendary Hunter"); Asia's fading-icon look, two to a row. Tiers you haven't reached have no card (natural discovery). The count is creatures currently at that tier, not "this tier or better", so nothing reads as a completion score.
2. **Creature Types**: one card per type you've met (Beast, Humanoid, Undead ...), two to a row. Background: the type's painted Wild Gambit creature scene (the glade for beasts, the crypt for undead ...), in the same merged art-and-name style as the zone cards.
3. **Zones**: one card per zone where you've met a creature (`rec.z`); a creature living in several zones counts in each. Full-width banners, one to a row: the zone's own world-map art as the background (the art the page's map draws, dimmed and slightly blurred so it reads as an old map), the zone's name written on it in Morpheus, gold, with a thick outline and drop shadow standing in for bold (the client has no bold Morpheus). Icon and text are merged into the art: no separate icon.
   - Grouped under each continent with fold / unfold headings, and Fold all / Unfold all.
   - Your current zone first, marked "You are here".
   - Dungeons in their own group, using the dungeon card art.
- Every card: hover highlight, the "New" count, tooltip with what clicking does.

**Bug found the same day: detail pane jumps back to the top** (Creatures, likely Quests, Dungeons, Trainers)
- Cause: these pages redraw the shown entry when item names arrive from the server (`GET_ITEM_INFO_RECEIVED`, constant while loot information loads) through their own handler, outside `UI.refreshing`, so `SetBlocks` resets the scroll.
- Fix: the detail pane keeps its scroll whenever the same entry is redrawn; it returns to the top only when a different entry is picked. Done once in the shared pane (`W.Detail`'s `SetBlocks`), so all pages are covered. Ships on its own ahead of the redesign.

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

## Decisions (2026-10-07)
- Items: hovering a link someone posts in chat does **not** count as discovering the item.
- The Combat Journal companion is dropped (section 2b).
- Toasts: the journal-entry badge (docs/art_source/Badge_Journal.png) overlaps the toast's top-right corner like a seal, on every toast that writes a journal entry; the "Almanac" word tag goes.
- The Almanac's logo is the closed crimson compass-rose journal (docs/art_source/Logo_Almanac.png), replacing the game's red book icon everywhere.
- Rares: rares and rare elites use the boss research tier counts (kills for Studied / Mastered / Revered / Exalted: 1 / 3 / 10 / 40; B.TIER_KILLS.rare), as built since data version 3.

## Open questions
- Which open-source Classic server database to use (license and how close it is to Forever); add a `Licenses\` folder as Plus Everything has.
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

## 76. Follow button: footsteps (2026-10-07, Asia)

- **Look.** A pair of gold footprints (`Media/Follow_Footsteps.tga`, 64 x 64, source in `docs/art_source/`), no frame or background. The old framed spell icons stay as choices (Settings > Follow button > Icon). A saved winged boot, the old default, becomes the footsteps once (`db.follow.iconV`).
- **Aura.** Two ADD-blended glow textures behind the prints (gold), breathing slowly, on for as long as you follow anyone: it follows the game's `AUTOFOLLOW_BEGIN` / `AUTOFOLLOW_END` events (the name comes from the event, else the target at that moment) and clears on `PLAYER_ENTERING_WORLD`. It is not tied to the current target. The game's own "Following X." lines come from the plain `/follow` macro the button runs.
- **Clicks.** The target frame takes the mouse wherever it overlaps a button on the same LOW strata, whatever the frame levels (found with a mouse-focus watcher), so the button is on MEDIUM, level 2: above the target frame, under windows (the Almanac, the games, the bags). Stretching a button's click area with negative hit-rect insets did not work (the middle was handed to the target frame); the button is instead a real frame about 1.3 times the prints each way (`FB.HIT_GROW`, 0.15).
