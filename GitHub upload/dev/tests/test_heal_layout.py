"""Healer Assist, your layout (2026-11-11): the spell buttons in your order and any hidden (a hidden spell isn't
suggested either), the icons beside the portraits nudged, the window's size, the space between icons.
Run: python3 dev/tests/test_heal_layout.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player, ALL_FILES

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

p = Player("Alice", files=ALL_FILES, cls="PRIEST")
p.lua("""
-- a priest's spellbook: four of the catalog's spells
Enum.SpellBookItemType = { Spell = 1 }
Enum.SpellBookSpellBank = { Player = 0 }
BOOK = { { 2050, "Lesser Heal" }, { 139, "Renew" }, { 17, "Power Word: Shield" }, { 527, "Dispel Magic" } }
C_SpellBook = {
  GetNumSpellBookSkillLines = function() return 1 end,
  GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #BOOK } end,
  GetSpellBookItemInfo = function(i) local s = BOOK[i] return s and { itemType = 1, spellID = s[1], name = s[2] } end,
}
UnitClass = function() return "Priest", "PRIEST", 5 end
AzerothAlmanacDB = false FireEvent("ADDON_LOADED", "AzerothAlmanac") FireEvent("PLAYER_LOGIN") RunTimers(5)
HA = A.QoL.HealAssist
db = A.QoL.db.healAssist
HA:Apply()
function Names(list, key) local out = {} for i, x in ipairs(list) do out[i] = key and x[key] or x.spell.name end return table.concat(out, ",") end
""")
check(p.eval("db.offsetX") == 0 and p.eval("db.panelScale") == 100 and p.eval("db.gap") == 2, "defaults: no nudge, the window at 100%, 2 px between icons")
check(p.eval("Names(HA:SpellList(), 'name')") == "Lesser Heal,Renew,Power Word: Shield,Dispel Magic", "the spells known, in the catalog's order (%s)" % p.eval("Names(HA:SpellList(), 'name')"))

# reorder
p.lua('OK = HA:MoveSpell("Dispel Magic", -1)')
check(p.eval("OK") and p.eval("Names(HA:SpellList(), 'name')") == "Lesser Heal,Renew,Dispel Magic,Power Word: Shield", "Up: Dispel Magic one place earlier")
check(p.eval("Names(HA.Mine())") == "Lesser Heal,Renew,Dispel Magic,Power Word: Shield", "...and the buttons follow that order")
check(p.eval('HA:MoveSpell("Lesser Heal", -1)') is False, "the first can't go further up")
p.lua('HA:MoveSpell("Lesser Heal", 1)')
check(p.eval("Names(HA:SpellList(), 'name')") == "Renew,Lesser Heal,Dispel Magic,Power Word: Shield", "Down: Lesser Heal one place later")
check(p.eval("db.spellOrder[1]") == "Renew", "the whole order is saved")

# hide
p.lua('HA:ShowSpell("Renew", false)')
check("Renew" not in p.eval("Names(HA.Mine())"), "a hidden spell has no button, and isn't suggested (it's out of the list the picks come from)")
check(p.eval("(function() for _, s in ipairs(HA:SpellList()) do if s.name == 'Renew' then return s.shown end end end)()") is False, "...but Settings still lists it, unticked")
p.lua('HA:ShowSpell("Renew", true)')
check(p.eval("Names(HA.Mine())").startswith("Renew"), "ticked again: back in its place")
p.lua("HA:ResetSpells()")
check(p.eval("Names(HA.Mine())") == "Lesser Heal,Renew,Power Word: Shield,Dispel Magic" and p.eval("db.spellOrder") is None, "Reset order: the catalog's order, nothing hidden")

# placing: nudge beside the portraits, the window's size, the gap
p.lua("""
PLACED = {}
local function Btn(name, kind)
  local b = CreateFrame("Button") b.m = { spell = { kind = kind } }
  b.SetPoint = function(_, _, _, _, x, y) PLACED[name] = { x = x, y = y, scale = b._scale } end
  b.SetScale = function(_, s) b._scale = s end
  return b
end
E = { order = { "A", "B" }, buttons = { A = Btn("A", "heal"), B = Btn("B", "heal") } }
ANCHOR = CreateFrame("Frame")
db.iconSize, db.perRow = 24, 6
""")
p.lua("HA.Strip(E, ANCHOR, 'below', 4, -2)")
check(p.eval("PLACED.A.x") == 4 and p.eval("PLACED.B.x") == 4 + 24 + 2, "beside the portraits, as before: 2 px between icons")
p.lua("db.offsetX, db.offsetY = 30, -10 HA.Strip(E, ANCHOR, 'below', 4, -2)")
check(p.eval("PLACED.A.x") == 34 and p.eval("PLACED.A.y") == -12, "nudged: 30 px right, 10 px down")
p.lua("db.gap = 6 HA.Strip(E, ANCHOR, 'right', 4, -2)")
check(p.eval("PLACED.B.x") - p.eval("PLACED.A.x") == 24 + 6, "Space between icons: 6 px")
check(p.eval("PLACED.A.scale") == 1, "beside the portraits the icons stay at full size")
p.lua("db.panelScale = 80 HA.Strip(E, ANCHOR, 'inside', 150, -26)")
check(p.eval("PLACED.A.x") == 150 and p.eval("PLACED.A.y") == -26, "in the window: the nudge doesn't apply (the window drags)")
check(abs(p.eval("PLACED.A.scale") - 0.8) < 1e-9, "...and the icons take the window's size (80%)")

p.lua("SOK, SERR = pcall(function() A.QoL.Settings:Open('healer') RunTimers(1) end)")
check(p.eval("SOK"), "the Healer Assist settings page builds, with the spell list (%s)" % p.eval("tostring(SERR)"))
p.lua("RB, RBERR = pcall(function() A.QoL.Settings:RebuildPage('healer') end)")
check(p.eval("RB"), "...and builds again in place after Up / Down (%s)" % p.eval("tostring(RBERR)"))

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
