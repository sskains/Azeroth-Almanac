-- (1.0.1) How far away a mob is, under its nameplate.
--
-- The game will not tell an addon the distance to a unit it is not grouped with. UnitPosition
-- answers for you and your party only, UnitDistanceSquared returns "not measured" for anything
-- else, and on this client ClosestUnitPosition - which takes a creature id and documents itself as
-- returning a distance - answers for nothing we could find. Nameplate scale is no help either: it
-- reads the same at melee range as at forty yards here.
--
-- What the game will answer, any number of times, is "is this unit within N yards?", through spell
-- ranges, item ranges and the interact-distance checks. LibRangeCheck-3.0 collects every such
-- question this character can ask and walks them into a bracket:
--
--     local minRange, maxRange = rc:GetRange(unit)   -- "between min and max yards"
--
-- which steps in roughly 5 yard jumps and only when polled. The smoothing below turns that into a
-- number that reads as live, and is the part worth understanding:
--
--   * When the bracket changes you have just crossed one of its edges, so the estimate snaps to
--     that edge - the far edge when closing, the near edge when backing off - and the speed is
--     measured from the time since the previous crossing.
--   * Between crossings the estimate free-runs at that speed, clamped inside the bracket. Pinned
--     at an edge early, the speed decays and it relaxes toward the middle, which is what standing
--     still looks like.
--
-- It can only ever be as wrong as the bracket is wide, and it corrects itself visibly when you
-- change direction. The approach is Shannon's, from the AggroRadar addon; LibRangeCheck is MIT, by
-- mitch0 and the WoWUIDev community (Licenses\LibRangeCheck-MIT.txt).

local _, A = ...
local ns = A.QoL
local ND = ns:NewModule("NameplateDistance")

local RC = LibStub and LibStub("LibRangeCheck-3.0", true)

local POLL = 0.25             -- seconds between real bracket samples, as the library expects
local DEFAULT_SPEED = 7       -- yd/s, about run speed: used until a crossing has been timed
local MIN_SPEED, MAX_SPEED = 1.5, 14
local FAR = math.huge

local texts, track = {}, {}   -- [unit] = fontstring, [unit] = estimate state
local pool = {}

local function Settings()
	local s = ns.db and ns.db.unitFrames
	return s or {}
end
ND.Settings = Settings

local function Mid(lo, hi)
	if hi == FAR then return lo end
	return (lo + hi) / 2
end

local function Clamp(x, lo, hi)
	if x < lo then return lo end
	if x > hi then return hi end
	return x
end

---------------------------------------------------------------------------
-- The label under a plate
---------------------------------------------------------------------------

local function Acquire(plate)
	local fs = table.remove(pool)
	if not fs then
		fs = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	end
	fs:ClearAllPoints()
	fs:SetPoint("TOP", plate, "BOTTOM", 0, -2)
	fs:Show()
	return fs
end

local function Release(unit)
	local fs = texts[unit]
	if fs then
		fs:Hide()
		pool[#pool + 1] = fs
		texts[unit] = nil
	end
	track[unit] = nil
end
ND.Release = Release

function ND:ReleaseAll()
	for unit in pairs(texts) do Release(unit) end
end

local function Render(fs, yards, exact)
	local c = Settings().distanceColor
	fs:SetText(("%d yd"):format(math.floor(yards + 0.5)))
	if c then fs:SetTextColor(c[1], c[2], c[3]) else fs:SetTextColor(1, 0.82, 0.3) end
	fs:SetAlpha(exact and 1 or 0.85)
end

---------------------------------------------------------------------------
-- One sample of the real bracket, and the estimate that rides on it
---------------------------------------------------------------------------

local function Sample(unit, plate, minRange, maxRange)
	if not minRange then Release(unit) return end
	local hi = maxRange or FAR
	local now = GetTime()
	local s = track[unit]
	if not s then
		s = { lo = minRange, hi = hi, est = Mid(minRange, hi), v = 0, speed = DEFAULT_SPEED }
		track[unit] = s
	elseif s.lo ~= minRange or s.hi ~= hi then
		local dir = (Mid(minRange, hi) < Mid(s.lo, s.hi)) and -1 or 1
		-- just entered this bracket, so the truth is about at the edge we came in through
		local edge = (dir < 0) and (maxRange or minRange) or minRange
		if s.crossTime and s.crossDir == dir then
			local dt = now - s.crossTime
			if dt > 0.15 and dt < 4 then
				local measured = Clamp(math.abs(edge - s.crossEdge) / dt, MIN_SPEED, MAX_SPEED)
				s.speed = (s.speed + measured) / 2
			end
		end
		s.crossTime, s.crossEdge, s.crossDir = now, edge, dir
		-- a crossing is only noticed on the next sample, so on average half a sample has passed
		s.est = Clamp(edge + dir * s.speed * (POLL / 2), minRange, hi)
		s.v = dir * s.speed
		s.lo, s.hi = minRange, hi
	end
	local fs = texts[unit]
	if not fs then
		fs = Acquire(plate)
		texts[unit] = fs
	end
	fs:ClearAllPoints()
	fs:SetPoint("TOP", plate, "BOTTOM", 0, -2)
	Render(fs, Settings().distanceSmooth ~= false and s.est or Mid(s.lo, s.hi))
end

---------------------------------------------------------------------------
-- Driving it
---------------------------------------------------------------------------

local function Wanted(unit)
	local s = Settings()
	if not s.distance or not RC then return false end
	if not UnitExists(unit) or UnitIsDead(unit) then return false end
	if s.distanceWho == "target" then return UnitIsUnit(unit, "target") end
	if s.distanceWho == "enemies" then return UnitCanAttack("player", unit) end
	return true
end

local driver = CreateFrame("Frame")
local since = 0

driver:SetScript("OnUpdate", function(_, elapsed)
	if not RC then return end
	-- between samples the estimate free-runs; the bracket itself is only asked for every POLL
	for unit, fs in pairs(texts) do
		local s = track[unit]
		if s then
			local est = s.est + s.v * elapsed
			local pinned = false
			if est < s.lo then est, pinned = s.lo, true
			elseif est > s.hi then est, pinned = s.hi, true end
			if pinned then
				-- the speed guess was high, or they have slowed: let it bleed off
				s.v = s.v * (0.5 ^ (elapsed / POLL))
			end
			if math.abs(s.v) < 0.5 then
				est = est + (Mid(s.lo, s.hi) - est) * math.min(1, elapsed)
			end
			s.est = est
			if Settings().distanceSmooth ~= false then Render(fs, est) end
		end
	end

	since = since + elapsed
	if since < POLL then return end
	since = 0
	for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if unit then
			if Wanted(unit) then
				local minR, maxR = RC:GetRange(unit)
				Sample(unit, plate, minR, maxR)
			else
				Release(unit)
			end
		end
	end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event, unit)
	if event == "NAME_PLATE_UNIT_REMOVED" and unit then Release(unit) else ND:ReleaseAll() end
end)

function ND:Refresh()
	if not Settings().distance then self:ReleaseAll() end
end

-- (dev) what the library makes of a unit right now, bracket and all
function ND:Debug(unit)
	unit = (unit and unit ~= "" and unit) or "target"
	if not RC then ns.Print("nameplate distance: LibRangeCheck did not load") return end
	local minR, maxR = RC:GetRange(unit)
	ns.Print(("|cff9be36bdistance|r %s: %s - %s yd (checkers %s)")
		:format(tostring(UnitName(unit)), tostring(minR), tostring(maxR),
			tostring(RC.GetNumCheckers and RC:GetNumCheckers() or "?")))
end
