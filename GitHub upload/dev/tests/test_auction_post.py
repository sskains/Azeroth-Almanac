"""Bag to auction (#60), offline: Alt+Right-click a bag item with the Auctions tab open.
Run: python3 dev/tests/test_auction_post.py
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Player

FAILS = []
def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        FAILS.append(what)

FILES = ["Locale.lua", "Core.lua", "Modules/Store.lua", "QoL/Core.lua", "QoL/WindowUtil.lua",
         "QoL/AuctionPrices.lua", "QoL/AuctionPost.lua"]

def player():
    p = Player("Alice", files=FILES)
    p.lua("""
-- the game's Auction House (Auctions tab) and one bag, as far as the module touches them
AuctionFrame = CreateFrame("Frame") AuctionFrameAuctions = CreateFrame("Frame") AuctionFrameAuctions.priceType = 1
StartPrice, BuyoutPrice = CreateFrame("Frame"), CreateFrame("Frame")
AuctionsStackSizeEntry, AuctionsNumStacksEntry = CreateFrame("EditBox"), CreateFrame("EditBox")
AuctionsStackSizeEntry.SetNumber = function(self, n) self.n = n end
AuctionsNumStacksEntry.SetNumber = function(self, n) self.n = n end
PRICE = {}
MoneyInputFrame_SetCopper = function(f, c) PRICE[f] = c end
POSTS = 0
AuctionsCreateAuctionButton = CreateFrame("Button")
AuctionsCreateAuctionButton.IsEnabled = function() return true end
AuctionsCreateAuctionButton.Click = function() POSTS = POSTS + 1 SLOT = nil FireEvent("NEW_AUCTION_UPDATE") end
BAG = { [0] = { [1] = { link = "|cffffffff|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|r", name = "Linen Cloth", count = 20 } } }
C_Container = {
	GetContainerItemLink = function(b, s) return BAG[b] and BAG[b][s] and BAG[b][s].link end,
	GetContainerItemInfo = function(b, s) local it = BAG[b] and BAG[b][s] return it and { stackCount = it.count } end,
	PickupContainerItem = function(b, s) CURSOR = BAG[b][s] end,
}
C_Item = { GetItemInfo = function(link) return link:match("%[(.-)%]") end }
ClearCursor = function() CURSOR = nil end
ClickAuctionSellItemButton = function() if CURSOR then SLOT = CURSOR CURSOR = nil FireEvent("NEW_AUCTION_UPDATE") end end
GetAuctionSellItemInfo = function() if SLOT then return SLOT.name, nil, SLOT.count end end
GetCoinTextureString = function(c) return c .. "c" end
local bagFrame = CreateFrame("Frame") bagFrame.GetID = function() return 0 end
BUTTON = CreateFrame("Button", "ContainerFrame1Item1")
BUTTON.GetParent = function() return bagFrame end
BUTTON.GetID = function() return 1 end
ALT = true
IsAltKeyDown = function() return ALT end
AzerothAlmanacDB = false
FireEvent("ADDON_LOADED", "AzerothAlmanac")
FireEvent("PLAYER_LOGIN")
RunTimers(5)
QA = A.QoL.AuctionPost
-- the last scan's lowest price for Linen Cloth: 1 silver each
A.QoL.AuctionPrices.PriceFor = function() return { p = 100 } end
function Click(button) BUTTON:GetScript("PreClick")(BUTTON, button or "RightButton") BUTTON:GetScript("OnClick")(BUTTON, button or "RightButton") RunTimers(1) end
-- a bag addon's button: not hooked, found under the mouse (GLOBAL_MOUSE_DOWN), then its own click
OTHER = CreateFrame("Button", "SomeBagAddonItem7")
OTHER.GetBagID = function() return 0 end
OTHER.GetID = function() return 1 end
GetMouseFoci = function() return { OTHER } end
function MousePress(button) FireEvent("GLOBAL_MOUSE_DOWN", button or "RightButton") RunTimers(1) end
-- the game's own button: the press, then its click (both ways in for one Alt+Right-click)
function FullClick() GetMouseFoci = function() return { BUTTON } end FireEvent("GLOBAL_MOUSE_DOWN", "RightButton") Click() end
""")
    return p

print("Alt+Right-click with the Auctions tab open")
p = player()
p.lua("Click()")
check(p.eval("SLOT and SLOT.name") == "Linen Cloth", "the item goes into the sell slot")
check(p.eval("AuctionsStackSizeEntry.n") == 20 and p.eval("AuctionsNumStacksEntry.n") == 1, "the whole stack, one auction")
check(p.eval("PRICE[BuyoutPrice]") == 99 and p.eval("PRICE[StartPrice]") == 94, "buyout 1% under the last scan's lowest (99c each), bid a little under")
check(p.eval("POSTS") == 0, "nothing posted yet")
p.lua("Click()")
check(p.eval("POSTS") == 1 and p.eval("QA.Pending()") is None, "Alt+Right-click again: posted")

print("per stack prices")
p = player()
p.lua("AuctionFrameAuctions.priceType = 2 Click()")
check(p.eval("PRICE[BuyoutPrice]") == 99 * 20, "with Per Stack chosen, the stack's price")

print("Enter posts")
p = player()
p.lua("Click() KEY = nil for _, f in ipairs(FRAMES) do if f._scripts.OnKeyDown then KEY = f end end")
p.lua("KEY:GetScript('OnKeyDown')(KEY, 'A')")
check(p.eval("POSTS") == 0, "other keys do nothing")
p.lua("KEY:GetScript('OnKeyDown')(KEY, 'ENTER')")
check(p.eval("POSTS") == 1, "Enter posts it")

print("when it does nothing")
p = player()
p.lua("AuctionFrameAuctions:Hide() Click()")
check(p.eval("SLOT") is None, "Auctions tab not open: nothing new")
p.lua("AuctionFrameAuctions:Show() ALT = false Click()")
check(p.eval("SLOT") is None, "plain right-click: left to the game")
p.lua("ALT = true A.db.qol.auction.altPost = false Click()")
check(p.eval("SLOT") is None, "switched off in Settings: nothing")
p = player()
p.lua("A.QoL.AuctionPrices.PriceFor = function() return nil end Click()")
check(p.eval("SLOT and SLOT.name") == "Linen Cloth" and p.eval("PRICE[BuyoutPrice]") is None, "no scan price: in the slot, the game's suggestion left alone")

print("any bag (a bag addon's buttons)")
p = player()
p.lua("MousePress()")
check(p.eval("SLOT and SLOT.name") == "Linen Cloth" and p.eval("PRICE[BuyoutPrice]") == 99, "Alt+Right-click on a bag addon's button: into the slot, priced")
p.lua("RunTimers(1) MousePress()")
check(p.eval("POSTS") == 1, "again: posted")
p = player()
p.lua("FullClick()")
check(p.eval("SLOT and SLOT.name") == "Linen Cloth" and p.eval("POSTS") == 0, "the game's button: press and click count once (not posted straight away)")
p.lua("RunTimers(1) FullClick()")
check(p.eval("POSTS") == 1, "the second Alt+Right-click posts")

print("/aa ahpost")
p = player()
p.lua("AuctionFrameAuctions:Hide() MousePress() A.db.settings.debug = true SlashCmdList.AZEROTHALMANAC('ahpost')")
out = p.eval("table.concat(CHAT, ' / ')")
check("selling tab isn't open" in out and "old bag buttons hooked" in out and "mouse presses seen 1" in out, "it says what it sees and why nothing happened")

print("WoW Forever's Auction House (AuctionHouseFrame, the Sell tab)")
def newah():
    p = player()
    p.lua("""
AuctionFrame = nil AuctionFrameAuctions = nil
AuctionHouseFrameDisplayMode = { Buy = 1, CommoditiesSell = 2, ItemSell = 3, Auctions = 4 }
ItemLocation = { CreateFromBagAndSlot = function(self, b, s) return { GetBagAndSlot = function() return b, s end } end }
local function Price() local b = { amount = 0 } b.SetAmount = function(self, c) self.amount = c end b.GetAmount = function(self) return self.amount end return b end
SELLF = CreateFrame("Frame")
SELLF.PriceInput = Price()
SELLF.QuantityInput = { SetQuantity = function(self, n) self.n = n end }
SELLF.GetItem = function() return SELLF.item end
NPOSTS = 0
SELLF.PostButton = { IsEnabled = function() return SELLF.item ~= nil and SELLF.PriceInput.amount > 0 end,
	Click = function() NPOSTS = NPOSTS + 1 SELLF.item = nil FireEvent("AUCTION_HOUSE_AUCTION_CREATED") end }
AuctionHouseFrame = CreateFrame("Frame")
AuctionHouseFrame.mode = 2
AuctionHouseFrame.GetDisplayMode = function(self) return self.mode end
AuctionHouseFrame.CommoditiesSellFrame = SELLF
AuctionHouseFrame.ItemSellFrame = CreateFrame("Frame")
-- the game: the item goes in, then its search comes back with the lowest listed price (60c)
AuctionHouseFrame.SetPostItem = function(self, loc) SELLF.item = loc self.mode = 2 SELLF.PriceInput.amount = 0
	C_Timer.After(0.5, function() SELLF.PriceInput.amount = 60 FireEvent("COMMODITY_SEARCH_RESULTS_UPDATED") end) end
GetMouseFoci = function() return { OTHER } end
HANDLED = nil
""")
    return p
p = newah()
p.lua("MousePress() RunTimers(3)")
check(p.eval("SELLF.item ~= nil") , "Alt+Right-click: the item goes into the sell frame")
check(p.eval("SELLF.PriceInput.amount") == 59, "priced 1% under the lowest listed now (60c: 59c)")
check(p.eval("SELLF.QuantityInput.n") == 20, "the whole stack")
p.lua("RunTimers(1) FireEvent('GLOBAL_MOUSE_DOWN', 'RightButton') A.QoL.AuctionPost.OnModifiedClick('link', ItemLocation:CreateFromBagAndSlot(0, 1))")
check(p.eval("NPOSTS") == 1, "Alt+Right-click again: posted by the click itself (the press waits for it)")
p.lua("RunTimers(1)")
check(p.eval("NPOSTS") == 1, "...once")
p = newah()
p.lua("AuctionHouseFrame.SetPostItem = function(self, loc) SELLF.item = loc self.mode = 2 SELLF.PriceInput.amount = 0 end MousePress() RunTimers(3)")
check(p.eval("SELLF.PriceInput.amount") == 99, "nothing listed: 1% under the last scan")
p.lua("KEY = nil for _, f in ipairs(FRAMES) do if f._scripts.OnKeyDown then KEY = f end end KEY:GetScript('OnKeyDown')(KEY, 'ENTER')")
check(p.eval("NPOSTS") == 1, "Enter posts it")
p = newah()
p.lua("AuctionHouseFrame.mode = 1 MousePress() RunTimers(3)")
check(p.eval("SELLF.item") is None, "on the Buy tab: nothing")
p.lua("A.db.settings.debug = true SlashCmdList.AZEROTHALMANAC('ahpost')")
out = p.eval("table.concat(CHAT, ' / ')")
check("not on its Sell tab" in out, "/aa ahpost: says it's not on the Sell tab")
p = newah()
p.lua("HandleModifiedItemClick = HandleModifiedItemClick") 
p.lua("A.QoL.AuctionPost.OnModifiedClick('link', ItemLocation:CreateFromBagAndSlot(0, 1)) RunTimers(3)")
check(p.eval("SELLF.PriceInput.amount") == 59, "from the bag's own Alt-click (HandleModifiedItemClick, with the item's place): priced")

print()
print("FAILED: %d" % len(FAILS) if FAILS else "all passed")
sys.exit(1 if FAILS else 0)
