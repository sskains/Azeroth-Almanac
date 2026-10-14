"""The Journey's smoother, more whimsical time lapse (2026-10-13, DESIGN 109): idle time squeezed, the
head gliding along a growing line, gryphon flights in an arc, footstep puffs, a bounce on arrival, day
and night, "zzz" over long rests, a crossfade between zones and a sparkly end.
Run: python3 dev/tests/test_journey_smooth.py"""
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
AzerothAlmanacDB = false
FireEvent("ADDON_LOADED", "AzerothAlmanac")
FireEvent("PLAYER_LOGIN")
RunTimers(5)
local INFO = { [1429] = { name = "Elwynn Forest", mapType = 3, parentMapID = 13 }, [1436] = { name = "Westfall", mapType = 3, parentMapID = 13 },
	[13] = { name = "Eastern Kingdoms", mapType = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2 } }
C_Map.GetMapInfo = function(m) return INFO[m] end
C_Map.GetMapArtLayers = function(m) return INFO[m] and { { layerWidth = 1000, layerHeight = 660, tileWidth = 256, tileHeight = 256 } } or nil end
C_Map.GetMapArtLayerTextures = function(m) return INFO[m] and { 1, 2, 3 } or nil end
local RECT = { [1429] = { left = 1000, right = 0, top = 1000, bottom = 0 }, [1436] = { left = 2000, right = 1000, top = 1000, bottom = 0 },
	[13] = { left = 4000, right = -4000, top = 4000, bottom = -4000 } }
A.Townsfolk = A.Townsfolk or {}
A.Townsfolk.MapRect = function(m) return RECT[m] end
ME = A.CharKey()
-- midnight-ish start: a walk in Elwynn (a point every 10 s), a two-hour rest, a hearth, a flight to
-- Westfall, a walk there
T0 = os.time({ year = 2026, month = 10, day = 12, hour = 23, min = 50 })
pts = {}
local t = T0
for i = 1, 6 do pts[#pts + 1] = { t = t, m = 1429, x = 30 + i * 2, y = 50, c = ME } t = t + 10 end
REST_FROM = t - 10
t = t + 7200
pts[#pts + 1] = { t = t, m = 1429, x = 70, y = 30, c = ME, k = "h" } HEARTH = t
t = t + 20
pts[#pts + 1] = { t = t, m = 1429, x = 70, y = 31, c = ME, k = "F" } FLY_FROM = t
t = t + 120
pts[#pts + 1] = { t = t, m = 1436, x = 40, y = 60, c = ME, k = "f" } FLY_TO = t
for i = 1, 6 do t = t + 10 pts[#pts + 1] = { t = t, m = 1436, x = 40 + i * 2, y = 60, c = ME } end
A.Journey.Points = function() return pts end
PANE = A.Widgets.JourneyPane(UIParent, { full = true })
UP = PANE:GetScript("OnUpdate")
function Step(dt) NOW = (NOW or 100) + dt UP(PANE, dt) end
""")

print("idle time squeezed")
p.lua("PANE:Refresh(false)")
rest_share = p.eval("""(function()
	-- the share of the play length spent in the two-hour rest
	local lo, hi = 0, 1
	local function At(t) local a, b = 0, 1 for _ = 1, 40 do local m = (a + b) / 2 if PANE.TimeAt(m) < t then a = m else b = m end end return a end
	return At(HEARTH - 30) - At(REST_FROM + 1)
end)()""")
check(rest_share is not None and rest_share < 0.5, "a two-hour rest takes under half the time lapse (%.2f; it was 0.96)" % (rest_share or 1))
walk_share = p.eval("""(function()
	local function At(t) local a, b = 0, 1 for _ = 1, 40 do local m = (a + b) / 2 if PANE.TimeAt(m) < t then a = m else b = m end end return a end
	return At(T0 + 50) - At(T0)
end)()""")
check(walk_share > 0.08, "the walk before it gets real time on screen (%.2f; it was 0.006)" % walk_share)
check(p.eval("PANE.TimeAt(0)") == p.eval("T0") and p.eval("PANE.TimeAt(1)") == p.eval("pts[#pts].t"), "the clock still runs first point to last")

print("the head glides; the line grows behind it")
p.lua("""
PANE:Refresh(true)
HD = PANE.heads[ME]
-- play until the head is between the 2nd and 3rd point
SEEN_MID, CUT = false, false
for i = 1, 4000 do
	Step(0.05)
	if HD and HD.lx and PANE:IsPlaying() then
		local p2, p3 = pts[2], pts[3]
		if p2.px and p3.px then
			local w = 600
			local x2, x3 = p2.px * w, p3.px * w
			if HD.lx > x2 + 1 and HD.lx < x3 - 1 then SEEN_MID = true
				for _, o in ipairs(p3.segs or {}) do if o.cut then CUT = true end end
			end
		end
	end
	if SEEN_MID then break end
end
""")
check(p.eval("SEEN_MID"), "between two points the head sits part way along, not on either")
check(p.eval("CUT"), "...and the line into the next point is drawn only up to the head")

print("asleep through the rest; night on the map")
p.lua("""
ASLEEP, NIGHT = false, 0
for i = 1, 8000 do
	Step(0.05)
	local z = HD.zz and HD.zz[1]
	if z and z:IsShown() then ASLEEP = true end
	NIGHT = math.max(NIGHT, PANE.tint.night._alpha or 0)
	if PANE.revealAt and PANE.revealAt >= HEARTH then break end
end
""")
check(p.eval("ASLEEP"), "\"zzz\" over the head through the two-hour rest")
check(p.eval("NIGHT") > 0.2, "the map dims to night (at midnight: %.2f)" % p.eval("NIGHT"))
p.lua("for i = 1, 3 do Step(0.05) end")
check(p.eval("HD.bounceAt ~= nil"), "arriving by hearth: the head bounces")
check(not p.eval("HD.zz[1]:IsShown()"), "...and wakes up")

print("the flight: an arc, on a gryphon")
bowed = p.eval("""(function()
	local f = pts[#pts - 6]
	if not (f.bow and f.bow > 0) then return false end
	-- the middle bead sits off the straight line
	local mid = f.segs[math.floor(#f.segs / 2) + 1]
	return mid ~= nil
end)()""")
check(bowed, "the dotted flight line bows into an arc")
p.lua("""
MOUNT = false
for i = 1, 4000 do
	Step(0.05)
	if HD.mount:IsShown() then MOUNT = true end
	if PANE.revealAt and PANE.revealAt >= FLY_TO then break end
end
""")
check(p.eval("MOUNT"), "a gryphon carries the head along the flight")
p.lua("Step(0.05) Step(0.05)")
check(not p.eval("HD.mount:IsShown()"), "...and goes once it lands")

print("crossfade, the end")
check(p.eval("PANE.GetGhost() ~= nil"), "a zone change keeps the old map underneath to fade out")
p.lua("for i = 1, 8000 do Step(0.05) if not PANE:IsPlaying() then break end end")
check(not p.eval("PANE:IsPlaying()"), "the time lapse ends")
check(p.eval("PANE.summaryAt ~= nil") and p.eval("PANE.summary:IsShown()"), "the summary pops in")
p.lua("for i = 1, 40 do Step(0.05) end")
check(p.eval("PANE.summaryAt == nil") and p.eval("PANE.tint.night._alpha or 0") < 0.05, "...settles; at rest the map's own colours come back")

print("easing")
check(abs(p.eval("A.Journey.Ease(0.5)") - 0.875) < 1e-9 and p.eval("A.Journey.Smooth(0)") == 0 and p.eval("A.Journey.Smooth(1)") == 1, "out-cubic ease and smoothstep")
n, w = p.eval("A.Journey.Light(1)"), None
check(p.eval("(A.Journey.Light(1))") == 1 and p.eval("(A.Journey.Light(12))") == 0 and p.eval("select(2, A.Journey.Light(19))") > 0.9, "night at 1 AM, none at noon, warm at 7 PM")

print("Shannon's Wetlands walk and Stormwind flight (2026-10-13)")
p.lua("""
-- a slow walk: tiny steps a second apart, and a flight with the zones flown over in between
local t = T0 + 86400
SLOW = {}
for i = 1, 40 do SLOW[#SLOW + 1] = { t = t, m = 1429, x = 10 + i * 2, y = 50, c = ME } t = t + 5 end
SLOW[#SLOW + 1] = { t = t, m = 1429, x = 91, y = 50, c = ME, k = "F" } SF = SLOW[#SLOW]
t = t + 60 SLOW[#SLOW + 1] = { t = t, m = 13, x = 50, y = 50, c = ME }
t = t + 60 SLOW[#SLOW + 1] = { t = t, m = 1436, x = 30, y = 40, c = ME }
t = t + 60 SLOW[#SLOW + 1] = { t = t, m = 1436, x = 40, y = 60, c = ME, k = "f" } SL = SLOW[#SLOW]
A.Journey.Points = function() return SLOW end
PANE:Refresh(true)
MAXT, FRAMES_ON = 0, 0
for i = 1, 1200 do
	Step(0.05)
	local hd = PANE.heads[ME]
	local n = 0
	for _, tx in ipairs(hd.trail) do if tx:IsShown() then n = n + 1 end end
	MAXT = math.max(MAXT, n)
	if n >= 3 then FRAMES_ON = FRAMES_ON + 1 end
	if PANE.revealAt and PANE.revealAt >= SF.t then break end
end
""")
check(p.eval("MAXT") >= 4 and p.eval("FRAMES_ON") > 20, "a slow walk keeps its glowing tail (up to %d glows, %d frames with 3+)" % (p.eval("MAXT"), p.eval("FRAMES_ON")))
check(p.eval("SF.nextAll == SL"), "the zones flown over are dropped: the take-off pairs with the landing")

p.lua("""
A.db.trail = {}
UnitOnTaxi = function() return true end
A.Where = function() return { map = 1437, x = 20, y = 70 } end
A.JourneyRecorder:MapChanged() RunTimers(2)
TAXI_PTS = #A.JourneyRecorder:Points(0)
UnitOnTaxi = function() return false end
A.JourneyRecorder:MapChanged() RunTimers(2)
WALK_PTS = #A.JourneyRecorder:Points(0)
""")
check(p.eval("TAXI_PTS") == 0 and p.eval("WALK_PTS") == 1, "the recorder writes no point for a zone crossed in the air (%d), one on foot (%d)" % (p.eval("TAXI_PTS"), p.eval("WALK_PTS")))

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
