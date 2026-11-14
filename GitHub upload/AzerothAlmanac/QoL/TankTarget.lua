-- (2026-11-06) The tank's target: in a group with a tank (the tank role, or a raid's main tank),
-- the enemy each tank has targeted is marked on its nameplate, all the time - a tank shield with
-- an arrow above the plate, a soft glow round its health bar, or both (Settings > Group Settings).
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
-- The marker sits above the plate; the glows sit behind the bar, outside Threat Monitor's edge
-- (which hugs the bar at 2 px), so they never cover each other. (2026-11-11) The soft glow (the
-- "outline" look, glow only: no hard edge, Shannon) is purple by default; the red glow is a fourth
-- look, breathing, the nearest an addon gets to the game's ground circle; and your target being a
-- tank's target lights a brighter purple glow on its plate and a halo behind your Target frame.
-- Game art first: the role icon atlas, with the old role texture as the fallback (ground rule 7).

local _, A = ...
local ns = A.QoL
local TT = ns:NewModule("TankTarget")

local POLL = 0.25
TT.POLL = POLL
local ROLE_ATLAS, ARROW_ATLAS = "roleicon-tiny-tank", "npe_arrowdown"
local ROLE_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"

-- (2026-11-11, Shannon: "just a glow, no hard outline") the "outline" look is a glow round the bar now:
-- its name says so; its key stays, so saved choices still mean the same
TT.looks = { { name = "Marker above", key = "marker" }, { name = "Soft glow", key = "outline" }, { name = "Both", key = "both" },
	{ name = "Red glow", key = "glow" } }
-- (2026-11-11, Shannon: "a red selection under its feet, like the normal selection in the world") an
-- addon can't draw on the ground, so the closest is on the plate: a red halo round the health bar,
-- breathing slowly (the game's soft glow, drawn added so it reads as light, not paint)
local GLOW_TEXTURE = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"
local GLOW_COLOR = { 1, 0.16, 0.1 }
local GLOW_PULSE = 1.4                 -- seconds for one breath
local GLOW_LOW, GLOW_HIGH = 0.45, 0.95 -- its brightness, between breaths and at the top of one

-- (2026-11-11, Shannon: "enhance the outline ... a glow ... standard purple"; then "just a glow, no
-- hard outline") the glow round the bar, in the game's epic purple by default; no edge drawn
TT.PURPLE = { 0.64, 0.21, 0.93 }
local OLD_BLUE = { 0.25, 0.6, 1 }      -- the outline's first default: moved to purple once (OnInitialize)
-- (with no edge, the glow is the whole look: no "Off"; an "off" saved earlier reads as Soft)
TT.glowLevels = { { name = "Soft", key = "soft", alpha = 0.6 }, { name = "Strong", key = "strong", alpha = 0.95 } }
-- (2026-11-11) "you're on it": your target is a tank's target. Its plate gets a brighter purple glow
-- (no hard frame) that pulses once a second, and your Target frame a purple halo. Our own frames: nothing of the
-- game's (its nameplate highlight, its Target frame) is recoloured or changed.
local LOCK_PULSE, LOCK_LOW, LOCK_HIGH = 1.0, 0.6, 1.0

local db
local R = function(v) return ns.Readable(v) end
local tanks = {}      -- unit tokens of the group's tanks (and "player" with whenTank)
local plateUnit = {}  -- GUID -> nameplate unit token, for the enemy plates on screen
local onScreen = {}   -- nameplate unit token -> true, for every plate on screen (GUIDs can be secret)
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
	-- (2026-11-11) the soft glow round the bar (the "outline" look): the game's soft glow in the
	-- chosen colour, and nothing else (Shannon: no hard outline)
	m.edgeGlow = m:CreateTexture(nil, "BACKGROUND", nil, 1)
	m.edgeGlow:SetTexture(GLOW_TEXTURE)
	m.edgeGlow:SetBlendMode("ADD")
	m.edgeGlow:Hide()
	-- (2026-11-11) locked on (your target is this tank's target): a bigger, brighter purple glow, no frame
	m.lock = CreateFrame("Frame", nil, m)
	m.lock.halo = m.lock:CreateTexture(nil, "BACKGROUND")
	m.lock.halo:SetTexture(GLOW_TEXTURE)
	m.lock.halo:SetBlendMode("ADD")
	m.lock.halo:SetVertexColor(TT.PURPLE[1], TT.PURPLE[2], TT.PURPLE[3])
	m.lock.halo:SetPoint("TOPLEFT", -24, 16)
	m.lock.halo:SetPoint("BOTTOMRIGHT", 24, -16)
	m.lock:Hide()
	m:SetScript("OnUpdate", function(self)
		local now = GetTime()
		if self.glow:IsShown() then
			local k = 0.5 + 0.5 * math.sin(now * 2 * math.pi / GLOW_PULSE)
			self.glow:SetAlpha(GLOW_LOW + (GLOW_HIGH - GLOW_LOW) * k)
		end
		if self.lock:IsShown() then
			local k = 0.5 + 0.5 * math.sin(now * 2 * math.pi / LOCK_PULSE)
			self.lock:SetAlpha(LOCK_LOW + (LOCK_HIGH - LOCK_LOW) * k)
		end
	end)
	m:Hide()
	marks[plate] = m
	return m
end
TT.MarkOf = function(plate) return marks[plate] end

local function GlowAlpha()
	for _, g in ipairs(TT.glowLevels) do if g.key == db.outlineGlow then return g.alpha end end
	return TT.glowLevels[1].alpha
end

local function Place(m, plate, locked)
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
		local c = db.color or TT.PURPLE
		m.edgeGlow:ClearAllPoints()
		m.edgeGlow:SetPoint("TOPLEFT", bar, "TOPLEFT", -18, 12)
		m.edgeGlow:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 18, -12)
		m.edgeGlow:SetVertexColor(c[1], c[2], c[3])
		m.edgeGlow:SetAlpha(GlowAlpha())
	end
	m.edgeGlow:SetShown(outline)
	-- locked on: the brighter purple glow round the bar (or the plate, with no bar), whatever the look
	local lock = locked and db.lockOn ~= false and db.lockOnPlate ~= false
	if lock then
		local around = bar or plate
		m.lock:ClearAllPoints()
		m.lock:SetPoint("TOPLEFT", around, "TOPLEFT", -6, 6)
		m.lock:SetPoint("BOTTOMRIGHT", around, "BOTTOMRIGHT", 6, -6)
	end
	m.lock:SetShown(lock and true or false)
	if glow then
		m.glow:ClearAllPoints()
		m.glow:SetPoint("TOPLEFT", bar, "TOPLEFT", -22, 14)
		m.glow:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 22, -14)
	end
	m.glow:SetShown(glow)
end

local function Show(plate, locked)
	local m = Mark(plate)
	Place(m, plate, locked)
	if not m:IsShown() then
		m:Show()
		-- fade in rather than pop, so a tank flicking between mobs doesn't flash
		if UIFrameFadeIn then UIFrameFadeIn(m, 0.15, 0, 1) else m:SetAlpha(1) end
	end
end

---------------------------------------------------------------------------
-- What the tanks have targeted, and marking it
---------------------------------------------------------------------------

-- (2026-11-13, Shannon: "not working in dungeons") inside instances the game keeps a creature's GUID
-- secret, so a plate can't be found by GUID there, and a yes/no the game won't tell (a secret) must
-- not count as "no". The plate is found three ways, the first that works:
--   1. the game's own lookup by the unit token ("party1target"): no GUID needed
--   2. by GUID, in the map of plates on screen (out in the world)
--   3. each plate on screen asked "is this the same unit?" (the game compares, secrets and all)
local function Plate(u)
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, u)
	if ok and plate and not A.IsSecret(plate) then return plate end
end
TT.howFound = {}  -- tank -> "token", "guid" or "same": how its target's plate was last found (/aa tank why)

local function FindPlate(t)
	local plate = Plate(t)
	if plate then return plate, "token" end
	local guid = R(UnitGUID(t))
	local unit = guid and plateUnit[guid]
	plate = unit and Plate(unit)
	if plate then return plate, "guid" end
	for u in pairs(onScreen) do
		local ok, same = pcall(UnitIsUnit, u, t)
		if ok and R(same) == true then
			plate = Plate(u)
			if plate then return plate, "same" end
		end
	end
end

-- The plate of tank's target, if it's an enemy worth marking (only a clear "no" rules one out).
local function TargetPlate(tank)
	if R(UnitIsConnected(tank)) == false or R(UnitIsDeadOrGhost(tank)) == true then return nil end
	local t = tank .. "target"
	if R(UnitExists(t)) == false or R(UnitIsDead(t)) == true or R(UnitCanAttack("player", t)) == false then return nil end
	local plate, how = FindPlate(t)
	TT.howFound[tank] = how
	return plate
end

-- (2026-11-11) your Target frame's purple halo: a frame of ours behind the game's, anchored to it but
-- not inside it (the Target frame is a protected unit frame: nothing is added to or changed on it)
local targetHalo
local function TargetHalo()
	if targetHalo or not TargetFrame then return targetHalo end
	local h = CreateFrame("Frame", nil, UIParent)
	h:SetPoint("TOPLEFT", TargetFrame, "TOPLEFT", -14, 12)
	h:SetPoint("BOTTOMRIGHT", TargetFrame, "BOTTOMRIGHT", 14, -12)
	h:SetFrameStrata(TargetFrame:GetFrameStrata() or "LOW")
	h:SetFrameLevel(math.max(0, (TargetFrame:GetFrameLevel() or 1) - 1))
	h.tex = h:CreateTexture(nil, "BACKGROUND")
	h.tex:SetAllPoints()
	h.tex:SetTexture(GLOW_TEXTURE)
	h.tex:SetBlendMode("ADD")
	h.tex:SetVertexColor(TT.PURPLE[1], TT.PURPLE[2], TT.PURPLE[3])
	h:SetScript("OnUpdate", function(self)
		local k = 0.5 + 0.5 * math.sin(GetTime() * 2 * math.pi / LOCK_PULSE)
		self.tex:SetAlpha(LOCK_LOW + (LOCK_HIGH - LOCK_LOW) * k)
	end)
	h:Hide()
	targetHalo = h
	return h
end
TT.TargetHalo = function() return targetHalo end

-- your target is this tank's target: the game's own same-unit check, so it holds without a nameplate;
-- where that's secret (in instances), the two having the same plate
local function OnIt(tank, plate)
	if R(UnitExists("target")) == false then return false end
	local same = R(UnitIsUnit("target", tank .. "target"))
	if same ~= nil then return same == true end
	return plate ~= nil and Plate("target") == plate
end

function TT:Update()
	local want = {}
	local lockedAny = false
	if db and db.enabled then
		for _, tank in ipairs(tanks) do
			local ok, plate = pcall(TargetPlate, tank)
			plate = ok and plate or nil
			local okL, on = pcall(OnIt, tank, plate)
			on = okL and on and R(UnitCanAttack("player", "target")) ~= false and R(UnitIsDead("target")) ~= true
			if on then lockedAny = true end
			if ok and plate then want[plate] = want[plate] or (on and true) or false end
		end
	end
	for plate, locked in pairs(want) do Show(plate, locked) end
	for plate, m in pairs(marks) do
		if want[plate] == nil then m:Hide() end
	end
	local halo = TargetHalo()
	if halo then halo:SetShown(lockedAny and db.lockOn ~= false and db.lockOnFrame ~= false) end
	TT.lockedOn = lockedAny
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
	onScreen[unit] = true
	local guid = R(UnitGUID(unit))
	if guid then plateUnit[guid] = unit end
end

local function PlateRemoved(unit)
	onScreen[unit] = nil
	for guid, u in pairs(plateUnit) do
		if u == unit then plateUnit[guid] = nil end
	end
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if plate and marks[plate] then marks[plate]:Hide() end
end

local function ReadPlates()
	wipe(plateUnit)
	wipe(onScreen)
	for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if unit then PlateAdded(unit) end
	end
end

---------------------------------------------------------------------------
-- /aa tank why: what the game tells us, step by step (for a dungeon where the mark doesn't show)
---------------------------------------------------------------------------

local function Say(v)
	if v == nil then return "nil" end
	if A.IsSecret(v) then return "|cffff8040secret|r" end
	return tostring(v)
end

function TT:Why()
	local P = ns.Print
	local inInstance, kind = IsInInstance()
	P(("Tank's target: %s; %s; in %s."):format(db.enabled and "on" or "|cffff4040off|r", IsInRaid() and "raid" or IsInGroup() and "party" or "no group",
		inInstance and ("an instance (" .. Say(kind) .. ")") or "the open world"))
	local cv = GetCVar and GetCVar("nameplateShowEnemies")
	local n = 0
	for _ in pairs(onScreen) do n = n + 1 end
	P(("Enemy nameplates: %s; %d plates on screen."):format(cv == "1" and "on" or "|cffff4040off|r (V)", n))
	ReadTanks()
	if #tanks == 0 then
		P("|cffff4040No tank found.|r Someone needs the tank role (right-click their portrait > Set Role > Tank), or the raid's main tank.")
		local prefix, count = IsInRaid() and "raid" or "party", IsInRaid() and 40 or 4
		for i = 1, count do
			local u = prefix .. i
			if R(UnitExists(u)) then P(("  %s: %s, role %s"):format(u, Say(UnitName(u)), Say(UnitGroupRolesAssigned and UnitGroupRolesAssigned(u)))) end
		end
		return
	end
	for _, tank in ipairs(tanks) do
		local t = tank .. "target"
		P(("Tank %s (%s): target exists %s, name %s, enemy %s, dead %s, GUID %s."):format(tank, Say(UnitName(tank)), Say(UnitExists(t)),
			Say(UnitName(t)), Say(UnitCanAttack("player", t)), Say(UnitIsDead(t)), A.IsSecret(UnitGUID(t)) and "|cffff8040secret|r" or (UnitGUID(t) and "readable" or "nil")))
		local ok, plate = pcall(TargetPlate, tank)
		local how = ok and plate and TT.howFound[tank]
		P(("  its nameplate: %s"):format(how and ("found (" .. ({ token = "by unit", guid = "by GUID", same = "by comparing plates" })[how] .. ")")
			or ok and "|cffff4040not found|r (out of nameplate range, or the game won't say)" or ("|cffff4040error|r " .. tostring(plate))))
		local okL, on = pcall(OnIt, tank, ok and plate or nil)
		P(("  your target is it: %s"):format(okL and tostring(on) or ("error " .. tostring(on))))
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
	-- (2026-11-11) the outline's default went from blue to purple: a colour still at the old default
	-- moves over, once; one picked by hand stays
	local c = db.color
	if not db.purpled and type(c) == "table" and c[1] == OLD_BLUE[1] and c[2] == OLD_BLUE[2] and c[3] == OLD_BLUE[3] then
		db.color = { TT.PURPLE[1], TT.PURPLE[2], TT.PURPLE[3] }
	end
	db.purpled = true
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
