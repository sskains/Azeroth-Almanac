-- Townsfolk page: the people of Azeroth this account has met - trainers, innkeepers, bankers, flight
-- masters, vendors and quest givers - listed by what they do, and every flight path your characters
-- know. A person's page (0.69.0, #42): the name plate carries their title and roles, where they stand
-- and a faction crest on the portrait (hover it for who met them first, and a merchant's standing and
-- visits); below it, what they teach you (Training: name, level, cost, the spell's own tooltip), what
-- they sell (For sale), their quests and their flight path. A flight path's page shows who knows it,
-- its flight master, and the flights timed from and to it.

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local page = { key = "townsfolk", title = L["People"], icon = "Interface\\AddOns\\AzerothAlmanac\\Media\\Tab_People", order = 8 }
local list, detail, countText, kindButton, portrait, nameText, titleText, placeText, mapButton, pinButton
local filter, kindFilter = "", nil
local shown -- { npc = id } or { node = name }
local collapsed = {}

local NOTE = "|cffbfbfbf"
local FLIGHT_ICON = { "Ability_Mount_Gryphon_01", "Ability_Mount_Wyvern_01", "INV_Misc_Map_01" }
local QUEST_ICON = { "INV_Misc_Note_01", "INV_Letter_15" }
local SIDE = { A = L["Alliance"], H = L["Horde"], AH = L["Alliance and Horde"] }

-- the kinds the filter offers: the Townsfolk groups' families, quest givers and flight paths
local KINDS = {
	{ key = nil, label = L["Everyone"] },
	{ key = "trainer", label = L["Trainers"] },
	{ key = "service", label = L["Services"] },
	{ key = "vendor", label = L["Vendors"] },
	{ key = "quest", label = L["Quest givers"] },
	{ key = "flight", label = L["Flight paths"] },
}

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

---------------------------------------------------------------------------
-- Everyone met: townsfolk, merchants, trainers and quest givers, by NPC
---------------------------------------------------------------------------

local QUEST_GROUP = { key = "quest", label = L["Quest givers"], icon = QUEST_ICON, family = "quest" }
local VENDOR_GROUP = { key = "vendor_other", label = L["Other vendors"], icon = "INV_Misc_Coin_03", family = "vendor" }
local TRAINER_GROUP = { key = "trainer_other", label = L["Other trainers"], icon = "INV_Misc_Book_09", family = "trainer" }

-- npc -> { npc, name, title, recs = { kind = rec }, group, map, x, y, zone, sub, display }
-- (rebuilt when the records change)
local cache
ns:On("CHANGED", function() cache = nil end)
ns:On("RESET", function() cache = nil end)
local function People()
	if cache then return cache end
	local TF = ns.Townsfolk
	local out = {}
	local function Add(kind, npc, rec)
		if type(npc) ~= "number" or type(rec) ~= "table" then return end
		local p = out[npc]
		if not p then
			p = { npc = npc, recs = {} }
			out[npc] = p
		end
		p.recs[kind] = rec
		p.name = p.name or rec.name
		p.title = p.title or rec.title
		p.display = p.display or rec.display
		p.zone = p.zone or rec.zone
		p.sub = p.sub or (rec.sub ~= "" and rec.sub or nil)
	end
	for npc, rec in pairs(ns.Store:Shown("townsfolk")) do Add("townsfolk", npc, rec) end
	for npc, rec in pairs(ns.Store:Shown("merchant")) do Add("merchant", npc, rec) end
	for npc, rec in pairs(ns.Store:Shown("trainer")) do Add("trainer", npc, rec) end
	for npc, rec in pairs(ns.Store:Shown("npc")) do
		if rec.gives or rec.takes or out[npc] then Add("npc", npc, rec) end
	end
	for npc, p in pairs(out) do
		p.group = TF and TF:PrimaryGroup(npc)
			or (p.recs.trainer and TRAINER_GROUP) or (p.recs.merchant and VENDOR_GROUP) or QUEST_GROUP
		-- where they stand: talked-to spot, else their spawn, else where a merchant / trainer / quest was recorded
		local map, x, y
		if TF and p.recs.townsfolk then map, x, y = TF:Locate(npc, p.recs.townsfolk) end
		if not x then
			for _, kind in ipairs({ "merchant", "trainer", "npc" }) do
				local r = p.recs[kind]
				if r and r.map and r.x then map, x, y = r.map, r.x, r.y break end
			end
		end
		p.map, p.x, p.y = map, x, y
		if not p.zone then
			local r = p.recs.townsfolk
			for m in pairs(r and r.z or {}) do p.zone = ZoneName(m) break end
			p.zone = p.zone or ZoneName(map)
		end
	end
	cache = out
	return out
end

local function Person(npc)
	return npc and People()[npc]
end

-- every timed flight's other end, and the points themselves
local function Node(name)
	return name and ns.Store:Get("flight", name)
end

---------------------------------------------------------------------------
-- Detail: a person
---------------------------------------------------------------------------

local function Who(recs)
	local first, firstT, seen = nil, nil, {}
	for _, r in pairs(recs) do
		if r.f and (not firstT or r.f < firstT) then first, firstT = r.b, r.f end
		for key in pairs(r.c or {}) do seen[key] = true end
	end
	local others = {}
	for key in pairs(seen) do if key ~= first then others[#others + 1] = ns.CharName(key) end end
	table.sort(others)
	return first, firstT, others
end

local function QuestSlot(qid)
	local q = ns.Store:Get("quest", qid)
	local st = ns.Quests and ns.Quests.MyStatus and ns.Quests:MyStatus(qid)
	local lvl = ns.Quests and ns.Quests.Level and ns.Quests:Level(qid, q)
	local icon = st == "d" and "Interface\\RaidFrame\\ReadyCheck-Ready" or "Interface\\GossipFrame\\AvailableQuestIcon"
	return { name = q and q.name or (L["quest %d"]):format(qid), icon = icon,
		note = lvl and (L["Level %d"]):format(lvl) or nil, tip = L["Click to open in Quests."], onClick = GoTo("quests", "ShowQuest", qid) }
end

-- (0.69.0) the name plate's title line: their title, then their other roles ("<Innkeeper>  ·  Food & drink");
-- a role the title already says ("Innkeepers" under <Innkeeper>) isn't repeated
local function TitleLine(p)
	local TF = ns.Townsfolk
	local parts = {}
	local tl = p.title and p.title:lower()
	if p.title then parts[1] = "<" .. p.title .. ">" end
	for _, g in ipairs(TF and TF:GroupsOf(p.npc) or {}) do
		local stem = (g.label or ""):lower():gsub("s$", "")
		if stem ~= "" and not (tl and (tl:find(stem, 1, true) or stem:find(tl, 1, true))) then parts[#parts + 1] = g.label end
	end
	if #parts == 0 then parts[1] = p.group.label end
	return table.concat(parts, "  ·  ")
end

-- the portrait's tooltip: who met them, which side they serve, and (merchants) standing and visits
local function PortraitTip(p)
	local lines = {}
	local first, firstT, others = Who(p.recs)
	if first then lines[#lines + 1] = { L["First met"], ns.CharName(first) .. ", " .. ns.DateText(firstT) } end
	if #others > 0 then lines[#lines + 1] = { L["Also met by"], table.concat(others, ", ") } end
	local e = ns.Townsfolk and ns.Townsfolk:Get(p.npc)
	if e and SIDE[e.faction] then lines[#lines + 1] = { L["Serves"], SIDE[e.faction] } end
	for _, ln in ipairs(ns.MerchantFacts and ns.MerchantFacts(p.npc) or {}) do lines[#lines + 1] = ln end
	return lines
end

-- a trainer's training, as the merchants' stock: name (and rank), the level (or skill) it needs and
-- what it costs from this trainer, coloured for the character you're playing; hover for the spell's
-- own tooltip, Shift-click to link it, click a recipe to open it in Recipes
local TRAIN_COLOR = { now = "|cff40c040", later = "|cffe03030", known = "|cff999999", other = "|cffffffff" }
local function SpellLink(id)
	if C_Spell and C_Spell.GetSpellLink then
		local ok, link = pcall(C_Spell.GetSpellLink, id)
		if ok and link then return link end
	end
	if GetSpellLink then
		local ok, link = pcall(GetSpellLink, id)
		if ok then return link end
	end
end

local function TrainingSlots(npc, t)
	local TR = ns.Trainers
	local me = ns.CharKey and ns.CharKey()
	local prof = TR and TR:IsProfession(t.group)
	local rows = {}
	for _, id in ipairs(t.teaches or {}) do
		local rec = ns.Store:Get("spell", id)
		if rec then rows[#rows + 1] = { id = id, rec = rec } end
	end
	table.sort(rows, function(a, c)
		local x, y = a.rec, c.rec
		-- (recipes by the skill they need, spells by level)
		if prof and (x.skill or 0) ~= (y.skill or 0) then return (x.skill or 0) < (y.skill or 0) end
		if (x.lvl or 0) ~= (y.lvl or 0) then return (x.lvl or 0) < (y.lvl or 0) end
		if (x.skill or 0) ~= (y.skill or 0) then return (x.skill or 0) < (y.skill or 0) end
		if (x.name or "") ~= (y.name or "") then return (x.name or "") < (y.name or "") end
		return (tonumber((x.rank or ""):match("%d+")) or 0) < (tonumber((y.rank or ""):match("%d+")) or 0)
	end)
	local slots = {}
	for _, r in ipairs(rows) do
		local id, rec = r.id, r.rec
		local st = (TR and me and TR:StatusFor(me, rec, id)) or "other"
		local cost = rec.trainers and rec.trainers[npc]
		if cost == nil then cost = rec.cost end
		local need = (prof and rec.skill and (L["Skill %d"]):format(rec.skill)) or (rec.lvl and (L["Level %d"]):format(rec.lvl)) or nil
		local price = cost and (cost > 0 and ns.MoneyText(cost) or L["free"]) or nil
		slots[#slots + 1] = {
			spell = id, icon = rec.icon, color = TRAIN_COLOR[st],
			name = (rec.name or "?") .. (rec.rank and ("  |cff999999" .. rec.rank .. "|r") or ""),
			note = (need and price) and (need .. "   " .. price) or need or price,
			extra = prof and L["Click to open in Recipes. Shift-click to link it."] or L["Shift-click to link it."],
			onClick = function()
				if IsShiftKeyDown and IsShiftKeyDown() then
					local link = SpellLink(id)
					if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
					return
				end
				if prof then
					local recipes = ns.UI:GetPage("trainers")
					if recipes and recipes.ShowSpell then recipes:ShowSpell(id) end
				end
			end,
		}
	end
	return slots
end

local function DescribePerson(p)
	local b = {}
	local m = p.recs.merchant
	local t = p.recs.trainer

	-- what they teach you (class spells, weapon skills, riding, recipes): only what they've shown you
	if t then
		local slots = TrainingSlots(p.npc, t)
		b[#b + 1] = { "banner", (L["Training (%d)"]):format(#slots) }
		if #slots > 0 then
			b[#b + 1] = { "slots", slots }
			b[#b + 1] = { "small", "|cff40c040" .. L["green"] .. "|r " .. L["can learn now"] .. "   |cffe03030" .. L["red"] .. "|r "
				.. L["not yet"] .. "   |cff999999" .. L["grey"] .. "|r " .. L["learned"] .. "  " .. L["(for the character you're playing)"] }
		else
			b[#b + 1] = { "small", L["Open their training window to record what they teach."] }
		end
	end

	-- what they sell, with your standing and visits on its heading (Merchants is part of People)
	if m and ns.MerchantBlocks then
		for _, block in ipairs(ns.MerchantBlocks(p.npc) or {}) do b[#b + 1] = block end
	end

	-- quests they give and take in
	local q = p.recs.npc
	for _, role in ipairs({ { "gives", L["Quests they give"] }, { "takes", L["Quests they take in"] } }) do
		local ids = {}
		for qid in pairs(q and q[role[1]] or {}) do ids[#ids + 1] = qid end
		if #ids > 0 then
			table.sort(ids, function(x, y)
				local a, c = ns.Store:Get("quest", x), ns.Store:Get("quest", y)
				return ((a and a.name) or "") < ((c and c.name) or "")
			end)
			local slots = {}
			for _, qid in ipairs(ids) do slots[#slots + 1] = QuestSlot(qid) end
			b[#b + 1] = { "banner", (role[2] .. " (%d)"):format(#ids) }
			b[#b + 1] = { "slots", slots }
		end
	end
	-- their flight point
	local node = p.recs.townsfolk and p.recs.townsfolk.node
	if not node then
		for name, rec in pairs(ns.Store:Shown("flight")) do if rec.master == p.npc then node = name break end end
	end
	if node then
		b[#b + 1] = { "banner", L["Flight path"] }
		b[#b + 1] = { "slots", { { name = node, icon = W.FindIcon(FLIGHT_ICON), note = L["Flight master here"],
			tip = L["Click to open this flight path."], onClick = function() page:ShowNode(node) end } } }
	end
	if #b == 0 then b[#b + 1] = { "small", L["Nothing more recorded for them yet: what they teach, sell or ask of you shows here once you've seen it."] } end
	if not p.x then b[#b + 1] = { "small", L["Talk to them to record exactly where they stand."] } end
	return b
end

---------------------------------------------------------------------------
-- Detail: a flight path
---------------------------------------------------------------------------

local function DescribeNode(name, rec)
	local b = {}
	local F = ns.Flights
	b[#b + 1] = { "banner", L["General"] }
	b[#b + 1] = { "stat", L["Zone"], rec.zone or ZoneName(rec.map) or "?" }
	if rec.x then b[#b + 1] = { "stat", L["Coordinates"], ("%.1f, %.1f"):format(rec.x, rec.y) .. (rec.exact and "" or (NOTE .. "  " .. L["(from the flight map)"] .. "|r")) } end
	local knowers = {}
	for key, t in pairs(rec.known or {}) do knowers[#knowers + 1] = { key = key, t = t } end
	table.sort(knowers, function(x, y) return x.t < y.t end)
	local names = {}
	for _, k in ipairs(knowers) do names[#names + 1] = ns.CharName(k.key) end
	if #names > 0 then b[#b + 1] = { "stat", L["Known by"], table.concat(names, ", ") } end
	b[#b + 1] = { "stat", L["First seen"], ns.CharName(rec.b) .. ", " .. ns.DateText(rec.f) }

	local master = rec.master and Person(rec.master)
	if master then
		b[#b + 1] = { "banner", L["Flight master"] }
		b[#b + 1] = { "slots", { { name = master.name or "?", icon = W.FindIcon(FLIGHT_ICON), note = master.title,
			tip = L["Click to open their page."], onClick = function() page:ShowPerson(rec.master) end } } }
	end

	local from, to = F:Routes(name)
	local function RouteSlots(routes)
		local slots = {}
		for _, r in ipairs(routes) do
			local other = Node(r.other)
			local note = F:TimeText(r.t) .. ((r.n or 1) > 1 and (NOTE .. "  " .. (L["(%d flights)"]):format(r.n) .. "|r") or "")
			if r.shared then note = note .. NOTE .. "  " .. L["(shared)"] .. "|r" end
			slots[#slots + 1] = { name = r.other, icon = W.FindIcon(FLIGHT_ICON), note = note,
				tip = other and L["Click to open this flight path."] or L["Not seen on a flight map yet."],
				onClick = other and function() page:ShowNode(r.other) end or nil }
		end
		return slots
	end
	if #from > 0 then
		b[#b + 1] = { "banner", (L["Flights from here (%d)"]):format(#from) }
		b[#b + 1] = { "slots", RouteSlots(from) }
	end
	if #to > 0 then
		b[#b + 1] = { "banner", (L["Flights to here (%d)"]):format(#to) }
		b[#b + 1] = { "slots", RouteSlots(to) }
	end
	if #from + #to == 0 then b[#b + 1] = { "small", L["Flight times are recorded as you fly."] } end
	return b
end

---------------------------------------------------------------------------
-- Showing a record
---------------------------------------------------------------------------

local function Located()
	if shown and shown.npc then
		local p = Person(shown.npc)
		if p and p.map and p.x then
			return p.map, p.x, p.y, p.name, p.title, p.display, W.FindIcon(p.group.icon or W.KIND.townsfolk.icon)
		end
	elseif shown and shown.node then
		local rec = Node(shown.node)
		if rec and rec.map and rec.x then return rec.map, rec.x, rec.y, rec.name, L["Flight path"], nil, W.FindIcon(FLIGHT_ICON) end
	end
end

local function Show(sel)
	shown = sel
	local p = sel and sel.npc and Person(sel.npc)
	local node = sel and sel.node and Node(sel.node)
	if not (p or node) then
		shown = nil
		portrait:Hide()
		nameText:SetText("")
		titleText:SetText("")
		placeText:SetText("")
		mapButton:Hide()
		pinButton:Hide()
		detail:SetBlocks(nil, L["Select someone you've met, or a flight path."])
		return
	end
	portrait:Show()
	if p then
		local fam = p.group.family
		local ring = fam == "trainer" and { 0.95, 0.78, 0.3 } or fam == "service" and { 0.45, 0.7, 1 } or fam == "vendor" and { 0.5, 0.88, 0.45 } or { 0.85, 0.75, 0.5 }
		portrait:SetRing(ring[1], ring[2], ring[3])
		local faced = false
		for kind, r in pairs(p.recs) do
			if ns.Bestiary:SetFace(portrait.art, p.npc, r, kind) then faced = true break end
		end
		if not faced then
			W.SetIcon(portrait.art, p.group.icon or W.KIND.townsfolk.icon)
			portrait.art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		end
		nameText:SetText(p.name or "?")
		titleText:SetText(TitleLine(p))
		placeText:SetText(NOTE .. (p.sub and (p.sub .. ", ") or "") .. (p.zone or "?") .. "|r")
		local e = ns.Townsfolk and ns.Townsfolk:Get(p.npc)
		local side = e and (e.faction == "A" and "Alliance" or e.faction == "H" and "Horde") or nil
		W.SetFactionBadge(portrait.crest, side)
		portrait.tip = { title = p.name, lines = PortraitTip(p) }
		detail:SetBlocks(DescribePerson(p))
	else
		portrait:SetRing(0.62, 0.5, 0.24)
		portrait.crest:Hide()
		portrait.tip = nil
		W.SetIcon(portrait.art, FLIGHT_ICON)
		portrait.art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		nameText:SetText((node.name or "?"):gsub(",.*$", ""))
		titleText:SetText(L["Flight path"])
		placeText:SetText(NOTE .. (node.zone or ZoneName(node.map) or "?") .. "|r")
		detail:SetBlocks(DescribeNode(sel.node, node))
	end
	local map = Located()
	mapButton:SetShown(map ~= nil)
	pinButton:SetShown(map ~= nil)
end

local function Waypoint()
	local map, x, y, name = Located()
	if map then W.Waypoint(map, x, y, name) end
end

---------------------------------------------------------------------------
-- List, filters
---------------------------------------------------------------------------

local function Matches(p)
	if kindFilter and kindFilter ~= p.group.family then return false end
	if filter == "" then return true end
	for _, v in ipairs({ p.name, p.title, p.zone, p.sub, p.group.label }) do
		if v and v:lower():find(filter, 1, true) then return true end
	end
	return false
end

-- (0.69.0, #38) a person as one record for "new": first met (by anyone, or by this character) in any role
local function PersonRec(p)
	local f, c = nil, {}
	for _, r in pairs(p.recs) do
		if r.f and (not f or r.f < f) then f = r.f end
		for key, t in pairs(r.c or {}) do if not c[key] or t < c[key] then c[key] = t end end
	end
	return { f = f, c = c }
end

local function Collect()
	local rows, n, total = {}, 0, 0
	local byGroup, groups = {}, {}
	local new = {}
	local order = {}
	for i, g in ipairs(ns.Townsfolk and ns.Townsfolk.groups or {}) do if g.key then order[g.key] = i end end
	order.quest = 1000
	if kindFilter ~= "flight" then
		for _, p in pairs(People()) do
			total = total + 1
			if Matches(p) and ns.New and ns.New:IsNew("townsfolk", PersonRec(p)) then
				new[#new + 1] = { npc = p.npc, p = p, isNew = true, newKey = "npc:" .. p.npc, newAt = ns.New:FoundAt(PersonRec(p)) or 0 }
			elseif Matches(p) then
				local g = p.group
				if not byGroup[g.key] then
					byGroup[g.key] = {}
					groups[#groups + 1] = g
				end
				table.insert(byGroup[g.key], p)
			end
		end
	end
	table.sort(groups, function(a, b) return (order[a.key] or 999) < (order[b.key] or 999) end)
	for _, g in ipairs(groups) do
		local people = byGroup[g.key]
		table.sort(people, function(a, b) return (a.name or "") < (b.name or "") end)
		rows[#rows + 1] = { header = g.label, key = g.key, count = #people }
		for _, p in ipairs(people) do
			n = n + 1
			if not collapsed[g.key] then rows[#rows + 1] = { npc = p.npc, p = p } end
		end
	end
	-- flight paths, by zone
	if kindFilter == nil or kindFilter == "flight" then
		local nodes = {}
		for name, rec in pairs(ns.Store:Shown("flight")) do
			total = total + 1
			local hay = (name .. " " .. (rec.zone or "")):lower()
			if filter == "" or hay:find(filter, 1, true) then
				if ns.New and ns.New:IsNew("townsfolk", rec) then
					new[#new + 1] = { node = name, rec = rec, isNew = true, newKey = "flight:" .. name, newAt = ns.New:FoundAt(rec) or 0 }
				else
					nodes[#nodes + 1] = { node = name, rec = rec }
				end
			end
		end
		if #nodes > 0 then
			table.sort(nodes, function(a, b) return a.node < b.node end)
			rows[#rows + 1] = { header = L["Flight paths"], key = "flight", count = #nodes }
			for _, e in ipairs(nodes) do
				n = n + 1
				if not collapsed.flight then rows[#rows + 1] = e end
			end
		end
	end
	-- the New group goes first
	if #new > 0 then
		table.sort(new, function(a, b) return a.newAt > b.newAt end)
		local head = { ns.New:Header(#new) }
		if not collapsed.new then for _, r in ipairs(new) do head[#head + 1] = r end end
		for _, r in ipairs(rows) do head[#head + 1] = r end
		rows = head
		n = n + #new
	end
	return rows, n, total
end

local function KindLabel()
	for _, k in ipairs(KINDS) do if k.key == kindFilter then return k.label end end
	return L["Everyone"]
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
	kindButton = W.Dropdown(header, KindLabel(), 130, function(self) KindMenu(self) end)
	kindButton:SetPoint("LEFT", search, "RIGHT", 12, 0)
	local hint = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("LEFT", kindButton, "RIGHT", 10, 0)
	hint:SetText(L["a name, title or place"])
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
		round = true,
		emptyText = L["No one yet. Trainers, innkeepers, bankers, flight masters, vendors and quest givers are recorded as you meet them."],
		update = function(row, r)
			row.icon:ClearAllPoints()
			row:SetHeader(r.header ~= nil, r.header and collapsed[r.key])
			if ns.New then ns.New:MarkRow(row, r.isNew, "townsfolk", r.newKey) end
			if r.header then
				row.icon:SetPoint("LEFT", 4, 0)
				row.icon:SetTexture(nil)
				row.text:SetFontObject(W.Font("GameFontNormalLarge", "GameFontNormal"))
				row.text:SetText(r.header)
				row.right:SetText(r.newHeader and "" or ("|cff999999" .. r.count .. "|r"))
			elseif r.npc then
				row.icon:SetPoint("LEFT", 22, 0)
				local faced = false
				for kind, rec in pairs(r.p.recs) do
					if ns.Bestiary:SetFace(row.icon, r.npc, rec, kind) then faced = true break end
				end
				if not faced then
					W.SetIcon(row.icon, r.p.group.icon or W.KIND.townsfolk.icon)
					row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				end
				row.text:SetFontObject(GameFontHighlight)
				row.text:SetText(r.p.name or "?")
				row.right:SetText("|cff999999" .. (r.p.zone or "") .. "|r")
			else
				row.icon:SetPoint("LEFT", 22, 0)
				W.SetIcon(row.icon, FLIGHT_ICON)
				row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				row.text:SetFontObject(GameFontHighlight)
				row.text:SetText((r.node:gsub(",.*$", "")))
				row.right:SetText("|cff999999" .. (r.rec.zone or "") .. "|r")
			end
		end,
		restore = function(r)
			if r.npc then Show({ npc = r.npc }) elseif r.node then Show({ node = r.node }) end
		end,
		onClick = function(r)
			if r.header then
				collapsed[r.key] = not collapsed[r.key]
				page:Refresh()
			elseif r.npc then
				if ns.New and ns.New:Clicked("townsfolk", r) then list:Refresh() end
				Show({ npc = r.npc })
			elseif r.node then
				if ns.New and ns.New:Clicked("townsfolk", r) then list:Refresh() end
				Show({ node = r.node })
			end
		end,
	})
	list:SetAllPoints(left)

	detail = W.Detail(parent, 64)
	detail:SetTheme({ "Tailoring", "Cooking" })
	detail:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
	detail:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
	portrait = W.Portrait(detail.top, 60)
	portrait:SetPoint("TOPLEFT", 0, 2)
	-- (0.69.0) the side they serve, as a crest on the ring; hover the portrait for who met them
	portrait.crest = portrait:CreateTexture(nil, "OVERLAY")
	portrait.crest:SetSize(24, 24)
	portrait.crest:SetPoint("CENTER", portrait, "BOTTOMRIGHT", -7, 7)
	portrait.crest:Hide()
	portrait:EnableMouse(true)
	portrait:SetScript("OnEnter", function(self)
		local tip = self.tip
		if not tip or #tip.lines == 0 then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(tip.title or "", 1, 0.82, 0)
		for _, ln in ipairs(tip.lines) do GameTooltip:AddDoubleLine(ln[1], ln[2], 1, 0.82, 0, 1, 1, 1) end
		GameTooltip:Show()
	end)
	portrait:SetScript("OnLeave", GameTooltip_Hide)
	nameText = detail.top:CreateFontString(nil, "OVERLAY")
	W.HeroFont(nameText, 26)
	nameText:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 10, -2)
	nameText:SetPoint("RIGHT", detail.top, "RIGHT", -150, 0)
	nameText:SetJustifyH("LEFT")
	nameText:SetWordWrap(false)
	titleText = detail.top:CreateFontString(nil, "OVERLAY")
	titleText:SetFontObject(GameFontHighlight)
	titleText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -4)
	titleText:SetPoint("RIGHT", detail.top, "RIGHT", -150, 0)
	titleText:SetJustifyH("LEFT")
	placeText = detail.top:CreateFontString(nil, "OVERLAY")
	placeText:SetFontObject(GameFontHighlightSmall)
	placeText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -3)
	placeText:SetPoint("RIGHT", detail.top, "RIGHT", -150, 0)
	placeText:SetJustifyH("LEFT")

	-- Show on map: their zone in Places with their face on its map; else the waypoint
	mapButton = W.Button(detail.top, L["Show on map"], 130, function()
		local map, x, y, name, sub, face, icon = Located()
		local places = ns.UI:GetPage("places")
		if map and places and places.ShowZone then
			local back = shown
			local pin = { x = x, y = y, name = name, sub = sub, face = face, icon = icon,
				onClick = function() if back.npc then page:ShowPerson(back.npc) else page:ShowNode(back.node) end end }
			if not places:ShowZone(map, nil, nil, pin) then Waypoint() end
		end
	end)
	mapButton:SetPoint("TOPRIGHT", detail.top, "TOPRIGHT", -16, 0)
	mapButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(L["Show on map"], 1, 0.82, 0)
		GameTooltip:AddLine(L["Opens the zone in Places with this marked on its map."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	mapButton:SetScript("OnLeave", GameTooltip_Hide)
	pinButton = W.Button(detail.top, W.PinMarkup(18) .. " " .. L["Set waypoint"], 130, Waypoint)
	pinButton:SetPoint("TOPRIGHT", mapButton, "BOTTOMRIGHT", 0, -6)
	pinButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(L["Set waypoint"], 1, 0.82, 0)
		GameTooltip:AddLine(L["Sets the game's map pin and arrow here."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	pinButton:SetScript("OnLeave", GameTooltip_Hide)
	Show(nil)
end

function page:Refresh()
	if not list then return end
	local rows, n, total = Collect()
	local keep
	for _, r in ipairs(rows) do
		if shown and ((shown.npc and r.npc == shown.npc) or (shown.node and r.node == shown.node)) then keep = r end
	end
	list:SetData(rows)
	list:Select(keep)
	countText:SetText((L["%d of %d"]):format(n, total))
	if shown then Show(shown) end
end

function page:ShowPerson(npc)
	ns.UI:Open("townsfolk")
	shown = { npc = npc }
	if kindFilter and Person(npc) and Person(npc).group.family ~= kindFilter then
		kindFilter = nil
		kindButton:SetText(KindLabel())
	end
	self:Refresh()
end

function page:ShowNode(name)
	ns.UI:Open("townsfolk")
	shown = { node = name }
	if kindFilter and kindFilter ~= "flight" then
		kindFilter = nil
		kindButton:SetText(KindLabel())
	end
	collapsed.flight = nil
	self:Refresh()
end

-- (the old Merchants page's way in: a merchant opens on their People page)
function page:ShowMerchant(npc) self:ShowPerson(npc) end

ns:On("RESET", function() shown = nil if list then list:Select(nil) Show(nil) end end)

ns.UI:RegisterPage(page)
