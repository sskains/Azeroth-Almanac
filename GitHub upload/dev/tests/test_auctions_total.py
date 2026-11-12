"""Characters > Auctions (2026-11-11): the heading shows what the posted auctions are worth, the prices listed
(buyout, else the bid) and what's left after the auction house's 5% cut. Run: python3 dev/tests/test_auctions_total.py"""
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
IW = A.QoL.InventoryWindow
-- the screenshot's seven: 4s x4, 5s, 17s x2 (buyouts), and one more with only a bid of 2s
ITEMS = { { buyout = 400 }, { buyout = 400 }, { buyout = 400 }, { buyout = 400 }, { buyout = 500 }, { buyout = 1700 }, { buyout = 1700 }, { bid = 200 } }
T, AFTER = IW.AuctionsWorth(ITEMS)
E1, E2 = IW.AuctionsWorth({})
""")
check(p.eval("T") == 5700, "the total adds every listed price, a bid where there's no buyout (57s)")
check(p.eval("AFTER") == 5415, "...and 5% less after the auction house's cut (54s 15c)")
check(p.eval("E1") == 0 and p.eval("E2") == 0, "no auctions: nothing")

# the tab draws with the total in its heading
p.lua("""
GetMoneyString = function(c) return tostring(c) .. 'c' end GetCoinTextureString = GetMoneyString -- (the stub has no money text)
local me = A.CharKey()
INV = A.QoL.Inventory
OK, ERR = pcall(function()
  A.UI:Open("characters") RunTimers(1)
  local c = INV:Me() c.auctions = { time = time() - 60, items = { { 2840, 1, buyout = 400, ends = time() + 3600 }, { 2841, 1, buyout = 1700, ends = time() + 3500 } } }
  A.UI:GetPage("characters"):ShowInventory(c.key, "auctions") RunTimers(1)
end)
""")
check(p.eval("OK"), "the Auctions tab draws with the total (%s)" % p.eval("tostring(ERR)"))

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
