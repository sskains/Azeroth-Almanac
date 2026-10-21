"""Wild Gambit: Execute's reach and Mind Control's limit, old protocols included.
Run: python3 dev/tests/test_wg_abilities.py

Execute (protocol 14) removes any enemy card with fewer spikes than your biggest card on the
board; before that it only reached a neighbour of a bigger card of yours. Mind Control takes a
card of 10 spikes or fewer; it was 8. A match with an older copy plays by the older rules.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

p = Player("Alice")
p.lua("""
WL, WG = A.QoL.WildLogic, A.WildGambit
EX, MC = WL.ABILITIES.WARRIOR, WL.ABILITIES.PRIEST
function C(n, e, s, w) return { name = "c", s = { n, e, s, w }, total = n + e + s + w } end
function Even(t) local q = t / 4 return C(q, q, q, q) end   -- a card of `t` spikes in all
-- my big card at 1, their card at 9: opposite corners, nowhere near each other
function Far(mine, theirs)
	return { [1] = { card = Even(mine), owner = "me" }, [9] = { card = Even(theirs), owner = "bot" } }
end
function Proto(n) WG.net = n and { proto = n } or nil end
""")

print("Execute reaches across the board (protocol 14)")
p.lua("B = Far(12, 8)")
check(p.eval("WL.CanTarget(B, EX, 9, 'me')"), "an enemy card of 8 against your biggest of 12, three squares away")
p.lua("B = Far(12, 12)")
check(not p.eval("WL.CanTarget(B, EX, 9, 'me')"), "the same size is not fewer: refused")
p.lua("B = Far(8, 12)")
check(not p.eval("WL.CanTarget(B, EX, 9, 'me')"), "bigger than your biggest: refused")
p.lua("B = { [9] = { card = Even(4), owner = 'bot' } }")
check(not p.eval("WL.Usable(B, EX, 'me')"), "nothing of yours on the board: Execute can't be used at all")
p.lua("B = Far(12, 8) B[9].shield = true")
check(not p.eval("WL.CanTarget(B, EX, 9, 'me')"), "a shielded card is still safe")
p.lua("B = Far(12, 8) B[9].frozen = true")
check(not p.eval("WL.CanTarget(B, EX, 9, 'me')"), "a frozen card can't be touched")

print("your biggest card is the one on the board now")
# a frozen card is nobody's: it must not set the threshold
p.lua("B = Far(20, 8) B[1].frozen = true B[3] = { card = Even(4), owner = 'me' }")
check(not p.eval("WL.CanTarget(B, EX, 9, 'me')"), "your frozen 20 doesn't count: only your 4 does, so their 8 is safe")
p.lua("B = Far(20, 8) B[1].owner = 'bot' B[3] = { card = Even(12), owner = 'me' }")
check(p.eval("WL.CanTarget(B, EX, 9, 'me')"), "their 20 is theirs: your 12 sets the reach, their 8 can be taken")

print("the card is removed and its owner draws again")
p.lua("B = Far(12, 8) OUT = WL.Use(B, EX, 9, 'me')")
check(p.eval("B[9]") is None, "the card leaves the board")
check(p.eval("OUT.removed and OUT.removed.cell == 9 and OUT.removed.owner == 'bot'"), "it is reported removed, with its owner (who is dealt a new card)")
check(p.eval("OUT.removed.from") == 1, "the striker is your biggest card, wherever it stands")
check(p.eval("#OUT.captured") == 0, "nothing is captured: Execute removes, it does not take")

print("a match with an older copy keeps the old Execute")
p.lua("Proto(13) B = Far(12, 8)")
check(p.eval("WL.OldExecute()"), "protocol 13: the old rule is in force")
check(not p.eval("WL.CanTarget(B, EX, 9, 'me')"), "no longer reaches the far corner")
p.lua("B = { [5] = { card = Even(12), owner = 'me' }, [6] = { card = Even(8), owner = 'bot' } }")
check(p.eval("WL.CanTarget(B, EX, 6, 'me')"), "a neighbour of a bigger card of yours still goes")
p.lua("OUT = WL.Use(B, EX, 6, 'me')")
check(p.eval("OUT.removed.from") == 5, "the neighbour strikes")
p.lua("Proto(nil)")
check(not p.eval("WL.OldExecute()"), "back on the newest protocol")

print("Mind Control stops at 10 spikes (was 8)")
check(p.eval("MC.max") == 10, "the ability says 10")
p.lua("B = Far(4, 10)")
check(p.eval("WL.CanTarget(B, MC, 9, 'me')"), "a card of exactly 10 can be taken")
p.lua("B = Far(4, 12)")
check(not p.eval("WL.CanTarget(B, MC, 9, 'me')"), "12 is beyond it")
p.lua("B = Far(4, 10) OUT = WL.Use(B, MC, 9, 'me')")
check(p.eval("B[9].owner") == "me" and p.eval("OUT.captured[1] and OUT.captured[1].mc"), "the card changes hands (it is not removed)")

print("a match with an older copy keeps Mind Control at 8")
p.lua("Proto(13) B = Far(4, 10)")
check(p.eval("WL.OldMC()") and not p.eval("WL.CanTarget(B, MC, 9, 'me')"), "protocol 13: 10 is refused")
p.lua("B = Far(4, 8)")
check(p.eval("WL.CanTarget(B, MC, 9, 'me')"), "8 still goes")
check(p.eval("WL.SmallMax(MC)") == 8 and p.eval("WL.SmallMax(WL.ABILITIES.MAGE)") == 10,
      "the limit the screen shows follows the match: Mind Control 8, Polymorph still 10")
p.lua("Proto(nil)")
check(p.eval("WL.SmallMax(MC)") == 10, "and 10 again on the newest protocol")

print("what the spell card says")
check("fewer spikes than your biggest" in p.eval("EX.short"), "Execute's card describes the new reach")
check("10 spikes or fewer" in p.eval("MC.short") and "10 spikes or fewer" in p.eval("MC.text"),
      "Mind Control's card says 10")
# (the targeting hint itself is a file-local in WildGambit.lua: it is checked in game)

print()
if FAILS:
    print("FAILED: %d" % len(FAILS))
    sys.exit(1)
print("all passed")
