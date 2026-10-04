-- Ported from Plus Everything (same author) for Azeroth Almanac's quality-of-life helpers.
-- Collapsible windows: a button in the title bar shrinks an Azeroth Almanac window to a small, movable
-- bar (icon, title and a one-line summary) and expands it again. Used by Dungeons and the
-- Questopedia. The collapsed state is remembered in the window's settings (db.collapsed).

local _, A = ...
local ns = A.QoL

-- The class emblem (classFile like "PALADIN"): the round class-icon art when the client has it,
-- else the classic sheet. Used by the Inventory portraits and the unit-frame badges.
function ns.SetClassIcon(texture, classFile)
	texture:SetTexCoord(0, 1, 0, 1)
	texture:SetDesaturated(false)
	local class = classFile and classFile:lower()
	if class and C_Texture and C_Texture.GetAtlasInfo then
		for _, pattern in ipairs({ "classicon-%s", "groupfinder-icon-class-%s" }) do
			local atlas = pattern:format(class)
			if C_Texture.GetAtlasInfo(atlas) then
				texture:SetAtlas(atlas)
				return true
			end
		end
	end
	local coords = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
	if coords then
		texture:SetTexture("Interface\\WorldStateFrame\\Icons-Classes")
		-- trim the sheet's square border a little so the round mask shows only the emblem
		local l, r, t, b = unpack(coords)
		local w, h = (r - l) * 0.04, (b - t) * 0.04
		texture:SetTexCoord(l + w, r - w, t + h, b - h)
		return true
	end
end

local SMALLER ="Interface\\Buttons\\UI-Panel-SmallerButton"
local BIGGER = "Interface\\Buttons\\UI-Panel-BiggerButton"

-- opts = { db = settings table, width = collapsed width, byline = the title bar's grey sub-text,
--          summary = function() return "text for the collapsed bar" end,
--          keep = { frames that stay visible when collapsed (close button, ...) },
--          anchor = the button the collapse button goes left of, onExpand = function() end }
function ns.MakeCollapsible(frame, opts)
	local db = opts.db
	local keep = { }
	for _, f in ipairs(opts.keep or {}) do keep[f] = true end
	local hidden = {}
	local fullW, fullH = frame:GetSize()
	local bylineText

	local button = CreateFrame("Button", nil, frame)
	button:SetSize(24, 24)
	button:SetPoint("RIGHT", opts.anchor, "LEFT", -2, 0)
	keep[button] = true
	if frame.nativeChrome then
		keep[frame.nativeChrome] = true
		button:SetSize(20, 20)
		button:SetFrameLevel(frame:GetFrameLevel() + 52)
	end

	local function SetLook(collapsed)
		local base = collapsed and BIGGER or SMALLER
		button:SetNormalTexture(base .. "-Up")
		button:SetPushedTexture(base .. "-Down")
		button:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
	end

	-- Keep the top-left corner where it is, so the window shrinks and grows in place.
	local function PinTopLeft()
		local left, top = frame:GetLeft(), frame:GetTop()
		if type(left) ~= "number" or type(top) ~= "number" then return end -- not placed yet
		local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * scale, top * scale)
	end

	function frame:RefreshCollapsed()
		if db.collapsed and opts.byline and opts.summary then opts.byline:SetText(opts.summary() or "") end
	end

	function frame:Collapse()
		if frame.isCollapsed then return end
		frame.isCollapsed = true
		db.collapsed = true
		fullW, fullH = frame:GetSize()
		PinTopLeft()
		wipe(hidden)
		for _, child in ipairs({ frame:GetChildren() }) do
			if not keep[child] and child:IsShown() then
				hidden[#hidden + 1] = child
				child:Hide()
			end
		end
		if opts.byline then bylineText = opts.byline:GetText() end
		-- the native frame's portrait hangs below its title bar: leave room for it and the byline
		frame:SetSize(opts.width or 380, frame.nativeChrome and 62 or 42)
		SetLook(true)
		frame:RefreshCollapsed()
	end

	function frame:Expand()
		if not frame.isCollapsed then return end
		frame.isCollapsed = false
		db.collapsed = false
		PinTopLeft()
		frame:SetSize(fullW, fullH)
		for _, child in ipairs(hidden) do child:Show() end
		wipe(hidden)
		if opts.byline and bylineText then opts.byline:SetText(bylineText) end
		SetLook(false)
		if opts.onExpand then opts.onExpand() end
	end

	function frame:ToggleCollapsed()
		if frame.isCollapsed then frame:Expand() else frame:Collapse() end
	end

	button:SetScript("OnClick", function() frame:ToggleCollapsed() end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(frame.isCollapsed and "Expand" or "Collapse to a small bar")
		GameTooltip:AddLine("Double-click the title bar does the same", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)

	-- Double-click on the window (the title bar when collapsed) toggles too.
	frame:SetScript("OnMouseUp", function(_, mouse)
		if mouse ~= "LeftButton" then return end
		local now = GetTime()
		if frame.lastClick and now - frame.lastClick < 0.35 then
			frame.lastClick = nil
			local _, y = GetCursorPosition()
			y = y / frame:GetEffectiveScale()
			if frame.isCollapsed or (frame:GetTop() and frame:GetTop() - y <= 42) then frame:ToggleCollapsed() end
		else
			frame.lastClick = now
		end
	end)

	SetLook(false)
	if db.collapsed then
		db.collapsed = false
		frame:Collapse()
	end
	return button
end

---------------------------------------------------------------------------
-- Native window chrome
---------------------------------------------------------------------------

local function Hide(region)
	if type(region) == "table" and region.Hide then region:Hide() end
end

-- A template's child frame or region, when the client's template has it.
local function Part(owner, key)
	local v = owner[key]
	return type(v) == "table" and v or nil
end

-- Puts a window in the game's own portrait frame (the stone border, title bar and round
-- portrait of the character and spellbook windows). The window keeps its own content and close
-- button; its flat backdrop and hand-drawn header are hidden.
-- opts = { title = "Questopedia", icon = texture path or fileID,
--          hide = { header regions to hide }, close = the close button, buttons = { gear, ... },
--          byline = the grey sub-title font string (moved under the title bar) }
-- Returns the chrome frame, or nil on a client without the template (the old look stays).
function ns.NativeWindow(frame, opts)
	local ok, chrome = pcall(CreateFrame, "Frame", nil, frame, "PortraitFrameTemplateNoCloseButton")
	if not ok or not chrome then
		ok, chrome = pcall(CreateFrame, "Frame", nil, frame, "PortraitFrameTemplate")
		if not ok or not chrome then return nil end
		Hide(chrome.CloseButton)
	end
	if frame.ClearBackdrop then frame:ClearBackdrop() elseif frame.SetBackdrop then frame:SetBackdrop(nil) end
	for _, region in ipairs(opts.hide or {}) do Hide(region) end
	chrome:SetAllPoints(frame)
	chrome:EnableMouse(false)
	local base = frame:GetFrameLevel()
	chrome:SetFrameLevel(base)
	-- the border, portrait and title over the window's content, its buttons over those
	local over = base + 50
	for _, key in ipairs({ "NineSlice", "PortraitContainer", "TitleContainer" }) do
		local child = Part(chrome, key)
		if child then child:SetFrameLevel(over) end
	end

	if chrome.SetTitle then
		chrome:SetTitle(opts.title or "")
	else
		local text = Part(chrome, "TitleText") or (Part(chrome, "TitleContainer") and Part(chrome.TitleContainer, "TitleText"))
		if text then text:SetText(opts.title or "") end
	end
	local portrait = chrome.GetPortrait and chrome:GetPortrait()
		or Part(chrome, "portrait") or (Part(chrome, "PortraitContainer") and Part(chrome.PortraitContainer, "portrait"))
	if portrait and opts.icon then
		if SetPortraitToTexture then
			SetPortraitToTexture(portrait, opts.icon)
		else
			portrait:SetTexture(opts.icon)
		end
	end
	frame.portrait = portrait

	-- Text and art drawn straight on the window would sit under the frame's stone background:
	-- lift them onto a layer above it.
	local lift = CreateFrame("Frame", nil, frame)
	lift:SetAllPoints(frame)
	lift:SetFrameLevel(base + 1)
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:IsShown() and region:GetObjectType() ~= "MaskTexture" then region:SetParent(lift) end
	end
	frame.lift = lift

	if opts.close then
		opts.close:ClearAllPoints()
		opts.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 1, 1)
		opts.close:SetFrameLevel(over + 2)
	end
	for _, b in ipairs(opts.buttons or {}) do
		b:SetFrameLevel(over + 2)
		b:SetSize(20, 20)
	end
	if opts.byline then
		opts.byline:ClearAllPoints()
		opts.byline:SetPoint("TOPLEFT", frame, "TOPLEFT", 62, -31)
		opts.byline:SetParent(Part(chrome, "TitleContainer") or chrome)
	end
	frame.nativeChrome = chrome
	return chrome
end

-- A recessed panel inside a native window: the game's inset (dark marble with a thin bevel), as
-- around the character window's stats or the quest log's list. Falls back to the flat backdrop
-- already on the frame.
function ns.NativeInset(f)
	local ok, inset = pcall(CreateFrame, "Frame", nil, f, "InsetFrameTemplate")
	if not ok or not inset then return nil end
	if f.ClearBackdrop then f:ClearBackdrop() elseif f.SetBackdrop then f:SetBackdrop(nil) end
	inset:SetAllPoints(f)
	inset:EnableMouse(false)
	inset:SetFrameLevel(f:GetFrameLevel())
	f.inset = inset
	return inset
end
