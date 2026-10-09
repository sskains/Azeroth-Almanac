# Contributing to Azeroth Almanac

Two developers work on this addon, each usually with a Claude session. These rules keep our edits from colliding.

## 1. GitHub `main` is the source of truth

- Before starting any work: **Fetch origin**, then **Pull** (GitHub Desktop), or `git pull`.
- Never build on a copy that hasn't been pulled today.
- Claude sessions: start each session with **sskains/Azeroth-Almanac** attached as the repository, and begin from the latest `main`.

## 2. One branch per change

- Name branches for what they do: `wild-gambit-header`, `bestiary-fix`, `art-holiday-boards`.
- Keep them small and short-lived. Merge into `main` through a pull request as soon as the change works.
- Pull `main` into your branch if it lives more than a day.

## 3. Split the work by file

Several files are large, and two people editing one at the same time is the main cause of painful conflicts:

| File | Notes |
|---|---|
| `QoL/WildGambit.lua` (~5,000 lines) | Wild Gambit UI and game flow |
| `QoL/WildGambitLogic.lua` | Wild Gambit rules |
| `UI/Settings.lua`, `UI/Widgets.lua` | Shared by every feature: keep edits small and local |

Say which area you're in before starting, and avoid the other person's files until their branch is merged.

**Current owners:** Shannon's session owns `QoL/WildGambit*.lua`, Wild Gambit art, and `UI/Settings.lua` (Wild Gambit section). Ask before editing those.

## 4. Art can't be merged

- Textures (`AzerothAlmanac/Media/*.tga`) are binary: if two people change one, the last push wins.
- Announce before replacing an existing texture. New art gets a new file name.
- Convert art with `tools/art_convert.py` (32-bit TGA, power-of-two sizes; magenta-keyed or glow-on-black). Keep the source image in `docs/art_source/`.
- A new texture needs a full game restart to load; a replaced one only needs `/reload`.

## 5. Releases and version numbers: Shannon only

- The version lives in three places: `AzerothAlmanac/AzerothAlmanac.toc`, `AzerothAlmanac/Core.lua` (`ns.VERSION`) and `STATUS.md`.
- **Feature branches don't bump the version.** Shannon bumps it once on `main` when releasing, and builds the release zips.
- Every change adds a line to `CHANGELOG.md` under an **Unreleased** heading at the top; Shannon turns that heading into the version number when releasing.
- Anything that needs checking in game goes in `docs/TEST_CHECKLIST.md` under its area.
- Design decisions go in `docs/DESIGN.md` (the old `docs/TASKS.md`; its checkboxes are historical).
- **Mini game protocols** (#59, DESIGN 81): Wild Gambit's `PROTO`, Murloc Tac Toe's `PROTO` and Gem Match's range go up only when the messages between players change, with a CHANGELOG line saying so. When Wild Gambit's goes up, keep `WG.PROTO_MIN` at the oldest protocol whose behaviour is still in the code and tested; list new features in `WG.FEATURE_PROTO`.

## 5b. Tracking work

- GitHub Issues are the task list; the project board shows To do / In progress / Needs testing / Done. See `docs/ROADMAP.md`.
- Assign yourself and move the card to In progress **before** starting, so we never both take the same thing.
- One branch per issue; reference it in the pull request (`Closes #12`).

## 6. Code conventions

- Lua, WoW Forever beta (interface 16001). Addon namespace: `local _, A = ...`; QoL modules use `A.QoL` and `ns:NewModule`.
- Lua's limit is 200 locals per file scope. `WildGambit.lua` is at that limit, so new helpers go in a table or a `do ... end` block.
- A local function used before it's defined must be forward-declared.
- Never assign to the game's own globals. Never call protected functions in combat; check `InCombatLockdown()`.
- Blocked-action reports are logged to SavedVariables (`db.diag`, latest 30) for tracing.
- Keep the UI native-looking: game art and atlases first, custom art in the game's style.

## 7. Testing

- Syntax-check every changed Lua file before committing.
- The offline Wild Gambit tests (game, PvP, hero, lobby, tutorial) run with Python + `lupa` against stubbed WoW APIs; run them after Wild Gambit changes.
- Anything that can only be confirmed in game: say so in the pull request and in `STATUS.md`.

## 8. Commits and pull requests

- One logical change per commit, with a message that says what changed (`0.49.1: holiday board slots aligned`).
- Pull request description: what changed, how it was tested, what still needs an in-game check.
- Merge only after a quick look from the other developer when the change touches shared files.
