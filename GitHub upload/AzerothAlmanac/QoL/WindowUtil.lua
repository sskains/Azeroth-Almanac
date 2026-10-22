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
	-- the holiday's snow and frost, over the border it has just been given
	ns.DressForSeason(frame)
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
	-- the same recipe list background as the Almanac's dark panels (Widgets W.Inset)
	local list = inset:CreateTexture(nil, "BACKGROUND", nil, 2)
	list:SetPoint("TOPLEFT", 3, -3)
	list:SetPoint("BOTTOMRIGHT", -3, 3)
	local set = false
	for _, name in ipairs({ "Professions-background-summarylist", "auctionhouse-background-summarylist" }) do
		if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) and pcall(list.SetAtlas, list, name) then set = true break end
	end
	list:SetShown(set)
	return inset
end

---------------------------------------------------------------------------
-- Wooden look shared by Wild Gambit and Gem Match
---------------------------------------------------------------------------

-- a button in carved oak with bronze rivets (custom art) instead of the game's red one: its riveted
-- ends keep their shape, the middle stretches; lighter under the mouse, darker when pressed
-- `allow` (optional) is asked before the click sound: a game passes its own sound setting
function ns.WoodButton(b, allow)
	if not b or b.wood then return b end
	for _, key in ipairs({ "Left", "Middle", "Right", "LeftDisabled", "MiddleDisabled", "RightDisabled" }) do
		local r = b[key]
		if type(r) == "table" and r.SetAlpha then r:SetAlpha(0) end
	end
	for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
		local ok, t = pcall(b[get], b)
		if ok and type(t) == "table" and t.SetAlpha then t:SetAlpha(0) end
	end
	local t = b:CreateTexture(nil, "BACKGROUND", nil, 1)
	t:SetPoint("TOPLEFT", -4, 5)
	t:SetPoint("BOTTOMRIGHT", 4, -5)
	t:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\Button_Wood")
	if t.SetTextureSliceMargins then
		pcall(t.SetTextureSliceMargins, t, 40, 20, 40, 20)
		if t.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then pcall(t.SetTextureSliceMode, t, Enum.UITextureSliceMode.Stretched) end
	end
	b.wood = t
	-- the same soft click on every wooden button in every game
	b:HookScript("OnClick", function()
		if PlaySound and (not allow or allow()) then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) or 856) end
	end)
	b:HookScript("OnEnter", function(self) self.wood:SetVertexColor(1.2, 1.15, 1.05) end)
	b:HookScript("OnLeave", function(self) self.wood:SetVertexColor(1, 1, 1) end)
	b:HookScript("OnMouseDown", function(self) self.wood:SetVertexColor(0.75, 0.72, 0.68) end)
	b:HookScript("OnMouseUp", function(self) self.wood:SetVertexColor(self:IsMouseOver() and 1.2 or 1, self:IsMouseOver() and 1.15 or 1, self:IsMouseOver() and 1.05 or 1) end)
	return b
end

function ns.WoodLettering(b, size)
	size = size or 13
	ns.letterFonts = ns.letterFonts or {}
	if not ns.letterFonts[size] then
		local function Make(name, r, g, bl)
			local f = CreateFont(name)
			f:SetFont(A.TITLE_FONT, size, "")
			f:SetTextColor(r, g, bl)
			f:SetShadowColor(0, 0, 0, 0.9)
			f:SetShadowOffset(1, -1)
			return f
		end
		ns.letterFonts[size] = { Make("AzAlmWGLetter" .. size, 1, 0.82, 0.4), Make("AzAlmWGLetterOff" .. size, 0.62, 0.52, 0.32) }
	end
	local fonts = ns.letterFonts[size]
	b:SetNormalFontObject(fonts[1])
	b:SetHighlightFontObject(fonts[1])
	b:SetDisabledFontObject(fonts[2])
	return b
end

-- the window's corner icon, bigger and in the gold elite frame (the boss portrait's gold dragon ring,
-- (2026-10-22) Every emblem made is remembered weakly, so its cap of snow can be put on and taken
-- off as the season moves. Without this the cap was decided once, when the window was first built,
-- so a window opened before `/aa season` was typed never got one however often the season changed -
-- which is exactly how Wild Gambit came to be the only window without snow on its emblem.
local emblems = setmetatable({}, { __mode = "k" })
local CAP_SIZE = 106

function ns.RedressEmblem(e)
	if not (e and e.cap) then return end
	local d = ns.SeasonDecor()
	if d and d.cap then
		e.cap:SetTexture("Interface\\AddOns\\AzerothAlmanac\\Media\\" .. d.cap)
		e.cap:Show()
	else
		e.cap:Hide()
	end
end

-- as on the legendary cards) over the template's small round portrait, which it covers with a dark
-- socket. Centred on where that portrait sits.
function ns.GoldEmblem(frame, icon)
	local base = frame:GetFrameLevel()
	local e = CreateFrame("Frame", nil, frame)
	e:SetAllPoints(frame)
	e:EnableMouse(false)
	e:SetFrameLevel(base + 70)
	local anchor = frame.portrait
	local function Put(t, size)
		t:SetSize(size, size)
		t:ClearAllPoints()
		if anchor and anchor.GetCenter then t:SetPoint("CENTER", anchor, "CENTER", 0, 0) else t:SetPoint("CENTER", frame, "TOPLEFT", 28, -28) end
	end
	e.socket = e:CreateTexture(nil, "BACKGROUND")
	e.socket:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
	e.socket:SetVertexColor(0.04, 0.03, 0.025, 1)
	Put(e.socket, 84)
	-- A cap of snow during a holiday that has one. Drawn at CAP_SIZE rather than the socket's 84:
	-- the art leaves room above the circle it caps (its disc is 0.8 of the texture), so drawn at the
	-- socket's own size the snow would be cut off at the top.
	e.cap = e:CreateTexture(nil, "OVERLAY", nil, 3)
	Put(e.cap, CAP_SIZE)
	emblems[e] = true
	ns.RedressEmblem(e)
	e.icon = e:CreateTexture(nil, "ARTWORK")
	e.icon:SetTexture(icon)
	e.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
	Put(e.icon, 74)
	local mask = e:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(e.icon)
	e.icon:AddMaskTexture(mask)
	e.ring = e:CreateTexture(nil, "OVERLAY")
	-- the winged gold dragon where the client has it (as on the legendary cards), else the plain ring
	local ok, wide = false, 1
	for _, atlas in ipairs({ "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged", "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold" }) do
		if not ok and e.ring.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
			ok = pcall(e.ring.SetAtlas, e.ring, atlas)
			local info = ok and C_Texture.GetAtlasInfo(atlas)
			if info and info.width and info.height and info.height > 0 then wide = info.width / info.height end
		end
	end
	Put(e.ring, 118)
	e.ring:SetWidth(118 * wide) -- (the winged one is wider than it is tall)
	e.ring:SetShown(ok and true or false)
	frame.emblem = e
	return e
end

-- Wild Gambit headings (the pick screen's "Choose a card" / "Choose your class"): the carved-wood
-- screens' Morpheus lettering in gold with a deep shadow, flanked by a thin gold rule and a small
-- gold diamond on each side. `o:Layout()` puts the ornaments at the text's current width.
function ns.Ornament(fs, size, ruleLen)
	fs:SetFont(A.TITLE_FONT, size, "")
	fs:SetTextColor(1, 0.82, 0.4)
	fs:SetShadowColor(0, 0, 0, 0.95)
	fs:SetShadowOffset(1.5, -1.5)
	local parent = fs:GetParent()
	local o = { fs = fs, size = size, ruleLen = ruleLen }
	for _, side in ipairs({ "l", "r" }) do
		local d = parent:CreateTexture(nil, "OVERLAY")
		d:SetColorTexture(1, 0.82, 0.4, 0.95)
		d:SetSize(6, 6)
		d:SetRotation(math.rad(45))
		local rule = parent:CreateTexture(nil, "OVERLAY")
		rule:SetColorTexture(1, 0.82, 0.4, 0.5)
		rule:SetSize(ruleLen, 1.5)
		o["d" .. side], o["rule" .. side] = d, rule
	end
	function o:Layout(show)
		local on = show ~= false and fs:IsShown()
		for _, t in ipairs({ self.dl, self.dr, self.rulel, self.ruler }) do t:SetShown(on) end
		if not on then return end
		local w = fs:GetStringWidth()
		self.dl:ClearAllPoints()
		self.dl:SetPoint("CENTER", fs, "CENTER", -(w / 2 + 12), 0)
		self.dr:ClearAllPoints()
		self.dr:SetPoint("CENTER", fs, "CENTER", w / 2 + 12, 0)
		self.rulel:ClearAllPoints()
		self.rulel:SetPoint("RIGHT", self.dl, "LEFT", -3, 0)
		self.ruler:ClearAllPoints()
		self.ruler:SetPoint("LEFT", self.dr, "RIGHT", 3, 0)
	end
	return o
end

-- The holiday on now: "HallowsEnd", "WinterVeil" or nil. Shared by Wild Gambit's holiday boards and
-- Murloc Tac Toe's seasonal champions and board.
--
-- The game's own calendar is asked first, so the dress follows the event the server is actually
-- running rather than this addon's guess at when it starts. Classic clients differ in how much of
-- the calendar they expose, and its day events are only there once something has loaded them, so
-- every call is guarded and anything unanswered falls back to the dates Blizzard has kept to:
-- Hallow's End 18 Oct - 1 Nov, Winter Veil 16 Dec - 2 Jan.
local HOLIDAY_WORDS = {
	{ "HallowsEnd", "hallow" },
	{ "WinterVeil", "winter veil" },
}
local holidayCache, holidayAt = false, 0

local function HolidayFromCalendar()
	local C = C_Calendar
	if not (C and C.GetDate and C.GetNumDayEvents and C.GetDayEvent) then return nil end
	local ok, today = pcall(C.GetDate)
	if not (ok and type(today) == "table" and today.monthDay) then return nil end
	local okn, n = pcall(C.GetNumDayEvents, 0, today.monthDay)
	if not (okn and type(n) == "number" and n > 0) then return nil end
	for i = 1, n do
		local oke, e = pcall(C.GetDayEvent, 0, today.monthDay, i)
		local title = oke and type(e) == "table" and e.title
		if type(title) == "string" then
			local low = title:lower()
			for _, pair in ipairs(HOLIDAY_WORDS) do
				if low:find(pair[2], 1, true) then return pair[1] end
			end
		end
	end
	return nil
end

local function HolidayFromDates()
	local ok, t = pcall(date, "*t")
	if not (ok and type(t) == "table") then return nil end
	local m, d = t.month, t.day
	if (m == 10 and d >= 18) or (m == 11 and d <= 1) then return "HallowsEnd" end
	if (m == 12 and d >= 16) or (m == 1 and d <= 2) then return "WinterVeil" end
end

-- (2026-10-21, Shannon) A holiday can be pretended, so the seasonal dress can be looked at out of
-- season: `/aa season winterveil`. It is deliberately NOT saved - a pretend holiday should not
-- outlive the session it was turned on in, or it would be forgotten and mistaken for a bug in
-- March. `false` means pretend there is no holiday at all; nil means ask the calendar again.
function ns.PretendHoliday(key)
	ns.pretending = key
	holidayAt = 0 -- (so the next ask reads afresh rather than reusing the last minute's answer)
end

function ns.HolidayNow()
	if ns.pretending ~= nil then return ns.pretending or nil end
	-- asked often (every board dress and champion list), answered at most once a minute
	local now = GetTime and GetTime() or 0
	if holidayCache ~= false and (now - holidayAt) < 60 then return holidayCache end
	-- (nil is a real answer and is cached as nil; `false` only ever means "not asked yet")
	holidayCache, holidayAt = HolidayFromCalendar() or HolidayFromDates() or nil, now
	return holidayCache
end

-- (2026-10-22, Shannon: "winter touches to the Almanac") The Almanac's own windows dress for a
-- holiday too, not only the three games' boards: a drift of snow along the top edge, frost creeping
-- in at the corners, and a few flakes drifting inside. One table of holidays rather than code
-- written for Winter Veil, so Hallow's End next October costs art and a row here.
--
-- Everything is drawn above the window's border (frame level + 60) and never takes the mouse, so it
-- cannot swallow a click. Every window dressed is remembered weakly, so `/aa season` can redraw
-- them all at once and a closed window is still collected.
local SEASON_MEDIA = "Interface\\AddOns\\AzerothAlmanac\\Media\\"
local DECOR = {
	WinterVeil = {
		strip = "Season_Snow_Top", stripH = 26, tile = 3,
		corner = "Season_Frost_Corner", cornerSize = 104,
		cap = "Season_Emblem_Sprig", minimap = "Season_Minimap_Cap",
		mote = { 0.86, 0.94, 1 }, motes = 8, fall = 0.055,
	},
}
local dressed = setmetatable({}, { __mode = "k" })
local driver

-- the holiday's decoration, or nil: no holiday, none painted for it, or the player turned it off
function ns.SeasonDecor()
	local s = A.db and A.db.settings
	if s and s.seasonalDecor == false then return nil end
	local h = ns.HolidayNow()
	return h and DECOR[h] or nil
end

local CORNERS = { { "TOPLEFT", 0, 1, 0, 1 }, { "TOPRIGHT", 1, 0, 0, 1 },
	{ "BOTTOMLEFT", 0, 1, 1, 0 }, { "BOTTOMRIGHT", 1, 0, 1, 0 } }

local function Flakes(deco, d, w, h)
	local t = GetTime and GetTime() or 0
	for i, m in ipairs(deco.motes) do
		local y = (m.y + t * d.fall * m.sp) % 1.08 - 0.04
		local x = m.x + 0.015 * math.sin(t * m.sw + m.ph)
		m.tex:ClearAllPoints()
		m.tex:SetPoint("CENTER", deco, "TOPLEFT", x * w, -(y * h))
		m.tex:SetAlpha(m.a * (0.45 + 0.4 * math.sin(t * 1.1 + m.ph)))
	end
end

local function Drive()
	if driver then return end
	driver = CreateFrame("Frame")
	driver:SetScript("OnUpdate", function()
		for frame, deco in pairs(dressed) do
			if deco.on and frame:IsVisible() then
				Flakes(deco, deco.on, frame:GetWidth(), frame:GetHeight())
			end
		end
	end)
end

-- dress (or undress) one window for the season it is now
function ns.RedressWindow(frame)
	local deco = dressed[frame]
	if not deco then return end
	local d = ns.SeasonDecor()
	deco.on = d
	if not d then deco:Hide() return end
	deco:Show()
	deco.strip:SetTexture(SEASON_MEDIA .. d.strip)
	deco.strip:SetTexCoord(0, d.tile or 1, 0, 1)
	deco.strip:SetHeight(d.stripH)
	for i, t in ipairs(deco.corners) do
		t:SetTexture(SEASON_MEDIA .. d.corner)
		t:SetSize(d.cornerSize, d.cornerSize)
		local c = CORNERS[i]
		t:SetTexCoord(c[2], c[3], c[4], c[5])
	end
	for _, m in ipairs(deco.motes) do
		m.tex:SetVertexColor(d.mote[1], d.mote[2], d.mote[3])
		m.tex:SetShown(true)
	end
	for i = d.motes + 1, #deco.motes do deco.motes[i].tex:Hide() end
end

function ns.RedressAll()
	for frame in pairs(dressed) do ns.RedressWindow(frame) end
	for e in pairs(emblems) do ns.RedressEmblem(e) end
end

-- ask for a window to be dressed for whatever holiday is on. Safe to call on any frame, once.
function ns.DressForSeason(frame, opts)
	if not frame or dressed[frame] then return end
	opts = opts or {}
	local deco = CreateFrame("Frame", nil, frame)
	deco:SetAllPoints(frame)
	deco:EnableMouse(false)
	deco:SetFrameLevel(frame:GetFrameLevel() + 60)
	deco.strip = deco:CreateTexture(nil, "OVERLAY", nil, 2)
	deco.strip:SetPoint("TOPLEFT", opts.inset or 3, opts.top or -2)
	deco.strip:SetPoint("TOPRIGHT", -(opts.inset or 3), opts.top or -2)
	deco.corners = {}
	for i, c in ipairs(CORNERS) do
		local t = deco:CreateTexture(nil, "OVERLAY", nil, 1)
		t:SetPoint(c[1])
		deco.corners[i] = t
	end
	-- the flakes sit under the border art, so they drift behind the frame rather than over it
	deco.motes = {}
	for k = 1, 10 do
		local t = deco:CreateTexture(nil, "ARTWORK", nil, 3)
		t:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
		t:SetBlendMode("ADD")
		local size = 5 + (k % 3) * 3
		t:SetSize(size, size)
		deco.motes[k] = { tex = t, x = ((k * 37) % 100) / 100, y = ((k * 61) % 100) / 100,
			sp = 0.7 + (k % 4) * 0.22, sw = 0.5 + (k % 5) * 0.17, ph = k * 1.9,
			a = 0.30 + (k % 3) * 0.10 }
	end
	dressed[frame] = deco
	Drive()
	ns.RedressWindow(frame)
end
