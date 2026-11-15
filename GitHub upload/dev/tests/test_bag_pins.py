"""Bag pins (QoL/BagPins.lua, 2026-11-11): Alt+click pins a bag item to its slot; after the game's Cleanup
(C_Container.SortBags) the pinned items are moved back, one swap at a time once the bags have settled.
Run: python3 dev/tests/test_bag_pins.py"""
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
-- a real hooksecurefunc (the stub's does nothing), so the module's hook on the game's sort runs
hooksecurefunc = function(a, b, c)
  local t, name, fn = a, b, c
  if type(a) == "string" then t, name, fn = _G, a, b end
  local orig = t[name]
  t[name] = function(...) local r = { orig(...) } fn(...) return unpack(r) end
end
-- two bags of four slots: backpack (0) and bag 1
NUM_BAG_SLOTS = 1
BAGS = { [0] = { 6948, 118, 2512, nil }, [1] = { 4306, nil, 118, 2589 } }
LOCKED = {}
CURSOR = nil
local function info(bag, slot)
  local id = BAGS[bag] and BAGS[bag][slot]
  if not id then return nil end
  return { itemID = id, isLocked = LOCKED[bag .. ":" .. slot] == true, stackCount = 1 }
end
C_Container.GetContainerNumSlots = function(bag) return BAGS[bag] and 4 or 0 end
C_Container.GetContainerItemInfo = info
MOVES = 0
C_Container.PickupContainerItem = function(bag, slot)
  if not CURSOR then
    if BAGS[bag][slot] then CURSOR = { bag = bag, slot = slot } end
  else
    -- put down: the two slots trade places
    local a, b = BAGS[CURSOR.bag][CURSOR.slot], BAGS[bag][slot]
    BAGS[bag][slot], BAGS[CURSOR.bag][CURSOR.slot] = a, b
    LOCKED[bag .. ":" .. slot], LOCKED[CURSOR.bag .. ":" .. CURSOR.slot] = true, true
    CURSOR = nil
    MOVES = MOVES + 1
  end
end
CursorHasItem = function() return CURSOR ~= nil end
ClearCursor = function() CURSOR = nil end
function Unlock() LOCKED = {} end
-- Cleanup: everything by item ID, backpack first
C_Container.SortBags = function()
  local all = {}
  for bag = 0, 1 do for slot = 1, 4 do if BAGS[bag][slot] then all[#all + 1] = BAGS[bag][slot] end end end
  table.sort(all)
  local i = 1
  for bag = 0, 1 do for slot = 1, 4 do BAGS[bag][slot] = all[i] i = i + 1 end end
  FireEvent("BAG_UPDATE", 0) FireEvent("BAG_UPDATE_DELAYED")
end
GetItemInfo = function(id) return "Item " .. id end
C_Item = C_Item or {}
C_Item.GetItemInfo = GetItemInfo
AzerothAlmanacDB = false FireEvent("ADDON_LOADED", "AzerothAlmanac") FireEvent("PLAYER_LOGIN") RunTimers(5)
BP = A.QoL.BagPins
function Where(id) for bag = 0, 1 do for slot = 1, 4 do if BAGS[bag][slot] == id then return bag .. ":" .. slot end end end end
""")
check(p.eval("AzerothAlmanacDB.qol.bagPins.enabled") is True, "on by default")

# pin the hearthstone (6948) to backpack slot 1 and the bag-1 item 4306 to bag 1 slot 1
p.lua("BP:Toggle(0, 1) BP:Toggle(1, 1)")
check(p.eval("BP:Count()") == 2, "Alt+click pins: two pins")
check(p.eval("BP:Pins()['0:1']") == 6948 and p.eval("BP:Pins()['1:1']") == 4306, "...each pin is the item in that slot")

# Cleanup scrambles them
p.lua("C_Container.SortBags()")
check(p.eval("Where(6948)") != "0:1" or p.eval("Where(4306)") != "1:1", "Cleanup moved the pinned items (to %s and %s)" % (p.eval("Where(6948)"), p.eval("Where(4306)")))
check(p.eval("BP:Watching()"), "the sort is noticed (the module hooked the game's sort)")
p.lua("RunTimers(0.3)")
check(p.eval("MOVES") == 0, "nothing moves while the bags are still settling")
p.lua("for _ = 1, 40 do RunTimers(0.15) Unlock() end")
check(p.eval("Where(6948)") == "0:1" and p.eval("Where(4306)") == "1:1", "once settled the pinned items are back in their slots (%s, %s)" % (p.eval("Where(6948)"), p.eval("Where(4306)")))
check(p.eval("not BP:Restoring() and not BP:Watching()"), "...and it stops there")
check(p.eval("CURSOR") is None, "nothing is left on the cursor")
items = p.eval("(function() local n = 0 for bag = 0, 1 do for slot = 1, 4 do if BAGS[bag][slot] then n = n + 1 end end end return n end)()")
check(items == 6, "no item is lost or doubled (%d of 6)" % items)

# a swap waits for the last one to unlock
p.lua("MOVES = 0 BAGS[0][1], BAGS[0][3] = BAGS[0][3], BAGS[0][1] BAGS[1][1], BAGS[1][4] = BAGS[1][4], BAGS[1][1] BP:Restore() RunTimers(0.5)")
check(p.eval("MOVES") == 1, "one swap at a time: the next waits while the last is locked")
p.lua("for _ = 1, 10 do Unlock() RunTimers(0.15) end")
check(p.eval("Where(6948)") == "0:1" and p.eval("Where(4306)") == "1:1", "...then the rest follow")

# holding something: waits
p.lua("BAGS[0][1], BAGS[0][2] = BAGS[0][2], BAGS[0][1] MOVES = 0 CURSOR = { bag = 1, slot = 3 } BP:Restore() RunTimers(0.5)")
check(p.eval("MOVES") == 0, "while you hold an item on the cursor, nothing moves")
p.lua("CURSOR = nil for _ = 1, 10 do Unlock() RunTimers(0.15) end")
check(p.eval("Where(6948)") == "0:1", "...and it carries on once your hand is free")

# a pinned item that's gone
p.lua("BAGS[1][1] = nil MOVES = 0 C_Container.SortBags() for _ = 1, 40 do RunTimers(0.15) Unlock() end")
check(p.eval("Where(6948)") == "0:1" and p.eval("Where(4306)") is None, "an item that's gone: its pin waits, nothing else is disturbed")

# unpin
p.lua("BP:Toggle(0, 1)")
check(p.eval("BP:Pins()['0:1']") is None and p.eval("BP:Count()") == 1, "Alt+click a pinned item again: unpinned")
p.lua("BP:UnpinAll()")
check(p.eval("BP:Count()") == 0, "Unpin everything")

# switched off: Cleanup is left alone
p.lua("BP:Toggle(0, 2) AzerothAlmanacDB.qol.bagPins.enabled = false MOVES = 0 PINNED = BAGS[0][2] C_Container.SortBags() for _ = 1, 40 do RunTimers(0.15) Unlock() end")
check(not p.eval("BP:Watching()") and p.eval("MOVES") == 0, "switched off: nothing is put back after Cleanup")

# the game's bag buttons: the pin mark, and Alt+click
p.lua("""
AzerothAlmanacDB.qol.bagPins.enabled = true BP:UnpinAll()
BAGS = { [0] = { 6948, 118, 2512, nil }, [1] = { 4306, nil, 118, 2589 } } LOCKED = {} CURSOR = nil
local function Btn(bag, slot) local b = CreateFrame("Button") b.GetBagID = function() return bag end b.GetID = function() return slot end return b end
B01, B02, B14 = Btn(0, 1), Btn(0, 2), Btn(1, 4)
ContainerFrameCombinedBags = CreateFrame("Frame")
ContainerFrameCombinedBags.EnumerateValidItems = function() return ipairs({ B01, B02, B14 }) end
BP:Paint()
ALT = false IsAltKeyDown = function() return ALT end
function Click(b, button) b._scripts.OnClick(b, button or "LeftButton") end
""")
check(p.eval("B01.aaPin == nil or not B01.aaPin:IsShown()"), "no pin, no mark")
p.lua("Click(B01)")
check(p.eval("BP:Count()") == 0, "a plain click doesn't pin")
p.lua("ALT = true Click(B01, 'RightButton')")
check(p.eval("BP:Count()") == 0, "Alt+right-click doesn't pin (right-click uses the item)")
p.lua("Click(B01)")
check(p.eval("BP:Pins()['0:1']") == 6948, "Alt+click pins the item in that slot")
check(p.eval("B01.aaPin ~= nil and B01.aaPin:IsShown()") and not p.eval("B02.aaPin ~= nil and B02.aaPin:IsShown()"), "...and the pinned slot shows the pin, the others don't")
p.lua("BAGS[0][1] = nil BP:Paint()")
check(p.eval("B01.aaPin:IsShown()"), "the mark stays while the slot is empty (the item used up)")
p.lua("Click(B01)")
check(p.eval("BP:Count()") == 0 and not p.eval("B01.aaPin:IsShown()"), "Alt+click the empty pinned slot: unpinned, the mark goes")
p.lua("BAGS[0][1] = 6948 Click(B01) AzerothAlmanacDB.qol.bagPins.enabled = false BP:Paint()")
check(not p.eval("B01.aaPin:IsShown()"), "switched off: no marks")
p.lua("ALT = true Click(B02)")
check(p.eval("BP:Pins()['0:2']") is None, "...and Alt+click doesn't pin")
p.lua("SOK, SERR = pcall(function() A.QoL.Settings:Open('inventory') RunTimers(1) end)")
check(p.eval("SOK"), "the Bags and bank settings page builds with the Bag pins section (%s)" % p.eval("tostring(SERR)"))

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
