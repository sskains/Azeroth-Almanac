-- Ported from Plus Everything (same author) for Azeroth Almanac's quality-of-life helpers.
-- Unit frames: a small class emblem on the player, target and party portraits (like the faction
-- badge on the Inventory portraits), players' names in their class color, and XP left on the XP bar.
-- Settings > Group Settings. Only decorates Blizzard's frames: nothing here is protected.

local _, A = ...
local ns = A.QoL
local UF = ns:NewModule("UnitFrames")

local db
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local badges = {} -- unit frame -> badge
local tinted = setmetatable({}, { __mode = "k" }) -- frames whose name we've recolored, to put back when turned off

local COLORED_UNITS = { player = true, target = true, focus = true, party1 = true, party2 = true, party3 = true, party4 = true }

local function Readable(v) return ns.Readable(v) end

-- frame.a.b.c without erroring on a missing step
local function Path(root, ...)
	local node = root
	for i = 1, select("#", ...) do
		if type(node) ~= "table" then return nil end
		node = node[select(i, ...)]
	end
	return node
end

local function UnitOf(frame)
	local unit = frame.unit
	if not unit and frame.GetUnit then unit = frame:GetUnit() end
	return unit
end

local function PlayerClass(unit)
	if not unit then return end
	local ok, isPlayer = pcall(UnitIsPlayer, unit)
	if not (ok and Readable(isPlayer)) then return end
	local _, class = UnitClass(unit)
	return Readable(class)
end

local function ClassRGB(class)
	local c = class and ((CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
	if c then return c.r, c.g, c.b end
end

---------------------------------------------------------------------------
-- Class badges
---------------------------------------------------------------------------

-- side: "RIGHT" tucks it on the portrait's bottom right, "LEFT" on the bottom left (target frame).
local function MakeBadge(frame, portrait, side)
	local size = math.max(16, math.floor((portrait:GetWidth() or 40) * 0.42 + 0.5))
	local b = CreateFrame("Frame", nil, frame)
	b:SetSize(size, size)
	if side == "LEFT" then
		b:SetPoint("BOTTOMLEFT", portrait, "BOTTOMLEFT", -size * 0.18, -size * 0.12)
	else
		b:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", size * 0.18, -size * 0.12)
	end
	b:SetFrameLevel(frame:GetFrameLevel() + 8)
	b:EnableMouse(false)
	-- a gold rim and a dark disc behind the emblem
	b.rim = b:CreateTexture(nil, "BACKGROUND")
	b.rim:SetTexture(CIRCLE)
	b.rim:SetAllPoints()
	b.rim:SetVertexColor(0.85, 0.68, 0.3)
	b.disc = b:CreateTexture(nil, "BORDER")
	b.disc:SetTexture(CIRCLE)
	b.disc:SetPoint("TOPLEFT", 1.5, -1.5)
	b.disc:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
	b.disc:SetVertexColor(0.05, 0.04, 0.03)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 2, -2)
	b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	local mask = b:CreateMaskTexture()
	mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(b.icon)
	b.icon:AddMaskTexture(mask)
	b:Hide()
	badges[frame] = b
	return b
end

local function UpdateBadge(frame)
	local b = badges[frame]
	if not b then return end
	local class = db.classBadge and frame:IsShown() and PlayerClass(UnitOf(frame))
	if class and ns.SetClassIcon(b.icon, class) then
		local r, g, bl = ClassRGB(class)
		if r then b.rim:SetVertexColor(r, g, bl) end
		b:Show()
	else
		b:Hide()
	end
end

---------------------------------------------------------------------------
-- Class-colored names
---------------------------------------------------------------------------
-- The target and focus frames have a colored strip behind the name (Blizzard paints it by
-- standing: blue for friendly players, red for enemies). For players it takes their class
-- color instead. Your own frame and party frames have no strip, so their name text does.
-- (This replaced class-colored health bars: the health bars are left to the game.)

local names = {} -- unit frame -> { strip = texture } or { text = font string }

local function RecolorName(frame)
	local entry = names[frame]
	if not entry then return end
	local unit = UnitOf(frame)
	local class = db.classColor and unit and COLORED_UNITS[unit] and PlayerClass(unit)
	local r, g, b
	if class then r, g, b = ClassRGB(class) end
	if entry.strip then
		if r then
			entry.strip:SetVertexColor(r, g, b)
			tinted[frame] = true
		elseif tinted[frame] then
			tinted[frame] = nil
			if frame.CheckFaction then pcall(frame.CheckFaction, frame) end -- the game's own color back
		end
	elseif entry.text then
		if r then
			entry.text:SetTextColor(r, g, b)
			tinted[frame] = true
		elseif tinted[frame] then
			tinted[frame] = nil
			entry.text:SetTextColor(1, 0.82, 0) -- the game's gold
		end
	end
end

local function AddName(frame, entry)
	if not frame or not (entry.strip or entry.text) then return end
	if not names[frame] then
		names[frame] = entry
		-- Blizzard repaints the strip on every target change and standing update
		if entry.strip and frame.CheckFaction then hooksecurefunc(frame, "CheckFaction", RecolorName) end
	end
	RecolorName(frame)
end

---------------------------------------------------------------------------
-- Finding Blizzard's frames
---------------------------------------------------------------------------

local function PartyMembers()
	local list = {}
	local pool = PartyFrame and PartyFrame.PartyMemberFramePool
	if pool and pool.EnumerateActive then
		for member in pool:EnumerateActive() do list[#list + 1] = member end
	elseif PartyFrame then
		for i = 1, 4 do
			local member = PartyFrame["MemberFrame" .. i]
			if member then list[#list + 1] = member end
		end
	end
	return list
end

local hookedMembers = {}

local function Scan()
	if PlayerFrame then
		local portrait = Path(PlayerFrame, "PlayerFrameContainer", "PlayerPortrait")
		if portrait and not badges[PlayerFrame] then MakeBadge(PlayerFrame, portrait, "RIGHT") end
		AddName(PlayerFrame, { text = PlayerName or PlayerFrame.name })
	end
	for _, frame in ipairs({ TargetFrame or false, FocusFrame or false }) do
		if frame then
			local portrait = Path(frame, "TargetFrameContainer", "Portrait")
			if portrait and not badges[frame] then MakeBadge(frame, portrait, "LEFT") end
			AddName(frame, { strip = Path(frame, "TargetFrameContent", "TargetFrameContentMain", "ReputationColor") })
		end
	end
	for _, member in ipairs(PartyMembers()) do
		if member.Portrait and not badges[member] then MakeBadge(member, member.Portrait, "RIGHT") end
		AddName(member, { text = member.Name })
		if not hookedMembers[member] then
			hookedMembers[member] = true
			member:HookScript("OnShow", function(self) UpdateBadge(self) RecolorName(self) end)
		end
	end
end

---------------------------------------------------------------------------
-- XP needed on the experience bar
---------------------------------------------------------------------------
-- Each status-bar slot (main and secondary) has its own experience bar. Blizzard's text
-- ("1200 / 5600", on hover or always with the game's option) gets "- 4400 to go", and a
-- small label on the bar's right end always shows what's left.

local xpBars = {} -- experience bar -> our label

local function Number(n)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

local function XPLeft()
	local level, max = UnitLevel("player"), GetMaxPlayerLevel and GetMaxPlayerLevel()
	if max and level >= max then return end
	local current, total = UnitXP("player"), UnitXPMax("player")
	if not (current and total and total > 0) then return end
	return total - current, level + 1, total, GetXPExhaustion and GetXPExhaustion() or nil
end

-- Our own label only. Nothing here hooks, calls or rewrites the game's experience bar code or text
-- (doing that was suspected of upsetting the game's bar updates); the label simply reads the XP
-- numbers itself and checks every half second whether the game's own text is showing.
local function UpdateXPBar(bar)
	local label = xpBars[bar]
	local text = bar.OverlayFrame and bar.OverlayFrame.Text
	local left, nextLevel = XPLeft()
	if not (label and left and db.xpNeeded) then
		if label then label:Hide() end
		return
	end
	label:SetText(("%s XP to level %d"):format(Number(left), nextLevel))
	-- Only when Blizzard's own text isn't up, so the two don't overlap.
	label:SetShown(db.xpAlways and not (text and text:IsShown()))
end

local function MakeXPLabels()
	local manager = StatusTrackingBarManager
	local enum = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
	if not (manager and manager.barContainers and enum) then return end
	for _, container in ipairs(manager.barContainers) do
		local bar = container.bars and container.bars[enum.Experience]
		if bar and not xpBars[bar] and bar.OverlayFrame then
			local label = bar.OverlayFrame:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
			label:SetPoint("RIGHT", bar, "RIGHT", -6, 1)
			label:SetJustifyH("RIGHT")
			label:SetTextColor(1, 0.92, 0.7)
			xpBars[bar] = label
		end
	end
end

function UF:RefreshXP()
	MakeXPLabels()
	for bar in pairs(xpBars) do UpdateXPBar(bar) end
end

function UF:Refresh()
	if not db then return end
	UF:RefreshXP()
	Scan()
	for frame in pairs(badges) do UpdateBadge(frame) end
	for frame in pairs(names) do RecolorName(frame) end
end

---------------------------------------------------------------------------
-- Module API
---------------------------------------------------------------------------

function UF:OnInitialize(saved)
	db = saved.unitFrames
end

function UF:OnLogin()
	if PartyFrame then
		for _, method in ipairs({ "InitializePartyMemberFrames", "UpdatePartyFrames", "UpdateMemberFrames" }) do
			if PartyFrame[method] then hooksecurefunc(PartyFrame, method, function() UF:Refresh() end) end
		end
	end
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "GROUP_ROSTER_UPDATE", "UNIT_NAME_UPDATE", "UNIT_CONNECTION" }) do
		pcall(events.RegisterEvent, events, event)
	end
	local xpEvents = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP" }) do pcall(xpEvents.RegisterEvent, xpEvents, event) end
	xpEvents:SetScript("OnEvent", function() C_Timer.After(0, function() UF:RefreshXP() end) end)
	-- (hover shows the game's own text, which hides our label: follow that without hooking anything)
	C_Timer.NewTicker(0.5, function() if db.xpNeeded then UF:RefreshXP() end end)
	events:SetScript("OnEvent", function()
		-- after Blizzard's own handlers have updated the frames
		C_Timer.After(0, function() UF:Refresh() end)
	end)
	UF:Refresh()
end
