"""Quest Targeter: nameplate range raised to 45 yards (WoW Forever's limit) while on, put back when off. Run: python3 dev/tests/test_qt_range.py"""
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
CV = { nameplateMaxDistance = "20", nameplateShowEnemies = "0", nameplateShowAll = "0" }
GetCVar = function(k) return CV[k] end
SetCVar = function(k, v) CV[k] = tostring(v) end
COMBAT = false
InCombatLockdown = function() return COMBAT end
QT = A.QoL.QuestTargeter
T = { enabled = true, displayIDs = {}, facesVersion = 2 }
QT:OnInitialize({ questTargeter = T })
QT:ApplyRange()  ON = CV.nameplateMaxDistance  ALL = CV.nameplateShowAll  EN = CV.nameplateShowEnemies  SAVED = T.savedCVars.nameplateMaxDistance
T.enabled = false QT:ApplyRange()  OFF = CV.nameplateMaxDistance  ALL0 = CV.nameplateShowAll  EN0 = CV.nameplateShowEnemies  CLEARED = T.savedCVars.nameplateMaxDistance == nil
CV.nameplateMaxDistance = "25" T.enabled = true COMBAT = true QT:ApplyRange()  INCOMBAT = CV.nameplateMaxDistance
COMBAT = false QT:ApplyRange()  AFTER = CV.nameplateMaxDistance
T.enabled = false QT:ApplyRange()  BACK = CV.nameplateMaxDistance
-- a client that caps at 41
SetCVar = function(k, v) CV[k] = tostring(k == "nameplateMaxDistance" and math.min(41, tonumber(v)) or v) end
CV.nameplateMaxDistance = "20" T.enabled = true QT:ApplyRange() CAP = CV.nameplateMaxDistance
QT:ApplyRange() CAP2 = CV.nameplateMaxDistance
T.enabled = false QT:ApplyRange() CAPOFF = CV.nameplateMaxDistance
""")
check(p.eval("ON") == "45" and p.eval("SAVED") == 20, "on: nameplates reach 45 yards, the old 20 kept")
check(p.eval("ALL") == "1" and p.eval("EN") == "1", "on: enemy nameplates shown, out of combat too")
check(p.eval("ALL0") == "0" and p.eval("EN0") == "0", "off: both back as they were")
check(p.eval("OFF") == "20" and p.eval("CLEARED") is True, "off: back to 20")
check(p.eval("INCOMBAT") == "25" and p.eval("AFTER") == "45", "in combat it waits; after combat 45")
check(p.eval("BACK") == "25", "the player's own value (25) comes back")
check(p.eval("CAP") == "41" and p.eval("CAP2") == "41" and p.eval("CAPOFF") == "20", "a client that caps at 41: 41, and back to 20 when off")
print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
