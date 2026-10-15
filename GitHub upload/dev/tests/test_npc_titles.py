"""NPC titles under friendly nameplates (Shannon, 2026-10-15, DESIGN 123): "<Cooking Supplier>".
Run: python3 dev/tests/test_npc_titles.py"""
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
PP = A.QoL.PartyPlates
UNITS = {
	nameplate1 = { guid = "Creature-0-1-0-1-3081-01", reaction = 5, lines = { "Naal Mistrunner", "Cooking Supplier", "Level 40", "Thunder Bluff", "PvP" } },
	nameplate2 = { guid = "Creature-0-1-0-1-3082-02", reaction = 5, lines = { "Thunder Bluff Brave", "Level 55", "Thunder Bluff" } },
	nameplate3 = { guid = "Creature-0-1-0-1-3083-03", reaction = 2, lines = { "Defias Thug", "Defias Brotherhood", "Level 10" } },
	nameplate4 = { guid = "Player-1-0000AAAA", reaction = 5, player = true, lines = { "Bob", "<Some Guild>", "Level 20" } },
}
PLATES = {}
for u in pairs(UNITS) do
	local plate = CreateFrame("Frame")
	plate.namePlateUnitToken = u
	plate.UnitFrame = CreateFrame("Frame")
	plate.UnitFrame.healthBar = CreateFrame("StatusBar")
	PLATES[u] = plate
end
C_NamePlate = C_NamePlate or {}
C_NamePlate.GetNamePlateForUnit = function(u) return PLATES[u] end
C_NamePlate.GetNamePlates = function() local t = {} for _, p in pairs(PLATES) do t[#t + 1] = p end return t end
UnitGUID = function(u) return UNITS[u] and UNITS[u].guid or "Player-1-00000001" end
UnitIsPlayer = function(u) return u == "player" or (UNITS[u] and UNITS[u].player) or false end
UnitReaction = function(u) return UNITS[u] and UNITS[u].reaction end
UnitCanAttack = function(_, u) return (UNITS[u] and UNITS[u].reaction or 5) < 4 end
C_TooltipInfo = C_TooltipInfo or {}
READS = 0
C_TooltipInfo.GetUnit = function(u)
	READS = READS + 1
	local out = { lines = {} }
	for i, t in ipairs(UNITS[u].lines) do out.lines[i] = { leftText = t } end
	return out
end
PP:RefreshTitles()
""")
def title(u):
    return p.eval("""(function() local h = PP.titled[PLATES['%s']] if h and h:IsShown() then return h.text:GetText() end end)()""" % u)
check(title("nameplate1") == "<Cooking Supplier>", "Naal Mistrunner: <Cooking Supplier> (%r)" % title("nameplate1"))
check(title("nameplate2") is None, "a guard with no title (the level line isn't a title): nothing")
check(title("nameplate3") is None, "a hostile NPC: nothing (friendly only, Shannon)")
check(title("nameplate4") is None, "a player: nothing (their second line is a guild)")
p.lua("R0 = READS PP:RefreshTitles()")
check(p.eval("READS - R0") == 0, "titles are remembered per kind of NPC (no tooltip read again)")
p.lua("A.QoL.db.partyPlates.npcTitles = false PP:RefreshTitles()")
check(title("nameplate1") is None, "setting off: gone")

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
