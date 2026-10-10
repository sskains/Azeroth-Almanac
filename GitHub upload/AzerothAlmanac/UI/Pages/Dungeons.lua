-- Dungeons page (0.68.0, design: docs/DESIGN.md section 73). Two tabs:
--   Collection: a card for every dungeon and raid your characters have found (the stone-arch dungeon
--     card), four to a row; hovering grows a card; clicking one opens it in the second tab.
--   The dungeon: its floors on Blizzard's dungeon map art (left; 0.68.2, a floor at a time) with a round
--     portrait where each boss you've met stands; on the right the dungeon's Overview, or for the boss you click its Abilities, Loot
--     and Other facts (from the Creatures page, as far as its research tier unlocks them).
-- Only what you've found shows: unfound dungeons are counted, unmet bosses aren't drawn.

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local page = { key = "dungeons", title = L["Dungeons"], icon = "Interface\\AddOns\\AzerothAlmanac\\Media\\Tab_Dungeons", order = 7.5 }
local state = { tab = "collection", id = nil, boss = nil, sub = "overview" }
local filter = ""
local countText, tabRow, pageTabs = nil, nil, {}
local collection, scroll, content, cards = nil, nil, nil, {}
local view, left, right, nameText, subText, subRow, subTabs = nil, nil, nil, nil, nil, nil, {}
local nameArt -- (0.69.0, #31) the dungeon's name as word art over the header
local maps = {} -- the floor map (one widget, the floor picker turns its pages)
local artFrame -- the journal art, for a dungeon with no map art

local COLS, GAP, PAD, CAPTION = 4, 18, 16, 34
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"

local function DG() return ns.Dungeons end
local function B() return ns.Bestiary end

local function Duration(secs)
	if not secs then return "?" end
	local m = math.floor(secs / 60 + 0.5)
	if m < 60 then return (L["%d min"]):format(m) end
	return (L["%d h %d min"]):format(math.floor(m / 60), m % 60)
end

local function OpenCreature(npc)
	return function() local p = ns.UI:GetPage("bestiary") if p then p:ShowCreature(npc) end end
end

local function Levels(id, rec)
	local lo, hi = DG():Info(id, rec)
	if lo and hi and hi > 0 then return lo == hi and tostring(lo) or (lo .. "-" .. hi) end
end

local function IsRaid(id, rec)
	local _, _, _, raid = DG():Info(id, rec)
	return rec.type == "raid" or raid
end

-- the bosses of a dungeon you've met, how many of the records' bosses you haven't, and the rares
local function Met(id, rec)
	local met, unmet = DG():Bosses(id, rec)
	return met, (unmet.b or 0) + (unmet.e or 0), unmet.r or 0
end

local function TotalDungeons()
	local seen, n = {}, 0
	for _, d in ipairs(ns.DB and ns.DB.dungeon or {}) do
		local k = d.id or d.name -- (Lower and Upper Blackrock Spire are one instance)
		if k and not seen[k] then seen[k] = true n = n + 1 end
	end
	return n
end

local function KillNote(n)
	n = n or 0
	return n > 0 and ns.N(n, "kill", "kills") or L["Not yet defeated"]
end

-- (0.68.7) a boss's name: its creature record's once the game has named it (the dungeon's own entry
-- may still say "Boss #..." from before), else the entry's
local function BossName(e)
	local c = e.b.npc and ns.Store:Get("creature", e.b.npc)
	if c and c.name and not c.unnamed and not c.name:find("^Boss #") then return c.name end
	return e.b.name or "?"
end

local function TypeIcon(c) return W.FindIcon(c and W.TYPE_ICON[c.type or ""] or W.KIND.creature.icon) end

---------------------------------------------------------------------------
-- Tabs (the Settings panel's tab art, as the Characters page uses)
---------------------------------------------------------------------------

local function MakeTab(parent, label, icon, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(26)
	b.l = b:CreateTexture(nil, "BACKGROUND")
	b.m = b:CreateTexture(nil, "BACKGROUND")
	b.r = b:CreateTexture(nil, "BACKGROUND")
	b.native = W.TryAtlas(b.l, "Options_Tab_Left") and W.TryAtlas(b.m, "Options_Tab_Middle") and W.TryAtlas(b.r, "Options_Tab_Right")
	if b.native then
		b.l:SetPoint("BOTTOMLEFT") b.l:SetSize(7, 26)
		b.r:SetPoint("BOTTOMRIGHT") b.r:SetSize(7, 26)
		b.m:SetPoint("BOTTOMLEFT", b.l, "BOTTOMRIGHT") b.m:SetPoint("TOPRIGHT", b.r, "TOPLEFT")
	else
		b.l:SetAllPoints() b.l:SetColorTexture(0.14, 0.11, 0.06, 0.95)
		b.m:Hide() b.r:Hide()
	end
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(16, 16)
	b.icon:SetPoint("LEFT", 10, -1)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.text:SetPoint("LEFT", b.icon, "RIGHT", 5, 0)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetPoint("TOPLEFT", 4, -3)
	hl:SetPoint("BOTTOMRIGHT", -4, 0)
	hl:SetColorTexture(1, 0.85, 0.4, 0.08)
	function b:Set(text, tex)
		self.text:SetText(text)
		if tex then self.icon:SetTexture(tex) end
		self:SetWidth(math.floor(self.text:GetStringWidth() + 16 + 5 + 22))
	end
	function b:SetActive(on)
		if self.native then
			local suffix = on and "Options_Tab_Active_" or "Options_Tab_"
			W.TryAtlas(self.l, suffix .. "Left") W.TryAtlas(self.m, suffix .. "Middle") W.TryAtlas(self.r, suffix .. "Right")
			local h = on and 26 or 23
			self.l:SetHeight(h) self.r:SetHeight(h)
		else
			self.l:SetColorTexture(on and 0.45 or 0.14, on and 0.33 or 0.11, on and 0.12 or 0.06, 0.95)
		end
		self.text:SetFontObject(on and GameFontHighlightSmall or GameFontNormalSmall)
		self.icon:SetDesaturated(not on)
		self.icon:SetAlpha(on and 1 or 0.8)
	end
	function b:SetUsable(on)
		self.usable = on
		self:SetAlpha(on and 1 or 0.45)
	end
	b.usable = true
	b:SetScript("OnClick", function(self)
		if not self.usable then return end
		if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
		onClick()
	end)
	b:Set(label, icon)
	return b
end

---------------------------------------------------------------------------
-- Tab 1: the collection
---------------------------------------------------------------------------

local function Found()
	local list = {}
	-- (0.69.1) one card per dungeon: a record made up by /aa seeddungeons (or kept under a made-up key
	-- for a WoW Forever dungeon) gives way to the real one once the game has named that dungeon
	local real = {}
	for id, rec in pairs(ns.Store:Shown("instance")) do
		if type(rec) == "table" and type(id) == "number" and id > 0 and not rec.seeded then
			local k = DG().NameKey(rec.name)
			if k then real[k] = true end
		end
	end
	for id, rec in pairs(ns.Store:Shown("instance")) do
		local stand = type(rec) == "table" and (rec.seeded or (type(id) == "number" and id < 0))
		local k = type(rec) == "table" and DG().NameKey(rec.name)
		if type(rec) == "table" and not (stand and k and real[k]) and (filter == "" or (rec.name or ""):lower():find(filter, 1, true)) then
			local lo = DG():Info(id, rec)
			list[#list + 1] = { id = id, rec = rec, lo = lo or 99, raid = IsRaid(id, rec),
				isNew = ns.New and ns.New:IsNew("dungeons", rec) or nil }
		end
	end
	-- (0.69.0, #38) found since you last looked first; then dungeons, then raids; each by level, then name
	table.sort(list, function(a, b)
		if (a.isNew and 1 or 0) ~= (b.isNew and 1 or 0) then return a.isNew and true or false end
		if (a.raid and 1 or 0) ~= (b.raid and 1 or 0) then return not a.raid end
		if a.lo ~= b.lo then return a.lo < b.lo end
		return (a.rec.name or "") < (b.rec.name or "")
	end)
	return list
end

local function LayoutCollection()
	if not (collection and content) then return end
	local list = Found()
	local width = (scroll:GetWidth() or 0) - 4
	if width < 200 then width = 760 end
	local cw = math.floor((width - 2 * PAD - (COLS - 1) * GAP) / COLS)
	local ch = math.floor(W.DungeonCardHeight(cw))
	content:SetWidth(width)
	for i, it in ipairs(list) do
		local c = cards[i]
		if not c or c.cw ~= cw then
			if c then c:Hide() c.caption:Hide() end
			c = W.DungeonCard(content, cw)
			c.cw = cw
			c.caption = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			c.caption:SetWidth(cw + 10)
			c.caption:SetJustifyH("CENTER")
			c.onClick = function(self)
				if self.isNew and ns.New then ns.New:Click("dungeons", self.id) end
				page:ShowDungeon(self.id)
			end
			cards[i] = c
		end
		c:SetDungeon(it.id, it.rec)
		-- (0.69.0) a gold "New" ribbon across the top of a card found since you last looked
		if not c.newRibbon then
			local rb = CreateFrame("Frame", nil, c)
			rb:SetSize(cw * 0.56, 18)
			rb:SetPoint("CENTER", c, "TOP", 0, -4)
			rb:SetFrameLevel(c:GetFrameLevel() + 10)
			rb.bg = rb:CreateTexture(nil, "BACKGROUND")
			rb.bg:SetAllPoints()
			rb.bg:SetColorTexture(0.55, 0.36, 0.06, 0.95)
			rb.edge = rb:CreateTexture(nil, "BORDER")
			rb.edge:SetPoint("TOPLEFT", 1, -1)
			rb.edge:SetPoint("BOTTOMRIGHT", -1, 1)
			rb.edge:SetColorTexture(0.86, 0.62, 0.12, 1)
			rb.text = rb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			rb.text:SetPoint("CENTER", 0, 0)
			rb.text:SetText(L["New"])
			rb.text:SetTextColor(1, 1, 1)
			rb.text:SetShadowOffset(1, -1)
			c.newRibbon = rb
		end
		c.newRibbon:SetShown(it.isNew and true or false)
		c.isNew = it.isNew
		local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
		local x = PAD + col * (cw + GAP) + cw / 2
		local y = -(PAD + row * (ch + CAPTION + GAP) + ch / 2)
		c:SetFrameLevel(content:GetFrameLevel() + 2)
		c:PlaceAt(content, x, y)
		c.caption:ClearAllPoints()
		c.caption:SetPoint("TOP", content, "TOPLEFT", x, y - ch / 2 - 4)
		local met, unmetN = Met(it.id, it.rec)
		local killed = 0
		for _, e in ipairs(met) do if (e.b.kills or 0) > 0 then killed = killed + 1 end end
		local lv = Levels(it.id, it.rec)
		c.caption:SetText(("%s%s\n|cffbbbbbb%s|r"):format(DG():SizeText(it.id, it.rec), lv and ("|cffdddddd  ·  " .. (L["levels %s"]):format(lv) .. "|r") or "",
			(L["Bosses killed: %d of %d met"]):format(killed, #met)))
		c.tip = { it.rec.name or "?", (L["Entered %s."]):format(ns.N(it.rec.n or 1, "time", "times")),
			unmetN > 0 and (L["%s still to find."]):format(ns.N(unmetN, "boss", "bosses")) or L["Every boss here met."] }
		c:Show()
		c.caption:Show()
	end
	for i = #list + 1, #cards do cards[i]:Hide() cards[i].caption:Hide() end
	local rows = math.ceil(#list / COLS)
	content:SetHeight(math.max(1, 2 * PAD + rows * (ch + CAPTION + GAP)))
	collection.empty:SetShown(#list == 0)
end

---------------------------------------------------------------------------
-- Tab 2: the dungeon
---------------------------------------------------------------------------

local function BossEntry(id, rec, key)
	if not key then return nil end
	for _, e in ipairs((Met(id, rec))) do if e.key == key then return e end end
end

local function SelectBoss(key)
	state.boss = key
	-- (#56) from one boss to another you stay on the tab you were reading (Abilities, Loot, Other);
	-- from the Overview (or no boss) a boss opens on Abilities
	if not key then state.sub = "overview"
	elseif state.sub == "overview" or not state.sub then state.sub = "abilities" end
	page:Refresh()
end

-- (0.68.2) the floor picker over the map: < floor name (2 / 4) >
local floorBar
local function FloorBar()
	if floorBar then return floorBar end
	local f = CreateFrame("Frame", nil, left)
	f:SetHeight(26)
	local function Arrow(step)
		local b = CreateFrame("Button", nil, f)
		b:SetSize(26, 26)
		local base = step < 0 and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-" or "Interface\\Buttons\\UI-SpellbookIcon-NextPage-"
		b:SetNormalTexture(base .. "Up")
		b:SetPushedTexture(base .. "Down")
		b:SetDisabledTexture(base .. "Disabled")
		b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		b:SetScript("OnClick", function()
			state.floor = (state.floor or 1) + step
			if SOUNDKIT and SOUNDKIT.IG_ABILITY_PAGE_TURN then PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN) end
			page:Refresh()
		end)
		return b
	end
	f.prev = Arrow(-1)
	f.prev:SetPoint("LEFT")
	f.next = Arrow(1)
	f.next:SetPoint("RIGHT")
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.text:SetPoint("LEFT", f.prev, "RIGHT", 4, 0)
	f.text:SetPoint("RIGHT", f.next, "LEFT", -4, 0)
	f.text:SetWordWrap(false)
	floorBar = f
	return f
end

-- the dungeon's map (left pane): Blizzard's own floor art with a round portrait where each boss you've
-- met stands (the records' spot); dungeons without map art show their journal art and a list
local function LeftBlocks(id, rec)
	local b = {}
	local met = Met(id, rec)
	local floors, spots = DG():MapFloors(id, rec.name)
	-- (the map draws its pins later, when the blocks are laid out: what has a spot is worked out now)
	local placed = {}
	for _, e in ipairs(met) do if e.db and spots[e.db] then placed[e.key] = true end end
	if #floors > 0 then
		-- which floor: the chosen boss's when it changes, else the one you turned to, else the first with a boss met
		local chosen = BossEntry(id, rec, state.boss)
		if state.boss ~= state.floorBoss then
			state.floorBoss = state.boss
			local spot = chosen and chosen.db and spots[chosen.db]
			if spot then state.floor = spot.floor end
		end
		if not state.floor then
			for _, e in ipairs(met) do
				local spot = e.db and spots[e.db]
				if spot then state.floor = spot.floor break end
			end
		end
		state.floor = math.max(1, math.min(#floors, state.floor or 1))
		local fl = floors[state.floor]
		if #floors > 1 then
			local bar = FloorBar()
			bar.text:SetText(("%s  |cffbbbbbb(%d / %d)|r"):format(fl.name, state.floor, #floors))
			bar.prev:SetEnabled(state.floor > 1)
			bar.next:SetEnabled(state.floor < #floors)
			b[#b + 1] = { "frame", bar, function(width) bar:SetWidth(width) return 26 end }
		end
		maps[1] = maps[1] or W.ZoneMap(left)
		local m = maps[1]
		b[#b + 1] = { "frame", m, function(width)
			local h = m:DrawTiles(fl.prefix, width)
			local pins = {}
			for _, e in ipairs(met) do
				local spot = e.db and spots[e.db]
				if spot then
					if spot.floor == state.floor then
						local c = e.b.npc and ns.Store:Get("creature", e.b.npc)
						if c and not c.display and e.b.npc and B().LearnFace then pcall(B().LearnFace, B(), e.b.npc) end
						local sel = state.boss == e.key
						pins[#pins + 1] = { x = spot.x, y = spot.y, round = true, size = sel and 40 or 32,
							face = c and c.display, icon = c and TypeIcon(c) or SKULL,
							name = BossName(e), sub = KillNote(e.b.kills),
							onClick = function() SelectBoss(e.key) end, top = sel }
					end
				end
			end
			m:SetPins(pins)
			return h
		end }
		-- bosses met on the other floors, so they're a click away
		local elsewhere = {}
		for _, e in ipairs(met) do
			local spot = e.db and spots[e.db]
			if spot and spot.floor ~= state.floor then
				local c = e.b.npc and ns.Store:Get("creature", e.b.npc)
				elsewhere[#elsewhere + 1] = { name = BossName(e), icon = TypeIcon(c), note = floors[spot.floor].name,
					onClick = function() SelectBoss(e.key) end }
			end
		end
		if #elsewhere > 0 then
			b[#b + 1] = { "banner", L["On other floors"] }
			b[#b + 1] = { "slots", elsewhere }
		end
	else
		-- no map art for this dungeon (WoW Forever's own): its journal art
		if not artFrame then
			artFrame = CreateFrame("Frame", nil, left)
			artFrame.tex = artFrame:CreateTexture(nil, "ARTWORK")
			artFrame.tex:SetAllPoints()
		end
		local art = W.DungeonArt(id, rec.name)
		artFrame.tex:SetTexture(art)
		artFrame.tex:SetTexCoord(W.DungeonArtCoords(art, true))
		b[#b + 1] = { "frame", artFrame, function(width) artFrame:SetSize(width, width * 0.6) return width * 0.6 end }
		b[#b + 1] = { "small", L["There's no map of this dungeon yet; its bosses are listed below."] }
	end
	-- bosses met with no spot on the map
	local rest = {}
	for _, e in ipairs(met) do
		if not placed[e.key] then
			local c = e.b.npc and ns.Store:Get("creature", e.b.npc)
			rest[#rest + 1] = { name = BossName(e), icon = TypeIcon(c),
				note = KillNote(e.b.kills),
				onClick = function() SelectBoss(e.key) end }
		end
	end
	if #rest > 0 then
		b[#b + 1] = { "banner", #floors > 0 and L["Bosses met (no spot on the map)"] or (L["Bosses met (%d)"]):format(#rest) }
		b[#b + 1] = { "slots", rest }
	end
	if #met == 0 then b[#b + 1] = { "small", L["Bosses appear on the map as you fight them."] } end
	return b
end

-- the dungeon's Overview (right pane, no boss chosen)
local function OverviewBlocks(id, rec)
	local b = {}
	local met, hidden, rares = Met(id, rec)
	local lo, hi, zone = DG():Info(id, rec)
	b[#b + 1] = { "banner", L["General"] }
	b[#b + 1] = { "stat", L["Group size"], DG():SizeText(id, rec) }
	if zone then b[#b + 1] = { "stat", L["Entrance"], zone } end
	if lo and hi and hi > 0 then b[#b + 1] = { "stat", L["Levels"], lo == hi and tostring(lo) or (lo .. " - " .. hi) } end
	b[#b + 1] = { "stat", L["First entered"], ns.CharName(rec.b) .. ", " .. ns.DateText(rec.f) }
	b[#b + 1] = { "stat", L["Times entered"], tostring(rec.n or 1) }
	if rec.best then b[#b + 1] = { "stat", L["Quickest run with a kill"], Duration(rec.best) } end
	b[#b + 1] = { "stat", L["Last time"], ns.AgoText(rec.l) }

	-- (0.68.1) the bosses themselves are on the left (map or list): here, how far along you are
	b[#b + 1] = { "banner", L["Bosses"] }
	local killed, mastered = 0, 0
	for _, e in ipairs(met) do
		if (e.b.kills or 0) > 0 then killed = killed + 1 end
		local c = e.b.npc and ns.Store:Get("creature", e.b.npc)
		if c and B():Tier(c) >= 4 then mastered = mastered + 1 end
	end
	b[#b + 1] = { "stat", L["Met"], tostring(#met) }
	b[#b + 1] = { "stat", L["Defeated"], tostring(killed) }
	b[#b + 1] = { "stat", L["Mastered"], tostring(mastered) }
	if #met > 0 then b[#b + 1] = { "small", L["Click a boss on the left for its abilities, loot and more."] } end
	if hidden > 0 then b[#b + 1] = { "small", (L["%s you haven't met yet."]):format(ns.N(hidden, "more boss", "more bosses")) } end
	if rares > 0 then b[#b + 1] = { "small", (L["%s seen here only now and then."]):format(ns.N(rares, "rare creature is", "rare creatures are")) } end

	-- other creatures recorded inside (on its floors)
	local bossKeys = {}
	for _, e in ipairs(met) do if e.b.npc then bossKeys[e.b.npc] = true end end
	local others = {}
	for npc, c in pairs(ns.Store:Shown("creature")) do
		if type(c) == "table" and not bossKeys[npc] and c.z then
			for map in pairs(rec.maps or {}) do
				if c.z[map] then
					others[#others + 1] = { name = c.name or "?", icon = TypeIcon(c),
						note = ns.N(B():KillCount(c), "kill", "kills"), onClick = OpenCreature(npc) }
					break
				end
			end
		end
	end
	if #others > 0 then
		table.sort(others, function(x, y) return x.name < y.name end)
		b[#b + 1] = { "banner", (L["Other creatures here (%d)"]):format(#others) }
		local s = {}
		for k = 1, math.min(24, #others) do s[k] = others[k] end
		b[#b + 1] = { "slots", s }
		if #others > 24 then b[#b + 1] = { "small", (L["...and %d more in Creatures."]):format(#others - 24) } end
	end

	-- loot you've had from its bosses
	local loot, more = {}, 0
	for _, e in ipairs(met) do
		local c = e.b.npc and ns.Store:Get("creature", e.b.npc)
		local got = {}
		for item, n in pairs(c and c.loot or {}) do
			got[item] = true
			local rate = (c.corpses or 0) > 0 and ("  " .. math.floor(n / c.corpses * 100 + 0.5) .. "%") or ""
			loot[#loot + 1] = { item = item, note = (BossName(e)) .. rate }
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
			rows[#rows + 1] = { sortKey = ns.CharName(key, true), "stat", ns.CharName(key), (L["%s, %s, %s inside, last %s"]):format(ns.N(r.n or 0, "visit", "visits"),
				ns.N(kills, "boss kill", "boss kills"), Duration(r.time or 0), ns.DateText(r.last)) }
		end
	end
	if #rows > 0 then
		b[#b + 1] = { "banner", L["Your characters"] }
		table.sort(rows, function(x, y) return x.sortKey < y.sortKey end)
		for _, r in ipairs(rows) do b[#b + 1] = r end
	end

	-- its Wild Gambit dungeon event
	local _, def = W.DungeonArt(id, rec.name)
	if def then
		b[#b + 1] = { "banner", L["Wild Gambit event"] }
		b[#b + 1] = { "stat", def.event, def.text }
	end
	return b
end

-- a boss's tabs: the Creatures page's detail, split by its sections
local SECTIONS = {
	abilities = { [L["Abilities"]] = true },
	loot = { [L["Loot"]] = true, [L["Skinning and gathering"]] = true },
}
local function BossBlocks(id, rec, e, sub)
	local b = {}
	local npc = e.b.npc
	local p = ns.UI:GetPage("bestiary")
	local all = npc and p and p.CreatureBlocks and p:CreatureBlocks(npc)
	if sub == "other" then
		b[#b + 1] = { "banner", L["In this dungeon"] }
		b[#b + 1] = { "stat", L["Kills"], tostring(e.b.kills or 0) }
		if (e.b.wipes or 0) > 0 then b[#b + 1] = { "stat", L["Wipes"], tostring(e.b.wipes) } end
		if e.b.first then b[#b + 1] = { "stat", L["First met"], ns.CharName(e.b.first.c) .. ", " .. ns.DateText(e.b.first.t) } end
		if e.b.lastKill then b[#b + 1] = { "stat", L["Last kill"], ns.AgoText(e.b.lastKill) } end
		local c = npc and ns.Store:Get("creature", npc)
		if c then
			local tier, need = B():Tier(c)
			b[#b + 1] = { "stat", L["Research"], (B().TIERS[tier] or "?") .. ((need and need > 0 and B().TIERS[tier + 1]) and ("  ·  " .. (L["%d to %s"]):format(need, B().TIERS[tier + 1])) or "") }
			b[#b + 1] = { "slots", { { name = L["Open in Creatures"], icon = TypeIcon(c), onClick = OpenCreature(npc) } } }
		end
	end
	if not all then
		if sub ~= "other" then b[#b + 1] = { "small", L["Fight it or loot it to learn more about it."] } end
		return b
	end
	-- the blocks under each section's banner
	local cur
	local function Wanted(title)
		if sub == "other" then return not (SECTIONS.abilities[title] or SECTIONS.loot[title]) end
		return SECTIONS[sub] and SECTIONS[sub][title]
	end
	for _, blk in ipairs(all) do
		if blk[1] == "banner" then cur = Wanted(blk[2]) end
		if cur then b[#b + 1] = blk end
	end
	if #b == 0 then b[#b + 1] = { "small", L["Nothing known yet."] } end
	return b
end

local function ShowView()
	local id = state.id
	local rec = id and ns.Store:Get("instance", id)
	if not rec then
		nameText:SetText("")
		subText:SetText("")
		left:SetBlocks(nil, L["Choose a dungeon in Collection."])
		right:SetBlocks(nil, "")
		return
	end
	left:SetBlocks(LeftBlocks(id, rec), nil, true)
	local e = BossEntry(id, rec, state.boss)
	if not e then state.boss = nil state.sub = "overview" end
	for key, t in pairs(subTabs) do
		t:SetUsable(key == "overview" or e ~= nil)
		t:SetActive(state.sub == key)
	end
	nameArt:Hide()
	nameText:SetAlpha(1)
	if e then
		nameText:SetText(BossName(e))
		local c = e.b.npc and ns.Store:Get("creature", e.b.npc)
		local bits = {}
		if c then
			local lv = c.hi or c.lo
			bits[#bits + 1] = ((lv and lv > 0) and ((L["Level %s"]):format(lv) .. " ") or "") .. L["Boss"] .. (c.type and (" " .. c.type) or "")
			bits[#bits + 1] = B():TierMarkup(B():Tier(c), 12) .. " " .. (B().TIERS[B():Tier(c)] or "")
		end
		bits[#bits + 1] = KillNote(e.b.kills)
		subText:SetText(table.concat(bits, "  ·  "))
	else
		nameText:SetText(rec.name or "?")
		if W.SetNameArt and W.SetNameArt(nameArt, rec.name, 420, 34) then nameText:SetAlpha(0) end
		local sub = { DG():SizeText(id, rec) }
		local lv = Levels(id, rec)
		if lv then sub[#sub + 1] = (L["levels %s"]):format(lv) end
		local _, _, zone = DG():Info(id, rec)
		if zone then sub[#sub + 1] = zone end
		subText:SetText(table.concat(sub, "  ·  "))
	end
	if state.sub == "overview" or not e then
		right:SetBlocks(OverviewBlocks(id, rec), nil, true)
	else
		right:SetBlocks(BossBlocks(id, rec, e, state.sub), nil)
	end
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

function page:Build(parent, header)
	local search = W.Search(header, 200, function(text)
		filter = text
		page:Refresh()
	end)
	search:SetPoint("LEFT", header, "LEFT", 16, -2)
	countText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countText:SetPoint("RIGHT", header, "RIGHT", -12, -2)

	-- the two page tabs
	tabRow = CreateFrame("Frame", nil, parent)
	tabRow:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, 0)
	tabRow:SetSize(10, 27)
	pageTabs.collection = MakeTab(tabRow, L["Collection"], "Interface\\Icons\\INV_Misc_Book_10", function()
		state.tab = "collection" page:Refresh()
	end)
	pageTabs.collection:SetPoint("BOTTOMLEFT", tabRow, "BOTTOMLEFT", 0, 0)
	pageTabs.dungeon = MakeTab(tabRow, L["Dungeon"], "Interface\\Icons\\INV_Misc_Map_01", function()
		state.tab = "dungeon" page:Refresh()
	end)
	pageTabs.dungeon:SetPoint("BOTTOMLEFT", pageTabs.collection, "BOTTOMRIGHT", 2, 0)

	-- tab 1
	collection = W.Inset(parent)
	collection:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -28)
	collection:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
	scroll = W.Try("ScrollFrame", nil, collection, "UIPanelScrollFrameTemplate")
	W.SkinScroll(scroll)
	scroll:SetPoint("TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", -28, 6)
	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(600, 400)
	scroll:SetScrollChild(content)
	if W.WheelScroll then W.WheelScroll(scroll, 60) end
	scroll:SetScript("OnSizeChanged", function() if state.tab == "collection" then LayoutCollection() end end)
	collection.empty = collection:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	collection.empty:SetPoint("CENTER")
	collection.empty:SetWidth(420)
	collection.empty:SetText(L["No dungeons yet. Every dungeon and raid your characters enter becomes a card here, with its bosses as you meet them."])

	-- tab 2: the map (left) and the facts (right)
	view = CreateFrame("Frame", nil, parent)
	view:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -28)
	view:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
	left = W.Detail(view)
	left:SetPoint("TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", 0, 0)
	left:SetWidth(430)
	right = W.Detail(view, 46)
	right:SetTheme({ "Mining", "Blacksmithing" })
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, -28)
	right:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, 0)
	nameText = right.top:CreateFontString(nil, "OVERLAY")
	W.HeroFont(nameText, 24)
	nameText:SetPoint("TOPLEFT", 2, 0)
	nameText:SetPoint("RIGHT", right.top, "RIGHT", -4, 0)
	nameText:SetJustifyH("LEFT")
	subText = right.top:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	subText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -5)
	nameArt = right.top:CreateTexture(nil, "OVERLAY", nil, 2)
	nameArt:SetPoint("LEFT", nameText, "LEFT", -4, 1)
	nameArt:Hide()
	-- (0.69.0, #45) the dungeon you're in: the portal swirls behind its name
	local swirl = W.PortalSwirl(right.top, "BACKGROUND", 7)
	swirl:SetSize(180, 180)   -- (0.69.1: 20% larger)
	swirl:SetPoint("CENTER", nameText, "LEFT", 70, -6)
	local swirlHost = CreateFrame("Frame", nil, right.top)
	swirlHost:SetScript("OnUpdate", function(_, elapsed)
		local rec = state.id and ns.Store:Get("instance", state.id)
		local here = state.id and W.PortalOn() and W.IsCurrentDungeon(state.id, rec and rec.name) and state.boss == nil
		swirl:SetWanted(here and 1 or 0)
		swirl:Step(elapsed)
	end)
	-- the right pane's tabs, above it
	subRow = CreateFrame("Frame", nil, view)
	subRow:SetPoint("BOTTOMLEFT", right, "TOPLEFT", 10, -1)
	subRow:SetSize(10, 27)
	local x = 0
	for _, spec in ipairs({
		{ "overview", L["Overview"], "Interface\\Icons\\INV_Misc_Book_09" },
		{ "abilities", L["Abilities"], "Interface\\Icons\\Spell_Holy_MagicalSentry" },
		{ "loot", L["Loot"], "Interface\\Icons\\INV_Misc_Bag_10" },
		{ "other", L["Other"], "Interface\\Icons\\INV_Misc_Note_01" },
	}) do
		local key = spec[1]
		local t = MakeTab(subRow, spec[2], spec[3], function() state.sub = key ShowView() end)
		t:SetPoint("BOTTOMLEFT", subRow, "BOTTOMLEFT", x, 0)
		x = x + t:GetWidth() + 2
		subTabs[key] = t
	end
	page:Refresh()
end

function page:Refresh()
	if not collection then return end
	local found = 0
	for _ in pairs(ns.Store:Shown("instance")) do found = found + 1 end
	countText:SetText((L["Found %d of %d dungeons and raids"]):format(found, TotalDungeons()))
	local rec = state.id and ns.Store:Get("instance", state.id)
	pageTabs.dungeon:Set(rec and rec.name or L["Dungeon"])
	pageTabs.dungeon:SetUsable(rec ~= nil)
	if state.tab == "dungeon" and not rec then state.tab = "collection" end
	pageTabs.collection:SetActive(state.tab == "collection")
	pageTabs.dungeon:SetActive(state.tab == "dungeon")
	collection:SetShown(state.tab == "collection")
	view:SetShown(state.tab == "dungeon")
	if state.tab == "collection" then LayoutCollection() else ShowView() end
	if ns.UI.UpdateBack then ns.UI:UpdateBack() end
end

-- (0.68.1) the window's Back button: from a dungeon back to the collection
page.backText = L["To the dungeon collection."]
function page:CanGoBack() return state.tab == "dungeon" end
function page:GoBack()
	state.tab = "collection"
	self:Refresh()
end

function page:ShowDungeon(id)
	ns.UI:Open("dungeons")
	if state.id ~= id then state.boss, state.floor, state.floorBoss = nil, nil, nil state.sub = "overview" end
	state.id = id
	state.tab = "dungeon"
	self:Refresh()
end

ns:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
	if W.waitingItems and state.tab == "dungeon" and ns.UI:IsShown() and ns.UI:Current() == "dungeons" then
		W.waitingItems = false
		C_Timer.After(0.2, function() if state.tab == "dungeon" then ns.UI:Redraw(ShowView) end end) -- (#53: keeps the scroll)
	end
end)

ns:On("RESET", function() state.id, state.boss, state.tab, state.sub, state.floor, state.floorBoss = nil, nil, "collection", "overview", nil, nil if collection then page:Refresh() end end)

ns.UI:RegisterPage(page)
