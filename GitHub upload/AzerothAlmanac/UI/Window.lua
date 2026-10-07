-- The Almanac window: the game's portrait frame (stone border, title bar, round portrait, close
-- button) with the game's tabs along the bottom, one per page. Pages register themselves with
-- ns.UI:RegisterPage{ key, title, icon, order, Build = function(page, parent, header) end, Refresh = function(page) end }.
-- The window is built the first time it opens. Esc closes it; it remembers its place and page.

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local UI = ns.UI
local Window = ns:NewModule("Window")

local WIDTH, HEIGHT = 880, 680   -- tall enough for the Characters page's gear and professions without scrolling
local frame, pages, order, current = nil, {}, {}, nil

-- pages merged into another keep their key as an alias (Merchants lives in People now)
local aliases = {}
function UI:RegisterAlias(key, to) aliases[key] = to end
function UI:GetPage(key) return pages[aliases[key] or key] end

function UI:RegisterPage(def)
	pages[def.key] = def
	order[#order + 1] = def
	table.sort(order, function(a, b) return (a.order or 99) < (b.order or 99) end)
end

local function SavePosition()
	local p, _, rp, x, y = frame:GetPoint()
	ns.db.settings.window.point = { p, rp, x, y }
end

-- a page's icon on a texture: its icon file, or (def.portraitUnit) that unit's own portrait, as the
-- Characters page shows the character you're playing
local function ApplyIcon(texture, def, crop)
	if def and def.portraitUnit and SetPortraitTexture then
		SetPortraitTexture(texture, def.portraitUnit)
		if crop then texture:SetTexCoord(0.12, 0.88, 0.12, 0.88) else texture:SetTexCoord(0, 1, 0, 1) end
		return
	end
	texture:SetTexCoord(0, 1, 0, 1)
	texture:SetTexture(W.FindIcon(def and def.icon or ns.ICON))
end

local function SetPortrait(icon, def)
	local portrait = frame.GetPortrait and frame:GetPortrait()
	if type(portrait) ~= "table" then portrait = (type(frame.PortraitContainer) == "table" and frame.PortraitContainer.portrait) or nil end
	if type(portrait) ~= "table" then return end
	-- a plain texture under a round mask: SetPortraitToTexture spoils the icon file for every
	-- other texture that shows it (the Bestiary's side tab went black)
	if def and def.portraitUnit then ApplyIcon(portrait, def) else portrait:SetTexCoord(0, 1, 0, 1) portrait:SetTexture(icon) end
	if not portrait.almanacMask and frame.CreateMaskTexture and portrait.AddMaskTexture then
		local mask = frame:CreateMaskTexture()
		mask:SetAllPoints(portrait)
		mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		portrait:AddMaskTexture(mask)
		portrait.almanacMask = mask
	end
end

local function SetTitle(text)
	if frame.SetTitle then
		frame:SetTitle(text)
	else
		local t = (type(frame.TitleText) == "table" and frame.TitleText) or (type(frame.TitleContainer) == "table" and frame.TitleContainer.TitleText)
		if type(t) == "table" then t:SetText(text) end
	end
end

local function SelectTab(index)
	for i, tab in ipairs(frame.tabs) do
		tab:SetChecked(i == index)
		if tab.glow then tab.glow:SetShown(i == index) end
	end
end

function UI:Current() return current and current.key end

-- Back: one step, to the page you came from, showing what you were looking at there. Going back
-- uses it up (it never walks further back than the screen before).
local previous

local function UpdateBack()
	if frame and frame.back then frame.back:SetEnabled(previous ~= nil) end
end

function UI:GoBack()
	local p = previous
	if not p then return end
	previous = nil
	UI.restoring = true
	UI:ShowPage(p.key)
	UI.restoring = false
	local def = pages[p.key]
	if p.item and def and def.list and def.list.Restore then
		local ok, err = pcall(def.list.Restore, def.list, p.item)
		if not ok then ns.Debug("back: " .. tostring(err)) end
	end
	previous = nil
	UpdateBack()
end

function UI:ShowPage(key)
	ns.doing = "showing the " .. tostring(key) .. " page"
	local def = pages[aliases[key] or key] or order[1]
	if not def then return end
	-- leaving a page for another: remember where you were on it
	if current and current ~= def and not UI.restoring then
		previous = { key = current.key, item = current.list and current.list:Selected() }
	end
	for _, d in ipairs(order) do
		if d.container then d.container:Hide() end
		if d.header then d.header:Hide() end
	end
	if not def.container then
		def.container = CreateFrame("Frame", nil, frame.content)
		def.container:SetAllPoints(frame.content)
		def.header = CreateFrame("Frame", nil, frame)
		-- the header starts after the Back button
		def.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 64 + 96, -26)
		def.header:SetPoint("BOTTOMRIGHT", frame.content, "TOPRIGHT", 0, 2)
		UI.building = def
		local ok, err = pcall(def.Build, def, def.container, def.header)
		UI.building = nil
		if not ok then ns.Print("could not build the " .. def.key .. " page: " .. tostring(err)) end
	end
	def.container:Show()
	def.header:Show()
	current = def
	ns.db.settings.window.tab = def.key
	-- (character-only Almanac: whose it is, in the title)
	local me = ns.ScopeChar and ns.ScopeChar()
	SetTitle(L["Azeroth Almanac"] .. " - " .. def.title .. (me and ("  |cffbfbfbf(" .. ns.CharName(me) .. ")|r") or ""))
	SetPortrait(W.FindIcon(def.icon or ns.ICON), def)
	for i, d in ipairs(order) do if d == def then SelectTab(i) end end
	UpdateBack()
	if def.Refresh then
		local ok, err = pcall(def.Refresh, def)
		if not ok then ns.Debug("refresh " .. def.key .. ": " .. tostring(err)) end
	end
end

local function Build()
	local templated
	frame, templated = W.Try("Frame", "AzerothAlmanacFrame", UIParent, "PortraitFrameTemplate")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)
	local point = ns.db.settings.window.point
	if point then
		frame:SetPoint(point[1], UIParent, point[2], point[3], point[4])
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
	end
	frame:SetScale(ns.db.settings.window.scale or 1)
	if not templated then
		-- no portrait frame on this client: a plain dark window with a close button
		local bg = frame:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.05, 0.05, 0.05, 0.92)
		local close = W.Try("Button", nil, frame, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", 2, 2)
		frame.TitleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		frame.TitleText:SetPoint("TOP", 0, -6)
	end
	tinsert(UISpecialFrames, "AzerothAlmanacFrame")
	frame:SetScript("OnShow", function()
		if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN) end
	end)
	frame:SetScript("OnHide", function()
		if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end
		if W.CloseMenu then W.CloseMenu() end -- a dropdown left open would swallow the next click
	end)

	-- Back: the game's red panel button (it glows on hover, greys out with nowhere to go back to)
	frame.back = W.Button(frame, "|TInterface\\Buttons\\UI-SpellbookIcon-PrevPage-Up:16:16:0:0|t " .. L["Back"], 88, function()
		if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
		UI:GoBack()
	end)
	frame.back:SetPoint("LEFT", frame, "TOPLEFT", 64 + 12, -26 - 18)
	frame.back:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(L["Back"], 1, 0.82, 0)
		if previous then
			local def = pages[previous.key]
			GameTooltip:AddLine((L["To %s, where you left off."]):format(def and def.title or previous.key), 1, 1, 1)
		else
			GameTooltip:AddLine(L["Nowhere to go back to yet."], 0.7, 0.7, 0.7)
		end
		GameTooltip:Show()
	end)
	frame.back:SetScript("OnLeave", GameTooltip_Hide)
	if frame.back.SetMotionScriptsWhileDisabled then frame.back:SetMotionScriptsWhileDisabled(true) end
	frame.back:SetEnabled(false)

	-- the area pages draw in (below the title bar and portrait)
	frame.content = CreateFrame("Frame", nil, frame)
	frame.content:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -62)
	frame.content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)

	-- tabs down the right edge, like the character window's: a square icon in the spellbook's
	-- side-tab frame, the page's name on hover
	frame.tabs = {}
	for i, def in ipairs(order) do
		local tab = CreateFrame("CheckButton", "AzerothAlmanacFrameTab" .. i, frame)
		tab.frameArt = tab:CreateTexture(nil, "BACKGROUND")
		-- the profession window's side tabs (common-sidetab, -selected, -hover), when the client has them
		if W.TryAtlas(tab.frameArt, "common-sidetab") then
			tab.native = true
			tab:SetSize(55, 60)
			tab.frameArt:SetAllPoints()
		else
			tab:SetSize(36, 36)
			tab.frameArt:SetSize(64, 64)
			tab.frameArt:SetPoint("TOPLEFT", -3, 11)
		end
		if not tab.native and tab.frameArt:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab") == false then
			tab.frameArt:SetTexture("Interface\\Buttons\\UI-Quickslot2")
			tab.frameArt:ClearAllPoints()
			tab.frameArt:SetPoint("CENTER")
			tab.frameArt:SetSize(58, 58)
		end
		tab.icon = tab:CreateTexture(nil, "ARTWORK")
		if tab.native then
			tab.icon:SetSize(46, 46)
			tab.icon:SetPoint("CENTER", -2, 0)
		else
			tab.icon:SetAllPoints()
		end
		ApplyIcon(tab.icon, def, true)
		tab.def = def
		-- the selected tab's frame (or a glow); our own texture, because this client draws a checked
		-- texture opaque over the icon (the selected tab went black)
		tab.glow = tab:CreateTexture(nil, "OVERLAY")
		tab.glow:SetAllPoints()
		local hover = tab:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints()
		if tab.native and W.TryAtlas(tab.glow, "common-sidetab-selected") then
			W.TryAtlas(hover, "common-sidetab-hover")
		else
			tab.glow:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
			tab.glow:SetBlendMode("ADD")
			hover:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
			hover:SetBlendMode("ADD")
		end
		tab.glow:Hide()
		if i == 1 then
			tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", tab.native and -2 or 0, tab.native and -40 or -48)
		else
			tab:SetPoint("TOPLEFT", frame.tabs[i - 1], "BOTTOMLEFT", 0, tab.native and 4 or -14)
		end
		-- many pages: the tabs shrink a little so they all fit along the window's edge
		if tab.native then
			local room = HEIGHT - 50
			local step = 56
			if #order * step > room then tab:SetScale(room / (#order * step)) end
		end
		tab:SetScript("OnClick", function(self)
			if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
			UI:ShowPage(def.key)
		end)
		tab:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(def.title, 1, 0.82, 0)
			GameTooltip:Show()
		end)
		tab:SetScript("OnLeave", GameTooltip_Hide)
		frame.tabs[i] = tab
	end
	frame:Hide()
end

function UI:Open(key)
	if not ns.db then return end
	ns.doing = "opening the window"
	if not frame then Build() end
	frame:Show()
	self:ShowPage(key or ns.db.settings.window.tab or "journal")
end

function UI:Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		self:Open()
	end
end

function UI:IsShown() return frame and frame:IsShown() end

function UI:SetScale(scale)
	ns.db.settings.window.scale = scale
	if frame then frame:SetScale(scale) end
end

function UI:ResetPosition()
	ns.db.settings.window.point = nil
	if frame then
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
	end
end

-- item names arrive from the server a moment after they're first asked for: redraw the open page
-- (the Bestiary, Quests, Trainers and Dungeons pages do this themselves)
local OWN_ITEM_REFRESH = { bestiary = true, quests = true, trainers = true, dungeons = true }
local itemPending = false
ns:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
	if itemPending or not (W.waitingItems and frame and frame:IsShown() and current) or OWN_ITEM_REFRESH[current.key] then return end
	itemPending = true
	C_Timer.After(0.3, function()
		itemPending = false
		if frame:IsShown() and current and current.Refresh and not OWN_ITEM_REFRESH[current.key] then
			UI.refreshing = true
			pcall(current.Refresh, current)
			UI.refreshing = false
		end
	end)
end)

-- keep the open page current as discoveries come in (at most twice a second)
-- (0.64.0) only when what changed is something the page shows: PAGE_KINDS lists what each page
-- reads; a page not listed refreshes on every change, and a change of no kind refreshes any page
local PAGE_KINDS = {
	bestiary = { creature = true, zone = true, item = true },
	items = { item = true, merchant = true, quest = true, spell = true, creature = true },
	quests = { quest = true, zone = true, item = true, creature = true },
	gathering = { node = true, fishing = true, creature = true, item = true, zone = true },
	dungeons = { instance = true, creature = true, item = true },
	townsfolk = { townsfolk = true, merchant = true, trainer = true, npc = true, flight = true, mailbox = true, zone = true },
	trainers = { spell = true, trainer = true },
}
local pending, changedKinds, changedAll = false, {}, false
ns:On("CHANGED", function(kind)
	if not (frame and frame:IsShown() and current) then return end
	if kind then changedKinds[kind] = true else changedAll = true end
	if pending then return end
	pending = true
	C_Timer.After(0.5, function()
		pending = false
		local want = PAGE_KINDS[current and current.key or ""]
		local hit = changedAll or not want
		if not hit then for k in pairs(changedKinds) do if want[k] then hit = true break end end end
		wipe(changedKinds)
		changedAll = false
		if hit and frame:IsShown() and current and current.Refresh then
			UI.refreshing = true
			pcall(current.Refresh, current)
			UI.refreshing = false
		end
	end)
end)

-- pages that show a unit's portrait (Characters: the character you're playing) follow it as it changes
local function RefreshPortraits()
	if not frame then return end
	for _, tab in ipairs(frame.tabs or {}) do
		if tab.def and tab.def.portraitUnit then ApplyIcon(tab.icon, tab.def, true) end
	end
	if current and current.portraitUnit then SetPortrait(nil, current) end
end
ns:RegisterEvent("UNIT_PORTRAIT_UPDATE", function(_, unit) if unit == "player" then RefreshPortraits() end end)
ns:RegisterEvent("PLAYER_ENTERING_WORLD", function() C_Timer.After(1, RefreshPortraits) end)
