-- Dungeons and raids: each one a character enters (found.instance, from Places), the bosses met and
-- killed there, where they were met, the maps of its floors, and each character's runs.
--   found.instance[instanceID] += { maps = { [uiMapID] = floor name }, bosses = { [bossKey] = { name, npc,
--       kills, wipes, first = { char, t }, map, x, y } }, best = seconds of the quickest run with a kill }
--   chars[key].runs[instanceID] = { n = runs, last = time, kills = { [bossKey] = n }, time = seconds inside }
-- A boss's key is its NPC ID, or "e<encounterID>" / its name when the NPC isn't known.
-- The hidden database (Data\Dungeons.lua, from AtlasLoot Revival) knows which NPCs are a dungeon's
-- bosses; a boss is shown only once met, the others are counted.

local _, ns = ...
local L = ns.L
local D = ns:NewModule("Dungeons")
local R = ns.Readable

---------------------------------------------------------------------------
-- The hidden database
---------------------------------------------------------------------------

local byID, byName, bossOf
local function Index()
	if byID then return end
	byID, byName, bossOf = {}, {}, {}
	for _, d in ipairs(ns.DB and ns.DB.dungeon or {}) do
		if d.id then byID[d.id] = byID[d.id] or {} table.insert(byID[d.id], d) end
		byName[d.name] = byName[d.name] or {}
		table.insert(byName[d.name], d)
		for _, b in ipairs(d.bosses or {}) do
			if b.npc then bossOf[b.npc] = d end
		end
	end
end

-- the database entries for a dungeon (two for Blackrock Spire: lower and upper)
function D:Entries(id, name)
	Index()
	return byID[id] or (name and byName[name]) or {}
end

-- is this NPC a dungeon boss in the records?
function D:IsBoss(npc)
	Index()
	return npc and bossOf[npc] ~= nil
end

local function Items(s)
	local out = {}
	for part in (s or ""):gmatch("[^,]+") do
		local id, c = part:match("^(%d+):(%d+)$")
		if id then out[#out + 1] = { id = tonumber(id), chance = tonumber(c) / 100 } end
	end
	return out
end
D.Items = Items

---------------------------------------------------------------------------
-- Runs: from entering until leaving
---------------------------------------------------------------------------

local run -- { id, t, kills = n }

local function Me()
	local c = ns.db.chars[ns.CharKey()]
	if not c then return nil end
	c.runs = c.runs or {}
	return c
end

local function InstanceNow()
	local ok, name, itype, _, _, _, _, _, id = pcall(GetInstanceInfo)
	itype, id = R(itype), R(id)
	if ok and (itype == "party" or itype == "raid") and id then return id, R(name) end
end

function D:Check()
	if not ns.db then return end
	local id, name = InstanceNow()
	if run and run.id ~= id then
		-- left (or moved to another instance): close the run
		local c = Me()
		local secs = time() - run.t
		if c then
			local r = c.runs[run.id] or { n = 0, kills = {} }
			r.time = (r.time or 0) + secs
			c.runs[run.id] = r
		end
		local rec = ns.Store:Get("instance", run.id)
		if rec and run.kills > 0 then
			if not rec.best or secs < rec.best then rec.best = secs end
			ns.Store:AddJournal("instance", run.id, (L["%s: %s in %d min"]):format(rec.name or "?", ns.N(run.kills, "boss", "bosses"), math.floor(secs / 60 + 0.5)))
		end
		run = nil
	end
	if id and not run then
		run = { id = id, t = time(), kills = 0 }
		local c = Me()
		if c then
			local r = c.runs[id] or { n = 0, kills = {} }
			r.n = r.n + 1
			r.last = time()
			c.runs[id] = r
		end
	end
	-- the floors' maps, as the game names them
	if id then
		local rec = ns.Store:Get("instance", id)
		local where = ns.Where()
		if rec and where.map then
			rec.maps = rec.maps or {}
			if not rec.maps[where.map] then
				local info = C_Map and C_Map.GetMapInfo and select(2, pcall(C_Map.GetMapInfo, where.map))
				rec.maps[where.map] = type(info) == "table" and R(info.name) or name or "?"
			end
		end
	end
end

local pending = false
local function Soon()
	if pending then return end
	pending = true
	C_Timer.After(1, function() pending = false ns.doing = "recording a dungeon" pcall(D.Check, D) ns.doing = "idle" end)
end
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }) do ns:RegisterEvent(e, Soon) end

---------------------------------------------------------------------------
-- Bosses: the game's encounter events, and kills of a dungeon's bosses (for dungeons without them)
---------------------------------------------------------------------------

local function Boss(id, key, fields)
	local rec = ns.Store:Get("instance", id)
	if not rec then return nil end
	rec.bosses = rec.bosses or {}
	local b = rec.bosses[key] or { kills = 0, wipes = 0 }
	for k, v in pairs(fields) do if v ~= nil then b[k] = v end end
	if not b.first then b.first = { c = ns.CharKey(), t = time() } end
	if not b.x then
		local where = ns.Where()
		b.map, b.x, b.y = where.map, where.x, where.y
	end
	rec.bosses[key] = b
	return b, rec
end

local function Killed(id, key, b)
	b.kills = (b.kills or 0) + 1
	b.lastKill = time()
	local c = Me()
	if c then
		local r = c.runs[id] or { n = 1, kills = {} }
		r.kills = r.kills or {}
		r.kills[key] = (r.kills[key] or 0) + 1
		c.runs[id] = r
	end
	if run and run.id == id then run.kills = run.kills + 1 end
	ns:Fire("CHANGED", "instance", id)
end

local encounter -- { id, key }
ns:RegisterEvent("ENCOUNTER_START", function(_, encounterID, name)
	local id = InstanceNow()
	if not (ns.db and id) then return end
	encounterID, name = R(encounterID), R(name)
	local npc = ns.NpcFromGuid(R(UnitGUID("boss1")))
	local key = npc or (encounterID and ("e" .. encounterID)) or name
	if not key then return end
	Boss(id, key, { name = name, npc = npc, encounter = encounterID })
	encounter = { id = id, key = key, enc = encounterID }
end)

ns:RegisterEvent("ENCOUNTER_END", function(_, encounterID, name, _, _, success)
	if not (ns.db and encounter) then return end
	encounterID, success = R(encounterID), R(success)
	if encounter.enc and encounterID and encounter.enc ~= encounterID then return end
	local b = Boss(encounter.id, encounter.key, { name = R(name) })
	if b then
		if success == 1 or success == true then Killed(encounter.id, encounter.key, b) b.byEncounter = true
		else b.wipes = (b.wipes or 0) + 1 end
	end
	encounter = nil
end)

-- a kill of one of this dungeon's bosses, when the game sent no encounter for it
ns:On("KILL", function(npc, crec)
	local id, iname = InstanceNow()
	if not (id and npc) then return end
	local isBoss = crec and crec.boss
	for _, d in ipairs(D:Entries(id, iname)) do
		for _, b in ipairs(d.bosses or {}) do
			if b.npc == npc and b.k ~= "t" then isBoss = true end
			if not b.npc and b.name and crec and crec.name == b.name then isBoss = true end
		end
	end
	if not isBoss then return end
	local rec = ns.Store:Get("instance", id)
	local existing = rec and rec.bosses and rec.bosses[npc]
	if existing and existing.byEncounter and existing.lastKill and time() - existing.lastKill < 30 then return end
	local b = Boss(id, npc, { name = crec and crec.name, npc = npc })
	if b then Killed(id, npc, b) end
end)

---------------------------------------------------------------------------
-- Lookups for the page
---------------------------------------------------------------------------

-- the bosses of a dungeon for the page: met ones (with their records), and counts of the rest by kind
function D:Bosses(id, rec)
	local met, seen, unmet = {}, {}, { b = 0, r = 0, e = 0 }
	for key, b in pairs(rec.bosses or {}) do
		met[#met + 1] = { key = key, b = b }
		if b.npc then seen[b.npc] = true end
		if b.name then seen[b.name] = true end
	end
	for _, d in ipairs(self:Entries(id, rec.name)) do
		for _, b in ipairs(d.bosses or {}) do
			if b.k ~= "t" then
				local creature = b.npc and ns.Store:Get("creature", b.npc)
				if (b.npc and seen[b.npc]) or (b.name and seen[b.name]) then
					-- already listed
				elseif creature then
					-- met in the Bestiary (seen inside), not yet fought as a boss here
					met[#met + 1] = { key = b.npc, b = { name = creature.name, npc = b.npc, kills = 0, wipes = 0 }, db = b }
					seen[b.npc] = true
				else
					unmet[b.k] = (unmet[b.k] or 0) + 1
				end
			end
		end
	end
	-- attach each met boss's database entry (loot), keep the records' order of bosses
	local order = {}
	for _, d in ipairs(self:Entries(id, rec.name)) do
		for n, b in ipairs(d.bosses or {}) do
			if b.npc then order[b.npc] = order[b.npc] or n end
			if b.name then order[b.name] = order[b.name] or n end
			for _, m in ipairs(met) do
				if (b.npc and m.b.npc == b.npc) or (b.name and m.b.name == b.name) then m.db = m.db or b end
			end
		end
	end
	table.sort(met, function(a, b)
		local oa = order[a.b.npc or ""] or order[a.b.name or ""] or 999
		local ob = order[b.b.npc or ""] or order[b.b.name or ""] or 999
		if oa ~= ob then return oa < ob end
		return (a.b.name or "") < (b.b.name or "")
	end)
	return met, unmet
end

-- the level range and entrance zone from the records (shown once the dungeon has been entered)
function D:Info(id, rec)
	local lo, hi, zone, raid
	for _, d in ipairs(self:Entries(id, rec.name)) do
		lo = math.min(lo or d.min, d.min)
		hi = math.max(hi or d.max, d.max)
		zone = zone or (d.zone ~= "" and d.zone or nil)
		raid = raid or d.raid
	end
	return lo, hi, zone, raid
end
