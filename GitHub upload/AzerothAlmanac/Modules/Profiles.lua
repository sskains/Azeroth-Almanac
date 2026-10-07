-- Settings profiles (0.59.0): every character uses one profile of settings, "Shared" unless
-- you pick another in Settings > General. A profile holds the choices (on / off, colours, sizes,
-- opacity) of the Almanac and of every helper; never recorded data (discoveries, prices, flight
-- times, bags, Wild Gambit records), never the "Almanac shows" choice, and never window
-- positions, which each character keeps for itself.
--   AzerothAlmanacDB.profiles  = { [name] = { settings = {...}, qol = {...} } }  ("Shared" always)
--   AzerothAlmanacDB.profileOf = { ["Name-Realm"] = name }   (missing = "Shared")
--   AzerothAlmanacDB.chars[key].positions = { ["settings.window.point"] = {...}, ... }
-- The live settings stay where every module reads them (db.settings, db.qol): at login the
-- character's profile is laid over them, at logout they're saved back into it. Switching
-- profiles reloads the interface, so every module starts on the new settings.

local _, ns = ...
local L = ns.L
local P = {}
ns.Profiles = P

local SHARED = "Shared"

-- where windows and buttons sit: kept per character, outside any profile
local POSITIONS = {
	{ "settings", "window", "point" }, { "settings", "settingsPoint" }, { "settings", "toasts", "pos" },
	{ "settings", "minimap", "angle" }, { "settings", "nodes", "mmPos" },
	{ "qol", "healAssist", "pos" }, { "qol", "threat", "point" }, { "qol", "travel", "barPoint" },
	{ "qol", "wings", "panelPoint" },
}
local function IsPosition(root, a, b)
	for _, p in ipairs(POSITIONS) do
		if p[1] == root and p[2] == a and (p[3] == b) then return true end
	end
	return false
end

-- the helpers' tables mix choices with what they've learned: only these sub-tables are choices
local QOL_TABLES = {
	nodeHighlight = { types = true, colors = true },
	partyPlates = { color = true },
}
-- never part of a profile
local SKIP = { settings = { scope = true, journalMax = true } }
-- (0.63.0) A profile holds choices only: the keys the defaults list, plus the few the Settings
-- window sets that have no default. Anything else a module keeps (what it has learned, one-off
-- upgrade flags, records) stays out, and a profile laid over the live settings never touches it.
local EXTRA = {
	qol = { wildGambit = { allow = true, board = true, combatDock = true, difficulty = true, holidayBoards = true,
		realmSearch = true, tablePicked = true, class = true } },
	settings = {},
}
local function Defaults(root)
	if root == "settings" then return ns.defaults or {} end
	return (ns.QoL and ns.QoL.defaults) or {}
end
-- the choice keys of one table (settings.<key> or qol.<key>); nil: the whole value is the choice
local function ChoiceKeys(root, key)
	local d = Defaults(root)[key]
	local extra = EXTRA[root][key]
	if type(d) ~= "table" and not extra then return nil end
	local keys = {}
	for k, v in pairs(type(d) == "table" and d or {}) do
		if type(v) ~= "table" or root == "settings" or (QOL_TABLES[key] and QOL_TABLES[key][k]) then
			if not IsPosition(root, key, k) then keys[k] = true end
		end
	end
	for k in pairs(extra or {}) do keys[k] = true end
	return keys
end
local function Roots(root)
	local out = {}
	for k in pairs(Defaults(root)) do out[k] = true end
	for k in pairs(EXTRA[root]) do out[k] = true end
	return out
end

local function Copy(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = Copy(x) end
	return t
end

-- the live choices, as a profile
function P:Snapshot()
	local db = ns.db
	local snap = { settings = {}, qol = {} }
	for _, root in ipairs({ "settings", "qol" }) do
		local live = type(db[root]) == "table" and db[root] or {}
		for key in pairs(Roots(root)) do
			if not (SKIP[root] and SKIP[root][key]) and not IsPosition(root, key, nil) then
				local keys = ChoiceKeys(root, key)
				if keys then
					local t, src = {}, type(live[key]) == "table" and live[key] or {}
					for k in pairs(keys) do t[k] = Copy(src[k]) end
					snap[root][key] = t
				elseif type(live[key]) ~= "table" then
					snap[root][key] = live[key]
				end
			end
		end
	end
	return snap
end

-- lay a profile over the live settings: every choice it covers is replaced (one the profile
-- doesn't have goes back to its default), everything else is left as it is
local function Apply(snap)
	local db = ns.db
	if type(snap) ~= "table" then return end
	for _, root in ipairs({ "settings", "qol" }) do
		if type(db[root]) == "table" or root == "settings" then
			db[root] = db[root] or {}
			local live, part = db[root], snap[root] or {}
			for key in pairs(Roots(root)) do
				if not (SKIP[root] and SKIP[root][key]) and not IsPosition(root, key, nil) then
					local keys = ChoiceKeys(root, key)
					if keys then
						if type(part[key]) == "table" then
							live[key] = type(live[key]) == "table" and live[key] or {}
							for k in pairs(keys) do live[key][k] = Copy(part[key][k]) end
						end
					elseif part[key] ~= nil then
						live[key] = part[key]
					end
				end
			end
		end
	end
	-- (choices the profile didn't have: their defaults again; the helpers' are filled as they start)
	if ns.Store and ns.Store.ApplyDefaults then ns.Store.ApplyDefaults(db.settings, ns.defaults) end
end

local function Get(root, path)
	local t = ns.db[root]
	for i = 2, #path - 1 do
		t = type(t) == "table" and t[path[i]] or nil
	end
	return type(t) == "table" and t[path[#path]] or nil
end
local function Set(root, path, value)
	local t = ns.db[root]
	if type(t) ~= "table" then return end
	for i = 2, #path - 1 do
		if type(t[path[i]]) ~= "table" then t[path[i]] = {} end
		t = t[path[i]]
	end
	t[path[#path]] = Copy(value)
end
local function PosKey(p) return table.concat(p, ".") end

-- (called by Core when the saved data has loaded, before any module starts)
function P:Load()
	local db = ns.db
	db.profiles = type(db.profiles) == "table" and db.profiles or {}
	db.profileOf = type(db.profileOf) == "table" and db.profileOf or {}
	-- the first time: everything set so far becomes the Shared profile
	if not db.profiles[SHARED] then db.profiles[SHARED] = self:Snapshot() end
	local me = ns.CharKey()
	local name = db.profileOf[me]
	if not (name and db.profiles[name]) then name = SHARED end
	self.current = name
	Apply(db.profiles[name])
	-- this character's own window positions; a character new to the Almanac starts with every
	-- window where it first opens (not where the last character left it)
	local c = db.chars and db.chars[me]
	if c and type(c.positions) == "table" then
		for _, p in ipairs(POSITIONS) do
			local v = c.positions[PosKey(p)]
			if v ~= nil then Set(p[1], p, v) end
		end
	elseif not c then
		for _, p in ipairs(POSITIONS) do Set(p[1], p, nil) end
	end
end

-- this character's window positions, kept in its own record
function P:SavePositions()
	local c = ns.db and ns.db.chars and ns.db.chars[ns.CharKey()]
	if not c then return end
	c.positions = {}
	for _, p in ipairs(POSITIONS) do c.positions[PosKey(p)] = Copy(Get(p[1], p)) end
end

function P:Save()
	if self.skipSave or not (ns.db and self.current) then return end
	ns.db.profiles = type(ns.db.profiles) == "table" and ns.db.profiles or {}
	ns.db.profileOf = type(ns.db.profileOf) == "table" and ns.db.profileOf or {}
	ns.db.profiles[self.current] = self:Snapshot()
	self:SavePositions()
end
ns:RegisterEvent("PLAYER_LOGOUT", function() P:Save() end)

-- the profiles to choose from: Shared, this character's own (made on first use), then named ones
function P:List()
	local me = ns.CharKey()
	local out = { { key = SHARED, name = L["Shared (account)"] }, { key = me, name = L["This character"] } }
	local named = {}
	for name in pairs(ns.db.profiles or {}) do
		if name ~= SHARED and name ~= me and not name:find("%-") then named[#named + 1] = name end
	end
	table.sort(named)
	for _, name in ipairs(named) do out[#out + 1] = { key = name, name = name } end
	return out
end

function P:Label(key)
	if key == SHARED then return L["Shared (account)"] end
	if key == ns.CharKey() then return L["This character"] end
	if key:find("%-") then return ns.CharName(key, true) end
	return key
end

-- switch this character to a profile (a new one starts as a copy of the current settings)
function P:Use(key)
	if key == self.current then return end
	self:Save()
	if not ns.db.profiles[key] then ns.db.profiles[key] = Copy(ns.db.profiles[self.current]) end
	ns.db.profileOf[ns.CharKey()] = key ~= SHARED and key or nil
	self.skipSave = true -- (saved already; the reload mustn't save the old settings into the new one)
	ReloadUI()
end

function P:New(name)
	name = name and name:gsub("^%s+", ""):gsub("%s+$", "")
	if not name or name == "" or name:find("%-") or ns.db.profiles[name] then return false end
	self:Save()
	ns.db.profiles[name] = Copy(ns.db.profiles[self.current])
	self:Use(name)
	return true
end

-- copy another profile's settings into the one this character uses
function P:CopyFrom(key)
	if not ns.db.profiles[key] or key == self.current then return end
	ns.db.profiles[self.current] = Copy(ns.db.profiles[key])
	self:SavePositions() -- (the profile isn't saved over, but where the windows are still is)
	self.skipSave = true
	ReloadUI()
end

-- delete the profile in use: this character (and any other on it) goes back to Shared
function P:DeleteCurrent()
	local key = self.current
	if key == SHARED then return end
	ns.db.profiles[key] = nil
	for char, name in pairs(ns.db.profileOf) do if name == key then ns.db.profileOf[char] = nil end end
	self:SavePositions()
	self.skipSave = true
	ReloadUI()
end

-- the profiles there are to copy from (every one but the current)
function P:Others()
	local out = {}
	for key in pairs(ns.db.profiles or {}) do
		if key ~= self.current then out[#out + 1] = { key = key, name = self:Label(key) } end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end
