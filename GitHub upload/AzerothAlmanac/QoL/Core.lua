-- Quality-of-life helpers, ported from Plus Everything (same author): the crafting profit
-- calculator, auction house scanner, Quest Targeter, gathering highlight, disenchant values,
-- merchant helpers, flights, Wings & Whispers, My Characters, group helpers, Healer Assist and
-- Gem Match. They live in their own namespace, A.QoL, with their own saved settings
-- (AzerothAlmanacDB.qol), so the modules run as they did in Plus Everything.
-- The settings window (UI\Settings.lua) holds their options.
--
-- Data rule: nothing here comes from Questie or Wowhead. Quest turn-ins and quest-item drop
-- sources are served from the Almanac's own records (NPCs and creatures this account has met,
-- with the hidden VMaNGOS quest and item databases saying which of them matter); vendor
-- materials and disenchant results are built from VMaNGOS (Data\QoLData.lua).

local ADDON, A = ...
A.QoL = A.QoL or {}
local ns = A.QoL
ns.Almanac = A

local _G = _G
_G["BINDING_NAME_CLICK AzerothAlmanacQuestTargetButton:LeftButton"] = "Target nearest selected quest mob"
_G["BINDING_NAME_CLICK AzerothAlmanacClearMarksButton:LeftButton"] = "Clear markers on nearby quest mobs"
BINDING_NAME_AZEROTHALMANAC_SETTINGS = "Open Almanac settings"
BINDING_NAME_AZEROTHALMANAC_INVENTORY = "Characters: bags, bank and gear"
BINDING_NAME_AZEROTHALMANAC_GEM_MATCH = "Gem Match"

ns.defaults = {
	questTargeter = {
		enabled = true, showCounts = true, learnFromLoot = true, markTargets = true, markNearby = true,
		markNearbyMax = 6, turnIns = true, markTurnIns = true, pingTargets = true, pingType = 1,
		pingTurnIns = false, learnedFinishers = {}, learnedFinisherIDs = {}, turnInFaces = true,
		mobFaces = true, mobIDs = {}, displayIDs = {}, clearHotkey = true, itemSources = {},
	},
	nodeHighlight = {
		enabled = true,
		types = { herb = true, ore = true, chest = true, quest = true, other = false },
		colors = {
			herb = { 1, 0.82, 0.2 }, ore = { 1, 0.82, 0.2 }, chest = { 1, 0.82, 0.2 },
			other = { 1, 0.82, 0.2 }, quest = { 0.35, 0.8, 1 },
		},
		size = 48, sound = true, soundIndex = 1, gameIcon = true, showName = true,
		style = "pulse", look = "both", range = 15, customNames = {},
	},
	auction = { autoScan = true, tooltip = true, vendor = true, age = true, average = true, stackOnShift = true, realms = {} },
	disenchant = { tooltip = true, bestHint = true, learn = true, learned = {} },
	travel = {
		bar = true, barStyle = "minimap", barLocked = false, mapTimes = true, dockPanel = true, share = true,
		flights = {}, schedules = {}, docks = {}, speed = { yards = 0, seconds = 0 },
	},
	auctionVolume = { share = true, tooltip = true, realms = {} },
	merchant = {
		repair = true, guildRepair = false, sellJunk = true, report = true, search = true, bestReward = true,
		listView = false, usableOnly = false, unlearnedOnly = false,
	},
	follow = { enabled = true, size = 22, x = -2, y = 2, icon = "Ability_Rogue_Sprint" },
	healAssist = {
		enabled = true, mode = "frames", side = "below", iconSize = 24, perRow = 6, maxRows = 5,
		locked = false, solo = false, includeSelf = true, pets = false, petCare = true, predict = true,
		combatOnly = false, showWhenHurt = true, linger = true, lingerSeconds = 5, aggroMarkers = true,
		aggroGlow = true, aggroBadge = true, buffs = false, tankFirst = true, critical = 25,
		minMissing = 50, cover = 85, alertSound = false, alertFlash = false, danger = 30, pos = nil,
	},
	crafting = { rankByDaily = true, card = true, badges = true, basis = "avg", tooltip = true, vendorPrices = {}, recipes = {} },
	inventory = { tooltip = true, alts = true, staleDays = 7, hidden = {}, chars = {}, bankTab = true, restCalibration = {} },
	games = { sound = true, share = true, mode = "timed", best = { timed = 0, moves = 0 }, guild = {} },
	wildGambit = { sound = true, ambience = true, table = "Dark", back = "Wild", practice = { w = 0, l = 0, d = 0 } },
	murloc = { allow = true, friendsOnly = false, menu = true, sound = true, records = {}, practice = { w = 0, l = 0, d = 0 } },
	social = {
		autoInvite = true, keywords = "inv, invite", inviteWhispers = true, inviteGuildChat = false,
		inviteOnlyKnown = false, acceptFriends = true, acceptGuild = true,
	},
	wings = {
		enabled = true, panel = true, panelRepeats = true, sound = true, spicy = true, landing = true,
		center = false, party = false, gemPrompt = true, rides = {}, totals = {},
	},
	partyPlates = {
		enabled = true, colorMode = "class", color = { 0.3, 0.85, 1 }, healthBar = true, emblem = true,
		roles = true, beacon = false, nameScale = 100, raid = true,
	},
	threat = {
		enabled = true, solo = true, meter = true, rows = 6, locked = false, warn = true, warnAt = 70,
		aggroAt = 100, sound = true, flash = true, plates = true, tankMode = "auto",
	},
	unitFrames = { classBadge = true, classColor = true, xpNeeded = true, xpAlways = true },
	spellRanker = { autoCheck = true, checkOnOpen = true, autoReplace = true, ignore = {} },
	talentPlanner = {
		enabled = true,         -- the Planner tab on the Talents window
		levelHint = true,       -- chat line on level up: the followed build's next talent
		glow = true,            -- that talent glows on your Primary/Secondary tab
		builds = {},            -- class -> { { name, code, order "t:i,..." }, ... }
		follow = {},            -- "Name-Realm" -> { class, name } of the build being followed
		chars = {},             -- "Name-Realm" -> { class, code, time }: each character's current talents
		trees = {},             -- classFile -> the three trees as the game has them (read from the client, merged over the data)
	},
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

---------------------------------------------------------------------------
-- The helpers the Plus Everything modules expect
---------------------------------------------------------------------------

ns.Readable = A.Readable
ns.MoneyText = A.MoneyText

function ns.Print(msg) A.Print(msg) end

function ns.IsAddOnLoaded(name)
	if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
	return IsAddOnLoaded and IsAddOnLoaded(name)
end

-- An item's quality color: r, g, b, quality
function ns.ItemQualityColor(item)
	local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local _, link, quality = getInfo(item)
	if quality == nil and type(item) == "number" and C_Item and C_Item.GetItemQualityByID then
		quality = C_Item.GetItemQualityByID(item)
	end
	if quality then
		local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
		if c and c.r then return c.r, c.g, c.b, quality end
		local fn = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor
		if fn then
			local r, g, b = fn(quality)
			if r then return r, g, b, quality end
		end
	end
	local hex = type(link) == "string" and link:match("|c%x%x(%x%x%x%x%x%x)")
	if hex then
		return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, quality
	end
	return 1, 1, 1, quality
end

ns.modules = {}
function ns:NewModule(name)
	local module = { name = name }
	self[name] = module
	tinsert(self.modules, module)
	return module
end

---------------------------------------------------------------------------
-- Quest data for the Quest Targeter and the gathering highlight, from the Almanac's records
--   ns.QuestData.quests[questID] = { [8] = "npc,npc" (who takes it back), [18] = "object,object" }
--   ns.QuestData.npcs[npcID] = { name }   (NPCs this account has met)
--   ns.QuestData.mobs[name] = npcID       (creatures in the Bestiary)
--   ns.Drops[itemName] = { { mobName, zoneName, ... }, ... }  (met creatures the item drops from)
---------------------------------------------------------------------------

local function Join(list)
	return #list > 0 and table.concat(list, ",") or nil
end

local quests = setmetatable({}, { __index = function(t, id)
	local QDB = A.QuestDB
	local q = QDB and type(id) == "number" and QDB:Get(id)
	if not q then return nil end
	local enders, objects = {}, {}
	for _, e in ipairs(q.enders or {}) do if not e.object then enders[#enders + 1] = e.id end end
	for _, o in ipairs(q.targets or {}) do if o.object then objects[#objects + 1] = o.id end end
	-- items that come from objects (chests, plants ...)
	for _, it in ipairs(q.items or {}) do
		local src = A.ItemDB and A.ItemDB:Get(it.id)
		for _, ob in ipairs(src and src.objects or {}) do objects[#objects + 1] = ob.id end
	end
	local entry = { [8] = Join(enders), [18] = Join(objects) }
	rawset(t, id, entry)
	return entry
end })

local npcs = setmetatable({}, { __index = function(_, id)
	local name = A.Quests and A.Quests.NameOf and A.Quests:NameOf(id)
	if name then return { name } end
end })

local mobs = setmetatable({}, { __index = function(_, name)
	return A.Bestiary and A.Bestiary.ByName and A.Bestiary:ByName(name) or nil
end })

ns.QuestData = { quests = quests, npcs = npcs, mobs = mobs }

local GetItemName = function(id)
	if C_Item and C_Item.GetItemNameByID then
		local ok, n = pcall(C_Item.GetItemNameByID, id)
		if ok and n then return n end
	end
	local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	return info and (info(id))
end

-- the item an objective names: an item a quest in the log asks for, or one the Almanac has seen
local itemByName = {}
local function ItemIDByName(name)
	if itemByName[name] then return itemByName[name] end
	if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and A.QuestDB then
		for i = 1, C_QuestLog.GetNumQuestLogEntries() do
			local info = C_QuestLog.GetInfo(i)
			local q = info and not info.isHeader and info.questID and A.QuestDB:Get(info.questID)
			for _, it in ipairs(q and q.items or {}) do
				if GetItemName(it.id) == name then itemByName[name] = it.id return it.id end
			end
		end
	end
	for id, rec in pairs(A.db and A.db.found and A.db.found.item or {}) do
		if rec.name == name then itemByName[name] = id return id end
	end
end

local function ZoneNames(rec)
	local out = {}
	for map in pairs(rec.z or {}) do
		local ok, info = pcall(C_Map.GetMapInfo, map)
		if ok and type(info) == "table" and info.name then out[#out + 1] = info.name end
	end
	return out
end

ns.Drops = setmetatable({}, { __index = function(_, name)
	if type(name) ~= "string" or not A.db then return nil end
	local id = ItemIDByName(name)
	local src = id and A.ItemDB and A.ItemDB:Get(id)
	if not src then return nil end
	local list = {}
	for _, d in ipairs(src.drops or {}) do
		local rec = A.Store:Get("creature", d.id)
		if rec and rec.name then
			local entry = { rec.name }
			for _, z in ipairs(ZoneNames(rec)) do entry[#entry + 1] = z end
			list[#list + 1] = entry
		end
	end
	return #list > 0 and list or nil
end })

---------------------------------------------------------------------------
-- Starting up: saved settings, then each module (an Almanac module runs this)
---------------------------------------------------------------------------

local Q = A:NewModule("QoLStarter") -- not "QoL": that name is the helpers' namespace

local function Run(method, ...)
	for _, module in ipairs(ns.modules) do
		if module[method] then
			A.doing = "starting " .. module.name
			local ok, err = pcall(module[method], module, ...)
			if not ok then A.Print("error starting " .. module.name .. ": " .. tostring(err)) end
		end
	end
end

function Q:OnInitialize(adb)
	adb.qol = type(adb.qol) == "table" and adb.qol or {}
	ApplyDefaults(adb.qol, ns.defaults)
	ns.db = adb.qol
	Run("OnInitialize", ns.db)
end

function Q:OnLogin()
	Run("OnLogin")
end

-- the records were erased: the helpers' settings and their own data stay
A:On("RESET", function()
	if A.db and ns.db then A.db.qol = ns.db end
end)
