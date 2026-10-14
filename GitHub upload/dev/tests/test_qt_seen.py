"""Quest Targeter: mobs off camera still count for a while (Forever drops their nameplates). Run: python3 dev/tests/test_qt_seen.py"""
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
PLATES = {}   -- nameplateN -> { guid, name, dead }
local real = { UnitExists = UnitExists, UnitName = UnitName, UnitGUID = UnitGUID, UnitIsDead = UnitIsDead, UnitCanAttack = UnitCanAttack }
local function P(u) return type(u) == "string" and PLATES[u] end
UnitExists = function(u) if P(u) then return true end if type(u) == "string" and u:match("^nameplate") then return false end return real.UnitExists and real.UnitExists(u) end
UnitName = function(u) if P(u) then return P(u).name end return real.UnitName(u) end
UnitGUID = function(u) if P(u) then return P(u).guid end return real.UnitGUID and real.UnitGUID(u) end
UnitIsDead = function(u) if P(u) then return P(u).dead or false end return false end
UnitCanAttack = function(u1, u) if P(u) then return true end return false end
UnitIsPlayer = function(u) return u == "player" end
UnitIsTapDenied = function() return false end
UnitAffectingCombat = function() return false end
UnitThreatSituation = function() return nil end
GetRaidTargetIndex = function() return nil end
AzerothAlmanacDB = { version = 999, settings = {}, journal = {}, found = {}, chars = {} }
FireEvent("ADDON_LOADED", "AzerothAlmanac") FireEvent("PLAYER_LOGIN") RunTimers(3)
QT = A.QoL.QuestTargeter
A.Where = function() return { map = 1 } end   -- (no position: memory by time only)
function Count() FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate9") RunTimers(0.01) return QT:Nearby("Flatland Cougar") end
""")
p.lua('PLATES.nameplate1 = { guid = "Creature-0-1-1-1-3035-A", name = "Flatland Cougar" }')
check(p.eval("Count()") == 1, "a cougar on camera counts")
p.lua("PLATES.nameplate1 = nil")
check(p.eval("Count()") == 1, "turned away (its nameplate gone): still counted")
p.lua("RunTimers(70)")
check(p.eval("Count()") == 0, "a minute later, not seen again: no longer counted")
p.lua('PLATES.nameplate2 = { guid = "Creature-0-1-1-1-3035-B", name = "Flatland Cougar" } Count() PLATES.nameplate2.dead = true')
check(p.eval("Count()") == 0, "killed: forgotten at once")
# a distant mob whose nameplate unit is still blank when the event comes (WoW Forever)
p.lua('PLATES.nameplate3 = { guid = "Creature-0-1-1-1-2969-C", name = nil } FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate3") RunTimers(0.01) PLATES.nameplate3.name = "Wiry Swoop" RunTimers(1)')
check(p.eval('QT:Nearby("Wiry Swoop")') == 1, "a nameplate filled in late is counted without targeting it")
p.lua('local ok, e = pcall(SlashCmdList.AZALMQT, "why") WHY = ok or tostring(e)')
check(p.eval("WHY") is True, "/qt why runs (%s)" % p.eval("WHY"))
# (2026-10-12) an item no known creature drops yet: its name names the owner
check(p.eval('QT.OwnerOf("Nak\'s Skull")') == "Nak", "Nak's Skull -> Nak")
check(p.eval('QT.OwnerOf("Kurzen\'s Head")') == "Kurzen", "Kurzen's Head -> Kurzen")
check(p.eval('QT.OwnerOf("Mage\'s Robe")') is None and p.eval('QT.OwnerOf("Linen Cloth")') is None and p.eval('QT.OwnerOf("Ox\'s Hide")') is None,
      "no owner for a class word, a plain item, or a too-short name")
check(p.eval('QT.OwnerOf("Heart of Isha Awak")') == "Isha Awak" and p.eval('QT.OwnerOf("Scroll of Myzrael")') == "Myzrael",
      "Heart of Isha Awak -> Isha Awak, Scroll of Myzrael -> Myzrael")
check(p.eval('QT.OwnerOf("Heart of the Wild")') is None and p.eval('QT.OwnerOf("Essence of Water")') is None,
      "no owner for 'of the ...' or an element")
# (DESIGN 105) a quest item whose droppers you haven't met: named from Data\QuestMobs.lua
p.lua("""C_QuestLog.GetNumQuestLogEntries = function() return 0 end A.db.found.item = A.db.found.item or {} A.db.found.item[5842] = { name = "Unrefined Ore Sample" }
DROPS = A.QoL.DropsFor("Unrefined Ore Sample")""")
names = p.eval("DROPS and table.concat((function() local t = {} for i, e in ipairs(DROPS) do t[i] = e[1] end return t end)(), ',')")
check(names and "Gravelsnout Surveyor" in names and "Gravelsnout Digger" in names, "unmet droppers are named for targeting (%s)" % names)
check(p.eval("A.Store:Get('creature', 4116) == nil"), "...without the creature appearing in the Almanac (still not met)")
print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
