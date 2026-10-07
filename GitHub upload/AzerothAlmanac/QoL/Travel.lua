-- Ported from Plus Everything (same author) for Azeroth Almanac's quality-of-life helpers.
-- Travel Timers
--   Flights: learns how long each flight path takes (from -> to) and shows a countdown bar
--   while flying, either under the minimap or as a free bar. Routes you haven't flown yet
--   get an estimate from the route's length on the map and your average flight speed.
--   Flight map: destination tooltips show the flight time.
--   Boats and zeppelins: schedules can't be read from the game, so they're learned by
--   riding. A ride is noticed when you move while standing still; each ride records a
--   departure time from that port and the trip time. With two departures from the same
--   port the cycle is known, and the dock panel shows when the next one leaves.
--   Sharing: flight times and departures are sent to other Azeroth Almanac users in your guild and
--   group with hidden addon messages, so one person riding a boat updates everyone.

local _, A = ...
local ns = A.QoL
local TR = ns:NewModule("Travel")

local PREFIX = "AZALM1"
local DEFAULT_SPEED = 30          -- yards per second before any flight has been timed
local MIN_FLIGHT, MAX_FLIGHT = 15, 3600
local SAMPLE_INTERVAL = 1         -- seconds between transport-detection samples
local TRANSPORT_SPEED = 2.5       -- yards/second of movement while standing still = on a transport
local RIDE_START_SAMPLES = 3      -- consecutive moving samples before a ride counts as started
local RIDE_STOP_SECONDS = 8       -- seconds without movement that end a ride
local MIN_RIDE, MAX_RIDE = 30, 15 * 60
local FIT_TOLERANCE = 30          -- seconds a new departure may be off the known cycle
local MAX_DEPARTURES = 12
local DOCK_RADIUS = 60            -- yards around a learned boarding spot that count as "on the dock"

-- Transport routes by port (subzone, or zone for the zeppelin towers). Used to list
-- routes on a dock before they've been learned; learned routes are added as ridden,
-- under whatever subzone names the game actually reports.
local ROUTES = {
	-- Classic
	{ "Menethil Harbor", "Theramore Isle", "Boat" },
	{ "Menethil Harbor", "Auberdine", "Boat" },
	{ "Auberdine", "Rut'theran Village", "Boat" },
	{ "Booty Bay", "Ratchet", "Boat" },
	{ "Durotar", "Tirisfal Glades", "Zeppelin" },
	{ "Durotar", "Grom'gol Base Camp", "Zeppelin" },
	{ "Tirisfal Glades", "Grom'gol Base Camp", "Zeppelin" },
	-- New in WoW Forever (names from pre-release announcements; a multi-stop boat is one leg per stop)
	{ "Stormwind Harbor", "Auberdine", "Boat" },
	{ "Menethil Harbor", "Southshore", "Boat" },
	{ "Southshore", "Auberdine", "Boat" },
	{ "Steamwheedle Port", "Powderfuse Port", "Boat" },
}

-- Subzone names the game reports at a dock -> the port name used above. Seen in game:
-- Auberdine's piers are "The Long Wash" and "Mist's Edge", Menethil's is "Baradin Bay".
-- More can be added in game with /aa dockname <port> (saved in db.portAliases).
local PORT_ALIASES = {
	["The Long Wash"] = "Auberdine",
	["Mist's Edge"] = "Auberdine",
	["Baradin Bay"] = "Menethil Harbor",
}

local db
local bar
local boatStatus -- { text, value, max } from the Boats module while riding a boat or zeppelin
local flight -- { from, to, planned, estimated, yards, start } while taking a flight
local ride   -- transport ride in progress

local function Clock(seconds)
	seconds = math.max(0, math.floor(seconds + 0.5))
	local h, m, s = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60
	if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
	return ("%d:%02d"):format(math.floor(seconds / 60), s)
end

local function RealmSchedules()
	local realm = GetRealmName() or "?"
	db.schedules[realm] = db.schedules[realm] or {}
	return db.schedules[realm]
end

---------------------------------------------------------------------------
-- Sharing
---------------------------------------------------------------------------

local function Send(message)
	if not db.share or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
	if IsInGuild() then C_ChatInfo.SendAddonMessage(PREFIX, message, "GUILD") end
	if IsInRaid() then
		C_ChatInfo.SendAddonMessage(PREFIX, message, "RAID")
	elseif IsInGroup() then
		C_ChatInfo.SendAddonMessage(PREFIX, message, "PARTY")
	end
end

local function CleanName(s)
	return type(s) == "string" and #s > 0 and #s <= 60 and not s:find("[|\n]") and s or nil
end

---------------------------------------------------------------------------
-- Flights
---------------------------------------------------------------------------

local function FlightKey(from, to) return from .. " > " .. to end

local function CurrentNodeName()
	for i = 1, NumTaxiNodes() do
		if TaxiNodeGetType(i) == "CURRENT" then return TaxiNodeName(i) end
	end
end

-- Width and height of a map in yards, from where its corners are in the world.
local mapYards = {}
local function MapYards(mapID)
	if mapYards[mapID] == nil then
		mapYards[mapID] = false
		local _, p0 = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
		local _, p1 = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 0))
		local _, p2 = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 1))
		if p0 and p1 and p2 then
			local x0, y0 = p0:GetXY()
			local x1, y1 = p1:GetXY()
			local x2, y2 = p2:GetXY()
			mapYards[mapID] = { math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2), math.sqrt((x2 - x0) ^ 2 + (y2 - y0) ^ 2) }
		end
	end
	local size = mapYards[mapID]
	if size then return size[1], size[2] end
end

-- Size of the continent map the flight map shows, in yards, to turn route length into distance.
local function ContinentYards()
	local mapID = C_Map.GetBestMapForUnit("player")
	local info = mapID and C_Map.GetMapInfo(mapID)
	while info and info.mapType and info.mapType > Enum.UIMapType.Continent and info.parentMapID and info.parentMapID ~= 0 do
		mapID = info.parentMapID
		info = C_Map.GetMapInfo(mapID)
	end
	if mapID then return MapYards(mapID) end
end

-- Length of the route to a flight map slot in yards, following its hops.
local function RouteYards(slot)
	local width, height = ContinentYards()
	local hops = GetNumRoutes and GetNumRoutes(slot) or 0
	if not width or hops == 0 then return end
	local total = 0
	for i = 1, hops do
		local dx = (TaxiGetDestX(slot, i) - TaxiGetSrcX(slot, i)) * width
		local dy = (TaxiGetDestY(slot, i) - TaxiGetSrcY(slot, i)) * height
		total = total + math.sqrt(dx * dx + dy * dy)
	end
	return total
end

local function Speed()
	if db.speed.seconds > 0 then return db.speed.yards / db.speed.seconds end
	return DEFAULT_SPEED
end

-- Flight time to a slot on the open flight map: seconds, whether it's an estimate.
function TR:FlightTime(slot)
	local from, to = CurrentNodeName(), TaxiNodeName(slot)
	local known = from and to and db.flights[FlightKey(from, to)]
	if known then return known.t, false end
	local yards = RouteYards(slot)
	if yards then return yards / Speed(), true end
end

local function LearnFlight(from, to, seconds, yards)
	local key = FlightKey(from, to)
	local entry = db.flights[key]
	if entry then
		entry.t = (entry.t * entry.n + seconds) / (entry.n + 1)
		entry.n = math.min(entry.n + 1, 20)
	else
		db.flights[key] = { t = seconds, n = 1 }
	end
	if yards and yards > 0 then
		db.speed.yards = db.speed.yards + yards
		db.speed.seconds = db.speed.seconds + seconds
	end
end

local function OnTakeTaxiNode(slot)
	local from, to = CurrentNodeName(), TaxiNodeName(slot)
	if not from or not to then return end
	local seconds, estimated = TR:FlightTime(slot)
	flight = { from = from, to = to, planned = seconds, estimated = estimated, yards = RouteYards(slot),
		mapID = C_Map.GetBestMapForUnit("player") }
	db.current = { from = from, to = to, planned = seconds, estimated = estimated }
end

local function AddFlightTooltip(tooltip, slot)
	if not db.mapTimes or TaxiNodeGetType(slot) ~= "REACHABLE" then return end
	local seconds, estimated = TR:FlightTime(slot)
	if not seconds then return end
	tooltip:AddLine(("Flight time: %s%s"):format(estimated and "~" or "", Clock(seconds)),
		estimated and 0.7 or 1, estimated and 0.7 or 0.82, estimated and 0.7 or 0)
	if estimated then tooltip:AddLine("Estimate; exact after your first flight on this route", 0.5, 0.5, 0.5) end
	tooltip:Show()
end

local function HookFlightMaps()
	if TaxiNodeOnButtonEnter and not TR.hookedTaxiFrame then
		TR.hookedTaxiFrame = true
		hooksecurefunc("TaxiNodeOnButtonEnter", function(button) AddFlightTooltip(GameTooltip, button:GetID()) end)
	end
	if FlightMap_FlightPathPinMixin and not TR.hookedFlightMap then
		TR.hookedFlightMap = true
		hooksecurefunc(FlightMap_FlightPathPinMixin, "OnMouseEnter", function(pin)
			if pin.taxiNodeData then AddFlightTooltip(GameTooltip, pin.taxiNodeData.slotIndex) end
		end)
	end
end

---------------------------------------------------------------------------
-- In-flight bar
---------------------------------------------------------------------------

local function PlaceBar()
	bar:ClearAllPoints()
	if db.barStyle == "minimap" then
		bar:SetPoint("TOP", MinimapCluster or Minimap, "BOTTOM", 0, -8)
		bar:SetMovable(false)
	else
		local p = db.barPoint
		if p then bar:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else bar:SetPoint("TOP", UIParent, "TOP", 0, -160) end
		bar:SetMovable(true)
	end
end

local function BuildBar()
	bar = CreateFrame("StatusBar", "AzerothAlmanacFlightBar", UIParent)
	bar:SetSize(220, 18)
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar:SetStatusBarColor(0.25, 0.55, 1)
	bar:SetClampedToScreen(true)
	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.45)
	-- the bar sits in the helpers' see-through mesh box with its thin gold border
	bar.box = CreateFrame("Frame", nil, bar, "BackdropTemplate")
	bar.box:SetPoint("TOPLEFT", -6, 6)
	bar.box:SetPoint("BOTTOMRIGHT", 6, -6)
	bar.box:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
	ns.StylePanel(bar.box, db.panelAlpha or 0.8)
	bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.text:SetPoint("CENTER")
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function(self)
		if db.barStyle == "free" and not db.barLocked then self:StartMoving() end
	end)
	bar:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		db.barPoint = { point, relPoint, x, y }
	end)
	bar:Hide()
	PlaceBar()
end

function TR:ApplyLook()
	if bar and bar.box and bar.box.SetPanelAlpha then bar.box:SetPanelAlpha(db.panelAlpha or 0.8) end
end

local function UpdateBar()
	local flying = db.bar and flight and flight.start
	if not flying and not boatStatus then
		if bar then bar:Hide() end
		return
	end
	if not bar then BuildBar() end
	if not flying then
		bar:SetStatusBarColor(0.2, 0.75, 0.5)
		bar:SetMinMaxValues(0, math.max(1, boatStatus.max))
		bar:SetValue(math.min(boatStatus.value, boatStatus.max))
		bar.text:SetText(boatStatus.text)
		bar:Show()
		return
	end
	bar:SetStatusBarColor(0.25, 0.55, 1)
	local elapsed = GetServerTime() - flight.start
	if flight.planned then
		local left = flight.planned - elapsed
		bar:SetMinMaxValues(0, flight.planned)
		bar:SetValue(math.min(elapsed, flight.planned))
		bar.text:SetText(("%s  %s%s"):format(flight.to, flight.estimated and "~" or "", left > 0 and Clock(left) or "landing"))
	else
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(1)
		bar.text:SetText(("%s  %s flown"):format(flight.to, Clock(elapsed)))
	end
	bar:Show()
end

-- Called every tick: start the flight timer on take-off, save it on landing.
-- Other modules (Wings & Whispers) hear about take-offs and landings: fn("takeoff", flight) and
-- fn("land", flight, seconds). Not on a /reload mid-flight: that's no new take-off.
local listeners = {}
function TR:OnFlight(fn) listeners[#listeners + 1] = fn end
local function Tell(...)
	for _, fn in ipairs(listeners) do
		local ok, err = pcall(fn, ...)
		if not ok and TR.debug then ns.Print("travel listener: " .. tostring(err)) end
	end
end

local function WatchFlight()
	local onTaxi = UnitOnTaxi("player")
	if onTaxi and flight and not flight.start then
		flight.start = GetServerTime()
		db.current.start = flight.start
		Tell("takeoff", flight)
	elseif not onTaxi and flight and flight.start then
		local seconds = GetServerTime() - flight.start
		Tell("land", flight, seconds)
		if seconds >= MIN_FLIGHT and seconds <= MAX_FLIGHT then
			LearnFlight(flight.from, flight.to, seconds, flight.yards)
			Send(("F|%s|%s|%d"):format(flight.from, flight.to, seconds))
		end
		flight, db.current = nil, nil
	elseif not onTaxi and flight and not flight.start and db.current and GetServerTime() - (db.current.picked or GetServerTime()) > 30 then
		flight, db.current = nil, nil -- picked a destination but never took off
	end
	UpdateBar()
end

---------------------------------------------------------------------------
-- Boats and zeppelins
---------------------------------------------------------------------------

local function PortName()
	local sub = GetSubZoneText and GetSubZoneText() or ""
	local custom = db and db.portAliases and db.portAliases[sub]
	if custom then return custom end
	if PORT_ALIASES[sub] then return PORT_ALIASES[sub] end
	for _, route in ipairs(ROUTES) do
		if route[1] == sub or route[2] == sub then return sub end
	end
	local zone = GetZoneText() or ""
	for _, route in ipairs(ROUTES) do
		if route[1] == zone or route[2] == zone then return zone end
	end
	return sub ~= "" and sub or zone
end

local function PlayerWorld()
	local mapID = C_Map.GetBestMapForUnit("player")
	local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return end
	local continent, world = C_Map.GetWorldPosFromMapPos(mapID, pos)
	if not world then return end
	local x, y = world:GetXY()
	return continent, x, y, mapID, pos:GetXY()
end

-- Cycle length from a list of departure times: differences are whole multiples of it.
local function Period(departures)
	if #departures < 2 then return end
	local smallest
	for i = 2, #departures do
		local d = departures[i] - departures[i - 1]
		if d > 60 and (not smallest or d < smallest) then smallest = d end
	end
	if not smallest then return end
	local sum, n = 0, 0
	for i = 2, #departures do
		local d = departures[i] - departures[i - 1]
		local k = math.floor(d / smallest + 0.5)
		if k >= 1 then sum, n = sum + d / k, n + 1 end
	end
	return n > 0 and sum / n or nil
end

-- Adds a departure (server time). A departure that doesn't fit the known cycle means the
-- schedule shifted (e.g. a server restart), so older ones are dropped.
-- The cycle of a route: measured from its own departures, or else worked out from a round
-- trip (see InferFromRoundTrip).
local function CyclePeriod(r)
	return Period(r.departures) or r.inferred
end

-- A boat shuttles between two docks, so a round trip on the same boat gives the whole
-- cycle: from leaving A to leaving B on the way back is half of it (assuming it waits
-- about as long at both docks). "Same boat" = it left B within the trip time plus
-- ROUND_TRIP_WAIT of leaving A. If a later departure doesn't fit, the guess is dropped.
local ROUND_TRIP_WAIT = 240

local function InferFromRoundTrip(routes, r, when)
	if Period(r.departures) then return end
	local back = routes[FlightKey(r.to, r.from)]
	if not back or Period(back.departures) then return end
	for i = #back.departures, 1, -1 do
		local earlier = back.departures[i]
		local gap = when - earlier
		local trip = back.trip or r.trip or 0
		if gap > trip and gap <= trip + ROUND_TRIP_WAIT then
			r.inferred, back.inferred = 2 * gap, 2 * gap
			return 2 * gap
		end
	end
end

-- Adds a departure (server time). A departure that doesn't fit the known cycle means the
-- schedule shifted (e.g. a server restart), so older ones are dropped; one that doesn't fit
-- a round-trip guess just drops the guess.
function TR:AddDeparture(from, to, when, trip)
	local routes = RealmSchedules()
	local key = FlightKey(from, to)
	local r = routes[key] or { from = from, to = to, departures = {} }
	for _, t in ipairs(r.departures) do
		if math.abs(t - when) < FIT_TOLERANCE then return false end
	end
	local period, last = CyclePeriod(r), r.departures[#r.departures]
	if period and last then
		local cycles = (when - last) / period
		local off = math.abs(cycles - math.floor(cycles + 0.5)) * period
		if off > FIT_TOLERANCE then
			if Period(r.departures) then
				wipe(r.departures)
			else
				r.inferred = nil
				local back = routes[FlightKey(to, from)]
				if back then back.inferred = nil end
			end
		end
	end
	tinsert(r.departures, when)
	table.sort(r.departures)
	while #r.departures > MAX_DEPARTURES do tremove(r.departures, 1) end
	if trip and trip > 0 then r.trip = r.trip and (r.trip + trip) / 2 or trip end
	routes[key] = r
	local inferred = not r.inferred and InferFromRoundTrip(routes, r, when)
	if inferred then
		ns.Print(("Round trip on the same boat: %s <-> %s runs every %s. Both directions' schedules are now known."):format(
			from, to, Clock(inferred)))
	end
	return true
end

local function Debug(fmt, ...)
	if TR.debug then ns.Print("travel: " .. fmt:format(...)) end
end

-- `now` is when the boat stopped and `to` the port you were at then, so walking off or
-- taking a flight straight away doesn't change where the ride ended.
local function FinishRide(now, to)
	local r = ride
	ride = nil
	if TR.external then
		-- Still remember where you boarded, so the dock panel knows this spot is a dock.
		if r.dock and r.from and not (r.from:find("Sea$") or r.from:find("Ocean$")) then db.docks[r.from] = r.dock end
		Debug("ride ended at %s; schedules come from %s, so only the boarding spot is kept", tostring(to), TR.external)
		return
	end
	local trip = now - r.departed
	if trip < MIN_RIDE or trip > MAX_RIDE or not r.from or not to or r.from == to then
		Debug("ride not recorded: %s to %s, %ds (needs %d-%ds between two different ports)",
			tostring(r.from), tostring(to), trip, MIN_RIDE, MAX_RIDE)
		return
	end
	if r.dock then db.docks[r.from] = r.dock end
	if TR:AddDeparture(r.from, to, r.departed, trip) then
		ns.Print(("Learned a %s departure: %s to %s, trip %s."):format(r.kind or "transport", r.from, to, Clock(trip)))
		Send(("D|%s|%s|%s|%d|%d"):format(GetRealmName() or "?", r.from, to, r.departed, trip))
	end
end

-- Where a ride may end. Positions can freeze for a while around the loading screen of a
-- continent crossing, which looks like the boat stopping; seen in game as a ride from
-- Theramore "arriving" in The Great Sea after 50 s. So a ride never ends at sea, ends
-- after RIDE_STOP_SECONDS at a known port, and needs longer at any other place.
local UNKNOWN_STOP_SECONDS = 30
local SEA_GIVE_UP_SECONDS = 300

local function IsSea(name)
	return type(name) == "string" and (name:find("Sea$") or name:find("Ocean$") or name:find("Seas$")) ~= nil
end

local function IsKnownPort(name)
	for _, route in ipairs(ROUTES) do
		if route[1] == name or route[2] == name then return true end
	end
	return false
end

local last -- previous sample { continent, x, y, time, port, dock, stillFor }
local movingSamples, stillSince, stillStart, arrivePort = 0, nil, nil, nil
local selfMoving = false -- set by PLAYER_STARTED/STOPPED_MOVING, which only fire for your own movement
local BOARD_WAIT = 10    -- seconds you must stand still before a ride counts (waiting on the dock)

local function WatchTransport()
	if UnitOnTaxi("player") then
		-- Took a flight right after the boat docked: the ride ended where the boat stopped.
		if ride and stillSince and not IsSea(arrivePort) then FinishRide(stillSince, arrivePort) end
		ride = nil
		last = nil
		return
	end
	local now = GetServerTime()
	local continent, x, y, mapID, mx, my = PlayerWorld()
	local carried, rate = false, 0
	if continent and last and last.continent == continent and not selfMoving then
		local dt = now - last.time
		if dt > 0 then
			rate = math.sqrt((x - last.x) ^ 2 + (y - last.y) ^ 2) / dt
			carried = rate > TRANSPORT_SPEED
		end
	end
	Debug("%s | map %s | you moving: %s | carried %.1f yd/s -> %s | still %ds | ride: %s",
		PortName(), tostring(mapID), tostring(selfMoving), rate, tostring(carried),
		last and last.stillFor or 0, ride and ("from " .. tostring(ride.from)) or "no")

	if carried then
		movingSamples = movingSamples + 1
		stillSince, stillStart, arrivePort = nil, nil, nil
		if not ride and movingSamples >= RIDE_START_SAMPLES and last then
			if (last.stillFor or 0) >= BOARD_WAIT then
				ride = { from = last.port, dock = last.dock, departed = now - RIDE_START_SAMPLES * SAMPLE_INTERVAL }
				Debug("ride started from %s", tostring(ride.from))
			elseif movingSamples == RIDE_START_SAMPLES then
				Debug("moving without having waited %ds first (joined mid-trip?), not counted", BOARD_WAIT)
			end
		end
	elseif ride and continent then
		-- The boat stopped: note when and where the first time you stand still, then end the
		-- ride RIDE_STOP_SECONDS later even if you've walked off in the meantime.
		if not stillSince and not selfMoving then
			stillSince, arrivePort = now, PortName()
			Debug("boat stopped at %s%s", arrivePort,
				IsSea(arrivePort) and " (at sea: waiting for it to move again)" or "")
		end
		if stillSince then
			local stopped = now - stillSince
			if IsSea(arrivePort) then
				if stopped >= SEA_GIVE_UP_SECONDS then
					Debug("stopped at sea for %ds, ride dropped", stopped)
					ride, stillSince, arrivePort = nil, nil, nil
				end
			elseif stopped >= (IsKnownPort(arrivePort) and RIDE_STOP_SECONDS or UNKNOWN_STOP_SECONDS) then
				FinishRide(stillSince, arrivePort)
			end
		end
	elseif not ride then
		movingSamples = 0
	end

	if selfMoving then stillStart = nil end
	if continent and not ride and not selfMoving and not carried then
		-- Remember where we're standing still, as the boarding spot if a ride starts. A ride
		-- only counts after waiting here a while, so a /reload mid-voyage isn't a departure.
		stillStart = stillStart or now
		last = { continent = continent, x = x, y = y, time = now, port = PortName(), dock = { mapID, mx, my },
			stillFor = now - stillStart }
	elseif continent then
		last = last or {}
		last.continent, last.x, last.y, last.time = continent, x, y, now
	end
end

---------------------------------------------------------------------------
-- For the Boats module (dock panel, timetable, departure alert, on-board bar)
---------------------------------------------------------------------------

TR.ROUTES = ROUTES
TR.Clock = Clock
TR.PortName = PortName

-- Port names that count as "here": the port you're in (dock aliases applied), the raw
-- subzone, and any learned boarding spot within DOCK_RADIUS.
function TR:PortsHere()
	local ports = { [PortName()] = true }
	local sub = GetSubZoneText and GetSubZoneText() or ""
	if sub ~= "" then ports[sub] = true end
	local mapID = C_Map.GetBestMapForUnit("player")
	local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if pos then
		local px, py = pos:GetXY()
		local width, height = MapYards(mapID)
		for port, dock in pairs(db.docks) do
			if width and dock[1] == mapID then
				local dx, dy = (dock[2] - px) * width, (dock[3] - py) * height
				if dx * dx + dy * dy <= DOCK_RADIUS * DOCK_RADIUS then ports[port] = true end
			end
		end
	end
	return ports
end

function TR:LearnedRoutes()
	return RealmSchedules()
end

-- For a learned route: seconds until its next departure (nil if the cycle isn't known),
-- its last departure time, and the cycle length.
function TR:NextDeparture(r, now)
	local period, lastDep = CyclePeriod(r), r.departures[#r.departures]
	if not lastDep then return end
	if not period then return nil, lastDep end
	return lastDep + math.ceil((now - lastDep) / period) * period - now, lastDep, period
end

-- The ride in progress ({ from, departed }), if you're on a boat or zeppelin.
function TR:CurrentRide()
	return ride
end

function TR:SetBoatStatus(status)
	boatStatus = status
end

---------------------------------------------------------------------------
-- Incoming shared data
---------------------------------------------------------------------------

local function OnAddonMessage(prefix, message, _, sender)
	if prefix ~= PREFIX or not db.share then return end
	local me = UnitName("player")
	if sender == me or (sender and sender:match("^([^-]+)") == me) then return end
	local kind, a, b, c, d, e = strsplit("|", message)
	if kind == "F" then
		local from, to, seconds = CleanName(a), CleanName(b), tonumber(c)
		if from and to and seconds and seconds >= MIN_FLIGHT and seconds <= MAX_FLIGHT and not db.flights[FlightKey(from, to)] then
			db.flights[FlightKey(from, to)] = { t = seconds, n = 1, shared = true }
		end
	elseif kind == "D" then
		local realm, from, to, when, trip = CleanName(a), CleanName(b), CleanName(c), tonumber(d), tonumber(e)
		local now = GetServerTime()
		if not TR.external and realm == GetRealmName() and from and to and when and when <= now + 60 and when >= now - 7 * 86400
			and trip and trip >= MIN_RIDE and trip <= MAX_RIDE then
			TR:AddDeparture(from, to, when, trip)
		end
	end
end

-- Shortly after login, share the latest departure of each route so guildmates who
-- missed it catch up.
local function ShareRecent()
	if TR.external then return end
	local delay = 0
	for _, r in pairs(RealmSchedules()) do
		local lastDep = r.departures[#r.departures]
		if lastDep and GetServerTime() - lastDep < 86400 then
			delay = delay + 2 -- (each goes to the guild and the group: two messages)
			C_Timer.After(delay, function()
				Send(("D|%s|%s|%s|%d|%d"):format(GetRealmName() or "?", r.from, r.to, lastDep, math.floor(r.trip or 0)))
			end)
		end
	end
end

---------------------------------------------------------------------------
-- Module API
---------------------------------------------------------------------------

function TR:OnInitialize(saved)
	db = saved.travel
	-- Routes learned before a dock's alias was known (e.g. "The Long Wash" for Auberdine).
	-- (Collect first: adding keys to a table while looping over it isn't allowed.)
	for _, routes in pairs(db.schedules) do
		-- Rides that "ended" at sea before that was ruled out are bogus.
		local bogus = {}
		for key, r in pairs(routes) do
			if IsSea(r.from) or IsSea(r.to) then bogus[#bogus + 1] = key end
		end
		for _, key in ipairs(bogus) do routes[key] = nil end

		local renamed = {}
		for key, r in pairs(routes) do
			local from, to = PORT_ALIASES[r.from] or r.from, PORT_ALIASES[r.to] or r.to
			if from ~= r.from or to ~= r.to then renamed[key] = { from, to } end
		end
		for key, names in pairs(renamed) do
			local r = routes[key]
			routes[key] = nil
			r.from, r.to = names[1], names[2]
			local newKey = FlightKey(names[1], names[2])
			routes[newKey] = routes[newKey] or r
		end
	end
	local renamedDocks = {}
	for name in pairs(db.docks) do
		if PORT_ALIASES[name] then renamedDocks[#renamedDocks + 1] = name end
	end
	for _, name in ipairs(renamedDocks) do
		local port = PORT_ALIASES[name]
		db.docks[port] = db.docks[port] or db.docks[name]
		db.docks[name] = nil
	end
end

function TR:OnLogin()
	hooksecurefunc("TakeTaxiNode", function(slot)
		OnTakeTaxiNode(slot)
		if db.current then db.current.picked = GetServerTime() end
	end)
	HookFlightMaps()

	-- A /reload mid-flight: pick the flight back up.
	if db.current and db.current.start and UnitOnTaxi("player") then
		flight = { from = db.current.from, to = db.current.to, planned = db.current.planned,
			estimated = db.current.estimated, start = db.current.start }
	else
		db.current = nil
	end

	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
	local events = CreateFrame("Frame")
	events:RegisterEvent("ADDON_LOADED")
	events:RegisterEvent("CHAT_MSG_ADDON")
	events:RegisterEvent("PLAYER_STARTED_MOVING")
	events:RegisterEvent("PLAYER_STOPPED_MOVING")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:SetScript("OnEvent", function(_, event, ...)
		if event == "PLAYER_STARTED_MOVING" then
			selfMoving = true
		elseif event == "PLAYER_STOPPED_MOVING" or event == "PLAYER_ENTERING_WORLD" then
			-- After a loading screen (e.g. a boat crossing to the other continent) a "stopped
			-- moving" may never arrive, so don't stay stuck thinking you're walking.
			selfMoving = false
		elseif event == "ADDON_LOADED" then
			local name = ...
			if name == "Blizzard_FlightMap" or name == "Blizzard_UIPanels_Game" then HookFlightMaps() end
		elseif event == "CHAT_MSG_ADDON" then
			OnAddonMessage(...)
		end
	end)

	C_Timer.NewTicker(SAMPLE_INTERVAL, function()
		WatchFlight()
		WatchTransport()
		if ns.Boats and ns.Boats.Tick then ns.Boats:Tick() end
		UpdateBar()
	end)
	C_Timer.After(20, ShareRecent)
end

function TR:Refresh()
	if bar then PlaceBar() end
	UpdateBar()
	if ns.Boats and ns.Boats.Tick then ns.Boats:Tick() end
end

-- /aa dockname <port>: the dock you're standing on belongs to <port> (e.g. "Auberdine"),
-- for dock subzones the game names differently. No argument lists them; "clear" removes
-- the one for where you stand.
function TR:SetDockName(port)
	db.portAliases = db.portAliases or {}
	local sub = GetSubZoneText and GetSubZoneText() or ""
	port = strtrim(port or "")
	if port == "" then
		local lines = {}
		for dock, name in pairs(db.portAliases) do lines[#lines + 1] = dock .. " = " .. name end
		for dock, name in pairs(PORT_ALIASES) do lines[#lines + 1] = dock .. " = " .. name .. " (built in)" end
		table.sort(lines)
		ns.Print("Dock names: " .. table.concat(lines, ", "))
		return ns.Print(("You're in \"%s\", which counts as %s."):format(sub, PortName()))
	end
	if sub == "" then
		-- Open-air docks (e.g. zeppelin towers) have no subzone: remember this exact spot
		-- instead; the dock panel then shows within DOCK_RADIUS yards of it.
		local mapID = C_Map.GetBestMapForUnit("player")
		local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
		if not pos then return ns.Print("Can't read your position here.") end
		if port:lower() == "clear" then
			for name, dock in pairs(db.docks) do
				local width, height = MapYards(mapID)
				local x, y = pos:GetXY()
				if dock[1] == mapID and width and ((dock[2] - x) * width) ^ 2 + ((dock[3] - y) * height) ^ 2 <= DOCK_RADIUS ^ 2 then
					db.docks[name] = nil
					return ns.Print(("Forgot the %s dock spot here."):format(name))
				end
			end
			return ns.Print("No remembered dock spot here.")
		end
		local x, y = pos:GetXY()
		db.docks[port] = { mapID, x, y }
		return ns.Print(("This spot is now the %s dock (within %d yards)."):format(port, DOCK_RADIUS))
	end
	if port:lower() == "clear" then
		db.portAliases[sub] = nil
		return ns.Print(("\"%s\" no longer has a custom port name."):format(sub))
	end
	db.portAliases[sub] = port
	ns.Print(("\"%s\" now counts as %s."):format(sub, port))
end

function TR:ToggleDebug()
	self.debug = not self.debug
	ns.Print(self.debug and "Travel debug on: one line per second in chat. /aa traveldebug again to stop."
		or "Travel debug off.")
end

function TR:ResetBarPosition()
	db.barPoint = nil
	if bar then PlaceBar() end
end

function TR:Status()
	local flights, routes = 0, 0
	for _ in pairs(db.flights) do flights = flights + 1 end
	for _, r in pairs(RealmSchedules()) do
		if CyclePeriod(r) then routes = routes + 1 end
	end
	return flights, routes
end

function TR:Forget()
	wipe(db.flights)
	wipe(db.schedules)
	wipe(db.docks)
	db.speed.yards, db.speed.seconds = 0, 0
end
