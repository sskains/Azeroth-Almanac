-- The hidden quest database (Data\Quests.lua, built from VMaNGOS by tools\build_quests.py).
-- IDs and numbers only. A quest's page uses it to link what the player has already met: the NPC
-- who takes it in (once you've met them), the creatures and items its objectives ask for (once in
-- your Bestiary or Items), and the follow-ups a completed quest leads to. Nothing here is shown
-- for a quest the player hasn't been offered.

local _, ns = ...
local QDB = ns:NewModule("QuestDB")

local cache = {}

local function Who(s)
	local out = {}
	if not s then return out end
	for part in s:gmatch("[^,]+") do
		local o, id = part:match("^(o?)(%d+)$")
		if id then out[#out + 1] = { id = tonumber(id), object = o == "o" } end
	end
	return out
end

local function Counted(s)
	local out = {}
	if not s then return out end
	for part in s:gmatch("[^,]+") do
		local o, id, n = part:match("^(o?)(%d+):(%d+)$")
		if id then out[#out + 1] = { id = tonumber(id), object = o == "o", n = tonumber(n) } end
	end
	return out
end

local function Set(s)
	local out = {}
	if not s then return out end
	for id in s:gmatch("%d+") do out[#out + 1] = tonumber(id) end
	return out
end

-- { level, minLevel, zone (area ID, or a negative category), starters, enders = { { id, object } },
--   after = { questID }, targets = { { id, object, n } }, items = { { id, n } } }, or nil
function QDB:Get(quest)
	if not quest then return nil end
	local c = cache[quest]
	if c ~= nil then return c or nil end
	local raw = ns.DB and ns.DB.quest and ns.DB.quest[quest]
	if not raw then
		cache[quest] = false
		return nil
	end
	c = {
		level = raw[1], minLevel = raw[2], zone = raw[3],
		starters = Who(raw[4]), enders = Who(raw[5]), after = Set(raw[6]),
		targets = Counted(raw[7]), items = Counted(raw[8]), races = raw[9], classes = raw[10],
	}
	cache[quest] = c
	return c
end

-- quests that lead on to this one (built on first use)
local before
function QDB:Before(quest)
	if not before then
		before = {}
		for id in pairs(ns.DB and ns.DB.quest or {}) do
			local c = self:Get(id)
			for _, nxt in ipairs(c and c.after or {}) do
				before[nxt] = before[nxt] or {}
				table.insert(before[nxt], id)
			end
		end
	end
	return before[quest] or {}
end

-- can the character you're playing take this quest (by race and class)?
local function Bit(mask, id)
	if not (mask and mask > 0 and id) then return true end
	return math.floor(mask / 2 ^ (id - 1)) % 2 == 1
end
function QDB:ForMe(quest)
	local c = self:Get(quest)
	if not c then return true end
	local _, _, raceID = UnitRace("player")
	local _, _, classID = UnitClass("player")
	return Bit(c.races, raceID) and Bit(c.classes, classID)
end

-- does the database say a leads on to b?
function QDB:Leads(a, b)
	local c = self:Get(a)
	for _, id in ipairs(c and c.after or {}) do if id == b then return true end end
	return false
end

-- quests whose objectives ask for this creature (object = false) or item: { questID }
local wants
local function Wants()
	if wants then return wants end
	wants = { npc = {}, item = {} }
	for id in pairs(ns.DB and ns.DB.quest or {}) do
		local c = QDB:Get(id)
		for _, t in ipairs(c and c.targets or {}) do
			if not t.object then
				wants.npc[t.id] = wants.npc[t.id] or {}
				table.insert(wants.npc[t.id], id)
			end
		end
		for _, t in ipairs(c and c.items or {}) do
			wants.item[t.id] = wants.item[t.id] or {}
			table.insert(wants.item[t.id], id)
		end
	end
	return wants
end
function QDB:ForTarget(npc) return Wants().npc[npc] or {} end
function QDB:ForItem(item) return Wants().item[item] or {} end
