"""Quests page, in your quest log: Abandon, the tracker tick box, shift-click, and redrawing when quests
change (2026-10-13, Shannon). Run: python3 dev/tests/test_quest_log_actions.py"""
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
-- the game's quest log: two quests, one watched; the classic API
LOG = { [101] = 1, [202] = 2 }
WATCHED = { [1] = true }
C_QuestLog.GetLogIndexForQuestID = function(q) return LOG[q] end
C_QuestLog.GetQuestWatchType = nil
C_QuestLog.AddQuestWatch, C_QuestLog.RemoveQuestWatch, C_QuestLog.SetAbandonQuest = nil, nil, nil
IsQuestWatched = function(i) return WATCHED[i] and true or false end
AddQuestWatch = function(i) WATCHED[i] = true end
RemoveQuestWatch = function(i) WATCHED[i] = nil end
GetNumQuestWatches = function() local n = 0 for _ in pairs(WATCHED) do n = n + 1 end return n end
MAX_WATCHABLE_QUESTS = 2
SELECTED = nil
SelectQuestLogEntry = function(i) SELECTED = i end
ABANDONING = nil
SetAbandonQuest = function() ABANDONING = SELECTED end
GetAbandonQuestName = function() return "Cycle of Rebirth" end
POPUP = nil
StaticPopup_Show = function(which, a) POPUP = which .. ":" .. tostring(a) end
T = A.QuestTracking
""")
check(p.eval("T.Tracked(101)") and not p.eval("T.Tracked(202)"), "reads which quests are on the tracker")
p.lua("T.Toggle(202)")
check(p.eval("WATCHED[2] == true"), "the tick box puts a quest on the tracker")
p.lua("LOG[303] = 3 PRINTED = nil local real = A.Print A.Print = function(m) PRINTED = m end T.Toggle(303) A.Print = real")
check(p.eval("WATCHED[3] == nil") and "full" in (p.eval("PRINTED") or ""), "a full tracker says so instead (%s)" % p.eval("PRINTED"))
p.lua("T.Toggle(101)")
check(p.eval("WATCHED[1] == nil"), "...and takes one off")

print("the page")
p.lua("""
A.UI:Toggle() RunTimers(1) A.UI:Open("quests") RunTimers(1)
local actions
for _, f in ipairs(FRAMES) do if f.abandon and f.share then actions = f end end
ACT = actions
if actions then actions.qid = 202 actions.abandon:GetScript("OnClick")(actions.abandon) end
""")
check(p.eval("ACT ~= nil"), "the page has an Abandon button beside Share")
check(p.eval("ABANDONING") == 2 and p.eval("POPUP") == "ABANDON_QUEST:Cycle of Rebirth", "Abandon selects the quest and asks the game's own confirmation (%s)" % p.eval("POPUP"))
p.lua("""
SEEN = {}
local real = A.UI.pages and nil
local Current, IsShown = A.UI.Current, A.UI.IsShown
A.UI.Current = function() return "quests" end
A.UI.IsShown = function() return true end
ERR = nil
for _, ev in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_WATCH_UPDATE", "QUEST_LOG_UPDATE" }) do
	local ok, e = pcall(FireEvent, ev, 202) if not ok then ERR = e end
end
RunTimers(1)
A.UI.Current, A.UI.IsShown = Current, IsShown
""")
check(p.eval("ERR") is None and (p.eval("TIMER_ERRORS") or 0) == 0, "quest changes redraw the list without errors")

print("abandons and hand-ins show at once")
p.lua("""
Q = A.Quests
Q.SetStatus(202, "a", true) Q.SetStatus(101, "a", true)
GetAbandonQuest = nil
C_QuestLog.GetAbandonQuest = function() return 202 end
Q:Abandoned()
S1 = Q:MyStatus(202)
FireEvent("QUEST_TURNED_IN", 101, 100, 0)
S2 = Q:MyStatus(101)
""")
check(p.eval("S1") == "x", "abandoning marks the quest abandoned at once (was ~6 s)")
check(p.eval("S2") == "d", "handing in marks it done at once")

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
