-- Characters page: every character on the account. Since 0.18.0 it also holds what the separate
-- My Characters window showed (QoL\InventoryWindow.lua draws those parts):
--   list:   portrait (yours from the game, the others' class emblem, both with the faction banner),
--           name and level, race / class / zone, gold, rested XP, last played. Right-click: hide or
--           remove a character. "Show hidden characters" under the list.
--   header: search across every character's items, account gold.
--   plate:  portrait (live model for you), name, class line, gold, rest, last location (click: map),
--           hearthstone, data freshness, XP and rested XP bar.
--   tabs:   Story (levels, firsts), Gear, Bags, Bank, Auctions, Professions, each with a game icon.

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local page = { key = "characters", title = L["Characters"], icon = W.KIND.character.icon, order = 2, portraitUnit = "player" }   -- the tab shows you
local list, detail, plate, invScroll, invContent, tabRow, searchBox, goldText, summaryText, root
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
-- Story tab (what the page always showed)
---------------------------------------------------------------------------

local function Describe(item)
	local key, c = item.key, item.c
	local b = { { "banner", L["General"] } }
	b[#b + 1] = { "stat", L["Level"], tostring(c.level or "?") }
	b[#b + 1] = { "stat", L["Race and class"], (c.race or "?") .. " " .. (c.class or "") }
	b[#b + 1] = { "stat", L["Faction"], c.faction or "?" }
	b[#b + 1] = { "stat", L["Realm"], c.realm or "?" }
	b[#b + 1] = { "stat", L["Joined the Almanac"], ns.DateText(c.firstSeen) }
	b[#b + 1] = { "stat", L["Last played"], ns.AgoText(c.lastSeen) }
	b[#b + 1] = { "stat", L["Last seen in"], c.zone or "?" }
	b[#b + 1] = { "stat", L["Quests done"], tostring(ns.Quests:DoneCount(key)) }

	b[#b + 1] = { "banner", L["First to discover"] }
	local any = false
	local kinds = {}
	for kind in pairs(ns.db.found) do kinds[#kinds + 1] = kind end
	table.sort(kinds)
	for _, kind in ipairs(kinds) do
		local n = 0
		for _, rec in pairs(ns.db.found[kind]) do if rec.b == key then n = n + 1 end end
		if n > 0 then
			any = true
			local k = W.KIND[kind]
			b[#b + 1] = { "stat", k and k.label or kind, tostring(n) }
		end
	end
	if not any then b[#b + 1] = { "small", L["Nothing yet."] } end

	b[#b + 1] = { "banner", L["Levels"] }
	local levels = {}
	for lvl, info in pairs(c.levels or {}) do levels[#levels + 1] = { lvl = lvl, info = info } end
	table.sort(levels, function(x, y) return x.lvl > y.lvl end)
	if #levels == 0 then
		b[#b + 1] = { "small", L["Levels gained from now on are recorded here, with where you were."] }
	else
		for _, l in ipairs(levels) do
			local place = (l.info.s and l.info.s ~= "") and (l.info.s .. ", " .. (l.info.z or "")) or (l.info.z or "?")
			b[#b + 1] = { "stat", (L["Level %d"]):format(l.lvl), place .. "  |cff999999" .. ns.DateText(l.info.t) .. "|r" }
		end
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

local function SetFace(texture, key, c, ringOwner)
	if ringOwner and ringOwner.SetRing then ringOwner:SetRing(ClassColor(c.classFile)) end
	texture:SetDesaturated(false)
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
	for i, spec in ipairs(iw and iw.TABS or { { key = "story", label = "Story", icon = "Interface\\Icons\\INV_Misc_Book_09" } }) do
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
