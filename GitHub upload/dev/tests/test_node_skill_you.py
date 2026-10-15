"""Gathering tooltips show your own skill beside the one a node needs (Shannon, 2026-10-15, DESIGN 120).
Run: python3 dev/tests/test_node_skill_you.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player, ALL_FILES

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

p = Player("Alice", files=ALL_FILES)
p.lua("""
AzerothAlmanacDB = false FireEvent("ADDON_LOADED", "AzerothAlmanac") FireEvent("PLAYER_LOGIN") RunTimers(5)
G = A.Gathering
SKILLS = { { "Professions", true }, { "Herbalism", false, 87 } }
A.NumSkillLines = function() return #SKILLS end
A.SkillLine = function(i) local s = SKILLS[i] return s[1], s[2], s[3], 300 end
""")
check(p.eval("G:YouText(2, 125)") == "  |cffff2020(you: 87)|r", "herb needing 125 with Herbalism 87: red '(you: 87)' (%r)" % p.eval("G:YouText(2, 125)"))
check("ffff00" in p.eval("G:YouText(2, 50)") and "(you: 87)" in p.eval("G:YouText(2, 50)"), "needing 50: yellow")
check("not learned" in p.eval("G:YouText(3, 65)"), "Mining not learned: says so")
check(p.eval("G:YouText(1, 75)") is None, "a lock without Lockpicking: nothing added (only rogues pick)")

p.lua("""
TIP = { lines = { "Peacebloom", "Requires Herbalism (1)" } }
for i, t in ipairs(TIP.lines) do _G["ScanTTextLeft" .. i] = { GetText = function(self) return self.t end, SetText = function(self, v) self.t = v end, t = t } end
TIP.GetName = function() return "ScanT" end
TIP.NumLines = function() return 2 end
TIP.Show = function() TIP.shown = (TIP.shown or 0) + 1 end
""")
p.lua("G.ReadTooltip(TIP)")
check(p.eval("ScanTTextLeft2.t") == "Requires Herbalism (1)  |cff40c040(you: 87)|r", "the game's node tooltip: 'Requires Herbalism (1)  (you: 87)' in green (%r)" % p.eval("ScanTTextLeft2.t"))
check(p.eval("TIP.shown") == 1, "...and the tooltip re-sized")
p.lua("G.ReadTooltip(TIP)")
check(p.eval("ScanTTextLeft2.t").count("you:") == 1, "shown again: added once, not twice")

p.lua("""
TIP2 = { GetName = function() return "ScanU" end, NumLines = function() return 2 end, Show = function() end }
for i, t in ipairs({ "Silverleaf", "Herbalism" }) do _G["ScanUTextLeft" .. i] = { GetText = function(self) return self.t end, SetText = function(self, v) self.t = v end, t = t } end
G.Needs = function(_, rec) if rec and rec.name == "Silverleaf" then return 2, 1, 1 end end
G.ReadTooltip(TIP2)
""")
check(p.eval("ScanUTextLeft2.t") == "Herbalism  |cff40c040(needs 1, you: 87)|r", "Shannon's Silverleaf: the game's plain 'Herbalism' line gets '(needs 1, you: 87)' (%r)" % p.eval("ScanUTextLeft2.t"))

p.lua("""
ScanUTextLeft2.t = "Herbalism"   -- the game rewrites the tooltip while you hover
TIP2.GetUnit = function() return nil end
G.WatchTooltip(TIP2)
""")
check(p.eval("ScanUTextLeft2.t") == "Herbalism  |cff40c040(needs 1, you: 87)|r", "the game rewrites the line: it's put back (%r)" % p.eval("ScanUTextLeft2.t"))
p.lua("G.WatchTooltip(TIP2)")
check(p.eval("ScanUTextLeft2.t").count("you:") == 1, "...and watching again doesn't double it")

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
