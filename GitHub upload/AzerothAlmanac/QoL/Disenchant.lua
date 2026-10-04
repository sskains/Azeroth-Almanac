-- Ported from Plus Everything (same author) for Azeroth Almanac's quality-of-life helpers.
-- Disenchant Estimator
-- Adds the expected disenchant value to tooltips of green, blue and purple armor and weapons.
--   Data: Data\DisenchantData.lua, the Classic 1.12 disenchant tables (VMaNGOS), grouped by
--   rarity, armor/weapon and item level. Looked up with the item's WoW Forever rarity and
--   item level; if that exact level has no data, the nearest level within NEAREST_LEVELS is
--   used and the line is marked "est.".
--   Learning: your own disenchants are recorded per group and blended in, so the estimate
--   follows WoW Forever's actual results as you disenchant more.
--   Prices: each material's price from Azeroth Almanac's own auction scan (Auction Prices module).
--   Hold Shift for the material breakdown. A "Best" line compares disenchanting with
--   the item's auction and vendor price.

local _, A = ...
local ns = A.QoL
local DE = ns:NewModule("Disenchant")

local DISENCHANT_SPELL = 13262
local NEAREST_LEVELS = 5
local LEARN_MIN = 5        -- your own results count once a group has this many disenchants
local LEARN_WEIGHT = 30    -- your results weigh n / (n + LEARN_WEIGHT) against the built-in data
local LOOT_WINDOW = 3      -- seconds after the cast in which the loot counts as the disenchant

local db
local data = ns.DisenchantData or { mats = {}, buckets = {} } -- the module itself is ns.Disenchant
local pending -- { link, key } while a disenchant is being cast
local armed   -- { key, time } after a successful cast, waiting for the loot

local function Money(copper)
	copper = math.floor(copper + 0.5)
	if GetMoneyString then return GetMoneyString(copper, true) end
	return GetCoinTextureString(copper)
end

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

---------------------------------------------------------------------------
-- Estimating
---------------------------------------------------------------------------

-- The data group for an item: "quality:class:itemLevel", or nil if it can't be disenchanted.
function DE.GroupFor(link)
	if not link then return end
	local _, _, quality, itemLevel, _, _, _, _, _, _, _, classID = GetInfo(link)
	if not quality or not itemLevel or quality < 2 or quality > 4 then return end
	if classID ~= 2 and classID ~= 4 then return end
	return quality, classID, itemLevel
end

-- Built-in table for a group, trying the exact item level first, then nearby levels.
local function BuiltIn(quality, classID, itemLevel)
	for offset = 0, NEAREST_LEVELS do
		for _, level in ipairs(offset == 0 and { itemLevel } or { itemLevel - offset, itemLevel + offset }) do
			local key = quality .. ":" .. classID .. ":" .. level
			local bucket = data.buckets[key]
			if bucket then return bucket, offset > 0 end
		end
	end
end

-- Expected results as a list of { mat, chance, qty } (qty = expected amount per disenchant).
function DE:Estimate(link)
	local quality, classID, itemLevel = DE.GroupFor(link)
	if not quality then return end
	local key = quality .. ":" .. classID .. ":" .. itemLevel
	local bucket, approximate = BuiltIn(quality, classID, itemLevel)
	local mine = db.learned[key]
	local n = mine and mine.n or 0
	local w = n >= LEARN_MIN and n / (n + LEARN_WEIGHT) or 0
	if not bucket and w == 0 then return end
	if not bucket then w = 1 end

	local results = {}
	local function add(mat, chance, qty)
		local r = results[mat] or { mat = mat, chance = 0, qty = 0 }
		r.chance, r.qty = r.chance + chance, r.qty + qty
		results[mat] = r
	end
	if bucket then
		for i = 2, #bucket, 3 do
			local chance, avg = bucket[i + 1], bucket[i + 2]
			add(bucket[i], (1 - w) * chance, (1 - w) * chance * avg)
		end
	end
	if w > 0 then
		for mat, m in pairs(mine.mats) do
			add(mat, w * m.hits / n, w * m.qty / n)
		end
	end

	local list = {}
	for _, r in pairs(results) do list[#list + 1] = r end
	table.sort(list, function(a, b) return a.chance > b.chance end)
	return list, {
		approximate = approximate and w < 1,
		observed = bucket and bucket[1] or 0,
		yours = n,
	}
end

local function MatPrice(mat)
	return ns.AuctionPrices and ns.AuctionPrices.PriceForItemID and ns.AuctionPrices:PriceForItemID(mat)
end

-- Total expected value in copper, and whether any material had no price.
function DE:Value(list)
	local total, missing = 0, false
	for _, r in ipairs(list) do
		local price = MatPrice(r.mat)
		if price then total = total + r.qty * price else missing = true end
	end
	return total, missing
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------

local function MatName(mat)
	return data.mats[mat] or GetInfo(mat) or ("item " .. mat)
end

-- Small inline icons for the "Best" line. The Disenchant icon comes from the spell itself;
-- Interface\Icons textures get their border trimmed (the 5:59 crop of a 64x64 icon).
local BEST_ICONS = {
	Auction = "Interface\\Icons\\INV_Misc_Coin_02",
	Vendor = "Interface\\GossipFrame\\VendorGossipIcon",
}

local function SpellIcon(spellID)
	if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(spellID) end
	return GetSpellTexture and GetSpellTexture(spellID)
end

local function BestIcon(option)
	local texture = BEST_ICONS[option]
	if option == "Disenchant" then
		texture = SpellIcon(DISENCHANT_SPELL) or "Interface\\Icons\\INV_Enchant_Disenchant"
	end
	if not texture then return "" end
	local isIcon = type(texture) == "number" or tostring(texture):lower():find("^interface\\icons\\")
	return ("|T%s:14:14:0:0%s|t"):format(texture, isIcon and ":64:64:5:59:5:59" or "")
end

local function AddLines(tooltip, link)
	if not db.tooltip then return end
	local list, info = DE:Estimate(link)
	if not list then return end
	local value, missing = DE:Value(list)
	local label = "Disenchant" .. (info.approximate and " |cff999999(est.)|r" or "")
	tooltip:AddDoubleLine(label, Money(value) .. (missing and " |cffff9933+?|r" or ""), 1, 0.82, 0, 1, 1, 1)

	if IsShiftKeyDown() then
		for _, r in ipairs(list) do
			local price = MatPrice(r.mat)
			tooltip:AddDoubleLine(("   %.2fx %s (%d%%)"):format(r.qty, MatName(r.mat), math.floor(r.chance * 100 + 0.5)),
				price and Money(r.qty * price) or "|cff999999no price|r", 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
		end
		local source = ("   Classic disenchant tables (%d items like it)"):format(info.observed)
		if info.yours > 0 then source = source .. (", %d of yours"):format(info.yours) end
		tooltip:AddLine(source, 0.5, 0.5, 0.5)
	end

	if db.bestHint then
		local options = {}
		if value > 0 then options[#options + 1] = { "Disenchant", value } end
		local auction = ns.AuctionPrices and ns.AuctionPrices:PriceFor(link)
		if auction then options[#options + 1] = { "Auction", auction.p } end
		local sell = select(11, GetInfo(link))
		if sell and sell > 0 then options[#options + 1] = { "Vendor", sell } end
		if #options >= 2 then
			table.sort(options, function(a, b) return a[2] > b[2] end)
			local best = options[1][1]
			tooltip:AddDoubleLine("Best", BestIcon(best) .. " " .. best, 1, 0.82, 0, 0.3, 1, 0.3)
		end
	end
end

local function HookTooltips()
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
			if not tooltip.GetItem then return end
			local _, link = tooltip:GetItem()
			AddLines(tooltip, link)
		end)
	else
		for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
			tooltip:HookScript("OnTooltipSetItem", function(self)
				local _, link = self:GetItem()
				AddLines(self, link)
			end)
		end
	end
end

---------------------------------------------------------------------------
-- Learning from your disenchants
---------------------------------------------------------------------------

local castSentAt -- when a Disenchant cast was last sent

-- Clicking a bag item while Disenchant is waiting for a target sends the cast (firing
-- UNIT_SPELLCAST_SENT) and then returns here, so a click right after the cast was sent is
-- the item being disenchanted.
local function OnUseContainerItem(bag, slot)
	if not castSentAt or GetTime() - castSentAt > 0.5 then return end
	local link = C_Container and C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot)
		or GetContainerItemLink and GetContainerItemLink(bag, slot)
	if link then pending = { link = link, time = GetTime() } end
end

local function KeyFor(link)
	local quality, classID, itemLevel = DE.GroupFor(link)
	return quality and (quality .. ":" .. classID .. ":" .. itemLevel)
end

local function RecordLoot()
	if not armed or GetTime() - armed.time > LOOT_WINDOW then return end
	local key = armed.key
	armed = nil
	local mine = db.learned[key] or { n = 0, mats = {} }
	local got = false
	for slot = 1, GetNumLootItems() do
		local link = GetLootSlotLink(slot)
		local mat = link and tonumber(link:match("item:(%d+)"))
		if mat and data.mats[mat] then
			local quantity = select(3, GetLootSlotInfo(slot)) or 1
			local m = mine.mats[mat] or { hits = 0, qty = 0 }
			m.hits, m.qty = m.hits + 1, m.qty + quantity
			mine.mats[mat] = m
			got = true
		end
	end
	if got then
		mine.n = mine.n + 1
		db.learned[key] = mine
	end
end

local function OnEvent(_, event, ...)
	if event == "UNIT_SPELLCAST_SENT" then
		local unit, target, _, spellID = ... -- unit, target name, castGUID, spellID
		if unit == "player" and spellID == DISENCHANT_SPELL then
			castSentAt = GetTime()
			pending = nil
			-- Fallback in case the bag hook doesn't see the click: look the item up by name.
			-- The bag hook runs right after this and replaces it with the exact item.
			if target and target ~= "" then
				local _, link = GetInfo(target)
				if link then pending = { link = link, time = GetTime() } end
			end
		end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local unit, _, spellID = ... -- unit, castGUID, spellID
		if unit == "player" and spellID == DISENCHANT_SPELL then
			local key = pending and KeyFor(pending.link)
			pending = nil
			if key and db.learn then armed = { key = key, time = GetTime() } end
		end
	elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
		local unit, _, spellID = ...
		if unit == "player" and spellID == DISENCHANT_SPELL then pending = nil end
	elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
		RecordLoot()
	end
end

---------------------------------------------------------------------------
-- Module API
---------------------------------------------------------------------------

function DE:OnInitialize(saved)
	db = saved.disenchant
end

function DE:OnLogin()
	HookTooltips()
	if C_Container and C_Container.UseContainerItem then
		hooksecurefunc(C_Container, "UseContainerItem", OnUseContainerItem)
	elseif UseContainerItem then
		hooksecurefunc("UseContainerItem", OnUseContainerItem)
	end
	local events = CreateFrame("Frame")
	for _, event in ipairs({
		"UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
		"UNIT_SPELLCAST_INTERRUPTED", "LOOT_READY", "LOOT_OPENED",
	}) do
		events:RegisterEvent(event)
	end
	events:SetScript("OnEvent", OnEvent)
end

function DE:Status()
	local disenchants, groups = 0, 0
	for _, mine in pairs(db.learned) do
		disenchants, groups = disenchants + mine.n, groups + 1
	end
	local priced, mats = 0, 0
	for mat in pairs(data.mats) do
		mats = mats + 1
		if MatPrice(mat) then priced = priced + 1 end
	end
	return disenchants, groups, priced, mats
end

function DE:ForgetLearned()
	wipe(db.learned)
end
