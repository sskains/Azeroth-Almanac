"""The welcome guide (DESIGN 95), the Progression page and the Dungeons cards' Wild Gambit tooltip.
Run: python3 dev/tests/test_welcome.py"""
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
    if name == "UI/Welcome.lua":
        src = src.replace("local frame, pages, current", "local frame, pages, current\nfunction WELCOME_STATE() return frame, pages, current end")
    return src

def login(p, db="false"):
    p.lua("AzerothAlmanacDB = %s" % db)
    p.lua('FireEvent("ADDON_LOADED", "AzerothAlmanac") FireEvent("PLAYER_LOGIN") RunTimers(10)')

# 1. a brand-new install and character: the guide opens, the helpers start off
p = Player("Newbie", files=ALL_FILES, patch=spy, cls="PRIEST")
login(p)
check(p.eval("A.Welcome:IsShown()") is True, "a new character sees the welcome guide after login")
p.lua("""
local f, pages = WELCOME_STATE()
ERRS = {}
for i = 1, 7 do f.next:GetScript("OnClick")(f.next) end
local n = 0 for _ in pairs(pages) do n = n + 1 end
PAGES = n
local S = A.Settings
REPAIR = S:Control("Repair all my gear") and S:Control("Repair all my gear").get()
THREAT = S:Control("Threat monitor") and S:Control("Threat monitor").get()
HEALER = S:Control("Healer Assist") and S:Control("Healer Assist").get()
MINIMAP = S:Control("Minimap button").get()
ALERTS = S:Control("Show an alert for new discoveries").get()
""")
check(p.eval("PAGES") == 7, "all seven pages build (%s)" % p.eval("PAGES"))
check(p.eval("A.Welcome:IsShown()") is False, "Done on the last page closes it")
check(p.eval("REPAIR") is False and p.eval("THREAT") is False and p.eval("HEALER") is False, "optional helpers start off on a new install")
check(p.eval("MINIMAP") is True and p.eval("ALERTS") is True, "the essentials (minimap button, alerts) stay on")
# a tick in the guide changes the real setting
p.lua("""
A.Welcome:Show(6)
local f, pages = WELCOME_STATE()
for _, t in ipairs(pages[6].ticks) do if not t.get() then t.cb.GetChecked = function() return true end t.cb:GetScript("OnClick")(t.cb) end end
REPAIR2 = A.Settings:Control("Repair all my gear").get()
WELCOMED = A.db.chars[A.CharKey()].welcomed ~= nil
""")
check(p.eval("REPAIR2") is True, "ticking a box in the guide turns the setting on")
check(p.eval("WELCOMED") is True, "the character is marked as welcomed")

# 2. a character the Almanac already knew: no guide, settings untouched
q2 = Player("Veteran", files=ALL_FILES, patch=spy)
q2.lua("""
AzerothAlmanacDB = { version = 999, settings = {}, journal = {}, found = {}, chars = {} }
AzerothAlmanacDB.chars[A.CharKey()] = { name = "Veteran", firstSeen = 1, levels = {} }
FireEvent("ADDON_LOADED", "AzerothAlmanac") FireEvent("PLAYER_LOGIN") RunTimers(10)
REPAIR_V = A.Settings:Control("Repair all my gear") and A.Settings:Control("Repair all my gear").get()
""")
check(q2.eval("A.Welcome:IsShown()") is False, "a character known before doesn't get the guide")
check(q2.eval("REPAIR_V") is not False, "an existing install keeps its settings (repair: %s)" % q2.eval("REPAIR_V"))

# 3. the Progression page builds; the Dungeons card tooltip has the Wild Gambit event
p.lua("""
local ok, err = pcall(function() A.Settings:Open("tiers") end)
PROG_OK, PROG_ERR = ok, tostring(err)
LINES = {}
GameTooltip.AddLine = function(_, t) LINES[#LINES + 1] = tostring(t) end
local c = A.Widgets.DungeonCard(UIParent, 160)
c:SetDungeon(36, { name = "The Deadmines" })
local _, ev = A.Widgets.DungeonArt(36, "The Deadmines")
c.wg = ev
c.tip = { "The Deadmines", "Entered 1 time." }
c:GetScript("OnEnter")(c)
TIP = table.concat(LINES, "\\n")
""")
check(p.eval("PROG_OK") is True, "Settings > Progression builds (%s)" % p.eval("PROG_ERR"))
tip = p.eval("TIP") or ""
check("Van Cleef's Plunder" in tip and "pirated" in tip, "a dungeon card's tooltip names its Wild Gambit event and what it does")
print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
