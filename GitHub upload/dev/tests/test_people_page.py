"""A person's page on People: Wild Gambit first under its logo, trained spells ticked. Run: python3 dev/tests/test_people_page.py"""
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
local c = A.db.chars[me]
c.level = 30
c.skills = { Blacksmithing = { rank = 120, max = 150 } }
c.spells = { [2660] = 1700000000 }
A.db.found.spell = {
	[2660] = { name = "Rough Sharpening Stone", group = "skill:Blacksmithing", skill = 1, trainers = { [5511] = 10 }, c = {} },
	[3115] = { name = "Justicar's Belt", group = "skill:Blacksmithing", skill = 150, trainers = { [5511] = 3825 }, c = {} },
}
A.db.found.trainer = { [5511] = { name = "Therum Deepforge", group = "skill:Blacksmithing", teaches = { 2660, 3115 }, c = {} } }
A.Store:ClearShown()
local person = { npc = 5511, name = "Therum Deepforge", recs = { trainer = A.db.found.trainer[5511] }, group = { family = "trainer" } }
BLOCKS = DescribePerson(person)
FIRST = BLOCKS[1] and BLOCKS[1][1]
for _, b in ipairs(BLOCKS) do
	if b[1] == "slots" then
		for _, e in ipairs(b[2]) do
			if e.spell == 2660 then DONE_KNOWN = e.done end
			if e.spell == 3115 then DONE_OTHER = e.done end
		end
	end
end
-- the logo block draws
local d = A.Widgets.Detail(CreateFrame("Frame"), 0)
DREW = pcall(d.SetBlocks, d, BLOCKS)
""")
check(p.eval("FIRST") == "logo", "Wild Gambit comes first, under its logo (first block: %s)" % p.eval("FIRST"))
check(p.eval("DONE_KNOWN") is True, "a spell you've trained carries the tick")
check(not p.eval("DONE_OTHER"), "a spell you haven't trained has no tick")
check(p.eval("DREW") is True, "the page draws with the logo block")
print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
