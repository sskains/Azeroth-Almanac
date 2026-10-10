-- (#60, DESIGN 82) Bag to auction: Alt+Right-click an item in your bags while the Auction House is
-- open on its selling tab and it goes into the sell frame, the whole stack, priced 1% under the
-- lowest price known. Enter, or Alt+Right-click the same item again, posts it (a click or key press
-- is the hardware event posting needs).
--   Not Shift-click (links, splitting), not Ctrl-click (dressing room), not plain right-click (the
--   game's own: it puts the item in the sell frame unpriced). Elsewhere Alt+Right-click does nothing new.
--   Settings > Auction House > "Alt+Right-click a bag item to sell it" (on by default).
--
-- Two Auction Houses: WoW Forever's (the newer one: AuctionHouseFrame, tabs Buy / Sell / Auctions,
-- "Post Auctions" with Quantity, Unit Price and Create Auction) and the old Classic one (AuctionFrame,
-- its Auctions tab), whichever the client has.
--   Newer: the item goes in with AuctionHouseFrame:SetPostItem; the game then searches the current
--   listings and fills in the lowest live price, so the price is set 1% under that once it arrives
--   (live beats the last scan); with no live listing, 1% under the last scan (Auction Prices).
--   Old: ClickAuctionSellItemButton, prices 1% under the last scan.
-- Three ways in, so it works whatever draws your bags: HandleModifiedItemClick (the game's bags call
-- it on a modified click, with the item's location), the old bags' buttons (ContainerFrame<n>Item<m>),
-- and any Alt+right mouse press over a bag slot (GLOBAL_MOUSE_DOWN). One click is acted on once.
-- /aa ahpost says what it sees.

local _, A = ...
local ns = A.QoL
local AH = ns:NewModule("AuctionPost")

local UNDERCUT = 0.99           -- 1% under the lowest price (at least 1 copper under)
local pending                   -- { bag, slot, link, name, count, filled, set, at } the item waiting
local keys                      -- the Enter listener while an item waits to be posted
local hooked = {}
local lastAt = { t = 0 }        -- (one click, several ways in: acted on once)
local seen = { mouse = 0, modified = 0 }

local function On() return not (ns.db and ns.db.auction and ns.db.auction.altPost == false) end
local function Tell(msg) ns.Print("|cff9be36bAuction House:|r " .. msg) end

local function ItemLink(bag, slot) return ((C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink)(bag, slot) end
local function PickupItem(bag, slot) return ((C_Container and C_Container.PickupContainerItem) or PickupContainerItem)(bag, slot) end
local function ItemCount(bag, slot)
	if C_Container and C_Container.GetContainerItemInfo then
		local info = C_Container.GetContainerItemInfo(bag, slot)
		return info and info.stackCount or 1
	end
	local _, count = GetContainerItemInfo(bag, slot)
	return count or 1
end
local function Money(c)
	return (GetCoinTextureString and GetCoinTextureString(c)) or (ns.Almanac.MoneyText and ns.Almanac.MoneyText(c)) or tostring(c)
end
local function Undercut(low)
	if not low or low <= 0 then return nil end
	local each = math.floor(low * UNDERCUT)
	if each >= low then each = low - 1 end
	return math.max(1, each)
end

-- the last scan's lowest price for one of the item, undercut (and the price itself)
function AH.UnitPrice(link)
	local AP = ns.AuctionPrices
	local entry = AP and link and AP:PriceFor(link)
	local low = type(entry) == "table" and entry.p or tonumber(entry)
	if not low or low <= 0 then return nil end
	return Undercut(low), low
end

---------------------------------------------------------------------------
-- The newer Auction House (AuctionHouseFrame)
---------------------------------------------------------------------------

local function NewAH() return AuctionHouseFrame and AuctionHouseFrame:IsShown() and true or false end

-- the sell frame on show (commodities or single items), or nil when not on the Sell tab
local function SellFrame()
	local f = AuctionHouseFrame
	if not (f and f:IsShown()) then return nil end
	local mode = (f.GetDisplayMode and f:GetDisplayMode()) or f.displayMode
	local M = AuctionHouseFrameDisplayMode
	if M then
		if mode == M.CommoditiesSell then return f.CommoditiesSellFrame end
		if mode == M.ItemSell then return f.ItemSellFrame end
		return nil
	end
	-- (no list of modes: whichever sell frame is showing)
	for _, s in ipairs({ f.CommoditiesSellFrame, f.ItemSellFrame }) do if s and s:IsShown() then return s end end
end

-- the price box's amount (per item) and setting it
local function PriceOf(sf)
	local box = sf and sf.PriceInput
	if box and box.GetAmount then local ok, v = pcall(box.GetAmount, box) if ok then return tonumber(v) end end
end
local function SetPrice(sf, copper)
	local box = sf and sf.PriceInput
	if not (box and box.SetAmount) then return false end
	pcall(box.SetAmount, box, copper)
	-- (the Post button and the totals follow the price)
	if sf.OnPriceChanged then pcall(sf.OnPriceChanged, sf) end
	if sf.UpdateTotalPrice then pcall(sf.UpdateTotalPrice, sf) end
	if sf.UpdatePostState then pcall(sf.UpdatePostState, sf) end
	return true
end
local function SetQuantity(sf, n)
	local q = sf and sf.QuantityInput
	if q and q.SetQuantity then pcall(q.SetQuantity, q, n) end
	if sf and sf.UpdateTotalPrice then pcall(sf.UpdateTotalPrice, sf) end
end

-- what's in the newer sell frame: its bag and slot (nil when empty)
local function NewInSlot()
	local sf = SellFrame()
	local loc = sf and sf.GetItem and sf:GetItem()
	if loc and loc.GetBagAndSlot then
		local ok, bag, slot = pcall(loc.GetBagAndSlot, loc)
		if ok and bag then return bag * 100 + slot end
	end
end

-- the price: 1% under what the game found live (once its search is back), else under the last scan.
-- Run for the first few seconds after the item goes in (the game's search can land late and reset
-- its price); after that a price you type is left alone.
local function NewFill(final)
	if not pending then return end
	local sf = SellFrame()
	if not sf then return end
	local live = PriceOf(sf)
	local each, low, from
	if live and live > 0 and live ~= pending.set then
		each, low, from = Undercut(live), live, "lowest listed now"
	elseif not pending.set then
		each, low = AH.UnitPrice(pending.link)
		from = "last scan"
	end
	if each and each ~= live then
		pending.set = each
		SetPrice(sf, each)
		SetQuantity(sf, pending.count)
	end
	if not pending.filled and (each or final) then
		pending.filled = true
		if keys then keys:Show() end
		if pending.set then
			Tell(("%s x%d at %s each (%s %s). |cffffffffEnter|r or |cffffffffAlt+Right-click|r it again to post.")
				:format(pending.link or pending.name or "?", pending.count, Money(pending.set), from or "lowest", Money(low or pending.set)))
		else
			Tell(("%s x%d is in. No price known for it (nothing listed, and not in your scans): set one, then |cffffffffEnter|r or |cffffffffAlt+Right-click|r it again to post.")
				:format(pending.link or pending.name or "?", pending.count))
		end
	end
end

local function NewPost()
	local sf = SellFrame()
	if not (pending and sf) then return false end
	local button = sf.PostButton
	if button and button.IsEnabled and button:IsEnabled() then button:Click() return true end
	if sf.PostItem then local ok = pcall(sf.PostItem, sf) return ok end
	return false
end

local function NewPut(bag, slot)
	local loc = ItemLocation and ItemLocation.CreateFromBagAndSlot and ItemLocation:CreateFromBagAndSlot(bag, slot)
	if not loc then return false end
	if AuctionHouseFrame.SetPostItem then
		pcall(AuctionHouseFrame.SetPostItem, AuctionHouseFrame, loc)
	else
		local sf = SellFrame()
		if sf and sf.SetItem then pcall(sf.SetItem, sf, loc) end
	end
	return true
end

---------------------------------------------------------------------------
-- The old Auction House (AuctionFrame, Auctions tab)
---------------------------------------------------------------------------

local function OldAuctionsTab() return AuctionFrame and AuctionFrame:IsShown() and AuctionFrameAuctions and AuctionFrameAuctions:IsShown() end
local function OldInSlot()
	if not GetAuctionSellItemInfo then return nil end
	local name, _, count = GetAuctionSellItemInfo()
	if name then return name, count or 1 end
end

local function OldFill()
	if not (pending and OldAuctionsTab()) then return end
	local name, count = OldInSlot()
	if not name or name ~= pending.name then return end
	pending.filled = true
	if AuctionsStackSizeEntry and AuctionsStackSizeEntry.SetNumber then AuctionsStackSizeEntry:SetNumber(count) end
	if AuctionsNumStacksEntry and AuctionsNumStacksEntry.SetNumber then AuctionsNumStacksEntry:SetNumber(1) end
	local each, low = AH.UnitPrice(pending.link)
	if each and MoneyInputFrame_SetCopper and BuyoutPrice and StartPrice then
		-- (the price boxes are per item or per stack: the tab's "Per Item / Per Stack" choice)
		local perStack = AuctionFrameAuctions.priceType == (PRICE_TYPE_STACK or 2)
		local buyout = perStack and each * count or each
		MoneyInputFrame_SetCopper(BuyoutPrice, buyout)
		MoneyInputFrame_SetCopper(StartPrice, math.max(1, math.floor(buyout * 0.95)))
		if UpdateDeposit then pcall(UpdateDeposit) end
		if AuctionsFrameAuctions_ValidateAuction then pcall(AuctionsFrameAuctions_ValidateAuction) end
		Tell(("%s x%d at %s each (lowest seen %s). |cffffffffEnter|r or |cffffffffAlt+Right-click|r it again to post.")
			:format(pending.link or name, count, Money(each), Money(low)))
	else
		Tell(("%s x%d is in the slot. No auction price recorded for it yet (a full scan finds one), so the game's suggestion stands. |cffffffffEnter|r or |cffffffffAlt+Right-click|r it again to post.")
			:format(pending.link or name, count))
	end
	if keys then keys:Show() end
end

local function OldPost()
	local button = AuctionsCreateAuctionButton
	if not (pending and OldAuctionsTab() and button and button:IsEnabled()) then return false end
	button:Click()
	return true
end

---------------------------------------------------------------------------
-- Either
---------------------------------------------------------------------------

-- which Auction House is open on its selling tab: "new", "old" or nil
local function Selling()
	if SellFrame() then return "new" end
	if OldAuctionsTab() then return "old" end
end

local function Post()
	local kind = Selling()
	if kind == "new" then return NewPost() end
	if kind == "old" then return OldPost() end
	return false
end

-- what's in the sell slot now, as something to compare
local function Current(kind)
	if kind == "new" then return NewInSlot() end
	return (OldInSlot())
end

-- Alt+Right-click on bag `bag` slot `slot`. `before`: the sell slot before this click
local function OnAltRightClick(bag, slot, before, via)
	seen.click = ("bag %s slot %s"):format(tostring(bag), tostring(slot))
	seen.via = via
	if not On() then seen.why = "switched off in Settings" return end
	local kind = Selling()
	if not kind then
		seen.why = NewAH() and "the Auction House is open, but not on its Sell tab" or "the Auction House's selling tab isn't open"
		return
	end
	local key = bag * 100 + slot
	local link = ItemLink(bag, slot)
	if not link then seen.why = "no item in that bag slot" return end
	seen.why = nil
	-- the same item again, already waiting: post it. Posting needs the click itself (the press
	-- isn't one), so a press only stands by for the click; with no click coming (a bag addon that
	-- never tells the game), it tries a moment later, and Enter always works
	if pending and pending.filled and pending.bag == bag and pending.slot == slot and not (kind == "old" and before ~= pending.name) then
		if via == "the mouse" then
			local p = pending
			p.postSoon = GetTime()
			C_Timer.After(0.35, function() if pending == p and p.postSoon then p.postSoon = nil Post() end end)
			return
		end
		if lastAt.post and GetTime() - lastAt.post < 0.6 then return end
		lastAt.post = GetTime()
		pending.postSoon = nil
		if not Post() then Tell("not ready to post yet (a price and a quantity are needed).") end
		return
	end
	-- (the press and the click of one Alt+Right-click can both come here: acted on once)
	if lastAt.key == key and GetTime() - lastAt.t < 0.6 then return end
	lastAt.key, lastAt.t = key, GetTime()
	local name = (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(link)) or (GetItemInfo and GetItemInfo(link)) or link:match("%[(.-)%]")
	pending = { bag = bag, slot = slot, link = link, name = name, count = ItemCount(bag, slot), kind = kind, at = GetTime() }
	if kind == "new" then
		NewPut(bag, slot)
		-- (the game searches the live listings and fills its price: ours goes in after, more than once
		-- in case the search is slow; the search-result events also call NewFill)
		for _, t in ipairs({ 0.2, 0.8, 1.6 }) do C_Timer.After(t, function() NewFill(false) end) end
		C_Timer.After(2.6, function() NewFill(true) end)
	else
		local inSlot = OldInSlot()
		if inSlot ~= name or before == inSlot then
			ClearCursor()
			PickupItem(bag, slot)
			if ClickAuctionSellItemButton then ClickAuctionSellItemButton() end
			ClearCursor()
		end
		C_Timer.After(0.15, OldFill)
	end
end

---------------------------------------------------------------------------
-- The ways in
---------------------------------------------------------------------------

local function MouseFocus()
	if GetMouseFoci then local list = GetMouseFoci() return list and list[1] end
	if GetMouseFocus then return GetMouseFocus() end
end

-- a button as a bag and slot (the game's bag buttons, and bag addons that number theirs the same way)
local function BagSlotOf(f)
	if type(f) ~= "table" or not f.GetID then return nil end
	local ok, slot = pcall(f.GetID, f)
	if not ok or type(slot) ~= "number" or slot < 1 then return nil end
	local bag
	if f.GetBagID then local ok2, b = pcall(f.GetBagID, f) if ok2 then bag = b end end
	if bag == nil and type(f.bag) == "number" then bag = f.bag end
	if bag == nil and f.GetParent then
		local parent = f:GetParent()
		if parent and parent.GetID then local ok3, b = pcall(parent.GetID, parent) if ok3 then bag = b end end
	end
	if type(bag) ~= "number" or bag < 0 or bag > 4 then return nil end
	if not ItemLink(bag, slot) then return nil end
	return bag, slot
end

local function Run(...)
	local ok, err = pcall(OnAltRightClick, ...)
	if not ok then
		seen.why = "error: " .. tostring(err)
		ns.Almanac.Debug("auction post: " .. tostring(err))
	end
end

-- 1. the game's bags call HandleModifiedItemClick on any modified click (Alt counts), with the item's place
local function OnModifiedClick(link, itemLocation)
	if not IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then return end
	local button = GetMouseButtonClicked and GetMouseButtonClicked()
	if button and button ~= "RightButton" then return end
	seen.modified = seen.modified + 1
	local bag, slot
	if type(itemLocation) == "table" and itemLocation.GetBagAndSlot then
		local ok, b, s = pcall(itemLocation.GetBagAndSlot, itemLocation)
		if ok then bag, slot = b, s end
	end
	if not bag then bag, slot = BagSlotOf(MouseFocus()) end
	if not bag then seen.why = "an Alt-click came, but not from a bag slot the Almanac can read" return end
	Run(bag, slot, Current(Selling()), "the bag's click")
end

-- 2. any Alt+right press, over whatever is under the mouse
local function OnMouseDown(button)
	seen.mouse = seen.mouse + 1
	if button ~= "RightButton" or not IsAltKeyDown() then return end
	local f = MouseFocus()
	seen.focus = f and ((f.GetName and f:GetName()) or "a button with no name") or "nothing"
	if not Selling() then
		seen.click = "over " .. seen.focus
		seen.why = NewAH() and "the Auction House is open, but not on its Sell tab" or "the Auction House's selling tab isn't open"
		return
	end
	local bag, slot = BagSlotOf(f)
	if not bag then seen.why = "the button under the mouse isn't a bag slot the Almanac can read" return end
	Run(bag, slot, Current(Selling()), "the mouse")
end

-- 3. the old bags' own buttons: ContainerFrame1Item1 ...
local function HookBags()
	for fi = 1, (NUM_CONTAINER_FRAMES or 13) do
		for i = 1, (MAX_CONTAINER_ITEMS or 36) do
			local b = _G["ContainerFrame" .. fi .. "Item" .. i]
			if type(b) == "table" and b.HookScript and not hooked[b] then
				hooked[b] = true
				b:HookScript("PreClick", function(self, button)
					self.aaBefore = (button == "RightButton" and IsAltKeyDown() and Selling()) and (Current(Selling()) or false) or nil
				end)
				b:HookScript("OnClick", function(self, button)
					if button ~= "RightButton" or not IsAltKeyDown() then return end
					local before = self.aaBefore
					self.aaBefore = nil
					local bag, slot = BagSlotOf(self)
					if bag then Run(bag, slot, before or nil, "the bag button") end
				end)
			end
		end
	end
end

-- Enter posts while an item waits (other keys go on to the game as usual)
local function BuildKeys()
	keys = CreateFrame("Frame", nil, UIParent)
	keys:EnableKeyboard(true)
	if keys.SetPropagateKeyboardInput then keys:SetPropagateKeyboardInput(true) end
	keys:SetScript("OnKeyDown", function(self, key)
		local mine = (key == "ENTER" or key == "NUMPADENTER") and pending and pending.filled and Selling() ~= nil
			and not (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()) and not InCombatLockdown()
		if self.SetPropagateKeyboardInput and not InCombatLockdown() then self:SetPropagateKeyboardInput(not mine) end
		if mine then Post() end
	end)
	keys:Hide()
end

local function Done()
	pending = nil
	if keys then keys:Hide() end
end

-- /aa ahpost: what it sees
function AH:Status()
	local n = 0
	for _ in pairs(hooked) do n = n + 1 end
	local f = AuctionHouseFrame
	local mode = f and ((f.GetDisplayMode and f:GetDisplayMode()) or f.displayMode)
	local modeName = "?"
	for k, v in pairs(AuctionHouseFrameDisplayMode or {}) do if v == mode then modeName = k end end
	ns.Print("|cff9be36bAuction House, Alt+Right-click:|r " .. (On() and "on" or "|cffff6060off (Settings > Auction House)|r"))
	ns.Print(("  Auction House: %s%s; selling: %s"):format(
		f and (f:IsShown() and "open" or "closed") or (AuctionFrame and "the old one" or "|cffff6060not found|r"),
		f and f:IsShown() and (" on " .. modeName) or "",
		Selling() or "|cffffd100no (open the Sell tab)|r"))
	ns.Print(("  ways in: bag clicks seen %d, mouse presses seen %d, old bag buttons hooked %d"):format(seen.modified, seen.mouse, n))
	ns.Print(("  last Alt+Right-click: %s%s%s"):format(seen.click or "none seen", seen.via and (" (by " .. seen.via .. ")") or "",
		seen.focus and (", under the mouse: " .. seen.focus) or ""))
	if pending then ns.Print(("  waiting to post: %s x%d at %s"):format(pending.link or "?", pending.count or 0, pending.set and Money(pending.set) or "no price")) end
	if seen.why then ns.Print("  |cffffd100why nothing happened:|r " .. seen.why) end
end

function AH:OnLogin()
	HookBags()
	BuildKeys()
	if hooksecurefunc and HandleModifiedItemClick then
		hooksecurefunc("HandleModifiedItemClick", function(link, itemLocation)
			local ok, err = pcall(OnModifiedClick, link, itemLocation)
			if not ok then seen.why = "error: " .. tostring(err) end
		end)
	end
	local f = CreateFrame("Frame")
	for _, ev in ipairs({ "NEW_AUCTION_UPDATE", "AUCTION_HOUSE_CLOSED", "BAG_UPDATE", "GLOBAL_MOUSE_DOWN",
		"COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_HOUSE_POST_WARNING" }) do
		pcall(f.RegisterEvent, f, ev)
	end
	f:SetScript("OnEvent", function(_, event, ...)
		if event == "AUCTION_HOUSE_CLOSED" then
			Done()
		elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
			if pending and pending.kind == "new" then Done() end
		elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_UPDATED" then
			-- (the game's live price has arrived: ours goes under it, a moment after the game sets it)
			if pending and pending.kind == "new" and GetTime() - (pending.at or 0) < 4 then C_Timer.After(0.1, function() NewFill(false) end) end
		elseif event == "NEW_AUCTION_UPDATE" then
			if pending and pending.kind == "old" then
				if not OldInSlot() then Done()
				elseif not pending.filled then C_Timer.After(0, OldFill) end
			end
		elseif event == "GLOBAL_MOUSE_DOWN" then
			local ok, err = pcall(OnMouseDown, ...)
			if not ok then seen.why = "error: " .. tostring(err) end
		elseif event == "BAG_UPDATE" then
			HookBags() -- (bags opened later, or a new bag)
		end
	end)
end

-- (for the tests)
AH.OnAltRightClick, AH.HookBags, AH.OnMouseDown, AH.OnModifiedClick = OnAltRightClick, HookBags, OnMouseDown, OnModifiedClick
function AH.Pending() return pending end
