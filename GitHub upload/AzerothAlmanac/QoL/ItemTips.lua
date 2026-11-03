-- Item Tooltips
-- Two small lines on item tooltips, beside the vendor, auction and disenchant lines the other
-- modules add:
--   Item level: gear shows its item level when the game's own tooltip doesn't already.
--   Journal:    whether the item is in your Almanac, and how it was first found; "not in your
--               journal yet" for an uncommon-or-better item you have never come across.

local _, A = ...
local ns = A.QoL
local IT = ns:NewModule("ItemTips")

local db

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local HOW = {
	looted = "looted", received = "received", crafted = "crafted", bought = "bought",
	merchant = "seen on a merchant", reward = "offered as a quest reward", carried = "carried",
}

-- True if the tooltip already has a line matching the pattern (the game's own item level line).
local function HasLine(tooltip, pattern)
	local name = tooltip.GetName and tooltip:GetName()
	if not name then return false end
	for i = 2, tooltip:NumLines() do
		local line = _G[name .. "TextLeft" .. i]
		local text = line and line:GetText()
		if text and text:find(pattern) then return true end
	end
	return false
end

local function ItemLevelPattern()
	local format = ITEM_LEVEL or "Item Level %d"
	return (format:gsub("%%d", "%%d+"):gsub("%-", "%%-"))
end

-- What the Almanac knows about the item, as the text for the right-hand side of the line.
function IT.JournalText(id, quality)
	local store = A.Store
	local rec = store and store:Get("item", id)
	if not rec then
		if quality and quality >= 2 then return "|cff999999not in your journal yet|r" end
		return
	end
	local how = HOW[rec.how] or "found"
	local source
	local creature = rec.how == "looted" and rec.src and rec.src.creature
	if creature then
		local best, bestN
		for npc, n in pairs(creature) do
			if not bestN or n > bestN then best, bestN = npc, n end
		end
		local found = best and store:Get("creature", best)
		source = found and found.name
	end
	return "|cff66dd66" .. how .. (source and (" from " .. source) or "") .. "|r"
end

local function AddLines(tooltip, link)
	if not link then return end
	local _, _, quality, itemLevel, _, _, _, _, equipLoc = GetInfo(link)
	local added = false

	if db.level and itemLevel and itemLevel > 1 and equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_BAG"
		and not HasLine(tooltip, ItemLevelPattern()) then
		tooltip:AddDoubleLine("Item level", itemLevel, 1, 0.82, 0, 1, 1, 1)
		added = true
	end

	if db.journal then
		local id = tonumber(tostring(link):match("item:(%d+)"))
		local text = id and IT.JournalText(id, quality)
		if text then
			tooltip:AddDoubleLine("Journal", text, 1, 0.82, 0, 1, 1, 1)
			added = true
		end
	end
	return added
end

local function HookTooltips()
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
			if not tooltip.GetItem then return end
			local _, link = tooltip:GetItem()
			pcall(AddLines, tooltip, link)
		end)
	else
		for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
			tooltip:HookScript("OnTooltipSetItem", function(self)
				local _, link = self:GetItem()
				local ok, added = pcall(AddLines, self, link)
				if ok and added then self:Show() end
			end)
		end
	end
end

function IT:OnInitialize(saved)
	db = saved.itemTips
end

function IT:OnLogin()
	HookTooltips()
end
