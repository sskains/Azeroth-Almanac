"""Quests page: the quest chain tree and the quest giver's face (Shannon, 2026-10-15, DESIGN 124).
Run: python3 dev/tests/test_quest_chain.py"""
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
A.DB = A.DB or {} A.DB.quest = A.DB.quest or {}
-- 90001 -> 90002 -> 90003 -> { 90004, 90005 }; 90005 -> 90006; 90009 alone
local Q = A.DB.quest
Q[90001] = { 4, 1, 0, nil, nil, "90002" }
Q[90002] = { 5, 1, 0, nil, nil, "90003" }
Q[90003] = { 6, 1, 0, nil, nil, "90004,90005" }
Q[90004] = { 8, 1, 0 }
Q[90005] = { 7, 1, 0, nil, nil, "90006" }
Q[90006] = { 9, 1, 0 }
Q[90009] = { 9, 1, 0 }
for _, id in ipairs({ 90001, 90002, 90003, 90009 }) do A.Store:Discover("quest", id, { name = "Quest " .. id }, nil, A.Where(), true) end
C_QuestLog.GetTitleForQuestID = function(id) return id == 90006 and "The Sixth" or nil end
C_QuestLog.GetQuestInfo = nil
PAGE = A.UI:GetPage("quests")
""")
check(p.eval("PAGE.Chain(90009) == nil"), "a quest on its own: no chain section (Shannon: disappear)")
p.lua("CH = PAGE.Chain(90002)")
check(p.eval("CH ~= nil and #CH.rows") == 6, "the whole chain, before and after: 6 quests (%s)" % p.eval("CH and #CH.rows"))
check(p.eval("CH.step") == 2 and p.eval("CH.total") == 5, "step 2 of 5 (%s of %s)" % (p.eval("CH.step"), p.eval("CH.total")))
check(p.eval("CH.branches") is True, "...and it branches")
order = p.eval("(function() local t = {} for _, r in ipairs(CH.rows) do t[#t + 1] = r.id .. ':' .. r.depth end return table.concat(t, ' ') end)()")
check(order == "90001:0 90002:0 90003:0 90005:1 90006:1 90004:1", "a straight run stays flat, the branches indent (lowest level first): %s" % order)
p.lua("""
for _, r in ipairs(CH.rows) do if r.id == 90003 then KIDS = r.kids end end
""")
check(p.eval("KIDS") == 2, "the branching quest has a fold arrow (2 branches)")

print("the giver's face")
p.lua("""
A.Store:Discover("townsfolk", 3441, { name = "Melor Stonehoof" }, nil, A.Where(), true)
A.Store:Get("townsfolk", 3441).display = 1234
PAINTED = nil
SetPortraitTextureFromCreatureDisplayID = function(tex, d) PAINTED = d end
local q = A.Store:Get("quest", 90002)
q.giver = { id = 3441, kind = "npc", name = "Melor Stonehoof" }
PAGE:ShowQuest(90002)
""")
check(p.eval("PAINTED") == 1234, "Melor Stonehoof's own face on the Gives it slot (display %s)" % p.eval("PAINTED"))

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
