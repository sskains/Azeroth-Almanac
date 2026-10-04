-- The hidden item-source database (Data\Items.lua, built from VMaNGOS by tools\build_items.py).
-- An item's page only ever names sources the player has met (a creature in the Bestiary, a
-- merchant visited, an object looted); everything else is counted, never named.

local _, ns = ...
local IDB = ns:NewModule("ItemDB")

local cache = {}

local function Pairs(s)
	local out = {}
	if not s then return out end
	for part in s:gmatch("[^,]+") do
		local id, bp = part:match("^(%d+):(%d+)$")
		if id then out[#out + 1] = { id = tonumber(id), chance = tonumber(bp) / 100 } end
	end
	return out
end

local function Set(s)
	local out = {}
	if not s then return out end
	for id in s:gmatch("%d+") do out[#out + 1] = tonumber(id) end
	return out
end

-- { droppers = n, world = true when it drops from too many creatures to list, drops = { { id, chance } },
--   vendors = { npc }, quests = { questID }, objects = { { id, chance } } }, or nil
function IDB:Get(item)
	if not item then return nil end
	local c = cache[item]
	if c ~= nil then return c or nil end
	local raw = ns.DB and ns.DB.item and ns.DB.item[item]
	if not raw then
		cache[item] = false
		return nil
	end
	c = { droppers = raw[1] or 0, drops = Pairs(raw[2]), vendors = Set(raw[3]), quests = Set(raw[4]), objects = Pairs(raw[5]) }
	c.world = c.droppers > 0 and #c.drops == 0
	cache[item] = c
	return c
end

-- a lootable object's name, only for objects this account has looted from
function IDB:ObjectName(id, looted)
	if not looted then return nil end
	return ns.DB and ns.DB.object and ns.DB.object[id]
end

-- everything a lootable object (a herb, a vein, a chest, a fishing pool) can hold in the Classic
-- records: { { item, chance } }, likeliest first. Built once from the item list (only the gathering
-- page asks, and only for objects the player has looted).
local objectLoot
function IDB:ObjectLoot(obj)
	if not objectLoot then
		objectLoot = {}
		for item, raw in pairs(ns.DB and ns.DB.item or {}) do
			local s = raw[5]
			if s then
				for id, bp in s:gmatch("(%d+):(%d+)") do
					id = tonumber(id)
					local list = objectLoot[id] or {}
					objectLoot[id] = list
					list[#list + 1] = { item = item, chance = tonumber(bp) / 100 }
				end
			end
		end
		for _, list in pairs(objectLoot) do table.sort(list, function(a, b) return a.chance > b.chance end) end
	end
	return objectLoot[obj] or {}
end
