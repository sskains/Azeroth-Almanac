"""/aa xp [name|target]: asks another Almanac player how far they are through their level, the same
question as the right-click menu entry, and says why when it can't ask. Run: python3 dev/tests/test_slash_xp.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player, ALL_FILES, deliver

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

LOGIN = 'AzerothAlmanacDB = false FireEvent("ADDON_LOADED", "AzerothAlmanac") FireEvent("PLAYER_LOGIN") RunTimers(5)'
a, b = Player("Alice", files=ALL_FILES), Player("Bob", files=ALL_FILES)
a.lua(LOGIN)
b.lua(LOGIN + """
UnitLevel = function() return 20 end
UnitXP = function() return 3000 end
UnitXPMax = function() return 10000 end
AzerothAlmanacDB.settings.peers.xpShare = "all"
""")
a.outbox(), b.outbox()

def slash(p, arg):
    p.lua('CHAT = {} SlashCmdList.AZEROTHALMANAC(%r)' % arg)
    return "\n".join(str(v) for v in p.L.globals().CHAT.values())

def hello(p, sender, games):
    p.receive([{"prefix": "AzAlmHi", "text": "I|1.5.0|" + games}], sender)

# no target and no name: how to use it
out = slash(a, "xp")
check("/aa xp <name>" in out, "no name and no target: says how to use it")
check(not a.outbox(), "...and asks nobody")

# someone the Almanac hasn't met
out = slash(a, "xp Nobody")
check("isn't a known Almanac player" in out, "an unknown name: says so")
check(not a.outbox(), "...and sends nothing")

# yourself
out = slash(a, "xp Alice")
check("That's you" in out, "your own name: points at your experience bar")

# a copy that hasn't said it can answer (no capability list)
hello(a, "Carol", "")
out = slash(a, "xp Carol")
check("hasn't said it can answer" in out, "an old copy with no capability list: says so")
check(not a.outbox(), "...and sends nothing")

# Bob runs the Almanac and can answer
hello(a, "Bob", "xp:1-1")
out = slash(a, "xp Bob")
sent = a.outbox()
check("Asked Bob" in out, "a known player: asks")
check(any(m["text"] == "Q|xp" and m["target"] == "Bob" for m in sent), "...the question goes to Bob by whisper")
b.receive(sent, "Alice")
a.lua("CHAT = {}")
deliver(a, b)
out = "\n".join(str(v) for v in a.L.globals().CHAT.values())
check("Bob is level 20, 30% of the way to 21" in out, "...and Bob's answer is printed (%r)" % out[:120])

# asking again straight away
out = slash(a, "xp Bob")
check("a moment ago" in out, "asking again at once: wait for an answer")

# the target, when it's a player at the top level
a.lua("""
UnitExists = function(u) return u == "player" or u == "target" end
UnitIsPlayer = function(u) return u == "player" or u == "target" end
UnitIsUnit = function(x, y) return x == y end
local real = UnitName
UnitName = function(u) if u == "target" then return "Dave", nil end return real(u) end
UnitLevel = function(u) if u == "target" then return 60 end return 30 end
GetMaxPlayerLevel = function() return 60 end
""")
out = slash(a, "xp")
check("already at the highest level" in out, "a target at the top level: nothing to ask")

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
