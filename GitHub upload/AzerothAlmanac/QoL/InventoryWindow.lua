-- Ported from Plus Everything (same author) for Azeroth Almanac's quality-of-life helpers.
-- Inventory window (/aa inv): every character on the account with their bags, bank, gear,
-- mailbox, auctions and professions, a search across all of them, and portraits: the game's
-- live 3D model for the character you're playing, the class emblem for the others.

local _, A = ...
local ns = A.QoL
local IW = ns:NewModule("InventoryWindow")
local INV -- ns.Inventory, set on login

local WIN_W, WIN_H = 980, 640
local SIDE_W = 250
local MAIN_X = 12 + SIDE_W + 12
local MAIN_W = WIN_W - MAIN_X - 12
local SLOT = 38
local GAP = 4
local ROW_H = 54

local WHITE = "Interface\\Buttons\\WHITE8X8"
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local GOLD = { 1, 0.82, 0.25 }
local REST_ICON = "Interface\\CharacterFrame\\UI-StateIcon" -- the player frame's resting "Zzz"
local REST_COORDS = { 0, 0.5, 0, 0.421875 }
local LOCATION_ICON = "Interface\\Icons\\INV_Misc_Map_01"
local HEARTH_ICON = "Interface\\Icons\\INV_Misc_Rune_01"
local ICON_TRIM = { 0.08, 0.92, 0.08, 0.92 }
local EMPTY_SLOT = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
local BORDER = "Interface\\Common\\WhiteIconFrame"

local TABS = {
	{ key = "bags", label = "Bags" },
	{ key = "bank", label = "Bank" },
	{ key = "gear", label = "Gear" },
	{ key = "mail", label = "Mail" },
	{ key = "auctions", label = "Auctions" },
	{ key = "professions", label = "Professions" },
}

-- Paper-doll layout: left column, right column, weapons along the bottom.
local GEAR_LEFT = { "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "ShirtSlot", "TabardSlot", "WristSlot" }
local GEAR_RIGHT = { "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot" }
local GEAR_BOTTOM = { "MainHandSlot", "SecondaryHandSlot", "RangedSlot", "AmmoSlot" }

local PROFESSION_ICONS = {
	[171] = "Trade_Alchemy", [164] = "Trade_BlackSmithing", [333] = "Trade_Engraving", [202] = "Trade_Engineering",
	[182] = "Trade_Herbalism", [165] = "Trade_LeatherWorking", [186] = "Trade_Mining", [393] = "INV_Misc_Pelt_Wolf_01",
	[197] = "Trade_Tailoring", [185] = "INV_Misc_Food_15", [129] = "Spell_Holy_SealOfSacrifice", [356] = "Trade_Fishing",
	[762] = "Ability_Mount_RidingHorse",
}

local frame
local state = { selected = nil, tab = "bags", search = "", showHidden = false }
local pools = {}
local pending

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function Backdrop(f, bg, border)
	f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	f:SetBackdropColor(unpack(bg))
	f:SetBackdropBorderColor(unpack(border))
end

local function Money(copper)
	copper = math.floor((copper or 0) + 0.5)
	return GetMoneyString and GetMoneyString(copper, true) or GetCoinTextureString(copper)
end

local function Number(n)
	n = math.floor((n or 0) + 0.5)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

local function Ago(t)
	if not t then return "never" end
	local s = time() - t
	if s < 90 then return "just now" end
	if s < 3600 then return ("%dm ago"):format(math.floor(s / 60)) end
	if s < 86400 then return ("%dh ago"):format(math.floor(s / 3600)) end
	return ("%dd ago"):format(math.floor(s / 86400))
end

local function Text(parent, font, size, flags, template)
	local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
	if font then fs:SetFont(font, size, flags or "") end
	fs:SetJustifyH("LEFT")
	return fs
end

local function Pool(name, parent, make)
	local pool = pools[name]
	if not pool then pool = { used = 0, frames = {} } pools[name] = pool end
	pool.parent, pool.make = parent, make
	return pool
end

local function Get(pool)
	pool.used = pool.used + 1
	local f = pool.frames[pool.used]
	if not f then
		f = pool.make(pool.parent)
		pool.frames[pool.used] = f
	end
	f:Show()
	return f
end

local function ReleaseAll()
	for _, pool in pairs(pools) do
		for i = 1, #pool.frames do pool.frames[i]:Hide() end
		pool.used = 0
	end
end

local function QualityColor(quality)
	local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

local function Refresh() if IW.Refresh then IW:Refresh() end end

-- Item info may still be loading; redraw once it arrives.
local function WhenLoaded(item)
	local id = INV.ItemID(item)
	if id and Item and Item.CreateFromItemID then
		Item:CreateFromItemID(id):ContinueOnItemLoad(function()
			if not pending then
				pending = true
				C_Timer.After(0.2, function() pending = false Refresh() end)
			end
		end)
	end
end

---------------------------------------------------------------------------
-- Portraits
---------------------------------------------------------------------------

local RACE_ATLAS = { Scourge = "undead", NightElf = "nightelf", BloodElf = "bloodelf", HighmountainTauren = "highmountaintauren" }

-- For characters saved before the faction was recorded.
local FACTION_BY_RACE = {
	Human = "Alliance", Dwarf = "Alliance", NightElf = "Alliance", Gnome = "Alliance",
	Orc = "Horde", Scourge = "Horde", Tauren = "Horde", Troll = "Horde",
}

local function SetClassIcon(texture, c) return ns.SetClassIcon(texture, c.class) end

-- The live portrait for the character you're playing; race art (or the class icon) for the rest.
local function SetPortrait(texture, c)
	texture:SetTexCoord(0, 1, 0, 1)
	texture:SetDesaturated(false)
	if c.key == INV:Me().key and SetPortraitTexture then
		SetPortraitTexture(texture, "player")
		return
	end
	local race = c.raceFile and (RACE_ATLAS[c.raceFile] or c.raceFile:lower())
	local gender = c.sex == 3 and "female" or "male"
	if race and C_Texture and C_Texture.GetAtlasInfo then
		for _, pattern in ipairs({ "raceicon128-%s-%s", "raceicon-%s-%s" }) do
			local atlas = pattern:format(race, gender)
			if C_Texture.GetAtlasInfo(atlas) then
				texture:SetAtlas(atlas)
				return
			end
		end
	end
	if c.raceFile then
		texture:SetTexture(("Interface\\CharacterFrame\\TemporaryPortrait-%s-%s"):format(c.sex == 3 and "Female" or "Male", c.raceFile))
		return
	end
	local coords = c.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[c.class]
	if coords then
		texture:SetTexture("Interface\\WorldStateFrame\\Icons-Classes")
		texture:SetTexCoord(unpack(coords))
	end
end

-- A round portrait inside a class-colored ring, with a soft glow when selected.
local function MakePortrait(parent, size)
	local p = CreateFrame("Frame", nil, parent)
	p:SetSize(size, size)
	p.glow = p:CreateTexture(nil, "BACKGROUND", nil, -1)
	p.glow:SetTexture(CIRCLE)
	p.glow:SetBlendMode("ADD")
	p.glow:SetPoint("CENTER")
	p.glow:SetSize(size * 1.35, size * 1.35)
	p.ring = p:CreateTexture(nil, "BACKGROUND")
	p.ring:SetTexture(CIRCLE)
	p.ring:SetAllPoints()
	p.inner = p:CreateTexture(nil, "BORDER")
	p.inner:SetTexture(CIRCLE)
	p.inner:SetPoint("TOPLEFT", 2, -2)
	p.inner:SetPoint("BOTTOMRIGHT", -2, 2)
	p.inner:SetVertexColor(0.05, 0.04, 0.03)
	p.art = p:CreateTexture(nil, "ARTWORK")
	p.art:SetPoint("TOPLEFT", 3, -3)
	p.art:SetPoint("BOTTOMRIGHT", -3, 3)
	local mask = p:CreateMaskTexture()
	mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(p.art)
	p.art:AddMaskTexture(mask)
	-- The character you're playing gets a live 3D head-and-shoulders model. Models can't take a
	-- round mask, so it sits in the square that fits inside the circle (a little larger, so the
	-- face fills it; only the shoulders reach the edge).
	local function Model()
		if p.model then return p.model end
		local m = CreateFrame("PlayerModel", nil, p)
		m:SetPoint("CENTER", 0, -1)
		m:SetSize(size * 0.84, size * 0.84)
		m:SetFrameLevel(p:GetFrameLevel() + 1)
		m:SetScript("OnShow", function(self) self:Load() end)
		function m:Load()
			if not pcall(self.SetUnit, self, "player") then return false end
			if self.SetPortraitZoom then self:SetPortraitZoom(1) end
			if self.SetCamDistanceScale then self:SetCamDistanceScale(1) end
			if self.SetPosition then self:SetPosition(0, 0, 0) end
			return true
		end
		p.model = m
		return m
	end
	-- Faction banner tucked on the bottom right, above the model.
	local badge = CreateFrame("Frame", nil, p)
	badge:SetSize(size * 0.46, size * 0.46)
	badge:SetPoint("BOTTOMRIGHT", size * 0.12, -size * 0.08)
	badge:SetFrameLevel(p:GetFrameLevel() + 3)
	p.faction = badge:CreateTexture(nil, "OVERLAY")
	p.faction:SetAllPoints()
	function p:Set(c, selected)
		local r, g, b = INV:ClassColor(c)
		self.ring:SetVertexColor(r, g, b)
		self.glow:SetVertexColor(r, g, b, 0.5)
		self.glow:SetShown(selected)
		local faction = c.faction or FACTION_BY_RACE[c.raceFile or ""]
		if faction == "Alliance" or faction == "Horde" then
			self.faction:SetTexture("Interface\\TargetingFrame\\UI-PVP-" .. faction)
			self.faction:SetTexCoord(0, 0.625, 0, 0.625)
			self.faction:Show()
		else
			self.faction:Hide()
		end
		local isMe = c.key == INV:Me().key
		local model = isMe and Model()
		if model and model:Load() then
			model:Show()
			self.art:Hide()
			return
		end
		if self.model then self.model:Hide() end
		self.art:Show()
		if isMe or not SetClassIcon(self.art, c) then SetPortrait(self.art, c) end
	end
	return p
end

---------------------------------------------------------------------------
-- Item buttons
---------------------------------------------------------------------------

local function MakeItemButton(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(SLOT, SLOT)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.bg:SetTexture(EMPTY_SLOT)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.border = b:CreateTexture(nil, "OVERLAY")
	b.border:SetAllPoints()
	b.border:SetTexture(BORDER)
	b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	b.count:SetPoint("BOTTOMRIGHT", -2, 2)
	b.level = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	b.level:SetPoint("TOPLEFT", 2, -2)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b:SetScript("OnEnter", function(self)
		if not self.item then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local link = INV.Link(self.item)
		if link then GameTooltip:SetHyperlink(link) else GameTooltip:SetItemByID(INV.ItemID(self.item)) end
		if self.note then GameTooltip:AddLine(self.note, 0.6, 0.6, 0.6, true) end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:SetScript("OnClick", function(self)
		local link = self.item and INV.Link(self.item)
		if link then HandleModifiedItemClick(link) end
	end)
	return b
end

local function FillItem(b, item, count, emptyTexture)
	b.item, b.note = item, nil
	if not item then
		b.icon:Hide()
		b.border:Hide()
		b.count:SetText("")
		b.level:SetText("")
		b.bg:SetTexture(emptyTexture or EMPTY_SLOT)
		return
	end
	local id = INV.ItemID(item)
	b.bg:SetTexture(EMPTY_SLOT)
	b.icon:SetTexture(GetIcon(id))
	b.icon:Show()
	local _, _, quality, itemLevel = GetInfo(type(item) == "number" and item or item)
	if not quality then WhenLoaded(item) end
	if quality and quality >= 2 then
		b.border:SetVertexColor(QualityColor(quality))
		b.border:Show()
	else
		b.border:Hide()
	end
	b.count:SetText(count and count > 1 and count or "")
	b.level:SetText("")
	return itemLevel
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------

local function SectionHeader(parent, y, icon, title, detail)
	local h = Get(Pool("header", parent, function(p)
		local f = CreateFrame("Frame", nil, p)
		f:SetSize(MAIN_W - 40, 22)
		f.icon = f:CreateTexture(nil, "ARTWORK")
		f.icon:SetSize(18, 18)
		f.icon:SetPoint("LEFT")
		f.title = Text(f)
		f.title:SetFontObject("GameFontNormal")
		f.title:SetPoint("LEFT", f.icon, "RIGHT", 6, 0)
		f.detail = Text(f)
		f.detail:SetFontObject("GameFontDisableSmall")
		f.detail:SetPoint("LEFT", f.title, "RIGHT", 8, 0)
		f.line = f:CreateTexture(nil, "ARTWORK")
		f.line:SetColorTexture(0.45, 0.36, 0.18, 0.4)
		f.line:SetHeight(1)
		f.line:SetPoint("BOTTOMLEFT", 0, -2)
		f.line:SetPoint("BOTTOMRIGHT", 0, -2)
		return f
	end))
	h:ClearAllPoints()
	h:SetPoint("TOPLEFT", 4, -y)
	h.icon:SetTexture(icon)
	h.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	h.title:SetText(title)
	h.detail:SetText(detail or "")
	return y + 28
end

local function DrawContainers(content, containers, bankLabel)
	local y, perRow = 4, math.floor((MAIN_W - 40) / (SLOT + GAP))
	local slotPool = Pool("slot", content, MakeItemButton)
	if bankLabel then containers = INV.VisibleBank(containers) end
	local tabs = 0
	for n, container in ipairs(containers or {}) do
		local slots = container.slots
		local used = 0
		for slot in pairs(slots) do if type(slot) == "number" then used = used + 1 end end
		local name, icon
		if container.id == 0 then
			name, icon = "Backpack", "Interface\\Buttons\\Button-Backpack-Up"
		elseif container.id == -1 then
			name, icon = bankLabel or "Bank", "Interface\\Icons\\INV_Misc_Bag_10_Blue"
		elseif container.id == -2 then
			name, icon = "Keyring", "Interface\\Icons\\INV_Misc_Key_14"
		else
			local bagItem = slots.bag
			name = bagItem and GetInfo(bagItem) or ("Bag " .. n)
			if name ~= INV.BagName(name) then
				tabs = tabs + 1
				name = INV.BagName(name, tabs)
			end
			icon = bagItem and GetIcon(INV.ItemID(bagItem)) or "Interface\\Icons\\INV_Misc_Bag_08"
		end
		y = SectionHeader(content, y, icon, name, ("%d / %d"):format(used, slots.size or 0))
		for slot = 1, slots.size or 0 do
			local b = Get(slotPool)
			local entry = slots[slot]
			FillItem(b, entry and entry[1], entry and entry[2])
			local col, row = (slot - 1) % perRow, math.floor((slot - 1) / perRow)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", 6 + col * (SLOT + GAP), -(y + row * (SLOT + GAP)))
		end
		y = y + math.ceil((slots.size or 0) / perRow) * (SLOT + GAP) + 10
	end
	return y
end

local function EmptyNote(content, text)
	local fs = Get(Pool("note", content, function(p)
		local f = CreateFrame("Frame", nil, p)
		f:SetSize(MAIN_W - 60, 60)
		f.text = Text(f)
		f.text:SetFontObject("GameFontDisable")
		f.text:SetPoint("TOPLEFT")
		f.text:SetWidth(MAIN_W - 60)
		return f
	end))
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", 10, -12)
	fs.text:SetText(text)
	return 60
end

local model

local function DrawGear(content, c)
	local y0 = 8
	local total, n = 0, 0
	local slotPool = Pool("gearslot", content, MakeItemButton)
	local function Place(list, x, stepX, stepY, startY)
		for i, slotName in ipairs(list) do
			local ok, slotID, emptyTexture = pcall(GetInventorySlotInfo, slotName)
			if ok and slotID then
				local b = Get(slotPool)
				local item = c.gear and c.gear[slotID]
				local ilvl = FillItem(b, item, slotID == 0 and c.ammoCount or nil, emptyTexture)
				if item then
					local link = INV.Link(item)
					local detailed = link and C_Item and C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
					ilvl = detailed or ilvl
					if ilvl and slotID ~= 0 and slotID ~= 4 and slotID ~= 19 then
						b.level:SetText(ilvl)
						total, n = total + ilvl, n + 1
					end
				end
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", x + (i - 1) * stepX, -(startY + (i - 1) * stepY))
			end
		end
	end
	Place(GEAR_LEFT, 20, 0, SLOT + 8, y0)
	Place(GEAR_RIGHT, MAIN_W - 40 - SLOT - 20, 0, SLOT + 8, y0)
	local bottomX = (MAIN_W - 40) / 2 - (#GEAR_BOTTOM * (SLOT + 10)) / 2
	Place(GEAR_BOTTOM, bottomX, SLOT + 10, 0, y0 + 8 * (SLOT + 8) + 6)

	-- The character in the middle: a 3D model when possible, else the portrait art.
	if not model then
		model = CreateFrame("DressUpModel", nil, content)
		model.fallback = content:CreateTexture(nil, "ARTWORK")
		model.caption = Text(content)
		model.caption:SetFontObject("GameFontDisableSmall")
	end
	local mx, mw = 20 + SLOT + 30, MAIN_W - 40 - 2 * (SLOT + 50)
	model:ClearAllPoints()
	model:SetPoint("TOPLEFT", mx, -y0)
	model:SetSize(mw, 8 * (SLOT + 8) - 8)
	model.fallback:ClearAllPoints()
	model.fallback:SetPoint("CENTER", model, "CENTER")
	model.fallback:SetSize(160, 160)
	model.caption:ClearAllPoints()
	model.caption:SetPoint("TOP", model, "BOTTOM", 0, -2)
	local shown = false
	if c.key == INV:Me().key then
		shown = pcall(model.SetUnit, model, "player")
		model.caption:SetText("")
	elseif c.raceID and model.SetCustomRace then
		shown = pcall(function()
			model:SetCustomRace(c.raceID, c.sex == 3 and 1 or 0)
			model:Undress()
			for _, item in pairs(c.gear or {}) do
				local link = INV.Link(item)
				if link then model:TryOn(link) end
			end
		end)
		model.caption:SetText(shown and "Race and gear as saved; face and hair aren't stored" or "")
	end
	model:SetShown(shown)
	model.fallback:SetShown(not shown)
	if not shown then
		SetPortrait(model.fallback, c)
		model.caption:SetText("")
	end
	frame.gearSummary:SetText(n > 0 and ("Average item level |cffffffff%.1f|r"):format(total / n) or "")
	return y0 + 9 * (SLOT + 8) + 20
end

local function DrawRows(content, rows, y)
	local pool = Pool("row", content, function(p)
		local r = CreateFrame("Button", nil, p)
		r:SetSize(MAIN_W - 44, 34)
		r.bg = r:CreateTexture(nil, "BACKGROUND")
		r.bg:SetAllPoints()
		r.bg:SetColorTexture(1, 1, 1, 0.03)
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(28, 28)
		r.icon:SetPoint("LEFT", 4, 0)
		r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		r.name = Text(r)
		r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 6)
		r.sub = Text(r)
		r.sub:SetFontObject("GameFontDisableSmall")
		r.sub:SetPoint("LEFT", r.icon, "RIGHT", 8, -8)
		r.right = Text(r)
		r.right:SetJustifyH("RIGHT")
		r.right:SetPoint("RIGHT", -8, 0)
		r.bar = r:CreateTexture(nil, "ARTWORK")
		r.bar:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
		r.bar:SetPoint("LEFT", r.icon, "RIGHT", 180, 0)
		r.bar:SetHeight(12)
		r.barBg = r:CreateTexture(nil, "BORDER")
		r.barBg:SetColorTexture(0, 0, 0, 0.6)
		r.barBg:SetPoint("LEFT", r.bar, "LEFT")
		r.barBg:SetSize(260, 14)
		r:SetHighlightTexture(WHITE)
		r:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.05)
		r:SetScript("OnEnter", function(self)
			if not self.item then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			local link = INV.Link(self.item)
			if link then GameTooltip:SetHyperlink(link) else GameTooltip:SetItemByID(INV.ItemID(self.item)) end
			GameTooltip:Show()
		end)
		r:SetScript("OnLeave", GameTooltip_Hide)
		r:SetScript("OnClick", function(self)
			local link = self.item and INV.Link(self.item)
			if link then HandleModifiedItemClick(link) end
		end)
		return r
	end)
	for _, data in ipairs(rows) do
		local r = Get(pool)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", 4, -y)
		r.item = data.item
		r.icon:SetTexture(data.icon or (data.item and GetIcon(INV.ItemID(data.item))) or "Interface\\Icons\\INV_Misc_QuestionMark")
		r.name:SetText(data.name or "")
		r.name:SetTextColor(unpack(data.color or { 1, 1, 1 }))
		r.sub:SetText(data.sub or "")
		r.right:SetText(data.right or "")
		r.bar:SetShown(data.fill ~= nil)
		r.barBg:SetShown(data.fill ~= nil)
		if data.fill then
			r.bar:SetWidth(math.max(1, 260 * data.fill))
			r.bar:SetVertexColor(0.85, 0.62, 0.15)
		end
		y = y + 38
	end
	return y
end

local function ItemRow(item, count, sub, right)
	local name, _, quality = GetInfo(type(item) == "number" and item or item)
	if not name then WhenLoaded(item) end
	return {
		item = item, name = (name or "Loading...") .. (count and count > 1 and (" |cffffffffx" .. count .. "|r") or ""),
		color = { QualityColor(quality) }, sub = sub, right = right,
	}
end

local function DrawMail(content, c)
	local mail = c.mail
	if not mail then return EmptyNote(content, "No mailbox seen yet. Open a mailbox on this character to see what's waiting.") end
	local rows = {}
	local now = time()
	for _, e in ipairs(mail.items) do
		local days = e.expires and math.floor((e.expires - now) / 86400)
		local expires = days and (days < 3 and ("|cffff5555expires in %d days|r"):format(math.max(0, days)) or ("expires in %d days"):format(days)) or ""
		tinsert(rows, ItemRow(e[1], e[2], "from " .. (e.sender or "?"), expires))
	end
	local y = SectionHeader(content, 4, "Interface\\Icons\\INV_Letter_15", "Mailbox",
		("%d items, %s  |cff999999(seen %s)|r"):format(#mail.items, Money(mail.money or 0), Ago(mail.time)))
	if #rows == 0 then return y + EmptyNote(content, "") end
	return DrawRows(content, rows, y)
end

local function DrawAuctions(content, c)
	local a = c.auctions
	if not a then return EmptyNote(content, "No auctions seen yet. Open the auction house on this character to update.") end
	local rows = {}
	local now = time()
	for _, e in ipairs(a.items) do
		local left = e.ends and math.max(0, e.ends - now)
		local ends = left and (left > 3600 and ("%dh left"):format(math.floor(left / 3600)) or ("%dm left"):format(math.floor(left / 60))) or ""
		tinsert(rows, ItemRow(e[1], e[2], ends, e.buyout and Money(e.buyout) or (e.bid and Money(e.bid)) or ""))
	end
	local y = SectionHeader(content, 4, "Interface\\Icons\\INV_Misc_Coin_02", "Posted auctions",
		("%d  |cff999999(seen %s)|r"):format(#rows, Ago(a.time)))
	return DrawRows(content, rows, y)
end

-- The game's profession-book paintings, by skill line.
local PROFESSION_ART = {
	[171] = "Profession-overview-Card-Alchemy", [164] = "Profession-overview-Card-Blacksmithing",
	[333] = "Profession-overview-Card-Enchanting", [202] = "Profession-overview-Card-Engineering",
	[182] = "Profession-overview-Card-Herbalism", [165] = "Profession-overview-Card-Leatherworking",
	[186] = "Profession-overview-Card-Mining", [393] = "Profession-overview-Card-Skinning",
	[197] = "Profession-overview-Card-Tailoring", [185] = "Profession-overview-card-generic-cooking",
	[129] = "Profession-overview-card-generic-firstaid", [356] = "Profession-overview-card-generic-fishing",
}
local SECONDARY = { [185] = true, [129] = true, [356] = true, [762] = true }

-- A painted card: icon, name, and a gold rank bar along the bottom.
local function ProfessionCard(content, p, x, y, width, height)
	local card = Get(Pool("profcard", content, function(parent)
		local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
		Backdrop(f, { 0.07, 0.06, 0.045, 0.95 }, { 0.35, 0.28, 0.14, 1 })
		f.art = f:CreateTexture(nil, "BACKGROUND", nil, 1)
		f.art:SetPoint("TOPLEFT", 1, -1)
		f.shade = f:CreateTexture(nil, "BORDER") -- darker on the left, where the text sits
		f.shade:SetPoint("TOPLEFT", 1, -1)
		f.shade:SetPoint("BOTTOMLEFT", 1, 1)
		f.shade:SetWidth(260)
		f.shade:SetColorTexture(1, 1, 1)
		f.shade:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0.65), CreateColor(0, 0, 0, 0))
		f.iconBorder = f:CreateTexture(nil, "ARTWORK")
		f.iconBorder:SetSize(44, 44)
		f.iconBorder:SetPoint("TOPLEFT", 12, -12)
		f.iconBorder:SetColorTexture(0.55, 0.43, 0.2)
		f.icon = f:CreateTexture(nil, "OVERLAY")
		f.icon:SetPoint("TOPLEFT", f.iconBorder, 1, -1)
		f.icon:SetPoint("BOTTOMRIGHT", f.iconBorder, -1, 1)
		f.icon:SetTexCoord(unpack(ICON_TRIM))
		f.name = Text(f, TITLE_FONT, 18)
		f.name:SetTextColor(unpack(GOLD))
		f.name:SetShadowOffset(1, -1)
		f.name:SetPoint("TOPLEFT", f.iconBorder, "TOPRIGHT", 10, -3)
		f.sub = Text(f)
		f.sub:SetFontObject("GameFontHighlightSmall")
		f.sub:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -3)
		f.barBg = f:CreateTexture(nil, "ARTWORK")
		f.barBg:SetColorTexture(0, 0, 0, 0.75)
		f.barBg:SetPoint("BOTTOMLEFT", 12, 12)
		f.barBg:SetPoint("BOTTOMRIGHT", -12, 12)
		f.barBg:SetHeight(16)
		f.bar = f:CreateTexture(nil, "OVERLAY", nil, -1)
		f.bar:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
		f.bar:SetVertexColor(0.9, 0.62, 0.15)
		f.bar:SetPoint("TOPLEFT", f.barBg, 1, -1)
		f.bar:SetPoint("BOTTOMLEFT", f.barBg, 1, 1)
		f.barText = Text(f)
		f.barText:SetFontObject("GameFontHighlightSmall")
		f.barText:SetPoint("CENTER", f.barBg)
		return f
	end))
	card:ClearAllPoints()
	card:SetPoint("TOPLEFT", x, -y)
	card:SetSize(width, height)
	local art = { PROFESSION_ART[p.id] or "Profession-overview-Card", "Profession-overview-Card" }
	local painted = ns.Settings and ns.Settings.CoverAtlas and ns.Settings.CoverAtlas(card.art, art, width - 2, height - 2)
	card.art:SetShown(painted and true or false)
	card.shade:SetWidth(math.min(260, width - 2))
	card.icon:SetTexture("Interface\\Icons\\" .. (PROFESSION_ICONS[p.id] or "INV_Misc_Book_09"))
	card.name:SetText(p.name)
	local fill = p.max > 0 and math.min(1, p.rank / p.max) or 0
	card.sub:SetText(SECONDARY[p.id] and "Secondary skill" or "Profession")
	card.bar:SetWidth(math.max(1, (width - 26) * fill))
	card.barText:SetText(("%d / %d"):format(p.rank, p.max))
end

local function DrawProfessions(content, c)
	if not c.professions or #c.professions == 0 then
		return EmptyNote(content, "No professions recorded yet. Log in on this character to update.")
	end
	local y = SectionHeader(content, 4, "Interface\\Icons\\Trade_BlackSmithing", "Professions", "|cff999999" .. Ago(c.professionsTime) .. "|r")
	local width = MAIN_W - 44
	local primary, secondary = {}, {}
	for _, p in ipairs(INV.UniqueProfessions(c.professions)) do
		tinsert(SECONDARY[p.id] and secondary or primary, p)
	end
	-- Professions get a full-width card; secondary skills share a row, three across.
	for _, p in ipairs(primary) do
		ProfessionCard(content, p, 4, y, width, 96)
		y = y + 104
	end
	local gap, perRow = 8, 3
	local w = (width - gap * (perRow - 1)) / perRow
	for i, p in ipairs(secondary) do
		local col = (i - 1) % perRow
		ProfessionCard(content, p, 4 + col * (w + gap), y, w, 120)
		if col == perRow - 1 or i == #secondary then y = y + 128 end
	end
	return y
end

-- Search across every shown character.
local function DrawSearch(content)
	local term = state.search:lower()
	local found, order = {}, {}
	for _, c in ipairs(INV:Characters(false)) do
		local function consider(item)
			local id = INV.ItemID(item)
			if not id or found[id] then return end
			local name = GetInfo(type(item) == "number" and item or item)
			if not name then WhenLoaded(item) return end
			if name:lower():find(term, 1, true) then
				found[id] = item
				tinsert(order, { id = id, item = item, name = name })
			end
		end
		for _, part in ipairs({ c.bags, c.bank }) do
			for _, container in ipairs(part or {}) do
				for slot, e in pairs(container.slots) do if type(slot) == "number" then consider(e[1]) end end
			end
		end
		for _, item in pairs(c.gear or {}) do consider(item) end
		for _, e in ipairs(c.mail and c.mail.items or {}) do consider(e[1]) end
		for _, e in ipairs(c.auctions and c.auctions.items or {}) do consider(e[1]) end
	end
	table.sort(order, function(a, b) return a.name < b.name end)
	local y = SectionHeader(content, 4, "Interface\\Common\\UI-Searchbox-Icon", ("Search: \"%s\""):format(state.search),
		("%d items found"):format(#order))
	if #order == 0 then return y + EmptyNote(content, "Nothing matches on your characters.") end
	local rows = {}
	for i, e in ipairs(order) do
		if i > 120 then break end
		local who = {}
		for _, w in ipairs(INV:WhoHas(e.id)) do
			local r, g, b = INV:ClassColor(w.char)
			tinsert(who, ("|cff%02x%02x%02x%s|r %d |cff999999(%s)|r"):format(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), w.char.name, w.total, INV.Breakdown(w.parts)))
		end
		local row = ItemRow(e.item, nil, table.concat(who, "   "))
		tinsert(rows, row)
	end
	return DrawRows(content, rows, y)
end

---------------------------------------------------------------------------
-- Sidebar and header
---------------------------------------------------------------------------

local function CharacterMenu(owner, c)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(c.name .. " - " .. (c.realm or ""))
		if INV:IsHidden(c.key) then
			root:CreateButton("Show in lists and tooltips", function() INV:SetHidden(c.key, false) end)
		else
			root:CreateButton("Hide from lists and tooltips", function() INV:SetHidden(c.key, true) end)
		end
		if c.key ~= INV:Me().key then
			root:CreateButton("|cffff5555Remove this character's saved data|r", function()
				StaticPopup_Show("AZEROTHALMANAC_REMOVE_CHARACTER", c.name, nil, c.key)
			end)
		end
	end)
end

StaticPopupDialogs["AZEROTHALMANAC_REMOVE_CHARACTER"] = {
	text = "Remove everything Azeroth Almanac saved about %s? It comes back the next time you log in on them.",
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, key)
		INV:Remove(key)
		if state.selected == key then state.selected = nil end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

local function DrawSidebar()
	local list = INV:Characters(state.showHidden)
	local pool = Pool("char", frame.charContent, function(p)
		local r = CreateFrame("Button", nil, p)
		r:SetSize(SIDE_W - 30, ROW_H - 4)
		r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		r.bg = r:CreateTexture(nil, "BACKGROUND")
		r.bg:SetAllPoints()
		r.portrait = MakePortrait(r, 40)
		r.portrait:SetPoint("LEFT", 6, 0)
		r.name = Text(r)
		r.name:SetFontObject("GameFontNormal")
		r.name:SetPoint("TOPLEFT", r.portrait, "TOPRIGHT", 10, -2)
		r.info = Text(r)
		r.info:SetFontObject("GameFontDisableSmall")
		r.info:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2)
		r.info:SetPoint("RIGHT", r, "RIGHT", -6, 0)
		r.info:SetWordWrap(false)
		r.money = Text(r)
		r.money:SetFontObject("GameFontHighlightSmall")
		r.money:SetPoint("TOPLEFT", r.info, "BOTTOMLEFT", 0, -2)
		r.rested = Text(r)
		r.rested:SetFontObject("GameFontHighlightSmall")
		r.rested:SetJustifyH("RIGHT")
		r.rested:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -6, 8)
		r.restIcon = r:CreateTexture(nil, "OVERLAY")
		r.restIcon:SetTexture(REST_ICON)
		r.restIcon:SetTexCoord(unpack(REST_COORDS))
		r.restIcon:SetSize(14, 14)
		r.restIcon:SetPoint("RIGHT", r.rested, "LEFT", -2, 0)
		r:SetHighlightTexture(WHITE)
		r:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.05)
		r:SetScript("OnClick", function(self, button)
			if button == "RightButton" then
				CharacterMenu(self, self.char)
			else
				state.selected = self.char.key
				state.search = ""
				frame.search:SetText("")
				Refresh()
			end
		end)
		return r
	end)
	local y = 0
	local lastRealm
	for _, c in ipairs(list) do
		if c.realm ~= lastRealm then
			lastRealm = c.realm
			local h = Get(Pool("realm", frame.charContent, function(p)
				local fs = CreateFrame("Frame", nil, p)
				fs:SetSize(SIDE_W - 30, 18)
				fs.text = Text(fs)
				fs.text:SetFontObject("GameFontDisableSmall")
				fs.text:SetPoint("LEFT", 4, 0)
				return fs
			end))
			h:ClearAllPoints()
			h:SetPoint("TOPLEFT", 0, -y)
			h.text:SetText((c.realm or "?"):upper())
			y = y + 20
		end
		local r = Get(pool)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", 0, -y)
		r.char = c
		local selected = c.key == state.selected
		r.bg:SetColorTexture(0.45, 0.33, 0.12, selected and 0.5 or 0)
		r.portrait:Set(c, selected)
		local cr, cg, cb = INV:ClassColor(c)
		r.name:SetText(c.name .. (c.key == INV:Me().key and "  |cff999999(you)|r" or ""))
		r.name:SetTextColor(cr, cg, cb)
		r.info:SetText(("%s %s %s%s"):format(c.level or "?", c.race or "", c.class and (LOCALIZED_CLASS_NAMES_MALE or {})[c.class] or "",
			c.zone and ("  |cff808080- " .. c.zone .. "|r") or ""))
		r.money:SetText(Money(c.money))
		local _, share = INV:Rested(c)
		r.rested:SetText(share and share > 0 and ("|cff80b3ff%d%% rested|r"):format(math.floor(share * 100 + 0.5)) or "")
		r.restIcon:SetShown(share and c.resting and true or false)
		r:SetAlpha(INV:IsHidden(c.key) and 0.45 or 1)
		y = y + ROW_H
	end
	frame.charContent:SetHeight(math.max(10, y))
	frame.total:SetText(("Account gold: %s"):format(Money(INV:TotalMoney())))
end

local function DrawHeader(c)
	local h = frame.header
	h.portrait:Set(c, true)
	local r, g, b = INV:ClassColor(c)
	h.name:SetText(c.name)
	h.name:SetTextColor(r, g, b)
	local class = c.class and (LOCALIZED_CLASS_NAMES_MALE or {})[c.class] or ""
	h.info:SetText(("Level %s %s %s  |cff999999-  %s|r"):format(c.level or "?", c.race or "", class, c.realm or ""))
	local stale = (INV:Settings().staleDays or 7) * 86400
	local bank = c.bankTime and (time() - c.bankTime > stale and ("|cffff9933%s - visit a banker|r"):format(Ago(c.bankTime)) or Ago(c.bankTime))
		or "|cffff9933not seen - visit a banker|r"
	h.updated:SetText(("Bags %s\nBank %s\nGear %s"):format(Ago(c.bagsTime), bank, Ago(c.gearTime)))

	-- The chip row: gold, location, hearthstone, rest.
	local chips = h.chips
	for _, chip in pairs(chips) do chip.char = c end
	chips.money:SetLabel(Money(c.money), 180)
	if c.zone then
		local place = (c.subzone and c.subzone ~= "" and c.subzone ~= c.zone) and (c.subzone .. ", " .. c.zone) or c.zone
		chips.location:SetLabel(place, 250)
		chips.location:Show()
	else
		chips.location:Hide()
	end
	if c.hearth then
		chips.hearth:SetLabel(c.hearth, 150)
		chips.hearth:Show()
	else
		chips.hearth:Hide()
	end
	local levelling = c.xpMax and c.xpMax > 0 and not (c.maxLevel and (c.level or 0) >= c.maxLevel)
	if levelling then
		chips.rest:SetLabel(c.resting and "|cff80b3ffResting|r" or "|cff999999Not resting|r")
		chips.rest.icon:SetDesaturated(not c.resting)
		chips.rest.icon:SetAlpha(c.resting and 1 or 0.45)
		chips.rest:Show()
	else
		chips.rest:Hide()
	end
	local x = 0
	for _, key in ipairs({ "money", "location", "hearth", "rest" }) do
		local chip = chips[key]
		if chip:IsShown() then
			chip:ClearAllPoints()
			chip:SetPoint("TOPLEFT", h.info, "BOTTOMLEFT", x, -7)
			x = x + chip:GetWidth() + 20
		end
	end

	-- XP bar: XP on the left, rested on the right (estimated since logout for other characters).
	local bar = h.xpBar
	bar.char = c
	local width = bar:GetWidth() - 2
	bar.right:SetText("")
	if c.maxLevel and (c.level or 0) >= c.maxLevel then
		bar.fill:SetWidth(math.max(1, width))
		bar.rested:Hide()
		bar.left:SetText("Max level")
	elseif levelling then
		local rested, share, capped, estimated = INV:Rested(c)
		local xpShare = (c.xp or 0) / c.xpMax
		bar.fill:SetWidth(math.max(1, width * xpShare))
		bar.rested:SetShown(rested and rested > 0)
		bar.rested:SetWidth(math.max(1, width * math.min(1, xpShare + (share or 0))))
		bar.left:SetText(("XP %s / %s  (%d%%)"):format(Number(c.xp or 0), Number(c.xpMax), math.floor(xpShare * 100)))
		if rested and rested > 0 then
			bar.right:SetText(("|cff9fc4ffRested %s%s  (%d%%)%s|r"):format(estimated and "~" or "", Number(rested),
				math.floor(share * 100 + 0.5), capped and ", full" or ""))
		else
			bar.right:SetText("|cff999999No rested XP|r")
		end
	else
		bar.fill:SetWidth(1)
		bar.rested:Hide()
		bar.left:SetText("|cff999999XP not seen yet - log in on this character|r")
	end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

function IW:Refresh()
	if not frame or not frame:IsShown() then return end
	ReleaseAll()
	if model then model:Hide() model.fallback:Hide() model.caption:SetText("") end
	frame.gearSummary:SetText("")
	local me = INV:Me()
	if not state.selected or not INV:Settings().chars[state.selected] then state.selected = me.key end
	local c = INV:Settings().chars[state.selected]
	c.key = state.selected
	DrawSidebar()
	DrawHeader(c)

	for _, tab in ipairs(frame.tabs) do
		local on = tab.key == state.tab and state.search == ""
		tab:SetBackdropColor(on and 0.45 or 0.14, on and 0.33 or 0.11, on and 0.12 or 0.06, 0.95)
		local count = ""
		if tab.key == "mail" and c.mail then count = (" (%d)"):format(#c.mail.items)
		elseif tab.key == "auctions" and c.auctions then count = (" (%d)"):format(#c.auctions.items) end
		tab:SetText(tab.label .. count)
	end

	local content = frame.content
	local height
	if #state.search >= 2 then
		height = DrawSearch(content)
	elseif state.tab == "bags" then
		height = c.bags and DrawContainers(content, c.bags) or EmptyNote(content, "No bags seen yet. Log in on this character.")
	elseif state.tab == "bank" then
		height = c.bank and DrawContainers(content, c.bank, "Bank")
			or EmptyNote(content, "This character's bank hasn't been seen yet. Open the bank on them once and it's remembered.")
	elseif state.tab == "gear" then
		height = DrawGear(content, c)
	elseif state.tab == "mail" then
		height = DrawMail(content, c)
	elseif state.tab == "auctions" then
		height = DrawAuctions(content, c)
	else
		height = DrawProfessions(content, c)
	end
	content:SetHeight(math.max(10, height))
end

local function Build()
	frame = CreateFrame("Frame", "AzerothAlmanacInventory", UIParent, "BackdropTemplate")
	frame:SetSize(WIN_W, WIN_H)
	Backdrop(frame, { 0.035, 0.03, 0.025, 0.97 }, { 0.4, 0.32, 0.16, 1 })
	frame:SetPoint("CENTER")
	-- same layer as the game's windows: whichever was clicked last is in front
	frame:SetFrameStrata("MEDIUM")
	frame:SetToplevel(true)
	frame:HookScript("OnShow", frame.Raise)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	tinsert(UISpecialFrames, "AzerothAlmanacInventory")

	local titleBg = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	titleBg:SetColorTexture(0.08, 0.065, 0.045, 1)
	titleBg:SetPoint("TOPLEFT", 1, -1)
	titleBg:SetPoint("TOPRIGHT", -1, -1)
	titleBg:SetHeight(42)
	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetSize(28, 28)
	icon:SetPoint("TOPLEFT", 14, -8)
	icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
	local title = Text(frame, TITLE_FONT, 22)
	title:SetTextColor(unpack(GOLD))
	title:SetPoint("LEFT", icon, "RIGHT", 10, -1)
	title:SetText("My Characters")
	frame.total = Text(frame)
	frame.total:SetFontObject("GameFontHighlight")
	frame.total:SetPoint("RIGHT", frame, "TOPRIGHT", -44, -22)
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	-- Sidebar
	local side = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	Backdrop(side, { 0.06, 0.05, 0.04, 0.9 }, { 0.22, 0.18, 0.1, 1 })
	side:SetPoint("TOPLEFT", 12, -52)
	side:SetPoint("BOTTOMLEFT", 12, 12)
	side:SetWidth(SIDE_W)
	local search = CreateFrame("EditBox", nil, side, "SearchBoxTemplate")
	search:SetSize(SIDE_W - 24, 22)
	search:SetPoint("TOPLEFT", 14, -8)
	search:SetScript("OnTextChanged", function(self, user)
		if SearchBoxTemplate_OnTextChanged then SearchBoxTemplate_OnTextChanged(self) end
		state.search = self:GetText() or ""
		if user ~= false then Refresh() end
	end)
	if type(search.Instructions) == "table" then search.Instructions:SetText("Search all characters") end
	frame.search = search
	local scroll = CreateFrame("ScrollFrame", nil, side, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 6, -38)
	scroll:SetPoint("BOTTOMRIGHT", -26, 34)
	local charContent = CreateFrame("Frame", nil, scroll)
	charContent:SetSize(SIDE_W - 30, 10)
	scroll:SetScrollChild(charContent)
	frame.charContent = charContent
	local showHidden = CreateFrame("CheckButton", nil, side, "UICheckButtonTemplate")
	showHidden:SetSize(22, 22)
	showHidden:SetPoint("BOTTOMLEFT", 8, 6)
	showHidden:SetScript("OnClick", function(self) state.showHidden = self:GetChecked() and true or false Refresh() end)
	local showHiddenText = Text(side)
	showHiddenText:SetFontObject("GameFontHighlightSmall")
	showHiddenText:SetPoint("LEFT", showHidden, "RIGHT", 2, 0)
	showHiddenText:SetText("Show hidden characters (right-click to hide)")

	-- Header card: portrait | name, class line and a row of chips (gold, location, hearthstone,
	-- rest) | data freshness top-right; the XP bar runs along the bottom.
	local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	Backdrop(header, { 0.06, 0.05, 0.04, 0.9 }, { 0.22, 0.18, 0.1, 1 })
	header:SetPoint("TOPLEFT", MAIN_X, -52)
	header:SetSize(MAIN_W, 112)
	header.portrait = MakePortrait(header, 76)
	header.portrait:SetPoint("TOPLEFT", 14, -12)
	header.name = Text(header, TITLE_FONT, 26)
	header.name:SetPoint("TOPLEFT", header.portrait, "TOPRIGHT", 16, 4)
	header.info = Text(header)
	header.info:SetFontObject("GameFontHighlight")
	header.info:SetPoint("TOPLEFT", header.name, "BOTTOMLEFT", 0, -2)
	header.updated = Text(header)
	header.updated:SetFontObject("GameFontDisableSmall")
	header.updated:SetJustifyH("RIGHT")
	header.updated:SetPoint("TOPRIGHT", -14, -12)
	header.updated:SetSpacing(3)

	-- A small icon + label; labels are cut short so the row never overflows.
	local function Chip(icon, coords)
		local chip = CreateFrame("Button", nil, header)
		chip:SetHeight(18)
		chip.icon = chip:CreateTexture(nil, "ARTWORK")
		chip.icon:SetSize(14, 14)
		chip.icon:SetPoint("LEFT")
		chip.text = Text(chip)
		chip.text:SetFontObject("GameFontHighlightSmall")
		chip.text:SetWordWrap(false)
		if icon then
			chip.icon:SetTexture(icon)
			if coords then chip.icon:SetTexCoord(unpack(coords)) end
			chip.text:SetPoint("LEFT", chip.icon, "RIGHT", 4, 0)
		else
			chip.icon:Hide()
			chip.text:SetPoint("LEFT")
		end
		chip.iconWidth = icon and 18 or 0
		function chip:SetLabel(text, maxWidth)
			self.text:SetWidth(0)
			self.text:SetText(text)
			local w = math.min(self.text:GetStringWidth(), maxWidth or 260)
			self.text:SetWidth(w)
			self:SetWidth(self.iconWidth + w)
		end
		chip:SetScript("OnLeave", GameTooltip_Hide)
		return chip
	end
	local chips = {
		money = Chip(nil),
		location = Chip(LOCATION_ICON, ICON_TRIM),
		hearth = Chip(HEARTH_ICON, ICON_TRIM),
		rest = Chip(REST_ICON, REST_COORDS),
	}
	header.chips = chips

	-- Location: hover for details, click to open the world map there.
	chips.location:SetScript("OnEnter", function(self)
		local c = self.char
		if not c or not c.zone then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(c.name .. "'s last known location")
		if c.subzone and c.subzone ~= "" and c.subzone ~= c.zone then GameTooltip:AddLine(c.subzone, 1, 1, 1) end
		GameTooltip:AddLine(c.zone .. (c.x and ("  (%.1f, %.1f)"):format(c.x * 100, c.y * 100) or ""), 1, 1, 1)
		GameTooltip:AddLine((c.key == INV:Me().key and "Here now, updated " or "Left there ") .. Ago(c.locTime), 0.7, 0.7, 0.7)
		if c.mapID then GameTooltip:AddLine("Click to open the map there.", 0.6, 0.6, 0.6) end
		GameTooltip:Show()
	end)
	chips.location:SetScript("OnClick", function(self)
		local c = self.char
		if not (c and c.mapID) then return end
		if OpenWorldMap then
			OpenWorldMap(c.mapID)
		elseif WorldMapFrame then
			if not WorldMapFrame:IsShown() then ToggleWorldMap() end
			WorldMapFrame:SetMapID(c.mapID)
		end
	end)
	chips.hearth:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("Hearthstone")
		GameTooltip:AddLine("Set to " .. (self.char and self.char.hearth or "?"), 1, 1, 1)
		GameTooltip:Show()
	end)
	chips.rest:SetScript("OnEnter", function(self)
		local c = self.char
		if not c then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		if c.resting then
			GameTooltip:AddLine("Resting", 0.5, 0.7, 1)
			GameTooltip:AddLine("In an inn or city: rested XP builds at the full rate.", 1, 1, 1, true)
		else
			GameTooltip:AddLine("Not resting")
			GameTooltip:AddLine("Out in the open: rested XP builds at a quarter of the rate. Log out in an inn or city for the full rate.", 1, 1, 1, true)
		end
		local last = c.restChecks and c.restChecks[1]
		if last then
			GameTooltip:AddLine(("Last login: predicted ~%s, actual %s"):format(Number(last.predicted), Number(last.actual)), 0.7, 0.7, 0.7)
		end
		GameTooltip:Show()
	end)

	-- XP bar along the bottom: XP on the left, rested XP on the right (so they never overlap).
	local bar = CreateFrame("Frame", nil, header, "BackdropTemplate")
	Backdrop(bar, { 0, 0, 0, 0.7 }, { 0.35, 0.28, 0.14, 1 })
	bar:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 14 + 76 + 16, 12)
	bar:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -14, 12)
	bar:SetHeight(15)
	bar.rested = bar:CreateTexture(nil, "BORDER")
	bar.rested:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar.rested:SetVertexColor(0.25, 0.5, 1, 0.6)
	bar.rested:SetPoint("TOPLEFT", 1, -1)
	bar.rested:SetPoint("BOTTOMLEFT", 1, 1)
	bar.fill = bar:CreateTexture(nil, "ARTWORK")
	bar.fill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar.fill:SetVertexColor(0.58, 0.0, 0.55)
	bar.fill:SetPoint("TOPLEFT", 1, -1)
	bar.fill:SetPoint("BOTTOMLEFT", 1, 1)
	bar.left = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.left:SetPoint("LEFT", 6, 0)
	bar.right = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.right:SetPoint("RIGHT", -6, 0)
	-- Hover: this character's login checks (predicted vs actual rested XP) and the learned rates.
	bar:EnableMouse(true)
	bar:SetScript("OnEnter", function(self)
		local c = self.char
		if not c then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("Rested XP checks for " .. c.name)
		local checks = c.restChecks or {}
		if #checks == 0 then
			GameTooltip:AddLine("None yet. Each login after an hour or more away compares the estimate with the game.", 0.7, 0.7, 0.7, true)
		end
		for _, k in ipairs(checks) do
			local diff = k.predicted > 0 and (k.actual - k.predicted) / k.predicted * 100 or 0
			GameTooltip:AddDoubleLine(("%s: %.0fh %s"):format(date("%b %d", k.t), k.hours, k.resting and "resting" or "in the open"),
				("predicted ~%s, actual %s (%+d%%)"):format(Number(k.predicted), Number(k.actual), math.floor(diff + 0.5)),
				0.8, 0.8, 0.8, 1, 1, 1)
		end
		GameTooltip:AddLine(" ")
		for _, spec in ipairs({ { true, "In an inn or city" }, { false, "In the open" } }) do
			local factor, n = INV:RateFactor(spec[1])
			GameTooltip:AddDoubleLine(spec[2], n > 0 and ("x%.2f of the Classic rate (%d checks)"):format(factor, n) or "Classic rate (no checks yet)",
				0.5, 0.7, 1, 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	bar:SetScript("OnLeave", GameTooltip_Hide)
	header.xpBar = bar
	frame.header = header

	-- Tabs
	frame.tabs = {}
	local x = MAIN_X
	for _, spec in ipairs(TABS) do
		local tab = CreateFrame("Button", nil, frame, "BackdropTemplate")
		Backdrop(tab, { 0.14, 0.11, 0.06, 0.95 }, { 0.45, 0.36, 0.16, 0.9 })
		tab:SetSize(108, 26)
		tab:SetPoint("TOPLEFT", x, -172)
		local fs = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		fs:SetPoint("CENTER")
		tab:SetFontString(fs)
		tab:SetHighlightTexture(WHITE)
		tab:GetHighlightTexture():SetVertexColor(1, 0.85, 0.4, 0.1)
		tab.key, tab.label = spec.key, spec.label
		tab:SetScript("OnClick", function()
			state.tab = spec.key
			state.search = ""
			frame.search:SetText("")
			Refresh()
		end)
		tinsert(frame.tabs, tab)
		x = x + 112
	end
	frame.gearSummary = Text(frame)
	frame.gearSummary:SetFontObject("GameFontNormal")
	frame.gearSummary:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -178)

	-- Content
	local body = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	Backdrop(body, { 0.05, 0.045, 0.035, 0.9 }, { 0.22, 0.18, 0.1, 1 })
	body:SetPoint("TOPLEFT", MAIN_X, -204)
	body:SetPoint("BOTTOMRIGHT", -12, 12)
	local bodyScroll = CreateFrame("ScrollFrame", nil, body, "UIPanelScrollFrameTemplate")
	bodyScroll:SetPoint("TOPLEFT", 6, -6)
	bodyScroll:SetPoint("BOTTOMRIGHT", -28, 6)
	local content = CreateFrame("Frame", nil, bodyScroll)
	content:SetSize(MAIN_W - 40, 10)
	bodyScroll:SetScrollChild(content)
	frame.content = content

	if ns.NativeWindow(frame, { title = "My Characters", icon = "Interface\\Icons\\INV_Misc_Bag_08",
		hide = { titleBg, icon, title }, close = close }) then
		frame.total:ClearAllPoints()
		frame.total:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -31)
		ns.NativeInset(side)
		ns.NativeInset(header)
		ns.NativeInset(body)
	end
	frame:SetScript("OnShow", Refresh)
end

---------------------------------------------------------------------------
-- Module API
---------------------------------------------------------------------------

function IW:OnLogin()
	INV = ns.Inventory
	INV.OnChange = function()
		if frame and frame:IsShown() and not pending then
			pending = true
			C_Timer.After(0.3, function() pending = false Refresh() end)
		end
	end
end

function IW:Open(key)
	if not frame then Build() end
	if key then state.selected = key end
	frame:Show()
	Refresh()
end

function IW:Toggle()
	if frame and frame:IsShown() then frame:Hide() else self:Open() end
end
