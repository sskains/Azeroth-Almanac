-- Shared building blocks for every Almanac page, made from the game's own templates and art so
-- the pages look like the game's windows. Every template is created through pcall with a plain
-- fallback, because a missing template on this client must never break the window.
-- Note: the game's own drop-down / context menu system crashed this client when an addon used it
-- (seen in Plus Everything), so menus here are drawn by the addon.

local _, ns = ...
local L = ns.L

-- a gradient fill on a texture, with a plain colour where gradients aren't available
local function Fade(t, orient, r, g, b, a1, a2)
	t:SetColorTexture(1, 1, 1, 1)
	if not (CreateColor and pcall(t.SetGradient, t, orient, CreateColor(r, g, b, a1), CreateColor(r, g, b, a2))) then
		t:SetColorTexture(r, g, b, (a1 + a2) / 2)
	end
end
ns.UI = ns.UI or {}
local W = {}
ns.Widgets = W
W.Fade = Fade

-- the first atlas the client has, set on a texture
local function TryAtlas(t, ...)
	for i = 1, select("#", ...) do
		local name = select(i, ...)
		if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) and pcall(t.SetAtlas, t, name) then return true end
	end
	return false
end
W.TryAtlas = TryAtlas

---------------------------------------------------------------------------
-- Item clicks, the game's way, for every item the Almanac shows (slots, lists, icons):
-- Ctrl-click (the game's DRESSUP binding) tries it on in the dressing room, Shift-click
-- (CHATLINK) links it in chat. Holding Ctrl over something you can wear shows the magnifier.
---------------------------------------------------------------------------

local function Modified(action, fallback)
	if IsModifiedClick then return IsModifiedClick(action) end
	return fallback and fallback() or false
end

local function ItemLink(item)
	if type(item) == "string" then return item end
	if not item then return nil end
	local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local ok, _, link = pcall(getInfo, item)
	return ok and link or nil
end

-- can it go on the dressing room model? (armour, weapons, tabards, shirts)
function W.IsDressable(item)
	if not item then return false end
	local id = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
	if C_Item and C_Item.IsDressableItemByID and id then
		local ok, yes = pcall(C_Item.IsDressableItemByID, id)
		if ok then return yes and true or false end
	end
	if IsDressableItem then
		local ok, yes = pcall(IsDressableItem, ItemLink(item) or ("item:" .. tostring(id)))
		if ok then return yes and true or false end
	end
	local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	local equipLoc = instant and id and select(4, instant(id))
	return equipLoc ~= nil and equipLoc ~= "" and equipLoc ~= "INVTYPE_BAG" and equipLoc ~= "INVTYPE_AMMO"
		and equipLoc ~= "INVTYPE_QUIVER" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
end

-- handles a modified click on an item (ID or link); true when it did something with it
function W.ItemModifiedClick(item)
	if not item then return false end
	if Modified("DRESSUP", IsControlKeyDown) then
		if W.IsDressable(item) then
			local link = ItemLink(item) or ("item:" .. tostring(item))
			local dress = DressUpItemLink or DressUpLink
			if dress then pcall(dress, link) end
		end
		return true   -- Ctrl-click never also opens a page, as in the game's own windows
	end
	if Modified("CHATLINK", IsShiftKeyDown) then
		local link = ItemLink(item)
		-- true only when a chat box took it, so Shift-click still opens pages otherwise
		if link and ChatEdit_InsertLink and ChatEdit_InsertLink(link) then return true end
	end
	return false
end

-- the magnifier while Ctrl is held over a wearable item; getItem(frame) returns its ID or link
local function CursorFor(frame)
	local item = frame.itemCursorGet and frame.itemCursorGet(frame)
	if item and Modified("DRESSUP", IsControlKeyDown) and W.IsDressable(item) and ShowInspectCursor then
		ShowInspectCursor()
	elseif ResetCursor then
		ResetCursor()
	end
end
function W.ItemCursor(frame, getItem)
	frame.itemCursorGet = getItem
	frame:HookScript("OnEnter", function(self)
		CursorFor(self)
		self:RegisterEvent("MODIFIER_STATE_CHANGED")
	end)
	frame:HookScript("OnLeave", function(self)
		self:UnregisterEvent("MODIFIER_STATE_CHANGED")
		if ResetCursor then ResetCursor() end
	end)
	frame:HookScript("OnEvent", function(self, event)
		if event == "MODIFIER_STATE_CHANGED" and self:IsMouseOver() then CursorFor(self) end
	end)
end

local function Try(frameType, name, parent, template)
	local ok, f = pcall(CreateFrame, frameType, name, parent, template)
	if ok and f then return f, true end
	return CreateFrame(frameType, name, parent), false
end
W.Try = Try

-- first font object that exists
local function Font(...)
	for i = 1, select("#", ...) do
		local f = _G[select(i, ...)]
		if f then return f end
	end
	return GameFontNormal
end
W.Font = Font

W.FONT_TITLE = function() return Font("QuestTitleFont", "GameFontNormalHuge", "GameFontNormalLarge") end
W.FONT_HEAD = function() return Font("QuestTitleFontBlackShadow", "GameFontNormalLarge", "GameFontNormal") end
W.FONT_BODY = function() return Font("QuestFont", "GameFontBlackMedium", "GameFontBlack") end
W.FONT_SMALL = function() return Font("QuestFontNormalSmall", "GameFontBlackSmall", "GameFontBlack") end

-- what each kind of record is called and its icon (journal rows, details)
-- Icons are lists of candidates: some icon files don't exist on this client (INV_Misc_Map_01 shows a
-- red X), so the first one the game can load is used, and the book icon is the last resort.
W.KIND = {
	zone = { label = L["Zone"], icon = { 4624629, "INV_Scroll_03", "INV_Misc_Map08" } },   -- 4624629 picked in game with /aa whatis
	subzone = { label = L["Place"], icon = { "INV_Misc_Map02" } },
	instance = { label = L["Dungeon"], icon = { 655958, "INV_Misc_Key_14", "INV_Misc_Key_03" } },   -- 655958 picked in game with /aa whatis
	level = { label = L["Level"], icon = { "Spell_Holy_SurgeOfLight", "Spell_Holy_HolyBolt", "Spell_ChargePositive" } },
	character = { label = L["Character"], icon = { "INV_Misc_GroupNeedMore", "Achievement_Character_Human_Male", "INV_Misc_Head_Human_01" } },
	item = { label = L["Item"], icon = { 515958, "INV_Chest_Chain_05", "INV_Misc_Bag_08" } },   -- 515958 picked in game with /aa whatis
	merchant = { label = L["Merchant"], icon = { "INV_Misc_Coin_02", "INV_Misc_Coin_01" } },
	creature = { label = L["Creature"], icon = { 656556, "INV_Misc_Head_Dragon_01", "Ability_Hunter_Pet_Wolf" } },   -- 656556 picked in game with /aa whatis
	quest = { label = L["Quest"], icon = { 979575, "INV_Misc_Note_01", "INV_Letter_15" } },   -- 979575 picked in game with /aa whatis
	npc = { label = L["Quest giver"], icon = { "INV_Misc_Head_Human_01", "Achievement_Character_Human_Male" } },
	object = { label = L["Quest object"], icon = { "INV_Misc_Note_02", "INV_Scroll_03" } },
	trainer = { label = L["Trainer"], icon = { "INV_Misc_Book_08", "INV_Scroll_04" } },
	spell = { label = L["Spell or recipe"], icon = { "INV_Scroll_04", "INV_Misc_Book_08" } },
	townsfolk = { label = L["People"], icon = { 8197123, "INV_Misc_Spyglass_03", "INV_Misc_Head_Human_01" } },   -- 8197123 picked in game with /aa whatis
	mailbox = { label = L["Mailbox"], icon = { "INV_Letter_15" } },
	flight = { label = L["Flight path"], icon = { "Ability_Mount_Gryphon_01", "Ability_Mount_Wyvern_01", "INV_Misc_Map_01" } },
	node = { label = L["Gathering"], icon = { 237271, "Trade_Herbalism", "INV_Misc_Herb_07" } },   -- 237271 picked in game with /aa whatis
	fishing = { label = L["Fishing"], icon = { "Trade_Fishing", "INV_Misc_Fish_02" } },
	milestone = { label = L["Milestone"], icon = { "INV_Misc_Ribbon_01", "Spell_Holy_ChampionsBond", "INV_Misc_Note_06" } },
}
-- creature types: the icon shown in Bestiary rows
W.TYPE_ICON = {
	Beast = { "Ability_Hunter_Pet_Wolf", "INV_Misc_MonsterClaw_04" },
	Humanoid = { "INV_Misc_Head_Human_01", "Achievement_Character_Human_Male" },
	Undead = { "Spell_Shadow_RaiseDead", "INV_Misc_Bone_HumanSkull_01" },
	Demon = { "Spell_Shadow_SummonFelHunter", "Spell_Shadow_Metamorphosis" },
	Dragonkin = { "INV_Misc_Head_Dragon_01" },
	Elemental = { "Spell_Frost_SummonWaterElemental", "Spell_Fire_Elemental_Totem" },
	Giant = { "Ability_Warrior_Rampage", "INV_Stone_15" },
	Mechanical = { "INV_Misc_Gear_01" },
	Critter = { "Ability_Hunter_Pet_Wolf" },
}

function W.Icon(name)
	if not name then return nil end
	if type(name) == "table" then name = name[1] end
	if type(name) == "number" or name:find("\\") then return name end
	return "Interface\\Icons\\" .. name
end

-- the first candidate the game can load (SetTexture returns false for a missing file)
local known = {}
local tester
function W.FindIcon(candidates)
	if type(candidates) ~= "table" then candidates = { candidates } end
	local key = table.concat(candidates, "|")
	if known[key] then return known[key] end
	tester = tester or UIParent:CreateTexture(nil, "BACKGROUND")
	local found
	for _, c in ipairs(candidates) do
		local path = W.Icon(c)
		if tester:SetTexture(path) ~= false then found = path break end
	end
	found = found or ns.ICON
	known[key] = found
	return found
end

function W.SetIcon(texture, candidates)
	texture:SetTexture(W.FindIcon(candidates))
end

function W.KindIcon(kind)
	local k = W.KIND[kind]
	return W.FindIcon(k and k.icon or { "INV_Misc_QuestionMark" })
end

-- the game's own minimal scroll bar (the Map & Quest Log's): a thin track with end caps, a thin
-- thumb and small arrows, drawn over the old template's bar
-- Mouse-wheel scrolling: the scroll template jumps half of what's visible per notch, which flies
-- past whole sections on tall pages. Every Almanac scroll area moves a fixed step instead
-- (scroll.wheelStep: lists 3 rows, pages 40 px), times the Scroll speed setting, gliding there
-- over a moment when smooth scrolling is on. Shift + wheel keeps the old half-page jump.
local smoothing, wheelDriver = {}, nil
local function WheelSettings()
	local w = ns.db and ns.db.settings and ns.db.settings.window
	return ((w and w.scroll) or 100) / 100, not (w and w.smooth == false)
end
local function StepSmooth(self, elapsed)
	for scroll, target in pairs(smoothing) do
		local range = scroll:GetVerticalScrollRange() or 0
		if target > range then target = range smoothing[scroll] = range end
		local cur = scroll:GetVerticalScroll() or 0
		local d = target - cur
		if math.abs(d) < 0.5 or not scroll:IsVisible() then
			scroll:SetVerticalScroll(target)
			smoothing[scroll] = nil
		else
			scroll:SetVerticalScroll(cur + d * math.min(1, elapsed * 16))
		end
	end
	if not next(smoothing) then self:Hide() end
end
function W.WheelScroll(scroll, step)
	if step then scroll.wheelStep = step end
	if scroll.almanacWheel then return end
	scroll.almanacWheel = true
	scroll.wheelStep = scroll.wheelStep or 40
	if scroll.EnableMouseWheel then scroll:EnableMouseWheel(true) end
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = self:GetVerticalScrollRange() or 0
		if range <= 0 then return end
		local speed, smooth = WheelSettings()
		local amount = IsShiftKeyDown() and (self:GetHeight() or 0) / 2 or self.wheelStep * speed
		local from = smoothing[self] or self:GetVerticalScroll() or 0
		local to = math.max(0, math.min(range, from - delta * amount))
		if smooth then
			smoothing[self] = to
			if not wheelDriver then
				wheelDriver = CreateFrame("Frame")
				wheelDriver:SetScript("OnUpdate", StepSmooth)
			end
			wheelDriver:Show()
		else
			smoothing[self] = nil
			self:SetVerticalScroll(to)
		end
	end)
end

function W.SkinScroll(scroll)
	W.WheelScroll(scroll)
	local bar = type(scroll.ScrollBar) == "table" and scroll.ScrollBar or nil
	if not bar or bar.almanacSkin then return end
	if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("minimal-scrollbar-track-top")) then return end
	bar.almanacSkin = true
	pcall(function()
		for _, r in ipairs({ bar:GetRegions() }) do
			if r.GetObjectType and r:GetObjectType() == "Texture" and r ~= bar:GetThumbTexture() then r:SetAlpha(0) end
		end
		local function Track(atlas, point, h)
			local t = bar:CreateTexture(nil, "BACKGROUND")
			TryAtlas(t, atlas)
			t:SetWidth(8)
			if h then t:SetHeight(h) end
			return t
		end
		local top = Track("minimal-scrollbar-track-top", nil, 8)
		top:SetPoint("TOP", bar, "TOP", 0, 0)
		local bottom = Track("minimal-scrollbar-track-bottom", nil, 8)
		bottom:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
		local mid = Track("!minimal-scrollbar-track-middle")
		mid:SetPoint("TOP", top, "BOTTOM")
		mid:SetPoint("BOTTOM", bottom, "TOP")
		local thumb = bar:GetThumbTexture()
		if thumb then
			TryAtlas(thumb, "minimal-scrollbar-small-thumb-middle")
			thumb:SetSize(8, 40)
		end
		local name = bar.GetName and bar:GetName()
		local up = bar.ScrollUpButton or (name and _G[name .. "ScrollUpButton"])
		local down = bar.ScrollDownButton or (name and _G[name .. "ScrollDownButton"])
		for _, b in ipairs({ { up, "minimal-scrollbar-arrow-top" }, { down, "minimal-scrollbar-arrow-bottom" } }) do
			local btn, atlas = b[1], b[2]
			if btn then
				btn:SetSize(17, 11)
				for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
					local t = btn[get] and btn[get](btn)
					if t then
						local variant = get == "GetPushedTexture" and "-down" or get == "GetHighlightTexture" and "-over" or ""
						if not TryAtlas(t, atlas .. variant) then TryAtlas(t, atlas) end
						t:ClearAllPoints()
						t:SetAllPoints(btn)
						if get == "GetDisabledTexture" and t.SetDesaturated then t:SetDesaturated(true) t:SetAlpha(0.5) end
					end
				end
			end
		end
		bar:SetWidth(10)
	end)
end

-- shows a scroll frame's bar only when there is something to scroll
function W.FitScrollBar(scroll, contentHeight)
	local bar = type(scroll.ScrollBar) == "table" and scroll.ScrollBar or nil
	if bar and bar.SetShown then bar:SetShown(contentHeight > (scroll:GetHeight() or 0) + 1) end
end

-- a recessed panel (the dark marble inset of the character and quest windows)
-- Dark panels: the game's inset frame, filled with the profession window's recipe list background
-- (the dark leather behind the recipe list; the auction house's list background where it's
-- missing). Panels with a painting (W.Art) show it on top of this.
W.LIST_BG = { "Professions-background-summarylist", "auctionhouse-background-summarylist" }
function W.Inset(parent)
	local f = CreateFrame("Frame", nil, parent)
	local ok, inset = pcall(CreateFrame, "Frame", nil, f, "InsetFrameTemplate")
	if ok and inset then
		inset:SetAllPoints(f)
		inset:EnableMouse(false)
		f.inset = inset
	else
		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.45)
	end
	local host = f.inset or f
	local list = host:CreateTexture(nil, "BACKGROUND", nil, 2)
	list:SetPoint("TOPLEFT", 3, -3)
	list:SetPoint("BOTTOMRIGHT", -3, 3)
	if TryAtlas(list, unpack(W.LIST_BG)) then f.listBg = list else list:Hide() end
	return f
end

-- the quest log's parchment, filling a frame
function W.Parchment(parent)
	local t = parent:CreateTexture(nil, "BACKGROUND", nil, -6)
	t:SetAllPoints()
	-- the Map & Quest Log's own parchment (QuestMapFrame.DetailsFrame.Bg)
	if TryAtlas(t, "QuestDetailsBackgrounds") then return t end
	local ok = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("QuestBG-Parchment") and pcall(t.SetAtlas, t, "QuestBG-Parchment")
	if not ok then
		t:SetTexture("Interface\\QuestFrame\\QuestBG")
		t:SetTexCoord(0, 0.586, 0, 0.655)
	end
	return t
end

function W.Button(parent, text, width, onClick)
	local b = Try("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 100, 22)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

-- the profession window's Filter button: common-dropdown-b-button with gold text and a small arrow;
-- the red button where the art is missing
function W.Dropdown(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width or 120, 26)
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	if not TryAtlas(bg, "common-dropdown-b-button") then
		bg:Hide()
		local red = W.Button(parent, text, width, onClick)
		return red
	end
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	TryAtlas(hl, "common-dropdown-b-button")
	hl:SetBlendMode("ADD")
	hl:SetAlpha(0.3)
	b.arrow = b:CreateTexture(nil, "ARTWORK")
	b.arrow:SetSize(12, 12)
	b.arrow:SetPoint("RIGHT", -8, 0)
	b.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	b.label:SetPoint("LEFT", 10, 0)
	b.label:SetPoint("RIGHT", b.arrow, "LEFT", -4, 0)
	b.label:SetText(text)
	function b:SetText(t) self.label:SetText(t) end
	function b:GetText() return self.label:GetText() end
	b:SetScript("OnClick", function(self)
		if SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON then PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON) end
		onClick(self)
	end)
	return b
end

function W.Check(parent, label, get, set, tooltip)
	local cb = Try("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	-- the Settings panel's minimal checkbox and tick
	pcall(function()
		local box = cb:CreateTexture(nil, "BACKGROUND")
		local tick = cb:CreateTexture(nil, "ARTWORK")
		if TryAtlas(box, "checkbox-minimal") and TryAtlas(tick, "checkmark-minimal") then
			box:SetAllPoints()
			tick:SetAllPoints()
			cb:SetNormalTexture(box)
			cb:SetCheckedTexture(tick)
			local p, h, d = cb:GetPushedTexture(), cb:GetHighlightTexture(), cb:GetDisabledCheckedTexture()
			if p then p:SetAlpha(0) end
			if d then d:SetAlpha(0.4) end
			if h then h:ClearAllPoints() h:SetAllPoints(box) h:SetAlpha(0.3) end
		else
			box:Hide()
			tick:Hide()
		end
	end)
	local text = (type(cb.Text) == "table" and cb.Text) or (type(cb.text) == "table" and cb.text) or nil
	if not text then
		text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	end
	text:SetText(label)
	cb.label = text
	cb:SetScript("OnShow", function(self) self:SetChecked(get() and true or false) end)
	cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
	if tooltip then
		cb:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(label)
			GameTooltip:AddLine(tooltip, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		cb:SetScript("OnLeave", GameTooltip_Hide)
	end
	cb:SetChecked(get() and true or false)
	return cb
end

-- search box with the game's magnifier and clear button; onChange(text) as you type
function W.Search(parent, width, onChange)
	local box, templated = Try("EditBox", nil, parent, "SearchBoxTemplate")
	if not templated then
		box:Hide()
		box = Try("EditBox", nil, parent, "InputBoxTemplate")
	end
	box:SetSize(width or 180, 20)
	-- the Map & Quest Log's search border and magnifying glass
	pcall(function()
		local l, m, r = box.Left, box.Middle or box.Mid, box.Right
		if type(l) == "table" and type(m) == "table" and type(r) == "table"
			and TryAtlas(l, "common-search-border-left") and TryAtlas(m, "common-search-border-middle") and TryAtlas(r, "common-search-border-right") then
			l:ClearAllPoints() l:SetSize(8, 20) l:SetPoint("LEFT", box, "LEFT", -6, 0)
			r:ClearAllPoints() r:SetSize(8, 20) r:SetPoint("RIGHT", box, "RIGHT", 2, 0)
			m:ClearAllPoints() m:SetPoint("TOPLEFT", l, "TOPRIGHT") m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
		end
		local icon = box.searchIcon or box.SearchIcon
		if type(icon) == "table" and TryAtlas(icon, "common-search-magnifyingglass") then icon:SetSize(12, 12) end
	end)
	box:SetAutoFocus(false)
	box:SetMaxLetters(60)
	box:HookScript("OnTextChanged", function(self) onChange((self:GetText() or ""):lower()) end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	return box
end

---------------------------------------------------------------------------
-- Scrolling list: only the rows in view exist, so long lists stay cheap.
-- opts = { rowHeight = 22, onClick = function(item, index), update = function(row, item, index) }
-- list:SetData(items), list:Select(item), list:Refresh()
---------------------------------------------------------------------------



-- Rows in the My Characters look (Plus Everything's inventory window, which the user picked as the
-- Almanac's style): group headings in small grey capitals with a grey - / + at the right; entries
-- with a faint hover and a flat gold fill when selected. opts.round puts each entry's icon in a
-- round frame with a thin ring (people and creatures), else a square icon with a thin edge.
local WHITE = "Interface\\Buttons\\WHITE8X8"
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
W.WHITE, W.CIRCLE = WHITE, CIRCLE
W.GOLD = { 1, 0.82, 0.25 }
W.SELECTED = { 0.45, 0.33, 0.12, 0.5 }

-- An atlas stretched sideways without stretching its ends: cut into left / middle / right from the
-- atlas's own coordinates (cap = source pixels kept at each end). Returns a frame, or nil when the
-- client lacks the atlas. Used for the quest log / Skills window heading boxes.
function W.Slice3(parent, atlas, cap, layer)
	if not (C_Texture and C_Texture.GetAtlasInfo) then return nil end
	local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
	if not ok or not info then return nil end
	local file = info.file or info.filename
	local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
	cap = cap or 12
	local capU = (r - l) * (cap / (info.width or 64))
	local f = CreateFrame("Frame", nil, parent)
	local function Piece(u0, u1)
		local tex = f:CreateTexture(nil, layer or "BACKGROUND")
		tex:SetTexture(file)
		tex:SetTexCoord(u0, u1, t, b)
		return tex
	end
	local left, right, mid = Piece(l, l + capU), Piece(r - capU, r), Piece(l + capU, r - capU)
	f:SetScript("OnSizeChanged", function(self, _, h)
		local w = math.floor(cap * (h or 0) / (info.height or 28) + 0.5)
		left:SetWidth(w) right:SetWidth(w)
	end)
	left:SetPoint("TOPLEFT") left:SetPoint("BOTTOMLEFT") left:SetWidth(cap)
	right:SetPoint("TOPRIGHT") right:SetPoint("BOTTOMRIGHT") right:SetWidth(cap)
	mid:SetPoint("TOPLEFT", left, "TOPRIGHT") mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
	return f
end

-- List rows as in the profession window's recipe list: grey glow under the mouse
-- (Professions_Recipe_Hover, captured with /aa whatis), the gold bar on the selected entry
-- (Professions_Recipe_Active). The flat fills stay where the client lacks the art.
function W.RowHover(tex)
	if TryAtlas(tex, "Professions_Recipe_Hover") then tex:SetVertexColor(1, 1, 1, 1) return true end
	tex:SetColorTexture(1, 1, 1, 0.05)
	return false
end
function W.RowSelected(tex)
	if TryAtlas(tex, "Professions_Recipe_Active", "Professions_Recipe_Selected") then tex:SetVertexColor(1, 1, 1, 1) return true end
	tex:SetColorTexture(unpack(W.SELECTED))
	return false
end

-- style "log": the Map & Quest Log's look (the Quests page's rows, shared): headings in the gold-edged
-- box (common-button-list-collapseExpand, 3-sliced) with light text and a gold - / +, entries in the
-- quest titles' font, the log's yellow glow (QuestLog-quest-glow-yellow) under the mouse and on the
-- selected entry. The box is its own layer and the words / icons sit on a layer above it.
local function LogGlow(row, layer, alpha)
	local g = row:CreateTexture(nil, layer, nil, 1)
	g:SetPoint("TOPLEFT", 20, 0)
	g:SetPoint("BOTTOMRIGHT", -24, 0)
	if not TryAtlas(g, "QuestLog-quest-glow-yellow") then g:SetColorTexture(1, 0.82, 0.2, 0.12) end
	g:SetAlpha(alpha)
	return g
end

local function DefaultRow(parent, height, round, style)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(height)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local log = style == "log"
	local hover, sel
	if log then
		hover = LogGlow(row, "HIGHLIGHT", 0.6)
		sel = LogGlow(row, "BACKGROUND", 1)
	else
		hover = row:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints()
		W.RowHover(hover)
		sel = row:CreateTexture(nil, "BACKGROUND")
		sel:SetPoint("TOPLEFT", 0, -1)
		sel:SetPoint("BOTTOMRIGHT", 0, 1)
		W.RowSelected(sel)
	end
	row.hover = { hover }
	-- log style: the heading box, and a layer above it for everything drawn on the row
	local layer = row
	if log then
		row.bar = W.Slice3(row, "common-button-list-collapseExpand", 14)
		if not row.bar then
			row.bar = CreateFrame("Frame", nil, row)
			local t = row.bar:CreateTexture(nil, "BACKGROUND")
			t:SetAllPoints()
			t:SetColorTexture(0.2, 0.14, 0.06, 0.9)
		end
		row.bar:SetPoint("TOPLEFT", 2, -1)
		row.bar:SetPoint("BOTTOMRIGHT", -2, 1)
		row.bar:SetFrameLevel(row:GetFrameLevel() + 1)
		row.bar:Hide()
		layer = CreateFrame("Frame", nil, row)
		layer:SetAllPoints()
		layer:SetFrameLevel(row:GetFrameLevel() + 2)
	end
	row.sel = { sel }
	row.selected = { SetShown = function(_, on) sel:SetShown(on and true or false) end, Hide = function() sel:Hide() end }
	sel:Hide()
	row.icon = layer:CreateTexture(nil, "ARTWORK")
	local size = height - (round and 6 or 8)
	row.icon:SetSize(size, size)
	row.icon:SetPoint("LEFT", 4, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	-- the frame round the icon follows the icon wherever a page moves it
	if round then
		row.ring = layer:CreateTexture(nil, "BORDER")
		row.ring:SetTexture(CIRCLE)
		row.ring:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -2, 2)
		row.ring:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 2, -2)
		row.ring:SetVertexColor(0.62, 0.5, 0.24)
		local mask = layer:CreateMaskTexture()
		mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(row.icon)
		if row.icon.AddMaskTexture then row.icon:AddMaskTexture(mask) end
	else
		row.ring = layer:CreateTexture(nil, "BORDER")
		row.ring:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -1, 1)
		row.ring:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 1, -1)
		row.ring:SetColorTexture(0.32, 0.26, 0.15, 1)
	end
	function row:SetRing(r, g, b) if round then self.ring:SetVertexColor(r, g, b) end end
	row.text = layer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	row.right = layer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.right:SetPoint("RIGHT", -6, 0)
	row.right:SetJustifyH("RIGHT")
	row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
	-- headings: the list's own - / +, greyed to sit with the grey capitals
	row.state = layer:CreateTexture(nil, "ARTWORK")
	row.state:SetPoint("RIGHT", -8, 0)
	local nativeState = TryAtlas(row.state, "common-button-list-minus")
	local plusBar
	if not nativeState then
		row.state:SetSize(9, 2)
		row.state:SetColorTexture(1, 1, 1, 1)
		plusBar = layer:CreateTexture(nil, "ARTWORK")
		plusBar:SetSize(2, 9)
		plusBar:SetPoint("CENTER", row.state, "CENTER")
		plusBar:SetColorTexture(1, 1, 1, 1)
		plusBar:SetVertexColor(0.6, 0.6, 0.6)
	end
	row.state:SetVertexColor(0.6, 0.6, 0.6)
	if row.state.SetDesaturated then row.state:SetDesaturated(not log) end
	if log then row.state:SetVertexColor(1, 1, 1) row.state:SetPoint("RIGHT", -10, 0) end
	function row:SetHeader(on, collapsed)
		self.isHeader = on
		hover:SetShown(not on)   -- headings have their own look; no row glow on them
		self.state:SetShown(on)
		if self.bar then self.bar:SetShown(on) end
		if on and nativeState then
			local big = log and 12 or 10
			if collapsed then TryAtlas(self.state, "common-button-list-plus") self.state:SetSize(big, big)
			else TryAtlas(self.state, "common-button-list-minus") self.state:SetSize(big, 3) end
			if log then self.state:SetVertexColor(1, 1, 1) else self.state:SetVertexColor(0.6, 0.6, 0.6) end
		end
		if plusBar then plusBar:SetShown(on and collapsed and true or false) end
		self.right:ClearAllPoints()
		if on then
			self.right:SetPoint("RIGHT", self.state, "LEFT", -8, 0)
		else
			self.right:SetPoint("RIGHT", -6, 0)
		end
	end
	-- after a page fills a heading: grey capitals, no icon, as "CLASSIC BETA PVE"
	function row:StyleHeader()
		if not self.isHeader then
			self.ring:SetShown(self.icon:IsShown() and self.icon:GetTexture() ~= nil)
			return
		end
		self.icon:Hide()
		self.ring:Hide()
		-- (row.indent: a heading nested under another, e.g. a zone under its continent)
		local ind = self.indent or 0
		if self.bar then self.bar:SetPoint("TOPLEFT", 2 + ind, -1) end
		local text = self.text:GetText() or ""
		text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		if log then
			-- the quest log's headings: light, a size up from the entries, as written
			self.text:SetFontObject(Font("GameFontHighlightMedium", "GameFontNormalMed1", "GameFontHighlight"))
			self.text:SetTextColor(0.86, 0.84, 0.78)
			self.text:ClearAllPoints()
			self.text:SetPoint("LEFT", 10 + ind, 0)
			self.text:SetPoint("RIGHT", self.right, "LEFT", -6, 0)
			self.text:SetText(text)
			return
		end
		self.text:SetFontObject(GameFontDisableSmall)
		self.text:SetTextColor(0.62, 0.62, 0.62)
		self.text:ClearAllPoints()
		self.text:SetPoint("LEFT", 6 + ind, 0)
		self.text:SetPoint("RIGHT", self.right, "LEFT", -6, 0)
		self.text:SetText(text:upper())
	end
	function row:UnstyleHeader()
		self.indent = 0
		if self.bar then self.bar:SetPoint("TOPLEFT", 2, -1) end
		self.icon:Show()
		self.text:SetFontObject(GameFontNormal)
		self.text:ClearAllPoints()
		self.text:SetPoint("LEFT", self.icon, "RIGHT", 7, 0)
		self.text:SetPoint("RIGHT", self.right, "LEFT", -6, 0)
		self.text:SetTextColor(1, 0.82, 0)
	end
	function row:SetSpacer(on)
		self.spacer = on
		self.icon:SetShown(not on)
		self.ring:SetShown(not on)
		self.text:SetShown(not on)
		self.right:SetShown(not on)
		hover:SetShown(not on)
		if on then self:SetHeader(false) self.selected:Hide() if self.bar then self.bar:Hide() end end
		self:EnableMouse(not on)
	end
	row:SetHeader(false)
	return row
end

function W.List(parent, opts)
	local holder = CreateFrame("Frame", nil, parent)
	holder.opts = opts
	-- the page being built remembers its (first) list, for the window's Back button
	local building = ns.UI and ns.UI.building
	if building and building.list == nil then building.list = holder end
	local rh = opts.rowHeight or 22
	local scroll = Try("ScrollFrame", nil, holder, "UIPanelScrollFrameTemplate")
	W.SkinScroll(scroll)
	W.WheelScroll(scroll, rh * 3) -- three rows a notch
	scroll:SetPoint("TOPLEFT", 4, -4)
	scroll:SetPoint("BOTTOMRIGHT", -24, 4)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(1, 1)
	scroll:SetScrollChild(child)
	holder.scroll, holder.child = scroll, child
	local rows, data, selected = {}, {}, nil

	local empty = holder:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	empty:SetPoint("CENTER")
	empty:SetWidth(220)
	empty:SetText(opts.emptyText or L["Nothing discovered yet."])

	-- lists with folding headings: "Collapse all" / "Expand all" across the top.
	-- opts.collapse = { state = the page's collapsed table, key = function(row) -> heading key or nil, refresh = function() }
	local toggle
	if opts.collapse then
		toggle = CreateFrame("Button", nil, holder)
		toggle:SetHeight(20)
		toggle:SetPoint("TOPLEFT", 8, -5)
		toggle:SetPoint("TOPRIGHT", -26, -5)
		toggle.icon = toggle:CreateTexture(nil, "ARTWORK")
		toggle.icon:SetPoint("RIGHT", -4, 0)
		toggle.text = toggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		toggle.text:SetPoint("RIGHT", toggle.icon, "LEFT", -8, 0)
		toggle.text:SetTextColor(0.75, 0.75, 0.75)
		toggle.rule = toggle:CreateTexture(nil, "ARTWORK")
		toggle.rule:SetHeight(1)
		toggle.rule:SetPoint("BOTTOMLEFT", 0, -3)
		toggle.rule:SetPoint("BOTTOMRIGHT", 0, -3)
		-- the Skills list's own divider line, else a gold rule fading in
		if TryAtlas(toggle.rule, "UI-Character-Info-ScrollLine-Long") then toggle.rule:SetHeight(6) toggle.rule:SetPoint("BOTTOMLEFT", -6, -6) toggle.rule:SetPoint("BOTTOMRIGHT", 6, -6)
		else
			toggle.rule:SetColorTexture(1, 1, 1, 1)
			Fade(toggle.rule, "HORIZONTAL", 0.6, 0.5, 0.3, 0, 0.6)
		end
		toggle:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 0.82, 0) end)
		toggle:SetScript("OnLeave", function(self) self.text:SetTextColor(0.75, 0.75, 0.75) end)
		toggle:SetScript("OnClick", function(self)
			local target = not self.allCollapsed
			for _, k in ipairs(self.keys or {}) do opts.collapse.state[k] = target or nil end
			if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
			opts.collapse.refresh()
		end)
		scroll:SetPoint("TOPLEFT", 4, -30)
		holder.toggle = toggle
	end
	local function UpdateToggle()
		if not toggle then return end
		local keys, all = {}, true
		for _, r in ipairs(data) do
			local k = not r.spacer and opts.collapse.key(r)
			if k ~= nil and k ~= false then
				keys[#keys + 1] = k
				if not opts.collapse.state[k] then all = false end
			end
		end
		toggle.keys = keys
		toggle.allCollapsed = #keys > 0 and all
		toggle.text:SetText(toggle.allCollapsed and L["Expand all"] or L["Collapse all"])
		if toggle.allCollapsed then
			if TryAtlas(toggle.icon, "common-button-list-plus") then toggle.icon:SetSize(10, 10) else toggle.icon:SetTexture("Interface\\Buttons\\UI-PlusButton-Up") toggle.icon:SetSize(14, 14) end
		else
			if TryAtlas(toggle.icon, "common-button-list-minus") then toggle.icon:SetSize(10, 3) else toggle.icon:SetTexture("Interface\\Buttons\\UI-MinusButton-Up") toggle.icon:SetSize(14, 14) end
		end
		toggle.icon:SetVertexColor(0.75, 0.75, 0.75)
		toggle:SetShown(#keys > 1)
		-- no toggle: the list takes the room back
		scroll:SetPoint("TOPLEFT", 4, #keys > 1 and -30 or -4)
	end

	function holder:Refresh()
		local width = scroll:GetWidth()
		child:SetWidth(width > 0 and width or 1)
		child:SetHeight(math.max(#data * rh, 1))
		local offset = scroll:GetVerticalScroll() or 0
		local first = math.floor(offset / rh) + 1
		local visible = math.ceil((scroll:GetHeight() or 0) / rh) + 1
		for i = 1, math.max(visible, #rows) do
			local index = first + i - 1
			local row = rows[i]
			if i <= visible and data[index] then
				if not row then
					row = (opts.build and opts.build(child, rh)) or DefaultRow(child, rh, opts.round, opts.style)
					row:SetScript("OnClick", function(self, mouse)
						if self.item == nil then return end
						-- headings fold; they're never "selected" (that would drop the record being read)
						if mouse == "LeftButton" and self.item.header == nil then holder:Select(self.item) end
						if opts.onClick then opts.onClick(self.item, self.index, mouse) end
					end)
					-- (opts.onHover(item) / opts.onLeave(item): a page can preview what's under the mouse)
					if opts.onHover then row:HookScript("OnEnter", function(self) if self.item then opts.onHover(self.item) end end) end
					if opts.onLeave then row:HookScript("OnLeave", function(self) opts.onLeave(self.item) end) end
					-- lists of items: the magnifier while Ctrl is held, as on item slots
					if opts.itemOf then W.ItemCursor(row, function(r) return r.item and opts.itemOf(r.item) end) end
					rows[i] = row
				end
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(index - 1) * rh)
				row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
				row:Show()
				if data[index].spacer then
					row.item, row.index = nil, index
					if row.SetSpacer then row:SetSpacer(true) end
				else
					if row.SetSpacer and row.spacer then row:SetSpacer(false) end
					row.item, row.index = data[index], index
					if row.UnstyleHeader then row:UnstyleHeader() end
					if row.SetHeader then row:SetHeader(false) end
					opts.update(row, data[index], index)
					if row.StyleHeader then row:StyleHeader() end
					if row.selected then row.selected:SetShown(data[index] == selected) end
				end
			elseif row then
				row.item = nil
				row:Hide()
			end
		end
		empty:SetShown(#data == 0)
		W.FitScrollBar(scroll, #data * rh)
	end

	-- a little space above each heading after the first, as in the profession window
	function holder:SetData(items)
		data = {}
		for i, it in ipairs(items or {}) do
			if opts.spacers ~= false and opts.style ~= "log" and i > 1 and (it.header ~= nil or it.kind == "zone" or it.kind == "header") then data[#data + 1] = { spacer = true } end
			data[#data + 1] = it
		end
		local maxScroll = math.max(#data * rh - (scroll:GetHeight() or 0), 0)
		if (scroll:GetVerticalScroll() or 0) > maxScroll then scroll:SetVerticalScroll(maxScroll) end
		UpdateToggle()
		self:Refresh()
	end

	function holder:Select(item)
		selected = item
		self:Refresh()
	end

	function holder:Selected() return selected end

	-- shows an item again after coming back to this page: the same row in the current data (matched
	-- on its plain fields, since the data may have been rebuilt), as if it had been clicked
	function holder:Restore(item)
		if type(item) ~= "table" then return end
		local match
		for _, d in ipairs(data) do
			if type(d) == "table" and not d.spacer then
				local same, any = true, false
				for k, v in pairs(item) do
					local t = type(v)
					if t == "string" or t == "number" or t == "boolean" then
						any = true
						if d[k] ~= v then same = false break end
					end
				end
				if same and any then match = d break end
			end
		end
		match = match or item
		self:Select(match)
		if opts.restore then opts.restore(match)
		elseif opts.onClick then opts.onClick(match, nil, "LeftButton") end
	end
	function holder:Data() return data end
	function holder:SetEmptyText(text) empty:SetText(text) end

	scroll:HookScript("OnVerticalScroll", function() holder:Refresh() end)
	scroll:HookScript("OnSizeChanged", function() holder:Refresh() end)
	scroll:EnableMouseWheel(true)
	return holder
end

---------------------------------------------------------------------------
-- Detail pane, in WoW Forever's own two looks:
--   "dark"      (default) the character sheet: gold banner headers, gold-label / white-value stat
--               rows, skill-style bars, white text. For facts: creatures, items, merchants, places.
--   "parchment" the quest log: dark serif headings on parchment. For story text: journal, lore.
-- Item and ability lists are drawn like quest rewards: an icon slot with a name plate, two to a
-- row, with the game's own tooltip on hover (shift-click links an item in chat).
-- pane:SetBlocks({
--   { "title", "Thistlefur Shaman" }, { "banner", "General" }, { "stat", "Level", "23-24" },
--   { "bar", "Studied", 7, 10, "7 / 10 kills" }, { "skillbar", nil, 7, 10, "7 / 10" } (the blue skills bar), { "body", text }, { "small", text }, { "gap", 8 },
--   { "slots", { { item = 2592, note = "3 / 4 (75%)" }, { spell = 11986, note = "seen" }, { icon = 132000, name = "...", note = "..." } } },
-- }, emptyText)
---------------------------------------------------------------------------

local function HasAtlas(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

---------------------------------------------------------------------------
-- The profession window's paintings, as backgrounds (the Professions book look)
--   Profession-overview-Card-<Prof>          664x142  wide header card (primary professions)
--   Profession-overview-card-generic-<prof>  225x275  secondary professions' cards
--   Profession-background-card-<Prof>        360x484  the crafting page's tall painting
--   Profession-Background-Overview           665x570  the book's own background
-- Recorded in the game: Blacksmithing, Mining (overview + background), Cooking, Fishing, First Aid
-- (generic + background). The other professions use the same names and are tried first, with
-- recorded ones as fallbacks. /aa cards lists which ones this client has.
---------------------------------------------------------------------------

W.PROFESSIONS = { "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism", "Leatherworking",
	"Mining", "Skinning", "Tailoring", "Cooking", "FirstAid", "Fishing" }

-- Fills width x height with the first atlas that exists, without stretching (crops, like "cover").
function W.CoverAtlas(texture, candidates, width, height)
	if not (C_Texture and C_Texture.GetAtlasInfo) or not width or width <= 0 or not height or height <= 0 then return false end
	for _, name in ipairs(candidates) do
		local info = C_Texture.GetAtlasInfo(name)
		if info and info.file and info.width and info.width > 0 then
			local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
			local scale = math.max(width / info.width, height / info.height)
			local keepW, keepH = width / (info.width * scale), height / (info.height * scale)
			local cx, cy = (r - l) * (1 - keepW) / 2, (b - t) * (1 - keepH) / 2
			texture:SetTexture(info.file)
			texture:SetTexCoord(l + cx, r - cx, t + cy, b - cy)
			texture:SetSize(width, height)
			return name
		end
	end
	return false
end

local function Exists(name) return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil end

-- the atlases for a theme: a profession name or a list of them (the first one the client has wins)
function W.ThemeAtlases(theme)
	local list = type(theme) == "table" and theme or { theme or "Blacksmithing" }
	local wide, tall = {}, {}
	for _, prof in ipairs(list) do
		wide[#wide + 1] = "Profession-overview-Card-" .. prof
		wide[#wide + 1] = "Profession-overview-card-generic-" .. prof:lower()
		tall[#tall + 1] = "Profession-background-card-" .. prof
	end
	for _, prof in ipairs({ "Blacksmithing", "Mining" }) do wide[#wide + 1] = "Profession-overview-Card-" .. prof end
	wide[#wide + 1] = "Profession-overview-Card"
	for _, prof in ipairs({ "Blacksmithing", "Mining", "Cooking", "Fishing", "FirstAid" }) do tall[#tall + 1] = "Profession-background-card-" .. prof end
	return wide, tall
end

function W.ExistingAtlas(candidates)
	for _, name in ipairs(candidates) do if Exists(name) then return name end end
end

-- a painting layer in a panel: art:Set(candidates, "cover" | "corner", alpha). "cover" fills the
-- panel (header cards); "corner" stands the painting in the bottom right at the panel's height,
-- faded, as the profession book's secondary cards do. Redrawn when the panel changes size.
function W.Art(panel, level)
	local holder = CreateFrame("Frame", nil, panel)
	holder:SetPoint("TOPLEFT", 3, -3)
	holder:SetPoint("BOTTOMRIGHT", -3, 3)
	holder:SetFrameLevel(level or (panel:GetFrameLevel() + 2))
	holder:EnableMouse(false)
	local tex = holder:CreateTexture(nil, "BACKGROUND")
	local fade = holder:CreateTexture(nil, "BACKGROUND", nil, 1)
	fade:Hide()
	local want
	local function Draw()
		if not want then tex:Hide() fade:Hide() return end
		local w, h = holder:GetWidth(), holder:GetHeight()
		if not w or w <= 0 or not h or h <= 0 then return end
		tex:ClearAllPoints()
		fade:Hide()
		local ok
		if want.mode == "corner" then
			local name = W.ExistingAtlas(want.list)
			local info = name and C_Texture.GetAtlasInfo(name)
			if info and info.width and info.height and info.height > 0 then
				local ph = math.min(h, info.height * 1.6)
				local pw = ph * info.width / info.height
				tex:SetAtlas(name)
				tex:SetSize(pw, ph)
				tex:SetPoint("BOTTOMRIGHT")
				ok = true
			end
		else
			ok = W.CoverAtlas(tex, want.list, w, h)
			tex:SetPoint("CENTER")
			if ok and not want.clear then
				-- darker towards the left, where the name and facts sit
				fade:ClearAllPoints()
				fade:SetAllPoints(tex)
				W.Fade(fade, "HORIZONTAL", 0.03, 0.025, 0.02, 0.55, 0)
				fade:Show()
			end
		end
		tex:SetAlpha(want.alpha or 1)
		tex:SetShown(ok and true or false)
	end
	holder:SetScript("OnSizeChanged", Draw)
	function holder:Set(list, mode, alpha, clear)
		want = list and { list = list, mode = mode, alpha = alpha, clear = clear } or nil
		Draw()
	end
	return holder
end

-- A section heading in the My Characters look: a small icon, the title in gold, a grey count
-- after it ("Backpack  20 / 20") and a thin bronze rule underneath.
-- The count is taken from a title ending in "(n)"; the icon from the title (SECTION_ICON).
local SECTION_ICON = {
	["General"] = { "INV_Misc_Note_01" }, ["Health"] = { "INV_Potion_54", "INV_Potion_51" },
	["Abilities"] = { "INV_Misc_Book_11", "INV_Misc_Book_09" }, ["Defenses"] = { "INV_Shield_06", "INV_Shield_04" },
	["Loot"] = { "INV_Misc_Bag_10", "INV_Misc_Bag_08" }, ["Loot from its bosses"] = { "INV_Misc_Bag_10", "INV_Misc_Bag_08" },
	["Skinning and gathering"] = { "INV_Misc_Pelt_Wolf_01", "Trade_Herbalism" },
	["Where"] = { "INV_Misc_Map02" }, ["Places found here"] = { "INV_Misc_Map02" }, ["Explored by"] = { "INV_Misc_Map02" },
	["Wanted for quests"] = { "INV_Misc_Note_02" }, ["Quests"] = { "INV_Misc_Note_02" }, ["Quest rewards"] = { "INV_Misc_Note_02" },
	["Quests offered here"] = { "INV_Misc_Note_02" }, ["Quest Givers"] = { "INV_Misc_Note_02" }, ["What it asks for"] = { "INV_Misc_Note_02" },
	["First to discover"] = { "INV_Misc_Spyglass_02", "INV_Misc_Spyglass_03" }, ["Levels"] = { "Spell_Holy_HolyBolt" },
	["Bosses met"] = { "INV_Misc_Head_Dragon_01" }, ["Creatures"] = { "Ability_Hunter_Pet_Wolf", "INV_Misc_MonsterClaw_04" },
	["Your characters"] = { "INV_Misc_GroupNeedMore", "INV_Misc_Head_Human_01" }, ["Your Characters"] = { "INV_Misc_GroupNeedMore", "INV_Misc_Head_Human_01" },
	["Dropped by"] = { "INV_Misc_MonsterClaw_04" }, ["Sold by"] = { "INV_Misc_Coin_02" }, ["Merchants"] = { "INV_Misc_Coin_02" },
	["For sale"] = { "INV_Misc_Coin_02" }, ["Made by"] = { "Trade_BlackSmithing" }, ["Makes"] = { "Trade_BlackSmithing" },
	["Reagent for"] = { "Trade_BlackSmithing" }, ["Other sources"] = { "INV_Misc_QuestionMark" }, ["Record"] = { "INV_Scroll_03" },
	["Trainers"] = { "INV_Misc_Book_08" }, ["All ranks"] = { "INV_Scroll_04" }, ["Details"] = { "INV_Scroll_04" },
	["Description"] = { "INV_Scroll_03" }, ["Progress"] = { "INV_Misc_Note_02" }, ["Completion"] = { "INV_Misc_Note_02" },
	["Rewards"] = { "INV_Misc_Bag_10" }, ["The Story"] = { "INV_Misc_Book_09" },
}
W.SECTION_ICON = SECTION_ICON

local function Banner(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(24)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(18, 18)
	f.icon:SetPoint("LEFT", 2, 1)
	f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.title:SetPoint("LEFT", f.icon, "RIGHT", 6, 0)
	f.detail = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.detail:SetPoint("LEFT", f.title, "RIGHT", 8, 0)
	f.line = f:CreateTexture(nil, "ARTWORK")
	f.line:SetColorTexture(0.45, 0.36, 0.18, 0.4)
	f.line:SetHeight(1)
	f.line:SetPoint("BOTTOMLEFT", 0, -2)
	f.line:SetPoint("BOTTOMRIGHT", 0, -2)
	-- text, detail (optional, else from "(n)"), icon (optional)
	function f:Set(text, detail, icon)
		text = text or ""
		local base, n = text:match("^(.-)%s*%((%d+)%)$")
		if base and not detail then text, detail = base, n end
		self.title:SetText(text)
		self.detail:SetText(detail or "")
		local candidates = icon or SECTION_ICON[text] or SECTION_ICON[(text:gsub("%s*%(.*$", ""))]
		if candidates then
			W.SetIcon(self.icon, candidates)
			self.icon:Show()
			self.title:SetPoint("LEFT", self.icon, "RIGHT", 6, 0)
		else
			self.icon:Hide()
			self.title:SetPoint("LEFT", self, "LEFT", 2, 0)
		end
	end
	f.text = { SetText = function(_, t) f:Set(t) end }
	return f
end
W.Section = Banner

-- a name in the window's title font (the My Characters name: Morpheus, large)
function W.HeroFont(fs, size)
	if not pcall(fs.SetFont, fs, "Fonts\\MORPHEUS.TTF", size or 24, "") then
		fs:SetFontObject(W.Font("GameFontNormalHuge", "GameFontNormalLarge"))
	end
	fs:SetShadowOffset(1, -1)
	fs:SetShadowColor(0, 0, 0, 1)
	return fs
end

-- a round portrait in a coloured ring, as in My Characters: p.art (masked round), p:SetRing(r, g, b)
function W.Portrait(parent, size)
	local p = CreateFrame("Frame", nil, parent)
	p:SetSize(size, size)
	p.ring = p:CreateTexture(nil, "BACKGROUND")
	p.ring:SetTexture(CIRCLE)
	p.ring:SetAllPoints()
	p.ring:SetVertexColor(0.62, 0.5, 0.24)
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
	if p.art.AddMaskTexture then p.art:AddMaskTexture(mask) end
	function p:SetRing(r, g, b) self.ring:SetVertexColor(r, g, b) end
	-- a thinner ring (the tier badges): half the coloured edge, the art a little larger
	function p:SetThin()
		self.inner:SetPoint("TOPLEFT", 1, -1)
		self.inner:SetPoint("BOTTOMRIGHT", -1, 1)
		self.art:SetPoint("TOPLEFT", 2, -2)
		self.art:SetPoint("BOTTOMRIGHT", -2, 2)
		return self
	end
	return p
end

-- the Alliance / Horde crest for a texture (the friends list's round faction icons); hides it for
-- anything else. faction = "Alliance" | "Horde" (UnitFactionGroup)
function W.SetFactionBadge(tex, faction)
	if faction == "Alliance" or faction == "Horde" then
		tex:SetTexture("Interface\\FriendsFrame\\PlusManz-" .. faction)
		tex:SetTexCoord(0, 1, 0, 1)
		tex:Show()
		return true
	end
	tex:Hide()
	return false
end

-- The target frame's dragon round a round portrait, by creature class: gold for elites and bosses,
-- silver for rares, silver-winged for rare elites (the classic target frame sheets). The dragon is
-- cut from the 256 x 128 sheet at x 146..256, y 0..100; its portrait hole is 64 px across, centred
-- 36 px from the cut's left and 44 px from its top, so it wraps the right side of the portrait.
-- Returns true when a dragon shows. anchor = the round portrait region, diameter = its size.
local DRAGON = {
	elite = "Interface\\TargetingFrame\\UI-TargetingFrame-Elite",
	worldboss = "Interface\\TargetingFrame\\UI-TargetingFrame-Elite",
	boss = "Interface\\TargetingFrame\\UI-TargetingFrame-Elite",
	rare = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare",
	rareelite = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare-Elite",
}
W.DRAGON = DRAGON
function W.DragonFor(rec)
	if not rec then return nil end
	if rec.boss then return "boss" end
	return DRAGON[rec.class or ""] and rec.class or nil
end
function W.SetDragon(tex, kind, anchor, diameter)
	local file = kind and DRAGON[kind]
	if not file then tex:Hide() return false end
	local k = diameter / 64
	tex:SetTexture(file)
	tex:SetTexCoord(146 / 256, 1, 0, 100 / 128)
	tex:SetSize(110 * k, 100 * k)
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", anchor, "CENTER", -36 * k, 44 * k)
	tex:Show()
	return true
end

-- a skill-window bar: dark track, coloured fill, thin frame, text on top
-- The profession window's skill bar: Profession-ProgressBar-BG behind, the profession's animated
-- fill art (one frame of its flip-book sheet, cut to the filled part), a flare at the edge, the
-- Profession-ProgressBar-frame on top, and the count in Number12FontOutline. Falls back to a plain
-- status bar where the art is missing. flavor = the profession whose fill art to use.
local FLIP = {} -- [atlas] = { file, l, r, t, b (first frame) } or false
local function FlipFrame(atlas)
	if FLIP[atlas] ~= nil then return FLIP[atlas] end
	FLIP[atlas] = false
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
	if type(info) ~= "table" or not info.width or info.width == 0 then return false end
	-- the sheet is a grid of frames, each about as wide as the bar (441 x 18 on the profession
	-- window). The art recording showed Skillbar_Fill_Flipbook_* sheets are 1712 x 1020: 4 columns
	-- of 428 x 17 frames, 60 rows. Find the grid: columns that give a whole frame width nearest
	-- the bar, then the row count (dividing the height evenly) nearest the bar's shape.
	local W, H = info.width, info.height
	local cols, rows, best = 1, 1, math.huge
	for c = 1, 8 do
		if W % c == 0 then
			local fw = W / c
			local d = math.abs(fw - 441)
			if d < best then best, cols = d, c end
		end
	end
	local fw, bestR = W / cols, math.huge
	for r = 1, 128 do
		if H % r == 0 then
			local e = math.abs(fw / (H / r) - 441 / 18)
			if e < bestR then bestR, rows = e, r end
		end
	end
	if bestR > 3 then rows = 1 end
	local n = rows
	local file = info.file or info.filename
	if not file then return false end
	local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
	FLIP[atlas] = { file = file, l = l, r = l + (r - l) / cols, t = t, b = t + (b - t) / n }
	return FLIP[atlas]
end

-- the casting bar's gold fill ("Mastery"): the whole atlas, cut to the filled part
local CAST = {}
local function CastFrame(atlas)
	if CAST[atlas] ~= nil then return CAST[atlas] end
	CAST[atlas] = false
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
	local file = type(info) == "table" and (info.file or info.filename)
	if not file then return false end
	CAST[atlas] = { file = file, l = info.leftTexCoord, r = info.rightTexCoord, t = info.topTexCoord, b = info.bottomTexCoord }
	return CAST[atlas]
end

function W.Bar(parent, flavor)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(23)
	f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.label:SetPoint("LEFT", 0, 0)
	f.label:SetJustifyH("LEFT")
	local bar = CreateFrame("Frame", nil, f)
	bar:SetHeight(23)
	f.bar = bar
	bar.bg = bar:CreateTexture(nil, "ARTWORK", nil, 1)
	bar.bg:SetAllPoints()
	bar.fill = bar:CreateTexture(nil, "ARTWORK", nil, 2)
	bar.fill:SetPoint("TOPLEFT", 3, -3)
	bar.fill:SetPoint("BOTTOMLEFT", 3, 2)
	bar.flare = bar:CreateTexture(nil, "ARTWORK", nil, 3)
	bar.flare:SetSize(53, 16)
	bar.flare:SetBlendMode("ADD")
	bar.flare:SetPoint("CENTER", bar.fill, "RIGHT", 0, 0)
	-- the casting bar's flash over a full gold bar
	bar.glow = bar:CreateTexture(nil, "ARTWORK", nil, 3)
	bar.glow:SetPoint("TOPLEFT", 1, -1)
	bar.glow:SetPoint("BOTTOMRIGHT", -1, 0)
	bar.glow:SetBlendMode("ADD")
	bar.glow:SetAlpha(0.45)
	bar.glow:Hide()
	local glowArt = TryAtlas(bar.glow, "UI-CastingBar-Full-Glow-Standard", "ui-castingbar-full-glow-standard")
	bar.border = bar:CreateTexture(nil, "ARTWORK", nil, 4)
	bar.border:SetAllPoints()
	bar.text = bar:CreateFontString(nil, "OVERLAY")
	bar.text:SetFontObject(W.Font("Number12FontOutline", "GameFontHighlightSmall"))
	bar.text:SetPoint("CENTER", 0, 0)
	local native = TryAtlas(bar.bg, "Profession-ProgressBar-BG") and TryAtlas(bar.border, "Profession-ProgressBar-frame")
	if not native then
		bar.bg:SetColorTexture(0, 0, 0, 0.6)
		bar.border:SetTexture(nil)
	end
	local art, gold
	function f:SetFlavor(name)
		gold = false
		if name == "Mastery" then
			-- Mastered: the casting bar's gold fill (the First Aid green where the client lacks it)
			art = CastFrame("UI-CastingBar-Filling-Standard") or CastFrame("UI-CastingBar-Full-Standard")
			if art then
				gold = true
				bar.fill:SetTexture(art.file)
				bar.fill:SetVertexColor(1, 1, 1)
				if not TryAtlas(bar.flare, "UI-CastingBar-Pip") then bar.flare:SetTexture(nil) end
				return
			end
			name = "FirstAid"
		end
		art = FlipFrame("Skillbar_Fill_Flipbook_" .. (name or "Blacksmithing"))
		if art then
			bar.fill:SetTexture(art.file)
			bar.fill:SetVertexColor(1, 1, 1)
			if not TryAtlas(bar.flare, "Skillbar_Flare_" .. (name or "Blacksmithing")) then bar.flare:SetTexture(nil) end
		else
			bar.fill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
			bar.fill:SetVertexColor(0.85, 0.55, 0.1)
			bar.fill:SetTexCoord(0, 1, 0, 1)
			bar.flare:SetTexture(nil)
		end
	end
	f:SetFlavor(flavor)
	-- the old status-bar call (a colour) still works: it tints the fill
	function bar:SetStatusBarColor(r, g, b) bar.fill:SetVertexColor(r, g, b) end
	function f:Set(label, cur, max, text)
		self.label:SetText(label or "")
		local labelW = label and label ~= "" and math.max(self.label:GetStringWidth() + 12, 110) or 0
		bar:ClearAllPoints()
		bar:SetPoint("LEFT", labelW, 0)
		bar:SetPoint("RIGHT", 0, 0)
		max = math.max(max or 1, 1)
		local frac = math.max(0, math.min((cur or 0) / max, 1))
		local inner = math.max((bar:GetWidth() or 0) - 6, 1)
		if frac <= 0 then
			bar.fill:Hide()
			bar.flare:Hide()
		else
			bar.fill:Show()
			bar.fill:SetWidth(inner * frac)
			if art then bar.fill:SetTexCoord(art.l, art.l + (art.r - art.l) * frac, art.t, art.b) end
			bar.flare:SetShown(frac < 1 and art ~= nil)
		end
		bar.glow:SetShown(gold and glowArt and frac >= 1 or false)
		bar.text:SetText(text or ((cur or 0) .. "/" .. max))
	end
	-- the width is only known once laid out: redo the fill then
	bar:SetScript("OnSizeChanged", function() if f.last then f:Set(unpack(f.last, 1, 4)) end end)
	local set = f.Set
	function f:Set(...) self.last = { ... } return set(self, ...) end
	return f
end

-- the character sheet's skill bar: a blue fill in the skills tab's thin metal border, the count
-- in the middle. Same calls as W.Bar (Set, SetFlavor (nothing to do), .bar, .label).
function W.SkillBar(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(20)
	f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.label:SetPoint("LEFT", 0, 0)
	local bar = CreateFrame("StatusBar", nil, f)
	bar:SetPoint("LEFT", 6, 0)
	bar:SetPoint("RIGHT", -6, 0)
	bar:SetHeight(15)
	bar:SetStatusBarTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
	bar:SetStatusBarColor(0.25, 0.25, 0.75)
	bar:SetMinMaxValues(0, 1)
	f.bar = bar
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(0, 0, 0, 0.55)
	-- the border (281 x 32 round a 270 x 15 bar, 5 out on the left), its ends kept by slices
	local border = CreateFrame("Frame", nil, bar)
	border:SetFrameLevel(bar:GetFrameLevel() + 2)
	border:SetPoint("LEFT", bar, "LEFT", -5, 0)
	border:SetPoint("RIGHT", bar, "RIGHT", 6, 0)
	border:SetHeight(32)
	bar.border = border:CreateTexture(nil, "OVERLAY")
	bar.border:SetAllPoints()
	bar.border:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-BarBorder")
	if bar.border.SetTextureSliceMargins then
		pcall(bar.border.SetTextureSliceMargins, bar.border, 14, 8, 14, 8)
		if bar.border.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then pcall(bar.border.SetTextureSliceMode, bar.border, Enum.UITextureSliceMode.Stretched) end
	end
	bar.text = border:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
	function f:SetFlavor() end
	function f:Set(label, cur, max, text)
		self.label:SetText(label or "")
		max = math.max(max or 1, 1)
		bar:SetMinMaxValues(0, max)
		bar:SetValue(math.max(0, math.min(cur or 0, max)))
		bar.text:SetText(text or ((cur or 0) .. " / " .. max))
	end
	return f
end

-- a reward-style slot: icon in a quick-slot frame, name plate beside it
local function Slot(parent)
	local f = CreateFrame("Button", nil, parent)
	f:SetHeight(40)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(36, 36)
	f.icon:SetPoint("LEFT", 2, 0)
	f.border = f:CreateTexture(nil, "OVERLAY")
	f.border:SetSize(52, 52)
	f.border:SetPoint("CENTER", f.icon, "CENTER")
	f.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
	-- "fade": a dark band fading to the right with a thin gold rule along its foot (dark panes)
	f.plate = f:CreateTexture(nil, "BACKGROUND")
	f.plate:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 0, 0)
	f.plate:SetPoint("BOTTOMRIGHT", -2, 2)
	f.plate:SetColorTexture(1, 1, 1, 1)
	Fade(f.plate, "HORIZONTAL", 0.05, 0.03, 0.01, 0.55, 0.05)
	f.rule = f:CreateTexture(nil, "BORDER")
	f.rule:SetPoint("TOPLEFT", f.plate, "BOTTOMLEFT", 0, 1)
	f.rule:SetPoint("RIGHT", f.plate, "RIGHT", 0, 0)
	f.rule:SetHeight(1)
	Fade(f.rule, "HORIZONTAL", 0.85, 0.65, 0.1, 0.6, 0)
	-- "box": the quest log's reward name box, a dark box with a thin bronze edge
	f.box = f:CreateTexture(nil, "BACKGROUND")
	f.box:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 4, 0)
	f.box:SetPoint("BOTTOMRIGHT", f.icon, "BOTTOMRIGHT", 0, 0)
	f.box:SetPoint("RIGHT", f, "RIGHT", -4, 0)
	f.box:SetColorTexture(0.06, 0.045, 0.03, 0.95)
	f.edges = {}
	for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local t = f:CreateTexture(nil, "BORDER")
		t:SetColorTexture(0.4, 0.32, 0.2, 1)
		t:SetPoint(e[1], f.box, e[1])
		t:SetPoint(e[2], f.box, e[2])
		if e[3] then t:SetHeight(1) else t:SetWidth(1) end
		f.edges[#f.edges + 1] = t
	end
	-- the quest log's own reward item (MapQuestInfoRewardsFrame): a 30 px icon with a quality
	-- border, the QuestItemBorder name frame beside it, the count on the icon
	f.nameFrame = f:CreateTexture(nil, "BACKGROUND")
	f.nameFrame:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 2, 0)
	f.nameFrame:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 2, 0)
	f.nameFrame:SetPoint("RIGHT", f, "RIGHT", -4, 0)
	f.nativeBox = TryAtlas(f.nameFrame, "QuestItemBorder")
	f.iconBorder = f:CreateTexture(nil, "OVERLAY", nil, 1)
	f.iconBorder:SetAllPoints(f.icon)
	f.iconBorder:SetTexture(651080) -- Interface\Common\WhiteIconFrame, tinted by quality
	f.count = f:CreateFontString(nil, "OVERLAY", nil, 2)
	f.count:SetFontObject(W.Font("NumberFontNormalSmall", "NumberFontNormal", "GameFontHighlightSmall"))
	f.count:SetPoint("BOTTOMRIGHT", f.icon, "BOTTOMRIGHT", -1, 1)
	-- "fade" (dark panes) now draws as My Characters' items: the bag's empty-slot art behind a square
	-- icon, the quality edge round it, name and note beside it
	f.slotBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	f.slotBg:SetPoint("TOPLEFT", f.icon, "TOPLEFT", -1, 1)
	f.slotBg:SetPoint("BOTTOMRIGHT", f.icon, "BOTTOMRIGHT", 1, -1)
	f.slotBg:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
	-- dark panes: the loot window's item card behind the name (Looting_ItemCard_BG, its stroke, a
	-- quality-coloured rarity stripe along the foot, a brighter stroke on hover)
	f.card = f:CreateTexture(nil, "BACKGROUND", nil, 2)
	f.card:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 3, 1)
	f.card:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 3, -1)
	f.card:SetPoint("RIGHT", f, "RIGHT", -2, 0)
	f.nativeCard = TryAtlas(f.card, "Looting_ItemCard_BG")
	f.cardStroke = f:CreateTexture(nil, "BORDER", nil, 1)
	f.cardStroke:SetAllPoints(f.card)
	TryAtlas(f.cardStroke, "Looting_ItemCard_Stroke_Normal")
	f.cardHover = f:CreateTexture(nil, "BORDER", nil, 2)
	f.cardHover:SetAllPoints(f.card)
	f.cardHover:SetBlendMode("ADD")
	if not TryAtlas(f.cardHover, "Looting_ItemCard_Stroke_ClickState") then f.cardHover:SetColorTexture(1, 0.85, 0.4, 0.08) end
	f.cardHover:Hide()
	f.stripe = f:CreateTexture(nil, "BORDER", nil, 3)
	f.stripe:SetPoint("BOTTOMLEFT", f.card, "BOTTOMLEFT", 6, 2)
	f.stripe:SetPoint("BOTTOMRIGHT", f.card, "BOTTOMRIGHT", -6, 2)
	f.stripe:SetHeight(5)
	if not TryAtlas(f.stripe, "Looting_RarityTag_Frame") then f.stripe:SetColorTexture(1, 1, 1, 0.5) end
	f.stripe:Hide()
	function f:SetLook(look)
		local box = look == "box"
		self.plate:SetShown(false)
		self.rule:SetShown(false)
		self.border:SetShown(false)
		self.slotBg:SetShown(not box)
		self.nameFrame:SetShown(box and self.nativeBox)
		self.box:SetShown(box and not self.nativeBox)
		for _, t in ipairs(self.edges) do t:SetShown(box and not self.nativeBox) end
		local card = not box and self.nativeCard
		self.card:SetShown(card and true or false)
		self.cardStroke:SetShown(card and true or false)
		if not card then self.cardHover:Hide() self.stripe:Hide() end
		self.useCard = card
		self.icon:SetSize(box and 30 or 36, box and 30 or 36)
		self:SetHeight(box and 32 or 40)
		self.look = look
	end
	f.name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.name:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, -4)
	f.name:SetPoint("RIGHT", -6, 0)
	f.name:SetJustifyH("LEFT")
	f.name:SetWordWrap(false)
	f.note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.note:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -3)
	f.note:SetPoint("RIGHT", -6, 0)
	f.note:SetJustifyH("LEFT")
	f.note:SetWordWrap(false)
	f:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	local hl = f:GetHighlightTexture()
	if hl then hl:ClearAllPoints() hl:SetAllPoints(f.icon) end
	f:SetScript("OnEnter", function(self)
		local e = self.entry
		if not e then return end
		if self.useCard then self.cardHover:Show() end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if e.item then pcall(GameTooltip.SetItemByID, GameTooltip, e.item)
		elseif e.spell then pcall(GameTooltip.SetSpellByID, GameTooltip, e.spell)
		else
			GameTooltip:AddLine(e.name or "")
			if e.tip then GameTooltip:AddLine(e.tip, 1, 1, 1, true) end
		end
		if e.extra then GameTooltip:AddLine(e.extra, 0.6, 0.8, 1, true) end
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function(self) self.cardHover:Hide() GameTooltip_Hide() end)
	f:SetScript("OnClick", function(self)
		local e = self.entry
		-- Ctrl-click: dressing room, Shift-click: chat link; before the slot's own click
		if e and e.item and W.ItemModifiedClick(e.item) then return end
		if e and e.onClick then return e.onClick(e) end
	end)
	W.ItemCursor(f, function(self) return self.entry and self.entry.item end)
	return f
end

-- fill a slot from an entry: name, icon and colour from the game for items and spells
W.waitingItems = false
local function FillSlot(f, e)
	f.entry = e
	local name, icon, color = e.name, e.icon, nil
	if e.item then
		local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
		local ok, n, _, q, _, _, _, _, _, _, tex = pcall(getInfo, e.item)
		if ok and n then
			name, icon = name or n, icon or tex
			local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
			color = c and c.hex
		else
			W.waitingItems = true
			local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
			icon = icon or (instant and select(5, instant(e.item)))
			name = name or (L["item %d"]):format(e.item)
		end
	elseif e.spell then
		if e.spell == 6603 then
			name, icon = name or L["Melee"], icon or 132147
		elseif C_Spell and C_Spell.GetSpellInfo then
			local ok, info = pcall(C_Spell.GetSpellInfo, e.spell)
			if ok and type(info) == "table" then name, icon = name or info.name, icon or info.iconID end
		elseif GetSpellInfo then
			local n, _, tex = GetSpellInfo(e.spell)
			name, icon = name or n, icon or tex
		end
		name = name or ("spell " .. e.spell)
	end
	f.icon:SetTexture(icon or W.FindIcon({ "INV_Misc_QuestionMark" }))
	local boxed = f.look == "box"
	local q = e.item and select(4, pcall((C_Item and C_Item.GetItemInfo) or GetItemInfo, e.item))
	q = type(q) == "number" and q or nil
	local qc = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
	if e.item and qc and q >= 2 then
		f.iconBorder:SetVertexColor(qc.r, qc.g, qc.b)
		f.iconBorder:Show()
	else
		f.iconBorder:Hide()
	end
	-- the card's rarity stripe in the item's quality colour (uncommon and up)
	if f.useCard and e.item and qc and q >= 2 and not e.grey then
		f.stripe:SetVertexColor(qc.r, qc.g, qc.b, 0.9)
		f.stripe:Show()
	else
		f.stripe:Hide()
	end
	if f.useCard then f.card:SetDesaturated(e.grey and true or false) f.card:SetAlpha(e.grey and 0.6 or 1) end
	f.count:SetText(e.count and e.count > 1 and tostring(e.count) or "")
	f.name:SetFontObject(e.number and W.Font("NumberFontNormal", "GameFontHighlight") or GameFontHighlightSmall)
	if f.icon.SetDesaturated then f.icon:SetDesaturated(e.grey and true or false) end
	f.name:SetText((e.color or color or "|cffffffff") .. (name or "?") .. "|r")
	f.note:SetText(e.note or "")
	-- a name alone sits in the middle of its plate, as on the quest log's rewards
	f.name:ClearAllPoints()
	local inset = boxed and 8 or 10
	if e.note and e.note ~= "" then
		f.name:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", inset, boxed and -2 or -4)
	else
		f.name:SetPoint("LEFT", f.icon, "RIGHT", inset, 0)
	end
	f.name:SetPoint("RIGHT", -8, 0)
end

-- the quest log's reward-band heading: light serif text between two gold rules fading outward
local function Ornate(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(30)
	f.text = f:CreateFontString(nil, "OVERLAY")
	f.text:SetFontObject(W.Font("QuestFont_Huge", "QuestTitleFont", "GameFontNormalLarge"))
	f.text:SetTextColor(0.9, 0.79, 0.67)
	f.text:SetPoint("CENTER", 0, 0)
	for _, side in ipairs({ "LEFT", "RIGHT" }) do
		local line = f:CreateTexture(nil, "ARTWORK")
		line:SetHeight(1)
		line:SetColorTexture(1, 1, 1, 1)
		if side == "LEFT" then
			line:SetPoint("LEFT", f, "LEFT", 16, 0)
			line:SetPoint("RIGHT", f.text, "LEFT", -10, 0)
			Fade(line, "HORIZONTAL", 0.9, 0.79, 0.67, 0, 0.7)
		else
			line:SetPoint("LEFT", f.text, "RIGHT", 10, 0)
			line:SetPoint("RIGHT", f, "RIGHT", -16, 0)
			Fade(line, "HORIZONTAL", 0.9, 0.79, 0.67, 0.7, 0)
		end
		local dot = f:CreateTexture(nil, "ARTWORK")
		dot:SetSize(5, 5)
		dot:SetColorTexture(0.85, 0.7, 0.35, 0.9)
		dot:SetPoint("CENTER", line, side == "LEFT" and "RIGHT" or "LEFT", 0, 0)
		if dot.SetRotation then pcall(dot.SetRotation, dot, math.pi / 4) end
	end
	return f
end

function W.Detail(parent, top, style)
	style = style or "dark"
	local holder = CreateFrame("Frame", nil, parent)
	local pad = 12
	local cardGap, artLevel = 0, 0
	if style == "parchment" then
		W.Parchment(holder)
	elseif top then
		-- the header card (name, portrait, facts) and the body below it, each its own inset
		local card = W.Inset(holder)
		card:SetPoint("TOPLEFT")
		card:SetPoint("TOPRIGHT")
		card:SetHeight(top + 2 * pad)
		card:SetFrameLevel(holder:GetFrameLevel())
		local body = W.Inset(holder)
		body:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -8)
		body:SetPoint("BOTTOMRIGHT")
		body:SetFrameLevel(holder:GetFrameLevel())
		holder.card, holder.body = card, body
		cardGap = 14 + pad
		-- the profession book's paintings: the wide card behind the header, the tall one in the body
		local function Above(panel) return (type(panel.inset) == "table" and panel.inset.GetFrameLevel and panel.inset:GetFrameLevel() or panel:GetFrameLevel()) + 1 end
		holder.cardArt = W.Art(card, Above(card))
		holder.bodyArt = W.Art(body, Above(body))
		artLevel = math.max(holder.cardArt:GetFrameLevel(), holder.bodyArt:GetFrameLevel())
	else
		local inset = W.Inset(holder)
		inset:SetAllPoints(holder)
		inset:SetFrameLevel(holder:GetFrameLevel())
		-- "painted": the dark look over one of the game's paintings (holder:SetPainting)
		if style == "painted" then
			local lvl = (type(inset.inset) == "table" and inset.inset.GetFrameLevel and inset.inset:GetFrameLevel() or inset:GetFrameLevel()) + 1
			holder.paintArt = W.Art(inset, lvl)
			holder.paintShade = holder.paintArt:CreateTexture(nil, "BORDER")
			holder.paintShade:SetAllPoints()
			holder.paintShade:SetColorTexture(1, 1, 1, 1)
			Fade(holder.paintShade, "VERTICAL", 0.02, 0.015, 0.01, 0.15, 0.4)
			artLevel = holder.paintArt:GetFrameLevel()
			style = "dark"
		end
	end
	if top then
		holder.top = CreateFrame("Frame", nil, holder)
		holder.top:SetPoint("TOPLEFT", pad, -pad)
		holder.top:SetPoint("TOPRIGHT", -pad, -pad)
		holder.top:SetHeight(top)
	end
	local scroll = Try("ScrollFrame", nil, holder, "UIPanelScrollFrameTemplate")
	W.SkinScroll(scroll)
	local over = math.max(holder:GetFrameLevel() + 3, artLevel + 1)
	scroll:SetFrameLevel(over)
	if top then holder.top:SetFrameLevel(over) end
	-- parchment: the scroll area covers the whole page (its bar sits just outside, as the quest
	-- log's does), so the reward band can run from edge to edge and down to the bottom; the text
	-- keeps its margin inside an inner frame
	local paperPage = style == "parchment"
	local inner = paperPage and pad or 0
	if paperPage then
		scroll:SetPoint("TOPLEFT", 0, 0)
		scroll:SetPoint("BOTTOMRIGHT", 0, 0)
	else
		scroll:SetPoint("TOPLEFT", pad, -pad - (top and top + 6 + cardGap or 0))
		scroll:SetPoint("BOTTOMRIGHT", -30, pad)
	end
	local root = CreateFrame("Frame", nil, scroll)
	root:SetSize(1, 1)
	scroll:SetScrollChild(root)
	holder.scroll = scroll   -- pages that move the body (Characters) re-anchor it
	local child = root
	if paperPage then
		child = CreateFrame("Frame", nil, root)
		child:SetPoint("TOPLEFT", inner, -inner)
		child:SetSize(1, 1)
	end
	local pools = { text = {}, banner = {}, ornate = {}, stat = {}, bar = {}, skillbar = {}, slot = {} }
	local used = {}

	-- the dark reward band of the quest log, drawn behind every block after { "band" }
	-- (the quest log's own art: QuestLog-reward-tile-vertical, -reward-header-top, -reward-bottom)
	local band = root:CreateTexture(nil, "BACKGROUND", nil, -5)
	local nativeBand = TryAtlas(band, "QuestLog-reward-tile-vertical")
	if not nativeBand then
		band:SetColorTexture(1, 1, 1, 1)
		Fade(band, "VERTICAL", 0.11, 0.075, 0.045, 0.97, 0.97)
	end
	local bandHead = root:CreateTexture(nil, "BORDER", nil, 1)
	local nativeHead = TryAtlas(bandHead, "QuestLog-reward-header-top")
	local bandFoot = root:CreateTexture(nil, "BORDER", nil, 1)
	local nativeFoot = TryAtlas(bandFoot, "QuestLog-reward-bottom")
	-- { "dark" } on a parchment page: the Almanac's dark panel (the recipe list's background)
	-- from there down to the reward band, edge to edge, with a bronze rule on top
	local darkBg = root:CreateTexture(nil, "BACKGROUND", nil, -6)
	if not TryAtlas(darkBg, unpack(W.LIST_BG)) then darkBg:SetColorTexture(0.06, 0.05, 0.04, 0.97) end
	local darkEdge = root:CreateTexture(nil, "BORDER")
	darkEdge:SetHeight(2)
	darkEdge:SetColorTexture(0.55, 0.42, 0.2, 0.9)
	local bandEdge = root:CreateTexture(nil, "BORDER")
	bandEdge:SetHeight(2)
	bandEdge:SetColorTexture(0.55, 0.42, 0.2, 0.9)
	local HEAD_H, FOOT_H = 55, 87
	local headLabel = child:CreateFontString(nil, "OVERLAY")
	headLabel:SetFontObject(W.Font("QuestFont_Huge", "QuestTitleFont", "GameFontNormalLarge"))
	headLabel:SetTextColor(0.9, 0.79, 0.67)
	for _, t in ipairs({ band, bandHead, bandFoot, bandEdge, headLabel, darkBg, darkEdge }) do t:Hide() end

	local function Take(kind, make)
		used[kind] = (used[kind] or 0) + 1
		local f = pools[kind][used[kind]]
		if not f then
			f = make()
			pools[kind][used[kind]] = f
		end
		f:Show()
		return f
	end

	local parchmentFonts = { title = W.FONT_TITLE, head = W.FONT_TITLE, body = W.FONT_BODY, small = W.FONT_SMALL }
	local darkFonts = {
		title = function() return W.Font("GameFontNormalHuge", "GameFontNormalLarge") end,
		head = function() return W.Font("GameFontNormalLarge", "GameFontNormal") end,
		body = function() return W.Font("GameFontHighlight") end,
		small = function() return W.Font("GameFontDisableSmall", "GameFontHighlightSmall") end,
	}
	local fonts = style == "parchment" and parchmentFonts or darkFonts

	-- a font object with its own colour (SetTextColor from an earlier use would otherwise stick)
	local function UseFont(fs, obj)
		fs:SetFontObject(obj)
		if obj and obj.GetTextColor then
			local ok, r, g, b = pcall(obj.GetTextColor, obj)
			if ok and r then fs:SetTextColor(r, g, b) end
		end
	end

	local empty = holder:CreateFontString(nil, "OVERLAY")
	UseFont(empty, fonts.body())
	empty:SetPoint("CENTER")
	empty:SetWidth(260)

	local lastPlaced = {}
	-- keepScroll: stay where the reader was (a refresh of the same page)
	function holder:SetBlocks(blocks, emptyText, keepScroll)
		-- the window's background refresh (new discoveries coming in) never moves the reader
		if ns.UI and ns.UI.refreshing then keepScroll = true end
		local oldScroll = keepScroll and scroll:GetVerticalScroll() or 0
		local width = math.max((scroll:GetWidth() or 300) - 4 - 2 * inner, 100)
		child:SetWidth(width)
		root:SetWidth(width + 2 * inner)
		for k in pairs(used) do used[k] = 0 end
		W.waitingItems = false
		local y, any = 0, false
		local mode = style -- "parchment" | "dark" | "band"
		local firstHead = false
		local stripe = 0
		headLabel:Hide()
		local placed = {}
		local bandTop, darkTop
		for _, block in ipairs(blocks or {}) do
			local kind = block[1]
			local paper = mode == "parchment"
			local f = paper and parchmentFonts or darkFonts
			any = any or (kind ~= "gap" and kind ~= "band")
			if kind == "gap" then
				y = y + (block[2] or 8)
			elseif kind == "frame" then
				-- a frame of the page's own (a map): { "frame", frame, function(width) return height end }
				local fr = block[2]
				fr:SetParent(child)
				fr:ClearAllPoints()
				fr:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
				local h = type(block[3]) == "function" and block[3](width) or block[3] or fr:GetHeight() or 0
				placed[fr] = true
				if h > 0 then
					fr:Show()
					y = y + h + 10
				else
					fr:Hide()
				end
			elseif kind == "dark" then
				if style == "parchment" and not darkTop and not bandTop then
					y = y + 10
					darkTop = y
					y = y + 12
					mode = "dark"
					stripe = 0
				end
			elseif kind == "band" then
				if style == "parchment" and not bandTop then
					y = y + 10
					bandTop = y
					y = y + (nativeHead and 6 or 8)
					mode = "band"
					firstHead = nativeHead
				end
			elseif kind == "banner" then
				if mode == "parchment" then
					local t = Take("text", function() return child:CreateFontString(nil, "OVERLAY") end)
					UseFont(t, f.head())
					t:SetJustifyH("LEFT")
					t:SetWidth(width)
					t:ClearAllPoints()
					t:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y - 4)
					t:SetText(block[2] or "")
					y = y + t:GetStringHeight() + 10
				elseif mode == "band" and firstHead then
					-- the first heading sits in the band's own ornamented top, like "Rewards"
					firstHead = false
					headLabel:ClearAllPoints()
					headLabel:SetPoint("CENTER", child, "TOPLEFT", width / 2, -(bandTop + HEAD_H * 0.55))
					headLabel:SetText(block[2] or "")
					headLabel:Show()
					y = bandTop + HEAD_H + 2
				elseif mode == "band" then
					local o = Take("ornate", function() return Ornate(child) end)
					o:ClearAllPoints()
					o:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
					o:SetPoint("RIGHT", child, "RIGHT", 0, 0)
					o.text:SetText(block[2] or "")
					y = y + 30 + 6
				else
					local bn = Take("banner", function() return Banner(child) end)
					if y > 0 then y = y + 8 end
					bn:ClearAllPoints()
					bn:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
					bn:SetPoint("RIGHT", child, "RIGHT", -2, 0)
					bn:Set(block[2], block[3], block[4])
					y = y + 24 + 8
					stripe = 0
				end
			elseif kind == "stat" then
				local r = Take("stat", function()
					local r = CreateFrame("Frame", nil, child)
					r:SetHeight(23)
					r.stripe = r:CreateTexture(nil, "BACKGROUND")
					r.stripe:SetAllPoints()
					r.hasStripe = TryAtlas(r.stripe, "UI-Character-Info-Line-Bounce2")
					r.label = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
					r.label:SetPoint("TOPLEFT", 26, -5)
					r.label:SetJustifyH("LEFT")
					r.value = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
					r.value:SetPoint("TOPRIGHT", -8, -5)
					r.value:SetJustifyH("RIGHT")
					return r
				end)
				if paper then
					-- the quest log's ink: dark brown label, the quest font for the value
					UseFont(r.label, f.body())
					r.label:SetTextColor(0.42, 0.24, 0.02)
					UseFont(r.value, f.body())
				else
					UseFont(r.label, GameFontNormal)
					UseFont(r.value, GameFontHighlight)
				end
				r:ClearAllPoints()
				r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
				r:SetPoint("RIGHT", child, "RIGHT", 0, 0)
				r.label:SetText(block[2] or "")
				r.value:SetWidth(width - math.min(r.label:GetStringWidth(), width * 0.45) - 30)
				r.value:SetText(block[3] or "")
				local h = math.max(r.value:GetStringHeight(), 13) + 10
				r:SetHeight(h)
				stripe = stripe + 1
				r.stripe:SetShown(false)
				y = y + h
			elseif kind == "bar" then
				local b = Take("bar", function() return W.Bar(child) end)
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", child, "TOPLEFT", 8, -y)
				b:SetPoint("RIGHT", child, "RIGHT", -8, 0)
				b:SetFlavor(block[6])
				b:Set(block[2], block[3], block[4], block[5])
				y = y + 28
			elseif kind == "skillbar" then
				-- the character sheet's blue skill bar (as on a creature's page)
				local b = Take("skillbar", function() return W.SkillBar(child) end)
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", child, "TOPLEFT", 8, -y - 6)
				b:SetPoint("RIGHT", child, "RIGHT", -8, 0)
				b:Set(block[2], block[3], block[4], block[5])
				y = y + 34
			elseif kind == "slots" then
				local list = block[2] or {}
				-- quest pages use the quest log's reward boxes everywhere (its size: about 170 wide,
				-- 34 a row); other dark pages keep their wider item cards
				local box = style == "parchment" or mode ~= "dark"
				local colW = math.floor((width - 8) / 2)
				if box and style == "parchment" then colW = math.min(colW, 170) end
				local rowH = box and (style == "parchment" and 34 or 36) or 44
				for n, e in ipairs(list) do
					local s = Take("slot", function() return Slot(child) end)
					local col, row = (n - 1) % 2, math.floor((n - 1) / 2)
					s:ClearAllPoints()
					s:SetPoint("TOPLEFT", child, "TOPLEFT", 4 + col * (colW + 4), -y - row * rowH)
					s:SetWidth(colW)
					s:SetLook(box and "box" or "fade")
					FillSlot(s, e)
				end
				y = y + math.ceil(#list / 2) * rowH + 4
			else
				local t = Take("text", function() return child:CreateFontString(nil, "OVERLAY") end)
				if mode == "band" then
					UseFont(t, kind == "small" and W.Font("GameFontDisableSmall", "GameFontHighlightSmall") or kind == "title" and W.FONT_TITLE() or W.Font("QuestMapRewardsFont", "GameFontHighlightSmall"))
					if kind ~= "small" and kind ~= "title" then t:SetTextColor(0.9, 0.79, 0.67) end
				else
					UseFont(t, (f[kind] or f.body)())
				end
				t:SetJustifyH(block.center and "CENTER" or "LEFT")
				t:SetJustifyV("TOP")
				t:SetWidth(width - (kind == "title" and 0 or 8))
				t:ClearAllPoints()
				t:SetPoint("TOPLEFT", child, "TOPLEFT", kind == "title" and 0 or (mode == "band" and 8 or 2), -y)
				t:SetText(block[2] or "")
				y = y + t:GetStringHeight() + (kind == "title" and 8 or 4)
			end
		end
		for kind, pool in pairs(pools) do
			for i = (used[kind] or 0) + 1, #pool do pool[i]:Hide() end
		end
		for fr in pairs(lastPlaced) do if not placed[fr] then fr:Hide() end end
		lastPlaced = placed
		if darkTop then
			local top0 = darkTop + inner
			local bottom = bandTop and (bandTop + inner) or math.max(y + 12 + 2 * inner, (scroll:GetHeight() or 0))
			darkBg:ClearAllPoints()
			darkBg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -top0)
			darkBg:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -top0)
			darkBg:SetHeight(math.max(1, bottom - top0))
			darkBg:Show()
			darkEdge:ClearAllPoints()
			darkEdge:SetPoint("BOTTOMLEFT", darkBg, "TOPLEFT")
			darkEdge:SetPoint("BOTTOMRIGHT", darkBg, "TOPRIGHT")
			darkEdge:Show()
			if not bandTop then y = y + 12 end
		else
			darkBg:Hide()
			darkEdge:Hide()
		end
		if bandTop then
			y = y + 12
			-- the band runs edge to edge and to the bottom of the page even when the page is short
			local top0 = bandTop + inner
			local h = math.max(y + 2 * inner, (scroll:GetHeight() or 0))
			local bandH = h - top0
			band:ClearAllPoints()
			band:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -top0)
			band:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -top0)
			band:SetHeight(bandH)
			band:Show()
			if nativeHead then
				bandHead:ClearAllPoints()
				bandHead:SetPoint("TOPLEFT", band, "TOPLEFT")
				bandHead:SetPoint("TOPRIGHT", band, "TOPRIGHT")
				bandHead:SetHeight(HEAD_H)
				bandHead:Show()
				bandEdge:Hide()
			else
				bandEdge:ClearAllPoints()
				bandEdge:SetPoint("BOTTOMLEFT", band, "TOPLEFT", 0, 0)
				bandEdge:SetPoint("BOTTOMRIGHT", band, "TOPRIGHT", 0, 0)
				bandEdge:Show()
			end
			-- the ornamented foot closes the band (shorter on a short band)
			if nativeFoot and bandH > HEAD_H + 30 then
				bandFoot:ClearAllPoints()
				bandFoot:SetPoint("BOTTOMLEFT", band, "BOTTOMLEFT")
				bandFoot:SetPoint("BOTTOMRIGHT", band, "BOTTOMRIGHT")
				bandFoot:SetHeight(math.min(FOOT_H, bandH - HEAD_H))
				bandFoot:Show()
			else
				bandFoot:Hide()
			end
		else
			band:Hide()
			bandHead:Hide()
			bandFoot:Hide()
			bandEdge:Hide()
		end
		child:SetHeight(math.max(y, 1))
		local total = y + 2 * inner
		root:SetHeight(math.max(total, 1))
		scroll:SetVerticalScroll(math.min(oldScroll, math.max(total - (scroll:GetHeight() or 0), 0)))
		W.FitScrollBar(scroll, total)
		empty:SetText(emptyText or "")
		empty:SetShown(not any and emptyText ~= nil)
	end

	-- theme: a profession (or a list to try in order) whose paintings the panels show
	-- the painting behind a "painted" pane: the first of the atlases the client has, filling it
	function holder:SetPainting(candidates, alpha)
		if self.paintArt then self.paintArt:Set(candidates, "cover", alpha or 1, true) end
	end

	function holder:SetTheme(theme)
		if not self.cardArt then return end
		if self.theme == theme then return end
		self.theme = theme
		if not theme then self.cardArt:Set(nil) self.bodyArt:Set(nil) return end
		local wide, tall = W.ThemeAtlases(theme)
		self.cardArt:Set(wide, "cover", 0.9)
		self.bodyArt:Set(tall, "corner", 0.28)
	end

	function holder:Fonts() return fonts end
	return holder
end

---------------------------------------------------------------------------
-- A small pop-up menu drawn by the addon (anchor, { { text, icon, run }, ... })
---------------------------------------------------------------------------

local menu, catcher
function W.CloseMenu()
	if menu then menu:Hide() end
	if catcher then catcher:Hide() end
end
function W.Menu(anchor, items)
	if not menu then
		catcher = CreateFrame("Button", nil, UIParent)
		catcher:SetAllPoints(UIParent)
		catcher:SetFrameStrata("FULLSCREEN")
		catcher:RegisterForClicks("AnyUp")
		catcher:SetScript("OnClick", function() menu:Hide() catcher:Hide() end)
		menu = Try("Frame", "AzerothAlmanacMenu", UIParent, "BackdropTemplate")
		menu:SetFrameStrata("FULLSCREEN_DIALOG")
		menu:SetClampedToScreen(true)
		menu:EnableMouse(true)
		if menu.SetBackdrop then
			menu:SetBackdrop({
				bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				tile = true, tileSize = 16, edgeSize = 14,
				insets = { left = 3, right = 3, top = 3, bottom = 3 },
			})
		end
		menu.rows = {}
	end
	for _, r in ipairs(menu.rows) do r:Hide() end
	-- long menus (every known zone ...) wrap into columns
	local perCol = 22
	local columns = math.ceil(#items / perCol)
	local colWidth, colX = {}, {}
	for i, item in ipairs(items) do
		local row = menu.rows[i]
		if not row then
			row = CreateFrame("Button", nil, menu)
			row:SetHeight(22)
			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(18, 18)
			row.icon:SetPoint("LEFT", 2, 0)
			row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			-- (round icons: masked to a circle in a coloured ring, as the tier badges)
			row.ring = row:CreateTexture(nil, "BACKGROUND")
			row.ring:SetTexture(CIRCLE)
			row.ring:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -2, 2)
			row.ring:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 2, -2)
			row.ring:Hide()
			row.mask = row:CreateMaskTexture()
			row.mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			row.mask:SetAllPoints(row.icon)
			row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
			row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			-- (a section's plate: a dark band between two gold rules, the title centred on it)
			row.plate = row:CreateTexture(nil, "BACKGROUND")
			row.plate:SetPoint("TOPLEFT", 0, -3)
			row.plate:SetPoint("BOTTOMRIGHT", 0, 3)
			row.plate:SetColorTexture(0, 0, 0, 0.55)
			row.ruleTop = row:CreateTexture(nil, "ARTWORK")
			row.ruleTop:SetPoint("TOPLEFT", row.plate, "TOPLEFT")
			row.ruleTop:SetPoint("TOPRIGHT", row.plate, "TOPRIGHT")
			row.ruleTop:SetHeight(1)
			row.ruleTop:SetColorTexture(1, 0.82, 0, 0.55)
			row.ruleBottom = row:CreateTexture(nil, "ARTWORK")
			row.ruleBottom:SetPoint("BOTTOMLEFT", row.plate, "BOTTOMLEFT")
			row.ruleBottom:SetPoint("BOTTOMRIGHT", row.plate, "BOTTOMRIGHT")
			row.ruleBottom:SetHeight(1)
			row.ruleBottom:SetColorTexture(1, 0.82, 0, 0.55)
			menu.rows[i] = row
		end
		-- item.section = true: a divider with the section's name on a plate (not clickable);
		-- item.divider = true: just a thin gold rule, ending a section
		local section = item.section and true or false
		row:SetHeight(item.divider and 9 or 22)
		row.plate:SetShown(section)
		row.ruleTop:SetShown(section or item.divider or false)
		row.ruleBottom:SetShown(section)
		row.ruleTop:ClearAllPoints()
		if item.divider then
			row.ruleTop:SetPoint("LEFT", row, "LEFT", 4, 0)
			row.ruleTop:SetPoint("RIGHT", row, "RIGHT", -4, 0)
		else
			row.ruleTop:SetPoint("TOPLEFT", row.plate, "TOPLEFT")
			row.ruleTop:SetPoint("TOPRIGHT", row.plate, "TOPRIGHT")
		end
		row.text:ClearAllPoints()
		if section then row.text:SetPoint("CENTER", 0, 0) else row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0) end
		if item.icon then W.SetIcon(row.icon, item.icon) end
		-- (item.portraitUnit: that unit's own portrait, e.g. you for Characters)
		if item.portraitUnit and SetPortraitTexture then pcall(SetPortraitTexture, row.icon, item.portraitUnit) end
		row.icon:SetShown(item.icon ~= nil)
		-- item.ring = { r, g, b }: the icon round in a ring of that colour
		local round = item.icon ~= nil and item.ring ~= nil
		if round and not row.masked then row.icon:AddMaskTexture(row.mask) row.masked = true
		elseif not round and row.masked then row.icon:RemoveMaskTexture(row.mask) row.masked = false end
		row.ring:SetShown(round)
		if round then row.ring:SetVertexColor(item.ring[1], item.ring[2], item.ring[3]) end
		row.text:SetFontObject((item.title or section) and GameFontNormal or GameFontHighlight)
		row.text:SetText(item.text)
		if item.selected then row.text:SetTextColor(1, 0.82, 0) elseif not (item.title or section) then row.text:SetTextColor(1, 1, 1) end
		row:SetScript("OnClick", item.run and function()
			menu:Hide()
			catcher:Hide()
			item.run()
		end or nil)
		row:EnableMouse(item.run ~= nil)
		row:Show()
		local col = math.floor((i - 1) / perCol) + 1
		local w = row.text:GetStringWidth()
		w = (type(w) == "number" and w or 0) + (item.icon and 56 or 30)
		colWidth[col] = math.max(colWidth[col] or 140, w)
	end
	local x = 8
	for col = 1, columns do colX[col] = x x = x + colWidth[col] + 4 end
	local tallest, y, lastCol = 0, 8, 1
	for i, item in ipairs(items) do
		local row = menu.rows[i]
		local col = math.floor((i - 1) / perCol) + 1
		if col ~= lastCol then y, lastCol = 8, col end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", colX[col], -y)
		row:SetWidth(colWidth[col])
		y = y + (item.divider and 9 or 22)
		tallest = math.max(tallest, y)
	end
	menu:SetSize(x + 4, tallest + 8)
	menu:ClearAllPoints()
	menu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 4, -2)
	catcher:Show()
	menu:Show()
end

---------------------------------------------------------------------------
-- The game's own map waypoint (and its arrow) on a spot: map, x, y in percent
---------------------------------------------------------------------------

-- the user waypoint's diamond as text markup (for "set waypoint" buttons), else a skull
function W.PinMarkup(size)
	size = size or 18
	for _, atlas in ipairs({ "Waypoint-MapPin-Tracked", "Waypoint-MapPin-Untracked" }) do
		if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then return ("|A:%s:%d:%d|a"):format(atlas, size, size) end
	end
	return "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:14:14|t"
end

function W.Waypoint(map, x, y, name)
	if not (map and x and y) then return end
	if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
		ns.Print(L["This client can't set map waypoints."])
		return
	end
	if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(map) then
		ns.Print(L["A waypoint can't be placed on that map."])
		return
	end
	-- (0.67.4) no C_SuperTrack.SetSuperTrackedUserWaypoint: it's protected on WoW Forever, so it only
	-- counted an "Interface action failed because of an AddOn" (pcall can't catch that)
	pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(map, x / 100, y / 100))
	ns.Print((L["Waypoint set on %s."]):format(name or "?"))
end
