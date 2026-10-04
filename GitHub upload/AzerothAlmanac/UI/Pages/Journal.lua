-- Journal page: the adventurer's journal. Left: the timeline of everything discovered, newest
-- first, by day, across all characters (search; filters by character, kind and zone). Right: the
-- overview (what each catalogue holds, research, milestones, recent finds, who found what first),
-- for the account or one character, or the selected entry on parchment.

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local page = { key = "journal", title = L["Journal"], icon = "INV_Misc_Book_09", order = 1 }
local list, detail, search, countText, charButton, kindButton, zoneButton
local filter = ""
local charFilter, kindFilter, zoneFilter -- nil = all
local collapsed = {}
local viewing = "overview" -- "overview" | "milestones" | "entry"

-- opens another page on something: GoTo("items", "ShowItem", id)
local function GoTo(pageKey, method, ...)
	local args = { ... }
	return function()
		-- open the page first (a page's own Show* opens it too; "Refresh" only needs the opening)
		ns.UI:Open(pageKey)
		local p = ns.UI:GetPage(pageKey)
		if p and method ~= "Refresh" and p[method] then p[method](p, unpack(args)) end
	end
end

local function MapName(map)
	local z = ns.Store:Get("zone", map)
	if z and z.name then return z.name, true end
	if C_Map and C_Map.GetMapInfo then
		local ok, info = pcall(C_Map.GetMapInfo, map)
		if ok and type(info) == "table" and info.name then return info.name, false end
	end
	return (L["map %d"]):format(map), false
end

-- the entry's subject as a slot: its icon (the item's own, with its tooltip), a note, and a click
-- that opens it on its page
local function Subject(e, rec)
	local k, id = e.k, e.i
	local open = L["Click to open it."]
	if k == "item" then
		return { item = id, note = L["Item"], extra = L["Click to open in Items."], onClick = GoTo("items", "ShowItem", id) }
	elseif k == "creature" then
		local B = ns.Bestiary
		local tier = rec and B and B:Tier(rec)
		return { name = rec and rec.name or e.s, icon = W.FindIcon(W.TYPE_ICON[rec and rec.type or ""] or W.KIND.creature.icon),
			note = tier and (B:TierMarkup(tier, 12) .. " " .. B.TIERS[tier]) or L["Creature"],
			tip = L["Click to open in the Bestiary."], onClick = GoTo("bestiary", "ShowCreature", id) }
	elseif k == "merchant" then
		return { name = rec and rec.name or e.s, icon = W.KindIcon("merchant"), note = rec and rec.title or L["Merchant"],
			tip = L["Click to open in Merchants."], onClick = GoTo("merchants", "ShowMerchant", id) }
	elseif k == "quest" then
		return { name = rec and rec.name or e.s, icon = W.KindIcon("quest"), note = L["Quest"],
			tip = L["Click to open in Quests."], onClick = GoTo("quests", "ShowQuest", id) }
	elseif k == "zone" then
		return { name = rec and rec.name or e.s, icon = W.KindIcon("zone"), note = rec and rec.continent or L["Zone"],
			tip = L["Click to open in Places."], onClick = GoTo("places", "ShowZone", id) }
	elseif k == "subzone" then
		local map = rec and rec.map or tonumber(tostring(id):match("^(%d+):"))
		return { name = rec and rec.name or e.s, icon = W.KindIcon("subzone"), note = map and (MapName(map)) or L["Place"],
			tip = L["Click to open its zone in Places."], onClick = map and GoTo("places", "ShowZone", map) or nil }
	elseif k == "instance" then
		return { name = rec and rec.name or e.s, icon = W.KindIcon("instance"), note = rec and rec.type == "raid" and L["Raid"] or L["Dungeon"],
			tip = L["Click to open in Dungeons."], onClick = GoTo("dungeons", "ShowDungeon", id) }
	elseif k == "trainer" then
		return { name = rec and rec.name or e.s, icon = W.KindIcon("trainer"), note = rec and rec.title or L["Trainer"],
			tip = L["Click to open in Trainers."], onClick = rec and rec.group and GoTo("trainers", "ShowGroup", rec.group) or GoTo("trainers", "Refresh") }
	elseif k == "spell" then
		return { spell = id, note = L["Spell or recipe"], extra = L["Click to open in Trainers."], onClick = GoTo("trainers", "ShowSpell", id) }
	elseif k == "townsfolk" or k == "npc" then
		return { name = rec and rec.name or e.s, icon = W.KindIcon(k), note = rec and rec.title or W.KIND[k].label,
			tip = L["Click to open in Townsfolk."], onClick = GoTo("townsfolk", "ShowPerson", id) }
	elseif k == "flight" then
		return { name = rec and rec.name or e.s, icon = W.KindIcon("flight"), note = L["Flight path"],
			tip = L["Click to open in Townsfolk."], onClick = GoTo("townsfolk", "ShowNode", id) }
	elseif k == "milestone" then
		local def = ns.Milestones and ns.Milestones.byId[id]
		return { name = def and def.title or e.s, icon = W.FindIcon(def and def.icon or W.KIND.milestone.icon), note = L["Milestone"],
			tip = def and def.text or nil, onClick = function() page:ShowMilestones() end }
	elseif k == "node" then
		return { name = rec and rec.name or e.s, icon = W.KindIcon("node"), note = L["Gathering"],
			tip = L["Click to open in Gathering."], onClick = GoTo("gathering", "ShowNode", id) }
	elseif k == "fishing" then
		return { name = rec and (rec.zone or rec.name) or e.s, icon = W.KindIcon("fishing"), note = L["Fishing"],
			tip = L["Click to open in Gathering."], onClick = GoTo("gathering", "ShowFishing", id) }
	elseif k == "character" then
		return { name = ns.CharName(id, true), icon = W.KindIcon("character"), note = L["Character"],
			tip = L["Click to open in Characters."], onClick = function() ns.UI:Open("characters") end }
	end
end

local NOTE = "|cffbfbfbf"

local function Describe(e)
	local blocks = {}
	local kind = W.KIND[e.k]
	blocks[#blocks + 1] = { "title", e.s or "?" }
	blocks[#blocks + 1] = { "small", (kind and kind.label or e.k or "?") }
	blocks[#blocks + 1] = { "gap", 6 }
	blocks[#blocks + 1] = { "body", (L["%s, %s"]):format(ns.CharName(e.c, true), ns.DateTimeText(e.t)) }
	local rec = ns.Store:Get(e.k, e.i)
	-- what it was, and where: each a slot with its tooltip, a click opens it on its own page
	local slots = {}
	local subject = Subject(e, rec)
	if subject then slots[#slots + 1] = subject end
	if e.m then
		local name, known = MapName(e.m)
		slots[#slots + 1] = { name = name, icon = W.KindIcon("zone"),
			note = e.x and (L["at %.1f, %.1f"]):format(e.x, e.y) or L["Where"],
			tip = (known and L["Click to open in Places."] or "") .. (e.x and ("\n" .. L["Shift-click: set a waypoint there."]) or ""),
			onClick = function()
				if IsShiftKeyDown() and e.x then W.Waypoint(e.m, e.x, e.y, e.s) return end
				if known then GoTo("places", "ShowZone", e.m)() elseif e.x then W.Waypoint(e.m, e.x, e.y, e.s) end
			end }
	end
	if #slots > 0 then
		blocks[#blocks + 1] = { "gap", 4 }
		blocks[#blocks + 1] = { "slots", slots }
	end
	if rec then
		blocks[#blocks + 1] = { "gap", 10 }
		blocks[#blocks + 1] = { "banner", L["Record"] }
		blocks[#blocks + 1] = { "body", (L["First discovered by %s on %s."]):format(ns.CharName(rec.b, true), ns.DateText(rec.f)) }
		blocks[#blocks + 1] = { "body", (L["Seen %s, last %s."]):format(ns.Times(rec.n or 1), ns.AgoText(rec.l)) }
		local who = {}
		for key in pairs(rec.c or {}) do if key ~= rec.b then who[#who + 1] = ns.CharName(key, true) end end
		table.sort(who)
		if #who > 0 then blocks[#blocks + 1] = { "body", L["Also found by: "] .. table.concat(who, ", ") } end
	end
	return blocks
end

local function DayKey(t) return date("%Y-%m-%d", t) end
local function DayLabel(t)
	local today = DayKey(time())
	local d = DayKey(t)
	if d == today then return L["Today"] end
	if d == DayKey(time() - 86400) then return L["Yesterday"] end
	return date("%A, %b %d, %Y", t)
end

local function Collect()
	local out = {}
	local j = ns.db.journal
	local n, day, h = 0, nil, nil
	for i = #j, 1, -1 do
		local e = j[i]
		if (not charFilter or e.c == charFilter) and (not kindFilter or e.k == kindFilter) and (not zoneFilter or e.m == zoneFilter)
			and (filter == "" or (e.s and e.s:lower():find(filter, 1, true))) then
			local d = DayKey(e.t or 0)
			if d ~= day then
				day = d
				h = { header = DayLabel(e.t or 0), day = d, count = 0 }
				out[#out + 1] = h
			end
			h.count = h.count + 1
			n = n + 1
			if not collapsed[d] then out[#out + 1] = e end
		end
	end
	return out, n
end

---------------------------------------------------------------------------
-- Filters
---------------------------------------------------------------------------

local KINDS = { "zone", "subzone", "instance", "creature", "item", "quest", "merchant", "trainer", "spell", "townsfolk",
	"npc", "flight", "node", "fishing", "milestone", "level", "character" }

local function CharLabel() return charFilter and ns.CharName(charFilter) or L["All characters"] end
local function KindLabel() return kindFilter and (W.KIND[kindFilter] and W.KIND[kindFilter].label or kindFilter) or L["Everything"] end
local function ZoneLabel() return zoneFilter and (MapName(zoneFilter)) or L["All zones"] end

local function Menu(anchor, title, current, choices, set)
	local items = { { title = true, text = title } }
	for _, c in ipairs(choices) do
		items[#items + 1] = { text = c.text, icon = c.icon, selected = c.value == current, run = function() set(c.value) end }
	end
	W.Menu(anchor, items)
end

local function CharMenu(anchor)
	local choices = { { text = L["All characters"] } }
	local keys = {}
	for key in pairs(ns.db.chars) do keys[#keys + 1] = key end
	table.sort(keys)
	for _, key in ipairs(keys) do choices[#choices + 1] = { text = ns.CharName(key), value = key } end
	Menu(anchor, L["Character"], charFilter, choices, function(v) page:SetCharacter(v) end)
end

local function KindMenu(anchor)
	local present = {}
	for _, e in ipairs(ns.db.journal) do present[e.k] = true end
	local choices = { { text = L["Everything"] } }
	for _, k in ipairs(KINDS) do
		if present[k] and W.KIND[k] then choices[#choices + 1] = { text = W.KIND[k].label, value = k, icon = W.KindIcon(k) } end
	end
	Menu(anchor, L["Kind"], kindFilter, choices, function(v)
		kindFilter = v
		kindButton:SetText(KindLabel())
		page:Refresh()
	end)
end

local function ZoneMenu(anchor)
	local maps, names = {}, {}
	for _, e in ipairs(ns.db.journal) do
		if e.m and not maps[e.m] then
			local name, known = MapName(e.m)
			if known then maps[e.m] = true names[#names + 1] = { map = e.m, name = name } end
		end
	end
	table.sort(names, function(a, b) return a.name < b.name end)
	local choices = { { text = L["All zones"] } }
	for _, z in ipairs(names) do choices[#choices + 1] = { text = z.name, value = z.map } end
	Menu(anchor, L["Zone"], zoneFilter, choices, function(v)
		zoneFilter = v
		zoneButton:SetText(ZoneLabel())
		page:Refresh()
	end)
end

---------------------------------------------------------------------------
-- The overview
---------------------------------------------------------------------------

local CATALOGUES = {
	{ "zone", L["Zones"], "places" }, { "subzone", L["Places"], "places" }, { "instance", L["Dungeons and raids"], "dungeons" },
	{ "creature", L["Creatures"], "bestiary" }, { "item", L["Items"], "items" }, { "quest", L["Quests"], "quests" },
	{ "merchant", L["Merchants"], "merchants" }, { "trainer", L["Trainers"], "trainers" }, { "townsfolk", L["Townsfolk"], "townsfolk" },
	{ "flight", L["Flight paths"], "townsfolk" }, { "node", L["Gathering nodes"], "gathering" }, { "fishing", L["Fishing waters"], "gathering" },
}

local function Overview()
	local b = {}
	local char = charFilter
	b[#b + 1] = { "title", char and (L["%s's journal"]):format(ns.CharName(char, true)) or L["The Adventurer's Journal"] }
	b[#b + 1] = { "small", char and L["What this character has discovered. Pick All characters for the whole account."]
		or L["Everything your characters have discovered, together."] }

	-- each catalogue: how much it holds, and what's new this session
	local slots = {}
	for _, c in ipairs(CATALOGUES) do
		local n, new = 0, 0
		for _, rec in pairs(ns.Store:All(c[1])) do
			local at = char and (rec.c and rec.c[char]) or (not char and rec.f)
			if at then
				n = n + 1
				if at >= ns.sessionStart then new = new + 1 end
			end
		end
		if n > 0 then
			slots[#slots + 1] = { name = c[2], icon = W.KindIcon(c[1]), count = nil,
				note = tostring(n) .. (new > 0 and ("  |cff1eff00+" .. new .. " " .. L["this session"] .. "|r") or ""),
				tip = L["Click to open it."], onClick = GoTo(c[3], "Refresh") }
		end
	end
	b[#b + 1] = { "banner", L["Discoveries"] }
	if #slots > 0 then b[#b + 1] = { "slots", slots } else b[#b + 1] = { "small", L["Nothing discovered yet. Go explore!"] } end

	-- research
	local M = ns.Milestones
	local s = M and M:Stats(char) or {}
	local B = ns.Bestiary
	local research = {}
	if B and (s.studied or 0) > 0 then
		research[#research + 1] = { name = L["Creatures studied"], icon = B:TierIcon(3), note = tostring(s.studied - (s.mastered or 0)), onClick = GoTo("bestiary", "Refresh") }
	end
	if B and (s.mastered or 0) > 0 then
		research[#research + 1] = { name = L["Creatures mastered"], icon = B:TierIcon(4), note = tostring(s.mastered), onClick = GoTo("bestiary", "Refresh") }
	end
	if (s.kills or 0) > 0 then research[#research + 1] = { name = L["Creatures defeated"], icon = W.FindIcon({ "Ability_DualWield", "INV_Sword_04" }), note = tostring(s.kills) } end
	if (s.quest or 0) > 0 then research[#research + 1] = { name = L["Quests completed"], icon = W.KindIcon("quest"), note = tostring(s.quest), onClick = GoTo("quests", "Refresh") } end
	if not char then
		for _, g in ipairs({ { "herb", L["Herbs gathered"] }, { "ore", L["Veins mined"] }, { "fish", L["Fish caught"] }, { "skin", L["Creatures skinned"] } }) do
			if (s[g[1]] or 0) > 0 then
				research[#research + 1] = { name = g[2], icon = W.FindIcon(ns.Gathering.KIND[g[1]] and ns.Gathering.KIND[g[1]].icon or { "INV_Misc_Pelt_Wolf_01" }),
					note = tostring(s[g[1]]), onClick = GoTo("gathering", "Refresh") }
			end
		end
	end
	if #research > 0 then
		b[#b + 1] = { "banner", L["Research"] }
		b[#b + 1] = { "slots", research }
	end

	-- milestones: the latest few
	local earned = M and M:EarnedList(char) or {}
	b[#b + 1] = { "banner", (L["Milestones (%d)"]):format(#earned) }
	if #earned > 0 then
		local ms = {}
		for i = 1, math.min(6, #earned) do
			local e = earned[i]
			ms[#ms + 1] = { name = e.def.title, icon = W.FindIcon(e.def.icon), tip = e.def.text,
				note = e.quiet and ns.CharName(e.c) or (ns.CharName(e.c) .. NOTE .. "  " .. ns.DateText(e.t) .. "|r"),
				onClick = function() page:ShowMilestones() end }
		end
		ms[#ms + 1] = { name = L["Every milestone"], icon = W.FindIcon(W.KIND.milestone.icon), note = L["Click to see them all."],
			onClick = function() page:ShowMilestones() end }
		b[#b + 1] = { "slots", ms }
	else
		b[#b + 1] = { "small", L["Milestones come from your own discoveries: your first elite, a hundred creatures, ten mastered..."] }
	end

	-- recent discoveries
	local recent = {}
	local j = ns.db.journal
	for i = #j, 1, -1 do
		local e = j[i]
		if not char or e.c == char then
			local slot = Subject(e, ns.Store:Get(e.k, e.i))
			if slot then recent[#recent + 1] = slot end
			if #recent >= 6 then break end
		end
	end
	if #recent > 0 then
		b[#b + 1] = { "banner", L["Recent discoveries"] }
		b[#b + 1] = { "slots", recent }
	end

	-- account view: who found things first
	if not char then
		local firsts = {}
		for _, c in ipairs(CATALOGUES) do
			for _, rec in pairs(ns.Store:All(c[1])) do
				if rec.b then firsts[rec.b] = (firsts[rec.b] or 0) + 1 end
			end
		end
		local who = {}
		for key, n in pairs(firsts) do
			if ns.db.chars[key] then
				who[#who + 1] = { name = ns.CharName(key), icon = W.KindIcon("character"), n = n,
					note = (L["first to find %d"]):format(n), tip = L["Click to see this character's journal."],
					onClick = function() page:SetCharacter(key) end }
			end
		end
		table.sort(who, function(x, y) return x.n > y.n end)
		if #who > 1 then
			b[#b + 1] = { "banner", L["First to find"] }
			b[#b + 1] = { "slots", who }
		end
	end
	return b
end

local function Milestones()
	local b = {}
	local M = ns.Milestones
	local earned = M and M:EarnedList(charFilter) or {}
	b[#b + 1] = { "title", L["Milestones"] }
	b[#b + 1] = { "small", charFilter and (L["Reached by %s."]):format(ns.CharName(charFilter, true))
		or L["Reached by your characters, from their own discoveries."] }
	b[#b + 1] = { "gap", 6 }
	if #earned == 0 then
		b[#b + 1] = { "body", L["None yet."] }
		return b
	end
	local slots = {}
	for _, e in ipairs(earned) do
		slots[#slots + 1] = { name = e.def.title, icon = W.FindIcon(e.def.icon), tip = e.def.text,
			note = e.quiet and (ns.CharName(e.c) .. NOTE .. "  " .. L["(before milestones)"] .. "|r") or (ns.CharName(e.c) .. NOTE .. "  " .. ns.DateText(e.t) .. "|r") }
	end
	b[#b + 1] = { "slots", slots }
	return b
end

local function ShowView()
	if viewing == "milestones" then detail:SetBlocks(Milestones())
	elseif viewing == "overview" then detail:SetBlocks(Overview()) end
end

function page:Build(parent, header)
	search = W.Search(header, 130, function(text)
		filter = text
		page:Refresh()
	end)
	search:SetPoint("LEFT", header, "LEFT", 16, -2)
	charButton = W.Dropdown(header, CharLabel(), 118, function(self) CharMenu(self) end)
	charButton:SetPoint("LEFT", search, "RIGHT", 10, 0)
	kindButton = W.Dropdown(header, KindLabel(), 108, function(self) KindMenu(self) end)
	kindButton:SetPoint("LEFT", charButton, "RIGHT", 6, 0)
	zoneButton = W.Dropdown(header, ZoneLabel(), 118, function(self) ZoneMenu(self) end)
	zoneButton:SetPoint("LEFT", kindButton, "RIGHT", 6, 0)
	countText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countText:SetPoint("RIGHT", header, "RIGHT", -12, -2)
	local home = W.Button(header, L["Overview"], 96, function() page:ShowOverview() end)
	home:SetPoint("RIGHT", countText, "LEFT", -10, 0)

	local left = W.Inset(parent)
	left:SetPoint("TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", 0, 0)
	left:SetWidth(400)
	list = W.List(left, {
		collapse = { state = collapsed, key = function(r) return r.header and r.day end, refresh = function() page:Refresh() end },
		rowHeight = 26,
		emptyText = L["Nothing discovered yet. Go explore!"],
		update = function(row, e)
			row:SetHeader(e.header ~= nil, e.header and collapsed[e.day])
			if e.header then
				row.icon:SetTexture(nil)
				row.text:SetFontObject(W.Font("GameFontNormal", "GameFontNormalSmall"))
				row.text:SetText(e.header)
				row.right:SetText("|cff999999" .. e.count .. "|r")
				return
			end
			row.text:SetFontObject(GameFontHighlight)
			local icon
			if e.k == "item" then
				local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
				icon = instant and select(5, instant(e.i))
			elseif e.k == "milestone" then
				local def = ns.Milestones and ns.Milestones.byId[e.i]
				icon = def and W.FindIcon(def.icon)
			end
			row.icon:SetTexture(icon or W.KindIcon(e.k))
			row.text:SetText(e.s or "?")
			row.right:SetText(ns.CharName(e.c) .. "  |cff999999" .. date("%H:%M", e.t or 0) .. "|r")
		end,
		restore = function(e) if not e.header then viewing = "entry" detail:SetBlocks(Describe(e)) end end,
		onClick = function(e)
			if e.header then
				collapsed[e.day] = not collapsed[e.day]
				page:Refresh()
				return
			end
			viewing = "entry"
			detail:SetBlocks(Describe(e))
		end,
	})
	list:SetAllPoints(left)

	-- the profession book's own painted background, darkened, under the overview and entries
	detail = W.Detail(parent, nil, "painted")
	detail:SetPainting({ "Profession-background-card-Blacksmithing", "Profession-background-card-Mining",
		"Profession-background-card-Cooking", "Profession-background-card-Fishing", "Profession-background-card-FirstAid" }, 1)
	detail:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
	detail:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
	ShowView()
end

function page:Refresh()
	if not list then return end
	local data, n = Collect()
	list:SetData(data)
	countText:SetText((L["%d entries"]):format(n))
	local sel = list:Selected()
	if viewing == "entry" and sel and not sel.header then detail:SetBlocks(Describe(sel)) else
		if viewing == "entry" then viewing = "overview" end
		ShowView()
	end
end

function page:ShowOverview()
	ns.UI:Open("journal")
	viewing = "overview"
	if list then list:Select(nil) end
	self:Refresh()
end

function page:ShowMilestones()
	ns.UI:Open("journal")
	viewing = "milestones"
	if list then list:Select(nil) end
	self:Refresh()
end

-- the journal of one character (nil = the whole account)
function page:SetCharacter(key)
	charFilter = key
	if charButton then charButton:SetText(CharLabel()) end
	if viewing == "entry" then viewing = "overview" end
	if list then list:Select(nil) end
	self:Refresh()
end

ns:On("RESET", function()
	if list then list:Select(nil) viewing = "overview" ShowView() end
end)

ns.UI:RegisterPage(page)
