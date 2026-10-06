-- Saved data: everything the Almanac knows lives in AzerothAlmanacDB (account-wide).
--   settings            options (ns.defaults fills in anything missing)
--   chars[key]          each character: name, realm, class, race, faction, level, seen times, story
--   found[kind][id]     discoveries shared by all characters:
--                         f = first found (time), b = by (character key), l = last seen (time),
--                         n = times seen, plus the kind's own fields (name, map, ...)
--   journal             the timeline: { t = time, k = kind, i = id, c = character, s = text, m, x, y },
--                         oldest first, capped at settings.journalMax
-- The data has a version number; MIGRATIONS[v] upgrades version v-1 to v when the format changes.

local _, ns = ...
local L = ns.L
local Store = ns:NewModule("Store")

local VERSION = 4

local MIGRATIONS = {
	-- 2: Mastered now takes 15 kills of a normal creature (was 10); a setting left at the old
	-- default moves with it
	[2] = function(db)
		local t = db.settings and db.settings.tiers and db.settings.tiers.normal
		if t and t.mastered == 10 then t.mastered = 15 end
	end,
	-- 3: bosses and rares (rare elites, world and dungeon bosses) go Studied at 1 kill and
	-- Mastered at 3 (were 3 and 5); settings left at the old defaults move with them
	[3] = function(db)
		local tiers = db.settings and db.settings.tiers
		for _, key in ipairs({ "boss", "rare" }) do
			local t = tiers and tiers[key]
			if t and t.studied == 3 and t.mastered == 5 then t.studied, t.mastered = 1, 3 end
		end
	end,
	-- 4: the tier kills are fixed now (Bestiary.TIER_KILLS), no longer a setting
	[4] = function(db)
		if db.settings then db.settings.tiers = nil end
	end,
}

local function ApplyDefaults(target, defaults)
	for key, value in pairs(defaults) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then target[key] = {} end
			ApplyDefaults(target[key], value)
		elseif target[key] == nil then
			target[key] = value
		end
	end
end

local function Fresh()
	return { version = VERSION, created = time(), settings = {}, chars = {}, found = {}, journal = {} }
end

function Store:Load()
	local db = AzerothAlmanacDB
	if type(db) ~= "table" or not db.version then db = Fresh() end
	for v = (db.version or 1) + 1, VERSION do
		if MIGRATIONS[v] then
			local ok, err = pcall(MIGRATIONS[v], db)
			if not ok then ns.Print("could not upgrade the saved data to version " .. v .. ": " .. tostring(err)) end
		end
		db.version = v
	end
	db.settings = db.settings or {}
	db.chars = db.chars or {}
	db.found = db.found or {}
	db.journal = db.journal or {}
	ApplyDefaults(db.settings, ns.defaults)
	local build, _, _, interface = GetBuildInfo()
	db.build, db.interface = build, interface
	AzerothAlmanacDB = db
	ns.db = db
end

function Store:Reset()
	local settings, qol = ns.db.settings, ns.db.qol
	local fresh = Fresh()
	fresh.settings = settings
	fresh.qol = qol -- the helpers' settings and data (prices, bags, flight times) aren't records
	AzerothAlmanacDB = fresh
	ns.db = fresh
	ns:Fire("RESET")
	ns:Fire("CHANGED")
end

---------------------------------------------------------------------------
-- Discoveries
---------------------------------------------------------------------------

function Store:Get(kind, id)
	local list = ns.db.found[kind]
	return list and list[id]
end

function Store:All(kind)
	ns.db.found[kind] = ns.db.found[kind] or {}
	return ns.db.found[kind]
end

function Store:Count(kind)
	local n = 0
	for _ in pairs(ns.db.found[kind] or {}) do n = n + 1 end
	return n
end

-- Records that the playing character met something. fields are merged into the record (nil values
-- are ignored, so a later sighting never erases what an earlier one learned).
-- journalText: what the journal says when this is new ("Thistlefur Village, Ashenvale").
-- Returns the record and true when it's a new discovery for the account.
-- quiet: count it as found but leave it out of the journal (items you were already carrying,
-- a merchant's whole stock), so the journal stays a story rather than a list.
function Store:Discover(kind, id, fields, journalText, where, quiet)
	if id == nil then return end
	local list = self:All(kind)
	local rec = list[id]
	local now = time()
	local char = ns.CharKey()
	local isNew = rec == nil
	if isNew then
		rec = { f = now, b = char, n = 0 }
		list[id] = rec
	end
	rec.l = now
	rec.n = (rec.n or 0) + 1
	for k, v in pairs(fields or {}) do
		if v ~= nil and not ns.IsSecret(v) then rec[k] = v end
	end
	-- which characters have met it (small set of keys)
	rec.c = rec.c or {}
	if not rec.c[char] then
		rec.c[char] = now
		self:CharSeen(kind, id)
	end
	if isNew then
		if not quiet then self:AddJournal(kind, id, journalText or tostring(id), where) end
		ns:Fire("DISCOVERY", kind, id, rec, journalText, quiet)
	end
	ns:Fire("CHANGED", kind, id)
	return rec, isNew
end

-- the playing character's own "first time here" list, for character stories
function Store:CharSeen(kind, id)
	local c = ns.db.chars[ns.CharKey()]
	if not c then return end
	c.firsts = c.firsts or {}
	c.firsts[kind] = c.firsts[kind] or {}
	if not c.firsts[kind][id] then c.firsts[kind][id] = time() end
end

---------------------------------------------------------------------------
-- Journal
---------------------------------------------------------------------------

function Store:AddJournal(kind, id, text, where)
	local j = ns.db.journal
	where = where or ns.Where()
	j[#j + 1] = { t = time(), k = kind, i = id, c = ns.CharKey(), s = text, m = where.map, x = where.x, y = where.y }
	local max = ns.db.settings.journalMax or 5000
	if #j > max then
		local drop = #j - max
		for i = 1, #j - drop do j[i] = j[i + drop] end
		for i = #j - drop + 1, #j do j[i] = nil end
	end
end

---------------------------------------------------------------------------
-- Stats: counts and an estimate of the saved data's size
---------------------------------------------------------------------------

local function Weigh(v, seen)
	local t = type(v)
	if t == "string" then return #v + 4 end
	if t == "number" or t == "boolean" then return 8 end
	if t ~= "table" or seen[v] then return 0 end
	seen[v] = true
	local bytes = 8
	for k, x in pairs(v) do bytes = bytes + Weigh(k, seen) + Weigh(x, seen) + 4 end
	return bytes
end

function Store:SizeKB()
	return math.floor(Weigh(ns.db, {}) / 1024 + 0.5)
end

function Store:PrintStats()
	local parts = {}
	local kinds = {}
	for kind in pairs(ns.db.found) do kinds[#kinds + 1] = kind end
	table.sort(kinds)
	for _, kind in ipairs(kinds) do parts[#parts + 1] = kind .. " " .. self:Count(kind) end
	local chars = 0
	for _ in pairs(ns.db.chars) do chars = chars + 1 end
	ns.Print((L["%d characters. Discoveries: %s. Journal: %d entries. Saved data about %d KB."])
		:format(chars, #parts > 0 and table.concat(parts, ", ") or L["none yet"], #ns.db.journal, self:SizeKB()))
	for _, d in ipairs(ns.db.diag or {}) do
		ns.Print(("blocked: %s (%s) while %s, %s"):format(d.func or "?", d.event or "?", d.doing or "?", ns.DateTimeText(d.t)))
	end
end
