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
pts = {}
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

print("opening, Play, speed (2026-10-10)")
p.lua("""
A.db.settings.window.journeyAt = nil
PANE:Hide()
PANE:Show()
RunTimers(0.1)
PANE:GetScript("OnUpdate")(PANE, 0.1)
""")
check(not p.eval("PANE:IsPlaying()"), "opening the pane doesn't start the time lapse")
check(p.eval("PANE.shownMap") == 13, "...it shows the whole journey (on the continent)")
check(p.eval("PANE.playGlow:IsShown()"), "...and Play glows")
check(p.eval("PANE.range:GetText()") == "Today", "the time frame is a drop-down on Today")
p.lua("PANE.play:GetScript('OnClick')(PANE.play)")
check(p.eval("PANE:IsPlaying()") and "Journey_Pause" in (p.eval("PANE.play.tex._tex") or ""), "Play plays, and turns into Pause")
p.lua("PANE:GetScript('OnUpdate')(PANE, 0.1)")
check(not p.eval("PANE.playGlow:IsShown()"), "the glow goes once it's played")
# (1.1.0) 100 ticks, not 300: the time lapse no longer runs for a fixed 80 seconds, it is as long
# as the journey has in it, down to a 20 second floor. 300 ticks ran past the end of a short one,
# which finishes it and clears the kept place; 10 seconds is still partway through the shortest.
p.lua("for i = 1, 100 do NOW = NOW + 0.1 PANE:GetScript('OnUpdate')(PANE, 0.1) end PANE.play:GetScript('OnClick')(PANE.play)")
at = p.eval("A.Journey.KeptPlace('today')")
check(at is not None and 0 < at < 1 and "Journey_Play" in (p.eval("PANE.play.tex._tex") or ""), "Pause keeps the place (%s) and shows Play" % at)
p.lua("PANE:Hide() PANE:Show() RunTimers(0.1)")
check(not p.eval("PANE:IsPlaying()") and p.eval("PANE.shownMap") == 1429, "reopened: at rest where you left off (still in Elwynn)")
p.lua("PANE.faster:GetScript('OnClick')(PANE.faster)")
check(p.eval("PANE.speedText:GetText()") == "2x", "Faster: 2x shown")
p.lua("for i = 1, 5 do PANE.faster:GetScript('OnClick')(PANE.faster) end")
check(p.eval("PANE.speedText:GetText()") == "8x", "...up to 8x, no further")
p.lua("for i = 1, 5 do PANE.slower:GetScript('OnClick')(PANE.slower) end")
check(p.eval("PANE.speedText:GetText()") == "1x", "Slower: down to 1x")

print("whose journey, Yesterday, Larger (2026-10-10)")
p.lua("""
A.db.chars["Bob-Testrealm"] = { name = "Bob", class = "WARRIOR" }
for i = 1, 5 do pts[#pts + 1] = { t = 2700 + i * 60, m = 1436, x = 60, y = 40 + i, c = "Bob-Testrealm" } end
table.sort(pts, function(a, b) return a.t < b.t end)
A.Journey.Points = function(from, char)
	local out = {}
	for _, q in ipairs(pts) do if not char or q.c == char then out[#out + 1] = q end end
	return out
end
A.db.settings.window.journeyAt = nil
PANE:Hide() PANE:Show() RunTimers(0.1)
function Count() local n = 0 for _ in pairs(PANE:GetScript("OnUpdate") and {} or {}) do end return n end
""")
check(p.eval("PANE.who:GetText()") == p.eval("A.CharName(A.CharKey(), true)"), "whose journey: you by default (%s)" % p.eval("PANE.who:GetText()"))
check(p.eval("PANE.range:GetText()") == "Today", "...Today")
p.lua("PANE.who:GetScript('OnClick')(PANE.who) MENU = AzerothAlmanacMenu")
rows = p.eval("(function() local t = {} for i, r in ipairs(MENU.rows) do if r:IsShown() then t[#t + 1] = r.text:GetText() .. (r.tick:IsShown() and ' [x]' or (r.box:IsShown() and ' [ ]' or '')) end end return table.concat(t, ' / ') end)()")
check("Everyone [ ]" in rows and "Bob [ ]" in rows and "[x]" in rows, "the drop-down: Everyone and each character with a tick box, you ticked (%s)" % rows)
p.lua("for i, r in ipairs(MENU.rows) do if r:IsShown() and r.text:GetText() == 'Everyone' then r:GetScript('OnClick')(r) break end end")
check(p.eval("PANE.who:GetText()") == "Everyone" and p.eval("MENU:IsShown()"), "Everyone ticks them all (the menu stays open)")
p.lua("for i, r in ipairs(MENU.rows) do if r:IsShown() and r.text:GetText() == 'Everyone' then r:GetScript('OnClick')(r) break end end")
check(p.eval("PANE.who:GetText()") == p.eval("A.CharName(A.CharKey(), true)"), "Everyone again: back to just you")
p.lua("for i, r in ipairs(MENU.rows) do if r:IsShown() and r.text:GetText() == A.CharName(A.CharKey(), true) then r:GetScript('OnClick')(r) break end end")
check(p.eval("PANE.who:GetText()") == p.eval("A.CharName(A.CharKey(), true)"), "the last one ticked can't be unticked")
p.lua("for i, r in ipairs(MENU.rows) do if r:IsShown() and r.text:GetText() == 'Bob' then r:GetScript('OnClick')(r) break end end")
check(p.eval("PANE.who:GetText()") in ("Everyone", "2 characters"), "Bob ticked too: both (%s)" % p.eval("PANE.who:GetText()"))
p.lua("PANE:Hide() PANE:Show() RunTimers(0.1)")
check(p.eval("PANE.who:GetText()") == p.eval("A.CharName(A.CharKey(), true)"), "reopened: back to you")
p.lua("local real = time time = function(t) if t then return os.time(t) end return real() end")  # (the stub's time() ignores a date table)
y = p.eval("A.Journey.From('yesterday')"); t = p.eval("A.Journey.From('today')")
check(t - y in (82800, 86400, 90000) and p.eval("A.Journey.To('yesterday')") == t, "Yesterday: midnight to midnight")
check([r for r in p.eval("(function() local t = {} for _, r in ipairs(A.Journey.RANGES) do t[#t + 1] = r.key end return table.concat(t, ',') end)()").split(",")] == ["today", "yesterday", "week"], "time frames: Today, Yesterday, Week (Month and All dropped in 1.1.0)")
p.lua("PANE:SetLarge(true)")
check("Journey_Smaller" in (p.eval("PANE.big.tex._tex") or ""), "Larger is a picture button; enlarged it shows Smaller")

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
