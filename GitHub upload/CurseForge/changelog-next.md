# Azeroth Almanac 1.5.2: what's new

Paste this into the "Changelog" box when uploading. It is written for players; the developer detail is in
`CHANGELOG.md` under 1.5.2.

Needs a **full game restart**, not just `/reload`: this update adds three new files (`QoL/BagPins.lua`,
`QoL/HealerTarget.lua`, `QoL/QuestLogCounts.lua`).

## New

- **Bag pins.** Alt+click an item in your bags to pin it to its slot. The game's Cleanup still sorts everything else, and your pinned items go back where you put them. Alt+click again to unpin.
- **See who the other healers are healing.** In a group with another healer, the person they've selected gets a badge with their name on their unit frame. While their heal is on the way, the frame glows green, so you can heal someone else and no heal is wasted.
- **Tank's target: purple glow and "you're on it".** The outline is now a soft purple glow round the tank's target's health bar (Soft or Strong). When your own target is the tank's, its nameplate and your Target frame glow purple. There's also a new Red glow look. For now it works out in the world but not inside dungeons, where the game doesn't let addons see another player's target. `/aa tank why` explains what it can see.
- **Quest counts by zone.** How many quests you have in each zone, beside the zone's name, both on the Almanac's Quests page and in the game's quest log.
- **Auctions total.** Characters > Auctions shows what all your posted auctions are worth, and what you'd get after the 5% cut.
- **Healer Assist your way.** Reorder or hide spell buttons, change the space between them, nudge the icons beside the portraits and resize the window.
- **Find people by what they sell.** The People search now finds vendors and trainers by their goods: "crusader" finds the blacksmith selling the Crusader's leggings plans. The search box for a person's lists now stays in the top bar while you scroll.
- **Your Deck: a New section.** Wild Gambit's Your Deck page opens with the cards you've earned or that went up a tier since you last looked.
- **Flight countdown.** The take-off card has a proper progress bar with the time left counting down, and the landing card closes when you walk off.

## Fixed and improved

- **Wild Gambit says why a win earned no card.** An enemy's card comes with your first kill of one; a win before that now tells you so (your wins still count). The table picks opponents whose wins count.
- **No more dungeon discoveries popping up days later.** Creatures from a dungeon you visited earlier no longer get announced as new discoveries in an unrelated session.
- **Alt+Right-click to sell matches the lowest live price** again, not an old scan's.
- **Characters > Auctions shows new auctions** right after you post, cancel, or open the Auctions tab.
- **Crafting profit is per item** ("+2.6s ea"), not mixed up with sales per day.
- **Quest Targeter:** no more "blocked from an action" popup when clicking the target button repeatedly in combat, and its badges now line up with the game's quest icons.
- **"XP to level"** on the experience bar moved left so the gryphon no longer covers it.
