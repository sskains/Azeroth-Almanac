"""People page: their Wild Gambit card where the logo was, or a faded preview marked "Not earned yet"
(Shannon, 2026-10-15, DESIGN 125). Run: python3 dev/tests/test_people_card.py"""
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
WG = A.QoL.WildGambit
PV = WG.PreviewCard(3011, { name = "Bena Winterhoof", level = 30, display = 4321 })
""")
check(p.eval("PV ~= nil and PV.preview == true and PV.name == 'Bena Winterhoof'"), "a preview card for someone not beaten yet")
check(p.eval("PV.tier") == 2, "...the card a first win would give (tier %s)" % p.eval("PV.tier"))
check(p.eval("WG:CardFor(3011) == nil"), "...and it isn't added to your cards")
p.lua("""
A.Store:Discover("townsfolk", 3011, { name = "Bena Winterhoof", title = "Expert Alchemist" }, nil, A.Where(), true)
CALLED = 0
local real = WG.PreviewCard
WG.PreviewCard = function(...) CALLED = CALLED + 1 return real(...) end
OK, ERR = pcall(function() A.UI:Open("townsfolk") RunTimers(1) A.UI:GetPage("townsfolk"):ShowPerson(3011) RunTimers(1) end)
""")
check(p.eval("OK"), "the People page opens the person with the card block (%s)" % p.eval("tostring(ERR)"))
check(p.eval("CALLED") >= 1, "...not beaten yet: the faded preview card is drawn")

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
