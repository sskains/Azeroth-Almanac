"""Wild Gambit: Hall of Thanes' Restless Thanes (DESIGN 103). Run: python3 dev/tests/test_wg_thanes.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player, HERE

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

p = Player("Alice")
p.lua("""
WL, WD = A.QoL.WildLogic, A.QoL.WildDungeons
function C(n, e, s, w) return { name = "c", s = { n, e, s, w }, total = n + e + s + w } end
function Fresh() return { rules = { haunt = { me = 2, bot = 2 } } } end
""")

print("the event")
p.lua("B = {} OUT = WD.Apply('thanes', B, { me = {}, bot = {} }, {}, WL.Random(1))")
check(p.eval("B.rules.haunt.me == 2 and B.rules.haunt.bot == 2 and OUT.rule == 'haunt'"), "Restless Thanes haunts each player's next two cards")
check(p.eval("WD.BY_KEY.thanes.event") == "Restless Thanes" and p.eval("WD.BY_KEY.thanes.corner") is True, "Hall of Thanes' event is Restless Thanes, its card waits at the corner")
check(p.eval("WD.UNUSED.anvil ~= nil and WD.E.anvil ~= nil and WD.BY_KEY.anvil == nil"), "Anvil Oath is kept (unused): its rules stay, it's never rolled or listed")
p.lua("B = { rules = { haunt = { me = 1, bot = 0 } } }")
check(not p.eval("WD.Can('thanes', B, {}, {})"), "not again while the spirits are still restless")

print("the counter-capture")
# enemy (bot) card at 5 with east side 6; I play at 6 with west side 3: theirs is stronger
p.lua("B = Fresh() B[5] = { card = C(1, 6, 1, 1), owner = 'bot' } GOT = WL.Place(B, 6, C(1, 1, 1, 3), 'me')")
check(p.eval("B[6].owner") == "bot" and p.eval("GOT[1] and GOT[1].counter and GOT[1].from == 5 and GOT[1].side == 2"),
      "placed beside a stronger enemy side: taken by it (struck from its east side)")
p.lua("B = Fresh() B[5] = { card = C(1, 3, 1, 1), owner = 'bot' } GOT = WL.Place(B, 6, C(1, 1, 1, 3), 'me')")
check(p.eval("B[6].owner") == "me" and p.eval("#GOT") == 0, "a tie: nothing either way")
p.lua("B = Fresh() B.rules.ties = true B[5] = { card = C(1, 3, 1, 1), owner = 'bot' } GOT = WL.Place(B, 6, C(1, 1, 1, 3), 'me')")
check(p.eval("B[5].owner") == "me" and p.eval("B[6].owner") == "me", "with Thorns a tie still captures for you, and never counters")
# I take 5 (my west 7 > its east 2), but 9 below (bot, north 8) beats my south 1: my capture stands, my card goes
p.lua("""B = Fresh() B[5] = { card = C(1, 2, 1, 1), owner = 'bot' } B[9] = { card = C(8, 1, 1, 1), owner = 'bot' }
GOT = WL.Place(B, 6, C(1, 1, 1, 7), 'me')""")
check(p.eval("B[5].owner") == "me" and p.eval("B[6].owner") == "bot" and p.eval("GOT[#GOT].counter and GOT[#GOT].from == 9"),
      "your own captures stand; the stronger neighbour still takes the card")
p.lua("""B = Fresh() B[3] = { card = C(1, 1, 4, 1), owner = 'bot' } B[9] = { card = C(9, 1, 1, 1), owner = 'bot' }
GOT = WL.Place(B, 6, C(1, 1, 1, 1), 'me')""")
check(p.eval("#GOT") == 1 and p.eval("GOT[1].from") == 9 and p.eval("GOT[1].margin") == 8, "several stronger: one capture, by the biggest margin")
p.lua("B = Fresh() B[5] = { card = C(1, 6, 1, 1), owner = 'bot' } B.ankh = 'me' GOT = WL.Place(B, 6, C(1, 1, 1, 3), 'me')")
check(p.eval("B[6].owner") == "me" and p.eval("GOT[1].saved") and p.eval("B.ankh") is None, "Reincarnation brings it straight back (the ankh is spent)")
p.lua("B = Fresh() B[5] = { card = C(1, 6, 1, 1), owner = 'bot', stone = true } GOT = WL.Place(B, 6, C(1, 1, 1, 3), 'me')")
check(p.eval("B[6].owner") == "bot", "a stone (Petrify) card still strikes back")
p.lua("B = Fresh() B[5] = { card = A.QoL.WildDungeons.ICE, frozen = true, ice = true } GOT = WL.Place(B, 6, C(0, 0, 0, 0), 'me')")
check(p.eval("B[6].owner") == "me", "ice and frozen squares don't strike")
p.lua("B = Fresh() B.rules.chain = true B[5] = { card = C(1, 6, 1, 1), owner = 'bot' } B[7] = { card = C(1, 1, 1, 1), owner = 'me' } GOT = WL.Place(B, 6, C(1, 1, 1, 3), 'me')")
check(p.eval("#GOT") == 1 and p.eval("B[7].owner") == "me", "no chain: the counter takes one card and stops")

print("two cards each, then it's over")
p.lua("""B = Fresh()
WL.Place(B, 1, C(1, 1, 1, 1), 'me') WL.Place(B, 9, C(1, 1, 1, 1), 'bot') WL.Place(B, 3, C(1, 1, 1, 1), 'me')
LEFT = B.rules.haunt and B.rules.haunt.bot
WL.Place(B, 7, C(1, 1, 1, 1), 'bot')
B[5] = { card = C(1, 6, 1, 1), owner = 'bot' } GOT = WL.Place(B, 6, C(1, 1, 1, 3), 'me')""")
check(p.eval("LEFT") == 1, "after three cards the other player still has one haunted card")
check(p.eval("B.rules.haunt") is None and p.eval("B[6].owner") == "me", "after two each: the rule is gone, no more counters")
p.lua("B = { rules = { haunt = { me = 1, bot = 1 } }, traps = { [6] = 'bot' } } WL.Place(B, 6, C(1, 1, 1, 1), 'me')")
check(p.eval("B.rules.haunt.me") == 0, "a card walking into a trap still uses up a haunted turn")

print("the practice gambler")
# two equal squares (edges, no captures either way), but one sits beside my strong east side
p.lua("""
function Board() local B = Fresh() for i = 1, 9 do if i ~= 6 and i ~= 8 then B[i] = { card = C(1, 1, 1, 1), owner = 'me' } end end
	B[5] = { card = C(1, 9, 1, 1), owner = 'me' } return B end
PICKS, PLAIN = {}, {}
for seed = 1, 12 do
	local _, c = WL.BotMove(Board(), { C(1, 1, 1, 1) }, 'bot', {}, WL.Random(seed)) PICKS[c] = (PICKS[c] or 0) + 1
	local B = Board() B.rules = nil
	local _, c2 = WL.BotMove(B, { C(1, 1, 1, 1) }, 'bot', {}, WL.Random(seed)) PLAIN[c2] = (PLAIN[c2] or 0) + 1
end""")
check(p.eval("PICKS[8]") == 12, "haunted: it never walks into the counter (square 8 every time, %s)" % p.eval("PICKS[8]"))
p.lua("BB = Board() GOT6 = WL.Place(BB, 6, C(1, 1, 1, 1), 'bot')")
check(p.eval("GOT6[1] and GOT6[1].counter") is True, "(square 6 really is the trap: a card there is taken back)")
p.lua("B2 = WL.CopyBoard(Fresh()) B2.rules.haunt.me = 0")
check(p.eval("Fresh().rules.haunt.me") == 2, "trying moves on a copy leaves the real count alone")

print("on the table (a practice game)")
t = Player("Bob")
t.lua(open(os.path.join(HERE, "wg_setup.lua")).read())
t.lua("""
-- the event's show runs on OnUpdate tweens: step every frame's OnUpdate along with the timers
local run = RunTimers
function RunTimers(dt)
	local steps = math.max(1, math.floor((dt or 0) / 0.05))
	for _ = 1, steps do
		local list = {} for i, f in ipairs(FRAMES) do list[i] = f end
		for _, f in ipairs(list) do local fn = f._scripts.OnUpdate if fn and f._shown then pcall(fn, f, 0.05) end end
		run(0.05)
	end
end
WG = A.WildGambit
WG:ShowPick()
WG.nextOpponent = { npc = 1500, name = "Hogger", reaction = "hostile" }
WG:Start(nil)
for i = 1, 4 do if Game().turn == "me" then break end RunTimers(2) end
MyMove() RunTimers(2)
for i = 1, 4 do if Game().turn == "me" then break end RunTimers(2) end
A.db.settings.debug = true
Game().flying = 0 Game().eventBusy = nil
WG:DebugDungeon("thanes") RunTimers(9)
HAUNT = Game().board.rules and Game().board.rules.haunt and true or false
MIST = Game().dun and Game().dun.mist ~= nil
TIMER_ERRORS = 0
for i = 1, 14 do if Game().over then break end if Game().turn == 'me' then MyMove() else RunTimers(2) end RunTimers(2) end
RunTimers(5)
""")
check(t.eval("HAUNT") and t.eval("MIST"), "fired: the board is haunted and the mist is over it")
check(t.eval("Game().board.rules == nil or Game().board.rules.haunt == nil"), "after the cards are played the haunting is over")
check(t.eval("Game().over") and (t.eval("TIMER_ERRORS") or 0) == 0, "the game plays to the end with no errors (%s)" % t.eval("tostring(LAST_TIMER_ERROR)"))
check(t.eval("Game().dun.mist") is None, "the mist has gone")
print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
