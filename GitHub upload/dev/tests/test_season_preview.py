"""`/aa season`: pretending a holiday is on, everywhere at once (Shannon, 2026-10-21), offline.
Run: python3 dev/tests/test_season_preview.py

The three games share one calendar check (`ns.HolidayNow` in WindowUtil), so one pretend holiday
has to reach all of them - the seasonal dress of Wild Gambit, Murloc Tac Toe and Gem Match, and
Murloc Tac Toe's seasonal champions. It must also not be saved: a pretend holiday that outlived
its session would be mistaken for a bug months later.
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
# Wild Gambit reads its own saved table to find the "Holiday boards" switch, and without it
# every holiday question answers "no" - so give it one, as a logged-in client would.
p.lua("Q.WildGambit:OnInitialize({ wildGambit = { records = {} } })")

print("the calendar, untouched")
real = p.eval("Q.HolidayNow()")
check(p.eval("Q.PretendHoliday ~= nil"), "the pretend is there to be set")
check(p.eval("Q.pretending == nil"), "nothing is pretended to begin with")

print("pretending Winter Veil")
p.lua('Q.PretendHoliday("WinterVeil")')
check(p.eval('Q.HolidayNow() == "WinterVeil"'), "every seasonal check now answers Winter Veil")
check(p.eval('Q.WildGambit:BackKey() == "WinterVeil"'), "Wild Gambit deals the Winter Veil card back")
check(p.eval('Q.WildGambit:TableKey() == "WinterVeil"'), "...and lays the Winter Veil table")
check(p.eval('Q.WildGambit:HolidayBoard() == "WinterVeil"'), "...and the Winter Veil board")

print("pretending Hallow's End")
p.lua('Q.PretendHoliday("HallowsEnd")')
check(p.eval('Q.HolidayNow() == "HallowsEnd"'), "the answer changes at once, not a minute later")
# Hallow's End has no card back or table of its own: those must fall back, not blank out
check(p.eval('Q.WildGambit:BackKey() ~= "HallowsEnd"'), "a holiday with no card back keeps the chosen one")
check(p.eval('Q.WildGambit:TableKey() ~= "HallowsEnd"'), "...and the chosen table")

print("pretending no holiday at all")
p.lua("Q.PretendHoliday(false)")
check(p.eval("Q.HolidayNow() == nil"), "false means no holiday, which is a real answer")
check(p.eval('Q.WildGambit:HolidayBoard() == nil'), "so the board is whichever one was picked")

print("and back to the calendar")
p.lua("Q.PretendHoliday(nil)")
check(p.eval("Q.HolidayNow()") == real, "clearing it gives the calendar's own answer again")

print("each game can be told the season moved")
for mod in ("WildGambit", "MurlocTacToe", "GemMatch"):
    check(p.eval("type(Q.%s.SeasonChanged) == 'function'" % mod), "%s takes SeasonChanged" % mod)
    # with no window built it must do nothing rather than error
    ok = p.eval("select(1, pcall(Q.%s.SeasonChanged, Q.%s))" % (mod, mod))
    check(ok is True, "...and is safe to call before its window exists")

print("the command")
check(p.eval("type(A.SeasonPreview) == 'function'"), "/aa season has something to call")
for arg in ("", "winterveil", "hallowsend", "plain", "off", "nonsense"):
    ok = p.eval("select(1, pcall(A.SeasonPreview, %r))" % arg)
    check(ok is True, "/aa season %s doesn't error" % (arg or "(on its own)"))
check(p.eval("Q.pretending == nil"), "...and 'off' really did leave it following the calendar")

print("the Almanac's own windows dress too")
check(p.eval("type(Q.SeasonDecor) == 'function'"), "there is a decoration to ask for")
check(p.eval("type(Q.DressForSeason) == 'function'"), "...and a way to ask for it")
p.lua('Q.PretendHoliday("WinterVeil")')
check(p.eval("Q.SeasonDecor() ~= nil"), "Winter Veil has decoration")
check(p.eval('Q.SeasonDecor().strip ~= nil'), "...snow along the top")
check(p.eval('Q.SeasonDecor().corner ~= nil'), "...frost in the corners")
check(p.eval('Q.SeasonDecor().motes ~= nil'), "...and flakes drifting inside")
p.lua('Q.PretendHoliday("HallowsEnd")')
check(p.eval("Q.SeasonDecor() == nil"), "a holiday with no decoration painted yet gets none")
p.lua("Q.PretendHoliday(false)")
check(p.eval("Q.SeasonDecor() == nil"), "and no holiday means none")

print("the switch in Settings turns it off")
p.lua('Q.PretendHoliday("WinterVeil")')
# the harness does not load saved variables, so make the table the game would have
p.lua("A.db = A.db or {}; A.db.settings = A.db.settings or {}")
p.lua("A.db.settings.seasonalDecor = false")
check(p.eval("Q.SeasonDecor() == nil"), "off means off, holiday or not")
p.lua("A.db.settings.seasonalDecor = nil")
check(p.eval("Q.SeasonDecor() ~= nil"), "...and unset means on, the default")

print("dressing a window")
# it must be safe on any frame, and asking twice must not dress it twice
ok = p.eval("select(1, pcall(Q.DressForSeason, CreateFrame('Frame')))")
check(ok is True, "a plain frame can be dressed without erroring")
check(p.eval("select(1, pcall(Q.RedressAll))") is True, "redrawing them all is safe")
p.lua("Q.PretendHoliday(nil)")

print("nothing of it is saved")
# the pretend lives on the namespace, not in the saved variables
saved = p.eval("(function() for k in pairs(A.db or {}) do if tostring(k):lower():find('pretend') then return true end end return false end)()")
check(saved is False, "no pretend holiday is written to the saved variables")

print()
if FAILS:
    print("FAILED: %d" % len(FAILS))
    sys.exit(1)
print("all passed")
