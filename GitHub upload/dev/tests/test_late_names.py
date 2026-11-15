"""Creatures known only by their corpse (Modules/Bestiary.lua): named when the game answers, outside.
(2026-11-14, a player: Deadmines discoveries announced days after she was there) a name that comes
more than an hour after the corpse is written quietly, its journal line at the corpse's time; a name
already in the Almanac (a boss's encounter stand-in) is no discovery at all.
Run: python3 dev/tests/test_late_names.py"""
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
B, S = A.Bestiary, A.Store
ALERTS = {}
A:On("DISCOVERY", function(kind, id, rec, text, quiet) if not quiet then ALERTS[#ALERTS + 1] = text end end)
NAMES = {}
B.NameFromGuid = function(guid) return NAMES[guid] end
function Journal(name) local n, at = 0, nil for i, e in ipairs(A.db.journal) do if e.s == name then n, at = n + 1, i end end return n, at end
-- three corpses in a dungeon, names hidden
B:FromCorpse(9001, "Creature-0-1-1-1-9001-A")
B:FromCorpse(9002, "Creature-0-1-1-1-9002-B")
B:FromCorpse(644, "Creature-0-1-1-1-644-C")
-- the boss was announced by its encounter, as a stand-in
S:Discover("creature", -2741, { name = "Rhahk'Zor", boss = true }, "Rhahk'Zor")
ALERTS = {}
""")
check(p.eval("S:Get('creature', 9001).unnamed") is True, "a corpse with its name hidden: an unnamed record")

p.lua('NAMES["Creature-0-1-1-1-9001-A"] = "Defias Miner" RunTimers(600) B:ResolveNames()')
check(p.eval("ALERTS[1]") == "Defias Miner" and p.eval("(Journal('Defias Miner'))") == 1, "named on the way out (10 min later): announced and journalled")

p.lua("""
S:Discover("zone", 1, { name = "Stormwind City" }, "Stormwind City")
ALERTS = {}
for _ = 1, 30 do RunTimers(3600) end
NAMES["Creature-0-1-1-1-9002-B"] = "Goblin Woodcarver" NAMES["Creature-0-1-1-1-644-C"] = "Rhahk'Zor"
B:ResolveNames()
""")
check(p.eval("S:Get('creature', 9002).name") == "Goblin Woodcarver" and not p.eval("S:Get('creature', 9002).unnamed"), "named a day later: the record gets its name")
check(p.eval("#ALERTS") == 0, "...but no alert, a day after the dungeon")
n, at = p.eval("(Journal('Goblin Woodcarver'))"), p.eval("select(2, Journal('Goblin Woodcarver'))")
check(n == 1 and at < p.eval("select(2, Journal('Stormwind City'))"), "...its journal line goes in at the corpse's time, before later lines")
check(p.eval("(Journal(\"Rhahk'Zor\"))") == 1, "a boss already announced by its encounter: no second journal line")
check(p.eval("S:Get('creature', -2741)") is None and p.eval("S:Get('creature', 644).boss") is True, "...and the stand-in still folds into the real record")

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
