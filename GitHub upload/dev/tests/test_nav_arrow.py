"""The navigation arrow (DESIGN 98), offline. Run: python3 dev/tests/test_nav_arrow.py"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player, ALL_FILES

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

p = Player("Alice", files=ALL_FILES)
p.lua("""
-- one zone, 1000 x 1000 yards: map 1 spans north 1000..0, west 1000..0
local function V(x, y) return { x = x, y = y, GetXY = function(s) return s.x, s.y end } end
CreateVector2D = V
C_Map = C_Map or {}
C_Map.GetWorldPosFromMapPos = function(map, v) if map == 1 then return 0, V(1000 - 1000 * v.y, 1000 - 1000 * v.x) elseif map == 2 then return 1, V(0, 0) end end
ME = { 50, 50 }
C_Map.GetBestMapForUnit = function() return 1 end
C_Map.GetPlayerMapPosition = function() return V(ME[1] / 100, ME[2] / 100) end
FACING = 0
GetPlayerFacing = function() return FACING end
PIN = nil
C_Map.HasUserWaypoint = function() return PIN ~= nil end
-- (WoW Forever: the pin's position is a plain { x, y } table, no GetXY)
C_Map.GetUserWaypoint = function() return PIN and { uiMapID = PIN[1], position = { x = PIN[2] / 100, y = PIN[3] / 100 } } end
C_Map.ClearUserWaypoint = function() PIN = nil end
C_Map.GetMapInfo = function(m) return { name = "Zone " .. m } end
FOCUS = nil
C_SuperTrack = { GetSuperTrackedQuestID = function() return FOCUS end }
DONE = false
OBJ = {}
C_QuestLog = { IsComplete = function() return DONE end, GetQuestObjectives = function() return OBJ end, GetTitleForQuestID = function(q) return "Quest " .. q end }
AzerothAlmanacDB = { version = 999, settings = {}, journal = {}, found = {}, chars = {} }
FireEvent("ADDON_LOADED", "AzerothAlmanac") FireEvent("PLAYER_LOGIN") RunTimers(3)
NA = A.NavArrow
""")
# maths: north is up the map (smaller y), west is left (smaller x)
d, b = p.eval("NA.Bearing(0, 0, 100, 0)")
check(abs(d - 100) < 1e-6 and abs(b) < 1e-6, "due north: 100 yd, bearing 0")
d, b = p.eval("NA.Bearing(0, 0, 0, 100)")
check(abs(b - math.pi / 2) < 1e-6, "due west: bearing 90 degrees (counter-clockwise, as the game's facing)")
check(abs(p.eval("NA.Turn(0.1, 2 * math.pi - 0.1)") - 0.2) < 1e-6, "the turn wraps round north")
inst, n, w = p.eval("NA.World(1, 50, 40)")
check(inst == 0 and abs(n - 600) < 1e-6 and abs(w - 500) < 1e-6, "map 50%, 40% -> 600 north, 500 west")

# 1. nothing: hidden
p.lua("NA:Resolve() NA:Paint()")
check(p.eval("AzerothAlmanacNavArrow:IsShown()") in (False, None), "no pin and no focused quest: no arrow")

# 2. a focused quest: the nearest spot of what it asks for, from your records
p.lua("""
A.DB.quest[90001] = { 5, 1, 12, nil, "777", nil, "701:8" }
A.db.found.creature = A.db.found.creature or {}
A.db.found.creature[701] = { name = "Kobold Vermin", c = {}, kz = { [1] = { "50.0:30.0", "50.0:60.0" } } }
A.db.found.npc = A.db.found.npc or {}
A.db.found.npc[777] = { name = "Marshal McBride", map = 1, x = 20, y = 50, c = {} }
A.Store:ClearShown()
FOCUS = 90001
OBJ = { { text = "Kobold Vermin slain: 2/8", finished = false } }
NA:Resolve() NA:Paint()
T1 = AzerothAlmanacNavArrow.name:GetText() D1 = AzerothAlmanacNavArrow.dist:GetText()
""")
check(p.eval("T1") == "Kobold Vermin", "focused quest: points to the creature it asks for (%s)" % p.eval("T1"))
check((p.eval("D1") or "").startswith("100 yd"), "...at the nearest spot you've killed it (%s)" % p.eval("D1"))
# 3. complete: the turn-in
p.lua("DONE = true NA:Resolve() NA:Paint() T2 = AzerothAlmanacNavArrow.name:GetText()")
check(p.eval("T2") == "Marshal McBride", "complete: points to whoever takes it in (%s)" % p.eval("T2"))
# 4. the pin wins
p.lua("A.Widgets.Waypoint(1, 80, 50, 'Goldshire Inn') PIN = { 1, 80, 50 } NA:Resolve() NA:Paint() T3 = AzerothAlmanacNavArrow.name:GetText()")
check(p.eval("T3") == "Goldshire Inn", "a map pin always comes first, with the name it was set for (%s)" % p.eval("T3"))
# 5. arriving at the pin removes it, then back to the quest
p.lua("ME = { 79.5, 50 } NA:Paint() ARR = AzerothAlmanacNavArrow.dist:GetText() RunTimers(2) T4 = AzerothAlmanacNavArrow.name:GetText()")
check("Arrived" in (p.eval("ARR") or ""), "within 8 yards: Arrived")
check(p.eval("PIN") is None and p.eval("T4") == "Marshal McBride", "the pin is removed and the arrow goes back to the quest")
# 6. a quest with nothing known: hidden, with a note
p.lua("DONE = false FOCUS = 90002 A.DB.quest[90002] = { 5, 1, 12, nil, nil, nil, '702:5' } NA:Resolve() NA:Paint() N6 = AzerothAlmanacNavArrow.name:GetText() ARROW6 = AzerothAlmanacNavArrow.arrow:IsShown()")
check("not found yet" in (p.eval("N6") or "") and not p.eval("ARROW6"), "nothing known: no arrow, a note (%s)" % p.eval("N6"))
# 7. facing: the arrow turns
p.lua("FOCUS = 90001 ME = { 50, 50 } FACING = math.pi NA:Resolve() NA:Paint()")
check(p.eval("AzerothAlmanacNavArrow.glow:IsShown()") is True, "facing the target (it lies south, you face south): on-course glow")
p.lua("ME = { 50, 57 } NA:Resolve() NA:Paint() N8 = AzerothAlmanacNavArrow.name:GetText() A8 = AzerothAlmanacNavArrow.arrow:IsShown()")
check("around here" in (p.eval("N8") or "") and not p.eval("A8"), "near where you saw it (30 yd): 'around here', no arrow (%s)" % p.eval("N8"))
print("the game's own quest markers (DESIGN 101)")
p.lua("""
PIN = nil ME = { 50, 50 } DONE = false
MARKERS = { [1] = { { questID = 97933, x = 0.20, y = 0.50 } } }
C_QuestLog.GetQuestsOnMap = function(m) return MARKERS[m] or {} end
FOCUS = 97933 OBJ = { { text = "Peacebloom: 0/3", finished = false } }
NA:Resolve() NA:Paint() G1 = AzerothAlmanacNavArrow.name:GetText() GA1 = AzerothAlmanacNavArrow.arrow:IsShown() GD1 = AzerothAlmanacNavArrow.dist:GetText()
""")
check(p.eval("G1") == "Quest 97933" and p.eval("GA1") and (p.eval("GD1") or "").startswith("300 yd"),
      "a quest the Almanac knows nothing of (Forever's own): follows the game's marker (%s, %s)" % (p.eval("G1"), p.eval("GD1")))
p.lua("ME = { 22, 50 } NA:Resolve() NA:Paint() G2 = AzerothAlmanacNavArrow.name:GetText() GA2 = AzerothAlmanacNavArrow.arrow:IsShown()")
check("around here" in (p.eval("G2") or "") and not p.eval("GA2"), "within 60 yards of the game's area marker: 'around here' (%s)" % p.eval("G2"))
p.lua("ME = { 50, 50 } DONE = true NA:Resolve() NA:Paint() G3 = AzerothAlmanacNavArrow.name:GetText() GA3 = AzerothAlmanacNavArrow.arrow:IsShown()")
check(p.eval("G3") == "Turn in" and p.eval("GA3"), "complete, turn-in never met: follows the game's turn-in marker (%s)" % p.eval("G3"))
p.lua("ME = { 20.5, 50 } NA:Paint() G4 = AzerothAlmanacNavArrow.dist:GetText()")
check("Arrived" in (p.eval("G4") or ""), "...and arrives at it (a turn-in marker is the NPC)")
# your own spot comes first while in progress; the game's turn-in first once complete
p.lua("""
ME = { 50, 50 } DONE = false MARKERS[1] = { { questID = 90001, x = 0.90, y = 0.90 } }
FOCUS = 90001 OBJ = { { text = "Kobold Vermin slain: 2/8", finished = false } }
NA:Resolve() NA:Paint() G5 = AzerothAlmanacNavArrow.name:GetText()
DONE = true NA:Resolve() NA:Paint() G6 = AzerothAlmanacNavArrow.name:GetText() G6X = NA:Target() and NA:Target().x
""")
check(p.eval("G5") == "Kobold Vermin", "in progress: your own nearest spot wins over the game's marker (%s)" % p.eval("G5"))
check(p.eval("G6") == "Marshal McBride" and abs((p.eval("G6X") or 0) - 90) < 0.01, "complete: the game's turn-in marker first, named for who you met (%s)" % p.eval("G6"))
p.lua("MARKERS = {} C_QuestLog.GetQuestsOnMap = nil DONE = false")
print("/aa navprobe")
p.lua("""
C_QuestLog.GetNextWaypoint = function(q) return 1429, 0.42, 0.61 end
C_QuestLog.GetQuestsOnMap = function(m) return { { questID = 33, x = 0.4, y = 0.6, isMapIndicatorQuest = false } } end
QuestPOIGetIconInfo = function(q) return false, 0.4, 0.6, 1 end
CHAT = {} SlashCmdList.AZEROTHALMANAC("navprobe 33")
""")
out = p.eval("table.concat(CHAT, ' / ')")
check("Navigation probe" in out and "quest 33" in out and "GetNextWaypoint: 1429, 0.4200, 0.6100" in out and "QuestPOIGetIconInfo" in out,
      "it prints what the game says about the quest (%s)" % out[-160:])
p.lua('CHAT = {} C_QuestLog.GetNextWaypoint = function() error("boom") end SlashCmdList.AZEROTHALMANAC("navprobe 33")')
check("error" in p.eval("table.concat(CHAT, ' / ')"), "a call that errors is reported, not thrown")
print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
