-- (2026-11-11) Who the other healers are on: in a group with another healer, the group member each
-- of them has selected, and the one they're casting a heal on, is marked on that member's unit frame
-- (yours, the party frames, the raid frames). A backup healer sees at a glance who is already being
-- looked after and picks someone else, so two heals don't land on the same person.
--
--   Selected: a small badge on the frame's top edge, the healer role cross and the healer's name.
--   Casting: the badge lights up and a soft green glow goes round the frame for as long as the heal
--   is on its way.
--
-- What they're casting on is read from the game's incoming heals, per healer
-- (UnitGetIncomingHeals(member, healer)), so a heal cast by mouseover, a click on a frame or a
-- macro is caught without the healer targeting anyone. Where the game won't say (no such value, or
-- a secret one in combat), a heal being cast while a group member is selected counts as cast on them.
--
-- Who counts as a healer: someone in the healer role; with no role set, a priest, druid, paladin or
-- shaman. Like the tank's target (TankTarget.lua): in combat everything is read every POLL seconds,
-- out of combat the game's events alone do it. Our own frames only: nothing of the game's unit
-- frames is changed (they're protected), and the marks don't take the mouse.

local _, A = ...
local ns = A.QoL
local HT = ns:NewModule("HealerTarget")

local POLL = 0.25
HT.POLL = POLL
local ROLE_ATLAS = "roleicon-tiny-healer"
local ROLE_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local GLOW_TEXTURE = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"
HT.GREEN = { 0.1, 1, 0.35 }
local PULSE, LOW, HIGH = 1.0, 0.55, 1.0
local SELECTED_ALPHA = 0.75 -- the badge, when they've only selected the member
local HEAL_CLASSES = { PRIEST = true, DRUID = true, PALADIN = true, SHAMAN = true }

local db
local R = function(v) return ns.Readable(v) end
local healers = {}  -- unit tokens of the other healers in the group
local members = {}  -- unit tokens of everyone who can be healed (you first)
local marks = {}    -- member token -> its mark frame
local ticker

local function HasAtlas(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

---------------------------------------------------------------------------
-- Who the healers are
---------------------------------------------------------------------------

function HT.IsHealer(token)
	local role = UnitGroupRolesAssigned and R(UnitGroupRolesAssigned(token))
	if role == "HEALER" then return true end
	if role == "TANK" or role == "DAMAGER" then return false end
	local _, class = UnitClass(token)
	return HEAL_CLASSES[R(class) or ""] == true
end

local function ReadGroup()
	wipe(healers)
	wipe(members)
	if not (db and db.enabled) or not IsInGroup() then return end
	members[1] = "player"
	local raid = IsInRaid()
	local prefix, count = raid and "raid" or "party", raid and 40 or 4
	for i = 1, count do
		local token = prefix .. i
		if R(UnitExists(token)) and not R(UnitIsUnit(token, "player")) then
			members[#members + 1] = token
			if HT.IsHealer(token) then healers[#healers + 1] = token end
		end
	end
end
HT.Healers = function() return healers end

---------------------------------------------------------------------------
-- What each healer is on
---------------------------------------------------------------------------

local function Same(a, b)
	local ok, same = pcall(UnitIsUnit, a, b)
	return ok and R(same) == true
end

local function Casting(h)
	local name = UnitCastingInfo and UnitCastingInfo(h)
	if name == nil and UnitChannelInfo then name = UnitChannelInfo(h) end
	return name ~= nil -- (a secret name still means a cast)
end

-- the heal healer h has on its way to member m: a number, or nil when the game doesn't say
local function Incoming(m, h)
	if type(UnitGetIncomingHeals) ~= "function" then return nil end
	local ok, v = pcall(UnitGetIncomingHeals, m, h)
	v = ok and R(v) or nil
	return type(v) == "number" and v or nil
end

-- member token -> { { healer = token, casting = bool }, ... }, casting first
function HT:Read()
	local on = {}
	local function Add(m, h, casting)
		local list = on[m] or {}
		on[m] = list
		for _, x in ipairs(list) do
			if x.healer == h then x.casting = x.casting or casting return end
		end
		list[#list + 1] = { healer = h, casting = casting }
	end
	for _, h in ipairs(healers) do
		if R(UnitIsConnected(h)) and not R(UnitIsDeadOrGhost(h)) then
			local told, castOn = false, false
			for _, m in ipairs(members) do
				if m ~= h then
					local inc = Incoming(m, h)
					if inc ~= nil then told = true end
					if inc and inc > 0 then Add(m, h, true) castOn = true end
				end
			end
			local target = h .. "target"
			if R(UnitExists(target)) and not R(UnitCanAttack(h, target)) then
				for _, m in ipairs(members) do
					if m ~= h and Same(target, m) then
						-- the game can't say where heals are going: a cast while someone's selected is on them
						local casting = not told and not castOn and Casting(h)
						if casting or db.selected ~= false then Add(m, h, casting) end
						break
					end
				end
			end
		end
	end
	for _, list in pairs(on) do
		table.sort(list, function(a, b)
			if a.casting ~= b.casting then return a.casting end
			return a.healer < b.healer
		end)
	end
	return on
end

---------------------------------------------------------------------------
-- The mark on a member's frame
---------------------------------------------------------------------------

local function FrameFor(token)
	local HA = ns.HealAssist
	local f = HA and HA.FrameFor and HA.FrameFor(token)
	if f then return f end
	if token == "player" then return PlayerFrame end
end
HT.FrameFor = FrameFor

-- the picture of a portrait frame (the party and player frames are bigger boxes than their art)
local function ArtOf(f)
	if f == PlayerFrame then
		local c = PlayerFrame.PlayerFrameContainer
		return c and c.FrameTexture or f
	end
	return f.Texture or (f.PartyMemberOverlay and f.PartyMemberOverlay.Texture) or f
end

local function Mark(token)
	local m = marks[token]
	if m then return m end
	m = CreateFrame("Frame", nil, UIParent)
	m:EnableMouse(false)
	-- the glow: our own frame behind the unit frame, a soft green halo round its picture
	m.glow = CreateFrame("Frame", nil, UIParent)
	m.glow:EnableMouse(false)
	m.glow.tex = m.glow:CreateTexture(nil, "BACKGROUND")
	m.glow.tex:SetAllPoints()
	m.glow.tex:SetTexture(GLOW_TEXTURE)
	m.glow.tex:SetBlendMode("ADD")
	m.glow.tex:SetVertexColor(HT.GREEN[1], HT.GREEN[2], HT.GREEN[3])
	m.glow:SetScript("OnUpdate", function(self)
		local k = 0.5 + 0.5 * math.sin(GetTime() * 2 * math.pi / PULSE)
		self.tex:SetAlpha(LOW + (HIGH - LOW) * k)
	end)
	m.glow:Hide()
	-- the badge: a dark strip on the frame's top edge, the healer cross and the healer's name
	m:SetSize(60, 14)
	m.back = m:CreateTexture(nil, "BACKGROUND")
	m.back:SetAllPoints()
	m.back:SetColorTexture(0, 0, 0, 0.65)
	m.icon = m:CreateTexture(nil, "ARTWORK")
	m.icon:SetSize(12, 12)
	m.icon:SetPoint("LEFT", 2, 0)
	if HasAtlas(ROLE_ATLAS) then
		m.icon:SetAtlas(ROLE_ATLAS)
	else
		m.icon:SetTexture(ROLE_TEXTURE)
		m.icon:SetTexCoord(20 / 64, 39 / 64, 1 / 64, 20 / 64)
	end
	m.text = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	m.text:SetPoint("LEFT", m.icon, "RIGHT", 2, 0)
	m.text:SetJustifyH("LEFT")
	m:Hide()
	marks[token] = m
	return m
end
HT.MarkOf = function(token) return marks[token] end

local function Place(m, frame)
	if m.frame == frame then return end
	m.frame = frame
	local art = ArtOf(frame)
	local okS, strata = pcall(frame.GetFrameStrata, frame)
	local okL, level = pcall(frame.GetFrameLevel, frame)
	strata = okS and type(strata) == "string" and strata or "LOW"
	if strata == "BACKGROUND" then strata = "LOW" end
	level = okL and type(level) == "number" and level or 1
	m:SetFrameStrata(strata)
	m:SetFrameLevel(math.min(9000, level + 15))
	m:ClearAllPoints()
	m:SetPoint("BOTTOMRIGHT", art, "TOPRIGHT", -6, -7)
	m.glow:SetFrameStrata(strata)
	m.glow:SetFrameLevel(math.max(0, level - 1))
	m.glow:ClearAllPoints()
	m.glow:SetPoint("TOPLEFT", art, "TOPLEFT", -14, 12)
	m.glow:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", 14, -12)
end

local function NameOf(h)
	local name = UnitName(h)
	local _, class = UnitClass(h)
	class = R(class)
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	return name, c
end

local function Show(token, list)
	local frame = FrameFor(token)
	if not frame then return false end
	local m = Mark(token)
	Place(m, frame)
	local casting = list[1].casting
	-- the names: the healer's own (in class colour), "+1" for each more
	if db.names ~= false then
		local name, c = NameOf(list[1].healer)
		pcall(m.text.SetText, m.text, name or "")
		if c then m.text:SetTextColor(c.r, c.g, c.b) else m.text:SetTextColor(1, 1, 1) end
		if #list > 1 then
			local more = m.more or m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			m.more = more
			more:SetPoint("LEFT", m.text, "RIGHT", 2, 0)
			more:SetText("+" .. (#list - 1))
			more:Show()
		elseif m.more then
			m.more:Hide()
		end
		m.text:Show()
		local okW, w = pcall(m.text.GetStringWidth, m.text)
		w = okW and type(w) == "number" and w or 40
		local mw = (m.more and m.more:IsShown()) and (m.more:GetStringWidth() or 12) + 2 or 0
		m:SetWidth(math.min(110, math.max(16, 18 + w + mw + 4)))
	else
		m.text:Hide()
		if m.more then m.more:Hide() end
		m:SetWidth(16)
	end
	m:SetAlpha(casting and 1 or SELECTED_ALPHA)
	m:Show()
	m.glow:SetShown(casting and db.glow ~= false or false)
	m.casting = casting
	return true
end

local function Hide(m)
	m:Hide()
	m.glow:Hide()
	m.casting = nil
end

function HT:Update()
	local on = (db and db.enabled and #healers > 0) and self:Read() or {}
	local shown = {}
	for token, list in pairs(on) do
		if Show(token, list) then shown[token] = true end
	end
	for token, m in pairs(marks) do
		if not shown[token] then Hide(m) end
	end
	HT.on = on
end

local function Tick() HT:Update() end

local function StartPolling()
	if ticker or not (db and db.enabled) or #healers == 0 then return end
	ticker = C_Timer.NewTicker(POLL, Tick)
end

local function StopPolling()
	if ticker then ticker:Cancel() ticker = nil end
end
HT.Polling = function() return ticker ~= nil end

---------------------------------------------------------------------------
-- Settings and start-up
---------------------------------------------------------------------------

-- after a setting changed (Settings > Healer Assist > Other healers' targets)
function HT:Refresh()
	ReadGroup()
	-- frames can have moved: place every mark again
	for _, m in pairs(marks) do m.frame = nil end
	if InCombatLockdown() and #healers > 0 and db.enabled then StartPolling() else StopPolling() end
	self:Update()
end

-- a test: a member of yours marked as healed by "Healer" for 10 seconds (Settings button)
function HT:Preview()
	local token = members[2] or "player"
	local frame = FrameFor(token)
	if not frame then return end
	local m = Mark(token)
	Place(m, frame)
	m.text:SetText(UnitName("player") or "Healer")
	m.text:SetTextColor(1, 1, 1)
	m.text:Show()
	m:SetWidth(90)
	m:SetAlpha(1)
	m:Show()
	m.glow:Show()
	C_Timer.After(10, function() HT:Update() end)
end

function HT:OnInitialize(saved)
	db = saved.healerTarget
end

local UNIT_EVENTS = {
	UNIT_TARGET = true, UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_FAILED = true,
	UNIT_SPELLCAST_INTERRUPTED = true, UNIT_SPELLCAST_SUCCEEDED = true, UNIT_SPELLCAST_CHANNEL_START = true,
	UNIT_SPELLCAST_CHANNEL_STOP = true, UNIT_HEAL_PREDICTION = true,
}

function HT:OnLogin()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_ENTERING_WORLD",
		"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_CONNECTION" }) do
		events:RegisterEvent(event)
	end
	for event in pairs(UNIT_EVENTS) do pcall(events.RegisterEvent, events, event) end
	events:SetScript("OnEvent", function(_, event, unit)
		if UNIT_EVENTS[event] then
			-- only the group's own units (these fire for every nameplate too); in combat the poll has it
			if ticker or #healers == 0 or not unit then return end
			local ours = false
			for _, t in ipairs(members) do if t == unit then ours = true break end end
			if not ours then return end
		end
		if event == "PLAYER_REGEN_DISABLED" then
			StartPolling()
		elseif event == "PLAYER_REGEN_ENABLED" then
			StopPolling()
			-- (the game's frames may have been rearranged in combat)
			for _, m in pairs(marks) do m.frame = nil end
		elseif not UNIT_EVENTS[event] then
			ReadGroup()
			for _, m in pairs(marks) do m.frame = nil end
			if InCombatLockdown() then StartPolling() end
			if #healers == 0 then StopPolling() end
		end
		if #healers > 0 or next(marks) then HT:Update() end
	end)
	ReadGroup()
	if InCombatLockdown() then StartPolling() end
	HT:Update()
end
