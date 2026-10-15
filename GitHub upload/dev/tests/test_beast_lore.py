"""Beast Lore onto the creature card (Shannon, 2026-10-14, DESIGN 119): the lines Beast Lore adds to
the target's tooltip are kept on the creature and shown on its card.
Run: python3 dev/tests/test_beast_lore.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player, ALL_FILES

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

p = Player("Alice", files=ALL_FILES, cls="HUNTER")
p.lua("""
AzerothAlmanacDB = false FireEvent("ADDON_LOADED", "AzerothAlmanac") FireEvent("PLAYER_LOGIN") RunTimers(5)
B = A.Bestiary
GUID = "Creature-0-1-0-1-1135-0000ABCDEF"
UnitGUID = function(u) if u == "target" then return GUID end return "Player-1-00000001" end
UnitName = function(u) if u == "target" then return "Black Bear" end if u == "player" then return "Alice" end end
UnitIsPlayer = function(u) return u == "player" end
UnitPlayerControlled = function() return false end
UnitReaction = function() return 2 end
UnitExists = function(u) return u == "player" or u == "target" end
UnitLevel = function() return 8 end
UnitClassification = function() return "normal" end
UnitCreatureType = function() return "Beast" end
UnitCreatureFamily = function() return "Bear" end
LORE = false
C_TooltipInfo = C_TooltipInfo or {}
C_TooltipInfo.GetUnit = function(u)
	local lines = { { leftText = "Black Bear" }, { leftText = "Level 8 Beast" }, { leftText = "Skinnable" } }
	if LORE then
		lines[#lines + 1] = { leftText = "Diet: Meat, Fish, Fruit" }
		lines[#lines + 1] = { leftText = "Tameable" }
		lines[#lines + 1] = { leftText = "Armor", rightText = "312" }
	end
	return { lines = lines }
end
""")
check(p.eval("A.NpcFromGuid(GUID)") == 1135, "test creature id")
p.lua("""
FireEvent("UNIT_SPELLCAST_SENT", "player", "Black Bear", "Cast-1", 1462)
LORE = true
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 1462)
RunTimers(3)
REC = A.Store:Get("creature", 1135)
""")
check(p.eval("REC ~= nil and REC.lore ~= nil"), "Beast Lore is kept on the creature")
n = p.eval("REC and REC.lore and #REC.lore.lines or 0")
check(n == 3, "just the three new lines (not the name, level or Skinnable) (%d)" % n)
check(p.eval("REC.lore.lines[1][1]") == "Diet: Meat, Fish, Fruit" and p.eval("REC.lore.lines[3][2]") == "312", "...as the game wrote them")

blocks = p.eval("""(function()
	local page = A.UI:GetPage("bestiary")
	local b = page:CreatureBlocks(1135)
	local out = {}
	for _, x in ipairs(b or {}) do out[#out + 1] = tostring(x[1]) .. "|" .. tostring(x[2]) .. "|" .. tostring(x[3]) end
	return table.concat(out, "\\n")
end)()""") or ""
check("banner|Beast Lore" in blocks, "the card has a Beast Lore section")
check("stat|Diet|Meat, Fish, Fruit" in blocks, "...Diet: as a stat line")
check("small|Tameable" in blocks and "stat|Armor|312" in blocks, "...Tameable and Armor too")

p.lua("""
LORE = false
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 133)
RunTimers(3)
""")
check(p.eval("#REC.lore.lines") == 3, "other spells don't touch it")

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
