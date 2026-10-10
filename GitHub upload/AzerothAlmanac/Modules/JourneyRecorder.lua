-- The Journey recorder (0.69.1; DESIGN section 74, "Recorder"): where each character walks, so the
-- Journal's Journey follows the real path instead of joining up discoveries.
--   A point every 5 seconds once you've moved about 15 yards (standing still or AFK adds nothing),
--   or at once when the map changes; time, map, x, y, and what moved you when it wasn't walking:
--     F  took off on a flight path      f  landed (the flight itself isn't recorded)
--     b  on a boat (Travel's ride)          z  on a zeppelin (#49: by the port the ride left from)
--     h  arrived by hearthstone
--     i  went into or out of a dungeon
--     d  died here                       g  running back as a ghost
--   Saved per character per day as one compact string: ns.db.trail[char][day] = "dt:map:x:y:k;..."
--   (dt seconds after midnight, x / y map percent to one place). About 3 KB an hour of walking.
--   Days older than a week are thinned once (every third plain point kept, every marked one kept).
--   Settings > General > "Record my journey" turns it off. Only your own characters; nothing shared.
--   JR:Points(from, char) -> { { t, m, x, y, c, k } } oldest first, for UI/Journey.lua.

local _, ns = ...
local JR = ns:NewModule("JourneyRecorder")

local TICK = 5
local MIN_YARDS = 15
local MIN_PERCENT = 0.4      -- (map percent, when the game won't give world positions)
local KEEP_FULL_DAYS = 7
local HEARTHSTONE = 8690

local last                   -- { m, x, y, wx, wy, t } the last point written
local nextKind               -- a mark waiting for the next point (h, i)
local wasTaxi, wasGhost = false, false

local function On() return ns.db and not (ns.db.settings and ns.db.settings.window and ns.db.settings.window.journey == false) end

local function DayKey(t) return date("%Y-%m-%d", t) end
local function DayStart(t)
	local d = date("*t", t)
	return time({ year = d.year, month = d.month, day = d.day, hour = 0 })
end

local function Store()
	ns.db.trail = ns.db.trail or {}
	local me = ns.CharKey()
	ns.db.trail[me] = ns.db.trail[me] or {}
	return ns.db.trail[me]
end

local function World()
	if not UnitPosition then return nil end
	local ok, y, x = pcall(UnitPosition, "player")
	y, x = ok and ns.Readable(y) or nil, ok and ns.Readable(x) or nil
	if type(x) == "number" and type(y) == "number" then return x, y end
end

local function Write(kind, force)
	local w = ns.Where()
	if not (w.map and w.x and w.y) then return end
	local now = time()
	local wx, wy = World()
	if last and not force and not kind and last.m == w.map then
		local far
		if wx and last.wx then far = ((wx - last.wx) ^ 2 + (wy - last.wy) ^ 2) >= MIN_YARDS * MIN_YARDS
		else far = math.abs(w.x - last.x) + math.abs(w.y - last.y) >= MIN_PERCENT end
		if not far then return end
	end
	kind = kind or nextKind
	nextKind = nil
	local day = DayKey(now)
	local s = Store()
	local entry = ("%d:%d:%.1f:%.1f%s;"):format(now - DayStart(now), w.map, w.x, w.y, kind and (":" .. kind) or "")
	s[day] = (s[day] or "") .. entry
	last = { m = w.map, x = w.x, y = w.y, wx = wx, wy = wy, t = now }
end

function JR:Tick()
	if not On() then return end
	local taxi = UnitOnTaxi and UnitOnTaxi("player") and true or false
	if taxi then
		if not wasTaxi then Write("F", true) end   -- take-off: where you left from
		wasTaxi = true
		return                                      -- (the flight itself isn't walked)
	end
	if wasTaxi then
		wasTaxi = false
		Write("f", true)                            -- landed
		return
	end
	local ghost = UnitIsGhost and UnitIsGhost("player") and true or false
	if ghost ~= wasGhost then wasGhost = ghost end
	local TR = ns.QoL and ns.QoL.Travel
	local riding = TR and TR.CurrentRide and TR:CurrentRide()
	local rideMark = riding and ((TR.RideKind and TR:RideKind() == "Zeppelin") and "z" or "b") or nil
	Write(rideMark or (ghost and "g") or nil)
end

-- a map change (a zone line, a dungeon, a hearth) gets a point at once
function JR:MapChanged()
	if not On() then return end
	local ok, inside = pcall(IsInInstance)
	inside = ok and ns.Readable(inside) or false
	local was = self.inside
	self.inside = inside and true or false
	if was ~= nil and was ~= self.inside then nextKind = "i" end
	C_Timer.After(1, function() pcall(Write, nil, true) end)
end

-- the points from a time on, for one character (nil: every character), oldest first
function JR:Points(from, char)
	local out = {}
	local trail = ns.db and ns.db.trail
	if not trail then return out end
	local fromDay = DayKey(math.max(from or 0, 0))
	for key, days in pairs(trail) do
		if not char or key == char then
			for day, s in pairs(days) do
				if from == 0 or day >= fromDay then
					local y, mo, d = day:match("^(%d+)-(%d+)-(%d+)$")
					local base = y and time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 0 }) or 0
					for dt, m, x, yy, k in s:gmatch("(%d+):(%d+):([%d%.]+):([%d%.]+):?(%a?);") do
						local t = base + tonumber(dt)
						if t >= (from or 0) then
							out[#out + 1] = { t = t, m = tonumber(m), x = tonumber(x), y = tonumber(yy), c = key, k = k ~= "" and k or nil, s = #out }
						end
					end
				end
			end
		end
	end
	-- (in time order; points in the same second keep the order they were written)
	table.sort(out, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.s < b.s end)
	return out
end

-- days older than a week: every third plain point, every marked one (once per day)
local function Thin()
	local trail = ns.db and ns.db.trail
	if not trail then return end
	local cutoff = DayKey(time() - KEEP_FULL_DAYS * 86400)
	ns.db.trailThinned = ns.db.trailThinned or {}
	local done = ns.db.trailThinned
	for key, days in pairs(trail) do
		for day, s in pairs(days) do
			local id = key .. "|" .. day
			if day < cutoff and not done[id] then
				local keep, i = {}, 0
				for e in s:gmatch("[^;]+") do
					i = i + 1
					if i % 3 == 1 or e:match(":%a$") then keep[#keep + 1] = e end
				end
				days[day] = #keep > 0 and (table.concat(keep, ";") .. ";") or nil
				done[id] = true
			end
		end
	end
end

function JR:OnLogin()
	last = nil
	pcall(Thin)
	C_Timer.NewTicker(TICK, function() local ok, err = pcall(JR.Tick, JR) if not ok then ns.Debug("journey: " .. tostring(err)) end end)
end

ns:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() pcall(JR.MapChanged, JR) end)
ns:RegisterEvent("PLAYER_ENTERING_WORLD", function() pcall(JR.MapChanged, JR) end)
ns:RegisterEvent("PLAYER_DEAD", function() if On() then pcall(Write, "d", true) end end)
ns:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
	if unit == "player" and ns.Readable(spellID) == HEARTHSTONE then nextKind = "h" end
end)
