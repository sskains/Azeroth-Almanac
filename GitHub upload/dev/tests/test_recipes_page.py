"""The Recipes page: cards, the skill-bracket list, badges and the summary (DESIGN 90), offline smoke test.
Run: python3 dev/tests/test_recipes_page.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player, ALL_FILES

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

def spy(name, src):
    if name == "UI/Pages/Trainers.lua":
        src = src.replace("list = W.List(listHolder, {", "list = W.List(listHolder, CaptureOpts {")
        src = src.replace("		local rows, total = CardRows()\n		list:SetData(rows)", "		local rows, total = CardRows()\n		R_ROWS = rows\n		list:SetData(rows)")
        src = src.replace("	local rows, n, total = Collect()\n	local keep", "	local rows, n, total = Collect()\n	R_ROWS = rows\n	local keep")
        src = src.replace("		local ok, b = pcall(Summary)", "		local ok, b = pcall(Summary)\n		SUMMARY = ok and b or tostring(b)")
        src = src.replace("	detail:SetBlocks(DescribeSpell(sel.id, rec), nil, keep)", "	SPELL_BLOCKS = DescribeSpell(sel.id, rec)\n	detail:SetBlocks(SPELL_BLOCKS, nil, keep)")
    return src

p = Player("Alice", files=ALL_FILES, patch=spy)
p.lua("""
function CaptureOpts(t) R_OPTS = t return t end
AzerothAlmanacDB = false
FireEvent("ADDON_LOADED", "AzerothAlmanac")
FireEvent("PLAYER_LOGIN")
RunTimers(5)
local me = A.CharKey()
A.db.chars[me] = A.db.chars[me] or {}
local c = A.db.chars[me]
c.level = 20
c.skills = { Alchemy = { rank = 60, max = 75 } }
c.spells = { [2330] = 1700000000 }
c.recipeDiff = { [2330] = 1 }
A.db.found.spell = {
	[2330] = { name = "Minor Healing Potion", group = "skill:Alchemy", skill = 1, cat = "Potions", reagents = { { 2447, 1 }, { 765, 1 } }, made = 118, c = {} },
	[2331] = { name = "Minor Mana Potion", group = "skill:Alchemy", skill = 25, cost = 100, trainers = { [1215] = 100 }, c = {} },
	[2332] = { name = "Elixir of Fortitude", group = "skill:Alchemy", skill = 175, c = {} },
	[3275] = { name = "Linen Bandage", group = "skill:First Aid", skill = 1, c = {} },
	[9999] = { name = "Fireball", group = "class:MAGE", lvl = 1, c = {} },
}
A.db.found.trainer = { [1215] = { name = "Alchemist Mallory", group = "skill:Alchemy", map = 1429, x = 40, y = 50, zone = "Elwynn Forest" } }
A.Store:ClearShown()
A.QoL = A.QoL or {}
A.QoL.Inventory = A.QoL.Inventory or {}
A.QoL.Inventory.WhoHas = function(_, item)
	if item == 2447 then return { { key = me, total = 5, parts = { bags = 3, bank = 2 } } } end
	if item == 765 then return { { key = me, total = 2, parts = { bags = 2 } } } end
	return {}
end
A.UI:Open("trainers")
RP = A.UI:GetPage("trainers")
RP:Refresh()
function Find(f) for _, r in ipairs(R_ROWS or {}) do if f(r) then return r end end end
function Cards() local t = {} for _, r in ipairs(R_ROWS or {}) do if r.card == "pair" then for _, o in ipairs({ r.a, r.b }) do if o then t[#t + 1] = o.plain end end end end return table.concat(t, ",") end
function Draw() for _, r in ipairs(R_ROWS or {}) do
	local row = Mock("Row") row.icon = Mock("I") row.text = Mock("T") row.right = Mock("R") row.SetHeader = function() end
	R_OPTS.update(row, r)
end end
function BlockText(b) local t = {} for _, x in ipairs(b or {}) do t[#t + 1] = tostring(x[2]) .. "=" .. tostring(x[3]) end return table.concat(t, " | ") end
""")
cards = p.eval("Cards()")
print("  cards:", cards)
check(cards.startswith("Show all"), "the page opens on its cards, Show all first")
check("Alchemy" in cards and "First Aid" in cards and cards.index("Alchemy") < cards.index("First Aid"), "a card per profession, primary ones before First Aid")
check("Fireball" not in cards and "MAGE" not in cards, "class spells stay off the Recipes page")
check("Can learn now" in cards and "Not yet" in cards and "Learned" in cards, "For <you>: Can learn now, Not yet, Learned")
p.lua("Draw()")
check(p.eval("type(SUMMARY) == 'table'") and "You can learn now" in p.eval("BlockText(SUMMARY)") or "can learn" in p.eval("BlockText(SUMMARY)").lower(), "the summary shows what you can learn now")
# open the Alchemy card
p.lua("""
for _, r in ipairs(R_ROWS) do if r.card == 'pair' then for _, o in ipairs({ r.a, r.b }) do if o and o.plain == 'Alchemy' then o.action() end end end end
""")
heads = p.eval("(function() local t = {} for _, r in ipairs(R_ROWS) do if r.header then t[#t + 1] = r.header end end return table.concat(t, ',') end)()")
print("  headers:", heads)
check(heads.startswith("Alchemy") and "Apprentice" in heads and "Expert" in heads, "Alchemy, then the ranks by skill (Apprentice, Expert)")
check("First Aid" not in heads, "only Alchemy in its card")
check(p.eval("Find(function(r) return r.id == 3275 end) == nil"), "no First Aid recipes in the Alchemy card")
p.lua("Draw()")
# badges and difficulty colour
p.lua("""
ROWX = Mock("Row") ROWX.icon = Mock("I") ROWX.text = Mock("T") ROWX.right = Mock("R") ROWX.SetHeader = function() end
local tex
ROWX.CreateTexture = function() local t = Mock("Badge") t.SetTexture = function(_, f) tex = f end return t end
R_OPTS.update(ROWX, Find(function(r) return r.id == 2330 end))
BADGE1 = tex
R_OPTS.update(ROWX, Find(function(r) return r.id == 2331 end))
BADGE2 = tex
""")
check("ReadyCheck-Ready" in (p.eval("BADGE1") or ""), "a learned recipe wears the tick badge")
check("Character-Plus" in (p.eval("BADGE2") or ""), "a recipe you can learn now wears the plus")
# the recipe page: can make now (bags 3 + bank 2 of 2447, 2 of 765) -> 2
p.lua("RP:ShowSpell(2330)")
bt = p.eval("BlockText(SPELL_BLOCKS)")
check("Can make now=2" in bt, "Can make now counts this character's bags and bank (2)")
p.lua("RP:ShowOnly('skill:First Aid')")
check(p.eval("Find(function(r) return r.id == 3275 end) ~= nil") and p.eval("Find(function(r) return r.id == 2330 end) == nil"), "ShowOnly opens one profession")
print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
