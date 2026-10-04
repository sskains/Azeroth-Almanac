-- Flight paths: every flight point a character knows, read from the flight map when it opens
-- (TAXIMAP_OPENED). The point you stand at gets the flight master and your exact position; the others
-- get their zone (from the node name, "Sentinel Hill, Westfall") and, where the client can convert
-- it, a map position from the flight map. Flight times come from the travel helper (QoL\Travel.lua),
-- which times each flight you take.
-- found.flight[name] = { name, zone, map, x, y (percent, where known), master = npcID,
--                        known = { [charKey] = time learned / first seen } }

local _, ns = ...
local L = ns.L
local F = ns:NewModule("Flights")
local R = ns.Readable

local function Call(fn, ...)
	if not fn then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return R(a), R(b), R(c) end
end

-- the continent map the flight map shows: the player's map, walked up to its continent
local function ContinentMap()
	local map = C_Map and C_Map.GetBestMapForUnit and Call(C_Map.GetBestMapForUnit, "player")
	local info = map and Call(C_Map.GetMapInfo, map)
	while type(info) == "table" and info.mapType and Enum and Enum.UIMapType and info.mapType > Enum.UIMapType.Continent
		and info.parentMapID and info.parentMapID ~= 0 do
		map = info.parentMapID
		info = Call(C_Map.GetMapInfo, map)
	end
	return map
end

-- a zone's uiMapID from its name: the Almanac's own zone records first
local function ZoneMap(zone)
	if not zone then return nil end
	for id, rec in pairs(ns.Store:All("zone")) do
		if rec.name == zone then return id end
	end
end

-- a flight-map position (0..1 on the continent) as a zone map position: map, x, y (percent)
local function ToZone(cont, x, y)
	if not (cont and x and y and C_Map and C_Map.GetMapInfoAtPosition and C_Map.GetWorldPosFromMapPos
		and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
	local info = Call(C_Map.GetMapInfoAtPosition, cont, x, y)
	if type(info) ~= "table" or not info.mapID or info.mapID == cont then return nil end
	local ok, inst, world = pcall(C_Map.GetWorldPosFromMapPos, cont, CreateVector2D(x, y))
	if not ok or type(world) ~= "table" then return nil end
	local ok2, _, pos = pcall(C_Map.GetMapPosFromWorldPos, inst, world, info.mapID)
	if not ok2 or type(pos) ~= "table" or not pos.GetXY then return nil end
	local zx, zy = pos:GetXY()
	if not zx or zx < 0 or zx > 1 or zy < 0 or zy > 1 then return nil end
	return info.mapID, zx * 100, zy * 100
end

function F:Read()
	if not (ns.db and NumTaxiNodes) then return end
	local n = Call(NumTaxiNodes) or 0
	if n == 0 then return end
	local cont = ContinentMap()
	local char = ns.CharKey()
	local now = time()
	local where = ns.Where()
	local npc = ns.NpcFromGuid(R(UnitGUID("npc")))
	for i = 1, n do
		local kind = Call(TaxiNodeGetType, i)
		local name = Call(TaxiNodeName, i)
		if name and kind and kind ~= "NONE" then
			local current = kind == "CURRENT"
			local zone = name:match(",%s*(.-)%s*$")
			local fields = { name = name, zone = zone }
			local existing = ns.Store:Get("flight", name)
			if current then
				fields.map, fields.x, fields.y, fields.exact = where.map, where.x, where.y, true
				fields.master = npc
				if where.zone then fields.zone = fields.zone or where.zone end
			elseif not (existing and existing.x) then
				local tx, ty = Call(TaxiNodePosition, i)
				local m, x, y = ToZone(cont, tx, ty)
				fields.map, fields.x, fields.y = m or ZoneMap(zone), x, y
			end
			-- a new point is a journal entry (and an alert) when you're standing at it: you just
			-- learned it. Points already known when the map first opens are recorded quietly.
			local text = name
			local rec, isNew = ns.Store:Discover("flight", name, fields, text, where, not current)
			if rec then
				rec.known = rec.known or {}
				if not rec.known[char] then rec.known[char] = now end
			end
			if current and npc then
				local tf = ns.Store:Get("townsfolk", npc)
				if tf then tf.node = name end
			end
		end
	end
	ns:Fire("CHANGED", "flight")
end

ns:RegisterEvent("TAXIMAP_OPENED", function()
	ns.doing = "reading the flight map"
	local ok, err = pcall(F.Read, F)
	if not ok then ns.Debug("flights: " .. tostring(err)) end
	ns.doing = "idle"
end)

-- the travel helper's timed flights: { to = name, t = seconds, n = times, shared } from or to a point
function F:Routes(name)
	local q = ns.QoL and ns.QoL.db and ns.QoL.db.travel
	local from, to = {}, {}
	for key, e in pairs(q and q.flights or {}) do
		local a, b = key:match("^(.-) > (.+)$")
		if a == name and type(e) == "table" and e.t then from[#from + 1] = { other = b, t = e.t, n = e.n, shared = e.shared } end
		if b == name and type(e) == "table" and e.t then to[#to + 1] = { other = a, t = e.t, n = e.n, shared = e.shared } end
	end
	local function ByTime(x, y) return x.t < y.t end
	table.sort(from, ByTime)
	table.sort(to, ByTime)
	return from, to
end

function F:TimeText(seconds)
	seconds = math.floor((seconds or 0) + 0.5)
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end
