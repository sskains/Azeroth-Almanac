-- Ported from Plus Everything (same author) for Azeroth Almanac's quality-of-life helpers.
-- Merchant: when you open a vendor, repairs your gear (optionally from guild funds first) and
-- sells your grey junk, then says what it did in chat. Each part has its own switch.
-- Also: at a quest turn-in with reward choices, the one that sells to a vendor for the most gets a
-- gold coin in the bottom right corner (merchant.bestReward).

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
-- Quest turn-in: a gold coin on the reward choice worth the most at a vendor
---------------------------------------------------------------------------

local marks = {}          -- button -> coin texture
local retry = false

local function ClearMarks()
	for _, coin in pairs(marks) do coin:Hide() end
end

-- the reward choice buttons by choice index (the quest frame's shared QuestInfo buttons)
local function ChoiceButtons()
	local out = {}
	local rf = QuestInfoRewardsFrame or (QuestInfoFrame and QuestInfoFrame.rewardsFrame)
	local list = rf and rf.RewardButtons
	if not list then
		list = {}
		for i = 1, 12 do list[i] = _G["QuestInfoRewardsFrameQuestInfoItem" .. i] end
	end
	for _, b in pairs(list) do
		if b and b:IsVisible() and b.type == "choice" and b.GetID then out[b:GetID()] = b end
	end
	return out
end

local function Coin(button)
	local coin = marks[button]
	if coin then return coin end
	coin = button:CreateTexture(nil, "OVERLAY", nil, 7)
	coin:SetSize(16, 16)
	local icon = button.Icon or (button.GetName and button:GetName() and _G[button:GetName() .. "IconTexture"])
	coin:SetPoint("BOTTOMRIGHT", icon or button, "BOTTOMRIGHT", 3, -3)
	local ok = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Coin-Gold") and pcall(coin.SetAtlas, coin, "Coin-Gold")
	if not ok then coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon") end
	marks[button] = coin
	return coin
end

local function MarkBestReward()
	ClearMarks()
	if not (db and db.bestReward) then return end
	if not (QuestFrameRewardPanel and QuestFrameRewardPanel:IsVisible()) then return end
	local n = GetNumQuestChoices and GetNumQuestChoices() or 0
	if n < 2 then return end
	local values, best, waiting = {}, 0, false
	for i = 1, n do
		local link = GetQuestItemLink and GetQuestItemLink("choice", i)
		local _, _, count = GetQuestItemInfo("choice", i)
		local price = link and select(11, GetInfo(link))
		if price == nil then waiting = true end
		values[i] = (price or 0) * math.max(1, count or 1)
		if values[i] > best then best = values[i] end
	end
	if waiting and not retry then
		-- item info still arriving: look again in a moment
		retry = true
		C_Timer.After(0.5, function() retry = false MarkBestReward() end)
	end
	if best <= 0 then return end
	local buttons = ChoiceButtons()
	for i = 1, n do
		if values[i] == best and buttons[i] then Coin(buttons[i]):Show() end
	end
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

	-- the quest frame lays its reward buttons out on QUEST_COMPLETE; mark after it has
	local quest = CreateFrame("Frame")
	for _, e in ipairs({ "QUEST_COMPLETE", "QUEST_FINISHED", "QUEST_DETAIL", "QUEST_PROGRESS", "GET_ITEM_INFO_RECEIVED" }) do
		pcall(quest.RegisterEvent, quest, e)
	end
	quest:SetScript("OnEvent", function(_, event)
		if event == "QUEST_COMPLETE" then
			C_Timer.After(0.05, MarkBestReward)
			C_Timer.After(0.4, MarkBestReward)
		elseif event == "GET_ITEM_INFO_RECEIVED" then
			if next(marks) and QuestFrameRewardPanel and QuestFrameRewardPanel:IsVisible() and not retry then
				retry = true
				C_Timer.After(0.2, function() retry = false MarkBestReward() end)
			end
		else
			ClearMarks()
		end
	end)
	-- the map's quest details reuse the same buttons: never leave a coin on them there
	if QuestInfo_Display then hooksecurefunc("QuestInfo_Display", function() ClearMarks() C_Timer.After(0.05, MarkBestReward) end) end
end

-- For the settings page: what's in your bags right now.
function MR:JunkValue()
	local total, items = 0, 0
	for _, e in ipairs(Junk()) do total, items = total + e[4], items + e[3] end
	return items, total
end
