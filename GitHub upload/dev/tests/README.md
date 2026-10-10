# Offline tests

Lua tests that run outside the game: Python 3 with [lupa](https://pypi.org/project/lupa/) (Lua 5.1, as WoW uses).

```
pip install lupa
python3 "dev/tests/test_wg_pvp.py"
python3 "dev/tests/test_wg_cards.py"
python3 "dev/tests/test_auction_post.py"
python3 "dev/tests/test_wg_resume.py"
python3 "dev/tests/test_items_page.py"
python3 "dev/tests/test_creatures_page.py"
python3 "dev/tests/test_upgrades.py"
```

- `wow_stub.lua`: stand-ins for the WoW client. Every frame method exists and does nothing; unknown CamelCase globals are forgiving stubs; timers run when the test says (`RunTimers(seconds)`); addon messages go to `OUTBOX`; chat lines to `CHAT`.
- `harness.py`: `Player(name)` is one client (its own Lua runtime with the Almanac files loaded in `.toc` order); `deliver(a, b)` carries each one's addon messages to the other. `patch=` edits a file's source as it loads, to stand in for an older copy.
- `wg_setup.lua`: Wild Gambit helpers inside a Player (a fixed card collection, `MyMove()`, `CastSpell()`, `PlayTurn()`, `BoardText()`, `Accept()`).
- `test_wg_pvp.py`: two players' Wild Gambit matches through addon messages: new against new, a copy without the board checksum against a new one, a drifted move (called off on both screens, nothing counted), every class's spell, and protocol ranges (negotiated down to a shared protocol; refused with both sides told when there is none).

- `test_wg_cards.py`: Wild Gambit's earned cards (#54): a card from the first kill, starters, NPC cards from wins (friendly, neutral, enemy), a practice win counted, stronger NPCs, the iron ring on the Creatures page, and the card toast (new, upgrade, held in combat, stacked, off).
- `test_auction_post.py`: Alt+Right-click a bag item at the Auction House (#60): into the slot, whole stack, undercut price (per item or per stack), posting by a second Alt+Right-click or Enter, and when it stays out of the way.
- `test_wg_resume.py`: a Wild Gambit game across a /reload (#50): practice comes back as it was and plays on; a player match asks for the moves it missed (theirs made meanwhile, and its own that never left) and plays to the end; a game that wasn't kept tells the other side at once.
- `test_items_page.py`: the Items page (#55): cards, the tree's branches and folding, a card's filtered tree, search, "Can't use", an item opened from elsewhere.
- `test_creatures_page.py`: the Creatures page's cards draw (smoke test).
- `harness.ALL_FILES` loads the whole addon in .toc order, for page tests.
- `test_upgrades.py`: upgrade arrows (#55 part 2): talents saved, the spec, green for you, "Upgrade at NN", gold for an alt with an unbound copy, soulbound and other-realm cases, rings, two-handers, the Settings override and switch.

Run the tests after any change to Wild Gambit's messages or rules. When a test needs another file, add it to `WG_FILES` in `harness.py` in `.toc` order, and anything the client provides to `wow_stub.lua`.
