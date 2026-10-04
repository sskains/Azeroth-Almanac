-- Merchants: every vendor a character opens, shared by the whole account.
-- found.merchant[npcID] = { name, title, map, x, y, zone, sub, reaction (your standing with them
--   when last checked: 4 neutral, 5 friendly, 6 honored, 7 revered, 8 exalted), checked = time,
--   stock = { { id, name, price, stack, avail (-1 = unlimited), cost = "item:count;..." }, ... },
--   was = { [itemID] = { price, time } }   an item's previous price when it changed }
-- Every item on sale is recorded (quietly) as an item you've seen, sold by this merchant.

local _, ns = ...
local L = ns.L
local M = ns:NewModule("Merchants")
local R = ns.Readable

local function ItemID(link)
	link = R(link)
	if type(link) ~= "string" then return nil end
	return tonumber(link:match("item:(%d+)"))
end

-- the NPC's title ("<Weaponsmith>") is the second line of its tooltip
local function Title(unit)
	if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
	local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
	if not ok or type(data) ~= "table" or ns.IsSecret(data) then return nil end
	local lines = R(data.lines)
	local line = type(lines) == "table" and lines[2] and R(lines[2].leftText)
	if type(line) == "string" and not line:find("%d") then return line end
end

local function ReadItem(i)
	local info
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
		local ok, t = pcall(C_MerchantFrame.GetItemInfo, i)
		if ok and type(t) == "table" then info = t end
	end
	if not info and GetMerchantItemInfo then
		local ok, name, _, price, stack, avail, _, extended = pcall(GetMerchantItemInfo, i)
		if ok then info = { name = name, price = price, stackCount = stack, numAvailable = avail, hasExtendedCost = extended } end
	end
	if not info then return nil end
	local id = ItemID(GetMerchantItemLink(i)) or (GetMerchantItemID and R(GetMerchantItemID(i)))
	if not id then return nil end
	local e = { id = id, name = R(info.name), price = R(info.price) or 0, stack = R(info.stackCount) or 1, avail = R(info.numAvailable) or -1 }
	if R(info.hasExtendedCost) and GetMerchantItemCostInfo then
		local okN, n = pcall(GetMerchantItemCostInfo, i)
		local parts = {}
		for j = 1, (okN and R(n) or 0) do
			local okC, _, value, link, currency = pcall(GetMerchantItemCostItem, i, j)
			if okC then
				local cid = ItemID(link)
				parts[#parts + 1] = (cid and ("i" .. cid) or ("c" .. tostring(R(currency) or "?"))) .. ":" .. tostring(R(value) or 0)
			end
		end
		if #parts > 0 then e.cost = table.concat(parts, ";") end
	end
	return e
end

function M:Read()
	local guid = R(UnitGUID("npc"))
	local npc = ns.NpcFromGuid(guid)
	if not npc then return end
	local okN, n = pcall(GetMerchantNumItems)
	n = okN and R(n) or 0
	local stock = {}
	for i = 1, n do
		local e = ReadItem(i)
		if e then stock[#stock + 1] = e end
	end
	local where = ns.Where()
	local name = R(UnitName("npc"))
	local existing = ns.Store:Get("merchant", npc)
	local fields = {
		name = name, title = Title("npc"), reaction = R(UnitReaction("npc", "player")),
		zone = where.zone, sub = where.sub, map = where.map,
	}
	if not existing or not existing.x then fields.x, fields.y = where.x, where.y end
	local text = name and (where.sub and where.sub ~= "" and (L["%s, %s"]):format(name, where.sub) or name) or "?"
	local rec = ns.Store:Discover("merchant", npc, fields, text, where)
	-- their face, from the merchant you're talking to
	if rec and not rec.display and ns.Bestiary and ns.Bestiary.FaceFromUnit then pcall(ns.Bestiary.FaceFromUnit, ns.Bestiary, "npc", npc, "merchant") end
	if not rec then return end
	-- price changes since the last visit
	rec.was = rec.was or {}
	local before = {}
	for _, e in ipairs(rec.stock or {}) do before[e.id] = e.price end
	for _, e in ipairs(stock) do
		if before[e.id] and before[e.id] ~= e.price then rec.was[e.id] = { before[e.id], rec.checked } end
	end
	rec.stock = stock
	rec.checked = time()
	for _, e in ipairs(stock) do ns.Items:Found(e.id, "merchant", "merchant", npc, true, where) end
	ns:Fire("CHANGED", "merchant", npc)
end

-- the merchant window fills its pages a moment after it opens, and updates as you buy
local pending = false
local function Soon()
	if pending or not ns.db then return end
	pending = true
	C_Timer.After(0.6, function()
		pending = false
		ns.doing = "reading a merchant"
		M:Read()
		ns.doing = "idle"
	end)
end
ns:RegisterEvent("MERCHANT_SHOW", Soon)
ns:RegisterEvent("MERCHANT_UPDATE", Soon)

-- merchants that have this item on sale: { { npc, rec, entry }, ... }
function M:Selling(itemID)
	local out = {}
	for npc, rec in pairs(ns.Store:All("merchant")) do
		for _, e in ipairs(rec.stock or {}) do
			if e.id == itemID then out[#out + 1] = { npc = npc, rec = rec, e = e } break end
		end
	end
	table.sort(out, function(a, b) return (a.e.price or 0) < (b.e.price or 0) end)
	return out
end

-- buying an item also records where it came from
if hooksecurefunc and BuyMerchantItem then
	hooksecurefunc("BuyMerchantItem", function(index)
		local id = ItemID(GetMerchantItemLink(index))
		local npc = ns.NpcFromGuid(R(UnitGUID("npc")))
		if id and ns.db then
			local rec = ns.Items:Found(id, "bought", "merchant", npc or 0, true)
			if rec then rec.bought = (rec.bought or 0) + 1 end
		end
	end)
end
