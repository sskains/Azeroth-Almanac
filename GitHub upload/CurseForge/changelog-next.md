# Azeroth Almanac: what's new (draft for the next CurseForge file)

Paste this into the "Changelog" box when uploading the next release. It is written for players; the developer
detail is in `CHANGELOG.md` under **Unreleased**, which becomes the version's section when it is released.
Needs a **full game restart**, not just `/reload`: this update adds a new file (`QoL/ItemTips.lua`).

## New

- **Item tooltips: item level and a Journal line.** Gear shows its item level (when the game's own tooltip
  doesn't). A new Journal line tells you how you first found an item ("looted from Defias Pillager", "bought",
  "crafted"), or "not in your journal yet" for an uncommon-or-better item you haven't come across. Both can be
  switched off in /aa settings > Item tooltips.
- **Your Deck, redesigned.** A stats strip (your cards, total power, a count for each tier, your strongest card),
  **Your hand** (the five cards you've starred, on a shelf of their own, with a slot waiting for each one still to
  choose) and your cards in a section for each creature type.
- **Wild Gambit on the Creatures page.** The Wild Gambit logo sits at the top of the Creatures page and opens your
  deck.
- **"Already built in" in the welcome guide.** A new page lists everything the Almanac already does (map arrow,
  every character's bags, auction prices, crafting profit, talent planner, flight timers and more), each one a
  click to its settings. Type `/aa features` to see it any time.
- **Clearer about what runs by itself.** The welcome guide now also shows the switches for sharing flight times and
  auction sales, the keyword auto-invite ("inv") and joining group invites from friends and guildmates. Nothing's
  default changed.

## Fixed

- **Quest Targeter no longer lands on someone else's mob.** It re-checks the nearby mobs on every click and drops
  a target another player has tagged or is fighting ("Skipped Nightsaber: someone else is fighting it."); the next
  click picks another.
- **Wild Gambit result banner.** The win/loss text sits inside the frame instead of running over it.

---

Short version for the "Summary of changes" line (if there is a character limit):

> Item level and Journal lines on item tooltips, a redesigned Your Deck (stats, Your hand, creature-type sections),
> a Wild Gambit button on the Creatures page, an "Already built in" welcome page (/aa features), and Quest Targeter
> now skips mobs other players are fighting. Full game restart needed.
