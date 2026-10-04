-- Gathering page: herbs, ore, chests and other objects you've opened, fishing by zone, and the
-- creatures you've skinned. A node's page: how often you've gathered it, your skill at the time,
-- what came out (and, once Studied, everything it can hold; once Mastered, how likely each is),
-- and where you found it (Show on map pins every spot).

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local page = { key = "gathering", title = L["Gathering"], icon = { "Trade_Herbalism", "INV_Misc_Herb_07", "Trade_Mining" }, order = 6.2 }
local list, detail, countText, kindButton, portrait, nameText, kindText, placeText, mapButton
local filter, kindFilter = "", nil
local shown -- { node = name } | { fish = map }
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

-- the record's face: what comes out of it most often
local function TopItem(rec)
	local best, n = nil, 0
	for item, c in pairs(rec.items or {}) do if c > n then best, n = item, c end end
	return best
end

local function Record(sel)
	if not sel then return nil end
	if sel.node then return ns.Store:Get("node", sel.node), "node" end
	if sel.fish then return ns.Store:Get("fishing", sel.fish), "fish" end
	if sel.creature then return ns.Store:Get("creature", sel.creature), "skin" end
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

	-- research: Studied reveals everything it can hold, Mastered how likely each is
	local B = ns.Bestiary
	local text = (L["%d / %d"]):format(math.min(rec.gathered or 0, G.MASTERED), G.MASTERED)
	if need and B then text = text .. "  ·  " .. (L["%d to %s"]):format(need, B.TIERS[tier == 1 and 3 or 4]) elseif B then text = text .. "  ·  " .. B.TIERS[4] end
	b[#b + 1] = { "bar", nil, math.min(rec.gathered or 0, G.MASTERED), G.MASTERED, text, tier >= 4 and "Mastery" or k.flavor }

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

-- a skinned creature: what its corpses gave you; its full skinning table once it is Mastered in the
-- Bestiary (the creature's research tier, by kills)
local function DescribeSkin(npc, rec)
	local B = ns.Bestiary
	local b = {}
	local tier = B:Tier(rec)
	b[#b + 1] = { "banner", L["General"] }
	b[#b + 1] = { "stat", L["Kind"], L["Skinning"] }
	b[#b + 1] = { "stat", L["Skinned"], ns.Times(rec.gathered or 0) }
	if (rec.kills or 0) > 0 then b[#b + 1] = { "stat", L["Kills"], tostring(rec.kills) } end
	b[#b + 1] = { "stat", L["Research"], B:TierMarkup(tier, 14) .. " " .. B:TierText(tier) }
	local got = {}
	for item, n in pairs(rec.gather or {}) do got[#got + 1] = { item = item, n = n } end
	table.sort(got, function(x, y) return x.n > y.n end)
	local c = ns.CreatureDB and ns.CreatureDB:Get(npc)
	local classic = {}
	if c and c.skin and tier >= 4 then for _, e in ipairs(c.skin) do classic[e.item] = e.chance end end
	local slots = {}
	for _, e in ipairs(got) do
		local note = ("%d / %d"):format(e.n, rec.gathered or e.n)
		if classic[e.item] then note = note .. "  " .. CLASSIC .. (L["Classic %.0f%%"]):format(classic[e.item]) .. "|r" end
		slots[#slots + 1] = { item = e.item, note = note, onClick = GoTo("items", "ShowItem", e.item) }
	end
	b[#b + 1] = { "banner", (L["What came out (%d)"]):format(#slots) }
	if #slots > 0 then b[#b + 1] = { "slots", slots } end
	if c and c.skin and #c.skin > 0 then
		if tier >= 4 then
			local more = {}
			for _, e in ipairs(c.skin) do
				if not (rec.gather and rec.gather[e.item]) then
					more[#more + 1] = { item = e.item, grey = true, note = CLASSIC .. (L["Classic %.0f%%"]):format(e.chance) .. "|r" }
				end
			end
			if #more > 0 then
				b[#b + 1] = { "banner", (L["It can also give (%d)"]):format(#more) }
				b[#b + 1] = { "slots", more }
			end
		else
			b[#b + 1] = { "small", L["Everything it can give is revealed once it is Mastered in the Bestiary."] }
		end
	end
	b[#b + 1] = { "banner", L["The creature"] }
	b[#b + 1] = { "slots", { { name = rec.name or "?", icon = W.FindIcon(W.TYPE_ICON[rec.type or ""] or W.KIND.creature.icon),
		note = L["Open in the Bestiary"], tip = L["Its abilities, loot, kills and where it lives."], onClick = GoTo("bestiary", "ShowCreature", npc) } } }
	return b
end

local function Show(sel)
	local rec, what = Record(sel)
	if rec and what == "skin" then
		shown = sel
		local B = ns.Bestiary
		portrait:Show()
		if not B:SetFace(portrait.art, sel.creature, rec) then
			W.SetIcon(portrait.art, { "INV_Misc_Pelt_Wolf_01" })
			portrait.art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		end
		local tier = B:Tier(rec)
		local c = B.TIER_COLORS[tier]
		portrait:SetRing(c[1], c[2], c[3])
		nameText:SetText(rec.name or "?")
		kindText:SetText(B:TierMarkup(tier, 14) .. " " .. L["Skinning"])
		placeText:SetText("")
		mapButton:Hide()
		detail:SetBlocks(DescribeSkin(sel.creature, rec))
		return
	end
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
	kindText:SetText((ns.Bestiary and (ns.Bestiary:TierMarkup(tier, 14) .. " ") or "") .. (isFish and L["Fishing"] or k.label))
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
	for npc, rec in pairs(ns.Store:All("creature")) do
		if (rec.gathered or 0) > 0 and Hit(rec.name) then table.insert(groups.skin, { creature = npc, rec = rec, label = rec.name or "?" }) end
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
		rowHeight = 28,
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
			if r.creature then
				if not ns.Bestiary:SetFace(row.icon, r.creature, r.rec) then W.SetIcon(row.icon, { "INV_Misc_Pelt_Wolf_01" }) row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
				row.right:SetText("|cff999999" .. ns.Times(r.rec.gathered or 0) .. "|r")
			else
				local top = TopItem(r.rec)
				local icon = top and ItemIcon(top)
				if icon then row.icon:SetTexture(icon) else W.SetIcon(row.icon, ns.Gathering.KIND[r.fish and "fish" or (r.rec.kind or "chest")].icon) end
				local tier = ns.Gathering:Tier(r.rec)
				local count = (r.rec.gathered or 0) > 0 and ns.Times(r.rec.gathered) or L["sighted"]
				row.right:SetText((tier > 1 and ns.Bestiary and (ns.Bestiary:TierMarkup(tier, 14) .. " ") or "") .. "|cff999999" .. count .. "|r")
			end
		end,
		restore = function(r)
			if r.node then Show({ node = r.node }) elseif r.fish then Show({ fish = r.fish }) elseif r.creature then Show({ creature = r.creature }) end
		end,
		onClick = function(r)
			if r.header then
				collapsed[r.key] = not collapsed[r.key]
				page:Refresh()
			elseif r.creature then
				Show({ creature = r.creature })
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
			or (shown.creature and r.creature == shown.creature)) then keep = r end
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

function page:ShowFishing(map)
	ns.UI:Open("gathering")
	shown = { fish = map }
	self:Refresh()
end

ns:On("RESET", function() shown = nil if list then list:Select(nil) Show(nil) end end)

ns.UI:RegisterPage(page)
