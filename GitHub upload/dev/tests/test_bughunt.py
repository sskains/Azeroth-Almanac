"""Bug hunt, 2026-10-11: the fixes that can be checked offline. Run: python3 dev/tests/test_bughunt.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player, ALL_FILES

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

# the game's bag and item calls, in place before the files load (Merchant reads them at load)
BAGS = """
BAG = { [0] = { { quality = 0, stackCount = 2, itemID = 1 }, { quality = 0, stackCount = 1, itemID = 2 }, { quality = 0, stackCount = 3, itemID = 3 } } }
C_Container = { GetContainerNumSlots = function(b) return BAG[b] and #BAG[b] or 0 end,
	GetContainerItemInfo = function(b, s) return BAG[b] and BAG[b][s] end,
	UseContainerItem = function(b, s) SOLD = (SOLD or 0) + 1 end }
C_Item = { GetItemInfo = function() return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 10 end }
C_MerchantFrame = false
"""
def patch(name, src):
    return (BAGS + src) if name == "QoL/Merchant.lua" else src

p = Player("Alice", files=ALL_FILES, patch=patch)
p.lua('AzerothAlmanacDB = false FireEvent("ADDON_LOADED", "AzerothAlmanac") FireEvent("PLAYER_LOGIN") RunTimers(10)')

print("Wild Gambit: winning a creature's card says so in chat")
p.lua('CHAT = {} A.QoL.WildGambit.AddWin({ npc = 900, name = "Guard Thomas", level = 35, class = "elite", type = "Humanoid", reaction = "friendly" })')
out = p.eval("table.concat(CHAT, ' / ')")
check("earned" in out and "Guard Thomas" in out, "the line comes (it called a Tell that wasn't there yet): " + out[:80])

print("Junk selling: closing the vendor part way reports only what was sold")
p.lua("""
CHAT = {} SOLD = 0
MerchantFrame = CreateFrame("Frame", "MerchantFrame") MerchantFrame:Show()
A.db.qol.merchant.sellJunk = true A.db.qol.merchant.report = true GetMoneyString = function(c) return c .. "c" end
FireEvent("MERCHANT_SHOW") RunTimers(1)
""")
p.lua("for _ = 1, 4 do if SOLD >= 1 then MerchantFrame:Hide() end RunTimers(0.3) end")
out = p.eval("table.concat(CHAT, ' / ')")
check(p.eval("SOLD") == 1 and "Sold 2 junk items" in out, "one stack of 2 sold, then the window closed: '%s' (sold %s)" % (out[:70], p.eval("SOLD")))

print("Journey recorder: waiting as a ghost doesn't write a point every 5 seconds")
p.lua("""
UnitIsGhost = function() return true end
A.Where = function() return { map = 1429, x = 40.0, y = 60.0 } end
JR = A.JourneyRecorder or A.Modules and A.Modules.JourneyRecorder
""")
jr = p.eval("JR ~= nil")
if not jr:
    p.lua("for k, v in pairs(A) do if type(v) == 'table' and v.Tick and v.MapChanged then JR = v end end")
p.lua("""
local s = A.db.trail and A.db.trail[A.CharKey()] or {}
for k in pairs(s) do s[k] = nil end
for _ = 1, 24 do JR:Tick() RunTimers(5) end
COUNT = 0
for _, day in pairs(A.db.trail[A.CharKey()] or {}) do for _ in day:gmatch(";") do COUNT = COUNT + 1 end end
""")
check(p.eval("COUNT") == 1, "2 minutes at the spirit healer: one point (was 24): %s" % p.eval("COUNT"))
p.lua("""
A.Where = function() return { map = 1429, x = 45.0, y = 60.0 } end
JR:Tick()
COUNT = 0
for _, day in pairs(A.db.trail[A.CharKey()] or {}) do for _ in day:gmatch(";") do COUNT = COUNT + 1 end end
""")
check(p.eval("COUNT") == 2, "running back as a ghost still draws the run: %s" % p.eval("COUNT"))

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
