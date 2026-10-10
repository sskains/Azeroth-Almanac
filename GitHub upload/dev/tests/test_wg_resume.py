"""Wild Gambit across a /reload (#50), offline. Run: python3 dev/tests/test_wg_resume.py

  practice: the game comes back as it was (board, hands, whose turn) and plays on
  player match: the reloaded side asks for what it missed; moves made meanwhile, and a move of its
                own that never left, both arrive; the match plays to the end, boards agreeing
  too late / not kept: the other side is told at once ("gone") and cancels, nothing counted
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player, deliver, HERE

SETUP = open(os.path.join(HERE, "wg_setup.lua")).read()
FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

def player(name, saved=None, offset=0, cls="MAGE", now=None):
    p = Player(name, cls=cls)
    if saved:
        p.L.globals().SAVED_DB = saved
    if now:
        p.lua("NOW = %d" % now)
    p.lua("COLLECTION_OFFSET = %d" % offset)
    p.lua(SETUP)
    return p

def reload(p, **kw):
    """the same character after a /reload: a fresh runtime with its saved data"""
    return player(p.name, saved=p.eval("SavedText()"), **kw)

def mirror(a, b):
    return a.eval("BoardText()").replace("M", "x").replace("B", "y") == b.eval("BoardText()").replace("M", "y").replace("B", "x")

print("a practice game")
a = player("Alice")
a.lua("""
WG = A.WildGambit
WG:ShowPick()
WG.nextOpponent = { npc = 1500, name = "Hogger", reaction = "hostile" }
WG:Start(nil)
for i = 1, 3 do
	if Game().turn == "me" then MyMove() else RunTimers(2) end
	RunTimers(2)
end
-- (reloaded on your own turn, so the gambler doesn't move on before the boards are compared)
for i = 1, 5 do if Game().turn == "me" then break end RunTimers(2) end
""")
before = a.eval("BoardText()")
turn = a.eval("Game().turn")
hands = (a.eval("#Game().hands.me"), a.eval("#Game().hands.bot"))
check(a.eval("A.WildGambit.D.DB().resume ~= nil"), "kept while it's played")
a2 = reload(a)
check(a2.eval("Game() ~= nil and not Game().over"), "after a /reload the game is back")
check(a2.eval("BoardText()") == before, "the same board (%s)" % before)
check(a2.eval("Game().turn") == turn and (a2.eval("#Game().hands.me"), a2.eval("#Game().hands.bot")) == hands, "same turn and hands")
a2.lua("for i = 1, 12 do if Game().over then break end if Game().turn == 'me' then MyMove() else RunTimers(2) end RunTimers(2) end")
check(a2.eval("Game().over") and not a2.eval("Game().cancelled"), "it plays on to the end")
check(a2.eval("A.WildGambit.D.DB().resume") is None, "and is forgotten once it's over")
a3 = reload(a2)
check(a3.eval("Game()") is None, "nothing to pick up after it ended")

print("a player match")
def pvp():
    a = player("Alice")
    b = player("Bob", offset=100, cls="WARRIOR")
    log = []
    a.lua('A.WildGambit:Challenge("Bob")'); deliver(a, b, rounds=5, log=log)
    b.lua("Accept()"); deliver(a, b, rounds=5, log=log)
    a.lua("A.WildGambit:Ready()"); b.lua("A.WildGambit:Ready()"); deliver(a, b, rounds=10, log=log)
    for _ in range(3):
        (a if a.eval("Game().turn") == "me" else b).lua("MyMove()")
        deliver(a, b, rounds=3)
    return a, b
def play_out(a, b):
    for _ in range(12):
        if a.eval("Game().over") or b.eval("Game().over"):
            break
        (a if a.eval("Game().turn") == "me" else b).lua("MyMove()")
        deliver(a, b, rounds=3)
        if not (a.eval("Game().over") or b.eval("Game().over")) and not mirror(a, b):
            return False
    return True

a, b = pvp()
# Bob reloads; meanwhile it's Alice's move (or Bob's, then Alice's): what Alice sends is lost
if b.eval("Game().turn") == "me":
    b.lua("MyMove()"); deliver(a, b, rounds=3)
b2 = reload(b)
a.lua("MyMove()")
a.outbox()  # (sent while Bob was reloading: lost)
check(b2.eval("Game() ~= nil and Game().pvp ~= nil"), "Bob's match is back after his /reload")
deliver(a, b2, rounds=6)
check(mirror(a, b2), "he asks for what he missed, and Alice's move arrives: boards agree")
check(play_out(a, b2) and a.eval("Game().over") and b2.eval("Game().over"), "the match plays to the end, boards agreeing")
check(not a.eval("Game().cancelled") and not b2.eval("Game().cancelled"), "...counted, not cancelled")

a, b = pvp()
if b.eval("Game().turn") != "me":
    a.lua("MyMove()"); deliver(a, b, rounds=3)
b.lua("MyMove()")
b3 = reload(b)  # (his move was still in his outbox: it never left)
b.outbox()
deliver(a, b3, rounds=8)
check(mirror(a, b3), "his own move that never left reaches Alice after the reload: boards agree")
check(play_out(a, b3) and a.eval("Game().over"), "...and the match plays on to the end")

print("too late, or not kept")
a, b = pvp()
b4 = player("Bob", offset=100, cls="WARRIOR")   # (a /reload that kept nothing)
if a.eval("Game().turn") == "me":
    a.lua("MyMove()")
else:
    a.lua("FireEvent('PLAYER_REGEN_ENABLED')")
    a.lua("RunTimers(16)")  # (a heartbeat)
deliver(a, b4, rounds=6)
check(a.eval("Game().over") and a.eval("Game().cancelled"), "the other side hears 'gone' at once and cancels (not counted)")
a, b = pvp()
b5 = reload(b, now=100 + 400)  # (back after more than 4.5 minutes)
check(b5.eval("Game()") is None, "a player match older than four and a half minutes isn't picked up")

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
