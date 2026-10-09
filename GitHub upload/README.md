# Azeroth Almanac

A discovery addon for **WoW Forever** (interface 16001). It records what your characters meet in the world — creatures, items, quests, merchants, trainers, townsfolk, flight paths, zones, dungeons, herbs, veins and fishing waters — and turns it into an adventurer's journal that grows as you explore.

There are no completion percentages and no "x of y" totals. Progress is what you've found: running counts, research tiers per creature and node, milestones from your own discoveries, and a timeline of everything you've seen.

Slash command: `/aa` · Saved variables: `AzerothAlmanacDB` (account-wide)

## Install

Copy the `AzerothAlmanac` folder into `World of Warcraft\_classic_beta_\Interface\AddOns\` and log in. Adding new files needs a full relog; edits only need `/reload`.

## What's in it

| Page | What it holds |
|---|---|
| Journal | Timeline of discoveries by day, filters by character / kind / zone, and the Overview: catalogue counts, research, milestones, recent finds, who found what first |
| Bestiary | Creatures you've met: research tiers (Sighted → Fought → Studied → Mastered), abilities, loot, kill and sighting spots on the map |
| Items | Everything looted, bought, received or carried, with where it came from |
| Quests | Quests offered and completed, objectives, rewards, givers |
| Merchants | Vendors visited with their full stock and prices |
| Trainers | Class and profession trainers, spells and recipes as each character sees them |
| Townsfolk | Trainers, innkeepers, bankers, flight masters, vendors, quest givers — and every flight path your characters know |
| Places | Zones, places within them and dungeons, with an in-page map |
| Gathering | Herbs, ore, chests, fishing by zone and skinning; gathered and sighted spots on the world map and minimap |
| Dungeons | Dungeons and raids found, bosses and loot as you meet them |
| Characters | Every character on the account |

Also included, ported from Plus Everything (same author): quest targeter, gathering highlight, auction prices, crafting profits, disenchant values, merchant helpers, flight timers, Wings & Whispers, My Characters (bags and bank across characters), group tools, Healer Assist, Gem Match, and the Spell Ranker (old spell ranks on your bars, replaced automatically when you train a new rank). Everything is configured in `/aa settings`.

## Data rules

- **Natural discovery.** Nothing is shown before you've met it in your own game.
- **Hidden databases.** Classic records built from VMaNGOS (and AtlasLoot Revival for dungeon loot and boss map spots) ship with the addon, but a record only fills in once evidence or a research tier unlocks it.
- No Wowhead or Questie data.

## Repository layout

```
AzerothAlmanac/   the addon (copy this into Interface\AddOns)
tools/            Python build scripts for the hidden databases (Data\*.lua) from the VMaNGOS world database
docs/DESIGN.md    design record: ground rules, research and each feature's agreed design
docs/ROADMAP.md   how work is tracked (GitHub Issues + project board) and what's next
docs/TEST_CHECKLIST.md   everything that still needs confirming in game
CHANGELOG.md      what changed in each version
docs/ArtCatalogue.md   every game atlas, font and layout recorded in game with /aa artlog
dev/AlmanacProbe/ the early API probe addon (development only)
STATUS.md         where the project stands
```

## License

Azeroth Almanac is released under the GNU General Public License, version 2 (`LICENSE`). Its hidden databases are derived from the VMaNGOS world database (GPL-2.0) and AtlasLoot Revival (MIT); their notices are in `AzerothAlmanac/Licenses/`.
