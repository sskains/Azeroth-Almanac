-- Dungeons page: the dungeons and raids your characters have entered. Each one shows its floors on
-- the game's own map art (with a skull where each boss was met), the bosses met there (the rest
-- only counted), the loot you've had from them, and every character's runs.

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local page = { key = "dungeons", title = L["Dungeons"], icon = W.KIND.instance.icon, order = 6.5 }
local list, detail, countText, nameText, subText
local filter = ""
local shown
local collapsed = {}
local maps = {} -- one map widget per floor

local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"

local function DG() return ns.Dungeons end

local function Duration(secs)
	if not secs then return "?" end
	local m = math.floor(secs / 60 + 0.5)
	if m < 60 then return (L["%d min"]):format(m) end
	return (L["%d h %d min"]):format(math.floor(m / 60), m % 60)
end

local function OpenCreature(npc)
	return function() local p = ns.UI:GetPage("bestiary") if p then p:ShowCreature(npc) end end
end

local function Describe(id, rec)
	local b = {}
	local met, unmet = DG():Bosses(id, rec)

	-- the floors, with a skull where each boss was met and an arrow where you stand
	local floors = {}
	for map, fname in pairs(rec.maps or {}) do floors[#floors + 1] = { map = map, name = fname } end
	table.sort(floors, function(x, y) return x.map < y.map end)
	for n, fl in ipairs(floors) do
		if n > 4 then break end
		maps[n] = maps[n] or W.ZoneMap(detail)
		local m = maps[n]
		if #floors > 1 then b[#b + 1] = { "small", fl.name } end
		b[#b + 1] = { "frame", m, function(width)
			local h = m:Draw(fl.map, width)
			if h > 0 then
				local pins = {}
				for _, e in ipairs(met) do
					if e.b.map == fl.map and e.b.x then
						pins[#pins + 1] = { x = e.b.x, y = e.b.y, icon = SKULL, size = 18, name = e.b.name,
							sub = (e.b.kills or 0) > 0 and (L["Killed %s"]):format(ns.Times(e.b.kills)) or L["Not yet defeated"],
							onClick = e.b.npc and OpenCreature(e.b.npc) or nil }
					end
				end
				local here = ns.Where()
				if here.map == fl.map and here.x then
					pins[#pins + 1] = { x = here.x, y = here.y, icon = "Interface\\WorldMap\\WorldMapArrow", size = 24, top = true,
						facing = GetPlayerFacing and ns.Readable(GetPlayerFacing()), name = UnitName("player"), sub = L["You are here."] }
				end
				m:SetPins(pins)
			end
			return h
		end }
	end

	-- general
	local lo, hi, zone, raid = DG():Info(id, rec)
	b[#b + 1] = { "banner", L["General"] }
	b[#b + 1] = { "stat", L["Kind"], (rec.type == "raid" or raid) and L["Raid"] or L["Dungeon"] }
	if zone then b[#b + 1] = { "stat", L["Entrance"], zone } end
	if lo and hi and hi > 0 then b[#b + 1] = { "stat", L["Levels"], lo == hi and tostring(lo) or (lo .. " - " .. hi) } end
	b[#b + 1] = { "stat", L["First entered"], ns.CharName(rec.b) .. ", " .. ns.DateText(rec.f) }
	b[#b + 1] = { "stat", L["Times entered"], tostring(rec.n or 1) }
	if rec.best then b[#b + 1] = { "stat", L["Quickest run with a kill"], Duration(rec.best) } end
	b[#b + 1] = { "stat", L["Last time"], ns.AgoText(rec.l) }

	-- bosses
	local hidden = (unmet.b or 0) + (unmet.e or 0)
	b[#b + 1] = { "banner", (L["Bosses met (%d)"]):format(#met) }
	if #met > 0 then
		local s = {}
		for _, e in ipairs(met) do
			local c = e.b.npc and ns.Store:Get("creature", e.b.npc)
			local note = (e.b.kills or 0) > 0 and (L["Killed %s"]):format(ns.Times(e.b.kills)) or L["Not yet defeated"]
			if c then note = note .. "  ·  " .. ns.Bestiary:TierMarkup(ns.Bestiary:Tier(c), 12) .. " " .. ns.Bestiary.TIERS[ns.Bestiary:Tier(c)] end
			local tip = {}
			if (e.b.wipes or 0) > 0 then tip[#tip + 1] = (L["Wiped %s."]):format(ns.Times(e.b.wipes)) end
			if e.b.first then tip[#tip + 1] = (L["First met by %s on %s."]):format(ns.CharName(e.b.first.c, true), ns.DateText(e.b.first.t)) end
			if e.b.npc then tip[#tip + 1] = L["Click to open in the Bestiary."] end
			s[#s + 1] = { name = e.b.name or "?", icon = W.FindIcon(c and W.TYPE_ICON[c.type or ""] or W.KIND.creature.icon),
				note = note, tip = table.concat(tip, "\n"), onClick = e.b.npc and OpenCreature(e.b.npc) or nil }
		end
		b[#b + 1] = { "slots", s }
	end
	if hidden > 0 then b[#b + 1] = { "small", (L["%s you haven't met yet."]):format(ns.N(hidden, "more boss", "more bosses")) } end
	if (unmet.r or 0) > 0 then b[#b + 1] = { "small", (L["%s seen here only now and then."]):format(ns.N(unmet.r, "rare creature is", "rare creatures are")) } end
	if #met == 0 and hidden == 0 then b[#b + 1] = { "small", L["Bosses appear here as you meet them."] } end

	-- loot you've had from its bosses
	local loot, more = {}, 0
	for _, e in ipairs(met) do
		local c = e.b.npc and ns.Store:Get("creature", e.b.npc)
		local got = {}
		for item, n in pairs(c and c.loot or {}) do
			got[item] = true
			local rate = (c.corpses or 0) > 0 and ("  " .. math.floor(n / c.corpses * 100 + 0.5) .. "%") or ""
			loot[#loot + 1] = { item = item, note = (e.b.name or "?") .. rate }
		end
		for _, it in ipairs(e.db and DG().Items(e.db.items) or {}) do
			if not got[it.id] then more = more + 1 end
		end
	end
	if #loot > 0 or more > 0 then
		b[#b + 1] = { "banner", L["Loot from its bosses"] }
		if #loot > 0 then b[#b + 1] = { "slots", loot } end
		if more > 0 then b[#b + 1] = { "small", (L["%s these bosses carry that you haven't had yet."]):format(ns.N(more, "more item", "more items")) } end
	end

	-- your characters
	local rows = {}
	for key, c in pairs(ns.db.chars) do
		local r = c.runs and c.runs[id]
		if r then
			local kills = 0
			for _, n in pairs(r.kills or {}) do kills = kills + n end
			rows[#rows + 1] = { "stat", ns.CharName(key), (L["%s, %s, %s inside, last %s"]):format(ns.N(r.n or 0, "visit", "visits"),
				ns.N(kills, "boss kill", "boss kills"), Duration(r.time or 0), ns.DateText(r.last)) }
		end
	end
	if #rows > 0 then
		b[#b + 1] = { "banner", L["Your characters"] }
		table.sort(rows, function(x, y) return x[2] < y[2] end)
		for _, r in ipairs(rows) do b[#b + 1] = r end
	end
	return b
end

local function Show(id, keep)
	shown = id
	local rec = id and ns.Store:Get("instance", id)
	if not rec then
		nameText:SetText("")
		subText:SetText("")
		detail:SetBlocks(nil, L["Select a dungeon or raid."])
		return
	end
	local lo, hi, zone, raid = DG():Info(id, rec)
	nameText:SetText(rec.name or "?")
	local sub = { (rec.type == "raid" or raid) and L["Raid"] or L["Dungeon"] }
	if zone then sub[#sub + 1] = zone end
	if lo and hi and hi > 0 then sub[#sub + 1] = (L["levels %s"]):format(lo == hi and tostring(lo) or (lo .. "-" .. hi)) end
	subText:SetText(table.concat(sub, "  ·  "))
	detail:SetBlocks(Describe(id, rec), nil, keep)
end

local function Collect()
	local groups, total = { party = {}, raid = {} }, 0
	for id, rec in pairs(ns.Store:All("instance")) do
		total = total + 1
		if filter == "" or (rec.name or ""):lower():find(filter, 1, true) then
			local lo, _, _, raid = DG():Info(id, rec)
			table.insert((rec.type == "raid" or raid) and groups.raid or groups.party, { id = id, rec = rec, lo = lo or 99 })
		end
	end
	local rows, n = {}, 0
	for _, g in ipairs({ { "party", L["Dungeons"] }, { "raid", L["Raids"] } }) do
		local items = groups[g[1]]
		if #items > 0 then
			table.sort(items, function(a, b) if a.lo ~= b.lo then return a.lo < b.lo end return (a.rec.name or "") < (b.rec.name or "") end)
			rows[#rows + 1] = { header = g[2], key = g[1], count = #items }
			if not collapsed[g[1]] then for _, it in ipairs(items) do rows[#rows + 1] = it end end
			n = n + #items
		end
	end
	return rows, n, total
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
	left:SetWidth(300)
	list = W.List(left, {
		collapse = { state = collapsed, key = function(r) return r.header and r.key end, refresh = function() page:Refresh() end },
		rowHeight = 28,
		round = true,
		emptyText = L["No dungeons yet. Every dungeon and raid your characters enter is recorded here, with its bosses as you meet them."],
		update = function(row, r)
			row.icon:ClearAllPoints()
			row:SetHeader(r.header ~= nil, r.header and collapsed[r.key])
			if r.header then
				row.icon:SetPoint("LEFT", 4, 0)
				row.icon:SetTexture(nil)
				row.text:SetFontObject(W.Font("GameFontNormalLarge", "GameFontNormal"))
				row.text:SetText(r.header)
				row.right:SetText("|cff999999" .. r.count .. "|r")
			else
				row.icon:SetPoint("LEFT", 20, 0)
				row.icon:SetTexture(W.KindIcon("instance"))
				row.text:SetFontObject(GameFontHighlight)
				row.text:SetText(r.rec.name or "?")
				local lo, hi = DG():Info(r.id, r.rec)
				row.right:SetText(lo and hi and hi > 0 and ("|cff999999[" .. (lo == hi and lo or (lo .. "-" .. hi)) .. "]|r") or "")
			end
		end,
		onClick = function(r)
			if r.header then
				collapsed[r.key] = not collapsed[r.key]
				page:Refresh()
			elseif r.id then
				Show(r.id)
			end
		end,
	})
	list:SetAllPoints(left)

	detail = W.Detail(parent, 46)
	detail:SetTheme({ "Mining", "Blacksmithing" }) -- the profession book's paintings behind the card and body
	detail:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
	detail:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
	nameText = detail.top:CreateFontString(nil, "OVERLAY")
	W.HeroFont(nameText, 26)
	nameText:SetPoint("TOPLEFT", 2, 0)
	subText = detail.top:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	subText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -5)
	Show(nil)
end

function page:Refresh()
	if not list then return end
	local rows, n, total = Collect()
	local keep
	for _, r in ipairs(rows) do if r.id and r.id == shown then keep = r end end
	list:SetData(rows)
	list:Select(keep)
	countText:SetText((L["%d of %d dungeons and raids"]):format(n, total))
	if shown then Show(shown, true) end
end

function page:ShowDungeon(id)
	ns.UI:Open("dungeons")
	shown = id
	self:Refresh()
end

ns:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
	if W.waitingItems and shown and ns.UI:IsShown() and ns.UI:Current() == "dungeons" then
		W.waitingItems = false
		C_Timer.After(0.2, function() if shown then Show(shown, true) end end)
	end
end)

ns:On("RESET", function() shown = nil if list then list:Select(nil) Show(nil) end end)

ns.UI:RegisterPage(page)
