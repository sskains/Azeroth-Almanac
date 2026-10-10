-- Journal page: the adventurer's journal (0.69.1 layout). Left: the overview on the painted book page:
-- a card for each kind of discovery (two to a row, the painted art, how many, +n this session), then
-- research, milestones and who found what first. Picking a card shows its entries in the list; picking
-- it again (or All discoveries) shows everything. Top right: the Journey (UI/Journey.lua). Bottom right:
-- the entries, newest first, by day (search; filters by character and zone). Hover an entry: its journal
-- entry in a tooltip, and its spot lit on the Journey; click: open it on its own page.

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local page = { key = "journal", title = L["Journal"], icon = ns.JOURNAL_ICON, order = 1 }
local list, detail, search, countText, charButton, zoneButton, journey
local large = false -- the Journey filling the right side (its Larger button)
local filter = ""
local charFilter, kindFilter, zoneFilter -- nil = all
local collapsed = {}
local LEFT_W = 330 -- the overview's width (its cards two to a row)
-- the classes with a painted crest (Media\Crest_<CLASS>), for First to find
local CREST_CLASSES = { DRUID = true, HUNTER = true, MAGE = true, PALADIN = true, PRIEST = true,
	ROGUE = true, SHAMAN = true, WARLOCK = true, WARRIOR = true }
local FACTION_BY_RACE = { Human = "Alliance", Dwarf = "Alliance", NightElf = "Alliance", Gnome = "Alliance",
	Orc = "Horde", Scourge = "Horde", Tauren = "Horde", Troll = "Horde" }

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
			tip = L["Click to open in Creatures."], onClick = GoTo("bestiary", "ShowCreature", id) }
	elseif k == "merchant" then
		return { name = rec and rec.name or e.s, icon = W.KindArt("merchant"), note = rec and rec.title or L["Merchant"],
			tip = L["Click to open in People."], onClick = GoTo("merchants", "ShowMerchant", id) }
	elseif k == "quest" then
		return { name = rec and rec.name or e.s, icon = W.KindArt("quest"), note = L["Quest"],
			tip = L["Click to open in Quests."], onClick = GoTo("quests", "ShowQuest", id) }
	elseif k == "zone" then
		return { name = rec and rec.name or e.s, icon = W.KindArt("zone"), note = rec and rec.continent or L["Zone"],
			tip = L["Click to open in Places."], onClick = GoTo("places", "ShowZone", id) }
	elseif k == "subzone" then
		local map = rec and rec.map or tonumber(tostring(id):match("^(%d+):"))
		return { name = rec and rec.name or e.s, icon = W.KindArt("subzone"), note = map and (MapName(map)) or L["Place"],
			tip = L["Click to open its zone in Places."], onClick = map and GoTo("places", "ShowZone", map) or nil }
	elseif k == "instance" then
		return { name = rec and rec.name or e.s, icon = W.KindArt("instance"), note = rec and rec.type == "raid" and L["Raid"] or L["Dungeon"],
			tip = L["Click to open in Dungeons."], onClick = GoTo("dungeons", "ShowDungeon", id) }
	elseif k == "trainer" then
		return { name = rec and rec.name or e.s, icon = W.KindArt("trainer"), note = rec and rec.title or L["Trainer"],
			tip = L["Click to open in People."], onClick = GoTo("townsfolk", "ShowPerson", id) }
	elseif k == "spell" then
		return { spell = id, note = L["Spell or recipe"], extra = L["Click to open it: a recipe in Recipes, a class spell on its trainer's page in People."], onClick = GoTo("trainers", "ShowSpell", id) }
	elseif k == "townsfolk" or k == "npc" then
		return { name = rec and rec.name or e.s, icon = W.KindArt(k), note = rec and rec.title or W.KIND[k].label,
			tip = L["Click to open in People."], onClick = GoTo("townsfolk", "ShowPerson", id) }
	elseif k == "flight" then
		return { name = rec and rec.name or e.s, icon = W.KindArt("flight"), note = L["Flight path"],
			tip = L["Click to open in People."], onClick = GoTo("townsfolk", "ShowNode", id) }
	elseif k == "milestone" then
		local def = ns.Milestones and ns.Milestones.byId[id]
		return { name = def and def.title or e.s, icon = W.FindIcon(def and def.icon or W.KIND.milestone.icon), note = L["Milestone"],
			tip = def and def.text or nil, onClick = function() page:ShowMilestones() end }
	elseif k == "node" then
		-- (0.69.1) the node's own item (a Peacebloom entry shows Peacebloom); the painting when it has none
		local own = ns.Gathering and ns.Gathering.NodeIcon and ns.Gathering:NodeIcon(rec)
		return { name = rec and rec.name or e.s, icon = own or W.KindArt("node"), note = L["Gathering"],
			tip = L["Click to open in Gathering."], onClick = GoTo("gathering", "ShowNode", id) }
	elseif k == "fishing" then
		return { name = rec and (rec.zone or rec.name) or e.s, icon = W.KindArt("fishing"), note = L["Fishing"],
			tip = L["Click to open in Gathering."], onClick = GoTo("gathering", "ShowFishing", id) }
	elseif k == "character" then
		return { name = ns.CharName(id, true), icon = W.KindArt("character"), note = L["Character"],
			tip = L["Click to open in Characters."], onClick = function() ns.UI:Open("characters") end }
	end
end

local NOTE = "|cffbfbfbf"

-- (0.69.1) an entry's journal record as tooltip lines (the list's hover): what it is, who found it and
-- when, where, and the record's history
local function EntryTooltip(e)
	local rec = ns.Store:Get(e.k, e.i)
	local kind = W.KIND[e.k]
	local sub = Subject(e, rec)
	GameTooltip:SetOwner(list or UIParent, "ANCHOR_CURSOR_RIGHT", 16, 0)
	if e.k == "item" and GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(e.i)
		GameTooltip:AddLine(" ")
	else
		GameTooltip:SetText(e.s or "?", 1, 0.82, 0, 1, true)
		GameTooltip:AddLine(kind and kind.label or e.k or "?", 0.7, 0.7, 0.7)
	end
	GameTooltip:AddLine((L["%s, %s"]):format(ns.CharName(e.c, true), ns.DateTimeText(e.t)), 1, 1, 1)
	if e.m then
		local name = MapName(e.m)
		GameTooltip:AddLine(name .. (e.x and ("  |cff999999" .. (L["at %.1f, %.1f"]):format(e.x, e.y) .. "|r") or ""), 0.85, 0.85, 0.85)
	end
	if e.k == "milestone" and sub and sub.tip then GameTooltip:AddLine(sub.tip, 0.9, 0.9, 0.9, true) end
	if rec and rec.f then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine((L["First discovered by %s on %s."]):format(ns.CharName(rec.b, true), ns.DateText(rec.f)), 0.8, 0.8, 0.8, true)
		GameTooltip:AddLine((L["Seen %s, last %s."]):format(ns.Times(rec.n or 1), ns.AgoText(rec.l)), 0.8, 0.8, 0.8, true)
		local who = {}
		for key in pairs(rec.c or {}) do if key ~= rec.b then who[#who + 1] = ns.CharName(key, true) end end
		table.sort(who)
		if #who > 0 then GameTooltip:AddLine(L["Also found by: "] .. table.concat(who, ", "), 0.8, 0.8, 0.8, true) end
	end
	local hint = sub and (sub.tip or sub.extra)
	if e.k == "level" then hint = L["Click to open in Characters."] end
	if hint and e.k ~= "milestone" then GameTooltip:AddLine(hint, 0.6, 0.8, 1, true) end
	GameTooltip:Show()
end

-- an entry clicked (in the list or on the Journey): open it on its own page
local function OpenEntry(e)
	if not e or e.header then return end
	if e.k == "item" and W.ItemModifiedClick(e.i) then return end
	if e.k == "level" then ns.UI:Open("characters") return end
	if e.k == "milestone" then return end -- (the tooltip is the milestone)
	local sub = Subject(e, ns.Store:Get(e.k, e.i))
	if sub and sub.onClick then sub.onClick() end
end

-- (#46) other pages' Journey dots open their entries the same way
function page:OpenEntry(e) OpenEntry(e) end

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
	local cf = ns.ScopeChar() or charFilter -- (character-only Almanac: this character's journal)
	for i = #j, 1, -1 do
		local e = j[i]
		if (not cf or e.c == cf) and (not kindFilter or e.k == kindFilter) and (not zoneFilter or e.m == zoneFilter)
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
	{ "merchant", L["Merchants"], "townsfolk" }, { "trainer", L["Trainers"], "townsfolk" }, { "townsfolk", L["People"], "townsfolk" },
	{ "flight", L["Flight paths"], "townsfolk" }, { "node", L["Gathering nodes"], "gathering" }, { "fishing", L["Fishing waters"], "gathering" },
}

-- (0.69.1) the cards: each kind of journal entry, short names (two cards to a row)
local CARDS = {
	{ "zone", L["Zones"] }, { "subzone", L["Places"] }, { "instance", L["Dungeons"] }, { "creature", L["Creatures"] },
	{ "item", L["Items"] }, { "quest", L["Quests"] }, { "merchant", L["Merchants"] }, { "trainer", L["Trainers"] },
	{ "spell", L["Recipes"] }, { "townsfolk", L["People"] }, { "npc", L["Quest givers"] }, { "flight", L["Flight paths"] },
	{ "node", L["Gathering"] }, { "fishing", L["Fishing"] }, { "level", L["Levels"] }, { "character", L["Characters"] },
}
local SELECTED = "|cffffd200"

local function Overview()
	local b = {}
	local char = ns.ScopeChar() or charFilter
	b[#b + 1] = { "title", char and (L["%s's journal"]):format(ns.CharName(char, true)) or L["The Adventurer's Journal"] }
	b[#b + 1] = { "small", char and L["What this character has discovered. Pick All characters for the whole account."]
		or L["Everything your characters have discovered, together."] }

	-- (0.69.1) a card per kind of entry in the journal: how many, how many this session; picking one
	-- shows its entries in the list (picking it again, or All discoveries, shows everything)
	local count, fresh, total = {}, {}, 0
	for _, e in ipairs(ns.db.journal or {}) do
		if (not char or e.c == char) and e.k ~= "milestone" then
			count[e.k] = (count[e.k] or 0) + 1
			total = total + 1
			if (e.t or 0) >= (ns.sessionStart or 0) then fresh[e.k] = (fresh[e.k] or 0) + 1 end
		end
	end
	local slots = {}
	local function New(n) return (n and n > 0) and ("  |cff1eff00+" .. n .. "|r") or "" end
	local allNew = 0
	for _, n in pairs(fresh) do allNew = allNew + n end
	slots[#slots + 1] = { name = L["All discoveries"], icon = ns.JOURNAL_ICON, color = (kindFilter == nil) and SELECTED or nil, selected = (kindFilter == nil),
		note = tostring(total) .. New(allNew), tip = L["Every entry, newest first."], onClick = function() page:SetKind(nil) end }
	for _, c in ipairs(CARDS) do
		local k = c[1]
		if (count[k] or 0) > 0 then
			slots[#slots + 1] = { name = c[2], icon = W.KindArt(k), color = (kindFilter == k) and SELECTED or nil, selected = (kindFilter == k),
				note = tostring(count[k]) .. New(fresh[k]),
				tip = (kindFilter == k) and L["Showing these below. Click again to show everything."] or L["Click to show these below."],
				onClick = function() page:SetKind(k) end }
		end
	end
	b[#b + 1] = { "banner", L["Discoveries"] }
	if total > 0 then b[#b + 1] = { "slots", slots, cards = true } else b[#b + 1] = { "small", L["Nothing discovered yet. Go explore!"] } end

	-- research
	local M = ns.Milestones
	local s = M and M:Stats(char) or {}
	local B = ns.Bestiary
	local research = {}
	if B and (s.studied or 0) > 0 then
		research[#research + 1] = { name = L["Hunted"], icon = B:TierIcon(3), note = tostring(s.studied - (s.mastered or 0)),
			tip = L["Creatures researched to Hunted. Click: only those, in Creatures."], onClick = GoTo("bestiary", "ShowTier", 3) }
	end
	if B and (s.mastered or 0) > 0 then
		research[#research + 1] = { name = L["Master Hunter"], icon = B:TierIcon(4), note = tostring(s.mastered),
			tip = L["Creatures at Master Hunter. Click: only those, in Creatures."], onClick = GoTo("bestiary", "ShowTier", 4) }
	end
	if (s.kills or 0) > 0 then research[#research + 1] = { name = L["Defeated"], icon = W.FindIcon({ "Ability_DualWield", "INV_Sword_04" }), note = tostring(s.kills),
		tip = L["Creatures defeated. Click: every creature, in Creatures."], onClick = GoTo("bestiary", "ShowTier", nil) } end
	if (s.quest or 0) > 0 then research[#research + 1] = { name = L["Quests done"], icon = W.KindArt("quest"), note = tostring(s.quest),
		tip = L["Quests completed. Click: only the done ones, in Quests."], onClick = GoTo("quests", "ShowStatus", "d") } end
	if not char then
		for _, g in ipairs({ { "herb", L["Herbs picked"] }, { "ore", L["Veins mined"] }, { "fish", L["Fish caught"] }, { "skin", L["Skinned"] } }) do
			if (s[g[1]] or 0) > 0 then
				-- (0.69.1) Gathering opens on that group alone (Herbs, Ore and stone, Fishing, Skinning)
				-- (0.69.1) Fish caught wears the painted fishing art; the others their gathering icons
				local icon = g[1] == "fish" and W.KindArt("fishing")
					or W.FindIcon(ns.Gathering.KIND[g[1]] and ns.Gathering.KIND[g[1]].icon or { "INV_Misc_Pelt_Wolf_01" })
				research[#research + 1] = { name = g[2], icon = icon,
					note = tostring(s[g[1]]), tip = (L["Click: only %s, in Gathering."]):format(g[2]:lower()), onClick = GoTo("gathering", "ShowOnly", g[1]) }
			end
		end
	end
	if #research > 0 then
		b[#b + 1] = { "banner", L["Research"] }
		b[#b + 1] = { "slots", research, cards = true }
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
				onClick = function() page:SetKind("milestone") end }
		end
		ms[#ms + 1] = { name = L["Every milestone"], icon = W.FindIcon(W.KIND.milestone.icon), note = L["Shown below when picked."],
			color = (kindFilter == "milestone") and SELECTED or nil, selected = (kindFilter == "milestone"), onClick = function() page:SetKind("milestone") end }
		b[#b + 1] = { "slots", ms, cards = true }
	else
		b[#b + 1] = { "small", L["Milestones come from your own discoveries: your first elite, a hundred creatures, ten at Master Hunter..."] }
	end

	-- account view: who found things first
	if not char then
		local firsts = {}
		for _, c in ipairs(CATALOGUES) do
			for _, rec in pairs(ns.Store:Shown(c[1])) do
				if rec.b then firsts[rec.b] = (firsts[rec.b] or 0) + 1 end
			end
		end
		local who = {}
		for key, n in pairs(firsts) do
			local ch = ns.db.chars[key]
			if ch then
				-- (0.69.1) the character's class crest in the class-tinted ring, the faction banner beside it
				local cc = ch.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[ch.classFile]
				local crest = ch.classFile and CREST_CLASSES[ch.classFile]
				who[#who + 1] = { name = ns.CharName(key), n = n,
					icon = crest and ("Interface\\AddOns\\AzerothAlmanac\\Media\\Crest_" .. ch.classFile) or W.KindIcon("character"),
					crop = crest and 0.13 or nil,
					ring = cc and { cc.r, cc.g, cc.b } or { 0.62, 0.5, 0.24 },
					faction = ch.faction or FACTION_BY_RACE[ch.raceFile or ""],
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

function page:Build(parent, header)
	search = W.Search(header, 150, function(text)
		filter = text
		page:Refresh()
	end)
	search:SetPoint("LEFT", header, "LEFT", 16, -2)
	charButton = W.Dropdown(header, CharLabel(), 130, function(self) CharMenu(self) end)
	charButton:SetPoint("LEFT", search, "RIGHT", 10, 0)
	zoneButton = W.Dropdown(header, ZoneLabel(), 130, function(self) ZoneMenu(self) end)
	zoneButton:SetPoint("LEFT", charButton, "RIGHT", 6, 0)
	countText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countText:SetPoint("RIGHT", header, "RIGHT", -12, -2)

	-- (0.69.1) left: the overview, on the profession book's painted page
	detail = W.Detail(parent, nil, "painted")
	detail:SetPainting({ "Profession-background-card-Blacksmithing", "Profession-background-card-Mining",
		"Profession-background-card-Cooking", "Profession-background-card-Fishing", "Profession-background-card-FirstAid" }, 1)
	detail:SetPoint("TOPLEFT", 0, 0)
	detail:SetPoint("BOTTOMLEFT", 0, 0)
	detail:SetWidth(LEFT_W)

	-- top right: the Journey; bottom right: the entries
	journey = W.JourneyPane(parent, {
		onPick = function(e) OpenEntry(e) end,
		onLarger = function() large = not large page:Layout() end,
	})
	journey:SetCharacter(charFilter)

	local box = W.Inset(parent)
	page.box = box
	local hovered
	list = W.List(box, {
		collapse = { state = collapsed, key = function(r) return r.header and r.day end, refresh = function() page:Refresh() end },
		rowHeight = 26,
		emptyText = L["Nothing discovered yet. Go explore!"],
		update = function(row, e)
			row:SetHeader(e.header ~= nil, e.header and collapsed[e.day])
			-- (0.69.0) the journal seal on the corner of each entry's icon (the open journal, its burning page)
			if not row.seal then
				row.seal = row.icon:GetParent():CreateTexture(nil, "OVERLAY", nil, 7)
				row.seal:SetSize(14, 14)
				row.seal:SetPoint("CENTER", row.icon, "BOTTOMRIGHT", -1, 2)
				row.seal:SetTexture(ns.JOURNAL_ICON)
			end
			row.seal:SetShown(not e.header)
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
			elseif e.k == "node" and ns.Gathering and ns.Gathering.NodeIcon then
				icon = ns.Gathering:NodeIcon(ns.Store:Get("node", e.i))
			end
			W.SetTex(row.icon, icon or W.KindArt(e.k))
			row.text:SetText(e.s or "?")
			row.right:SetText(ns.CharName(e.c) .. "  |cff999999" .. date("%H:%M", e.t or 0) .. "|r")
		end,
		itemOf = function(e) return e.k == "item" and e.i or nil end,
		restore = function() end, -- (coming Back to the Journal opens nothing)
		-- hover: the journal entry in a tooltip, and the Journey turns to where it happened
		onHover = function(e)
			if e.header then return end
			hovered = e
			EntryTooltip(e)
			if journey and e.m and e.x then journey:Focus(e) end
		end,
		onLeave = function()
			hovered = nil
			GameTooltip:Hide()
			-- (back to the whole map once the mouse has left the list, not between two rows)
			C_Timer.After(0.35, function() if not hovered and journey then journey:Focus(nil) end end)
		end,
		onClick = function(e)
			if e.header then
				collapsed[e.day] = not collapsed[e.day]
				page:Refresh()
				return
			end
			GameTooltip:Hide()
			OpenEntry(e)
		end,
	})
	list:SetAllPoints(box)
	page:Layout()
end

function page:Layout()
	if not (journey and self.box) then return end
	journey:ClearAllPoints()
	journey:SetPoint("TOPLEFT", detail, "TOPRIGHT", 6, 0)
	journey:SetPoint("RIGHT", journey:GetParent(), "RIGHT", 0, 0)
	if large then
		journey:SetPoint("BOTTOM", journey:GetParent(), "BOTTOM", 0, 0)
		self.box:Hide()
	else
		journey:SetHeight(300)
		self.box:ClearAllPoints()
		self.box:SetPoint("TOPLEFT", journey, "BOTTOMLEFT", 0, -6)
		self.box:SetPoint("BOTTOMRIGHT", self.box:GetParent(), "BOTTOMRIGHT", 0, 0)
		self.box:Show()
	end
	journey:SetLarge(large)
end

function page:Refresh()
	if not list then return end
	local data, n = Collect()
	list:SetData(data)
	local kind = kindFilter and W.KIND[kindFilter]
	countText:SetText((kind and (kind.label .. ": ") or "") .. ns.N(n, "entry", "entries"))
	if journey and not journey:IsPlaying() then journey:Refresh(false) end
	detail:SetBlocks(Overview(), nil, true)
end

-- (0.69.1) show one kind of entry in the list (nil, or the same kind again: everything)
function page:SetKind(k)
	if k ~= nil and k == kindFilter then k = nil end
	kindFilter = k
	self:Refresh()
	if list and list.ScrollTop then list:ScrollTop() end
end

function page:ShowOverview()
	ns.UI:Open("journal")
	self:SetKind(nil)
end

function page:ShowMilestones()
	ns.UI:Open("journal")
	kindFilter = nil
	self:SetKind("milestone")
end

-- the journal of one character (nil = the whole account)
function page:SetCharacter(key)
	charFilter = key
	if charButton then charButton:SetText(CharLabel()) end
	if journey then journey:SetCharacter(key) end
	self:Refresh()
end

ns:On("RESET", function()
	kindFilter = nil
	if list then page:Refresh() end
end)

ns.UI:RegisterPage(page)
