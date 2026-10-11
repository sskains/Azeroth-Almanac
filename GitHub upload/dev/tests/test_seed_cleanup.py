"""The dungeon seeder's test records come out once at load. Run: python3 dev/tests/test_seed_cleanup.py"""
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
AzerothAlmanacDB = { version = 999, settings = {}, journal = {},
	found = { instance = { [1] = { seeded = true }, [2] = { bosses = { a = { seeded = true }, b = {} } } },
		creature = { [5] = { seeded = true }, [6] = { name = "Wolf" } } },
	chars = { x = { runs = { [1] = { seeded = true }, [2] = { n = 1 } } } } }
FireEvent("ADDON_LOADED", "AzerothAlmanac")
FireEvent("PLAYER_LOGIN")
RunTimers(3)
local f = A.db.found
R = { f.instance[1] == nil, f.instance[2] ~= nil and f.instance[2].bosses.a == nil, f.instance[2].bosses.b ~= nil,
	f.creature[5] == nil, f.creature[6] ~= nil, A.db.chars.x.runs[1] == nil, A.db.chars.x.runs[2] ~= nil, A.db.seedCleared == true }
""")
r = p.eval("R")
check(r[1] and r[2] and r[4] and r[6], "seeded dungeons, bosses, creatures and runs are taken out")
check(r[3] and r[5] and r[7], "your own records stay")
check(r[8], "done once (seedCleared)")
print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
