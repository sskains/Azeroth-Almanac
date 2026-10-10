"""Wild Gambit player-against-player, offline: two clients play whole matches through addon
messages. Run: python3 dev/tests/test_wg_pvp.py   (needs: pip install lupa)

Checks (#59 part 2):
  1. new against new: a full match, both boards the same after every move, checksums on every move
  2. old against new: a copy that sends no checksum still plays a full match with a new one
  3. drift: a move whose checksum doesn't match calls the game off on both screens, nothing counted
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


def old_copy(name, src):
    # an Almanac from before the checksum: no MoveSum / SpellSum, so its moves carry none
    if name == "QoL/WildGambit.lua":
        src = src.replace('WG.MoveSum("me", h, cell) or "-"', '"-"').replace('WG.SpellSum("me", cell, cell2) or "-"', '"-"')
        src = src.replace('local sum = f[7] ~= "-" and f[7] or nil', 'local sum = nil')
    return src


def protocols(lo, hi):
    # a copy that plays Wild Gambit protocols lo..hi (writes hi)
    def patch(name, src):
        if name == "QoL/WildGambit.lua":
            src = src.replace('local PREFIX, PROTO = "AzAlmWG", "12"', 'local PREFIX, PROTO = "AzAlmWG", "%d"' % hi)
            src = src.replace("WG.PROTO_MIN, WG.PROTO_MAX = tonumber(PROTO), tonumber(PROTO)", "WG.PROTO_MIN, WG.PROTO_MAX = %d, %d" % (lo, hi))
        return src
    return patch


def pair(old_b=False, cls_a="MAGE", cls_b="WARRIOR", patch_a=None, patch_b=None):
    a = Player("Alice", cls=cls_a, patch=patch_a)
    b = Player("Bob", cls=cls_b, patch=patch_b or (old_copy if old_b else None))
    a.lua(SETUP)
    b.lua("COLLECTION_OFFSET = 100")
    b.lua(SETUP)
    return a, b


def start(a, b, log):
    a.lua('WG = A.WildGambit WG:Challenge("Bob")')
    deliver(a, b, rounds=5, log=log)
    b.lua("Accept()")
    deliver(a, b, rounds=5, log=log)
    a.lua("A.WildGambit:Ready()")
    b.lua("A.WildGambit:Ready()")
    deliver(a, b, rounds=10, log=log)
    return a.eval("Game() ~= nil and Game().pvp ~= nil"), b.eval("Game() ~= nil and Game().pvp ~= nil")


def play_out(a, b, log, edit=None, spells=False):
    """Whoever's turn it is plays its first card on the first open square (casting its spell first
    when `spells` and it has a target), until the board is full."""
    for _ in range(24):
        ga, gb = a.eval("Game()"), b.eval("Game()")
        if ga.over or gb.over:
            break
        mover = a if a.eval("Game().turn") == "me" else b
        mover.lua("PlayTurn()" if spells else "MyMove()")
        deliver(a, b, rounds=3, log=log, edit=edit)
        if a.eval("Game().over") or b.eval("Game().over"):
            break
        same = a.eval("BoardText()").replace("M", "x").replace("B", "y") == b.eval("BoardText()").replace("M", "y").replace("B", "x")
        if not same:
            return False
    return True


def moves(log, who):
    return [t for n, t in log if n == who and "|M|" in t]


print("1. new against new")
a, b = pair()
log = []
ok_a, ok_b = start(a, b, log)
check(ok_a and ok_b, "the match begins on both screens")
same = play_out(a, b, log)
check(same, "both boards the same after every move")
check(a.eval("Game().over") and b.eval("Game().over"), "the match ends on both screens")
ms = moves(log, "Alice") + moves(log, "Bob")
check(len(ms) >= 9 and all(len(m.split("|")) >= 7 and m.split("|")[6] != "-" for m in ms), "every move carries a checksum (%d moves)" % len(ms))
check(not a.eval("A.WildGambit.desyncs") and not b.eval("A.WildGambit.desyncs"), "no false alarms")

print("2. old against new (Bob's copy sends no checksum)")
a, b = pair(old_b=True)
log = []
ok_a, ok_b = start(a, b, log)
check(ok_a and ok_b, "the match begins on both screens")
check(play_out(a, b, log), "both boards the same after every move")
check(a.eval("Game().over") and b.eval("Game().over"), "the match ends on both screens")
check(all(m.split("|")[6] == "-" for m in moves(log, "Bob")), "the old copy's moves carry no checksum")
check(all(m.split("|")[6] != "-" for m in moves(log, "Alice")), "the new copy's moves still carry one (the old copy ignores it)")
check(not a.eval("A.WildGambit.desyncs") and not b.eval("A.WildGambit.desyncs"), "no false alarms")

print("3. drift: a move's checksum doesn't match")
a, b = pair()
log = []
start(a, b, log)
first = a if a.eval("Game().turn") == "me" else b
other = b if first is a else a
first.lua("MyMove()")
def corrupt(src, m):
    f = m["text"].split("|")
    if len(f) >= 7 and f[1] == "M":
        f[6] = "bad0"
        return dict(m, text="|".join(f))
deliver(a, b, rounds=4, log=log, edit=corrupt)
check(other.eval("A.WildGambit.desyncs") == 1, "the receiving screen sees the boards differ")
check(other.eval("Game().over") and first.eval("Game().over"), "the game is called off on both screens")
check(not other.eval("A.WildGambit.D.DB().records.alice") and not other.eval("A.WildGambit.D.DB().records.bob")
      and not first.eval("A.WildGambit.D.DB().records.alice") and not first.eval("A.WildGambit.D.DB().records.bob"), "nothing counted on either screen")

print("4. every class's spell, both ways")
CLASSES = ["WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"]
for i, ca in enumerate(CLASSES):
    cb = CLASSES[(i + 4) % len(CLASSES)]
    a, b = pair(cls_a=ca, cls_b=cb)
    a.lua('A.WildGambit.D.DB().class = %r' % ca)
    b.lua('A.WildGambit.D.DB().class = %r' % cb)
    log = []
    start(a, b, log)
    same = play_out(a, b, log, spells=True)
    spells = [t for n, t in log if "|U|" in t]
    sums = all(len(t.split("|")) >= 7 and t.split("|")[6] != "-" for t in spells)
    over = a.eval("Game().over") and b.eval("Game().over")
    alarms = (a.eval("A.WildGambit.desyncs") or 0) + (b.eval("A.WildGambit.desyncs") or 0)
    check(same and over and sums and alarms == 0 and len(spells) >= 1,
          "%s against %s: %d spells cast, boards agree, match ends, no false alarms" % (ca, cb, len(spells)))
print("5. protocol ranges")
a, b = pair(patch_a=protocols(12, 13))
log = []
ok_a, ok_b = start(a, b, log)
check(any(t.startswith("13|C|") for n, t in log if n == "Alice"), "a 12-13 copy challenges at 13")
check(any("|V|" in t for n, t in log if n == "Bob"), "a 12-only copy answers with its range")
check(any(t.startswith("12|C|") for n, t in log if n == "Alice"), "the challenge goes again at 12")
check(ok_a and ok_b and play_out(a, b, log) and a.eval("Game().over"), "and the match is played through at 12")
check(all(t.startswith("12|") for n, t in log if "|M|" in t), "every move written in 12")

a, b = pair(patch_b=protocols(11, 11))
log = []
a.lua('A.WildGambit:Challenge("Bob")')
deliver(a, b, rounds=8, log=log)
chat_a = " ".join(a.eval("table.concat(CHAT, ' ')").split())
chat_b = " ".join(b.eval("table.concat(CHAT, ' ')").split())
check("They need to update" in chat_a, "a newer copy is told the other player needs to update")
check("Update your Almanac" in chat_b, "the older copy is told to update")
check(a.eval("A.WildGambit.net") is None and a.eval("Game()") is None, "no game starts, nothing left waiting")

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
