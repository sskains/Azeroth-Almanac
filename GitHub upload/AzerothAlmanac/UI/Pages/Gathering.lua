-- Gathering page (DESIGN 88): what you've gathered, by profession: a card each for Herbalism,
-- Mining, Treasure (chests and lockable things), Fishing and Skinning that opens to its list, each
-- entry with where it grows. Above: the session tally, the
-- New group, "Too high for you yet". A node's page:
-- how often you've gathered it, your skill at the time, what came out (and, once Journeyman, everything it can hold; once Expert, how likely each is),
-- and where you found it (Show on map pins every spot).

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local page = { key = "gathering", title = L["Gathering"], icon = "Interface\\AddOns\\AzerothAlmanac\\Media\\Tab_Gathering", order = 6 }
local list, detail, countText, portrait, nameText, kindText, placeText, mapButton
local filter = ""
local shown -- { node = name } | { fish = map } | { skin = itemID }
local collapsed = {}

local NOTE = "|cffbfbfbf"
local CLASSIC = "|cff9d9d9d"

local function GoTo(key, method, ...)
	local args = { ... }
	return function()
		-- open the page first (a page's own Show* opens it too; "Refresh" only needs the opening)
		ns.UI:Open(key)
		local p = ns.UI:GetPage(key)
		if p and method ~= "Refresh" and p[method] then p[method](p, unpack(args)) end
	end
end

local function ZoneName(map)
	local z = map and ns.Store:Get("zone", map)
	if z and z.name then return z.name end
	local ok, info = pcall(C_Map.GetMapInfo, map)
	return ok and type(info) == "table" and info.name or nil
end

local function ItemIcon(item)
	local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	return instant and select(5, instant(item)) or nil
end

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- name and quality of an item (the name may still be on its way from the server)
local function ItemName(id)
	local ok, name, _, quality = pcall(GetInfo, id)
	if ok and name then return name, quality end
	W.waitingItems = true
	return nil, nil
end

local function QualityHex(q)
	local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
	return c and c.hex or "|cffffffff"
end

-- Skinning by what you skinned: every leather / hide / scrap, with the creatures it came from
-- (built from each creature's own skinning record: gathered = skins, gather[item] = skins that gave it)
local function SkinItems()
	local out = {}
	for npc, rec in pairs(ns.Store:Shown("creature")) do
		for item, n in pairs(rec.gather or {}) do
			local e = out[item]
			if not e then e = { item = item, n = 0, sources = {} } out[item] = e end
			e.n = e.n + n
			e.sources[#e.sources + 1] = { npc = npc, rec = rec, n = n }
		end
	end
	for _, e in pairs(out) do table.sort(e.sources, function(a, b) return a.n > b.n end) end
	return out
end

-- the zones where the creatures that gave it were killed: { [map] = { kills = spots, names = { ... } } }
local function SkinZones(e)
	local zones = {}
	for _, src in ipairs(e.sources) do
		for map, list in pairs(src.rec.kz or {}) do
			local z = zones[map]
			if not z then z = { spots = 0, names = {} } zones[map] = z end
			z.spots = z.spots + #list
			z.names[#z.names + 1] = src.rec.name or "?"
		end
	end
	return zones
end

local function SkinBestZone(e)
	local best, n = nil, 0
	for map, z in pairs(SkinZones(e)) do if z.spots > n and ns.Store:Get("zone", map) then best, n = map, z.spots end end
	return best
end

-- the record's face: what comes out of it most often
-- the item a node is pictured by: what comes out most often. Chests and other loot containers
-- that give a mix of things (milk, potions, gloves ...) keep the chest icon instead; an object with
-- one kind of thing in it (an egg, a crate of one item) still shows that item.
-- (0.69.1: the module's, so the Journal shows the same item)
local function TopItem(rec) return ns.Gathering:TopItem(rec) end

local function Record(sel)
	if not sel then return nil end
	if sel.node then return ns.Store:Get("node", sel.node), "node" end
	if sel.fish then return ns.Store:Get("fishing", sel.fish), "fish" end
end

---------------------------------------------------------------------------
-- Detail
---------------------------------------------------------------------------

local function Who(rec)
	local others = {}
	for key in pairs(rec.c or {}) do if key ~= rec.b then others[#others + 1] = ns.CharName(key) end end
	table.sort(others)
	return others
end

-- the most common zone, for the map buttons
local function BestZone(rec)
	local best, n = nil, 0
	for map, c in pairs(rec.z or {}) do if c > n then best, n = map, c end end
	if not best then for map, c in pairs(rec.sz or {}) do if c > n then best, n = map, c end end end
	return best
end

local function Describe(rec, isFish)
	local G = ns.Gathering
	local b = {}
	local kind = isFish and "fish" or (rec.kind or "chest")
	local k = G.KIND[kind]
	local tier, need = G:Tier(rec)
	b[#b + 1] = { "banner", L["General"] }
	b[#b + 1] = { "stat", L["Kind"], k.label }
	b[#b + 1] = { "stat", isFish and L["Catches"] or L["Gathered"], (G:Count(rec)) > 0 and ns.Times(G:Count(rec)) or L["not yet"] }
	if (rec.sighted or 0) > 0 then b[#b + 1] = { "stat", L["Sighted"], ns.Times(rec.sighted) } end
	-- (0.69.0, #36 / #37) the skill it needs, coloured for you (a lock: for your rogue)
	if not isFish then
		local need, skill, lo, rogue = G:NeedText(rec)
		if need then
			if rogue then
				local r = G:CharSkill(1, rogue)
				need = need .. "  |cff999999" .. (r and r >= lo and (L["%s can open this"]):format(ns.CharName(rogue, true)) or (L["too hard for %s yet"]):format(ns.CharName(rogue, true))) .. "|r"
			end
			b[#b + 1] = { "stat", skill == 1 and L["Pick the lock"] or L["Needs"], need }
		end
		-- picked by your rogues, and failed picks (too hard at the time)
		if (G:PickCount(rec)) > 0 then
			local s = rec.pickSkill and (rec.pickSkill[1] == rec.pickSkill[2] and tostring(rec.pickSkill[1]) or (rec.pickSkill[1] .. " - " .. rec.pickSkill[2]))
			local pt = G:PickTier(rec)
			b[#b + 1] = { "stat", L["Lock picked"], G:TierMarkup(pt, 14, "lock") .. " " .. ns.Times(G:PickCount(rec)) .. (s and ("  |cff999999" .. (L["skill %s"]):format(s) .. "|r") or "") }
		end
		for key, rank in pairs(rec.hard or {}) do
			b[#b + 1] = { "stat", L["Too hard"], (L["for %s at %d"]):format(ns.CharName(key, true), rank) }
		end
	end
	if rec.skill then
		local s = rec.skill[1] == rec.skill[2] and tostring(rec.skill[1]) or (rec.skill[1] .. " - " .. rec.skill[2])
		b[#b + 1] = { "stat", L["Your skill at the time"], s }
	end
	b[#b + 1] = { "stat", (rec.gathered or 0) > 0 and L["First found"] or L["First sighted"], ns.CharName(rec.b) .. ", " .. ns.DateText(rec.f) }
	local others = Who(rec)
	if #others > 0 then b[#b + 1] = { "stat", L["Also gathered by"], table.concat(others, ", ") } end

	-- the ranks (the character sheet's blue skill bar, like a creature's): Journeyman reveals
	-- everything it can hold, Expert how likely each is; past Master the count keeps rolling
	local n = G:Count(rec)
	local nextAt = G.AT[tier + 1]
	if nextAt then
		b[#b + 1] = { "skillbar", nil, n, nextAt, (L["%d / %d"]):format(n, nextAt) .. "  ·  " .. (L["%d to %s"]):format(nextAt - n, G.TIERS[tier + 1]) }
	else
		b[#b + 1] = { "skillbar", nil, 1, 1, ns.Times(n) .. "  ·  " .. G.TIERS[#G.TIERS] }
	end

	-- what came out
	local seen, slots = {}, {}
	local got = {}
	for item, n in pairs(rec.items or {}) do got[#got + 1] = { item = item, n = n } end
	table.sort(got, function(x, y) return x.n > y.n end)
	local classic = {}
	if not isFish and tier >= 3 then
		for _, e in ipairs(G:Contents(rec)) do classic[e.item] = e.chance end
	end
	for _, e in ipairs(got) do
		seen[e.item] = true
		local each = (rec.qty and rec.qty[e.item] or e.n) / e.n
		local note = ("%d / %d"):format(e.n, rec.gathered or e.n)
		if each > 1.05 then note = note .. NOTE .. ("  x%.1f"):format(each) .. "|r" end
		if tier >= 4 and classic[e.item] then note = note .. "  " .. CLASSIC .. (L["Classic %.0f%%"]):format(classic[e.item]) .. "|r" end
		slots[#slots + 1] = { item = e.item, note = note, onClick = GoTo("items", "ShowItem", e.item) }
	end
	b[#b + 1] = { "banner", (L["What came out (%d)"]):format(#slots) }
	if #slots > 0 then b[#b + 1] = { "slots", slots } end
	if not isFish then
		if tier >= 3 then
			local more = {}
			for _, e in ipairs(G:Contents(rec)) do
				if not seen[e.item] then
					more[#more + 1] = { item = e.item, grey = true,
						note = tier >= 4 and (CLASSIC .. (L["Classic %.2f%%"]):format(e.chance) .. "|r") or (CLASSIC .. L["not found yet"] .. "|r") }
				end
			end
			if #more > 0 then
				b[#b + 1] = { "banner", (L["It can also hold (%d)"]):format(#more) }
				b[#b + 1] = { "slots", more }
			end
		else
			b[#b + 1] = { "small", (L["Gather it %d more times to learn everything it can hold."]):format(need or 0) }
		end
	end

	if isFish and rec.pools and next(rec.pools) then
		local pools = {}
		for name, n in pairs(rec.pools) do
			pools[#pools + 1] = { name = name, icon = W.FindIcon({ "INV_Misc_Fish_02", "Trade_Fishing" }), note = ns.Times(n) }
		end
		table.sort(pools, function(x, y) return x.name < y.name end)
		b[#b + 1] = { "banner", (L["Pools fished (%d)"]):format(#pools) }
		b[#b + 1] = { "slots", pools }
	end

	-- where: each zone, a click opens it in Places with every spot pinned
	if not isFish then
		local zones, maps = {}, {}
		for map in pairs(rec.z or {}) do maps[map] = true end
		for map in pairs(rec.sz or {}) do maps[map] = true end
		for map in pairs(maps) do
			local g, s = rec.z and rec.z[map] or 0, rec.sz and rec.sz[map] or 0
			local note = g > 0 and (L["gathered %s"]):format(ns.Times(g)) or ""
			if s > 0 then note = note .. (g > 0 and NOTE .. "  ·  " or NOTE) .. (L["sighted %s"]):format(ns.Times(s)) .. "|r" end
			zones[#zones + 1] = { name = ZoneName(map) or (L["map %d"]):format(map), icon = W.KindIcon("zone"), note = note,
				tip = L["Click to see every spot on the map."], onClick = function() page:ShowOnMap(map) end }
		end
		table.sort(zones, function(x, y) return x.name < y.name end)
		if #zones > 0 then
			b[#b + 1] = { "banner", (L["Where (%d)"]):format(#zones) }
			b[#b + 1] = { "slots", zones }
		end
	end
	return b
end

-- a skinned item: how often you got it, the creatures it came from (each opens in the Bestiary,
-- with its Classic chance once that creature is Mastered), and where they were killed
local function DescribeSkinItem(id, e)
	local B = ns.Bestiary
	local b = {}
	b[#b + 1] = { "banner", L["General"] }
	b[#b + 1] = { "stat", L["Kind"], L["Skinning"] }
	b[#b + 1] = { "stat", L["Skinned"], ns.Times(e.n) }
	b[#b + 1] = { "stat", L["From"], ns.N(#e.sources, "creature", "creatures") }
	local item = ns.Store:Get("item", id)
	if item and item.f then b[#b + 1] = { "stat", L["First found"], ns.CharName(item.b) .. ", " .. ns.DateText(item.f) } end

	local from = {}
	for _, src in ipairs(e.sources) do
		local rec = src.rec
		local tier = B and B:Tier(rec) or 1
		local note = (L["%d of %d skins"]):format(src.n, rec.gathered or src.n)
		if tier >= 4 and ns.CreatureDB then
			local c = ns.CreatureDB:Get(src.npc)
			for _, sk in ipairs(c and c.skin or {}) do
				if sk.item == id then note = note .. "  " .. CLASSIC .. (L["Classic %.0f%%"]):format(sk.chance) .. "|r" break end
			end
		end
		from[#from + 1] = { name = (B and (B:TierMarkup(tier, 12) .. " ") or "") .. (rec.name or "?"),
			icon = W.FindIcon(W.TYPE_ICON[rec.type or ""] or W.KIND.creature.icon), note = note,
			tip = L["Click to open it in Creatures."], onClick = GoTo("bestiary", "ShowCreature", src.npc) }
	end
	b[#b + 1] = { "banner", (L["Came from (%d)"]):format(#from) }
	b[#b + 1] = { "slots", from }

	local zones = {}
	for map, z in pairs(SkinZones(e)) do
		local names = {}
		for i, n in ipairs(z.names) do if i <= 3 then names[#names + 1] = n end end
		zones[#zones + 1] = { name = ZoneName(map) or (L["map %d"]):format(map), icon = W.KindIcon("zone"),
			note = NOTE .. table.concat(names, ", ") .. (#z.names > 3 and " ..." or "") .. "|r",
			tip = L["Click to see where you killed them on the map."], onClick = function() page:ShowOnMap(map) end }
	end
	table.sort(zones, function(x, y) return x.name < y.name end)
	if #zones > 0 then
		b[#b + 1] = { "banner", (L["Where (%d)"]):format(#zones) }
		b[#b + 1] = { "slots", zones }
	end

	b[#b + 1] = { "banner", L["The item"] }
	b[#b + 1] = { "slots", { { item = id, note = L["Open in Items"], onClick = GoTo("items", "ShowItem", id) } } }
	return b
end

-- (2026-10-09, Shannon) Fishing by fish: every kind of fish (and anything else) you've caught, over all
-- your fishing waters: { [item] = { item, n = catches that gave it, qty, maps = { [map] = n } } }
local function FishItems()
	local out = {}
	for map, rec in pairs(ns.Store:Shown("fishing")) do
		for item, n in pairs(rec.items or {}) do
			local e = out[item]
			if not e then e = { item = item, n = 0, qty = 0, maps = {} } out[item] = e end
			e.n = e.n + n
			e.qty = e.qty + (rec.qty and rec.qty[item] or n)
			e.maps[map] = (e.maps[map] or 0) + n
		end
	end
	return out
end

-- a fish: how often you caught it, and the waters it came from (each opens that water's page)
local function DescribeFishItem(id, e)
	local b = {}
	b[#b + 1] = { "banner", L["General"] }
	b[#b + 1] = { "stat", L["Kind"], L["Fishing"] }
	b[#b + 1] = { "stat", L["Caught"], ns.Times(e.n) .. (e.qty > e.n and ("  |cff999999" .. (L["%d in all"]):format(e.qty) .. "|r") or "") }
	local item = ns.Store:Get("item", id)
	if item and item.f then b[#b + 1] = { "stat", L["First found"], ns.CharName(item.b) .. ", " .. ns.DateText(item.f) } end
	local waters = {}
	for map, n in pairs(e.maps) do
		waters[#waters + 1] = { name = ZoneName(map) or (L["map %d"]):format(map), icon = W.FindIcon({ "Trade_Fishing", "INV_Misc_Fish_02" }),
			note = ns.Times(n), n = n, tip = L["Click to see this water's page."], onClick = function() page:ShowFishing(map) end }
	end
	table.sort(waters, function(x, y) return x.n > y.n end)
	if #waters > 0 then
		b[#b + 1] = { "banner", (L["Caught in (%d)"]):format(#waters) }
		b[#b + 1] = { "slots", waters }
	end
	b[#b + 1] = { "banner", L["The item"] }
	b[#b + 1] = { "slots", { { item = id, note = L["Open in Items"], onClick = GoTo("items", "ShowItem", id) } } }
	return b
end

local function Show(sel)
	if sel and sel.fishItem then
		local e = FishItems()[sel.fishItem]
		if e then
			shown = sel
			local name, q = ItemName(sel.fishItem)
			portrait:Show()
			portrait.art:SetTexture(ItemIcon(sel.fishItem) or W.FindIcon({ "INV_Misc_Fish_02" }))
			portrait.art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
			portrait:SetRing(c and c.r or 0.62, c and c.g or 0.5, c and c.b or 0.24)
			nameText:SetText(name or (L["item %d"]):format(sel.fishItem))
			kindText:SetText(L["Fishing"])
			placeText:SetText("")
			mapButton:Hide()
			detail:SetBlocks(DescribeFishItem(sel.fishItem, e))
			return
		end
		sel = nil
	end
	if sel and sel.skin then
		local e = SkinItems()[sel.skin]
		if e then
			shown = sel
			local name, q = ItemName(sel.skin)
			portrait:Show()
			portrait.art:SetTexture(ItemIcon(sel.skin) or W.FindIcon({ "INV_Misc_Pelt_Wolf_01" }))
			portrait.art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
			portrait:SetRing(c and c.r or 0.62, c and c.g or 0.5, c and c.b or 0.24)
			nameText:SetText(name or (L["item %d"]):format(sel.skin))
			kindText:SetText(L["Skinning"])
			placeText:SetText("")
			mapButton:SetShown(SkinBestZone(e) ~= nil)
			detail:SetBlocks(DescribeSkinItem(sel.skin, e))
			return
		end
		sel = nil
	end
	local rec, what = Record(sel)
	shown = rec and sel or nil
	if not rec then
		portrait:Hide()
		nameText:SetText("")
		kindText:SetText("")
		placeText:SetText("")
		mapButton:Hide()
		detail:SetBlocks(nil, L["Select something you've gathered."])
		return
	end
	local G = ns.Gathering
	local isFish = what == "fish"
	local k = G.KIND[isFish and "fish" or (rec.kind or "chest")]
	portrait:Show()
	local top = TopItem(rec)
	local icon = top and ItemIcon(top)
	if icon then portrait.art:SetTexture(icon) else W.SetIcon(portrait.art, k.icon) end
	portrait.art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local tier = G:Tier(rec)
	local c = ns.Bestiary and ns.Bestiary.TIER_COLORS[tier] or { 0.62, 0.5, 0.24 }
	portrait:SetRing(c[1], c[2], c[3])
	nameText:SetText(isFish and (rec.zone or rec.name or "?") or (rec.name or "?"))
	kindText:SetText(G:TierMarkup(tier, 14, isFish and "fish" or rec.kind) .. " " .. G:Title(tier, isFish and "fish" or rec.kind) .. "  |cff999999" .. (isFish and L["Fishing"] or k.label) .. "|r")
	local zone = isFish and sel.fish or BestZone(rec)
	placeText:SetText(NOTE .. (isFish and "" or (ZoneName(zone) or "")) .. "|r")
	mapButton:SetShown(zone ~= nil and ns.Store:Get("zone", zone) ~= nil)
	detail:SetBlocks(Describe(rec, isFish))
end

---------------------------------------------------------------------------
-- List (DESIGN 88, revised with Shannon 2026-10-09): a 4 : 1 card per profession (Herbalism, Mining,
-- Treasure, Fishing, Skinning) that opens to what you've gathered for it, A to Z, each with where it
-- grows. Above the cards: the session tally, the New group, "Too high for you yet". (Smelting lines
-- under ores were tried and taken out the same evening: Shannon's call.)
---------------------------------------------------------------------------

local PROF_H, TALLY_H = 76, 30
local PROFS = { "herb", "ore", "treasure", "fish", "skin" }
local PROF_LABEL = { herb = L["Herbalism"], ore = L["Mining"], treasure = L["Treasure"], fish = L["Fishing"], skin = L["Skinning"] }
local PROF_SKILL = { herb = L["Herbalism"], ore = L["Mining"], fish = L["Fishing"], skin = L["Skinning"] }
local PROF_ICON = {
	herb = { 133939, "Trade_Herbalism", "INV_Misc_Herb_07" }, ore = { "Trade_Mining", "INV_Ore_Copper_01" },
	treasure = { 1450989, 132594, "INV_Box_02" }, fish = { "Trade_Fishing", "INV_Misc_Fish_02" },
	skin = { "INV_Misc_Pelt_Wolf_01", "Trade_Skinning" },
}
local PROF_TINT = {
	herb = { 0.35, 0.7, 0.3 }, ore = { 0.8, 0.52, 0.3 }, treasure = { 0.9, 0.72, 0.3 },
	fish = { 0.3, 0.58, 0.85 }, skin = { 0.65, 0.42, 0.25 }, toohigh = { 0.85, 0.22, 0.15 },
}
-- each card's painted picture (Media\Gather_<Name>.tga, 512 x 128; ART_ASSETS.md "Gathering profession
-- cards"); a card without one keeps the plain tinted card with its icon. Add a line when a picture arrives.
local PROF_ART = { herb = "Gather_Herbalism", ore = "Gather_Mining" }
local function ProfIcon(prof) return W.FindIcon(PROF_ICON[prof]) end
local function IconMarkup(prof, size)
	local icon = ProfIcon(prof)
	return icon and ("|T" .. icon .. ":" .. (size or 14) .. ":" .. (size or 14) .. ":0:0:64:64:5:59:5:59|t") or ""
end
local opened = {} -- profession cards you've opened (they start folded)
local tallySeen = {} -- the tally's counts last drawn (a number that went up pulses once)

local function ZoneNameOf(map) return map and (ZoneName(map) or (L["map %d"]):format(map)) or nil end

-- where it grows: the zone gathered (else sighted) most, "+2" when there are more
local function WhereText(maps)
	local best, n, count = nil, -1, 0
	for map, c in pairs(maps or {}) do
		count = count + 1
		if c > n then best, n = map, c end
	end
	if not best then return nil end
	return ZoneNameOf(best) .. (count > 1 and (" +" .. (count - 1)) or "")
end
local function NodeWhere(rec)
	local maps = {}
	for map, c in pairs(rec.z or {}) do maps[map] = (maps[map] or 0) + c * 10 end
	for map, c in pairs(rec.sz or {}) do maps[map] = (maps[map] or 0) + c end
	return WhereText(maps)
end

-- what the playing character can't gather yet: needs more than their skill (only skills they have)
local function TooHigh(rec)
	local G = ns.Gathering
	local skill, lo = G:Needs(rec)
	if not skill then return nil end
	local me = ns.CharKey()
	local rank
	if skill == 1 then
		local rogue
		rogue, rank = G:LockRogue()
		if rogue ~= me then return nil end
	else
		rank = G:CharSkill(skill)
	end
	if rank and rank < lo then return skill, lo end
end

-- the playing character's skill for a profession card ("Mining 87"), or nil
local function MySkill(prof)
	local G = ns.Gathering
	if prof == "treasure" then
		local rogue, rank = G:LockRogue()
		return rogue == ns.CharKey() and rank and (L["Lockpicking"] .. " " .. rank) or nil
	end
	local c = ns.db and ns.db.chars[ns.CharKey()]
	local s = c and c.skills and c.skills[PROF_SKILL[prof] or ""]
	return s and s.rank and (PROF_SKILL[prof] .. " " .. s.rank) or nil
end

local function Collect()
	local G = ns.Gathering
	local rows, n = {}, 0
	local locks = G.LockRogue and G:LockRogue() ~= nil
	local function Hit(...)
		if filter == "" then return true end
		for i = 1, select("#", ...) do
			local v = select(i, ...)
			if type(v) == "string" and v:lower():find(filter, 1, true) then return true end
		end
	end
	local groups = { herb = {}, ore = {}, treasure = {}, fish = {}, skin = {} }
	local news = { herb = 0, ore = 0, treasure = 0, fish = 0, skin = 0 }
	local all, high = {}, {}
	local function IsNew(rec) return ns.New and rec and ns.New:IsNew("gathering", rec) end
	for name, rec in pairs(ns.Store:Shown("node")) do
		local quest = rec.kind ~= "herb" and rec.kind ~= "ore" and G.OnlyQuestItems(rec.items)
		local prof = G:Prof(rec)
		if not quest and Hit(name) then
			n = n + 1
			local e = { node = name, rec = rec, label = name, prof = prof, where = NodeWhere(rec) }
			table.insert(groups[prof], e)
			if IsNew(rec) then news[prof] = news[prof] + 1 end
			all[#all + 1] = { node = name, rec = rec, label = name, prof = prof }
			local skill, lo = TooHigh(rec)
			if skill then high[#high + 1] = { node = name, rec = rec, label = name, prof = prof, lo = lo, where = e.where, inHigh = true } end
		end
	end
	-- fishing: each kind of fish you've caught (no waters by zone in the list; a fish's page has them)
	for map, rec in pairs(ns.Store:Shown("fishing")) do
		if IsNew(rec) then news.fish = news.fish + 1 end
		all[#all + 1] = { fish = map, rec = rec, label = rec.zone or ZoneName(map) or "?", prof = "fish" }
	end
	for item, e in pairs(FishItems()) do
		local name, q = ItemName(item)
		local label = name or (L["item %d"]):format(item)
		if Hit(label) then
			n = n + 1
			table.insert(groups.fish, { fishItem = item, data = e, label = label, q = q, prof = "fish" })
		end
	end
	for item, e in pairs(SkinItems()) do
		local name, q = ItemName(item)
		local label = name or (L["item %d"]):format(item)
		local hit = Hit(label)
		if not hit then for _, src in ipairs(e.sources) do if Hit(src.rec.name) then hit = true break end end end
		if hit then
			n = n + 1
			local maps = {}
			for _, src in ipairs(e.sources) do for map, list in pairs(src.rec.kz or {}) do maps[map] = (maps[map] or 0) + #list end end
			table.insert(groups.skin, { skin = item, data = e, label = label, q = q, prof = "skin", where = WhereText(maps) })
		end
	end
	-- lockboxes you've come across (items, with the level each needs): in Treasure, for a rogue
	if locks then
		for item, rec in pairs(ns.Store:Shown("item")) do
			if G:ItemLock(item) then
				local name, q = ItemName(item)
				local label = name or rec.name or (L["item %d"]):format(item)
				if Hit(label) then n = n + 1 table.insert(groups.treasure, { lockbox = item, rec = rec, label = label, q = q, prof = "treasure" }) end
			end
		end
	end

	-- the session tally, when anything has been gathered since you logged in
	if (G.session and G.session.total or 0) > 0 then rows[#rows + 1] = { kind = "tally", header = false } end
	-- (#38) nodes and fishing waters found since you last looked
	if ns.New then
		local new = ns.New:Split("gathering", all, function(e) return e.rec end, function(e) return e.node or ("fish:" .. tostring(e.fish)) end)
		if #new > 0 then
			rows[#rows + 1] = ns.New:Header(#new)
			if not collapsed.new then for _, e in ipairs(new) do rows[#rows + 1] = e end end
		end
	end
	-- too high for you yet (folded until opened)
	if #high > 0 then
		table.sort(high, function(a, b) if a.lo ~= b.lo then return a.lo < b.lo end return a.label < b.label end)
		rows[#rows + 1] = { kind = "prof", prof = "toohigh", key = "toohigh", header = false, count = #high }
		if opened.toohigh or filter ~= "" then for _, e in ipairs(high) do rows[#rows + 1] = e end end
	end
	-- a card per profession you've gathered for, each opening to its list
	for _, prof in ipairs(PROFS) do
		local g = groups[prof]
		if #g > 0 then
			table.sort(g, function(a, b) return a.label < b.label end)
			rows[#rows + 1] = { kind = "prof", prof = prof, key = prof, header = false, count = #g, new = news[prof] }
			if opened[prof] or filter ~= "" then
				for _, e in ipairs(g) do
					rows[#rows + 1] = e
				end
			end
		end
	end
	return rows, n
end

local function Fold(key)
	return function()
		opened[key] = (not opened[key]) or nil
		page:Refresh()
	end
end

-- the session tally strip: "This session:" and each profession's icon and count; a count that went up
-- since it was last drawn pulses gold once
local function DrawTally(row)
	local G = ns.Gathering
	local t = row.tally
	if not t then
		t = CreateFrame("Frame", nil, row)
		t:SetPoint("TOPLEFT", 3, -3)
		t:SetPoint("BOTTOMRIGHT", -3, 3)
		t:SetFrameLevel(row:GetFrameLevel() + 3)
		t.bg = t:CreateTexture(nil, "BACKGROUND")
		t.bg:SetAllPoints()
		W.Fade(t.bg, "HORIZONTAL", 0.32, 0.22, 0.06, 0.95, 0.55)
		t.edge = t:CreateTexture(nil, "BORDER")
		t.edge:SetPoint("BOTTOMLEFT")
		t.edge:SetPoint("BOTTOMRIGHT")
		t.edge:SetHeight(1)
		t.edge:SetColorTexture(0.95, 0.75, 0.25, 0.9)
		t.top = t:CreateTexture(nil, "BORDER")
		t.top:SetPoint("TOPLEFT")
		t.top:SetPoint("TOPRIGHT")
		t.top:SetHeight(1)
		t.top:SetColorTexture(0.95, 0.75, 0.25, 0.9)
		t.label = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		t.label:SetPoint("LEFT", 8, 0)
		t.label:SetText(L["This session:"])
		t.value = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		t.value:SetPoint("RIGHT", -8, 0)
		t.segs = {}
		for i, prof in ipairs(PROFS) do
			local s = {}
			s.glow = t:CreateTexture(nil, "ARTWORK")
			s.glow:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
			s.glow:SetBlendMode("ADD")
			s.glow:SetVertexColor(1, 0.8, 0.3)
			s.glow:SetAlpha(0)
			s.text = t:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			s.glow:SetPoint("TOPLEFT", s.text, "TOPLEFT", -10, 8)
			s.glow:SetPoint("BOTTOMRIGHT", s.text, "BOTTOMRIGHT", 10, -8)
			s.anim = s.glow:CreateAnimationGroup()
			local a1 = s.anim:CreateAnimation("Alpha")
			a1:SetFromAlpha(0) a1:SetToAlpha(1) a1:SetDuration(0.25) a1:SetOrder(1)
			local a2 = s.anim:CreateAnimation("Alpha")
			a2:SetFromAlpha(1) a2:SetToAlpha(0) a2:SetDuration(0.9) a2:SetOrder(2)
			t.segs[prof] = s
		end
		row.tally = t
	end
	local counts = G.session and G.session.counts or {}
	local prev = t.label
	for _, prof in ipairs(PROFS) do
		local s = t.segs[prof]
		local c = counts[prof] or 0
		s.text:ClearAllPoints()
		if c > 0 then
			s.text:SetPoint("LEFT", prev, "RIGHT", 10, 0)
			s.text:SetText(IconMarkup(prof, 16) .. " " .. c)
			s.text:Show()
			prev = s.text
			if tallySeen[prof] and c > tallySeen[prof] and s.anim.Play then s.anim:Stop() s.anim:Play() end
		else
			s.text:Hide()
		end
		tallySeen[prof] = c
	end
	-- a rough auction value, only when prices are known
	local AP, worth = ns.AuctionPrices, 0
	if AP and AP.PriceForItemID then
		for item, q in pairs(G.session and G.session.items or {}) do
			local ok, p = pcall(AP.PriceForItemID, AP, item)
			if ok and type(p) == "number" then worth = worth + p * q end
		end
	end
	t.value:SetText(worth > 0 and ("~ " .. ns.MoneyText(math.floor(worth))) or "")
	t:Show()
end


local function FillRow(row, r)
	if row.banner then row.banner:Hide() row.banner:SetSelected(false) end
	if row.tally then row.tally:Hide() end
	row:SetHeader(r.newHeader ~= nil, r.newHeader and collapsed.new)
	row.icon:ClearAllPoints()
	if ns.New then ns.New:MarkRow(row, r.isNew, "gathering", r.newKey) end
	if r.kind == "tally" or r.kind == "prof" then
		row.icon:SetPoint("LEFT", 20, 0)
		row.icon:SetTexture(nil)
		row.text:SetText("")
		row.right:SetText("")
		if r.kind == "tally" then return DrawTally(row) end
		local label = r.prof == "toohigh" and L["Too high for you yet"] or PROF_LABEL[r.prof]
		local isOpen = opened[r.key] or filter ~= ""
		if not W.FillZoneBanner then
			-- (without the Places page's banners: a plain heading)
			row.text:SetFontObject(GameFontNormalLarge)
			row.text:SetText(label)
			return
		end
		local count
		if r.prof == "toohigh" then
			count = (L["%s you've seen but can't gather yet"]):format(ns.N(r.count, "node", "nodes"))
		else
			local mine = MySkill(r.prof)
			count = tostring(r.count) .. ((r.new or 0) > 0 and ("  |cff1eff00+" .. r.new .. "|r") or "") .. (mine and ("   |cffffd100" .. mine .. "|r") or "")
		end
		local tint = PROF_TINT[r.prof]
		W.FillZoneBanner(row, { name = label, art = PROF_ART[r.prof], icon = r.prof == "toohigh" and W.FindIcon({ "Ability_Warrior_Revenge", "INV_Misc_QuestionMark" }) or ProfIcon(r.prof),
			tint = tint, top = 4, count = "|cffcccccc" .. count .. "|r",
			pill = { sign = isOpen and "-" or "+", label = isOpen and L["Hide"] or L["Show"], action = Fold(r.key) } })
		row.banner.icon:SetAlpha(0.8)
		for _, t in ipairs(row.banner.edges) do t:SetColorTexture(tint[1] * 0.75, tint[2] * 0.75, tint[3] * 0.75, 1) end
		return
	end
	if r.newHeader then
		row.icon:SetPoint("LEFT", 4, 0)
		row.icon:SetTexture(nil)
		row.text:SetFontObject(W.Font("GameFontNormalLarge", "GameFontNormal"))
		row.text:SetText(r.header)
		row.right:SetText("")
		return
	end
	local G = ns.Gathering
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.icon:SetPoint("LEFT", 22, 0)
	row.text:SetFontObject(GameFontHighlight)
	local where = r.where and ("  |cff999999" .. r.where .. "|r") or ""
	if r.lockbox then
		row.icon:SetTexture(ItemIcon(r.lockbox) or W.FindIcon(G.KIND.lock.icon))
		row.text:SetText(QualityHex(r.q) .. r.label .. "|r")
		local lvl, _, rank = G:ItemLock(r.lockbox), G:LockRogue()
		row.right:SetText(G:NeedColor(lvl, rank) .. L["Lockpicking"] .. " " .. lvl .. "|r")
	elseif r.fishItem then
		row.icon:SetTexture(ItemIcon(r.fishItem) or ProfIcon("fish"))
		row.text:SetText(QualityHex(r.q) .. r.label .. "|r")
		row.right:SetText("|cff999999" .. ns.Times(r.data.n) .. "|r")
	elseif r.skin then
		row.icon:SetTexture(ItemIcon(r.skin) or ProfIcon("skin"))
		row.text:SetText(QualityHex(r.q) .. r.label .. "|r" .. where)
		row.right:SetText("|cff999999" .. ns.Times(r.data.n) .. "|r")
	else
		local top = TopItem(r.rec)
		local icon = top and ItemIcon(top)
		if icon then row.icon:SetTexture(icon) else W.SetIcon(row.icon, G.KIND[r.fish and "fish" or (r.rec.kind or "chest")].icon) end
		row.text:SetText(r.label .. where)
		local tier = G:Tier(r.rec)
		local count = G:Count(r.rec) > 0 and ns.Times(G:Count(r.rec)) or L["sighted"]
		local need = not r.fish and G:NeedText(r.rec)
		if r.inHigh then
			row.right:SetText(need or "")
		else
			row.right:SetText((need and (need .. "   ") or "") .. (tier > 1 and (G:TierMarkup(tier, 14, r.fish and "fish" or r.rec.kind) .. " ") or "") .. "|cff999999" .. count .. "|r")
		end
	end
end

function page:Build(parent, header)
	local search = W.Search(header, 200, function(text)
		filter = text
		page:Refresh()
	end)
	search:SetPoint("LEFT", header, "LEFT", 16, -2)
	countText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countText:SetPoint("RIGHT", header, "RIGHT", -12, -2)

	local left = W.Inset(parent)
	left:SetPoint("TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", 0, 0)
	left:SetWidth(330)
	list = W.List(left, {
		collapse = { state = collapsed, key = function(r) return r.newHeader and "new" or nil end, refresh = function() page:Refresh() end },
		rowHeight = 24,
		heightOf = function(r)
			if r.kind == "prof" then return PROF_H elseif r.kind == "tally" then return TALLY_H end
		end,
		style = "log",   -- the Map & Quest Log look, as on Places
		emptyText = L["Nothing gathered yet. Herbs, veins, treasure, fishing and skinning are recorded as you go."],
		-- (#62) the profession you're scrolling through stays pinned at the top
		sticky = function(r)
			if r.kind == "prof" then
				local c = PROF_TINT[r.prof]
				return { r.prof == "toohigh" and L["Too high for you yet"] or PROF_LABEL[r.prof], c[1], c[2], c[3], not opened[r.key] }
			end
		end,
		update = FillRow,
		restore = function(r)
			if r.node then Show({ node = r.node }) elseif r.fish then Show({ fish = r.fish }) elseif r.skin then Show({ skin = r.skin })
			elseif r.fishItem then Show({ fishItem = r.fishItem }) end
		end,
		onClick = function(r)
			if r.kind == "tally" then return end
			if r.kind == "prof" then return Fold(r.key)() end
			if r.newHeader then
				collapsed.new = not collapsed.new
				page:Refresh()
			elseif r.skin then
				Show({ skin = r.skin })
			elseif r.fishItem then
				Show({ fishItem = r.fishItem })
			elseif r.lockbox then
				local items = ns.UI:GetPage("items")
				if items and items.ShowItem then items:ShowItem(r.lockbox) end
			else
				if ns.New and ns.New:Clicked("gathering", r) then list:Refresh() end
				Show(r.node and { node = r.node } or { fish = r.fish })
			end
		end,
	})
	list:SetAllPoints(left)

	detail = W.Detail(parent, 64)
	detail:SetTheme({ "Herbalism", "Mining" })
	detail:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
	detail:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
	portrait = W.Portrait(detail.top, 60)
	portrait:SetPoint("TOPLEFT", 0, 2)
	nameText = detail.top:CreateFontString(nil, "OVERLAY")
	W.HeroFont(nameText, 26)
	nameText:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 10, -2)
	nameText:SetPoint("RIGHT", detail.top, "RIGHT", -150, 0)
	nameText:SetJustifyH("LEFT")
	nameText:SetWordWrap(false)
	kindText = detail.top:CreateFontString(nil, "OVERLAY")
	kindText:SetFontObject(GameFontHighlight)
	kindText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -4)
	kindText:SetJustifyH("LEFT")
	placeText = detail.top:CreateFontString(nil, "OVERLAY")
	placeText:SetFontObject(GameFontHighlightSmall)
	placeText:SetPoint("TOPLEFT", kindText, "BOTTOMLEFT", 0, -3)
	placeText:SetJustifyH("LEFT")
	mapButton = W.Button(detail.top, L["Show on map"], 130, function()
		if shown and shown.skin then
			local e = SkinItems()[shown.skin]
			if e then page:ShowOnMap(SkinBestZone(e)) end
			return
		end
		local rec = Record(shown)
		page:ShowOnMap(shown and shown.fish or BestZone(rec or {}))
	end)
	mapButton:SetPoint("TOPRIGHT", detail.top, "TOPRIGHT", -16, 0)
	mapButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(L["Show on map"], 1, 0.82, 0)
		GameTooltip:AddLine(L["Opens the zone in Places with every spot you gathered it pinned."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	mapButton:SetScript("OnLeave", GameTooltip_Hide)
	Show(nil)
end

-- the zone in Places with every spot pinned
function page:ShowOnMap(map)
	if shown and shown.skin then
		-- where the creatures that gave it were killed, each pin named for its creature
		local e = SkinItems()[shown.skin]
		local places = ns.UI:GetPage("places")
		if not (e and map and places) then return end
		local spots = {}
		for _, src in ipairs(e.sources) do
			for _, sp in ipairs(ns.Bestiary and ns.Bestiary:Spots(src.rec, "kz", map) or {}) do
				sp.sub = src.rec.name
				spots[#spots + 1] = sp
			end
		end
		local id = shown.skin
		local name = ItemName(id)
		places:ShowZone(map, nil, nil, { name = name or (L["item %d"]):format(id), sub = L["Skinning"], icon = ItemIcon(id),
			spots = spots, x = spots[1] and spots[1].x, y = spots[1] and spots[1].y, onClick = function() page:ShowSkin(id) end })
		return
	end
	local rec, what = Record(shown)
	local places = ns.UI:GetPage("places")
	if not (rec and map and places) then return end
	local spots = ns.Bestiary and ns.Bestiary:Spots(rec, "spots", map) or {}
	-- where it was only sighted: smaller pins, "Sighted here"
	for _, s in ipairs(ns.Bestiary and ns.Bestiary:Spots(rec, "seen", map) or {}) do
		local near = false
		for _, g in ipairs(spots) do if (g.x - s.x) ^ 2 + (g.y - s.y) ^ 2 < 1 then near = true break end end
		if not near then s.sub, s.size = L["Sighted here"], 14 spots[#spots + 1] = s end
	end
	local top = TopItem(rec)
	local back = shown
	local pin = { name = what == "fish" and L["Fishing"] or rec.name, sub = what == "fish" and (rec.zone or "") or ns.Gathering.KIND[rec.kind or "chest"].label,
		icon = top and ItemIcon(top) or W.FindIcon(ns.Gathering.KIND[what == "fish" and "fish" or (rec.kind or "chest")].icon),
		spots = spots, x = spots[1] and spots[1].x, y = spots[1] and spots[1].y,
		onClick = function() if back.node then page:ShowNode(back.node) else page:ShowFishing(back.fish) end end }
	places:ShowZone(map, nil, nil, pin)
end

function page:Refresh()
	if not list then return end
	local rows, n = Collect()
	local keep
	for _, r in ipairs(rows) do
		if shown and not keep and not r.inHigh and ((shown.node and r.node == shown.node) or (shown.fish and r.fish == shown.fish)
			or (shown.skin and r.skin == shown.skin) or (shown.fishItem and r.fishItem == shown.fishItem)) then keep = r end
	end
	list:SetData(rows)
	list:Select(keep)
	countText:SetText(ns.N(n, "entry", "entries"))
	if shown then Show(shown) end
end

-- the tally ticks while the page is open
ns:On("TALLY", function()
	if list and ns.UI:IsShown() and ns.UI:Current() == "gathering" then page:Refresh() end
end)

-- the profession card an entry is under
local function ProfOf(sel)
	if not sel then return nil end
	if sel.fish or sel.fishItem then return "fish" elseif sel.skin then return "skin" end
	local rec = sel.node and ns.Store:Get("node", sel.node)
	return rec and ns.Gathering:Prof(rec) or nil
end

-- (0.69.0, #40) opened from a profession card or a Journal research card: that profession's card
-- open at the top, the others folded ("herb", "ore", "chest" / "lock" = treasure, "fish", "skin")
function page:ShowOnly(key)
	ns.UI:Open("gathering")
	local prof = (key == "chest" or key == "lock" or key == "treasure") and "treasure" or key
	for k in pairs(opened) do opened[k] = nil end
	opened[prof] = true
	collapsed.new = true
	self:Refresh()
	if list and list.ScrollTop then list:ScrollTop() end
end

local function ShowEntry(sel)
	ns.UI:Open("gathering")
	shown = sel
	local prof = ProfOf(sel)
	if prof then opened[prof] = true end
	page:Refresh()
end
function page:ShowNode(name) ShowEntry({ node = name }) end
function page:ShowSkin(item) ShowEntry({ skin = item }) end
function page:ShowFishing(map) ShowEntry({ fish = map }) end

ns:On("RESET", function() shown = nil if list then list:Select(nil) Show(nil) end end)

ns.UI:RegisterPage(page)
