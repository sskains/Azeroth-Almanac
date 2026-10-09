# Roadmap and how we track work

**GitHub Issues are the task list.** One issue per piece of work, with an owner, and a project board that shows where everything stands. This file is the overview; the issues hold the details and discussion.

## Where things live

| What | Where |
|---|---|
| What to do next, who has it, what's in progress | GitHub Issues + the **Azeroth Almanac** project board |
| What still needs checking in game | `docs/TEST_CHECKLIST.md` (one issue tracks the test pass) |
| What changed in each version | `CHANGELOG.md` (newest first) |
| Why things are designed the way they are | `docs/DESIGN.md` (ground rules, research, feature designs) |
| Current version, what's built, known open points | `STATUS.md` |
| How we work together (branches, ownership, releases) | `CONTRIBUTING.md` |

## The board

Columns, left to right:

1. **To do**: agreed, not started. Ordered by priority, top first.
2. **In progress**: someone is on it. It must have an assignee and a branch.
3. **Needs testing**: built and merged to `main`; waiting for an in-game check.
4. **Done**: confirmed in game.

Plus a **Parked** list (label `parked`) for ideas we've agreed to come back to later.

Rules:
- Pick up work by assigning yourself and moving the card to In progress, *before* starting, so two people never take the same thing.
- One branch per issue. Mention the issue in the pull request (`Closes #12`), and GitHub links them.
- A bug found while testing gets its own issue, labelled `bug`.

## Labels

| Label | For |
|---|---|
| `wild-gambit` | The card game |
| `almanac` | The catalogue pages (Bestiary, Items, Quests, Places ...) |
| `qol` | Quality-of-life helpers (settings, auction house, Spell Ranker, Talent Planner ...) |
| `data` | Hidden databases and build tools |
| `feature` · `bug` · `testing` · `art` · `decision` · `chore` | Kind of work |
| `parked` | Agreed for later |

## Now (updated 2026-10-07, version 0.64.1)

- **In-game test pass of 0.62.0 - 0.64.1** (`docs/TEST_CHECKLIST.md`, top batches first): the review fixes are built but untested. Highest risk: Wild Gambit player matches (protocol 11, the pick cap, cancelled-game banner, timeouts), Wild Gambit looking the same after the old game-art board / card ornaments were removed (0.64.0), settings profiles (whitelist, 0.63.0), Healer Assist in combat, NPC interact nameplates hidden (0.64.1).
- **GitHub sync**: Shannon's 0.53 - 0.64.1 work is in Claude's working copy and the AddOns folder; it goes to `D:\GitHub\Azeroth-Almanac` when the Asia merge is started in GitHub Desktop. Delete there: `docs/TASKS.md`, `Media/Board_DarkPortal.tga`, `UI/Pages/Placeholders.lua`.
- **Create the GitHub issues** from `docs/ISSUES_TO_CREATE.md` (if not done yet), then delete that file.
- **Wild Gambit polish** from test results (owner: Shannon).
- **Journal-entry badge on the toasts** (art saved: `docs/art_source/Badge_Journal.png`): overlapping the corner like a seal, on every toast that writes a journal entry; replaces the "Almanac" tag (issue 24).
- **New Almanac logo everywhere** (art saved: `docs/art_source/Logo_Almanac.png`): replaces the game's red book icon in the AddOns list, minimap button, window, settings, toasts and tooltips (issue 25).
- **Bug: Characters page portraits** too small inside their rings (zoom the face or thin the ring; issue 23).

## Next

- **Dungeons page redesign** (added 2026-10-08, DESIGN section 73): a collection of dungeon cards, then each dungeon's map with clickable boss portraits and tabs for abilities, loot and more (issue 29).
- **Healer Assist with hidden health** (added 2026-10-08): probe whether health is secret on WoW Forever; if so, base the danger edge and greying on what the client allows (issue 28).

- **Wild Gambit dungeon cards** (designed 2026-10-07, DESIGN section 72): a rare dungeon card dealt in place of a card, played onto the board as a neutral square with the dungeon's own effect (issue 27). First: the journal art scan and the effects review.

- **Quest kill credit for dungeon kills** (added 2026-10-07): a quest's kill progress counts the kill for its target creature, so kills nobody's Almanac looted still count (issue 26).

- **People page redesign** (added 2026-10-07): the detail panel and its sub-panel show what this person can teach or sell you; facts about the person move to the name plate panel or a tab of their own.
- **Spells & Recipes becomes Professions** (added 2026-10-07): a tree of every recipe you've come across, by profession and specialisation, showing which you've learned and which you've found but not yet got.
- Dark Portal board, returning with new art.
- Remaining art: Tutor portrait; Murloc Tac Toe and Gem Match logos for the flight prompt.
- Probe leftovers: level-up, death and the damage meter's Deaths view, a real interrupt, the active world event.
- Travels: your trail on the map (design done, draw test passed).

## Later

Lore and books · Rares · Factions · Places and services · Character stories · More on items · World events · Data plumbing (Forever cache overlay, saved-data caps and migrations, localization).

## Parked

Rivals: PvP encounters.

## Owners

- **Shannon**: Wild Gambit (`QoL/WildGambit*.lua`, its art, its Settings section), releases and version numbers.
- **Asia**: add your areas here.
