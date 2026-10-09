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
		-- (0.69.1) by name as the game may say it too: "The Hall of Thanes" finds "Hall of Thanes"
		local key = D.NameKey(d.name) or d.name
		byName[key] = byName[key] or {}
		table.insert(byName[key], d)
		for _, b in ipairs(d.bosses or {}) do
			if b.npc then bossOf[b.npc] = d end
		end
	end
end

-- the database entries for a dungeon (two for Blackrock Spire: lower and upper)
function D:Entries(id, name)
	Index()
	return byID[id] or (name and byName[D.NameKey(name) or name]) or {}
end

-- is this NPC a dungeon boss in the records?
function D:IsBoss(npc)
	Index()
	return npc and bossOf[npc] ~= nil
end

-- (0.68.3) the dungeon a boss belongs to: its records entry, and the instance key you found it under (nil if not found)
function D:DungeonOf(npc)
	Index()
	local d = npc and bossOf[npc]
	if not d then return nil end
	local shown = ns.Store:Shown("instance")
	if d.id and shown[d.id] then return d, d.id end
	for id, rec in pairs(shown) do
		if type(rec) == "table" and rec.name == d.name then return d, id end
	end
	return d, nil
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
local backfilled -- (0.65.4) D:Backfill ran this session

local function Me()
	local c = ns.db.chars[ns.CharKey()]
	if not c then return nil end
	c.runs = c.runs or {}
	return c
end

local function InstanceNow()
	local ok, name, itype, _, _, maxPlayers, _, _, id = pcall(GetInstanceInfo)
	itype, id, maxPlayers = R(itype), R(id), R(maxPlayers)
	if ok and (itype == "party" or itype == "raid") and id then return id, R(name), type(maxPlayers) == "number" and maxPlayers or nil end
end

-- (0.69.0, #45) the instance you're in now (its ID), or nil
function D:Current()
	if run then return run.id end
	return (InstanceNow())
end

-- a dungeon's name made comparable: lower case, no leading "the", letters and digits only
-- ("The Hall of Thanes" and "Hall of Thanes" match)
function D.NameKey(name)
	if type(name) ~= "string" then return nil end
	local k = name:lower():gsub("^the%s+", ""):gsub("[^%w]", "")
	return k ~= "" and k or nil
end

local function Call(fn, ...)
	if not fn then return nil end
	local ok, a = pcall(fn, ...)
	if ok then return ns.Readable(a) end
end

-- (0.69.1) where you are as a dungeon's name, for when the game won't give the instance ID (WoW
-- Forever's own dungeons, such as the Hall of Thanes, come back without one): GetInstanceInfo's name
-- while in any instance, else the zone's name; nil outside instances and dungeon zones
function D:CurrentName()
	local ok, name, itype = pcall(GetInstanceInfo)
	name, itype = ok and ns.Readable(name) or nil, ok and ns.Readable(itype) or nil
	local inside = Call(IsInInstance)
	if (inside or (itype and itype ~= "none")) and type(name) == "string" and name ~= "" then return name end
	-- (a dungeon the game treats as an ordinary zone: its zone name, if a known dungeon has it)
	local zone = Call(GetRealZoneText) or Call(GetZoneText)
	local key = D.NameKey(zone)
	if not key then return nil end
	for _, d in ipairs(ns.DB and ns.DB.dungeon or {}) do
		if D.NameKey(d.name) == key then return zone end
	end
	for _, rec in pairs(ns.Store:All("instance")) do
		if D.NameKey(rec.name) == key then return zone end
	end
end

-- is this dungeon (ID, record) the one you're in? By ID, or by name when the game gives none
function D:IsHere(id, rec)
	local cur = self:Current()
	if cur and id == cur then return true end
	local key = D.NameKey(self:CurrentName())
	return key ~= nil and key == D.NameKey(rec and rec.name)
end

-- /aa where: what the game says about where you are (for dungeons it won't name)
function D:Report()
	local out = {}
	local function S(v) if v == nil then return "nil" end if ns.IsSecret(v) then return "(secret)" end return tostring(v) end
	local r = { pcall(GetInstanceInfo) }
	local parts = {}
	for i = 2, 10 do parts[#parts + 1] = S(r[i]) end
	out[#out + 1] = "GetInstanceInfo: " .. table.concat(parts, ", ")
	local ok, a, b = pcall(IsInInstance)
	out[#out + 1] = ("IsInInstance: %s, %s"):format(S(a), S(b))
	out[#out + 1] = ("Zone: %s / %s / %s"):format(S(Call(GetRealZoneText)), S(Call(GetZoneText)), S(Call(GetMinimapZoneText)))
	local map = C_Map and C_Map.GetBestMapForUnit and Call(C_Map.GetBestMapForUnit, "player")
	local info = map and C_Map.GetMapInfo and select(2, pcall(C_Map.GetMapInfo, map))
	out[#out + 1] = ("Map: %s (%s, type %s)"):format(S(map), type(info) == "table" and S(info.name) or "?", type(info) == "table" and S(info.mapType) or "?")
	out[#out + 1] = ("Almanac: current instance %s, as a name %s"):format(S(self:Current()), S(self:CurrentName()))
	local here = {}
	for id, rec in pairs(ns.Store:Shown("instance")) do if self:IsHere(id, rec) then here[#here + 1] = (rec.name or "?") .. " (" .. tostring(id) .. ")" end end
	out[#out + 1] = "Cards that swirl: " .. (#here > 0 and table.concat(here, ", ") or "none")
	for _, l in ipairs(out) do ns.Print(l) end
end

function D:Check()
	if not ns.db then return end
	if not backfilled then pcall(D.Backfill, D) end
	local id, name, size = InstanceNow()
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
	-- (0.68.4) its group size, as the game says inside
	if id and size and size > 0 then
		local rec = ns.Store:Get("instance", id)
		if rec then rec.size = size end
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

-- A boss the game hides from addons (inside instances a creature's GUID and name are secret) gets its
-- creature record from the encounter: an existing record of the same name, or a stand-in keyed by the
-- negative encounter ID (-2732). The boss entry's npc points at it, so the page links to Creatures.
function D:BossCreature(e, b, killed)
	local B = ns.Bestiary
	if not (b and b.name and ns.Store) then return end
	local key = (type(b.npc) == "number" and b.npc) or (B and B.ByName and B:ByName(b.name)) or (e.enc and -e.enc)
	if not key then return end
	local where = ns.Where()
	local crec = ns.Store:Discover("creature", key, { name = b.name, boss = true, class = e.class, type = e.type, enc = e.enc }, b.name, where)
	if not crec then return end
	b.npc = key
	if type(e.level) == "number" then
		crec.lo = crec.lo and math.min(crec.lo, e.level) or e.level
		crec.hi = crec.hi and math.max(crec.hi, e.level) or e.level
		if e.level == -1 then crec.lo, crec.hi = -1, -1 end
	end
	if where.map then
		crec.z = crec.z or {}
		if not killed then crec.z[where.map] = (crec.z[where.map] or 0) + 1 end
		if B and B.AddSpot then B:AddSpot(crec, "spots", where) end
	end
	if not killed and not crec.display and B and B.FaceFromUnit then pcall(B.FaceFromUnit, B, "boss1", key) end
	if killed and B and B.EncounterKill then
		D.fromEncounter = true
		pcall(B.EncounterKill, B, key)
		D.fromEncounter = false
	end
end

-- (0.66.0) a boss's stand-in (-encounterID) folds into its real record once the real one is known
-- by name (its corpse was looted and named): kills are the larger of the two (the same kills were
-- usually counted on both), the dungeon's boss entry points at the real one
function D:MergeStandIn(npc, rec)
	if not (rec and rec.name and type(npc) == "number" and npc > 0) then return end
	local all = ns.Store:All("creature")
	for key, st in pairs(all) do
		if type(key) == "number" and key < 0 and type(st) == "table" and st.name == rec.name then
			rec.kills = math.max(rec.kills or 0, st.kills or 0)
			rec.kc = rec.kc or {}
			for ck, n in pairs(st.kc or {}) do rec.kc[ck] = math.max(rec.kc[ck] or 0, n) end
			rec.c = rec.c or {}
			for ck, t in pairs(st.c or {}) do if not rec.c[ck] or t < rec.c[ck] then rec.c[ck] = t end end
			if st.f and (not rec.f or st.f < rec.f) then rec.f, rec.b = st.f, st.b end
			rec.boss, rec.enc = true, st.enc
			rec.lo, rec.hi = rec.lo or st.lo, rec.hi or st.hi
			rec.class, rec.type, rec.display = rec.class or st.class, rec.type or st.type, rec.display or st.display
			for m, n in pairs(st.z or {}) do rec.z = rec.z or {} rec.z[m] = (rec.z[m] or 0) + n end
			all[key] = nil
			for _, inst in pairs(ns.Store:All("instance")) do
				for _, b in pairs(type(inst) == "table" and inst.bosses or {}) do if b.npc == key then b.npc = npc end end
			end
			if ns.Store.ClearShown then ns.Store:ClearShown() end
			ns:Fire("CHANGED", "creature", npc)
		end
	end
end

-- (0.65.4) bosses killed inside an instance before 0.65.4, with no creature behind them: made now,
-- with the kills the dungeon records hold (once a session; quiet, no journal or toast)
function D:Backfill()
	if backfilled or not ns.db then return end
	backfilled = true
	for iid, rec in pairs(ns.Store:All("instance")) do
		for key, b in pairs(type(rec) == "table" and rec.bosses or {}) do
			local enc = type(key) == "string" and tonumber(key:match("^e(%d+)$"))
			if not b.npc and b.name and enc then
				if not ns.Store:Get("creature", -enc) then
					local t = b.first and b.first.t or time()
					local crec = { f = t, b = b.first and b.first.c or ns.CharKey(), n = 1, l = b.lastKill or t,
						name = b.name, boss = true, enc = enc, c = {}, kc = {} }
					local total = 0
					for ck, c in pairs(ns.db.chars or {}) do
						local n = c.runs and c.runs[iid] and c.runs[iid].kills and c.runs[iid].kills[key]
						if n and n > 0 then crec.kc[ck] = n crec.c[ck] = t total = total + n end
					end
					crec.c[crec.b] = crec.c[crec.b] or t
					crec.kills = math.max(total, b.kills or 0)
					if b.map then crec.z = { [b.map] = 1 } end
					ns.Store:All("creature")[-enc] = crec
					if ns.Store.ClearShown then ns.Store:ClearShown() end
				end
				b.npc = -enc
			end
		end
	end
end

local encounter -- { id, key }
ns:RegisterEvent("ENCOUNTER_START", function(_, encounterID, name)
	local id = InstanceNow()
	if not (ns.db and id) then return end
	encounterID, name = R(encounterID), R(name)
	local npc = ns.NpcFromGuid(R(UnitGUID("boss1")))
	local key = npc or (encounterID and ("e" .. encounterID)) or name
	if not key then return end
	local b = Boss(id, key, { name = name, npc = npc, encounter = encounterID })
	encounter = { id = id, key = key, enc = encounterID,
		level = R(UnitLevel("boss1")), class = R(UnitClassification("boss1")), type = R(UnitCreatureType("boss1")) }
	-- (0.65.4) inside instances the game hides a creature's GUID and name, so the Bestiary can't
	-- see the boss: the encounter makes its creature record instead
	if b and not npc then pcall(D.BossCreature, D, encounter, b) end
end)

ns:RegisterEvent("ENCOUNTER_END", function(_, encounterID, name, _, _, success)
	if not (ns.db and encounter) then return end
	encounterID, success = R(encounterID), R(success)
	if encounter.enc and encounterID and encounter.enc ~= encounterID then return end
	local b = Boss(encounter.id, encounter.key, { name = R(name) })
	if b then
		if success == 1 or success == true then
			Killed(encounter.id, encounter.key, b)
			b.byEncounter = true
			if not b.npc or b.npc < 0 then pcall(D.BossCreature, D, encounter, b, true) end
		else b.wipes = (b.wipes or 0) + 1 end
	end
	encounter = nil
end)

-- a kill of one of this dungeon's bosses, when the game sent no encounter for it
ns:On("KILL", function(npc, crec)
	if D.fromEncounter then return end
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

-- (0.68.2) a dungeon's floors on Blizzard's own dungeon map art. C_Map has no dungeon maps on this
-- client, but the art is still in it: Interface\WorldMap\<folder>\<folder><floor>_<1..12> (4 x 3 tiles;
-- a few dungeons number the tiles without a floor). The floors and each boss's spot come from the
-- records (AtlasLoot Revival's data). Returns the floors in order, { name, prefix }, and the spot of each
-- record boss (keyed by its record table): { floor = index into floors, x, y in percent }.
local artFound = {}
local function HasArt(path)
	if not GetFileIDFromPath then return true end
	if artFound[path] == nil then
		local ok, file = pcall(GetFileIDFromPath, path)
		artFound[path] = ok and type(file) == "number" and not ns.IsSecret(file) and file > 0 or false
	end
	return artFound[path]
end
function D:MapFloors(id, name)
	local floors, spots, index = {}, {}, {}
	for _, d in ipairs(self:Entries(id, name)) do
		if d.folder then
			local mine = {}
			for n, fl in ipairs(d.floors or {}) do
				local prefix = "Interface\\WorldMap\\" .. d.folder .. "\\" .. d.folder .. (d.tio and "" or (fl[2] .. "_"))
				-- (Upper and Lower Blackrock Spire share one instance and one floor: listed once)
				if not index[prefix] and HasArt(prefix .. "1") then
					floors[#floors + 1] = { name = fl[1], prefix = prefix }
					index[prefix] = #floors
				end
				mine[n] = index[prefix]
			end
			for _, b in ipairs(d.bosses or {}) do
				local floor = b.x and mine[b.f or 1]
				if floor then spots[b] = { floor = floor, x = b.x * 100, y = b.y * 100 } end
			end
		end
	end
	return floors, spots
end

-- (0.68.4) a dungeon's group size: what the game said inside, else the usual Classic size
local SIZE = { zulgurub = 20, ruins_of_ahnqiraj = 20, lower_blackrock_spire = 10, upper_blackrock_spire = 10 }
function D:Size(id, rec)
	if rec and type(rec.size) == "number" and rec.size > 0 then return rec.size end
	local size
	for _, d in ipairs(self:Entries(id, rec and rec.name)) do
		local s = SIZE[d.key] or (d.raid and 40) or 5
		size = math.max(size or 0, s)
	end
	return size or 5
end
-- (0.68.5) its tier colour, as item quality: 5 green, 10 blue, 20 purple, 40 orange
local SIZE_COLOR = { { 40, "ffff8000" }, { 20, "ffa335ee" }, { 10, "ff0070dd" }, { 0, "ff1eff00" } }
function D:SizeColor(size)
	for _, e in ipairs(SIZE_COLOR) do if (size or 5) >= e[1] then return e[2] end end
end
-- "5-man", "40-man", in its tier colour unless plain
function D:SizeText(id, rec, plain)
	local size = self:Size(id, rec)
	local text = (L["%d-man"]):format(size)
	if plain then return text end
	return "|c" .. self:SizeColor(size) .. text .. "|r"
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
