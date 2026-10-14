"""The People page's cards (0.70.1): sections of small cards per kind of person, a card opens its list. Run: python3 dev/tests/test_people_cards.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player, ALL_FILES

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

def spy(name, src):
    if name == "UI/Pages/Townsfolk.lua":
        src = src.replace("	list:SetPoint(\"TOPLEFT\", left, \"TOPLEFT\", 0, -32)", "	PEOPLE_LIST = list\n	list:SetPoint(\"TOPLEFT\", left, \"TOPLEFT\", 0, -32)")
        src = src.replace("	list = W.List(left, {", "	list = W.List(left, CaptureOpts {")
    return src

p = Player("Alice", files=ALL_FILES, patch=spy)
p.lua("""
function CaptureOpts(t) PEOPLE_OPTS = t return t end
AzerothAlmanacDB = false
FireEvent("ADDON_LOADED", "AzerothAlmanac")
FireEvent("PLAYER_LOGIN")
RunTimers(5)
-- NPC ids from the hidden database: 911 and 912 warrior trainers, 198 a mage trainer, 295 an innkeeper, 352 a flight master
A.db.found.townsfolk = {
	[911] = { name = "Warrior Trainer One", zone = "Elwynn Forest", c = {} },
	[912] = { name = "Warrior Trainer Two", zone = "Dun Morogh", c = {} },
	[198] = { name = "Mage Trainer", zone = "Elwynn Forest", c = {} },
	[295] = { name = "An Innkeeper", zone = "Elwynn Forest", c = {} },
	[352] = { name = "A Flight Master", zone = "Elwynn Forest", c = {} },
}
A.db.found.flight = { ["Goldshire, Elwynn Forest"] = { zone = "Elwynn Forest", c = {} } }
A.db.found.npc = { [9001] = { name = "A Quest Giver", gives = { 100 }, zone = "Elwynn Forest", c = {} } }
A.Store:ClearShown()
A.UI:Open("townsfolk")
local page = A.UI:GetPage("townsfolk")
page:Refresh()
local function Rows() return PEOPLE_LIST and PEOPLE_LIST:Data() or {} end
local function Cards()
	local out, sections = {}, {}
	for _, r in ipairs(Rows()) do
		if r.card == "section" then sections[#sections + 1] = r.header end
		if r.card == "pair" then
			for _, o in ipairs({ r.a, r.b }) do if o then out[o.plain] = o end end
		end
	end
	return out, sections
end
CARDS, SECTIONS = Cards()
ALL_ROW = nil
for _, r in ipairs(Rows()) do if r.card == "all" then ALL_ROW = r end end
WARRIOR = CARDS["Warrior"] and CARDS["Warrior"].count
FIRST_SECTION = SECTIONS[1]
HAS_FLIGHT = CARDS["Flight paths"] ~= nil
HAS_QUEST = CARDS["Quest givers"] ~= nil
HAS_INN = CARDS["Innkeepers"] ~= nil
NO_PRIEST = CARDS["Priest"] == nil
CREST = CARDS["Warrior"] and tostring(CARDS["Warrior"].icon):find("Crest_WARRIOR") ~= nil
-- open the Warrior card: the list holds only warrior trainers, flat
-- every card row draws through the page's own update (the shared pair cards and the banner)
FILLED, DRAW_ERR = 0, nil
for _, r in ipairs(Rows()) do
	local row = Mock("Row") row.icon = Mock("I") row.text = Mock("T") row.right = Mock("R") row.SetHeader = function() end
	local ok, err = pcall(PEOPLE_OPTS.update, row, r)
	if not ok then DRAW_ERR = tostring(err) end
	for _, c in ipairs(row.halves or {}) do if c:IsShown() then FILLED = FILLED + 1 end end
end
CARDS["Warrior"].action()
local rows = Rows()
LIST_N, LIST_OTHER, LIST_HEADERS = 0, 0, 0
for _, r in ipairs(rows) do
	if r.npc then
		LIST_N = LIST_N + 1
		if r.npc ~= 911 and r.npc ~= 912 then LIST_OTHER = LIST_OTHER + 1 end
	end
	if r.header then LIST_HEADERS = LIST_HEADERS + 1 end
end
-- the back arrow's work: the cards again
page:Refresh()
-- a person opened from another page: their card's list
page:ShowPerson(198)
local rows2 = Rows()
MAGE_ONLY = 0
for _, r in ipairs(rows2) do if r.npc then MAGE_ONLY = MAGE_ONLY + 1 end end
-- flight paths
page:ShowNode("Goldshire, Elwynn Forest")
NODE_ROWS = 0
for _, r in ipairs(Rows()) do if r.node then NODE_ROWS = NODE_ROWS + 1 end end
""")
check(p.eval("ALL_ROW") is not None, "the page opens on its cards, with a Show all banner")
check(p.eval("FIRST_SECTION") == "Class trainers", "Class trainers is the first section (%s)" % p.eval("FIRST_SECTION"))
check(str(p.eval("WARRIOR") or "").startswith("2"), "the Warrior card counts its two trainers (%s)" % p.eval("WARRIOR"))
check(p.eval("CREST") is True, "a class card wears the painted class crest")
check(p.eval("NO_PRIEST") is True, "a kind you haven't met has no card")
check(p.eval("HAS_INN") is True, "the Innkeepers card is there")
check(p.eval("HAS_FLIGHT") is True, "the Flight paths card is there")
check(p.eval("HAS_QUEST") is True, "the Quest givers card is there")
check(p.eval("LIST_N") == 2 and p.eval("LIST_OTHER") == 0, "a card opens a list of just its people (%s rows, %s others)" % (p.eval("LIST_N"), p.eval("LIST_OTHER")))
check(p.eval("LIST_HEADERS") == 0, "a card's list is flat, with no group heading")
check(p.eval("MAGE_ONLY") == 1, "a person opened from elsewhere shows their own card's list (%s)" % p.eval("MAGE_ONLY"))
check(p.eval("NODE_ROWS") == 1, "a flight path opens its own list")
check(p.eval("DRAW_ERR") is None, "every card row draws without an error (%s)" % p.eval("DRAW_ERR"))
check(p.eval("FILLED") >= 4, "the pair cards fill (%s halves)" % p.eval("FILLED"))
print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
