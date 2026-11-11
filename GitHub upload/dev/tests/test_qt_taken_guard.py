"""Quest Targeter: a click never leaves you on a mob someone else has tagged or is fighting.
Run: python3 dev/tests/test_qt_taken_guard.py"""
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
TARGET = { exists = true, tapDenied = false, combat = false, dead = false }
UnitExists = function(u) if u == "target" then return TARGET.exists end return false end
UnitCanAttack = function(a, u) return u == "target" end
UnitIsDead = function(u) return TARGET.dead end
UnitIsTapDenied = function(u) return TARGET.tapDenied end
UnitAffectingCombat = function(u) return TARGET.combat end
UnitThreatSituation = function() return nil end
UnitName = function(u) return u == "target" and "Nightsaber" or "Alice" end
UnitIsUnit = function() return false end
UnitInParty = function() return false end
UnitInRaid = function() return false end
CLEARS = 0
ClearTarget = function() CLEARS = CLEARS + 1 TARGET.exists = false end
AzerothAlmanacDB = { version = 999, settings = {}, journal = {}, found = {}, chars = {} }
FireEvent("ADDON_LOADED", "AzerothAlmanac") FireEvent("PLAYER_LOGIN") RunTimers(3)
QT = A.QoL.QuestTargeter
""")
check(p.eval("type(QT.PostClick) == 'function' and type(QT.PreClick) == 'function'") is True, "the targeting buttons have a before and an after check")
p.lua("TARGET.tapDenied = true QT.PostClick()")
check(p.eval("CLEARS") == 1, "a mob tagged by someone else is dropped as the target")
p.lua("TARGET = { exists = true, tapDenied = false, combat = false, dead = false } QT.PostClick()")
check(p.eval("CLEARS") == 1, "a free mob stays targeted")
p.lua("TARGET.combat = true UnitThreatSituation = function() return 1 end QT.PostClick()")
check(p.eval("CLEARS") == 1, "a mob already fighting you stays targeted")
p.lua("UnitThreatSituation = function() return nil end UnitExists = function(u) return u == 'target' or u == 'targettarget' end UnitIsTapDenied = function() return false end TARGET.combat = true QT.PostClick()")
check(p.eval("CLEARS") == 2, "a mob in combat with someone else is dropped")
p.lua("TARGET = { exists = true, tapDenied = true, combat = false, dead = true } QT.PostClick()")
check(p.eval("CLEARS") == 2, "a corpse is left alone")
# (2026-11-11) clicked again mid-fight: ClearTarget is protected in combat, so it must not be called
p.lua("TARGET = { exists = true, tapDenied = true, combat = false, dead = false } UnitExists = function(u) if u == 'target' then return TARGET.exists end return false end UnitIsTapDenied = function() return TARGET.tapDenied end")
p.lua("InCombatLockdown = function() return true end CHAT = {} RunTimers(3) QT.PostClick()")
check(p.eval("CLEARS") == 2, "in combat a taken mob is not cleared (no protected call, no \"blocked\" popup)")
chat = "\n".join(str(v) for v in p.L.globals().CHAT.values())
check("someone else's" in chat and "mid-fight" in chat, "...and the note says why the target stays (%r)" % chat[-90:])
p.lua("InCombatLockdown = function() return false end RunTimers(3) QT.PostClick()")
check(p.eval("CLEARS") == 3, "out of combat again: dropped as before")
p.lua("QT.PreClick()")
check(p.eval("true") is True, "the rescan before a click runs without error")
print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
