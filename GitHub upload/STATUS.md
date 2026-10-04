# Project status

**Version 0.17.0** · 2026-10-04 · WoW Forever beta (interface 16001)

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
| 27 | Gathering nodes on the world map and minimap | 🧪 | 0.16.0 |
| 28 | Bug check and polish pass (22 fixes, loot-card slots, coin art) | 🧪 | 0.16.1 |
| 29 | Spell Ranker (spellbook button, checks on open, auto-replace on training) | 🧪 | 0.17.0 |

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

## Needs checking in game first

- **Art and layout:**
  - Item cards on dark slots: the loot-window card may look squashed at slot height.
  - Coin atlases: fixed at 14 px.
  - Journal painted background: brightness.
  - Small loot-toast frame below Rare: whether the client has it.
- **Positions:**
  - Minimap pin scale: the standard yards per zoom level.
  - Flight paths you aren't standing at: converted from the flight map.
- **Spell Ranker:**
  - Button placement in this client's spellbook.
  - Auto-replace with `PickupSpell` / `PlaceAction` out of combat.
- **Gathering:**
  - Sightings depend on soft-interact targeting, which the gathering highlight turns on.
  - Skill is not recorded when the Professions heading is folded.

## Housekeeping

- `dev/AlmanacProbe` can be removed once nothing needs it.
- The detailed plan, decisions and per-version history live in `docs/TASKS.md`.
