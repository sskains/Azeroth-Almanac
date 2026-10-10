"""The Journey's time lapse follows you zone by zone, then pulls back to the continent (2026-10-10).
Run: python3 dev/tests/test_journey.py"""
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
-- three maps: two zones side by side on one continent
local INFO = { [1429] = { name = "Elwynn Forest", mapType = 3, parentMapID = 13 }, [1436] = { name = "Westfall", mapType = 3, parentMapID = 13 },
	[13] = { name = "Eastern Kingdoms", mapType = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2 } }
C_Map.GetMapInfo = function(m) return INFO[m] end
C_Map.GetMapArtLayers = function(m) return INFO[m] and { { layerWidth = 1000, layerHeight = 660, tileWidth = 256, tileHeight = 256 } } or nil end
C_Map.GetMapArtLayerTextures = function(m) return INFO[m] and { 1, 2, 3 } or nil end
local RECT = { [1429] = { left = 1000, right = 0, top = 1000, bottom = 0 }, [1436] = { left = 2000, right = 1000, top = 1000, bottom = 0 },
	[13] = { left = 4000, right = -4000, top = 4000, bottom = -4000 } }
A.Townsfolk = A.Townsfolk or {}
A.Townsfolk.MapRect = function(m) return RECT[m] end
local me = A.CharKey()
local pts = {}
for i = 1, 10 do pts[#pts + 1] = { t = 1000 + i * 60, m = 1429, x = 40 + i, y = 50, c = me } end
for i = 1, 10 do pts[#pts + 1] = { t = 2000 + i * 60, m = 1436, x = 40 + i, y = 50, c = me } end
A.Journey.Points = function() return pts end
PANE = A.Widgets.JourneyPane(UIParent, { full = true })
PANE:Refresh(true)
START = PANE.shownMap
local up = PANE:GetScript("OnUpdate")
SEEN = {}
for i = 1, 4000 do
	NOW = (NOW or 100) + 0.1
	up(PANE, 0.1)
	if PANE.shownMap and not SEEN[PANE.shownMap] then SEEN[PANE.shownMap] = i end
	if not PANE:IsPlaying() then break end
end
END = PANE.shownMap
""")
check(p.eval("START") == 1429, "the time lapse starts on the first point's zone (Elwynn)")
check(p.eval("SEEN[1436] ~= nil"), "it moves on to Westfall when the journey does")
check(p.eval("SEEN[1436] ~= nil and SEEN[1429] < SEEN[1436]"), "Elwynn first, then Westfall")
check(p.eval("not PANE:IsPlaying()"), "the time lapse ends")
check(p.eval("END") == 13, "at the end it pulls back to the continent (Eastern Kingdoms)")
p.lua("PANE:Refresh(false)")
check(p.eval("PANE.shownMap") == 13, "at rest the whole journey shows on the continent")
print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
