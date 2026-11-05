"""The Wild Gambit logo on the Creatures page opens your deck, even before Wild Gambit's window has
ever been built (it is built lazily, and ShowDeck used to do nothing without it).
Run: python3 dev/tests/test_creatures_deck_button.py"""
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
    if name == "UI/Pages/Bestiary.lua":
        src = src.replace("gambitBtn:SetActive(true)", "gambitBtn:SetActive(true) GAMBIT_BUTTON = gambitBtn", 1)
    return src

p = Player("Alice", files=ALL_FILES, patch=spy)
p.lua("""
AzerothAlmanacDB = { version = 999, settings = {}, journal = {}, found = {}, chars = {} }
FireEvent("ADDON_LOADED", "AzerothAlmanac") FireEvent("PLAYER_LOGIN") RunTimers(5)
WGM = A.QoL.WildGambit
BEFORE = WGM.D.Frame() ~= nil
local ok, err = pcall(function() A.UI:Open("bestiary") end)
OPEN_OK, OPEN_ERR = ok, tostring(err)
""")
check(p.eval("BEFORE") is False, "Wild Gambit's window has not been built yet (the case that failed)")
check(p.eval("OPEN_OK") is True, "the Creatures page opens (%s)" % p.eval("OPEN_ERR"))
check(p.eval("GAMBIT_BUTTON ~= nil") is True, "the page has the Wild Gambit button")
p.lua("""
local ok, err = pcall(function() GAMBIT_BUTTON:GetScript("OnClick")(GAMBIT_BUTTON) end)
CLICK_OK, CLICK_ERR = ok, tostring(err)
""")
check(p.eval("CLICK_OK") is True, "clicking it runs without error (%s)" % p.eval("CLICK_ERR"))
check(p.eval("WGM.D.Frame() ~= nil") is True, "the click builds Wild Gambit's window")
check(p.eval("WGM.D.Frame():IsShown()") is True, "...and shows it")
check(p.eval("WGM.D.Frame().deckPanel ~= nil and WGM.D.Frame().deckPanel:IsShown()") is True, "...with the deck open on it")
print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
