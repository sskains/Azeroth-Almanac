-- Characters: every character on the account that has logged in with the Almanac, and their story
-- (where and when each level was reached; first-time discoveries are kept by the Store).

local _, ns = ...
local L = ns.L
local Chars = ns:NewModule("Characters")

local function Me()
	local key = ns.CharKey()
	local c = ns.db.chars[key]
	if not c then
		c = { firstSeen = time(), levels = {} }
		ns.db.chars[key] = c
	end
	return c, key
end

local function Update()
	local c = Me()
	local name, realm = UnitFullName("player")
	c.name = name
	c.realm = realm or GetRealmName()
	c.realmName = GetRealmName()   -- the inventory records use this one
	local className, classFile = UnitClass("player")
	c.class, c.classFile = className, classFile
	local raceName, raceFile = UnitRace("player")
	c.race, c.raceFile = raceName, raceFile
	c.sex = UnitSex("player")
	c.faction = UnitFactionGroup("player")
	c.level = UnitLevel("player")
	c.lastSeen = time()
	local where = ns.Where()
	c.zone, c.map = where.zone, where.map
end

function Chars:OnLogin()
	local c = Me()
	local isNew = c.name == nil
	Update()
	c.logins = (c.logins or 0) + 1
	if isNew then
		ns.Store:AddJournal("character", ns.CharKey(), (L["%s joined the Almanac (level %d %s)"]):format(c.name or "?", c.level or 0, c.class or ""))
		ns:Fire("CHANGED", "character")
	end
end

ns:RegisterEvent("PLAYER_LEVEL_UP", function(_, level)
	local c = Me()
	level = tonumber(level) or UnitLevel("player")
	local where = ns.Where()
	c.levels[level] = { t = time(), m = where.map, x = where.x, y = where.y, z = where.zone, s = where.sub }
	c.level = level
	local text = (L["%s reached level %d in %s"]):format(c.name or "?", level, where.sub ~= "" and where.sub or where.zone or "?")
	ns.Store:AddJournal("level", level, text, where)
	ns:Fire("TOAST", "level", L["Level %d"]:format(level), where.zone or "", ns.Widgets and ns.Widgets.KindArt and ns.Widgets.KindArt("level") or nil,
		level >= 60 and 5 or level % 10 == 0 and 3 or 2)
	ns:Fire("CHANGED", "level")
end)

ns:RegisterEvent("PLAYER_LOGOUT", function()
	if ns.db then Update() end
end)

ns:RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
	if ns.db then
		local c = Me()
		local where = ns.Where()
		c.zone, c.map = where.zone, where.map
	end
end)

-- all characters, most recently played first
function Chars:List()
	local list = {}
	for key, c in pairs(ns.db.chars) do list[#list + 1] = { key = key, c = c } end
	table.sort(list, function(a, b) return (a.c.lastSeen or 0) > (b.c.lastSeen or 0) end)
	return list
end
