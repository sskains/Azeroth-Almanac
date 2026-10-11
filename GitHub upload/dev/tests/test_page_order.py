"""The pages' order on the window's tabs and the minimap menu. Run: python3 dev/tests/test_page_order.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player, ALL_FILES

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

def spy(name, src):
    if name == "UI/Window.lua":
        src = src.replace("local frame, pages, order, current = nil, {}, {}, nil", "local frame, pages, order, current = nil, {}, {}, nil\nTAB_ORDER = order")
    if name == "UI/MinimapButton.lua":
        src = src.replace("local function MenuItems()", "function MenuItems()")
    return src

WANT = ["journal", "characters", "places", "dungeons", "quests", "townsfolk", "bestiary", "items", "gathering", "trainers"]
p = Player("Alice", files=ALL_FILES, patch=spy)
p.lua("""
AzerothAlmanacDB = false
FireEvent("ADDON_LOADED", "AzerothAlmanac")
FireEvent("PLAYER_LOGIN")
RunTimers(5)
TABS = {}
for _, d in ipairs(TAB_ORDER) do TABS[#TABS + 1] = d.key end
TABS = table.concat(TABS, " ")
local opened = {}
local real = A.UI.Open
A.UI.Open = function(_, key) opened[#opened + 1] = key end
for _, it in ipairs(MenuItems()) do if it.run and not it.section and #opened < 10 then it.run() end end
A.UI.Open = real
MENU = table.concat(opened, " ", 1, math.min(#opened, 10))
""")
check(p.eval("TABS") == " ".join(WANT), "window tabs: " + p.eval("TABS"))
check(p.eval("MENU") == " ".join(WANT), "minimap menu: " + p.eval("MENU"))
print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
