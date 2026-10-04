-- The hidden creature database (Data\Creatures.lua, built from VMaNGOS by tools\build_creatures.py)
-- and what a player has unlocked of it. Nothing here is shown for a creature the player hasn't met.
--   Fought   (1 kill):  Classic health range, armor, melee damage per hit, money range
--   Studied  (kills):   every ability in its spell list
--   Mastered (kills):   immunities, resistances, the full loot table with drop chances, skinning
-- Evidence unlocks single facts sooner: an ability that hit you, a debuff it left, an item you
-- looted. Classic values are labelled as such; what the player observed always comes first.

local _, ns = ...
local L = ns.L
local DB = ns:NewModule("CreatureDB")

local cache = {}

local function Split(s, sep)
	local out = {}
	if not s then return out end
	for part in s:gmatch("[^" .. sep .. "]+") do out[#out + 1] = part end
	return out
end

local function Loot(s)
	local out = {}
	for _, part in ipairs(Split(s, ";")) do
		local item, bp = part:match("^(%d+):(%-?%d+)$")
		if item then
			bp = tonumber(bp)
			out[#out + 1] = { item = tonumber(item), chance = math.abs(bp) / 100, quest = bp < 0 }
		end
	end
	return out
end

-- the decoded record, or nil when the creature isn't in the Classic database (e.g. Forever's own)
function DB:Get(npc)
	if not npc then return nil end
	local c = cache[npc]
	if c ~= nil then return c or nil end
	local raw = ns.DB and ns.DB.creature and ns.DB.creature[npc]
	if not raw then
		cache[npc] = false
		return nil
	end
	c = {
		lo = raw[1], hi = raw[2], rank = raw[3], type = raw[4], family = raw[5],
		hpLo = raw[6], hpHi = raw[7], armor = raw[8], dmg = raw[9],
		spells = {}, loot = Loot(raw[11]), goldLo = raw[12], goldHi = raw[13],
		skin = Loot(raw[14]), mech = raw[15] or 0, school = raw[16] or 0, res = {},
	}
	for _, id in ipairs(Split(raw[10], ",")) do c.spells[#c.spells + 1] = tonumber(id) end
	for i, v in ipairs(Split(raw[17], ",")) do c.res[i] = tonumber(v) end
	cache[npc] = c
	return c
end

-- spell mechanics (the immunity mask has bit m-1 for mechanic m)
DB.MECHANICS = {
	[1] = L["Charm"], [2] = L["Disorient"], [3] = L["Disarm"], [4] = L["Distract"], [5] = L["Fear"],
	[6] = L["Grip"], [7] = L["Root"], [8] = L["Pacify"], [9] = L["Silence"], [10] = L["Sleep"],
	[11] = L["Snare"], [12] = L["Stun"], [13] = L["Freeze"], [14] = L["Knockout"], [15] = L["Bleed"],
	[16] = L["Bandage"], [17] = L["Polymorph"], [18] = L["Banish"], [19] = L["Shield"], [20] = L["Shackle"],
	[21] = L["Mount"], [22] = L["Persuade"], [23] = L["Turn"], [24] = L["Horror"], [25] = L["Invulnerability"],
	[26] = L["Interrupt"], [27] = L["Daze"], [28] = L["Discovery"], [29] = L["Immune shield"], [30] = L["Sap"],
}
DB.SCHOOLS = { [1] = L["Physical"], [2] = L["Holy"], [4] = L["Fire"], [8] = L["Nature"], [16] = L["Frost"], [32] = L["Shadow"], [64] = L["Arcane"] }
DB.RESIST_NAMES = { L["Holy"], L["Fire"], L["Nature"], L["Frost"], L["Shadow"], L["Arcane"] }

local function HasBit(mask, bit)
	return mask and mask > 0 and (math.floor(mask / bit) % 2) == 1
end

function DB:Immunities(c)
	local out = {}
	for m = 1, 30 do
		if HasBit(c.mech, 2 ^ (m - 1)) and self.MECHANICS[m] then out[#out + 1] = self.MECHANICS[m] end
	end
	local schools = {}
	for bit, name in pairs(self.SCHOOLS) do
		if HasBit(c.school, bit) then schools[#schools + 1] = name end
	end
	table.sort(schools)
	return out, schools
end

-- abilities the player knows about for this creature: { id = { seen = true/false } }
-- Studied reveals the whole list; before that only what the game showed (it hit you, a debuff,
-- a cast the client named) counts, plus a lone cast-time ability when it was seen casting.
function DB:KnownSpells(npc, rec, tier)
	local known, c = {}, self:Get(npc)
	for id in pairs(rec.ab or {}) do known[id] = "seen" end
	for id in pairs(rec.db or {}) do known[id] = known[id] or "seen" end
	for id in pairs(rec.cs or {}) do known[id] = known[id] or "seen" end
	local hidden = 0
	if c then
		for _, id in ipairs(c.spells) do
			if not known[id] then
				if tier >= 3 then known[id] = "studied" else hidden = hidden + 1 end
			end
		end
		-- seen casting, and it has exactly one ability: that must be it
		if tier < 3 and (rec.casts or 0) > 0 and #c.spells == 1 and not known[c.spells[1]] then
			known[c.spells[1]] = "cast"
			hidden = hidden - 1
		end
	end
	return known, math.max(hidden, 0)
end
