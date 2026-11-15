"""Quest counts beside zone names (2026-11-11): how many quests you have in each zone, on the Almanac's Quests page
(gold, beside the heading) and in the game's quest log (QoL/QuestLogCounts.lua). Run: python3 dev/tests/test_quest_zone_counts.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player, ALL_FILES

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

def spy(name, src):
    if name == "UI/Pages/Quests.lua":
        src = src.replace("\tlist:SetData(rows)", "\tQROWS = rows list:SetData(rows)")
    return src

p = Player("Alice", files=ALL_FILES, patch=spy)
p.lua("""
hooksecurefunc = function(a, b, c)
  local t, name, fn = a, b, c
  if type(a) == "string" then t, name, fn = _G, a, b end
  local orig = t[name]
  t[name] = function(...) local r = { orig(...) } fn(...) return unpack(r) end
end
-- the log: Duskwood with three quests, Darkshore with one
LOG = {
  { title = "Duskwood", isHeader = true },
  { title = "Dusky Crab Cakes", questID = 101, level = 20 }, { title = "Deliveries to Sven", questID = 102, level = 23 },
  { title = "The Hermit", questID = 103, level = 25 },
  { title = "Darkshore", isHeader = true },
  { title = "Cave Mushrooms", questID = 201, level = 17 },
}
C_QuestLog.GetNumQuestLogEntries = function() return #LOG end
C_QuestLog.GetInfo = function(i) return LOG[i] end
C_QuestLog.GetLogIndexForQuestID = function(q) for i, e in ipairs(LOG) do if e.questID == q then return i end end end
AzerothAlmanacDB = false FireEvent("ADDON_LOADED", "AzerothAlmanac") FireEvent("PLAYER_LOGIN") RunTimers(5)
Q = A.Quests
QC = A.QoL.QuestLogCounts
""")
counts = p.eval("Q:CountsByZone()")
check(counts["Duskwood"] == 3 and counts["Darkshore"] == 1, "counts by zone heading: Duskwood 3, Darkshore 1")
check(p.eval("Q:ZoneCountsOn()") is True, "on by default")

# the game's quest log: two headings and a quest row, in a scroll frame
p.lua("""
local function Fs(text)
  local fs = CreateFrame("Frame"):CreateFontString()
  fs._text = text fs.GetText = function() return fs._text end fs.IsShown = function() return true end
  fs.GetStringWidth = function() return 80 end
  return fs
end
local function Row(kind, text)
  local f = CreateFrame("Frame") f.IsShown = function() return true end f.GetChildren = function() end
  if kind == "header" then f.ButtonText = Fs(text) else f.Text = Fs(text) end
  return f
end
H1, H2, ROW = Row("header", "Duskwood"), Row("header", "Darkshore"), Row("quest", "[20] Dusky Crab Cakes")
QuestScrollFrame = CreateFrame("Frame") QuestScrollFrame.IsShown = function() return true end
QuestScrollFrame.GetChildren = function() return H1, ROW, H2 end
QC.Paint()
""")
check(p.eval("QC.LabelOf(H1) ~= nil and QC.LabelOf(H1):IsShown()") and p.eval("QC.LabelOf(H1):GetText()") == "(3)", "the game's log: Duskwood (3)")
check(p.eval("QC.LabelOf(H2):GetText()") == "(1)", "...Darkshore (1)")
check(p.eval("QC.LabelOf(ROW) == nil"), "...and nothing on a quest's own row")

# pooled frames: a heading reused for a zone that isn't in your log loses its count
p.lua("H2.ButtonText._text = 'Elwynn Forest' QC.Paint()")
check(not p.eval("QC.LabelOf(H2):IsShown()"), "a heading reused for another zone: its old count goes")

# the log redrawing: the hook paints after it
p.lua("H2.ButtonText._text = 'Darkshore' QC.LabelOf(H2):Hide() QuestLogQuests_Update = function() end QC.Hook() QuestLogQuests_Update() RunTimers(0.1)")
check(p.eval("QC.LabelOf(H2):IsShown()"), "the log's own redraw (QuestLogQuests_Update) brings the counts back")

# switched off
p.lua("A.db.settings.questZoneCounts = false QC.Paint()")
check(not p.eval("QC.LabelOf(H1):IsShown()") and not p.eval("QC.LabelOf(H2):IsShown()"), "switched off: no counts in the game's log")
p.lua("A.db.settings.questZoneCounts = nil")

# the Almanac's Quests page: each zone heading carries how many of its quests are in your log
p.lua("""
A.db.found.quest = {
  [101] = { name = "Dusky Crab Cakes", cat = "Duskwood", lvl = 20, c = {} }, [102] = { name = "Deliveries to Sven", cat = "Duskwood", lvl = 23, c = {} },
  [103] = { name = "The Hermit", cat = "Duskwood", lvl = 25, c = {} }, [104] = { name = "An old one, done", cat = "Duskwood", lvl = 22, c = {} },
  [201] = { name = "Cave Mushrooms", cat = "Darkshore", lvl = 17, c = {} }, [301] = { name = "Done long ago", cat = "Westfall", lvl = 12, c = {} },
}
A.Store:ClearShown()
OK, ERR = pcall(function() A.UI:Open("quests") RunTimers(1) A.UI:GetPage("quests"):ShowStatus(nil) RunTimers(1) end)
HEADS = {}
for _, r in ipairs(QROWS or {}) do if r.header and not r.newHeader then HEADS[r.header] = { inLog = r.inLog, count = r.count } end end
""")
check(p.eval("OK"), "the Quests page builds (%s)" % p.eval("tostring(ERR)"))
check(p.eval("HEADS.Duskwood and HEADS.Duskwood.inLog") == 3 and p.eval("HEADS.Duskwood.count") == 4, "Duskwood: 3 in your log, of the 4 the Almanac knows")
check(p.eval("HEADS.Westfall and HEADS.Westfall.inLog") == 0, "Westfall: none in your log (so no count beside its name)")

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
