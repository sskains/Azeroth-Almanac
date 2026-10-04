-- Ported from Plus Everything (same author) for Azeroth Almanac's quality-of-life helpers.
-- Auction Prices
-- Full-scans the auction house and adds "Vendor" and "Auction" lines to item tooltips.
--   Scan: a button beside the auction house window (or /aa scan) runs the game's full
--   scan (C_AuctionHouse.ReplicateItems). Blizzard allows one every 15 minutes.
--   Prices: lowest buyout per single item, kept per realm and faction and shared by all
--   your characters, plus each day's low for the last HISTORY_DAYS days.
--   Tooltip: last known price, how old it is, the average of the daily lows, and the
--   whole-stack price while holding Shift.
--   Automatic scans: when the auction house is open and the cooldown allows (setting).
--   Every listing is also handed to AuctionVolume, which estimates sales from scan to scan.

local _, A = ...
local ns = A.QoL
local AP = ns:NewModule("AuctionPrices")

local SCAN_COOLDOWN = 15 * 60
local HISTORY_DAYS = 7
local BATCH_SIZE = 1000         -- auctions read per frame, so big scans don't freeze the game
local RETRY_DELAY = 2           -- seconds to wait before re-reading auctions whose item info wasn't loaded
local SCAN_TIMEOUT = 90         -- give up if the game hasn't sent the scan by then
local AUTO_RETRY = 120          -- after a failed automatic scan, wait this long before trying again

local db
local scan -- current scan state, or nil
local scanButton
local lastAutoAttempt = 0

local function Today()
	return math.floor(time() / 86400)
end

local function RealmKey()
	return (GetRealmName() or "?") .. " - " .. (UnitFactionGroup("player") or "?")
end

local function RealmData()
	local key = RealmKey()
	db.realms[key] = db.realms[key] or { items = {}, lastScan = 0 }
	return db.realms[key]
end

-- Items with a random suffix ("of the Bear") are priced separately from the plain item.
function AP.ItemKey(link)
	if not link then return end
	local id, _, _, _, _, _, suffix = link:match("item:(%-?%d*):(%-?%d*):(%-?%d*):(%-?%d*):(%-?%d*):(%-?%d*):(%-?%d*)")
	if not id or id == "" then return end
	if suffix and suffix ~= "" and suffix ~= "0" then return id .. ":" .. suffix end
	return id
end

local function Money(copper)
	copper = math.floor(copper + 0.5)
	if GetMoneyString then return GetMoneyString(copper, true) end
	return GetCoinTextureString(copper)
end

local function AgeText(seconds)
	if seconds < 3600 then return ("%dm ago"):format(math.max(1, math.floor(seconds / 60))) end
	if seconds < 86400 then return ("%dh ago"):format(math.floor(seconds / 3600)) end
	return ("%dd ago"):format(math.floor(seconds / 86400))
end

---------------------------------------------------------------------------
-- Scanning
---------------------------------------------------------------------------

function AP:SecondsUntilScan()
	return math.max(0, RealmData().lastScan + SCAN_COOLDOWN - time())
end

local function UpdateScanButton()
	if not scanButton then return end
	if scan then
		scanButton:SetText(scan.total and ("Scanning %d%%"):format(math.floor(100 * scan.index / math.max(1, scan.total))) or "Waiting...")
		scanButton:Disable()
		return
	end
	local wait = AP:SecondsUntilScan()
	if wait > 0 then
		scanButton:SetText(("Scan in %d:%02d"):format(math.floor(wait / 60), wait % 60))
		scanButton:Disable()
	else
		scanButton:SetText("Full scan")
		scanButton:Enable()
	end
end

local function Record(lows, index)
	local info = { C_AuctionHouse.GetReplicateItemInfo(index) }
	local count, buyout, itemID, hasAllInfo = info[3], info[10], info[17], info[18]
	if not itemID or not buyout or buyout <= 0 or not count or count <= 0 then return true end
	local key = AP.ItemKey(C_AuctionHouse.GetReplicateItemLink(index))
	if not key then
		if not hasAllInfo and not scan.retrying then return false end
		key = tostring(itemID) -- item info never arrived; fall back to the plain item
	end
	local unit = buyout / count
	if not lows[key] or unit < lows[key] then lows[key] = unit end
	if ns.AuctionVolume then
		local timeLeft = C_AuctionHouse.GetReplicateItemTimeLeft and C_AuctionHouse.GetReplicateItemTimeLeft(index)
		ns.AuctionVolume:OnListing(itemID, count, buyout, info[15] or info[14], timeLeft)
	end
	return true
end

local function Finish()
	local realm = RealmData()
	local now, today = time(), Today()
	local items = 0
	for key, price in pairs(scan.lows) do
		items = items + 1
		local entry = realm.items[key] or { h = {} }
		entry.p, entry.t = math.floor(price + 0.5), now
		entry.h = entry.h or {}
		if not entry.h[today] or price < entry.h[today] then entry.h[today] = math.floor(price + 0.5) end
		for day in pairs(entry.h) do
			if day <= today - HISTORY_DAYS then entry.h[day] = nil end
		end
		realm.items[key] = entry
	end
	realm.lastScan = now
	if not scan.quiet then
		ns.Print(("Auction scan done: %d auctions, prices for %d items (%s)."):format(scan.total, items, RealmKey()))
	end
	if ns.AuctionVolume then ns.AuctionVolume:OnScanDone() end
	scan = nil
	UpdateScanButton()
	if ns.Settings and ns.Settings.RefreshAuction then ns.Settings:RefreshAuction() end
end

local worker = CreateFrame("Frame")
worker:Hide()
worker:SetScript("OnUpdate", function(self)
	if not scan or not scan.total then return end
	local last = math.min(scan.index + BATCH_SIZE, scan.total)
	for i = scan.index, last - 1 do
		if not Record(scan.lows, i) then scan.pending[#scan.pending + 1] = i end
	end
	scan.index = last
	UpdateScanButton()
	if scan.index < scan.total then return end

	self:Hide()
	if #scan.pending > 0 and not scan.retrying then
		-- Some item details were still loading; give the game a moment, then read those again.
		scan.retrying = true
		C_Timer.After(RETRY_DELAY, function()
			if not scan then return end
			for _, i in ipairs(scan.pending) do Record(scan.lows, i) end
			Finish()
		end)
	else
		Finish()
	end
end)

-- quiet: an automatic scan, which doesn't announce itself in chat.
function AP:StartScan(quiet)
	if scan then return quiet or ns.Print("A scan is already running.") end
	if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
		return quiet or ns.Print("Open the auction house first.")
	end
	local wait = self:SecondsUntilScan()
	if wait > 0 then
		return quiet or ns.Print(("Blizzard allows one full scan every 15 minutes. Next scan in %d:%02d."):format(math.floor(wait / 60), wait % 60))
	end
	scan = { lows = {}, pending = {}, index = 0, started = GetTime(), quiet = quiet }
	if ns.AuctionVolume then ns.AuctionVolume:OnScanStart() end
	C_AuctionHouse.ReplicateItems()
	if not quiet then ns.Print("Auction scan started. This can take a minute on a busy auction house.") end
	UpdateScanButton()
	C_Timer.After(SCAN_TIMEOUT, function()
		if scan and not scan.total then
			if not scan.quiet then ns.Print("The auction house didn't send the scan. Try again in a few minutes.") end
			scan = nil
			if ns.AuctionVolume then ns.AuctionVolume:OnScanAbort() end
			UpdateScanButton()
		end
	end)
end

-- Starts a quiet scan when automatic scanning is on and the cooldown allows.
local function AutoScan()
	if not db.autoScan or scan or AP:SecondsUntilScan() > 0 then return end
	if time() - lastAutoAttempt < AUTO_RETRY then return end
	if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return end
	lastAutoAttempt = time()
	AP:StartScan(true)
end

local function OnReplicateReady()
	if not scan or scan.total then return end
	scan.total = C_AuctionHouse.GetNumReplicateItems()
	worker:Show()
end

local function CreateScanButton()
	if scanButton or not AuctionHouseFrame then return end
	scanButton = CreateFrame("Button", "AzerothAlmanacAuctionScanButton", AuctionHouseFrame, "UIPanelButtonTemplate")
	scanButton:SetSize(120, 24)
	scanButton:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, -30)
	scanButton:SetScript("OnClick", function() AP:StartScan() end)
	scanButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Azeroth Almanac full scan")
		GameTooltip:AddLine("Reads every auction and saves the lowest price per item for tooltips. Blizzard allows one every 15 minutes.", 1, 1, 1, true)
		if db.autoScan then GameTooltip:AddLine("Automatic scanning is on: a scan starts by itself whenever one is allowed.", 0.4, 0.8, 1, true) end
		GameTooltip:Show()
	end)
	scanButton:SetScript("OnLeave", GameTooltip_Hide)
	local elapsed = 0
	scanButton:SetScript("OnUpdate", function(_, e)
		elapsed = elapsed + e
		if elapsed >= 1 then
			elapsed = 0
			UpdateScanButton()
			AutoScan()
		end
	end)
	UpdateScanButton()
end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------

function AP:PriceFor(link)
	local key = AP.ItemKey(link)
	local items = key and RealmData().items
	return items and (items[key] or (key:find(":") and items[key:match("^%d+")]))
end

function AP:PriceForItemID(itemID)
	local entry = RealmData().items[tostring(itemID)]
	return entry and entry.p
end

local function AverageOf(history)
	local sum, n = 0, 0
	for _, price in pairs(history or {}) do sum, n = sum + price, n + 1 end
	return n > 1 and sum / n or nil, n
end

-- A guildmate's scan: take their lowest price when it's newer than ours.
function AP:ApplySharedPrice(itemID, price, t)
	if not itemID or not price or price <= 0 or not t or t > time() + 600 then return end
	local items = RealmData().items
	local key = tostring(itemID)
	local entry = items[key] or { h = {} }
	if entry.t and entry.t >= t then return end
	entry.p, entry.t = price, t
	entry.h = entry.h or {}
	local day = math.floor(t / 86400)
	if not entry.h[day] or price < entry.h[day] then entry.h[day] = price end
	items[key] = entry
end

-- Average of the recent daily lows (needs two or more days of scans), and how many days.
function AP:AverageForItemID(itemID)
	local entry = RealmData().items[tostring(itemID)]
	if not entry then return end
	return AverageOf(entry.h)
end

-- Stack size of the bag item the tooltip is showing, when the game tells us.
local function StackCount(data)
	if data and data.guid and C_Item and C_Item.GetItemLocation and C_Item.GetStackCount then
		local location = C_Item.GetItemLocation(data.guid)
		if location and location:IsValid() then return C_Item.GetStackCount(location) end
	end
	return 1
end

local function AddLines(tooltip, link, data)
	if not db.tooltip or not link then return end
	local count = IsShiftKeyDown() and db.stackOnShift and StackCount(data) or 1
	local suffix = count > 1 and (" x" .. count) or ""
	local added = false

	if db.vendor then
		local sell = select(11, (C_Item and C_Item.GetItemInfo or GetItemInfo)(link))
		if sell and sell > 0 then
			tooltip:AddDoubleLine("Vendor" .. suffix, Money(sell * count), 1, 0.82, 0, 1, 1, 1)
			added = true
		end
	end

	local entry = AP:PriceFor(link)
	if entry then
		local label = "Auction" .. suffix
		if db.age then label = label .. " |cff999999(" .. AgeText(time() - entry.t) .. ")|r" end
		tooltip:AddDoubleLine(label, Money(entry.p * count), 1, 0.82, 0, 1, 1, 1)
		if db.average then
			local avg, days = AverageOf(entry.h)
			if avg then
				tooltip:AddDoubleLine(("Auction %d-day avg"):format(days) .. suffix, Money(avg * count), 1, 0.82, 0, 1, 1, 1)
			end
		end
		added = true
	end
	return added
end

local function HookTooltips()
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
			if not tooltip.GetItem then return end
			local _, link = tooltip:GetItem()
			AddLines(tooltip, link, data)
		end)
	else
		for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
			tooltip:HookScript("OnTooltipSetItem", function(self)
				local _, link = self:GetItem()
				if AddLines(self, link) then self:Show() end
			end)
		end
	end
end

---------------------------------------------------------------------------
-- Module API
---------------------------------------------------------------------------

function AP:OnInitialize(saved)
	db = saved.auction
end

function AP:OnLogin()
	HookTooltips()
	local events = CreateFrame("Frame")
	events:RegisterEvent("AUCTION_HOUSE_SHOW")
	events:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
	events:SetScript("OnEvent", function(_, event)
		if event == "AUCTION_HOUSE_SHOW" then
			CreateScanButton()
			UpdateScanButton()
		elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
			OnReplicateReady()
		end
	end)
	if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Auctionator") then
		ns.Print("Auctionator is also enabled, so tooltips will show both prices. Disable Auctionator in the AddOns list once you're happy with Azeroth Almanac's prices.")
	end
end

function AP:Status()
	local realm = RealmData()
	local items = 0
	for _ in pairs(realm.items) do items = items + 1 end
	return RealmKey(), items, realm.lastScan
end

function AP:ForgetRealm()
	db.realms[RealmKey()] = nil
end
