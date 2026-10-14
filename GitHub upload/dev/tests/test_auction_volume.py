"""How many of an item sell a day, for every item (2026-10-13, Shannon). Run: python3 dev/tests/test_auction_volume.py"""
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
AV = A.QoL.AuctionVolume
T = 1800000000
GetServerTime = function() return T end
-- Fletcher's Gloves (7348): not made by any recipe the Almanac knows
function Scan(list) AV:OnScanStart() for _, l in ipairs(list) do AV:OnListing(7348, l[1], l[2], l[3], l[4]) end AV:OnScanDone() end
local all = { { 1, 12000, 'Ann', 4 }, { 1, 12000, 'Bob', 4 }, { 1, 12500, 'Cid', 3 }, { 1, 13000, 'Dee', 4 } }
Scan(all)
FIRST = AV:DailyVolume(7348)
T = T + 2400
Scan({ all[2], all[3], all[4] })             -- Ann's (12 h+ left) went: sold
T = T + 2400
Scan({ all[3], all[4] })                     -- Bob's went too
T = T + 600
Scan({ all[4] })                             -- Cid's had under 30 minutes...? (3 = medium: 30 min - 2 h) gone in 10 min: sold
""")
check(p.eval("FIRST") is None, "one scan: not enough to say yet")
per = p.eval("(AV:DailyVolume(7348))")
# 3 sold in 5400 s watched -> 48 a day
check(per is not None and abs(per - 48) < 0.5, "three sold over an hour and a half watched: ~48 a day (%s)" % per)
p.lua("T = T + 5000 Scan({})")
check(abs(p.eval("(AV:DailyVolume(7348))") - 4 / 10400 * 86400) < 0.5, "Dee's (12 h+) gone after 83 min: counted too (4 over 2.9 h watched)")
check(p.eval("A.QoL.db.auctionVolume.realms[next(A.QoL.db.auctionVolume.realms)].allSnap ~= nil"), "the listings are kept compactly between scans")

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
