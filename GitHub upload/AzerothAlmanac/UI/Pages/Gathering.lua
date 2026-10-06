-- Gathering page: herbs, ore, chests and other objects you've opened, fishing by zone, and what
-- you've skinned (by leather / hide; the creatures it came from are on its page). A node's page:
-- how often you've gathered it, your skill at the time, what came out (and, once Journeyman, everything it can hold; once Expert, how likely each is),
-- and where you found it (Show on map pins every spot).

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local page = { key = "gathering", title = L["Gathering"], icon = { 237271, "Trade_Herbalism", "INV_Misc_Herb_07" }, order = 6 }
local list, detail, countText, kindButton, portrait, nameText, kindText, placeText, mapButton
local filter, kindFilter = "", nil
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
	for npc, rec in pairs(ns.Store:All("creature")) do
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
local function TopItem(rec)
	local best, n, kinds = nil, 0, 0
	for item, c in pairs(rec.items or {}) do
		kinds = kinds + 1
		if c > n then best, n = item, c end
	end
	if rec.kind == "chest" and kinds > 1 then return nil end
	return best
end

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
	b[#b + 1] = { "stat", isFish and L["Catches"] or L["Gathered"], (rec.gathered or 0) > 0 and ns.Times(rec.gathered) or L["not yet"] }
	if (rec.sighted or 0) > 0 then b[#b + 1] = { "stat", L["Sighted"], ns.Times(rec.sighted) } end
	if rec.skill then
		local s = rec.skill[1] == rec.skill[2] and tostring(rec.skill[1]) or (rec.skill[1] .. " - " .. rec.skill[2])
		b[#b + 1] = { "stat", L["Your skill at the time"], s }
	end
	b[#b + 1] = { "stat", (rec.gathered or 0) > 0 and L["First found"] or L["First sighted"], ns.CharName(rec.b) .. ", " .. ns.DateText(rec.f) }
	local others = Who(rec)
	if #others > 0 then b[#b + 1] = { "stat", L["Also gathered by"], table.concat(others, ", ") } end

	-- the ranks (the character sheet's blue skill bar, like a creature's): Journeyman reveals
	-- everything it can hold, Expert how likely each is; past Master the count keeps rolling
	local n = rec.gathered or 0
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

local function Show(sel)
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
-- List
---------------------------------------------------------------------------

local KINDS = {
	{ key = nil, label = L["Everything"] },
	{ key = "herb", label = L["Herbs"] }, { key = "ore", label = L["Ore and stone"] },
	{ key = "chest", label = L["Chests and objects"] }, { key = "fish", label = L["Fishing"] },
	{ key = "skin", label = L["Skinning"] },
}

local function Collect()
	local G = ns.Gathering
	local rows, n = {}, 0
	local groups = { herb = {}, ore = {}, chest = {}, fish = {}, skin = {} }
	local function Hit(...)
		if filter == "" then return true end
		for i = 1, select("#", ...) do
			local v = select(i, ...)
			if type(v) == "string" and v:lower():find(filter, 1, true) then return true end
		end
	end
	for name, rec in pairs(ns.Store:All("node")) do
		local quest = rec.kind ~= "herb" and rec.kind ~= "ore" and ns.Gathering.OnlyQuestItems(rec.items)
		if not quest and Hit(name) then table.insert(groups[rec.kind or "chest"] or groups.chest, { node = name, rec = rec, label = name }) end
	end
	for map, rec in pairs(ns.Store:All("fishing")) do
		local label = rec.zone or ZoneName(map) or "?"
		if Hit(label) then table.insert(groups.fish, { fish = map, rec = rec, label = label }) end
	end
	for item, e in pairs(SkinItems()) do
		local name, q = ItemName(item)
		local label = name or (L["item %d"]):format(item)
		-- a search finds it by its name or by a creature it came from
		local hit = Hit(label)
		if not hit then for _, src in ipairs(e.sources) do if Hit(src.rec.name) then hit = true break end end end
		if hit then table.insert(groups.skin, { skin = item, data = e, label = label, q = q }) end
	end
	local order = { { "herb", L["Herbs"] }, { "ore", L["Ore and stone"] }, { "chest", L["Chests and objects"] }, { "fish", L["Fishing"] }, { "skin", L["Skinning"] } }
	for _, o in ipairs(order) do
		local key, label = o[1], o[2]
		local g = groups[key]
		if #g > 0 and (kindFilter == nil or kindFilter == key) then
			table.sort(g, function(a, b) return a.label < b.label end)
			rows[#rows + 1] = { header = label, key = key, count = #g }
			for _, e in ipairs(g) do
				n = n + 1
				if not collapsed[key] then rows[#rows + 1] = e end
			end
		end
	end
	return rows, n
end

local function KindLabel()
	for _, k in ipairs(KINDS) do if k.key == kindFilter then return k.label end end
	return L["Everything"]
end

local function KindMenu(anchor)
	local items = { { title = true, text = L["Show"] } }
	for _, k in ipairs(KINDS) do
		items[#items + 1] = { text = k.label, selected = k.key == kindFilter, run = function()
			kindFilter = k.key
			kindButton:SetText(KindLabel())
			page:Refresh()
		end }
	end
	W.Menu(anchor, items)
end

function page:Build(parent, header)
	local search = W.Search(header, 180, function(text)
		filter = text
		page:Refresh()
	end)
	search:SetPoint("LEFT", header, "LEFT", 16, -2)
	kindButton = W.Dropdown(header, KindLabel(), 140, function(self) KindMenu(self) end)
	kindButton:SetPoint("LEFT", search, "RIGHT", 12, 0)
	countText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countText:SetPoint("RIGHT", header, "RIGHT", -12, -2)

	local left = W.Inset(parent)
	left:SetPoint("TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", 0, 0)
	left:SetWidth(320)
	list = W.List(left, {
		collapse = { state = collapsed, key = function(r) return r.header and r.key end, refresh = function() page:Refresh() end },
		rowHeight = 24,
		style = "log",   -- the Map & Quest Log look, as on Quests
		emptyText = L["Nothing gathered yet. Herbs, veins, chests, fishing and skinning are recorded as you go."],
		update = function(row, r)
			row.icon:ClearAllPoints()
			row:SetHeader(r.header ~= nil, r.header and collapsed[r.key])
			if r.header then
				row.icon:SetPoint("LEFT", 4, 0)
				row.icon:SetTexture(nil)
				row.text:SetFontObject(W.Font("GameFontNormalLarge", "GameFontNormal"))
				row.text:SetText(r.header)
				row.right:SetText("|cff999999" .. r.count .. "|r")
				return
			end
			row.icon:SetPoint("LEFT", 22, 0)
			row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			row.text:SetFontObject(GameFontHighlight)
			row.text:SetText(r.label)
			if r.skin then
				row.icon:SetTexture(ItemIcon(r.skin) or W.FindIcon({ "INV_Misc_Pelt_Wolf_01" }))
				row.text:SetText(QualityHex(r.q) .. r.label .. "|r")
				row.right:SetText("|cff999999" .. ns.Times(r.data.n) .. "|r")
			else
				local top = TopItem(r.rec)
				local icon = top and ItemIcon(top)
				if icon then row.icon:SetTexture(icon) else W.SetIcon(row.icon, ns.Gathering.KIND[r.fish and "fish" or (r.rec.kind or "chest")].icon) end
				local tier = ns.Gathering:Tier(r.rec)
				local count = (r.rec.gathered or 0) > 0 and ns.Times(r.rec.gathered) or L["sighted"]
				row.right:SetText((tier > 1 and (ns.Gathering:TierMarkup(tier, 14, r.fish and "fish" or r.rec.kind) .. " ") or "") .. "|cff999999" .. count .. "|r")
			end
		end,
		restore = function(r)
			if r.node then Show({ node = r.node }) elseif r.fish then Show({ fish = r.fish }) elseif r.skin then Show({ skin = r.skin }) end
		end,
		onClick = function(r)
			if r.header then
				collapsed[r.key] = not collapsed[r.key]
				page:Refresh()
			elseif r.skin then
				Show({ skin = r.skin })
			else
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
		if shown and ((shown.node and r.node == shown.node) or (shown.fish and r.fish == shown.fish)
			or (shown.skin and r.skin == shown.skin)) then keep = r end
	end
	list:SetData(rows)
	list:Select(keep)
	countText:SetText(ns.N(n, "entry", "entries"))
	if shown then Show(shown) end
end

function page:ShowNode(name)
	ns.UI:Open("gathering")
	shown = { node = name }
	self:Refresh()
end

function page:ShowSkin(item)
	ns.UI:Open("gathering")
	shown = { skin = item }
	self:Refresh()
end

function page:ShowFishing(map)
	ns.UI:Open("gathering")
	shown = { fish = map }
	self:Refresh()
end

ns:On("RESET", function() shown = nil if list then list:Select(nil) Show(nil) end end)

ns.UI:RegisterPage(page)
