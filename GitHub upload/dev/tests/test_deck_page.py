"""The Your Deck page: a stats strip, "Your hand" shelf (the starred cards), then sections by creature
type; a plain grid while searching or filtering. Run: python3 dev/tests/test_deck_page.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player, ALL_FILES

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

def spy(name, src):
    if name == "UI/Settings.lua":
        src = src.replace("if search.Instructions then", "if type(search.Instructions) == \"table\" then")
    if name == "QoL/WildGambitDeck.lua":
        src = src.replace("child = CreateFrame(\"Frame\", nil, scroll)", "child = CreateFrame(\"Frame\", nil, scroll) DECK_SCROLL = scroll", 1)
    return src

p = Player("Alice", files=ALL_FILES, patch=spy)
p.lua("""
AzerothAlmanacDB = { version = 999, settings = {}, journal = {}, found = {}, chars = {} }
FireEvent("ADDON_LOADED", "AzerothAlmanac") FireEvent("PLAYER_LOGIN") RunTimers(5)
WGM = A.QoL.WildGambit
-- a collection of eight creatures of three types
local cards = {}
local kinds = { "Beast", "Beast", "Beast", "Beast", "Humanoid", "Humanoid", "Critter", "Demon" }
local WL = A.QoL.WildLogic
for i, t in ipairs(kinds) do
	local c = WL.Card({ npc = 100 + i, name = "Creature " .. i, level = i, type = t }, 2 + (i % 4))
	cards[#cards + 1] = c
end
WGM.Collection = function() return cards end
FAVS = {}
WGM.Favorites = function() return FAVS end
local ok, err = pcall(function() WGM:Open() WGM:ShowDeck() end)
SHOW_OK, SHOW_ERR = ok, tostring(err)
""")
check(p.eval("SHOW_OK") is True, "the deck opens (%s)" % p.eval("SHOW_ERR"))
kinds = lambda: p.eval("(function() local t = {} for _, b in ipairs(WGM.DeckBlocks()) do t[#t + 1] = b.kind .. (b.type and (':' .. b.type) or '') end return table.concat(t, ',') end)()")
k = kinds()
check(k.startswith("stats,hand,head:Beast"), "stats, then the hand, then the biggest section first (%s)" % k)
check("head:Humanoid" in k and "head:Critter" in k and "head:Demon" in k, "a section for every creature type (%s)" % k)
check(p.eval("(function() local n = 0 for _, b in ipairs(WGM.DeckBlocks()) do if b.kind == 'row' then n = n + #b.items end end return n end)()") == 8, "all eight cards are in the sections when nothing is starred")
# star two: they leave the sections and sit in the hand
p.lua("FAVS[1] = 101 FAVS[2] = 105 WG_REFRESH = WGM.RefreshDeck() ")
check(p.eval("(function() local n = 0 for _, b in ipairs(WGM.DeckBlocks()) do if b.kind == 'row' then n = n + #b.items end end return n end)()") == 6, "two starred cards leave the sections (they are in the hand)")
# give the scroll area a real size so the layout runs for real (the mock reports none)
p.lua("""
DECK_SCROLL.GetWidth = function() return 780 end
DECK_SCROLL.GetHeight = function() return 420 end
DECK_SCROLL.GetVerticalScroll = function() return 0 end
local ok, err = pcall(function() WGM.RefreshDeck() end)
LAYOUT_OK, LAYOUT_ERR = ok, tostring(err)
""")
check(p.eval("LAYOUT_OK") is True, "the stats, hand and section banners lay out without error (%s)" % p.eval("LAYOUT_ERR"))
check(p.eval("WGM.DeckBlocks()[1].kind") == "stats", "unfiltered, the first block is the stats strip")

# (2026-11-13) "New": cards that weren't there (or have gone up a tier) since the page last opened
NEWS = "(function() local n, t = 0, nil for _, b in ipairs(WGM.DeckBlocks()) do if b.new then t = b.n end end return t or 0 end)()"
check(p.eval(NEWS) == 0, "the first visit: no New section (a whole collection isn't new)")
check(p.eval("A.QoL.db.wildGambit.deckSeen[tostring(101)]") is not None, "...and what you hold is remembered")
p.lua("""
WGM:HideDeck()
local cards = WGM.Collection()
local WL = A.QoL.WildLogic
cards[#cards + 1] = WL.Card({ npc = 201, name = "Fresh Wolf", level = 10, type = "Beast" }, 2)
cards[3] = WL.Card({ npc = 103, name = "Creature 3", level = 3, type = "Beast" }, 6)  -- a tier up (it was 5)
""")
p.lua("WGM:ShowDeck() WGM.RefreshDeck()")
k = kinds()
check(k.startswith("stats,head:New,row,hand"), "next visit: New sits at the top, after the stats and before the hand (%s)" % k)
check(p.eval(NEWS) == 2, "...holding the new card and the one a tier up (%s)" % p.eval(NEWS))
p.lua("FAVS[3] = 201 WGM.RefreshDeck()")
check(p.eval(NEWS) == 2, "starring one while you look doesn't make the section vanish")
p.lua("WGM:HideDeck() WGM:ShowDeck() WGM.RefreshDeck()")
check(p.eval(NEWS) == 0, "the visit after: they're not new any more")
p.lua("WGM:HideDeck() WGM.Collection()[#WGM.Collection() + 1] = A.QoL.WildLogic.Card({ npc = 202, name = 'Boar', level = 5, type = 'Beast' }, 2) WGM:ShowDeck() WGM.RefreshDeck()")
p.lua("A.QoL.WildGambit.DECK_TEXT = nil")
p.lua("local ok = pcall(function() WGM.RefreshDeck() end) NEW_LAYOUT_OK = ok")
check(p.eval("NEW_LAYOUT_OK") is True and p.eval(NEWS) == 1, "a New section lays out without error")
print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
