-- Ported from Plus Everything (same author) for Azeroth Almanac's quality-of-life helpers.
-- Threat monitor: a threat meter for your target, warnings before you pull aggro (or, for a tank,
-- when you lose it) and a threat edge on enemy nameplates. Works in a group, and solo when you
-- have a pet. Settings > Group Settings.
-- Uses the game's own threat functions (UnitDetailedThreatSituation / UnitThreatSituation), never
-- the combat log, and reads every value through ns.Readable.

local _, A = ...
local ns = A.QoL
local TM = ns:NewModule("ThreatMonitor")

local TICK = 0.2
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local GOLD = { 1, 0.82, 0 }
local PET_COLOR = { 0.45, 0.75, 0.4 }
local ROW_H, METER_W = 16, 230
local SOUND_WARN, SOUND_AGGRO, SOUND_LOST = 3175, 8959, 8959

-- plate edge colors
local RED, ORANGE, YELLOW, GREEN = { 1, 0.15, 0.1 }, { 1, 0.55, 0.1 }, { 1, 0.9, 0.2 }, { 0.25, 0.9, 0.3 }

TM.tankModes = { { name = "Automatic", key = "auto" }, { name = "I'm the tank", key = "tank" }, { name = "I'm not the tank", key = "dps" } }

local db, meter, flash, ticker
local mobs = {}   -- mob GUID -> warning state
local tints = {}  -- nameplate -> edge frame
local preview

local R = function(v) return ns.Readable(v) end

---------------------------------------------------------------------------
-- Who's who
---------------------------------------------------------------------------

local function HasPet() return R(UnitExists("pet")) == true end

-- Threat matters in a group, or solo with a pet (switchable).
local function Active()
	if not db.enabled then return false end
	if IsInGroup() then return true end
	return db.solo and HasPet()
end

local function IsTank()
	if db.tankMode == "tank" then return true end
	if db.tankMode == "dps" then return false end
	if UnitGroupRolesAssigned and R(UnitGroupRolesAssigned("player")) == "TANK" then return true end
	local _, class = UnitClass("player")
	local form = GetShapeshiftFormID and R(GetShapeshiftFormID())
	if class == "WARRIOR" and form == 18 then return true end          -- Defensive Stance
	if class == "DRUID" and (form == 5 or form == 8) then return true end -- Bear / Dire Bear Form
	if class == "PALADIN" and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
		for _, id in ipairs({ 25780, 20925 }) do                          -- Righteous Fury
			if R(C_UnitAuras.GetPlayerAuraBySpellID(id)) then return true end
		end
	end
	return false
end

-- player, party / raid members and pets
local function GroupUnits()
	local list = {}
	if IsInRaid() then
		for i = 1, 40 do list[#list + 1] = "raid" .. i list[#list + 1] = "raidpet" .. i end
	else
		list[#list + 1] = "player"
		list[#list + 1] = "pet"
		if IsInGroup() then
			for i = 1, 4 do list[#list + 1] = "party" .. i list[#list + 1] = "partypet" .. i end
		end
	end
	return list
end

local function UnitColor(unit)
	if unit:find("pet") then return PET_COLOR end
	local _, class = UnitClass(unit)
	class = R(class)
	local c = class and ((CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
	return c and { c.r, c.g, c.b } or { 0.7, 0.7, 0.7 }
end

-- Everyone on the mob's threat list: { unit, name, pct, tanking, color, me }, highest first.
local function ThreatList(mob)
	local rows = {}
	for _, unit in ipairs(GroupUnits()) do
		if R(UnitExists(unit)) then
			local tanking, status, pct = UnitDetailedThreatSituation(unit, mob)
			tanking, status, pct = R(tanking), R(status), R(pct)
			if status then
				rows[#rows + 1] = { unit = unit, name = R(UnitName(unit)) or "?", pct = tanking and 100 or (pct or 0),
					tanking = tanking, color = UnitColor(unit), me = R(UnitIsUnit(unit, "player")) == true }
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.tanking ~= b.tanking then return a.tanking and true or false end
		return a.pct > b.pct
	end)
	return rows
end

---------------------------------------------------------------------------
-- The meter
---------------------------------------------------------------------------

local function SavePosition(self)
	self:StopMovingOrSizing()
	local point, _, relPoint, x, y = self:GetPoint()
	db.point = { point, relPoint, x, y }
end

local function Row(i)
	local row = meter.rows[i]
	if row then return row end
	row = CreateFrame("StatusBar", nil, meter)
	row:SetSize(METER_W - 16, ROW_H)
	row:SetPoint("TOPLEFT", 8, -26 - (i - 1) * (ROW_H + 2))
	row:SetStatusBarTexture(BAR_TEXTURE)
	row:SetMinMaxValues(0, 100)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetTexture(BAR_TEXTURE)
	row.bg:SetVertexColor(0.12, 0.12, 0.12, 0.8)
	row.role = row:CreateTexture(nil, "OVERLAY")
	row.role:SetSize(12, 12)
	row.role:SetPoint("LEFT", 2, 0)
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("roleicon-tiny-tank") then
		row.role:SetAtlas("roleicon-tiny-tank")
	else
		row.role:SetTexture("Interface\\Icons\\INV_Shield_06")
		row.role:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", 17, 0)
	row.name:SetPoint("RIGHT", -44, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.pct = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.pct:SetPoint("RIGHT", -4, 0)
	-- a gold edge on your own bar
	row.mine = CreateFrame("Frame", nil, row, "BackdropTemplate")
	row.mine:SetPoint("TOPLEFT", -1, 1)
	row.mine:SetPoint("BOTTOMRIGHT", 1, -1)
	row.mine:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
	row.mine:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.9)
	meter.rows[i] = row
	return row
end

local function BuildMeter()
	meter = CreateFrame("Frame", "AzerothAlmanacThreatMeter", UIParent, "BackdropTemplate")
	meter:SetSize(METER_W, 60)
	meter:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	meter:SetBackdropColor(0.04, 0.04, 0.06, 0.88)
	meter:SetBackdropBorderColor(0.75, 0.62, 0.35, 1)
	meter:SetFrameStrata("MEDIUM")
	meter:SetClampedToScreen(true)
	meter:SetMovable(true)
	meter:EnableMouse(true)
	meter:RegisterForDrag("LeftButton")
	meter:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
	meter:SetScript("OnDragStop", SavePosition)
	if db.point then
		meter:SetPoint(db.point[1], UIParent, db.point[2], db.point[3], db.point[4])
	else
		meter:SetPoint("RIGHT", UIParent, "RIGHT", -260, -60)
	end
	meter.title = meter:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	meter.title:SetPoint("TOPLEFT", 9, -8)
	meter.title:SetPoint("RIGHT", -60, 0)
	meter.title:SetJustifyH("LEFT")
	meter.title:SetWordWrap(false)
	meter.mine = meter:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	meter.mine:SetPoint("TOPRIGHT", -9, -6)
	meter.rows = {}
	meter:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Threat")
		GameTooltip:AddLine("Threat on your target, as a share of what it takes to pull aggro. 100% pulls it.", 1, 1, 1, true)
		GameTooltip:AddLine(db.locked and "Locked (unlock in /aa > Group Settings)" or "Drag to move", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	meter:SetScript("OnLeave", GameTooltip_Hide)
	meter:Hide()
end

local function DrawMeter(title, rows)
	if not meter then BuildMeter() end
	meter.title:SetText(title or "")
	local n = math.min(#rows, db.rows or 6)
	local myPct
	for i = 1, n do
		local r, row = rows[i], Row(i)
		row:SetValue(math.min(100, r.pct))
		row:SetStatusBarColor(r.color[1], r.color[2], r.color[3], r.me and 1 or 0.75)
		row.name:SetText(r.name)
		row.pct:SetText(("%d%%"):format(math.floor(r.pct + 0.5)))
		row.role:SetShown(r.tanking and true or false)
		row.mine:SetShown(r.me and true or false)
		row:Show()
	end
	for _, r in ipairs(rows) do if r.me then myPct = r.pct end end
	for i = n + 1, #meter.rows do meter.rows[i]:Hide() end
	if myPct then
		local c = myPct >= (db.aggroAt or 100) and RED or myPct >= (db.warnAt or 70) and YELLOW or { 1, 1, 1 }
		meter.mine:SetText(("%d%%"):format(math.floor(myPct + 0.5)))
		meter.mine:SetTextColor(c[1], c[2], c[3])
	else
		meter.mine:SetText("")
	end
	meter:SetHeight(32 + math.max(1, n) * (ROW_H + 2))
	meter:SetAlpha(1)
	meter.fadeAt = nil
	meter:Show()
end

---------------------------------------------------------------------------
-- Warnings
---------------------------------------------------------------------------

local function Flash(color)
	if not flash then
		flash = CreateFrame("Frame", nil, UIParent)
		flash:SetAllPoints()
		flash:SetFrameStrata("BACKGROUND")
		flash.tex = flash:CreateTexture(nil, "BACKGROUND")
		flash.tex:SetAllPoints()
		flash.tex:SetTexture("Interface\\FullScreenTextures\\LowHealth")
		flash.tex:SetBlendMode("ADD")
		flash:SetScript("OnUpdate", function(self, elapsed)
			self.t = self.t + elapsed
			local p = self.t / 0.9
			if p >= 1 then self:Hide() return end
			self:SetAlpha(math.sin(p * math.pi) * 0.9)
		end)
	end
	flash.tex:SetVertexColor(color[1], color[2], color[3])
	flash.t = 0
	flash:SetAlpha(0)
	flash:Show()
end

local function Alert(text, color, sound, big)
	if not db.warn then return end
	if RaidNotice_AddMessage and RaidWarningFrame then
		RaidNotice_AddMessage(RaidWarningFrame, text, { r = color[1], g = color[2], b = color[3] })
	else
		ns.Print(text)
	end
	if db.sound and sound then PlaySound(sound, "Master") end
	if db.flash and big then Flash(color) end
end

local function CheckWarnings(mob, rows, mobName)
	local guid = R(UnitGUID(mob))
	if not guid then return end
	local s = mobs[guid]
	if not s then
		s = {}
		mobs[guid] = s
	end
	s.seen = GetTime()
	local me, tank
	for _, r in ipairs(rows) do
		if r.me then me = r end
		if r.tanking then tank = r end
	end
	if not me then return end
	if IsTank() then
		if me.tanking then
			s.had = true
		elseif s.had then
			s.had = false
			Alert(("Lost aggro on %s%s!"):format(mobName, tank and (" to " .. tank.name) or ""), RED, SOUND_LOST, true)
		end
		return
	end
	if tank and not tank.me then s.otherTanked = true end
	local warnAt, aggroAt = db.warnAt or 70, db.aggroAt or 100
	if (me.tanking and s.otherTanked) or (not me.tanking and me.pct >= aggroAt) then
		if not s.aggro then
			s.aggro = true
			Alert(me.tanking and ("You pulled aggro on %s!"):format(mobName) or ("Pulling aggro on %s!"):format(mobName), RED, SOUND_AGGRO, true)
		end
	elseif me.pct >= warnAt then
		if not s.warned then
			s.warned = true
			Alert(("Threat %d%% on %s"):format(math.floor(me.pct + 0.5), mobName), YELLOW, SOUND_WARN, false)
		end
	end
	-- ready to warn again once you've backed off
	if not me.tanking and me.pct < warnAt - 15 then s.warned, s.aggro = nil, nil end
end

---------------------------------------------------------------------------
-- Nameplate edges
---------------------------------------------------------------------------

local function Edge(plate)
	local e = tints[plate]
	if e then return e end
	e = CreateFrame("Frame", nil, plate, "BackdropTemplate")
	e:SetBackdrop({ edgeFile = WHITE, edgeSize = 2 })
	e.glow = e:CreateTexture(nil, "BACKGROUND")
	e.glow:SetTexture("Interface\\Buttons\\WHITE8X8")
	e.glow:SetPoint("TOPLEFT", -3, 3)
	e.glow:SetPoint("BOTTOMRIGHT", 3, -3)
	tints[plate] = e
	return e
end

local function PlateColor(unit, tank)
	if not (R(UnitCanAttack("player", unit)) and R(UnitAffectingCombat(unit))) then return nil end
	local status = R(UnitThreatSituation("player", unit))
	if tank then
		if status == 3 then return GREEN end
		if status == 2 then return YELLOW end
		return RED -- a loose mob
	end
	if status == 3 then return RED end
	if status == 2 then return ORANGE end
	if status == 1 then return YELLOW end
	return nil
end

local function UpdatePlates(active)
	local plates = C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}
	local seen = {}
	if active and db.plates then
		local tank = IsTank()
		for _, plate in ipairs(plates) do
			local frame = plate.UnitFrame
			local unit = plate.namePlateUnitToken or (frame and frame.unit)
			local color = unit and PlateColor(unit, tank)
			local bar = frame and (frame.healthBar or frame.HealthBarsContainer)
			if color and bar then
				local e = Edge(plate)
				-- the plate's unit frame is pooled: anchor to whichever one the plate has now
				e:ClearAllPoints()
				e:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 2)
				e:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 2, -2)
				e:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
				e:SetBackdropBorderColor(color[1], color[2], color[3], 1)
				e.glow:SetVertexColor(color[1], color[2], color[3], 0.25)
				e:Show()
				seen[plate] = true
			end
		end
	end
	for plate, e in pairs(tints) do
		if not seen[plate] then e:Hide() end
	end
end

---------------------------------------------------------------------------
-- Ticking
---------------------------------------------------------------------------

local function Tick()
	if preview then return end
	local active = Active()
	UpdatePlates(active)
	local mob = "target"
	local ok = active and R(UnitExists(mob)) and R(UnitCanAttack("player", mob)) and not R(UnitIsDead(mob))
	local rows = ok and ThreatList(mob) or {}
	if #rows > 0 then
		local name = R(UnitName(mob)) or ""
		if db.meter then DrawMeter(name, rows) end
		CheckWarnings(mob, rows, name)
	elseif meter and meter:IsShown() and not meter.fadeAt then
		meter.fadeAt = GetTime() + (R(UnitAffectingCombat("player")) and 4 or 1.5)
	end
	if meter and meter.fadeAt and GetTime() > meter.fadeAt then
		local a = meter:GetAlpha() - 0.25
		if a <= 0 then meter:Hide() meter.fadeAt = nil else meter:SetAlpha(a) end
	end
	-- forget mobs from long ago
	local now = GetTime()
	for guid, s in pairs(mobs) do if now - (s.seen or 0) > 120 then mobs[guid] = nil end end
end

local function StartTicker()
	if ticker or not db.enabled then return end
	ticker = C_Timer.NewTicker(TICK, Tick)
end

local function StopTicker()
	if ticker then ticker:Cancel() ticker = nil end
	-- out of combat: the meter and the plate edges go a few seconds later
	C_Timer.After(3, function()
		if ticker or preview then return end
		if meter then meter:Hide() end
		UpdatePlates(false)
	end)
end

---------------------------------------------------------------------------
-- Module API
---------------------------------------------------------------------------

function TM:OnInitialize(saved)
	db = saved.threat
end

function TM:OnLogin()
	local events = CreateFrame("Frame")
	for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_THREAT_LIST_UPDATE", "PLAYER_TARGET_CHANGED" }) do
		pcall(events.RegisterEvent, events, e)
	end
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then StartTicker()
		elseif event == "PLAYER_REGEN_ENABLED" then StopTicker()
		elseif not ticker and db.enabled then
			-- threat can start before your own combat does (a pet or the tank pulling)
			if event == "UNIT_THREAT_LIST_UPDATE" then StartTicker() C_Timer.After(6, function()
				if ticker and not R(UnitAffectingCombat("player")) then StopTicker() end
			end) end
		end
	end)
	if R(UnitAffectingCombat("player")) then StartTicker() end
end

function TM:Refresh()
	if not db.enabled then
		StopTicker()
		if meter then meter:Hide() end
		UpdatePlates(false)
		return
	end
	if R(UnitAffectingCombat("player")) then StartTicker() end
	if meter and not db.meter then meter:Hide() end
end

function TM:ResetPosition()
	db.point = nil
	if meter then
		meter:ClearAllPoints()
		meter:SetPoint("RIGHT", UIParent, "RIGHT", -260, -60)
	end
end

-- A sample of the meter and the warnings (Settings button and /aa threat).
function TM:Preview()
	preview = true
	local _, class = UnitClass("player")
	local me = R(UnitName("player")) or "You"
	local function C(c) local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[c] return cc and { cc.r, cc.g, cc.b } or { 0.7, 0.7, 0.7 } end
	DrawMeter("Defias Pillager (preview)", {
		{ name = "Tankyboi", pct = 100, tanking = true, color = C("WARRIOR") },
		{ name = me, pct = 82, color = C(class), me = true },
		{ name = "Pewpew", pct = 64, color = C("MAGE") },
		{ name = "Stabs", pct = 41, color = C("ROGUE") },
		{ name = "Wolf", pct = 12, color = PET_COLOR },
	})
	Alert(("Threat %d%% on %s"):format(82, "Defias Pillager"), YELLOW, SOUND_WARN, false)
	C_Timer.After(1.5, function() Alert("Pulling aggro on Defias Pillager!", RED, SOUND_AGGRO, true) end)
	C_Timer.After(8, function()
		preview = nil
		if meter and not ticker then meter:Hide() end
	end)
end
