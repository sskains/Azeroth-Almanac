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

local VERSION = 5

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
	-- 5 (0.64.0): data nothing reads any more: each character's "firsts" lists, the zones' and
	-- places' old exploration fields, an art recording session
	[5] = function(db)
		for _, c in pairs(db.chars or {}) do if type(c) == "table" then c.firsts = nil end end
		for _, rec in pairs(db.found and db.found.zone or {}) do if type(rec) == "table" then rec.explored = nil end end
		for _, rec in pairs(db.found and db.found.subzone or {}) do if type(rec) == "table" then rec.area = nil end end
		db.artlog = nil
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

Store.ApplyDefaults = ApplyDefaults -- (Profiles: choices a profile didn't have go back to their defaults)

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
	-- (nor are the settings profiles, who uses which, or the blocked-action log, 0.62.0)
	fresh.profiles, fresh.profileOf, fresh.diag = ns.db.profiles, ns.db.profileOf, ns.db.diag
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

-- What the Almanac shows (Settings > General > Almanac shows): the whole account's discoveries, or
-- only what the character you're playing has met. Every record keeps who met it (rec.c), so the
-- choice only filters what's shown; recording is the same either way.
-- ns.ScopeChar(): this character's key in character mode, else nil.
function ns.ScopeChar()
	local s = ns.db and ns.db.settings
	if s and s.scope == "character" then return ns.CharKey() end
end
local shownCache = {}
ns:On("CHANGED", function(kind) if kind then shownCache[kind] = nil else wipe(shownCache) end end)
ns:On("RESET", function() wipe(shownCache) end)
function Store:ClearShown() wipe(shownCache) end
function Store:Shown(kind)
	local me = ns.ScopeChar()
	if not me then return self:All(kind) end
	local cached = shownCache[kind]
	if cached and cached.me == me then return cached.list end
	local list = {}
	for id, rec in pairs(self:All(kind)) do
		if type(rec) == "table" and ((rec.c and rec.c[me]) or rec.b == me) then list[id] = rec end
	end
	shownCache[kind] = { me = me, list = list }
	return list
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
	local newForMe = not rec.c[char] and (isNew or rec.b ~= char)
	if not rec.c[char] then rec.c[char] = now end
	if isNew then
		if not quiet then self:AddJournal(kind, id, journalText or tostring(id), where) end
		ns:Fire("DISCOVERY", kind, id, rec, journalText, quiet)
	elseif newForMe and ns.ScopeChar() then
		-- (0.63.0) a character-only Almanac: new to this character is a discovery here, with its
		-- alert and journal line, even when another character found it first
		if not quiet then self:AddJournal(kind, id, journalText or tostring(id), where) end
		shownCache[kind] = nil
		ns:Fire("DISCOVERY", kind, id, rec, journalText, quiet, true)
	end
	ns:Fire("CHANGED", kind, id)
	return rec, isNew
end

---------------------------------------------------------------------------
-- Journal
---------------------------------------------------------------------------

function Store:AddJournal(kind, id, text, where)
	local j = ns.db.journal
	where = where or ns.Where()
	j[#j + 1] = { t = time(), k = kind, i = id, c = ns.CharKey(), s = text, m = where.map, x = where.x, y = where.y }
	local max = ns.db.settings.journalMax or 5000
	-- (trimmed in chunks of 250: shifting the whole journal for every entry past the cap was slow, 0.64.0)
	if #j > max + 250 then
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
	ns.Print((L["%s. Discoveries: %s. Journal: %s. Saved data about %d KB."])
		:format(ns.N(chars, "character", "characters"), #parts > 0 and table.concat(parts, ", ") or L["none yet"], ns.N(#ns.db.journal, "entry", "entries"), self:SizeKB()))
	-- blocked actions this version (a summary, one line per function: how often, the latest time)
	local by, order = {}, {}
	for _, d in ipairs(ns.db.diag or {}) do
		local k = d.func or "?"
		if not by[k] then by[k] = { n = 0 } order[#order + 1] = k end
		by[k].n = by[k].n + 1
		by[k].last, by[k].doing = d.t, d.doing
	end
	if #order == 0 then
		ns.Print(L["No blocked actions recorded in this version."])
	else
		for _, k in ipairs(order) do
			local b = by[k]
			ns.Print((L["Blocked by the game: %s, %d times (last %s, while %s)."]):format(k, b.n, ns.DateTimeText(b.last), b.doing or "?"))
		end
	end
end

function Store:ClearBlocked()
	ns.db.diag = {}
	ns.blockedSaid = {}
	ns.Print(L["Blocked-action log cleared."])
end
