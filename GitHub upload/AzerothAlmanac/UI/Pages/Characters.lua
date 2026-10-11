-- Characters page: every character on the account. Since 0.18.0 it also holds what the separate
-- My Characters window showed (QoL\InventoryWindow.lua draws those parts):
--   list:   the class's painted crest (Media\Crest_<CLASS>, 2026-10-10) with the faction banner,
--           name and level, race / class / zone, gold, rested XP, last played. Right-click: hide or
--           remove a character. "Show hidden characters" under the list.
--   header: search across every character's items, account gold.
--   plate:  portrait (live model for you), name, class line, gold, rest, last location (click: map),
--           hearthstone, data freshness, XP and rested XP bar.
--   tabs:   Story (levels, first visits), Gear, Bags, Bank, Auctions, Professions, each with a game icon;
--           (#46) Journey: the Journal's time lapse at full size for the selected character (or everyone).
local JOURNEY_TAB = { key = "journey", label = "Journey", icon = "Interface\\Icons\\INV_Misc_Map_01" }

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local page = { key = "characters", title = L["Characters"], icon = "Interface\\AddOns\\AzerothAlmanac\\Media\\Tab_Characters", order = 2 }   -- (the painted journal icon)
local list, detail, plate, invScroll, invContent, tabRow, searchBox, goldText, summaryText, root
local journeyPane -- (#46)
local tabs = {}
local state = { tab = "story", search = "", showHidden = false }
local pendingDraw
local built = false   -- Refresh waits until Build has made everything

local PVP = { Alliance = "Interface\\TargetingFrame\\UI-PVP-Alliance", Horde = "Interface\\TargetingFrame\\UI-PVP-Horde" }
local FACTION_BY_RACE = { Human = "Alliance", Dwarf = "Alliance", NightElf = "Alliance", Gnome = "Alliance",
	Orc = "Horde", Scourge = "Horde", Tauren = "Horde", Troll = "Horde" }

local function IW() return ns.QoL and ns.QoL.InventoryWindow end

local function ClassColor(classFile)
	local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if c and c.r then return c.r, c.g, c.b end
	return 0.62, 0.5, 0.24
end

local function Faction(c)
	return c and (c.faction or FACTION_BY_RACE[c.raceFile or ""])
end

---------------------------------------------------------------------------
-- Story tab (2026-10-10, Shannon: pictures, not a wall of text)
--   The hero row: three medallions, the level (a gold ring round the number), the class (its painted
--   crest in the class colour) and the faction (its banner), with race and class, the faction and
--   when they joined the Almanac under them; a strip of their adventure under that (creatures slain,
--   quests done, zones, dungeons), each with its painting. Then what they found first, as cards with
--   the Almanac's paintings (click: their journal of that kind). No realm (WoW Forever has none: the
--   second name is a surname), nothing the plate above already says (where they are, when played),
--   no level list.
---------------------------------------------------------------------------

-- the classes with a painted crest (Media\\Crest_<CLASS>): the list and the hero row
local CREST = { DRUID = true, HUNTER = true, MAGE = true, PALADIN = true, PRIEST = true,
	ROGUE = true, SHAMAN = true, WARLOCK = true, WARRIOR = true }
local MEDIA = "Interface\\AddOns\\AzerothAlmanac\\Media\\"
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
-- what they found first, in the Journal's order (kind, label)
local FIRSTS = {
	{ "zone", L["Zones"] }, { "subzone", L["Places"] }, { "instance", L["Dungeons"] }, { "creature", L["Creatures"] },
	{ "item", L["Items"] }, { "quest", L["Quests"] }, { "merchant", L["Merchants"] }, { "trainer", L["Trainers"] },
	{ "townsfolk", L["People"] }, { "flight", L["Flight paths"] }, { "node", L["Gathering"] }, { "fishing", L["Fishing waters"] },
	{ "mailbox", L["Mailboxes"] },
}

local hero
local function Medallion(parent, size)
	local m = CreateFrame("Frame", nil, parent)
	m:SetSize(size, size)
	m.ring = m:CreateTexture(nil, "BACKGROUND")
	m.ring:SetTexture(CIRCLE)
	m.ring:SetPoint("TOPLEFT", -3, 3)
	m.ring:SetPoint("BOTTOMRIGHT", 3, -3)
	m.disc = m:CreateTexture(nil, "BORDER")
	m.disc:SetTexture(CIRCLE)
	m.disc:SetAllPoints()
	m.disc:SetVertexColor(0.08, 0.06, 0.04, 1)
	m.icon = m:CreateTexture(nil, "ARTWORK")
	m.icon:SetAllPoints()
	if m.CreateMaskTexture then
		m.mask = m:CreateMaskTexture()
		m.mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		m.mask:SetAllPoints(m.icon)
		m.icon:AddMaskTexture(m.mask)
	end
	m.big = m:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	m.big:SetPoint("CENTER", 0, 1)
	m.label = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	m.label:SetPoint("TOP", m, "BOTTOM", 0, -8)
	m.sub = m:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	m.sub:SetPoint("TOP", m.label, "BOTTOM", 0, -2)
	return m
end

local function Hero(parent)
	if hero then return hero end
	hero = CreateFrame("Frame", nil, parent)
	hero:SetSize(10, 10)
	hero.meds = { Medallion(hero, 64), Medallion(hero, 64), Medallion(hero, 64) }
	hero.chips = {}
	for i = 1, 4 do
		local c = CreateFrame("Frame", nil, hero)
		c:SetSize(10, 30)
		c.bg = c:CreateTexture(nil, "BACKGROUND")
		c.bg:SetAllPoints()
		c.bg:SetColorTexture(0, 0, 0, 0.35)
		c.edge = c:CreateTexture(nil, "BACKGROUND", nil, -1)
		c.edge:SetPoint("TOPLEFT", -1, 1)
		c.edge:SetPoint("BOTTOMRIGHT", 1, -1)
		c.edge:SetColorTexture(0.45, 0.35, 0.18, 0.8)
		c.icon = c:CreateTexture(nil, "ARTWORK")
		c.icon:SetSize(26, 26)
		c.icon:SetPoint("LEFT", 2, 0)
		c.num = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		c.num:SetPoint("LEFT", c.icon, "RIGHT", 6, 5)
		c.what = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		c.what:SetPoint("TOPLEFT", c.num, "BOTTOMLEFT", 0, -1)
		hero.chips[i] = c
	end
	return hero
end

-- the hero row's contents for one character; returns the frame and its height for a width
local function FillHero(parent, key, c)
	local h = Hero(parent)
	local level, crest, faction = h.meds[1], h.meds[2], h.meds[3]
	-- level: the number in a gold ring
	level.ring:SetVertexColor(1, 0.78, 0.25)
	level.icon:Hide()
	level.big:SetText(tostring(c.level or "?"))
	level.label:SetText(L["Level"])
	level.sub:SetText("")
	-- class: the crest in the class colour (or the game's class circle)
	local r, g, b = ClassColor(c.classFile)
	crest.ring:SetVertexColor(r, g, b)
	crest.icon:Show()
	crest.big:SetText("")
	if c.classFile and CREST[c.classFile] then
		crest.icon:SetTexture(MEDIA .. "Crest_" .. c.classFile)
		crest.icon:SetTexCoord(0.13, 0.87, 0.13, 0.87)
	else
		local coords = c.classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[c.classFile]
		crest.icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
		if coords then crest.icon:SetTexCoord(unpack(coords)) end
	end
	crest.label:SetText(("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, c.class or "?"))
	crest.sub:SetText(c.race or "")
	-- faction: its banner
	local f = Faction(c)
	faction.ring:SetVertexColor(f == "Horde" and 0.75 or 0.25, f == "Horde" and 0.15 or 0.45, f == "Horde" and 0.1 or 0.85)
	faction.big:SetText("")
	faction.icon:Show()
	if not W.SetFactionBadge(faction.icon, f) then faction.icon:Show() W.SetIcon(faction.icon, { "INV_Misc_QuestionMark" }) end
	faction.label:SetText(f and L[f] or "?")
	faction.sub:SetText((L["joined %s"]):format(ns.DateText(c.firstSeen)))
	-- the adventure strip
	local M = ns.Milestones
	local st = M and M.Stats and M:Stats(key) or {}
	local chips = {
		{ W.KindArt("creature"), st.kills or 0, L["slain"] },
		{ W.KindArt("quest"), ns.Quests:DoneCount(key) or 0, L["quests done"] },
		{ W.KindArt("zone"), st.zone or 0, L["zones"] },
		{ W.KindArt("instance"), st.instance or 0, L["dungeons"] },
	}
	for i, ch in ipairs(chips) do
		local chip = h.chips[i]
		chip.icon:SetTexture(ch[1])
		chip.num:SetText(BreakUpLargeNumbers and BreakUpLargeNumbers(ch[2]) or tostring(ch[2]))
		chip.what:SetText(ch[3])
	end
	return h, function(width)
		-- the medallions spread across the width; the strip under them, four equal chips
		local step = width / 3
		for i, m in ipairs(h.meds) do
			m:ClearAllPoints()
			m:SetPoint("TOP", h, "TOPLEFT", step * (i - 0.5), -8)
		end
		local cw = math.floor((width - 3 * 6) / 4)
		for i, chip in ipairs(h.chips) do
			chip:ClearAllPoints()
			chip:SetSize(cw, 32)
			chip:SetPoint("TOPLEFT", h, "TOPLEFT", (i - 1) * (cw + 6), -(8 + 64 + 46))
		end
		h:SetSize(width, 8 + 64 + 46 + 32 + 4)
		return 8 + 64 + 46 + 32 + 4
	end
end

local function Describe(item)
	local key, c = item.key, item.c
	local b = {}
	local h, height = FillHero(detail and detail.scroll or UIParent, key, c)
	b[#b + 1] = { "frame", h, height }
	-- what they found first: a card each, with its painting; click for their journal of that kind
	local cards = {}
	for _, k in ipairs(FIRSTS) do
		local kind = k[1]
		local n = 0
		for _, rec in pairs(ns.db.found[kind] or {}) do if rec.b == key then n = n + 1 end end
		if n > 0 then
			cards[#cards + 1] = { name = k[2], icon = W.KindArt(kind), note = (L["%s found first"]):format(BreakUpLargeNumbers and BreakUpLargeNumbers(n) or n),
				tip = (L["%s found these before any of your other characters."]):format(ns.CharName(key, true)) .. "\n" .. L["Click to see them in their journal."],
				onClick = function()
					local p = ns.UI:GetPage("journal")
					ns.UI:Open("journal")
					if p then
						if p.SetCharacter then p:SetCharacter(key) end
						if p.SetKind then p:SetKind(kind) end
					end
				end }
		end
	end
	b[#b + 1] = { "gap", 6 }
	if #cards > 0 then
		b[#b + 1] = { "slots", cards, cards = true }
	else
		b[#b + 1] = { "small", L["Nothing found first yet: what this character finds before any other shows here."] }
	end
	return b
end

---------------------------------------------------------------------------
-- List rows
---------------------------------------------------------------------------

-- the default round row, grown to three lines with a faction banner on the portrait
-- (the list resets the name and right-hand text anchors before every update, so they're set each time)
local function DressRow(row)
	row.text:ClearAllPoints()
	-- a taller row (60) with the portrait kept at 46, so the rows breathe and the lines don't touch
	row.icon:SetSize(46, 46)
	row.text:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, 1)
	row.text:SetPoint("RIGHT", row, "RIGHT", -64, 0)
	row.text:SetWordWrap(false)
	row.right:ClearAllPoints()
	row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -8)
	if row.dressed then return end
	row.dressed = true
	row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.sub:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -4)
	row.sub:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	row.sub:SetJustifyH("LEFT")
	row.sub:SetWordWrap(false)
	row.money = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.money:SetPoint("TOPLEFT", row.sub, "BOTTOMLEFT", 0, -4)
	row.money:SetJustifyH("LEFT")
	row.rested = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.rested:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 9)
	row.rested:SetJustifyH("RIGHT")
	row.badge = row:CreateTexture(nil, "OVERLAY", nil, 3)
	row.badge:SetSize(20, 20)
	row.badge:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 7, -4)
end

-- (Shannon, 2026-10-10) the painted class crests, as in the Journal's First to find, for every
-- character (you too); the game's portrait and class circles only for a class without a crest
local function SetFace(texture, key, c, ringOwner)
	if ringOwner and ringOwner.SetRing then ringOwner:SetRing(ClassColor(c.classFile)) end
	texture:SetDesaturated(false)
	if c.classFile and CREST[c.classFile] then
		texture:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Crest_" .. c.classFile)
		texture:SetTexCoord(0.13, 0.87, 0.13, 0.87) -- (the crest's own painted rim stays under the ring)
		return
	end
	if key == ns.CharKey() and SetPortraitTexture then
		texture:SetTexCoord(0, 1, 0, 1)
		SetPortraitTexture(texture, "player")
		return
	end
	local coords = c.classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[c.classFile]
	if coords then
		texture:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
		texture:SetTexCoord(unpack(coords))
	else
		W.SetIcon(texture, { "INV_Misc_QuestionMark" })
		texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
end

local function UpdateRow(row, item)
	DressRow(row)
	local c, inv = item.c, item.inv
	SetFace(row.icon, item.key, c, row)
	local f = Faction(c)
	if PVP[f] then
		row.badge:SetTexture(PVP[f])
		row.badge:SetTexCoord(0, 0.625, 0, 0.625)
		row.badge:Show()
	else
		row.badge:Hide()
	end
	row.text:SetText(ns.CharName(item.key) .. "  |cffffffff" .. ((inv and inv.level) or c.level or "?") .. "|r"
		.. (item.key == ns.CharKey() and "  |cff999999" .. L["(you)"] .. "|r" or ""))
	local zone = (inv and inv.zone) or c.zone
	row.sub:SetText((c.race or "") .. " " .. (c.class or "") .. (zone and ("  |cff808080- " .. zone .. "|r") or ""))
	local iw = IW()
	row.money:SetText(inv and iw and iw.Money(inv.money) or "")
	row.right:SetText("|cff999999" .. ns.AgoText(c.lastSeen) .. "|r")
	local share = inv and iw and select(2, iw:Rested(inv))
	row.rested:SetText(share and share > 0 and ("|cff80b3ff" .. L["%d%% rested"] .. "|r"):format(math.floor(share * 100 + 0.5)) or "")
	row:SetAlpha(item.hidden and 0.45 or 1)
end

---------------------------------------------------------------------------
-- Tabs under the name plate: the Settings panel's own tab art, an icon and a label
---------------------------------------------------------------------------

local function MakeTab(parent, spec)
	local b = CreateFrame("Button", nil, parent)
	b.spec = spec
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
	b.icon:SetTexture(spec.icon)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.text:SetPoint("LEFT", b.icon, "RIGHT", 5, 0)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetPoint("TOPLEFT", 4, -3)
	hl:SetPoint("BOTTOMRIGHT", -4, 0)
	hl:SetColorTexture(1, 0.85, 0.4, 0.08)
	function b:SetLabel(text)
		self.text:SetText(text)
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
	b:SetScript("OnClick", function(self)
		state.tab = self.spec.key
		state.search = ""
		if searchBox then searchBox:SetText("") searchBox:ClearFocus() end
		if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
		page:Refresh()
	end)
	return b
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

function page:Build(parent, header)
	root = parent
	local iw = IW()

	searchBox = W.Search(header, 220, function(text)
		-- the box reports a change while the page is still being built; only real typing redraws
		text = text or ""
		if text == state.search then return end
		state.search = text
		page:Refresh()
	end)
	searchBox:SetPoint("LEFT", header, "LEFT", 22, -2)
	if type(searchBox.Instructions) == "table" then searchBox.Instructions:SetText(L["Search all characters' items"]) end
	goldText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	goldText:SetPoint("RIGHT", header, "RIGHT", -16, -2)

	local left = W.Inset(parent)
	left:SetPoint("TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", 0, 0)
	left:SetWidth(270)
	list = W.List(left, {
		rowHeight = 60,
		round = true,
		update = UpdateRow,
		onClick = function(item, _, mouse)
			if mouse == "RightButton" then
				if item.inv and iw then iw:Menu(list, item.inv) end
				return
			end
			page:Refresh()
		end,
	})
	list:SetPoint("TOPLEFT", left, "TOPLEFT", 0, 0)
	list:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", 0, 30)
	local hidden = W.Check(left, L["Show hidden characters (right-click to hide)"],
		function() return state.showHidden end, function(v) state.showHidden = v page:Refresh() end)
	hidden:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 8, 4)

	-- the name plate; the tabs sit in a strip between it and the body
	local TOP = 112
	detail = W.Detail(parent, TOP)
	detail:SetTheme({ "Tailoring", "Blacksmithing" })
	detail:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
	detail:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
	if iw and iw.BuildHeader then plate = iw:BuildHeader(detail.top) end
	summaryText = detail.top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	summaryText:SetJustifyH("RIGHT")
	if plate and plate.updated then summaryText:SetPoint("TOPRIGHT", plate.updated, "BOTTOMRIGHT", 0, -4)
	else summaryText:SetPoint("TOPRIGHT", detail.top, "TOPRIGHT", 0, -48) end

	local STRIP = 30
	if detail.body and detail.card then
		detail.body:ClearAllPoints()
		detail.body:SetPoint("TOPLEFT", detail.card, "BOTTOMLEFT", 0, -STRIP)
		detail.body:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", 0, 0)
		detail.scroll:ClearAllPoints()
		detail.scroll:SetPoint("TOPLEFT", detail.body, "TOPLEFT", 12, -12)
		detail.scroll:SetPoint("BOTTOMRIGHT", detail.body, "BOTTOMRIGHT", -30, 12)
	end
	tabRow = CreateFrame("Frame", nil, detail)
	tabRow:SetPoint("BOTTOMLEFT", detail.body or detail, "TOPLEFT", 10, -1)
	tabRow:SetSize(10, 27)
	tabRow:SetFrameLevel(detail.scroll:GetFrameLevel() + 2)
	local x = 0
	local specs = {}
	for _, spec in ipairs(iw and iw.TABS or { { key = "story", label = "Story", icon = "Interface\\Icons\\INV_Misc_Book_09" } }) do specs[#specs + 1] = spec end
	specs[#specs + 1] = JOURNEY_TAB
	for i, spec in ipairs(specs) do
		local t = MakeTab(tabRow, spec)
		t:SetLabel(L[spec.label])
		t:SetPoint("BOTTOMLEFT", tabRow, "BOTTOMLEFT", x, 0)
		x = x + t:GetWidth() + 2
		tabs[i] = t
	end

	-- the inventory tabs scroll in the same place as the story
	invScroll = W.Try("ScrollFrame", nil, detail, "UIPanelScrollFrameTemplate")
	W.SkinScroll(invScroll)
	invScroll:SetPoint("TOPLEFT", detail.scroll, "TOPLEFT", 0, 0)
	invScroll:SetPoint("BOTTOMRIGHT", detail.scroll, "BOTTOMRIGHT", 0, 0)
	invScroll:SetFrameLevel(detail.scroll:GetFrameLevel())
	invContent = CreateFrame("Frame", nil, invScroll)
	invContent:SetSize(10, 10)
	invScroll:SetScrollChild(invContent)
	invScroll:Hide()

	-- (#46) the Journey tab: the time lapse filling the body
	if W.JourneyPane then
		journeyPane = W.JourneyPane(detail, {
			full = true,
			onPick = function(e)
				ns.UI:Open("journal")
				local j = ns.UI:GetPage("journal")
				if j and j.OpenEntry then j:OpenEntry(e) end
			end,
		})
		journeyPane:SetPoint("TOPLEFT", detail.body or detail, "TOPLEFT", 6, -6)
		journeyPane:SetPoint("BOTTOMRIGHT", detail.body or detail, "BOTTOMRIGHT", -6, 6)
		journeyPane:SetFrameLevel(detail.scroll:GetFrameLevel() + 1)
		journeyPane:Hide()
	end

	if iw then
		iw.onChange = function()
			if pendingDraw then return end
			pendingDraw = true
			C_Timer.After(0.2, function() pendingDraw = false if page:IsShownNow() then page:Refresh() end end)
		end
		iw.onRemoved = function(invKey)
			for key, c in pairs(ns.db.chars) do
				local inv = iw:Find(key, c)
				if (inv and inv.key == invKey) or (not inv and key ~= ns.CharKey() and invKey and invKey:match("^([^-]+)") == c.name) then
					if key ~= ns.CharKey() then ns.db.chars[key] = nil end
				end
			end
			page:Refresh()
		end
	end
	built = true
end

function page:IsShownNow() return built and root and root:IsVisible() end

-- a stand-in record for a character the inventory has nothing on yet (the plate still shows them)
local function Stub(item)
	local c = item.c
	return { key = item.key, name = c.name or item.key, class = c.classFile, race = c.race, raceFile = c.raceFile,
		sex = c.sex, level = c.level, realm = c.realm, faction = c.faction, zone = c.zone }
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

local function Items()
	local iw = IW()
	local out = {}
	for _, item in ipairs(ns.Characters:List()) do
		item.inv = iw and iw:Find(item.key, item.c) or nil
		item.hidden = item.inv and iw:IsHidden(item.inv.key) or false
		if state.showHidden or not item.hidden then out[#out + 1] = item end
	end
	return out
end

local function DrawInventory(item)
	local iw = IW()
	local width = (detail.scroll:GetWidth() or 0)
	if width < 50 then
		-- first show: the frames have no size yet; draw a moment later
		C_Timer.After(0, function() if page:IsShownNow() then page:Refresh() end end)
		return
	end
	local h
	if #state.search >= 2 then
		h = iw:DrawSearch(invContent, state.search, width - 8)
	else
		h = iw:Draw(invContent, item.inv, state.tab, width - 8, summaryText)
	end
	invContent:SetSize(width - 8, math.max(10, h or 10))
end

function page:Refresh()
	if not built then return end
	local iw = IW()
	local data = Items()
	list:SetData(data)
	local sel = list:Selected()
	local found
	for _, item in ipairs(data) do
		if sel and item.key == sel.key then found = item end
	end
	if not found then
		for _, item in ipairs(data) do if item.key == ns.CharKey() then found = item end end
	end
	found = found or data[1]
	goldText:SetText(iw and (L["Account gold: %s"]):format(iw.Money(iw:TotalMoney())) or "")
	if not found then
		detail:SetBlocks(nil, L["No characters yet."])
		return
	end
	list:Select(found)
	if plate and iw then iw:SetHeader(plate, found.inv or Stub(found)) end
	summaryText:SetText("")

	local searching = #state.search >= 2
	for _, t in ipairs(tabs) do
		local label = L[t.spec.label]
		if t.spec.key == "auctions" and found.inv and found.inv.auctions then
			label = label .. (" (%d)"):format(#found.inv.auctions.items)
		end
		t:SetLabel(label)
		t:SetActive(not searching and t.spec.key == state.tab)
	end
	local x = 0
	for _, t in ipairs(tabs) do
		t:ClearAllPoints()
		t:SetPoint("BOTTOMLEFT", tabRow, "BOTTOMLEFT", x, 0)
		x = x + t:GetWidth() + 2
	end

	if state.tab == "journey" and not searching and journeyPane then
		invScroll:Hide()
		if iw then iw:Draw(invContent, nil, "none", 10) end
		detail.scroll:Hide()
		local changed = journeyPane.charKey ~= found.key
		journeyPane.charKey = found.key
		journeyPane:SetCharacter(found.key)
		if not journeyPane:IsShown() then journeyPane:Show() -- (its OnShow shows today's journey, Play glowing)
		elseif changed then journeyPane:Refresh(false) end
		return
	end
	if journeyPane then journeyPane:Hide() end
	if state.tab == "story" and not searching then
		invScroll:Hide()
		if iw then iw:Draw(invContent, nil, "none", 10) end   -- releases the inventory frames
		detail.scroll:Show()
		detail:SetBlocks(Describe(found))
	else
		detail.scroll:Hide()
		invScroll:Show()
		if iw then DrawInventory(found) end
	end
end

-- (#46) /aa journey: the Journey tab
function page:ShowJourney()
	state.tab = "journey"
	state.search = ""
	if searchBox then searchBox:SetText("") end
	self:Refresh()
end

-- /aa inv, the key binding and the minimap menu: open on a character (inventory key) and tab
function page:ShowInventory(invKey, tab)
	state.tab = tab or "bags"
	state.search = ""
	if searchBox then searchBox:SetText("") end
	if invKey and list then
		for _, item in ipairs(Items()) do
			if item.inv and item.inv.key == invKey then list:Select(item) end
		end
	end
	self:Refresh()
end

ns.UI:RegisterPage(page)
