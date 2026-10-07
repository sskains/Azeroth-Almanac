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

## Now

- **In-game test pass**: work through `docs/TEST_CHECKLIST.md`, Wild Gambit first (the tester build 0.52.1 is out).
- **Wild Gambit polish** from test results (owner: Shannon).

## Next

- Dark Portal board, returning with new art.
- Remaining art: Tutor portrait; Murloc Tac Toe and Gem Match logos for the flight prompt.
- Probe leftovers: level-up, death and the damage meter's Deaths view, a real interrupt, the active world event.
- Travels: your trail on the map (design done, draw test passed).

## Later

Lore and books · Rares · Factions · Places and services · Character stories · More on items · World events · Data plumbing (Forever cache overlay, saved-data caps and migrations, localization) · Combat Journal companion (needs a decision on how it's delivered).

## Parked

Rivals: PvP encounters.

## Owners

- **Shannon**: Wild Gambit (`QoL/WildGambit*.lua`, its art, its Settings section), releases and version numbers.
- **Asia**: add your areas here.
