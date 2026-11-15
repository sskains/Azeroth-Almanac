"""Other healers' targets (QoL/HealerTarget.lua, 2026-11-11): the group member another healer has selected,
and the one their heal is on its way to, is marked on that member's unit frame, so a backup healer picks
someone else. In combat it's read every 0.25 s, out of combat on events only.
Run: python3 dev/tests/test_healer_target.py"""
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
HT = A.QoL.HealerTarget
-- other helpers react to the fake group too: each handler runs on its own, only HealerTarget.lua's errors kept
HT_ERRORS = {}
function FireEvent(ev, ...)
  for _, f in ipairs(FRAMES) do
    if f._events and f._events[ev] and f._scripts.OnEvent then
      local ok, err = pcall(f._scripts.OnEvent, f, ev, ...)
      if not ok and tostring(err):find("HealerTarget") then HT_ERRORS[#HT_ERRORS + 1] = tostring(err) end
    end
  end
end
-- you're a shaman; party1 a priest with no role set, party2 the tank (a warrior), party3 a rogue
ROLE = { party2 = "TANK", party3 = "DAMAGER" }
CLASS = { player = "SHAMAN", party1 = "PRIEST", party2 = "WARRIOR", party3 = "ROGUE" }
NAME = { player = "Alice", party1 = "Bob", party2 = "Tankard", party3 = "Sly" }
TARGET = {}          -- healer -> member they've selected
INCOMING = {}        -- member -> { healer -> amount }
CASTING = {}         -- healer -> spell name
SECRET_INCOMING, COMBAT = false, false
local function Who(u)
  local h = u:match("^(party%d)target$")
  if h then return TARGET[h] end
  return NAME[u] and u or nil
end
IsInGroup = function() return true end
IsInRaid = function() return false end
UnitExists = function(u) return Who(u) ~= nil end
UnitIsUnit = function(a, b) return Who(a) ~= nil and Who(a) == Who(b) end
UnitGroupRolesAssigned = function(u) return ROLE[u] or "NONE" end
UnitClass = function(u) local c = CLASS[Who(u) or ""] return c, c end
UnitName = function(u) return NAME[Who(u) or ""] end
UnitCanAttack = function() return false end
UnitIsConnected = function() return true end
UnitIsDeadOrGhost = function() return false end
UnitCastingInfo = function(u) return CASTING[u] end
UnitChannelInfo = function() return nil end
UnitGetIncomingHeals = function(m, h)
  if SECRET_INCOMING then return nil end
  return (INCOMING[m] or {})[h] or 0
end
InCombatLockdown = function() return COMBAT end
-- each member's unit frame
UFRAMES = {}
for _, t in ipairs({ "player", "party1", "party2", "party3" }) do UFRAMES[t] = CreateFrame("Frame") end
A.QoL.HealAssist.FrameFor = function(t) return UFRAMES[t] end
FireEvent("GROUP_ROSTER_UPDATE")
function Mark(t) return HT.MarkOf(t) end
function Badge(t) local m = Mark(t) return m ~= nil and m:IsShown() end
function Glow(t) local m = Mark(t) return m ~= nil and m:IsShown() and m.glow:IsShown() end
function Text(t) local m = Mark(t) return m and m.text:GetText() end
""")
db = "AzerothAlmanacDB.qol.healerTarget"
check(p.eval(db + ".enabled") is True and p.eval(db + ".selected") is True, "on by default, selected members too")
check(p.eval("#HT.Healers()") == 1 and p.eval("HT.Healers()[1]") == "party1", "a priest with no role set counts as a healer; the tank and rogue don't, nor do you")
check(not any(p.eval(f"Badge('{t}')") for t in ("player", "party1", "party2", "party3")), "the healer has no one selected: nothing marked")

p.lua('TARGET.party1 = "party2" FireEvent("UNIT_TARGET", "party1")')
check(p.eval("Badge('party2')") and not p.eval("Glow('party2')"), "the healer selects the tank: a badge on the tank's frame, no glow yet")
check(p.eval("Text('party2')") == "Bob", "...with the healer's name on it")
check(abs(p.eval("Mark('party2'):GetAlpha()") - 0.75) < 0.01, "...dimmer, as they're only selected")

p.lua('CASTING.party1 = "Greater Heal" INCOMING.party2 = { party1 = 900 } FireEvent("UNIT_HEAL_PREDICTION", "party2")')
check(p.eval("Glow('party2')") and p.eval("Mark('party2'):GetAlpha()") == 1, "the heal is on its way to the tank: the glow, the badge at full brightness")

p.lua('INCOMING.party2 = nil INCOMING.player = { party1 = 400 } FireEvent("UNIT_HEAL_PREDICTION", "player")')
check(p.eval("Glow('player')"), "a heal cast on you without targeting you (mouseover, a click on your frame): your frame glows")
check(p.eval("Badge('party2')") and not p.eval("Glow('party2')"), "...and the tank, still selected, keeps the dim badge without the glow")

p.lua('SECRET_INCOMING = true INCOMING.player = nil FireEvent("UNIT_SPELLCAST_START", "party1")')
check(p.eval("Glow('party2')") and not p.eval("Glow('player')"), "the game won't say where heals go: a cast while the tank is selected counts as on the tank")
p.lua('SECRET_INCOMING = false CASTING.party1 = nil FireEvent("UNIT_SPELLCAST_STOP", "party1")')
check(p.eval("Badge('party2')") and not p.eval("Glow('party2')"), "the cast ends: back to the dim badge")

p.lua(db + '.selected = false HT:Refresh()')
check(not p.eval("Badge('party2')"), "\"Also who they've selected\" off: a selected member isn't marked")
p.lua(db + '.selected = true HT:Refresh()')

p.lua(db + '.names = false HT:Refresh()')
check(p.eval("Badge('party2')") and not p.eval("Mark('party2').text:IsShown()"), "names off: the badge is the healer cross alone")
p.lua(db + '.names = true HT:Refresh()')

# combat: the poll picks up a switch with no event
p.lua('COMBAT = true FireEvent("PLAYER_REGEN_DISABLED")')
check(p.eval("HT.Polling()"), "in combat: polling")
p.lua('TARGET.party1 = "party3" RunTimers(0.3)')
check(p.eval("Badge('party3')") and not p.eval("Badge('party2')"), "in combat, the healer switches with no event: the mark moves on the next poll")
p.lua('COMBAT = false FireEvent("PLAYER_REGEN_ENABLED")')
check(not p.eval("HT.Polling()"), "combat over: the poll stops")

p.lua('FireEvent("UNIT_TARGET", "nameplate4") FireEvent("UNIT_SPELLCAST_START", "nameplate4")')
check(p.eval("#HT_ERRORS") == 0, "events for other units (nameplates) are left alone, no errors")

p.lua('ROLE.party1 = "DAMAGER" FireEvent("PLAYER_ROLES_ASSIGNED")')
check(p.eval("#HT.Healers()") == 0 and not p.eval("Badge('party3')"), "the priest takes the damage role: not a healer, the mark goes")
p.lua('ROLE.party1 = "HEALER" FireEvent("PLAYER_ROLES_ASSIGNED")')
check(p.eval("Badge('party3')"), "...the healer role again: back")

p.lua(db + '.enabled = false HT:Refresh()')
check(not any(p.eval(f"Badge('{t}')") for t in ("player", "party1", "party2", "party3")), "switched off: every mark goes")
check(p.eval("#HT_ERRORS") == 0, "no errors from HealerTarget.lua" + ("" if p.eval("#HT_ERRORS") == 0 else ": " + str(p.eval("HT_ERRORS[1]"))))

print()
print("all passed" if not FAILS else f"{len(FAILS)} failed")
sys.exit(1 if FAILS else 0)
