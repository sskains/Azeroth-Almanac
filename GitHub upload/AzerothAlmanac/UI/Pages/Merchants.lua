-- Merchants are part of the People page (0.55.0): this file keeps a merchant's blocks for it
-- (ns.MerchantBlocks: your standing, the stock with prices, limited quantities, special costs and
-- price changes) and the old "merchants" page key as an alias of People. (The page itself went in 0.64.0.)

local _, ns = ...
local L = ns.L

local STANDING = { [1] = L["Hated"], [2] = L["Hostile"], [3] = L["Unfriendly"], [4] = L["Neutral"], [5] = L["Friendly"], [6] = L["Honored"], [7] = L["Revered"], [8] = L["Exalted"] }

local NOTE = "|cffbfbfbf"

local function PriceText(e) return ns.CostText(e.price, e.cost) end

local function Describe(npc, rec)
	local b = {}
	b[#b + 1] = { "banner", L["General"] }
	if rec.title then b[#b + 1] = { "stat", L["Title"], rec.title } end
	b[#b + 1] = { "stat", L["Where"], (rec.sub and rec.sub ~= "" and (rec.sub .. ", ") or "") .. (rec.zone or "?") }
	if rec.x then b[#b + 1] = { "stat", L["Coordinates"], ("%.1f, %.1f"):format(rec.x, rec.y) } end
	b[#b + 1] = { "stat", L["Your standing"], STANDING[rec.reaction or 0] or "?" }
	b[#b + 1] = { "stat", L["Stock checked"], ns.AgoText(rec.checked) }
	b[#b + 1] = { "stat", L["First visited"], ns.CharName(rec.b) .. ", " .. ns.DateText(rec.f) }
	local who = {}
	for key in pairs(rec.c or {}) do if key ~= rec.b then who[#who + 1] = ns.CharName(key) end end
	table.sort(who)
	if #who > 0 then b[#b + 1] = { "stat", L["Also visited by"], table.concat(who, ", ") } end
	b[#b + 1] = { "stat", L["Visits"], tostring(rec.n or 1) }

	b[#b + 1] = { "banner", (L["For sale (%d)"]):format(#(rec.stock or {})) }
	local slots = {}
	for _, e in ipairs(rec.stock or {}) do
		local note = PriceText(e)
		if (e.stack or 1) > 1 then note = note .. NOTE .. "  x" .. e.stack .. "|r" end
		local tip = {}
		if (e.avail or -1) >= 0 then tip[#tip + 1] = (L["Limited: %d left when checked."]):format(e.avail) end
		local was = rec.was and rec.was[e.id]
		if was then
			tip[#tip + 1] = (L["Was %s on %s."]):format(ns.MoneyText(was[1]), ns.DateText(was[2]))
			note = note .. NOTE .. "  " .. L["(price changed)"] .. "|r"
		end
		slots[#slots + 1] = { item = e.id, note = note, extra = #tip > 0 and table.concat(tip, " ") or nil }
	end
	if #slots > 0 then b[#b + 1] = { "slots", slots } else b[#b + 1] = { "small", L["Nothing for sale when last checked."] } end
	b[#b + 1] = { "small", L["Prices include the reputation discount you had at the time."] }
	return b
end

-- (0.69.0, #42) a merchant's facts for the portrait's tooltip on their People page
function ns.MerchantFacts(npc)
	local rec = npc and ns.Store:Get("merchant", npc)
	if not rec then return {} end
	return {
		{ L["Your standing"], STANDING[rec.reaction or 0] or "?" },
		{ L["Visits"], tostring(rec.n or 1) },
		{ L["Stock checked"], ns.AgoText(rec.checked) },
	}
end

-- a merchant's own blocks for their People page: the stock with its prices, under a "For sale"
-- heading that also says your standing, your visits and when the stock was checked
function ns.MerchantBlocks(npc)
	local rec = npc and ns.Store:Get("merchant", npc)
	if not rec then return nil end
	local b = {}
	for i, block in ipairs(Describe(npc, rec)) do
		if block[1] == "banner" and i > 1 then
			b[#b + 1] = block
			b[#b + 1] = { "small", NOTE .. (STANDING[rec.reaction or 0] or "?") .. "  ·  " .. ns.N(rec.n or 1, "visit", "visits")
				.. "  ·  " .. (L["stock checked %s"]):format(ns.AgoText(rec.checked)) .. "|r" }
		elseif block[1] ~= "stat" and block[1] ~= "banner" then
			b[#b + 1] = block
		end
	end
	return b
end

ns.UI:RegisterAlias("merchants", "townsfolk")
