"""Murloc Tac Toe: a seasonal champion is offered only during its own holiday (Shannon, 2026-10-22).
Run: python3 dev/tests/test_mtt_seasonal_champions.py

Three Hallow's End champions and two Winter Veil ones. Each shows only while its own holiday is on:
not after it ends, and not during the other one. `/aa mtt season` can override that for trying them
out, but the override must NOT be saved - an older version wrote it to the saved variables, so one
use of it left every seasonal champion offered all year on that character, for good.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player, ALL_FILES

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

p = Player("Alice", files=ALL_FILES, cls="WARRIOR")
p.lua("Q = A.QoL")
p.lua("A.db = A.db or {}; A.db.murloc = A.db.murloc or {}")
# The Hallow's End champions carry no model of their own - they are learnt in game, and the ID is
# kept per character - so without one they are not "known" and the season rule never gets a say.
# Give them one, so what is being tested here is the holiday and nothing else.
p.lua("A.db.murloc.display = { squashling = 1, bombay = 2, roach = 3 }")
p.lua("Q.MurlocTacToe:OnInitialize(A.db)")

HALLOW = ("squashling", "bombay", "roach")
WINTER = ("snowman", "reindeer")
def playable(k):
    return p.eval("Q.MurlocTacToe:Playable(%r)" % k)

print("during Hallow's End")
p.lua('Q.PretendHoliday("HallowsEnd")')
for k in HALLOW:
    check(playable(k) is True, "%s is offered" % k)
for k in WINTER:
    check(playable(k) is False, "%s is not" % k)

print("during the Feast of Winter Veil")
p.lua('Q.PretendHoliday("WinterVeil")')
for k in WINTER:
    check(playable(k) is True, "%s is offered" % k)
for k in HALLOW:
    check(playable(k) is False, "%s is not" % k)

print("with no holiday on at all")
p.lua("Q.PretendHoliday(false)")
for k in HALLOW + WINTER:
    check(playable(k) is False, "%s is put away" % k)
check(playable("murloc") is True, "the everyday champions stay")

print("a champion chosen in season does not linger out of it")
p.lua('Q.PretendHoliday("HallowsEnd")')
p.lua('A.db.murloc.champion = "squashling"')
check(p.eval('Q.MurlocTacToe:Champion() == "squashling"'), "it is yours during the holiday")
p.lua("Q.PretendHoliday(false)")
check(p.eval('Q.MurlocTacToe:Champion() == "murloc"'), "...and the murloc comes back after it")

print("the try-it-out override is not saved")
check(p.eval("A.db.murloc.anySeason == nil"), "nothing named anySeason reaches the saved variables")
check(p.eval("A.db.murloc.seasonShown == nil"), "nor seasonShown")
# and one set by an older version is cleared on login rather than left to haunt the character
p.lua("A.db.murloc.anySeason = true")
p.lua("Q.MurlocTacToe:OnInitialize(A.db)")
check(p.eval("A.db.murloc.anySeason == nil"), "one saved by an older version is cleared on login")
p.lua("Q.PretendHoliday(nil)")

print()
if FAILS:
    print("FAILED: %d" % len(FAILS))
    sys.exit(1)
print("all passed")
