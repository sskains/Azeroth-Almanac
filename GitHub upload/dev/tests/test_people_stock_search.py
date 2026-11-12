"""People page: a search over a person's Training and For sale lists (2026-11-08). Run: python3 dev/tests/test_people_stock_search.py"""
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
        src = src.replace("local function DescribePerson(p)", "function DescribePerson(p)")
    return src

p = Player("Alice", files=ALL_FILES, patch=spy)
p.lua("""
AzerothAlmanacDB = false
FireEvent("ADDON_LOADED", "AzerothAlmanac")
FireEvent("PLAYER_LOGIN")
RunTimers(5)
local me = A.CharKey()
A.db.chars[me] = A.db.chars[me] or {}
A.db.chars[me].level = 30
A.db.found.spell = {
	[2660] = { name = "Rough Sharpening Stone", group = "skill:Blacksmithing", skill = 1, trainers = { [5511] = 10 }, c = {} },
	[3115] = { name = "Justicar's Belt", group = "skill:Blacksmithing", skill = 150, trainers = { [5511] = 3825 }, c = {} },
}
A.db.found.trainer = { [5511] = { name = "Therum Deepforge", group = "skill:Blacksmithing", teaches = { 2660, 3115 }, c = {} },
	[5512] = { name = "Other Smith", group = "skill:Blacksmithing", teaches = { 2660 }, c = {} } }
A.db.found.item = A.db.found.item or {}
A.db.found.item[4293] = { name = "Pattern: Hillman's Leather Vest", c = {} }
A.db.found.item[4294] = { name = "Pattern: Hillman's Belt", c = {} }
A.db.found.item[2880] = { name = "Weak Flux", c = {} }
A.db.found.merchant = { [5511] = { name = "Therum Deepforge", checked = 1700000000, n = 1, reaction = 4, c = {},
	stock = { { id = 4293, price = 650 }, { id = 4294, price = 450 }, { id = 2880, price = 100, stack = 5 } } } }
A.Store:ClearShown()
PERSON = { npc = 5511, name = "Therum Deepforge", recs = { trainer = A.db.found.trainer[5511], merchant = A.db.found.merchant[5511] }, group = { family = "trainer" } }
NOBODY = { npc = 9999, name = "Nobody", recs = {}, group = { family = "other" } }
function Look(person)
	local out = { banners = {}, items = {}, spells = {}, small = {}, search = false }
	for _, b in ipairs(DescribePerson(person)) do
		
		if b[1] == "banner" then out.banners[#out.banners + 1] = b[2] end
		if b[1] == "small" then out.small[#out.small + 1] = b[2] end
		if b[1] == "slots" then
			for _, e in ipairs(b[2]) do
				if e.item then out.items[#out.items + 1] = e.item end
				if e.spell then out.spells[#out.spells + 1] = e.spell end
			end
		end
	end
	out.search = A.UI:GetPage("townsfolk"):StockSearchShown()
	out.banners = table.concat(out.banners, "|") out.small = table.concat(out.small, "|")
	out.items = table.concat(out.items, ",") out.spells = table.concat(out.spells, ",")
	return out
end
PAGE = A.UI:GetPage("townsfolk")
function Type(text)
	local box = PAGE:StockSearchBox()
	box:SetText(text)
	box._scripts.OnTextChanged(box)
end
-- the page as it's drawn, so a typed search redraws it
OPENED, OPEN_ERR = pcall(function() A.UI:Open("townsfolk") RunTimers(1) PAGE:ShowPerson(5511) RunTimers(1) end)
""")
check(p.eval("OPENED"), "the People page opens on someone who teaches and sells (%s)" % p.eval("tostring(OPEN_ERR)"))
p.lua("R = Look(PERSON)")
check(p.eval("R.search"), "a search box for their lists, in the window's top bar (always in view, 2026-11-11)")
check("Training (2)" in p.eval("R.banners") and "For sale (3)" in p.eval("R.banners"), "no search: every line, counted as before (%s)" % p.eval("R.banners"))

p.lua('Type("belt") R = Look(PERSON)')
check("Training (1 of 2)" in p.eval("R.banners") and p.eval("R.spells") == "3115", "\"belt\": Training keeps Justicar's Belt, counted 1 of 2 (%s)" % p.eval("R.banners"))
check("For sale (1 of 3)" in p.eval("R.banners") and p.eval("R.items") == "4294", "...For sale keeps the belt pattern, 1 of 3")

p.lua('Type("PATTERN") R = Look(PERSON)')
check(p.eval("R.items") == "4293,4294" and p.eval("R.spells") == "", "capitals don't matter: \"PATTERN\" finds both patterns and no training")
check("Nothing they teach matches your search." in p.eval("R.small"), "...and says nothing they teach matches")

p.lua('Type("zzz") R = Look(PERSON)')
check(p.eval("R.items") == "" and "Nothing they sell matches your search." in p.eval("R.small"), "nothing matches: says so for what they sell")

p.lua('Type("") R = Look(PERSON)')
check("Training (2)" in p.eval("R.banners") and "For sale (3)" in p.eval("R.banners") and p.eval("R.items") == "4293,4294,2880", "cleared: everything back")

p.lua("R = Look(NOBODY)")
check(not p.eval("R.search"), "someone with nothing to teach or sell: no search box")

# a search doesn't follow you to the next person
p.lua('Type("flux")')
p.lua('OK2 = pcall(function() PAGE:ShowPerson(5512) RunTimers(1) end)')
check(p.eval("OK2") and p.eval("PAGE:StockSearchBox():GetText()") == "", "opening another person clears the search")
p.lua('PAGE:ShowPerson(5511) RunTimers(1) R = Look(PERSON)')
check("For sale (3)" in p.eval("R.banners"), "...and the first person's lists are whole again")

# (2026-11-11, Shannon: "crusader" found no one, though a vendor sold the plans) the page's own search
# also finds people by what they sell or teach, and opens their lists already searched
p.lua("""
PAGE:Search("hillman") RunTimers(0.5)
""")
check(p.eval("PAGE:Matches(5511)") and not p.eval("PAGE:Matches(5512)"), "the People search \"hillman\" finds Therum, who sells Pattern: Hillman's Belt (by what he sells, not his name)")
p.lua("PAGE:ShowPerson(5511) RunTimers(1) R = Look(PERSON)")
check(p.eval("PAGE:StockSearchBox():GetText()") == "hillman", "...and opening him carries the search into his lists")
check(p.eval("R.items") == "4293,4294", "...so his For sale list shows just the Hillman's patterns (%s)" % p.eval("R.items"))
p.lua('PAGE:Search("therum") RunTimers(0.5) PAGE:ShowPerson(5512) RunTimers(0.5) PAGE:ShowPerson(5511) RunTimers(1) R = Look(PERSON)')
check(p.eval("PAGE:StockSearchBox():GetText()") == "" and "For sale (3)" in p.eval("R.banners"), "found by his name: his lists open whole")
p.lua('PAGE:Search("justicar") RunTimers(0.5) PAGE:ShowPerson(5512) RunTimers(0.5) PAGE:ShowPerson(5511) RunTimers(1)')
check(p.eval("PAGE:StockSearchBox():GetText()") == "justicar", "found by what he teaches (Justicar's Belt): his lists open searched too")
p.lua('PAGE:Search("") RunTimers(0.5)')

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
