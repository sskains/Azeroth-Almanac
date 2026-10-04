-- Ported from Plus Everything (same author) for Azeroth Almanac's quality-of-life helpers.
-- Merchant: when you open a vendor, repairs your gear (optionally from guild funds first) and
-- sells your grey junk, then says what it did in chat. Each part has its own switch.

local _, A = ...
local ns = A.QoL
local MR = ns:NewModule("Merchant")

local SELL_DELAY = 0.2    -- let the merchant window settle first
local SELL_STEP = 0.15    -- between items when selling one by one

local db

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local Container = C_Container or {}

local function Money(copper)
	copper = math.floor((copper or 0) + 0.5)
	return GetMoneyString and GetMoneyString(copper, true) or GetCoinTextureString(copper)
end

local function Report(text)
	if db.report then ns.Print(text) end
end

---------------------------------------------------------------------------
-- Repair
---------------------------------------------------------------------------

local function Repair()
	if not db.repair or not (CanMerchantRepair and CanMerchantRepair()) then return end
	local cost, canRepair = GetRepairAllCost()
	if not canRepair or not cost or cost <= 0 then return end
	if db.guildRepair and IsInGuild() and CanGuildBankRepair and CanGuildBankRepair() then
		RepairAllItems(true)
		C_Timer.After(0.3, function()
			local left = GetRepairAllCost()
			if left and left > 0 then
				-- Guild funds didn't cover it (limit or empty bank): pay the rest yourself.
				if GetMoney() >= left then
					RepairAllItems()
					Report(("Repaired: %s from guild funds, %s from your gold."):format(Money(cost - left), Money(left)))
				else
					Report(("Repaired %s from guild funds; %s more needed, which you can't afford."):format(Money(cost - left), Money(left)))
				end
			else
				Report(("Repaired for %s from guild funds."):format(Money(cost)))
			end
		end)
		return
	end
	if GetMoney() < cost then
		Report(("Repairs cost %s, which you can't afford right now."):format(Money(cost)))
		return
	end
	RepairAllItems()
	Report(("Repaired for %s."):format(Money(cost)))
end

---------------------------------------------------------------------------
-- Sell junk
---------------------------------------------------------------------------

-- Grey items with a sell price: { { bag, slot, count, value }, ... }
local function Junk()
	local list = {}
	local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
	for bag = 0, last do
		for slot = 1, (Container.GetContainerNumSlots and Container.GetContainerNumSlots(bag) or 0) do
			local info = Container.GetContainerItemInfo(bag, slot)
			if info and info.quality == 0 and not info.hasNoValue and not info.isLocked then
				local sell = select(11, GetInfo(info.hyperlink or info.itemID))
				if sell and sell > 0 then
					tinsert(list, { bag, slot, info.stackCount or 1, sell * (info.stackCount or 1) })
				end
			end
		end
	end
	return list
end

local function SellJunk()
	if not db.sellJunk then return end
	local list = Junk()
	if #list == 0 then return end
	local total, items = 0, 0
	for _, e in ipairs(list) do total, items = total + e[4], items + e[3] end

	-- The game's own "sell all junk" when this client has it.
	if C_MerchantFrame and C_MerchantFrame.SellAllJunkItems and (not C_MerchantFrame.IsSellAllJunkEnabled or C_MerchantFrame.IsSellAllJunkEnabled()) then
		local ok = pcall(C_MerchantFrame.SellAllJunkItems)
		if ok then
			Report(("Sold %d junk %s for %s."):format(items, items == 1 and "item" or "items", Money(total)))
			return
		end
	end

	-- Otherwise one by one, a moment apart, stopping if the merchant window closes.
	local i = 0
	local function Next()
		i = i + 1
		local e = list[i]
		if not e or not (MerchantFrame and MerchantFrame:IsShown()) then
			if i > 1 then Report(("Sold %d junk %s for %s."):format(items, items == 1 and "item" or "items", Money(total))) end
			return
		end
		pcall(Container.UseContainerItem, e[1], e[2])
		C_Timer.After(SELL_STEP, Next)
	end
	Next()
end

---------------------------------------------------------------------------
-- Module API
---------------------------------------------------------------------------

function MR:OnInitialize(saved)
	db = saved.merchant
end

function MR:OnLogin()
	local events = CreateFrame("Frame")
	events:RegisterEvent("MERCHANT_SHOW")
	events:SetScript("OnEvent", function()
		C_Timer.After(SELL_DELAY, function()
			Repair()
			SellJunk()
		end)
	end)
end

-- For the settings page: what's in your bags right now.
function MR:JunkValue()
	local total, items = 0, 0
	for _, e in ipairs(Junk()) do total, items = total + e[4], items + e[3] end
	return items, total
end
