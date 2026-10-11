"""The Characters page's Story tab (Shannon, 2026-10-10), offline. Run: python3 dev/tests/test_characters_page.py
  the hero row (level, class crest, faction banner, the adventure strip), what they found first as
  cards, no realm, nothing the plate above already says, no level list"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player, ALL_FILES

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

def spy(name, src):
    if name == "UI/Pages/Characters.lua":
        src += "\nCHAR_DESCRIBE = Describe\n"
    return src

p = Player("Alice", files=ALL_FILES, patch=spy)
p.lua("""
AzerothAlmanacDB = false
FireEvent("ADDON_LOADED", "AzerothAlmanac")
FireEvent("PLAYER_LOGIN")
RunTimers(5)
KEY = A.CharKey()
local c = A.db.chars[KEY]
c.level, c.class, c.classFile, c.race, c.raceFile, c.faction, c.realm = 25, "Paladin", "PALADIN", "Human", "Human", "Alliance", "Olaris"
A.db.found.creature = { [1] = { name = "Wolf", b = KEY, c = { [KEY] = true } }, [2] = { name = "Bear", b = KEY, c = { [KEY] = true } } }
A.db.found.zone = { [1429] = { name = "Elwynn Forest", b = KEY, c = { [KEY] = true } } }
A.db.found.item = { [5] = { name = "Sword", b = "Bob-Testrealm", c = {} } }
A.Store:ClearShown()
B = CHAR_DESCRIBE({ key = KEY, c = c })
function Text()
	local t = {}
	for _, b in ipairs(B) do
		if b[1] == "slots" then for _, e in ipairs(b[2]) do t[#t + 1] = "card:" .. e.name .. "=" .. (e.note or "") end
		else t[#t + 1] = tostring(b[1]) .. ":" .. tostring(b[2]) .. ":" .. tostring(b[3]) end
	end
	return table.concat(t, " | ")
end
""")
t = p.eval("Text()")
check(p.eval("B[1][1]") == "frame", "the Story starts with the hero row (a picture, not text)")
h = p.eval("B[1][2]")
p.lua("HEIGHT = B[1][3](500)")
check(h.meds[1].big.GetText(h.meds[1].big) == "25", "level medallion: 25")
check("Crest_PALADIN" in (h.meds[2].icon._tex or ""), "class medallion: the Paladin crest")
check(h.meds[3].label.GetText(h.meds[3].label) == "Alliance", "faction medallion: Alliance")
check(h.chips[3].num.GetText(h.chips[3].num) == "1" and h.chips[3].what.GetText(h.chips[3].what) == "zones", "the adventure strip: 1 zone")
check("Realm" not in t and "Olaris" not in t, "no realm (WoW Forever has none)")
check("Last seen" not in t and "Last played" not in t, "nothing the plate above already says")
check("Levels" not in t and "First to discover" not in t, "no level list, no title over the cards")
check("card:Creatures=2 found first" in t and "card:Zones=1 found first" in t and "card:Items" not in t, "found first: a card per kind with a count (%s)" % t)
print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
