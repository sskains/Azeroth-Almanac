"""The tank's target (QoL/TankTarget.lua, 2026-11-06): the enemy a group's tank has targeted is marked on
its nameplate; in combat the tanks' targets are read every 0.25 s, out of combat on events only.
Run: python3 dev/tests/test_tank_target.py"""
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
TT = A.QoL.TankTarget
-- other helpers react to the fake group too (Healer Assist wants a spellbook the stub hasn't got):
-- each handler runs on its own, and only TankTarget.lua's errors are kept
TT_ERRORS = {}
function FireEvent(ev, ...)
  for _, f in ipairs(FRAMES) do
    if f._events and f._events[ev] and f._scripts.OnEvent then
      local ok, err = pcall(f._scripts.OnEvent, f, ev, ...)
      if not ok and tostring(err):find("TankTarget") then TT_ERRORS[#TT_ERRORS + 1] = tostring(err) end
    end
  end
end
-- a party: party1 tanks, party2 doesn't (yet); two mobs with plates, one friendly NPC
ROLE = { party1 = "TANK", party2 = "DAMAGER", player = "DAMAGER" }
TARGET = { party1 = "wolf" }
DEAD, OFFLINE, COMBAT = {}, {}, false
GUID = { party1 = "Player-1-2", party2 = "Player-1-3", player = "Player-1-1",
         wolf = "Creature-0-1-1-1-100-A", boar = "Creature-0-1-1-1-101-B", guard = "Creature-0-1-1-1-102-C" }
PLATE_OF = { nameplate1 = "wolf", nameplate2 = "boar", nameplate3 = "guard" }
local function Who(u)
  if PLATE_OF[u] then return PLATE_OF[u] end
  local tank = u:match("^(.-)target$")
  if tank then return TARGET[tank] end
  return u
end
local function Plate()
  local p = CreateFrame("Frame")
  p.UnitFrame = CreateFrame("Frame")
  p.UnitFrame.healthBar = CreateFrame("StatusBar")
  p.UnitFrame.name = p.UnitFrame:CreateFontString()
  return p
end
PLATES = { nameplate1 = Plate(), nameplate2 = Plate(), nameplate3 = Plate() }
for u, pl in pairs(PLATES) do pl.namePlateUnitToken = u end
C_NamePlate = {
  GetNamePlateForUnit = function(u) return PLATES[u] end,
  GetNamePlates = function() local l = {} for _, pl in pairs(PLATES) do l[#l + 1] = pl end return l end,
}
IsInGroup = function() return true end
IsInRaid = function() return false end
UnitExists = function(u) local w = Who(u) return w ~= nil and GUID[w] ~= nil end
UnitGUID = function(u) local w = Who(u) return w and GUID[w] end
UnitIsUnit = function(a, b) return Who(a) == Who(b) end
UnitGroupRolesAssigned = function(u) return ROLE[u] or "NONE" end
GetPartyAssignment = function() return false end
UnitCanAttack = function(_, u) local w = Who(u) return w == "wolf" or w == "boar" end
UnitIsDead = function(u) return DEAD[Who(u)] == true end
UnitIsDeadOrGhost = function(u) return DEAD[Who(u)] == true end
UnitIsConnected = function(u) return not OFFLINE[u] end
InCombatLockdown = function() return COMBAT end
FireEvent("GROUP_ROSTER_UPDATE")
FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1") FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate2") FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate3")
function Marked(u) local m = TT.MarkOf(PLATES[u]) return m ~= nil and m:IsShown() end
""")
db = "AzerothAlmanacDB.qol.tankTarget"
check(p.eval(db + ".enabled") is True and p.eval(db + ".look") == "marker", "on by default, the marker look")
check(p.eval("#TT.Tanks()") == 1 and p.eval("TT.Tanks()[1]") == "party1", "the tank role makes party1 the tank")
check(p.eval("Marked('nameplate1')") and not p.eval("Marked('nameplate2')"), "out of combat: the tank's target (the wolf) is marked, nothing else")
check(not p.eval("TT.Polling()"), "...and nothing polls out of combat")

p.lua('TARGET.party1 = "boar" FireEvent("UNIT_TARGET", "party1")')
check(p.eval("Marked('nameplate2')") and not p.eval("Marked('nameplate1')"), "out of combat, the tank switches: the mark moves at once (UNIT_TARGET)")

# combat: the poll, every 0.25 s
p.lua('COMBAT = true FireEvent("PLAYER_REGEN_DISABLED")')
check(p.eval("TT.Polling()"), "combat starts: polling")
check(p.eval("TT.POLL") == 0.25, "...every 0.25 seconds")
p.lua('TARGET.party1 = "wolf" RunTimers(0.1)')
check(p.eval("Marked('nameplate2')"), "a switch with no event: unchanged before the next poll")
p.lua("RunTimers(0.2)")
check(p.eval("Marked('nameplate1')") and not p.eval("Marked('nameplate2')"), "...and the poll moves the mark to the wolf")

p.lua('TARGET.party1 = "guard" RunTimers(0.25)')
check(not p.eval("Marked('nameplate1')") and not p.eval("Marked('nameplate3')"), "the tank targets a friendly: nothing marked")
p.lua('TARGET.party1 = nil RunTimers(0.25)')
check(not any(p.eval("Marked('nameplate%d')" % i) for i in (1, 2, 3)), "no target: nothing marked")
p.lua('TARGET.party1 = "wolf" DEAD.wolf = true RunTimers(0.25)')
check(not p.eval("Marked('nameplate1')"), "the target dies: the mark goes")
p.lua('DEAD.wolf = nil DEAD.party1 = true RunTimers(0.25)')
check(not p.eval("Marked('nameplate1')"), "the tank dies: the mark goes")
p.lua('DEAD.party1 = nil OFFLINE.party1 = true RunTimers(0.25)')
check(not p.eval("Marked('nameplate1')"), "the tank goes offline: the mark goes")
p.lua('OFFLINE.party1 = nil RunTimers(0.25)')
check(p.eval("Marked('nameplate1')"), "back: marked again")

# two tanks
p.lua('ROLE.party2 = "TANK" TARGET.party2 = "boar" FireEvent("PLAYER_ROLES_ASSIGNED") RunTimers(0.25)')
check(p.eval("#TT.Tanks()") == 2, "a second tank")
check(p.eval("Marked('nameplate1')") and p.eval("Marked('nameplate2')"), "...both tanks' targets are marked")

# the plate leaves
p.lua('FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate2")')
check(not p.eval("Marked('nameplate2')"), "a plate leaves the screen: its mark goes with it")
p.lua('FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate2") RunTimers(0.25)')
check(p.eval("Marked('nameplate2')"), "...and comes back when the plate does")

# looks
p.lua(db + '.look = "outline" TT:Refresh()')
m = "TT.MarkOf(PLATES.nameplate1)"
check(p.eval(m + ".edge:IsShown()") and not p.eval(m + ".icon:IsShown()"), "Outline: the edge, no shield")
p.lua(db + '.look = "both" TT:Refresh()')
check(p.eval(m + ".edge:IsShown()") and p.eval(m + ".icon:IsShown()"), "Both: edge and shield")
p.lua(db + '.look = "marker" TT:Refresh()')
check(not p.eval(m + ".edge:IsShown()") and p.eval(m + ".icon:IsShown()"), "Marker above: the shield, no edge")
# (2026-11-11) the red glow: a breathing red halo round the bar, nothing else
check(p.eval('(function() for _, l in ipairs(TT.looks) do if l.key == "glow" then return l.name end end end)()') == "Red glow", "a fourth look: Red glow")
p.lua(db + '.look = "glow" TT:Refresh()')
check(p.eval(m + ".glow:IsShown()") and not p.eval(m + ".edge:IsShown()") and not p.eval(m + ".icon:IsShown()"), "Red glow: the glow, no shield, no edge")
p.lua("UPD = " + m + ":GetScript('OnUpdate') ALPHAS = {} for i = 1, 8 do NOW = (NOW or 100) + 0.2 UPD(" + m + ") ALPHAS[i] = " + m + ".glow._alpha end")
alphas = [p.eval("ALPHAS[%d]" % i) for i in range(1, 9)]
check(all(a is not None and 0.44 <= a <= 0.96 for a in alphas) and max(alphas) - min(alphas) > 0.2, "...it breathes, between dim and bright (%s)" % ["%.2f" % a for a in alphas if a is not None])
p.lua(db + '.look = "marker" TT:Refresh()')
check(not p.eval(m + ".glow:IsShown()"), "back to Marker above: the glow goes")

# combat ends: the poll stops, the mark stays
p.lua('COMBAT = false FireEvent("PLAYER_REGEN_ENABLED")')
check(not p.eval("TT.Polling()"), "combat ends: polling stops")
check(p.eval("Marked('nameplate1')"), "...and the mark stays (it shows at all times)")

# you're a tank
p.lua('ROLE.party2 = "DAMAGER" ROLE.player = "TANK" TARGET.player = "boar" FireEvent("PLAYER_ROLES_ASSIGNED")')
check(not p.eval("Marked('nameplate2')"), "your own target isn't marked by default when you're a tank")
p.lua(db + '.whenTank = true TT:Refresh()')
check(p.eval("Marked('nameplate2')"), "...it is with \"Also when I'm the tank\"")

# the switch
p.lua(db + '.enabled = false TT:Refresh()')
check(not any(p.eval("Marked('nameplate%d')" % i) for i in (1, 2, 3)), "switched off: every mark goes")
p.lua('COMBAT = true FireEvent("PLAYER_REGEN_DISABLED")')
check(not p.eval("TT.Polling()"), "...and combat doesn't start the poll")
p.lua(db + '.enabled = true TT:Refresh()')
check(p.eval("TT.Polling()") and p.eval("Marked('nameplate1')"), "switched back on in combat: polling and marked again")

# no tank: nothing to do
p.lua('COMBAT = false FireEvent("PLAYER_REGEN_ENABLED") ROLE.party1 = "DAMAGER" ROLE.player = "DAMAGER" FireEvent("GROUP_ROSTER_UPDATE")')
p.lua('COMBAT = true FireEvent("PLAYER_REGEN_DISABLED")')
check(p.eval("#TT.Tanks()") == 0 and not p.eval("TT.Polling()"), "a group without a tank: no poll in combat")
check(not any(p.eval("Marked('nameplate%d')" % i) for i in (1, 2, 3)), "...and nothing marked")

# Healer Assist still asks the same question
check(p.eval("A.QoL.IsTankUnit('party1')") is False and p.eval("(function() ROLE.party1 = 'TANK' return A.QoL.IsTankUnit('party1') end)()") is True,
      "the shared tank check answers by role")

# the settings section builds (Settings > Group Settings, /aa settings tank)
p.lua('SOK, SERR = pcall(function() A.QoL.Settings:Open("tank") RunTimers(1) end)')
check(p.eval("SOK"), "the Group Settings page opens with the Tank's target section (%s)" % p.eval("tostring(SERR)"))

check(p.eval("#TT_ERRORS") == 0, "no Lua errors from TankTarget.lua (%s)" % p.eval("TT_ERRORS[1]"))

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
