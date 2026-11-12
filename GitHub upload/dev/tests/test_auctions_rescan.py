"""Characters > Auctions keeps up with new auctions (2026-11-11): after posting, cancelling or opening the auction house's
Auctions tab, the owned list is asked for again and read; nothing is read (or wiped) once the auction house is closed.
Run: python3 dev/tests/test_auctions_rescan.py"""
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
-- (enough of the game for the Inventory module to start: no skills, no bags)
C_SkillInfo = { GetNumSkillLines = function() return 0 end }
C_Container = C_Container or {} C_Container.GetContainerNumSlots = function() return 0 end
AzerothAlmanacDB = false FireEvent("ADDON_LOADED", "AzerothAlmanac") FireEvent("PLAYER_LOGIN") RunTimers(5)
INV = A.QoL.Inventory
-- the game's owned auctions: the server's list, and what the client has been told of it so far
SERVER = { { itemLink = "|cffffffff|Hitem:2865::::::::24:::::|h[Rough Bronze Leggings]|h|r", quantity = 1, buyoutAmount = 578, timeLeftSeconds = 86000 } }
function Tick(s) for _ = 1, s * 4 do RunTimers(0.25) end end
CLIENT = {}
QUERIES = 0
C_AuctionHouse = C_AuctionHouse or {}
C_AuctionHouse.QueryOwnedAuctions = function() QUERIES = QUERIES + 1 C_Timer.After(0.2, function() CLIENT = {} for i, a in ipairs(SERVER) do CLIENT[i] = a end FireEvent("OWNED_AUCTIONS_UPDATED") end) end
C_AuctionHouse.GetNumOwnedAuctions = function() return #CLIENT end
C_AuctionHouse.GetOwnedAuctionInfo = function(i) return CLIENT[i] end
AuctionHouseFrame = CreateFrame("Frame")
AuctionHouseFrame.AuctionsFrame = CreateFrame("Frame")
AuctionHouseFrame:Show()
FireEvent("AUCTION_HOUSE_SHOW") RunTimers(1)
function Count() local c = INV:Me() return c.auctions and #c.auctions.items or -1 end
""")
check(p.eval("Count()") == 1, "the auction house opens: your one auction is read")

# posting: no OWNED_AUCTIONS_UPDATED on its own
p.lua("""
table.insert(SERVER, { itemLink = "|cffffffff|Hitem:3205::::::::24:::::|h[Barbed Club]|h|r", quantity = 1, buyoutAmount = 1200, timeLeftSeconds = 86000 })
FireEvent("AUCTION_HOUSE_AUCTION_CREATED") Tick(4)
""")
check(p.eval("Count()") == 2, "you post another: it's asked for again and read (2)")

# the Auctions tab shown: asked again
p.lua("""
table.insert(SERVER, { itemLink = "|cffffffff|Hitem:2140::::::::24:::::|h[Carving Knife]|h|r", quantity = 1, buyoutAmount = 400, timeLeftSeconds = 86000 })
Q0 = QUERIES
AuctionHouseFrame.AuctionsFrame:Hide() AuctionHouseFrame.AuctionsFrame:Show()
local onShow = AuctionHouseFrame.AuctionsFrame:GetScript("OnShow") if onShow then onShow(AuctionHouseFrame.AuctionsFrame) end
Tick(4)
""")
check(p.eval("QUERIES") > p.eval("Q0") and p.eval("Count()") == 3, "opening the Auctions tab asks again: the new one shows (3)")

# cancelling
p.lua("table.remove(SERVER, 1) FireEvent('AUCTION_CANCELED') Tick(4)")
check(p.eval("Count()") == 2, "cancelling one: read again (2)")

# closed: the game's list empties, ours is kept
p.lua("AuctionHouseFrame:Hide() CLIENT = {} FireEvent('OWNED_AUCTIONS_UPDATED') FireEvent('AUCTION_HOUSE_AUCTION_CREATED') Tick(4)")
check(p.eval("Count()") == 2, "the auction house closed: nothing read, the list isn't wiped")

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
