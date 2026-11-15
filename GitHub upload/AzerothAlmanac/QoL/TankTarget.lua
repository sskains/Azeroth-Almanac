-- (2026-11-06) The tank's target: in a group with a tank (the tank role, or a raid's main tank),
-- the enemy each tank has targeted is marked on its nameplate, all the time - a tank shield with
-- an arrow above the plate, an outline round its health bar, or both (Settings > Group Settings).
--
-- In combat the tanks' targets are read every POLL seconds, as asked: UNIT_TARGET says when a
-- tank switches, but it can be late or missing for a groupmate far off, and the poll is what
-- keeps the mark honest. Out of combat the events alone are enough (UNIT_TARGET, nameplates
-- appearing), so nothing ticks then.
--
-- Plates are found by GUID: a map kept from NAME_PLATE_UNIT_ADDED / REMOVED, so each poll is one
-- lookup per tank rather than a pass over every plate. Enemy plates work in dungeons and raids
-- (only friendly ones are locked there), but there is no plate to mark until the mob is in
-- nameplate range, or with enemy nameplates switched off.
--
-- The marker sits above the plate and the outline outside Threat Monitor's edge (which hugs the
-- bar at 2 px), so the two never cover each other. The red glow (2026-11-11) is a fourth look:
-- a breathing red halo behind the bar, the nearest an addon gets to the game's ground circle. Game art first: the role icon atlas, with the
-- old role texture as the fallback (ground rule 7).

local _, A = ...
local ns = A.QoL
local TT = ns:NewModule("TankTarget")

local POLL = 0.25
TT.POLL = POLL
local WHITE = "Interface\\Buttons\\WHITE8X8"
local ROLE_ATLAS, ARROW_ATLAS = "roleicon-tiny-tank", "npe_arrowdown"
local ROLE_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"

TT.looks = { { name = "Marker above", key = "marker" }, { name = "Outline", key = "outline" }, { name = "Both", key = "both" },
	{ name = "Red glow", key = "glow" } }
-- (2026-11-11, Shannon: "a red selection under its feet, like the normal selection in the world") an
-- addon can't draw on the ground, so the closest is on the plate: a red halo round the health bar,
-- breathing slowly (the game's soft glow, drawn added so it reads as light, not paint)
local GLOW_TEXTURE = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"
local GLOW_COLOR = { 1, 0.16, 0.1 }
local GLOW_PULSE = 1.4                 -- seconds for one breath
local GLOW_LOW, GLOW_HIGH = 0.45, 0.95 -- its brightness, between breaths and at the top of one

local db
local R = function(v) return ns.Readable(v) end
local tanks = {}      -- unit tokens of the group's tanks (and "player" with whenTank)
local plateUnit = {}  -- GUID -> nameplate unit token, for the enemy plates on screen
local marks = {}      -- plate -> its mark frame (kept, hidden, for when the plate comes back)
local ticker

local function HasAtlas(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

---------------------------------------------------------------------------
-- Who the tanks are
---------------------------------------------------------------------------

local function ReadTanks()
	wipe(tanks)
	if not (db and db.enabled) then return end
	if IsInGroup() then
		local raid = IsInRaid()
		local prefix, count = raid and "raid" or "party", raid and 40 or 4
		for i = 1, count do
			local token = prefix .. i
			if R(UnitExists(token)) and not R(UnitIsUnit(token, "player")) and ns.IsTankUnit(token) then
				tanks[#tanks + 1] = token
			end
		end
		if db.whenTank and ns.IsTankUnit("player") then tanks[#tanks + 1] = "player" end
	end
end
TT.Tanks = function() return tanks end

---------------------------------------------------------------------------
-- The mark on a plate
---------------------------------------------------------------------------

local function Mark(plate)
	local m = marks[plate]
	if m then return m end
	m = CreateFrame("Frame", nil, plate)
	m:SetFrameStrata("HIGH")
	-- the outline: outside Threat Monitor's 2 px edge
	m.edge = CreateFrame("Frame", nil, m, "BackdropTemplate")
	m.edge:SetBackdrop({ edgeFile = WHITE, edgeSize = 2 })
	-- the marker: the tank shield, an arrow under it pointing at the plate
	m.icon = m:CreateTexture(nil, "OVERLAY")
	m.icon:SetSize(18, 18)
	if HasAtlas(ROLE_ATLAS) then
		m.icon:SetAtlas(ROLE_ATLAS)
	else
		m.icon:SetTexture(ROLE_TEXTURE)
		m.icon:SetTexCoord(0, 19 / 64, 22 / 64, 41 / 64)
	end
	m.arrow = m:CreateTexture(nil, "OVERLAY")
	m.arrow:SetSize(14, 14)
	if HasAtlas(ARROW_ATLAS) then m.arrow:SetAtlas(ARROW_ATLAS) else m.arrow:Hide() m.noArrow = true end
	m.arrow:SetPoint("TOP", m.icon, "BOTTOM", 0, 2)
	-- the red glow: behind the bar, wider than it, breathing while it shows
	m.glow = m:CreateTexture(nil, "BACKGROUND")
	m.glow:SetTexture(GLOW_TEXTURE)
	m.glow:SetBlendMode("ADD")
	m.glow:SetVertexColor(GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3])
	m.glow:Hide()
	m:SetScript("OnUpdate", function(self)
		if not self.glow:IsShown() then return end
		local k = 0.5 + 0.5 * math.sin(GetTime() * 2 * math.pi / GLOW_PULSE)
		self.glow:SetAlpha(GLOW_LOW + (GLOW_HIGH - GLOW_LOW) * k)
	end)
	m:Hide()
	marks[plate] = m
	return m
end
TT.MarkOf = function(plate) return marks[plate] end

local function Place(m, plate)
	-- the plate's unit frame is pooled: anchor to whichever one the plate has now
	local frame = plate.UnitFrame
	local bar = frame and (frame.healthBar or frame.HealthBarsContainer)
	local top = (frame and frame.name) or bar or plate
	local look = db.look or "marker"
	-- (a plate with no health bar to go round gets the marker whatever the look)
	local glow = look == "glow" and bar ~= nil
	local outline = (look == "outline" or look == "both") and bar ~= nil
	local marker = look == "marker" or look == "both" or not (glow or outline)
	m:ClearAllPoints()
	m:SetAllPoints(plate)
	m.icon:ClearAllPoints()
	m.icon:SetPoint("BOTTOM", top, "TOP", 0, 16)
	m.icon:SetShown(marker)
	m.arrow:SetShown(marker and not m.noArrow)
	if outline then
		local c = db.color or { 0.25, 0.6, 1 }
		m.edge:ClearAllPoints()
		m.edge:SetPoint("TOPLEFT", bar, "TOPLEFT", -4, 4)
		m.edge:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 4, -4)
		m.edge:SetBackdropBorderColor(c[1], c[2], c[3], 1)
	end
	m.edge:SetShown(outline)
	if glow then
		m.glow:ClearAllPoints()
		m.glow:SetPoint("TOPLEFT", bar, "TOPLEFT", -22, 14)
		m.glow:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 22, -14)
	end
	m.glow:SetShown(glow)
end

local function Show(plate)
	local m = Mark(plate)
	Place(m, plate)
	if not m:IsShown() then
		m:Show()
		-- fade in rather than pop, so a tank flicking between mobs doesn't flash
		if UIFrameFadeIn then UIFrameFadeIn(m, 0.15, 0, 1) else m:SetAlpha(1) end
	end
end

---------------------------------------------------------------------------
-- What the tanks have targeted, and marking it
---------------------------------------------------------------------------

-- The plate of tank's target, if it's an enemy worth marking.
local function TargetPlate(tank)
	if not R(UnitIsConnected(tank)) or R(UnitIsDeadOrGhost(tank)) then return nil end
	local t = tank .. "target"
	if not R(UnitExists(t)) or R(UnitIsDead(t)) or not R(UnitCanAttack("player", t)) then return nil end
	local guid = R(UnitGUID(t))
	local unit = guid and plateUnit[guid]
	return unit and C_NamePlate.GetNamePlateForUnit(unit)
end

function TT:Update()
	local want = {}
	if db and db.enabled then
		for _, tank in ipairs(tanks) do
			local ok, plate = pcall(TargetPlate, tank)
			if ok and plate then want[plate] = true end
		end
	end
	for plate in pairs(want) do Show(plate) end
	for plate, m in pairs(marks) do
		if not want[plate] then m:Hide() end
	end
end

local function Tick() TT:Update() end

local function StartPolling()
	if ticker or not (db and db.enabled) or #tanks == 0 then return end
	ticker = C_Timer.NewTicker(POLL, Tick)
end

local function StopPolling()
	if ticker then ticker:Cancel() ticker = nil end
end
TT.Polling = function() return ticker ~= nil end

---------------------------------------------------------------------------
-- Nameplates on screen, by GUID
---------------------------------------------------------------------------

local function PlateAdded(unit)
	local guid = R(UnitGUID(unit))
	if guid then plateUnit[guid] = unit end
end

local function PlateRemoved(unit)
	for guid, u in pairs(plateUnit) do
		if u == unit then plateUnit[guid] = nil end
	end
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if plate and marks[plate] then marks[plate]:Hide() end
end

local function ReadPlates()
	wipe(plateUnit)
	for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if unit then PlateAdded(unit) end
	end
end

---------------------------------------------------------------------------
-- Settings and start-up
---------------------------------------------------------------------------

-- after a setting changed (Settings > Group Settings > Tank's target)
function TT:Refresh()
	ReadTanks()
	if InCombatLockdown() and #tanks > 0 and db.enabled then StartPolling() else StopPolling() end
	self:Update()
end

function TT:OnInitialize(saved)
	db = saved.tankTarget
end

function TT:OnLogin()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_ENTERING_WORLD", "UNIT_TARGET",
		"PLAYER_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_REGEN_DISABLED",
		"PLAYER_REGEN_ENABLED", "UNIT_CONNECTION" }) do
		events:RegisterEvent(event)
	end
	events:SetScript("OnEvent", function(_, event, unit)
		if event == "NAME_PLATE_UNIT_ADDED" then
			if unit then PlateAdded(unit) end
		elseif event == "NAME_PLATE_UNIT_REMOVED" then
			if unit then PlateRemoved(unit) end
			return
		elseif event == "PLAYER_REGEN_DISABLED" then
			StartPolling()
		elseif event == "PLAYER_REGEN_ENABLED" then
			StopPolling()
		elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" or event == "UNIT_CONNECTION" then
			ReadTanks()
			if InCombatLockdown() then StartPolling() end
			if #tanks == 0 then StopPolling() end
		elseif event == "PLAYER_ENTERING_WORLD" then
			ReadTanks()
			ReadPlates()
		end
		if #tanks > 0 or next(marks) then TT:Update() end
	end)
	ReadTanks()
	ReadPlates()
	-- logged in (or reloaded) mid-fight
	if InCombatLockdown() then StartPolling() end
	TT:Update()
end
