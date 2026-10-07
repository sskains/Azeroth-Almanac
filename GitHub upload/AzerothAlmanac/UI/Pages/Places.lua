-- Places page: zones with the places found in each, and dungeons and raids entered.
-- Left: zones (gold) with their places indented; dungeons at the end. Right: the selection.

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local page = { key = "places", title = L["Places"], icon = "Interface\\AddOns\\AzerothAlmanac\\Media\\Tab_Places", order = 7 }
local list, detail, countText, nameText
local filter = ""
local searchBox

local collapsed = {}

local function Who(rec)
	local who = {}
	for key in pairs(rec.c or {}) do if key ~= rec.b then who[#who + 1] = ns.CharName(key) end end
	table.sort(who)
	return who
end

local zoneMap -- the zone's map, drawn at the top of a zone's page
local focus   -- a creature opened from the Bestiary: its sightings and kills are pinned on the map
local focusMerchant -- a merchant opened from Merchants: shown with their face, on top
local focusPin -- anything else opened on its zone: { x, y, name, sub, face, icon, onClick }

local function GoTo(pageKey, method, ...)
	local args = { ... }
	return function()
		-- open the page first (a page's own Show* opens it too; "Refresh" only needs the opening)
		ns.UI:Open(pageKey)
		local p = ns.UI:GetPage(pageKey)
		if p and method ~= "Refresh" and p[method] then p[method](p, unpack(args)) end
	end
end

local function CreatureSlots(list)
	local s = {}
	for _, c in ipairs(list) do
		local rec = c.rec
		local lvl = rec.lo and (rec.lo == rec.hi and tostring(rec.lo) or (rec.lo .. "-" .. (rec.hi or rec.lo))) or "?"
		if rec.lo == -1 then lvl = "??" end
		s[#s + 1] = { name = rec.name or "?", icon = W.FindIcon(W.TYPE_ICON[rec.type or ""] or W.KIND.creature.icon),
			note = (L["Level %s"]):format(lvl) .. "  " .. ns.Bestiary:TierMarkup(ns.Bestiary:Tier(rec), 12) .. " " .. ns.Bestiary.TIERS[ns.Bestiary:Tier(rec)],
			tip = L["Click to open in Creatures."], onClick = GoTo("bestiary", "ShowCreature", c.npc) }
	end
	return s
end

local function MerchantSlots(list)
	local s = {}
	for _, m in ipairs(list) do
		s[#s + 1] = { name = m.rec.name or "?", icon = W.FindIcon(W.KIND.merchant.icon), note = m.rec.title or m.rec.sub,
			tip = L["Click to open in People."], onClick = GoTo("merchants", "ShowMerchant", m.npc) }
	end
	return s
end

local QUEST_ICON = { d = "Interface\\RaidFrame\\ReadyCheck-Ready", a = "Interface\\GossipFrame\\ActiveQuestIcon", x = "Interface\\RaidFrame\\ReadyCheck-NotReady" }
local function QuestSlots(list)
	local s = {}
	for _, q in ipairs(list) do
		local st = ns.Quests:MyStatus(q.qid)
		local lvl = ns.Quests:Level(q.qid, q.rec)
		s[#s + 1] = { name = q.rec.name or (L["quest %d"]):format(q.qid), icon = QUEST_ICON[st or ""] or "Interface\\GossipFrame\\AvailableQuestIcon",
			note = lvl and (L["Level %d"]):format(lvl) or nil, tip = L["Click to open in Quests."], onClick = GoTo("quests", "ShowQuest", q.qid) }
	end
	return s
end

-- pins for the zone's map: merchants, quest givers, and you when you're in this zone
local function Pins(map, found)
	local pins = {}
	for _, m in ipairs(found.merchants) do
		if m.rec.x then
			local mine = m.npc == focusMerchant
			pins[#pins + 1] = { x = m.rec.x, y = m.rec.y, icon = mine and W.FindIcon({ "INV_Misc_Coin_02" }) or "Interface\\GossipFrame\\VendorGossipIcon",
				size = mine and 26 or 16, face = mine and m.rec.display or nil, round = mine, top = mine,
				name = m.rec.name, sub = m.rec.title, onClick = GoTo("merchants", "ShowMerchant", m.npc) }
		end
	end
	for _, t in ipairs(found.trainers or {}) do
		if t.rec.x then
			pins[#pins + 1] = { x = t.rec.x, y = t.rec.y, icon = "Interface\\GossipFrame\\TrainerGossipIcon", size = 16,
				name = t.rec.name, sub = t.rec.title, onClick = GoTo("townsfolk", "ShowPerson", t.npc) }
		end
	end
	for _, g in ipairs(found.givers) do
		if g.rec.x and g.rec.gives then
			local n = 0
			for _ in pairs(g.rec.gives) do n = n + 1 end
			pins[#pins + 1] = { x = g.rec.x, y = g.rec.y, icon = "Interface\\GossipFrame\\AvailableQuestIcon", size = 16,
				name = g.rec.name, sub = (L["Gives %s you've found."]):format(ns.N(n, "quest", "quests")) }
		end
	end
	-- the Bestiary's creature: where it was seen (its face) and killed (a skull)
	local frec = focus and ns.Store:Get("creature", focus)
	if frec then
		local B = ns.Bestiary
		local face = frec.display
		for _, s in ipairs(B:Spots(frec, "spots", map)) do
			pins[#pins + 1] = { x = s.x, y = s.y, size = 18, face = face, round = true,
				icon = W.FindIcon(W.TYPE_ICON[frec.type or ""] or W.KIND.creature.icon),
				name = frec.name, sub = L["Seen here."], onClick = GoTo("bestiary", "ShowCreature", focus) }
		end
		for _, s in ipairs(B:Spots(frec, "kz", map)) do
			pins[#pins + 1] = { x = s.x, y = s.y, size = 16, top = true,
				icon = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
				name = frec.name, sub = L["Killed here."], onClick = GoTo("bestiary", "ShowCreature", focus) }
		end
	end
	if focusPin and focusPin.map == map and focusPin.spots then
		local p = focusPin
		for _, s in ipairs(p.spots) do
			pins[#pins + 1] = { x = s.x, y = s.y, icon = p.icon or W.FindIcon(W.KIND.townsfolk.icon), size = s.size or 18, round = true, top = true,
				name = p.name, sub = s.sub or p.sub, onClick = p.onClick }
		end
	elseif focusPin and focusPin.map == map and focusPin.x then
		local p = focusPin
		pins[#pins + 1] = { x = p.x, y = p.y, icon = p.icon or W.FindIcon(W.KIND.townsfolk.icon), size = 26, face = p.face,
			round = true, top = true, name = p.name, sub = p.sub, onClick = p.onClick }
	end
	local here = ns.Where()
	if here.map == map and here.x then
		local facing = GetPlayerFacing and ns.Readable(GetPlayerFacing())
		pins[#pins + 1] = { x = here.x, y = here.y, icon = "Interface\\WorldMap\\WorldMapArrow", size = 24, facing = facing, top = true,
			name = UnitName("player"), sub = L["You are here."] }
	end
	return pins
end

local function DescribeZone(z)
	local rec = z.rec
	local found = ns.Places:InZone(z.id, rec.name)
	local b = {}
	b[#b + 1] = { "frame", zoneMap, function(width)
		local h = zoneMap:Draw(z.id, width)
		if h > 0 then zoneMap:SetPins(Pins(z.id, found)) end
		return h
	end }
	local mrec = focusMerchant and ns.Store:Get("merchant", focusMerchant)
	if mrec then
		b[#b + 1] = { "small", W.PinMarkup(14) .. " " .. (L["%s is marked on the map%s. (Pick another zone to clear.)"]):format(mrec.name or "?",
			mrec.title and (" <" .. mrec.title .. ">") or "") }
	end
	if focusPin and focusPin.map == z.id then
		if focusPin.spots then
			b[#b + 1] = { "small", W.PinMarkup(14) .. " " .. (L["%s: %d spots marked on the map. (Pick another zone to clear.)"]):format(focusPin.name or "?", #focusPin.spots) }
		else
			b[#b + 1] = { "small", W.PinMarkup(14) .. " " .. (L["%s is marked on the map%s. (Pick another zone to clear.)"]):format(focusPin.name or "?",
				focusPin.sub and (" <" .. focusPin.sub .. ">") or "") }
		end
	end
	local frec = focus and ns.Store:Get("creature", focus)
	if frec then
		local seen, killed = #ns.Bestiary:Spots(frec, "spots", z.id), #ns.Bestiary:Spots(frec, "kz", z.id)
		b[#b + 1] = { "small", ("|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:14:14|t ")
			.. (L["%s on the map: seen in %d spots, killed in %d. (Pick another zone to clear.)"]):format(frec.name or "?", seen, killed)
			.. ((seen + killed == 0) and (" " .. L["Spots are recorded from now on."]) or "") }
	end
	b[#b + 1] = { "banner", L["General"] }
	if rec.continent then b[#b + 1] = { "stat", L["Continent"], rec.continent } end
	if found.lo then b[#b + 1] = { "stat", L["Creatures met"], (L["level %s"]):format(found.lo == found.hi and tostring(found.lo) or (found.lo .. " - " .. found.hi)) } end
	b[#b + 1] = { "stat", L["First discovered"], ns.CharName(rec.b) .. ", " .. ns.DateText(rec.f) }
	local who = Who(rec)
	if #who > 0 then b[#b + 1] = { "stat", L["Also found by"], table.concat(who, ", ") } end
	b[#b + 1] = { "stat", L["Visits"], tostring(rec.n or 1) }
	b[#b + 1] = { "stat", L["Last visit"], ns.AgoText(rec.l) }

	-- how much of it this character has explored (the game's own exploration list)
	local total, done, areas = ns.Places:Exploration(rec.name)
	if total then
		b[#b + 1] = { "banner", (L["Exploration (%d of %d)"]):format(done, total) }
		b[#b + 1] = { "stat", L["Explored"], (done >= total and "|cff40ff40" or "|cffffd100") .. (L["%d of %d areas"]):format(done, total) .. "|r" }
		local left = {}
		for _, a in ipairs(areas) do if not a.done then left[#left + 1] = a.name end end
		if #left > 0 then b[#b + 1] = { "small", L["Still to find: "] .. table.concat(left, ", ") } end
	end

	b[#b + 1] = { "banner", (L["Places found here (%d)"]):format(#z.subs) }
	if #z.subs == 0 then
		b[#b + 1] = { "small", L["None yet."] }
	else
		local me = ns.CharKey()
		for _, sz in ipairs(z.subs) do
			local mine = ns.Places:ExploredBy(me, sz.id)
			local text = ns.CharName(sz.rec.b) .. ", " .. ns.DateText(sz.rec.f)
			if mine then text = text .. "  |cff999999" .. (mine.xp and (L["explored, %d experience"]):format(mine.xp) or L["explored"]) .. "|r" end
			b[#b + 1] = { "stat", sz.rec.name or "?", text }
		end
	end
	if #found.creatures > 0 then
		b[#b + 1] = { "banner", (L["Creatures (%d)"]):format(#found.creatures) }
		b[#b + 1] = { "slots", CreatureSlots(found.creatures) }
	end
	if #found.merchants > 0 then
		b[#b + 1] = { "banner", (L["Merchants (%d)"]):format(#found.merchants) }
		b[#b + 1] = { "slots", MerchantSlots(found.merchants) }
	end
	if #(found.trainers or {}) > 0 then
		local s = {}
		for _, t in ipairs(found.trainers) do
			s[#s + 1] = { name = t.rec.name or "?", icon = W.FindIcon(W.KIND.trainer.icon), note = t.rec.title or t.rec.sub,
				tip = L["Click to open in People."], onClick = GoTo("townsfolk", "ShowPerson", t.npc) }
		end
		b[#b + 1] = { "banner", (L["Trainers (%d)"]):format(#found.trainers) }
		b[#b + 1] = { "slots", s }
	end
	if #found.quests > 0 then
		b[#b + 1] = { "banner", (L["Quests (%d)"]):format(#found.quests) }
		b[#b + 1] = { "slots", QuestSlots(found.quests) }
	end

	-- each character's own exploration of the zone
	local rows = {}
	for key, c in pairs(ns.db.chars) do
		local n, xp = 0, 0
		for _, sz in ipairs(z.subs) do
			local e = c.explored and c.explored[sz.id]
			if e then n = n + 1 xp = xp + (e.xp or 0) end
		end
		local areas = c.mapAreas and c.mapAreas[z.id]
		if n > 0 or areas or (rec.c and rec.c[key]) then
			local parts = {}
			if areas then parts[#parts + 1] = (L["%d map areas uncovered"]):format(areas) end
			if n > 0 then parts[#parts + 1] = (L["%s explored"]):format(ns.N(n, "place", "places")) .. (xp > 0 and (" (" .. (L["%d experience"]):format(xp) .. ")") or "") end
			if #parts == 0 then parts[1] = L["visited"] end
			rows[#rows + 1] = { "stat", ns.CharName(key), table.concat(parts, ", "), sortKey = ns.CharName(key, true) }
		end
	end
	if #rows > 0 then
		b[#b + 1] = { "banner", L["Your characters"] }
		table.sort(rows, function(x, y) return x.sortKey < y.sortKey end) -- (by name, not by colour code)
		for _, r in ipairs(rows) do b[#b + 1] = r end
	end
	return b
end

local function DescribeSub(sz)
	local rec = sz.rec
	local b = {}
	-- the zone's map with this place outlined (its uncovered area), else a pin where you first entered it
	if rec.map and zoneMap then
		b[#b + 1] = { "frame", zoneMap, function(width)
			local h = zoneMap:Draw(rec.map, width)
			if h > 0 then
				local outlined = rec.x and zoneMap:SetHighlight(rec.x, rec.y)
				local pins = {}
				if rec.x and not outlined then
					pins[1] = { x = rec.x, y = rec.y, icon = W.KindIcon("subzone"), size = 24, round = true, top = true, place = true,
						name = rec.name, sub = L["First entered here."] }
				end
				local here = ns.Where()
				if here.map == rec.map and here.x then
					pins[#pins + 1] = { x = here.x, y = here.y, icon = "Interface\\WorldMap\\WorldMapArrow", size = 24, top = true,
						facing = GetPlayerFacing and ns.Readable(GetPlayerFacing()), name = UnitName("player"), sub = L["You are here."] }
				end
				zoneMap:SetPins(pins)
			end
			return h
		end }
	end
	b[#b + 1] = { "banner", L["General"] }
	b[#b + 1] = { "stat", L["Zone"], rec.zone or "?" }
	b[#b + 1] = { "stat", L["First discovered"], ns.CharName(rec.b) .. ", " .. ns.DateText(rec.f) }
	local who = Who(rec)
	if #who > 0 then b[#b + 1] = { "stat", L["Also found by"], table.concat(who, ", ") } end
	if rec.x then b[#b + 1] = { "stat", L["First entered at"], ("%.1f, %.1f"):format(rec.x, rec.y) } end
	b[#b + 1] = { "stat", L["Visits"], tostring(rec.n or 1) }
	b[#b + 1] = { "stat", L["Last visit"], ns.AgoText(rec.l) }

	local explorers = {}
	for key in pairs(ns.db.chars) do
		local e = ns.Places:ExploredBy(key, sz.id)
		if e then explorers[#explorers + 1] = { "stat", ns.CharName(key), ((e.t or 0) > 0 and ns.DateText(e.t) or "") .. (e.xp and ("  |cff999999" .. (L["%d experience"]):format(e.xp) .. "|r") or "") } end
	end
	if #explorers > 0 then
		b[#b + 1] = { "banner", L["Explored by"] }
		for _, r in ipairs(explorers) do b[#b + 1] = r end
	end

	local merchants, quests = {}, {}
	for npc, m in pairs(ns.Store:Shown("merchant")) do
		if m.map == rec.map and m.sub == rec.name then merchants[#merchants + 1] = { npc = npc, rec = m } end
	end
	for qid, q in pairs(ns.Store:Shown("quest")) do
		if q.gpos and q.gpos.map == rec.map and q.gpos.sub == rec.name then quests[#quests + 1] = { qid = qid, rec = q } end
	end
	table.sort(merchants, function(x, y) return (x.rec.name or "") < (y.rec.name or "") end)
	table.sort(quests, function(x, y) return (x.rec.name or "") < (y.rec.name or "") end)
	if #merchants > 0 then
		b[#b + 1] = { "banner", (L["Merchants (%d)"]):format(#merchants) }
		b[#b + 1] = { "slots", MerchantSlots(merchants) }
	end
	if #quests > 0 then
		b[#b + 1] = { "banner", (L["Quests offered here (%d)"]):format(#quests) }
		b[#b + 1] = { "slots", QuestSlots(quests) }
	end
	return b
end

local function DescribeInstance(inst)
	local rec = inst.rec
	return {
		{ "banner", L["General"] },
		{ "stat", L["Kind"], rec.type == "raid" and L["Raid"] or L["Dungeon"] },
		{ "stat", L["First entered"], ns.CharName(rec.b) .. ", " .. ns.DateText(rec.f) },
		{ "stat", L["Times entered"], tostring(rec.n or 1) },
		{ "stat", L["Last time"], ns.AgoText(rec.l) },
	}
end

local function Matches(rec)
	return filter == "" or ((rec.name or ""):lower():find(filter, 1, true) ~= nil)
end

local function Collect()
	local rows, zones, places, dungeons = {}, 0, 0, 0
	-- continents, each with its zones, each with its places (the tree is sorted by continent)
	local lastCont, contRow
	for _, z in ipairs(ns.Places:Tree()) do
		zones = zones + 1
		places = places + #z.subs
		local subs = {}
		for _, s in ipairs(z.subs) do if Matches(s.rec) then subs[#subs + 1] = s end end
		if Matches(z.rec) or #subs > 0 then
			local cont = z.rec.continent or L["Elsewhere"]
			if cont ~= lastCont then
				lastCont = cont
				contRow = { kind = "continent", text = cont, key = "c:" .. cont, count = 0 }
				rows[#rows + 1] = contRow
			end
			contRow.count = contRow.count + 1
			if not collapsed[contRow.key] then
				rows[#rows + 1] = { kind = "zone", z = z, id = z.id } -- (id: so Back finds this row again)
				if not collapsed[z.id] then
					for _, s in ipairs(subs) do rows[#rows + 1] = { kind = "subzone", s = s, id = s.id } end
				end
			end
		end
	end
	local inst = {}
	for id, rec in pairs(ns.Store:Shown("instance")) do
		dungeons = dungeons + 1
		if Matches(rec) then inst[#inst + 1] = { id = id, rec = rec } end
	end
	table.sort(inst, function(a, b) return (a.rec.name or "") < (b.rec.name or "") end)
	if #inst > 0 then
		rows[#rows + 1] = { kind = "header", text = L["Dungeons and raids"] }
		for _, i in ipairs(inst) do rows[#rows + 1] = { kind = "instance", i = i, id = i.id } end
	end
	return rows, zones, places, dungeons
end

local function ShowRow(r, keep)
	if not r then return end
	if r.kind == "zone" then
		detail.shownZone = r.z.id
		nameText:SetText(r.z.rec.name or "?")
		detail:SetBlocks(DescribeZone(r.z), nil, keep)
	elseif r.kind == "subzone" then
		detail.shownZone = nil
		nameText:SetText(r.s.rec.name or "?")
		detail:SetBlocks(DescribeSub(r.s), nil, keep)
	elseif r.kind == "instance" then
		detail.shownZone = nil
		nameText:SetText(r.i.rec.name or "?")
		detail:SetBlocks(DescribeInstance(r.i), nil, keep)
	end
end

function page:Build(parent, header)
	local search = W.Search(header, 200, function(text)
		filter = text
		page:Refresh()
	end)
	searchBox = search
	search:SetPoint("LEFT", header, "LEFT", 16, -2)
	countText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countText:SetPoint("RIGHT", header, "RIGHT", -12, -2)

	local left = W.Inset(parent)
	left:SetPoint("TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", 0, 0)
	left:SetWidth(330)
	list = W.List(left, {
		collapse = { state = collapsed, key = function(r) return (r.kind == "zone" and r.z and r.z.id) or (r.kind == "continent" and r.key) or nil end, refresh = function() page:Refresh() end },
		rowHeight = 24,
		style = "log",   -- the Map & Quest Log look, as on Quests
		round = true,
		emptyText = L["No places yet. Every zone and place you enter is recorded here."],
		update = function(row, r)
			row:SetHeader(r.kind == "zone" or r.kind == "header" or r.kind == "continent", (r.kind == "zone" and collapsed[r.z.id]) or (r.kind == "continent" and collapsed[r.key]))
			row.icon:ClearAllPoints()
			if r.kind == "continent" then
				row.icon:SetPoint("LEFT", 4, 0)
				row.icon:SetTexture(W.FindIcon({ "INV_Misc_Map02", "INV_Misc_Map_01" }))
				row.text:SetFontObject(W.Font("GameFontNormalLarge", "GameFontNormal"))
				row.text:SetText("|cffffd100" .. r.text .. "|r")
				row.right:SetText("|cff999999" .. r.count .. "|r")
			elseif r.kind == "subzone" then
				row.icon:SetPoint("LEFT", 46, 0)
				row.icon:SetTexture(W.KindIcon("subzone"))
				row.text:SetFontObject(GameFontHighlight)
				row.text:SetText(r.s.rec.name)
				row.right:SetText("")
			elseif r.kind == "zone" then
				row.indent = 22 -- (under its continent)
				row.icon:SetPoint("LEFT", 20, 0)
				row.icon:SetTexture(W.KindIcon("zone"))
				row.text:SetFontObject(GameFontNormal)
				row.text:SetText(r.z.rec.name)
				local total, done = ns.Places:Exploration(r.z.rec.name)
				row.right:SetText(total and ((done >= total and "|cff40ff40" or "|cff999999") .. done .. "/" .. total .. "|r") or ("|cff999999" .. #r.z.subs .. "|r"))
			elseif r.kind == "instance" then
				row.icon:SetPoint("LEFT", 4, 0)
				row.icon:SetTexture(W.KindIcon("instance"))
				row.text:SetFontObject(GameFontNormal)
				row.text:SetText(r.i.rec.name)
				row.right:SetText(r.i.rec.type == "raid" and ("|cff999999" .. L["Raid"] .. "|r") or "")
			else
				row.icon:SetPoint("LEFT", 4, 0)
				row.icon:SetTexture(nil)
				row.text:SetFontObject(GameFontNormalSmall)
				row.text:SetText("|cffffffff" .. r.text .. "|r")
				row.right:SetText("")
			end
		end,
		restore = function(r) ShowRow(r) end,
		-- hovering a place outlines it on the map shown (when it's in that zone); leaving puts back
		-- the selected place's outline (or none for a zone)
		onHover = function(r)
			if r.kind ~= "subzone" or not (zoneMap and zoneMap:IsVisible() and zoneMap.map == r.s.rec.map) then return end
			if not r.s.rec.x then return end
			-- its outline, or (no shape for it) a pin where it was first entered; the selected
			-- place's own pin steps aside meanwhile
			zoneMap:ShowPlacePins(false)
			zoneMap:ClearPreviewPin()
			if not zoneMap:SetHighlight(r.s.rec.x, r.s.rec.y) then
				zoneMap:SetPreviewPin(r.s.rec.x, r.s.rec.y, W.KindIcon("subzone"), r.s.rec.name)
			end
			zoneMap.previewing = true
		end,
		onLeave = function()
			if not (zoneMap and zoneMap.previewing) then return end
			zoneMap.previewing = nil
			zoneMap:ClearPreviewPin()
			zoneMap:ShowPlacePins(true)
			local sel = list:Selected()
			if sel and sel.kind == "subzone" and sel.s.rec.x and zoneMap.map == sel.s.rec.map then
				zoneMap:SetHighlight(sel.s.rec.x, sel.s.rec.y)
			else
				zoneMap:ClearHighlight()
			end
		end,
		onClick = function(r, _, mouse)
			if mouse and mouse ~= "LeftButton" then return end
			-- the first click on a zone opened with something marked shows it plainly; after that it folds
			local hadFocus = focus or focusMerchant or focusPin
			focus, focusMerchant, focusPin = nil, nil, nil
			if r.kind == "continent" then
				collapsed[r.key] = not collapsed[r.key]
				page:Refresh()
				return
			end
			if r.kind == "zone" and detail.shownZone == r.z.id and not hadFocus then
				collapsed[r.z.id] = not collapsed[r.z.id]
				page:Refresh()
				return
			end
			-- a dungeon opens on its own page
			if r.kind == "instance" then
				local p = ns.UI:GetPage("dungeons")
				if p then return p:ShowDungeon(r.i.id) end
			end
			ShowRow(r)
		end,
	})
	list:SetAllPoints(left)

	detail = W.Detail(parent, 30)
	detail:SetTheme({ "Herbalism", "Fishing" }) -- the profession book's paintings behind the card and body
	zoneMap = W.ZoneMap(detail)
	detail:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
	detail:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
	nameText = detail.top:CreateFontString(nil, "OVERLAY")
	W.HeroFont(nameText, 26)
	nameText:SetPoint("TOPLEFT", 2, 0)
	detail:SetBlocks(nil, L["Select a zone or place. Click a zone again to fold it."])
end

function page:Refresh()
	if not list then return end
	local rows, zones, places, dungeons = Collect()
	-- keep the selection on the same record after a rebuild
	local sel = list:Selected()
	local keep
	if sel then
		for _, r in ipairs(rows) do
			if r.kind == sel.kind and ((r.z and sel.z and r.z.id == sel.z.id) or (r.s and sel.s and r.s.id == sel.s.id) or (r.i and sel.i and r.i.id == sel.i.id)) then keep = r end
		end
	end
	list:SetData(rows)
	list:Select(keep)
	if keep then ShowRow(keep, true) end
	countText:SetText((L["%d zones, %d places, %d dungeons"]):format(zones, places, dungeons))
end

-- open the page on a zone (uiMapID)
-- creature / merchant: marked with their spots or face. pin: anything else, { x, y (percent), name,
-- sub, face (display id), icon, onClick }
function page:ShowZone(map, creature, merchant, pin)
	-- (only a zone the page lists: in a character-only Almanac, one this character hasn't found
	-- isn't there, and the link falls back to its caller's own way, 0.63.0)
	if not ns.Store:Shown("zone")[map] then return false end
	focus, focusMerchant = creature, merchant
	focusPin = pin and { map = map, x = pin.x, y = pin.y, name = pin.name, sub = pin.sub, face = pin.face, icon = pin.icon, onClick = pin.onClick, spots = pin.spots } or nil
	ns.UI:Open("places")
	collapsed[map] = nil
	local zrec = ns.Store:Get("zone", map)
	collapsed["c:" .. ((zrec and zrec.continent) or L["Elsewhere"])] = nil
	-- a search that hides the zone would leave the page empty
	if filter ~= "" then
		filter = ""
		if searchBox and searchBox.SetText then searchBox:SetText("") end
	end
	self:Refresh()
	for _, r in ipairs(list:Data()) do
		if r.kind == "zone" and r.z.id == map then
			list:Select(r)
			ShowRow(r)
			return true
		end
	end
	return false
end

ns:On("RESET", function()
	if list then list:Select(nil) nameText:SetText("") detail:SetBlocks(nil, L["Select a zone or place."]) end
end)

ns.UI:RegisterPage(page)
