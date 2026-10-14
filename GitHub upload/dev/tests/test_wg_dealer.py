"""Wild Gambit: the goblin dealer and the plank under him both deal a new hand (2026-10-13).
Run: python3 dev/tests/test_wg_dealer.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player, ALL_FILES

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

p = Player("Alice", files=ALL_FILES)
p.lua('AzerothAlmanacDB = false FireEvent("ADDON_LOADED", "AzerothAlmanac") FireEvent("PLAYER_LOGIN") RunTimers(10)')
p.lua('WG = A.QoL.WildGambit WG:Toggle() RunTimers(1)')
p.lua('''
F = nil for _, f in ipairs(FRAMES) do if f.plank and f.plaque then F = f end end
DEALS = 0 local real = WG.Shuffle WG.Shuffle = function(...) DEALS = DEALS + 1 end
''')
check(p.eval("F ~= nil"), "the dealer has a plank button")
p.lua('F._scripts.OnClick(F) F.plank._scripts.OnClick(F.plank)')
check(p.eval("DEALS") == 2, "clicking the goblin and the plank both deal: %s" % p.eval("DEALS"))
p.lua('F.plank._scripts.OnEnter(F.plank)')
check(p.eval("F.hover") == True, "hovering the plank lights the goblin")
p.lua('F.plank._scripts.OnLeave(F.plank)')
check(p.eval("F.hover") == False, "leaving the plank puts it out")

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
