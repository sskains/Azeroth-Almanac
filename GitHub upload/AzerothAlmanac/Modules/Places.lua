-- Places: zones, subzones and instances, discovered when a character enters them.
--   found.zone[uiMapID]          = { name, continent, parent, explored = map areas uncovered }
--   found.subzone["map:Name"]    = { name, map, zone, x, y (where it was first entered), area }
--   found.instance[instanceID]   = { name, type = "party" / "raid", difficulty }
-- Per character (exploration is the character's own):
--   chars[key].explored[subzoneID] = { t = time, xp = experience gained }   from "Discovered X: N experience"
--   chars[key].mapAreas[uiMapID]   = map areas uncovered on that zone's map

local _, ns = ...
local L = ns.L
local Places = ns:NewModule("Places")

local function MapInfo(map)
	if not (map and C_Map and C_Map.GetMapInfo) then return nil end
	local ok, info = pcall(C_Map.GetMapInfo, map)
	if ok and type(info) == "table" and not ns.IsSecret(info) then return info end
end

-- the continent a map belongs to (walks up the parents)
local function Continent(map)
	local info = MapInfo(map)
	local guard = 0
	while info and guard < 8 do
		guard = guard + 1
		if info.mapType == 2 then return info.name, info.mapID end -- Enum.UIMapType.Continent
		if not info.parentMapID or info.parentMapID == 0 then break end
		info = MapInfo(info.parentMapID)
	end
end

local function ExploredCount(map)
	if not (C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures) then return nil end
	local ok, tex = pcall(C_MapExplorationInfo.GetExploredMapTextures, map)
	if ok and type(tex) == "table" and not ns.IsSecret(tex) then return #tex end
end

function Places:Check()
	if not ns.db then return end
	ns.doing = "recording a place"
	local where = ns.Where()

	-- dungeons and raids
	local okI, iname, itype, _, diffName, _, _, _, instanceID = pcall(GetInstanceInfo)
	iname, itype, instanceID = ns.Readable(iname), ns.Readable(itype), ns.Readable(instanceID)
	if okI and (itype == "party" or itype == "raid") and instanceID then
		ns.Store:Discover("instance", instanceID, { name = iname, type = itype, difficulty = ns.Readable(diffName) },
			(L["%s (%s)"]):format(iname or "?", itype == "raid" and L["raid"] or L["dungeon"]), where)
		-- a dungeon's floors belong to the dungeon (Dungeons page), not to the zones
		return
	end

	local map = where.map
	if not map then return end
	local info = MapInfo(map)
	-- on loading screens the game can briefly report the continent (Eastern Kingdoms) or the world
	if info and info.mapType and info.mapType <= 2 then return end
	local zoneName = (info and info.name) or where.zone
	local continent = Continent(map)
	-- (a visit counts when you arrive, not at every subzone and indoor change inside the zone,
	-- 0.64.0; the same for a subzone)
	local zrec
	if Places.lastMap ~= map or not ns.Store:Get("zone", map) then
		zrec = ns.Store:Discover("zone", map, { name = zoneName, continent = continent, parent = info and info.parentMapID },
			continent and (L["%s, %s"]):format(zoneName or "?", continent) or zoneName, where)
	else
		zrec = ns.Store:Get("zone", map)
	end
	Places.lastMap = map
	if zrec then
		local explored = ExploredCount(map)
		if explored then
			local c = ns.db.chars[ns.CharKey()]
			if c then
				c.mapAreas = c.mapAreas or {}
				c.mapAreas[map] = math.max(c.mapAreas[map] or 0, explored)
			end
		end
	end

	local sub = where.sub
	if sub and sub ~= "" and sub ~= zoneName then
		local id = map .. ":" .. sub
		local existing = ns.Store:Get("subzone", id)
		if Places.lastSub ~= id or not existing then
			local fields = { name = sub, map = map, zone = zoneName }
			if not existing then fields.x, fields.y = where.x, where.y end
			ns.Store:Discover("subzone", id, fields, (L["%s, %s"]):format(sub, zoneName or "?"), where)
		end
		Places.lastSub = id
	else
		Places.lastSub = nil
	end
end

-- version 0.1.0 could record a continent as a zone: remove those (and their journal lines)
function Places:OnLogin()
	ns.doing = "tidying places"
	local zones = ns.Store:All("zone")
	local gone = {}
	for id in pairs(zones) do
		local info = MapInfo(id)
		if info and info.mapType and info.mapType <= 2 then gone[id] = true end
	end
	if next(gone) then
		for id in pairs(gone) do zones[id] = nil end
		for sid, rec in pairs(ns.Store:All("subzone")) do if gone[rec.map] then ns.Store:All("subzone")[sid] = nil end end
		local j, kept = ns.db.journal, {}
		for _, e in ipairs(j) do
			if not ((e.k == "zone" and gone[e.i]) or (e.k == "subzone" and e.i and gone[tonumber(tostring(e.i):match("^(%d+):"))])) then kept[#kept + 1] = e end
		end
		ns.db.journal = kept
	end
	ns.doing = "idle"
end

local pending = false
local function Soon()
	if pending then return end
	pending = true
	C_Timer.After(0.5, function()
		pending = false
		Places:Check()
	end)
end

for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }) do
	ns:RegisterEvent(e, Soon)
end

---------------------------------------------------------------------------
-- Exploration: the game's "Discovered Goldshire: 40 experience gained" message
---------------------------------------------------------------------------

local EXPLORED_XP, EXPLORED

function Places:Explored(name, xp)
	if self.ForgetExploration then self:ForgetExploration() end
	local where = ns.Where()
	if not where.map then return end
	local info = MapInfo(where.map)
	local zoneName = (info and info.name) or where.zone
	-- the whole zone, or a place within it
	local id
	if name == zoneName then
		id = "zone:" .. where.map
	else
		id = where.map .. ":" .. name
		if not ns.Store:Get("subzone", id) then
			ns.Store:Discover("subzone", id, { name = name, map = where.map, zone = zoneName, x = where.x, y = where.y },
				(L["%s, %s"]):format(name, zoneName or "?"), where)
		end
		local rec = ns.Store:Get("subzone", id)
		if rec and xp then rec.xp = rec.xp or {} rec.xp[ns.CharKey()] = xp end
	end
	local c = ns.db.chars[ns.CharKey()]
	if not c then return end
	c.explored = c.explored or {}
	if not c.explored[id] then c.explored[id] = { t = time(), xp = xp } end
	ns:Fire("CHANGED", "subzone", id)
	-- (the achievement updates a moment after the message)
	C_Timer.After(2, function() pcall(Places.CheckZoneExplored, Places, zoneName, where.map) end)
end

ns:RegisterEvent("CHAT_MSG_SYSTEM", function(_, msg)
	msg = ns.Readable(msg)
	if not ns.db or type(msg) ~= "string" then return end
	EXPLORED_XP = EXPLORED_XP or ns.Pattern(ERR_ZONE_EXPLORED_XP)
	EXPLORED = EXPLORED or ns.Pattern(ERR_ZONE_EXPLORED)
	local name, xp = nil, nil
	if EXPLORED_XP then name, xp = msg:match(EXPLORED_XP) end
	if not name and EXPLORED then name = msg:match(EXPLORED) end
	if name then
		ns.doing = "recording exploration"
		Places:Explored(name, tonumber(xp))
		ns.doing = "idle"
	end
end)

---------------------------------------------------------------------------
-- How much of a zone is explored (0.57.0): WoW Forever's legacy exploration achievements
-- ("Explore Elwynn Forest") list every area of a zone as criteria, so the total is the game's
-- own, for the character you're playing. The one place the Almanac shows "x of y" (ground rule 9's
-- exception: the game already shows it). nil where the client has no such achievement.
---------------------------------------------------------------------------

local exploreIndex, exploreBuiltAt -- zone name (lower case) -> achievement id
local function BuildExploreIndex()
	exploreIndex, exploreBuiltAt = {}, GetTime()
	if not (GetCategoryList and GetCategoryNumAchievements and GetAchievementInfo) then return end
	local ok, cats = pcall(GetCategoryList)
	if not ok or type(cats) ~= "table" then return end
	local prefix = (ns.L["Explore %s"]):gsub("%%s", "(.+)")
	for _, cat in ipairs(cats) do
		local okN, n = pcall(GetCategoryNumAchievements, cat, true)
		for i = 1, (okN and tonumber(n) or 0) do
			local okA, id, name = pcall(GetAchievementInfo, cat, i)
			if okA and id and type(name) == "string" then
				local zone = name:match("^" .. prefix .. "$")
				if zone then exploreIndex[zone:lower()] = id end
			end
		end
	end
end

-- total areas, how many this character has explored, and the areas { { name, done } }
-- (answers kept for 30 seconds, and dropped when you explore somewhere: the pages ask for every
-- zone they draw, 0.64.0)
local exploreCache = {}
function Places:ForgetExploration() wipe(exploreCache) end
function Places:Exploration(zoneName)
	if not zoneName then return nil end
	local hit = exploreCache[zoneName]
	if hit and GetTime() - hit.t < 30 then return hit.total, hit.done, hit.areas end
	local total, done, areas = self:ReadExploration(zoneName)
	exploreCache[zoneName] = { t = GetTime(), total = total, done = done, areas = areas }
	return total, done, areas
end
function Places:ReadExploration(zoneName)
	if not exploreIndex then BuildExploreIndex() end
	local id = exploreIndex[zoneName:lower()]
	-- (read too early - the achievements not loaded yet - the index comes out short: a zone it
	-- doesn't know builds it again, once a minute at most, 0.63.0)
	if not id and GetTime() - (exploreBuiltAt or 0) > 60 then
		BuildExploreIndex()
		id = exploreIndex[zoneName:lower()]
	end
	if not (id and GetAchievementNumCriteria and GetAchievementCriteriaInfo) then return nil end
	local ok, n = pcall(GetAchievementNumCriteria, id)
	if not ok or type(n) ~= "number" or n < 1 then return nil end
	local done, areas = 0, {}
	for i = 1, n do
		local okC, name, _, completed = pcall(GetAchievementCriteriaInfo, id, i)
		if okC and name then
			areas[#areas + 1] = { name = name, done = completed and true or false }
			if completed then done = done + 1 end
		end
	end
	if #areas == 0 then return nil end
	return #areas, done, areas
end

-- the whole zone explored: a milestone-like alert and a journal line, once per zone per character
function Places:CheckZoneExplored(zoneName, map)
	local total, done = self:Exploration(zoneName)
	if not (total and done >= total) then return end
	local c = ns.db.chars[ns.CharKey()]
	if not c then return end
	c.zoneDone = c.zoneDone or {}
	if c.zoneDone[zoneName] then return end
	c.zoneDone[zoneName] = time()
	ns:Fire("TOAST", "milestone", L["Fully explored"], zoneName, ns.Widgets and ns.Widgets.KindIcon and ns.Widgets.KindIcon("zone") or nil, 4)
	ns.Store:AddJournal("zone", map, (L["%s fully explored (%d areas)."]):format(zoneName, total), ns.Where())
end

-- has this character explored a place (or the whole zone: "zone:<map>")? returns the record
function Places:ExploredBy(key, id)
	local c = ns.db.chars[key]
	return c and c.explored and c.explored[id]
end

-- what's been found in a zone, from every catalogue
function Places:InZone(map, zoneName)
	local out = { creatures = {}, merchants = {}, quests = {}, givers = {}, lo = nil, hi = nil }
	for npc, rec in pairs(ns.Store:Shown("creature")) do
		if rec.z and rec.z[map] then
			out.creatures[#out.creatures + 1] = { npc = npc, rec = rec }
			if rec.lo and rec.lo > 0 then out.lo = math.min(out.lo or rec.lo, rec.lo) end
			if rec.hi and rec.hi > 0 then out.hi = math.max(out.hi or rec.hi, rec.hi) end
		end
	end
	table.sort(out.creatures, function(a, b)
		if (a.rec.lo or 0) ~= (b.rec.lo or 0) then return (a.rec.lo or 0) < (b.rec.lo or 0) end
		return (a.rec.name or "") < (b.rec.name or "")
	end)
	for npc, rec in pairs(ns.Store:Shown("merchant")) do
		if rec.map == map then out.merchants[#out.merchants + 1] = { npc = npc, rec = rec } end
	end
	table.sort(out.merchants, function(a, b) return (a.rec.name or "") < (b.rec.name or "") end)
	out.trainers = {}
	for npc, rec in pairs(ns.Store:Shown("trainer")) do
		if rec.map == map then out.trainers[#out.trainers + 1] = { npc = npc, rec = rec } end
	end
	table.sort(out.trainers, function(a, b) return (a.rec.name or "") < (b.rec.name or "") end)
	for qid, rec in pairs(ns.Store:Shown("quest")) do
		if (rec.gpos and rec.gpos.map == map) or (zoneName and ns.Quests:Heading(qid, rec) == zoneName) then
			out.quests[#out.quests + 1] = { qid = qid, rec = rec }
		end
	end
	table.sort(out.quests, function(a, b) return (a.rec.name or "") < (b.rec.name or "") end)
	for _, kind in ipairs({ "npc", "object" }) do
		for id, rec in pairs(ns.Store:Shown(kind)) do
			if rec.map == map then out.givers[#out.givers + 1] = { id = id, kind = kind, rec = rec } end
		end
	end
	table.sort(out.givers, function(a, b) return (a.rec.name or "") < (b.rec.name or "") end)
	return out
end

-- zones with their subzones, for the Places page: { { id, rec, subs = { { id, rec }, ... } }, ... }
function Places:Tree()
	local zones = {}
	local byMap = {}
	for id, rec in pairs(ns.Store:Shown("zone")) do
		local z = { id = id, rec = rec, subs = {} }
		zones[#zones + 1] = z
		byMap[id] = z
	end
	for id, rec in pairs(ns.Store:Shown("subzone")) do
		local z = byMap[rec.map]
		if z then z.subs[#z.subs + 1] = { id = id, rec = rec } end
	end
	table.sort(zones, function(a, b)
		local ca, cb = a.rec.continent or "~", b.rec.continent or "~"
		if ca ~= cb then return ca < cb end
		return (a.rec.name or "") < (b.rec.name or "")
	end)
	for _, z in ipairs(zones) do
		table.sort(z.subs, function(a, b) return (a.rec.f or 0) < (b.rec.f or 0) end)
	end
	return zones
end
