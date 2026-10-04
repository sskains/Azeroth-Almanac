-- Ported from Plus Everything (same author) for Azeroth Almanac's quality-of-life helpers.
-- Party plates: your group members' nameplates stand out. Their name (and health bar) in
-- their class color, or one color of your choice for everyone, with a small class emblem
-- beside the name and the leader's crown / group role. Settings > Group Settings.
-- Friendly nameplates inside dungeons and raids are locked to addons by the game, so this
-- works out in the world (C_NamePlate gives no plate for the locked ones).

local _, A = ...
local ns = A.QoL
local PP = ns:NewModule("PartyPlates")

local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local LEADER_ATLAS = "UI-HUD-UnitFrame-Player-Group-LeaderIcon"
local ROLE_ATLAS = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer", DAMAGER = "roleicon-tiny-dps" }
local BEACON_ART = { { "npe_arrowdown", "npe_arrowdownglow" }, { "minimap-positionarrowdown" }, { "poi-door-arrow-down" } }

-- The two looks (Settings > Group Settings has a button for each; every part stays adjustable).
PP.presets = {
	subtle = { healthBar = true, emblem = true, roles = true, beacon = false, nameScale = 100 },
	bold = { healthBar = true, emblem = true, roles = true, beacon = true, nameScale = 125 },
}

local db
local decorated = {}  -- plate -> { label, nameHidden = font string, frame = UnitFrame, bar = health bar, r, g, b }
local byFrame = {}    -- UnitFrame -> the same entry, for the health colour hook
local group = {}      -- GUID -> unit token (party1, raid3, ...)

local function Readable(v) return ns.Readable(v) end

local function HasAtlas(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- Who's in your group, by GUID (nameplate tokens can't be compared to party tokens directly).
local function ReadGroup()
	wipe(group)
	local prefix, count
	if IsInRaid() then
		if not db.raid then return end
		prefix, count = "raid", 40
	elseif IsInGroup() then
		prefix, count = "party", 4
	else
		return
	end
	for i = 1, count do
		local unit = prefix .. i
		local guid = Readable(UnitGUID(unit))
		if type(guid) == "string" and not (Readable(UnitIsUnit(unit, "player")) == true) then group[guid] = unit end
	end
end

local function ColorFor(unit)
	if db.colorMode == "custom" and db.color then return db.color[1], db.color[2], db.color[3] end
	local _, class = UnitClass(unit)
	class = Readable(class)
	local c = class and ((CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
	if c then return c.r, c.g, c.b end
	return 0.4, 0.8, 1
end

---------------------------------------------------------------------------
-- The label: emblem, name, crown / role
---------------------------------------------------------------------------

local function Label(plate)
	local entry = decorated[plate]
	if entry and entry.label then return entry.label end
	local label = CreateFrame("Frame", nil, plate)
	label:SetSize(1, 1)
	label:EnableMouse(false)
	label.name = label:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label.name:SetShadowOffset(1, -1)
	label.name:SetPoint("BOTTOM", label, "BOTTOM", 0, 0)
	label.baseFont = { label.name:GetFont() } -- before any resizing
	-- round class emblem left of the name, in a thin ring of the same colour
	label.ring = label:CreateTexture(nil, "ARTWORK")
	label.ring:SetTexture(CIRCLE)
	label.ring:SetSize(18, 18)
	label.ring:SetPoint("RIGHT", label.name, "LEFT", -3, 0)
	label.emblem = label:CreateTexture(nil, "OVERLAY")
	label.emblem:SetPoint("TOPLEFT", label.ring, "TOPLEFT", 1.5, -1.5)
	label.emblem:SetPoint("BOTTOMRIGHT", label.ring, "BOTTOMRIGHT", -1.5, 1.5)
	local mask = label:CreateMaskTexture()
	mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(label.emblem)
	label.emblem:AddMaskTexture(mask)
	label.crown = label:CreateTexture(nil, "OVERLAY")
	label.crown:SetSize(14, 14)
	label.crown:SetPoint("BOTTOM", label.ring, "TOP", 0, -3)
	label.role = label:CreateTexture(nil, "OVERLAY")
	label.role:SetSize(14, 14)
	label.role:SetPoint("LEFT", label.name, "RIGHT", 3, 0)

	-- Beacon: the game's big down arrow (the new-player guide's), tinted, gently bobbing over
	-- their head so you can spot them from far away.
	label.beacon = CreateFrame("Frame", nil, label)
	label.beacon:SetSize(26, 26)
	label.beacon:SetPoint("BOTTOM", label.name, "TOP", 0, 14)
	label.beacon.glow = label.beacon:CreateTexture(nil, "BACKGROUND")
	label.beacon.glow:SetPoint("CENTER")
	label.beacon.glow:SetSize(40, 40)
	label.beacon.glow:SetBlendMode("ADD")
	label.beacon.arrow = label.beacon:CreateTexture(nil, "ARTWORK")
	label.beacon.arrow:SetAllPoints()
	local art = false
	for _, pair in ipairs(BEACON_ART) do
		if HasAtlas(pair[1]) then
			label.beacon.arrow:SetAtlas(pair[1])
			if pair[2] and HasAtlas(pair[2]) then label.beacon.glow:SetAtlas(pair[2]) else label.beacon.glow:Hide() end
			art = true
			break
		end
	end
	label.beacon.hasArt = art
	local bob = label.beacon:CreateAnimationGroup()
	bob:SetLooping("BOUNCE")
	local move = bob:CreateAnimation("Translation")
	move:SetOffset(0, 6)
	move:SetDuration(0.7)
	move:SetSmoothing("IN_OUT")
	label.beacon:SetScript("OnShow", function() bob:Play() end)
	label.beacon:SetScript("OnHide", function() bob:Stop() end)
	label.beacon:Hide()
	return label
end

local function Undecorate(plate)
	local entry = decorated[plate]
	if not entry then return end
	if entry.label then entry.label:Hide() end
	-- the game's own name comes back (tracked by the font string: the UnitFrame is pooled)
	if entry.nameHidden then entry.nameHidden:SetAlpha(1) entry.nameHidden = nil end
	if entry.frame then byFrame[entry.frame] = nil end
	-- the health bar gets the game's colour back on its next update; ask for one now
	if entry.bar and entry.frame and entry.frame.unit and CompactUnitFrame_UpdateHealthColor then
		pcall(CompactUnitFrame_UpdateHealthColor, entry.frame)
	end
	entry.frame, entry.bar = nil, nil
end

local function Decorate(unit)
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then return end -- none for locked (dungeon/raid friendly) plates
	Undecorate(plate)
	if not db.enabled then return end
	local guid = Readable(UnitGUID(unit))
	if type(guid) ~= "string" or not group[guid] then return end
	local frame = plate.UnitFrame
	if not frame then return end

	local r, g, b = ColorFor(unit)
	local entry = decorated[plate] or {}
	decorated[plate] = entry
	entry.label = Label(plate)
	entry.frame, entry.r, entry.g, entry.b = frame, r, g, b
	byFrame[frame] = entry

	local label = entry.label
	local blizzName = frame.name
	local anchor = frame.HealthBarsContainer or frame.healthBar or frame
	label:ClearAllPoints()
	label:SetPoint("BOTTOM", anchor, "TOP", 0, 3)
	label:SetFrameLevel(plate:GetFrameLevel() + 5)
	-- Bigger names (the text only: resizing plates can be blocked in combat). The size is always
	-- worked out from the game's own name on the plate, which Azeroth Almanac never resizes; reading our
	-- label's size back would grow it again on every refresh (a font set with SetFont sticks,
	-- even after SetFontObject).
	local scale = (db.nameScale or 100) / 100
	local font, size, flags
	if blizzName and blizzName.GetFont then font, size, flags = blizzName:GetFont() end
	if not (font and size) then font, size, flags = label.baseFont[1], label.baseFont[2], label.baseFont[3] end
	if font and size then label.name:SetFont(font, size * scale, flags or "") end
	label.ring:SetSize(18 * scale, 18 * scale)
	label.name:SetText(Readable(GetUnitName(unit, false)) or Readable(UnitName(unit)) or "")
	label.name:SetTextColor(r, g, b)

	local _, class = UnitClass(unit)
	class = Readable(class)
	local showEmblem = db.emblem and class and ns.SetClassIcon(label.emblem, class)
	label.emblem:SetShown(showEmblem and true or false)
	label.ring:SetShown(showEmblem and true or false)
	label.ring:SetVertexColor(r, g, b)

	local token = group[guid]
	local leader = db.roles and Readable(UnitIsGroupLeader(token)) == true and HasAtlas(LEADER_ATLAS)
	if leader then label.crown:SetAtlas(LEADER_ATLAS) end
	label.crown:SetShown(leader and true or false)
	local role = db.roles and UnitGroupRolesAssigned and Readable(UnitGroupRolesAssigned(token))
	local roleAtlas = role and ROLE_ATLAS[role]
	if roleAtlas and HasAtlas(roleAtlas) then label.role:SetAtlas(roleAtlas) label.role:Show() else label.role:Hide() end
	local beacon = label.beacon
	if db.beacon and beacon.hasArt then
		beacon.arrow:SetDesaturated(true)
		beacon.arrow:SetVertexColor(r, g, b)
		beacon.glow:SetVertexColor(r, g, b, 0.8)
		-- above the crown when there is one
		beacon:ClearAllPoints()
		beacon:SetPoint("BOTTOM", label.name, "TOP", 0, leader and 18 or 6)
		beacon:Show()
	else
		beacon:Hide()
	end
	label:Show()

	if blizzName then
		blizzName:SetAlpha(0)
		entry.nameHidden = blizzName
	end
	if db.healthBar and frame.healthBar then
		entry.bar = frame.healthBar
		entry.bar:SetStatusBarColor(r, g, b)
	end
end

function PP:Refresh()
	if not db then return end
	ReadGroup()
	for plate in pairs(decorated) do Undecorate(plate) end
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
	for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
		local unit = plate.namePlateUnitToken or (plate.GetUnit and plate:GetUnit()) or (plate.UnitFrame and plate.UnitFrame.unit)
		if unit then pcall(Decorate, unit) end
	end
end

---------------------------------------------------------------------------
-- Module API
---------------------------------------------------------------------------

function PP:OnInitialize(saved)
	db = saved.partyPlates
end

function PP:OnLogin()
	-- The game repaints nameplate health bars now and then; repaint group members' after it.
	if CompactUnitFrame_UpdateHealthColor then
		hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(frame)
			local entry = byFrame[frame]
			if entry and entry.bar then entry.bar:SetStatusBarColor(entry.r, entry.g, entry.b) end
		end)
	end
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "GROUP_ROSTER_UPDATE",
		"PARTY_LEADER_CHANGED", "PLAYER_ROLES_ASSIGNED", "PLAYER_ENTERING_WORLD" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event, unit)
		if event == "NAME_PLATE_UNIT_ADDED" then
			-- a moment later, after the game has set the plate up
			C_Timer.After(0, function() pcall(Decorate, unit) end)
		elseif event == "NAME_PLATE_UNIT_REMOVED" then
			local plate = C_NamePlate.GetNamePlateForUnit(unit)
			if plate then Undecorate(plate) end
		else
			C_Timer.After(0.2, function() PP:Refresh() end)
		end
	end)
	PP:Refresh()
end
