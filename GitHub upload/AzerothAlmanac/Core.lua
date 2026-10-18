-- Azeroth Almanac core: modules, events, shared helpers and the /aa command.
-- Each feature registers itself with ns:NewModule(name) and may define:
--   OnInitialize(db)   saved data is loaded and up to date (after ADDON_LOADED)
--   OnLogin()          the player is in the world (PLAYER_LOGIN)
-- Modules talk through a small message bus: ns:On("DISCOVERY", fn) / ns:Fire("DISCOVERY", ...).

local ADDON_NAME, ns = ...
local L = ns.L
AzerothAlmanac = ns -- global so Bindings.xml can reach the window

-- (2026-10-18) read from the TOC, so a version bump can't leave it behind (1.1.1 still said 1.1.0
-- here, and other players' copies were told the old number)
do
	local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	ns.VERSION = (meta and meta(ADDON_NAME, "Version")) or "1.1.1"
end
-- (0.69.0) the Almanac's own art: the logo (a closed crimson journal, its gold compass) and the journal
-- badge (the open journal, a page burning with gold writing), for journal entries
ns.ICON = "Interface\\AddOns\\AzerothAlmanac\\Media\\Logo_Almanac"
ns.JOURNAL_ICON = "Interface\\AddOns\\AzerothAlmanac\\Media\\Badge_Journal"

BINDING_HEADER_AZEROTHALMANAC = "Azeroth Almanac"
BINDING_NAME_AZEROTHALMANAC_TOGGLE = L["Open or close the Almanac"]

---------------------------------------------------------------------------
-- Settings defaults (AzerothAlmanacDB.settings)
---------------------------------------------------------------------------

ns.defaults = {
	minimap = { show = true, angle = 200 },
	window = { scale = 1, tab = "journal", scroll = 100, smooth = true },
	toasts = { enabled = true, sound = true, minTier = 1, soundTier = 2, cards = true, zone = true, subzone = true, instance = true, level = true, creature = true, tier = true, merchant = true, item = true, quest = true, trainer = true, flight = true, node = true, fishing = true, milestone = true },
	bestiary = { tooltip = true },
	-- xpShare: who gets your level and progress without being asked about it. "off", "party"
	-- (party and raid only), "known" (also guild and friends), "all" (anyone - still prompts).
	-- xpExact sends the exact experience remaining and an exact percent. On by default: an answer
	-- only ever goes to someone who asked for it and was allowed, so there is no stream of samples
	-- to round away. Off rounds the percent and drops the amount. xpAlways holds the players you
	-- ticked "Always" for, by peer key.
	peers = { share = true, tooltip = true, nudge = true, accepted = nil,
		xpAsk = true, xpShare = "known", xpExact = true, xpAlways = {} },
	nodes = { map = true, minimap = true, herb = true, ore = true, chest = true, sighted = true, size = 14, mmSize = 7, mmButton = true, tooltip = "full" },
	nav = { enabled = true, clearPin = true, eta = true, scale = 1 },
	townsfolk = { enabled = true, mapHidden = false, factionOnly = true, myClassOnly = true, continent = false, rims = false, size = 16, groups = {} },
	journalMax = 5000,
	debug = false,
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- This client hands addons "secret" values in some places (enemy health, cast bars ...).
-- They can't be compared, used as keys or turned into text. Returns the value only when it's safe.
function ns.IsSecret(v) return issecretvalue ~= nil and v ~= nil and issecretvalue(v) end
function ns.Readable(v)
	if v == nil or ns.IsSecret(v) then return nil end
	return v
end

-- (0.69.1) every chat line from the Almanac: the logo, then "Azeroth Almanac:" in the logo's crimson
ns.CHAT_PREFIX = "|T" .. ns.ICON .. ":14:14:0:0|t |cffd8342b" .. L["Azeroth Almanac"] .. ":|r "
function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(ns.CHAT_PREFIX .. tostring(msg))
end

function ns.Debug(msg)
	if ns.db and ns.db.settings.debug then ns.Print("|cff999999" .. tostring(msg) .. "|r") end
end

-- copper -> "1g 20s 5c" with the game's coin icons
-- money the way the game writes it: each amount followed by its coin (gold, silver, copper art),
-- empty coins left out. 13405 -> "1 [gold] 34 [silver] 5 [copper]"
local COINS = {
	{ 10000, "Interface\\MoneyFrame\\UI-GoldIcon" },
	{ 100, "Interface\\MoneyFrame\\UI-SilverIcon" },
	{ 1, "Interface\\MoneyFrame\\UI-CopperIcon" },
}
-- the bags' own coin art (Coin-Gold / -Silver / -Copper atlases) where the client has it
local COIN_ATLAS = { "Coin-Gold", "Coin-Silver", "Coin-Copper" }
local coinMarkup
local function CoinMarkup(i, file)
	if coinMarkup == nil then
		coinMarkup = false
		if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Coin-Gold") then coinMarkup = true end
	end
	if coinMarkup then return "|A:" .. COIN_ATLAS[i] .. ":14:14:2:0|a" end
	return "|T" .. file .. ":0:0:2:0|t"
end

function ns.MoneyText(copper)
	copper = math.floor(tonumber(copper) or 0)
	local parts = {}
	for i, coin in ipairs(COINS) do
		local n = math.floor(copper / coin[1]) % (i == 1 and math.huge or 100)
		if i == 1 then n = math.floor(copper / coin[1]) end
		if n > 0 or (i == 3 and #parts == 0) then
			parts[#parts + 1] = "|cffffffff" .. n .. "|r" .. CoinMarkup(i, coin[2])
		end
	end
	return table.concat(parts, " ")
end

-- a price as the merchant window shows it: coins, then any item or currency the merchant also
-- wants, each as its icon after the amount. cost = "i<itemID>:n;c<currencyID>:n"
function ns.CostText(price, cost)
	local parts = {}
	if (price or 0) > 0 or not cost then parts[#parts + 1] = ns.MoneyText(price or 0) end
	for part in (cost or ""):gmatch("[^;]+") do
		local kind, id, n = part:match("^(%a)(%d+):(%d+)$")
		id = tonumber(id)
		local icon
		if kind == "i" then
			local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
			if instant then
				local ok, _, _, _, _, tex = pcall(instant, id)
				icon = ok and tex or nil
			end
		elseif kind == "c" and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
			local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
			icon = ok and type(info) == "table" and info.iconFileID or nil
		end
		if n then
			parts[#parts + 1] = "|cffffffff" .. n .. "|r" .. (icon and ("|T" .. icon .. ":0:0:2:0|t") or (" " .. (kind == "i" and ("item " .. id) or ("currency " .. id))))
		end
	end
	return table.concat(parts, " ")
end

-- the client's name for a spell ID (nil when the game doesn't know it)
function ns.SpellLocal(id)
	if not id then return nil end
	local name
	if C_Spell and C_Spell.GetSpellName then
		local ok, n = pcall(C_Spell.GetSpellName, id)
		name = ok and n or nil
	elseif GetSpellInfo then
		local ok, n = pcall(GetSpellInfo, id)
		name = ok and n or nil
	end
	name = ns.Readable(name)
	return type(name) == "string" and name or nil
end

-- a Lua pattern from one of the game's own message formats ("Discovered %s: %d experience gained")
function ns.Pattern(fmt)
	if type(fmt) ~= "string" then return nil end
	fmt = fmt:gsub("%%%d?%$?d", "\1"):gsub("%%%d?%$?s", "\2")
	fmt = fmt:gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0")
	fmt = fmt:gsub("\1", "(%%d+)"):gsub("\2", "(.+)")
	return "^" .. fmt .. "$"
end

-- "Creature-0-4615-1-27150-3924-000041B7A4" -> "Creature", 3924
function ns.ParseGuid(guid)
	guid = ns.Readable(guid)
	if type(guid) ~= "string" then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	return kind, tonumber(id)
end

function ns.NpcFromGuid(guid)
	local kind, id = ns.ParseGuid(guid)
	if kind == "Creature" or kind == "Vehicle" then return id end
end

-- "Name-Realm" for the character you're playing
function ns.CharKey()
	local name, realm = UnitFullName("player")
	-- (early on - the saved data loading - the realm may not be filled in yet: the normalised
	-- name is what UnitFullName gives later, so the key is the same from the first moment)
	if not realm or realm == "" then realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or "?" end
	return (name or "?") .. "-" .. realm:gsub("%s", "")
end

function ns.ClassColor(classFile)
	local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if c and c.colorStr then return "|c" .. c.colorStr end
	return "|cffffffff"
end

-- "Zaphenat" in its class color, for a "Name-Realm" key. plain: no color (class colors are hard
-- to read on parchment).
function ns.CharName(key, plain)
	local c = key and ns.db and ns.db.chars[key]
	local name = (key or "?"):match("^([^-]+)") or key or "?"
	if plain then return name end
	return ns.ClassColor(c and c.classFile) .. name .. "|r"
end

-- "1 kill" / "5 kills"
function ns.N(n, one, many)
	n = n or 0
	return n .. " " .. (n == 1 and L[one] or L[many])
end

-- "once" / "twice" / "5 times"
function ns.Times(n)
	n = n or 0
	if n == 1 then return L["once"] end
	if n == 2 then return L["twice"] end
	return (L["%d times"]):format(n)
end

function ns.DateText(t)
	if not t then return "?" end
	return date("%b %d, %Y", t)
end

function ns.DateTimeText(t)
	if not t then return "?" end
	return date("%b %d, %Y %H:%M", t)
end

-- "just now", "5 min ago", "3 h ago", "2 days ago", or the date
function ns.AgoText(t)
	if not t then return "?" end
	local d = time() - t
	if d < 60 then return L["just now"] end
	if d < 3600 then return (L["%d min ago"]):format(math.floor(d / 60)) end
	if d < 86400 then return (L["%d h ago"]):format(math.floor(d / 3600)) end
	if d < 86400 * 14 then return (L["%s ago"]):format(ns.N(math.floor(d / 86400), "day", "days")) end
	return ns.DateText(t)
end

-- Where the player is: map, x and y in percent (one decimal), zone and subzone names.
-- (0.67.4) the skill list (professions, weapon skills): WoW Forever has C_SkillInfo; the old globals
-- (GetNumSkillLines / GetSkillLineInfo) are gone there (wowforeverguides.com, build 69913).
-- ns.NumSkillLines() and ns.SkillLine(i) -> name, isHeader, rank, maxRank (readable values only)
function ns.NumSkillLines()
	if C_SkillInfo and C_SkillInfo.GetNumSkillLines then
		local ok, n = pcall(C_SkillInfo.GetNumSkillLines)
		return ok and ns.Readable(n) or 0
	elseif GetNumSkillLines then
		local ok, n = pcall(GetNumSkillLines)
		return ok and ns.Readable(n) or 0
	end
	return 0
end
-- (2026-10-18, localization) Skill lines carry the client's own name ("Kräuterkunde"); the Almanac
-- compares and stores skills by their English name. A skill line the game gives an ID is returned
-- under its English name, and its local name is kept for display: ns.SkillLocal("Herbalism").
ns.SKILL_IDS = {
	Herbalism = 182, Mining = 186, Skinning = 393, Fishing = 356, Lockpicking = 633, Cooking = 185, ["First Aid"] = 129,
	Alchemy = 171, Blacksmithing = 164, Enchanting = 333, Engineering = 202, Leatherworking = 165, Tailoring = 197,
	Axes = 44, ["Two-Handed Axes"] = 172, Bows = 45, Guns = 46, Maces = 54, ["Two-Handed Maces"] = 160, Polearms = 229,
	Swords = 43, ["Two-Handed Swords"] = 55, Staves = 136, ["Fist Weapons"] = 473, Daggers = 173, Thrown = 176,
	Crossbows = 226, Wands = 228, Unarmed = 162, Defense = 95,
	Cloth = 415, Leather = 414, Mail = 413, ["Plate Mail"] = 293, Shield = 433,
}
local SKILL_BY_ID = {}
for name, id in pairs(ns.SKILL_IDS) do SKILL_BY_ID[id] = name end
ns.SKILL_LOCAL = {} -- English name -> the client's name, as read from the skill lines
function ns.SkillLocal(name) return name and (ns.SKILL_LOCAL[name] or name) end

-- name (English for skills the Almanac knows), isHeader, rank, max, the client's own name
function ns.SkillLine(i)
	local R = ns.Readable
	if C_SkillInfo and C_SkillInfo.GetSkillLineInfo then
		local ok, info = pcall(C_SkillInfo.GetSkillLineInfo, i)
		if ok and type(info) == "table" then
			local name = R(info.name)
			local id = R(info.skillID) or R(info.skillLineID)
			local eng = id and SKILL_BY_ID[id]
			if eng and type(name) == "string" then ns.SKILL_LOCAL[eng] = name end
			return eng or name, R(info.isHeader), R(info.rank), R(info.maxRank), name
		end
		return nil
	elseif GetSkillLineInfo then
		local ok, name, isHeader, _, rank, _, _, max = pcall(GetSkillLineInfo, i)
		if ok then return R(name), R(isHeader), R(rank), R(max) end
	end
end

function ns.Where()
	local map = ns.Readable(C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
	local x, y
	if map and C_Map.GetPlayerMapPosition then
		local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
		if ok and pos and not ns.IsSecret(pos) and pos.GetXY then
			local okXY, px, py = pcall(pos.GetXY, pos)
			px, py = okXY and ns.Readable(px), okXY and ns.Readable(py)
			if type(px) == "number" and type(py) == "number" then
				x, y = math.floor(px * 1000 + 0.5) / 10, math.floor(py * 1000 + 0.5) / 10
			end
		end
	end
	return { map = map, x = x, y = y, zone = ns.Readable(GetZoneText()), sub = ns.Readable(GetSubZoneText()) }
end

---------------------------------------------------------------------------
-- Modules and messages
---------------------------------------------------------------------------

ns.modules = {}
function ns:NewModule(name)
	local module = { name = name }
	self[name] = module
	tinsert(self.modules, module)
	return module
end

local listeners = {}
function ns:On(message, fn)
	listeners[message] = listeners[message] or {}
	tinsert(listeners[message], fn)
end
function ns:Fire(message, ...)
	for _, fn in ipairs(listeners[message] or {}) do
		local ok, err = pcall(fn, ...)
		if not ok then ns.Debug("listener error (" .. message .. "): " .. tostring(err)) end
	end
end

-- Game events for modules: ns:RegisterEvent("ZONE_CHANGED", fn). One shared frame.
local eventFrame = CreateFrame("Frame")
local handlers = {}
function ns:RegisterEvent(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
		if not ok then ns.Debug("event not available: " .. event) end
	end
	tinsert(handlers[event], fn)
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

-- When the game blocks something and blames the Almanac, write down which function it was and
-- what the Almanac was doing (ns.doing), so it can be fixed. /aa stats shows the count.
ns.doing = "starting"
local function Blocked(event, addon, func)
	if addon ~= ADDON_NAME or not ns.db then return end
	ns.db.diag = ns.db.diag or {}
	local list = ns.db.diag
	-- the latest 30 (the oldest drop off, so a fresh block is always there to read)
	while #list >= 30 do table.remove(list, 1) end
	list[#list + 1] = { t = time(), event = event, func = tostring(func), doing = ns.doing, combat = InCombatLockdown and InCombatLockdown() or nil, v = ns.VERSION }
	-- said once per function per session (the map can trigger the same block many times a fight)
	ns.blockedSaid = ns.blockedSaid or {}
	if ns.blockedSaid[tostring(func)] then return end
	ns.blockedSaid[tostring(func)] = true
	ns.Print(("|cffff6060the game blocked %s while the Almanac was %s.|r This is recorded for fixing."):format(tostring(func), tostring(ns.doing)))
end
eventFrame:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		if ... == ADDON_NAME then
			ns.Store:Load()
			-- this character's settings profile over the live settings, before any module starts
			if ns.Profiles then
				local ok, err = pcall(ns.Profiles.Load, ns.Profiles)
				if not ok then ns.Print("settings profile: " .. tostring(err)) end
			end
			for _, module in ipairs(ns.modules) do
				if module.OnInitialize then
					local ok, err = pcall(module.OnInitialize, module, ns.db)
					if not ok then ns.Print("error starting " .. module.name .. ": " .. tostring(err)) end
				end
			end
		end
	elseif event == "PLAYER_LOGIN" then
		-- blocked-action reports from older versions are history (their causes were fixed since):
		-- keep only this version's
		if ns.db and type(ns.db.diag) == "table" then
			local keep = {}
			for _, d in ipairs(ns.db.diag) do if d.v == ns.VERSION then keep[#keep + 1] = d end end
			ns.db.diag = keep
		end
		for _, module in ipairs(ns.modules) do
			if module.OnLogin then
				local ok, err = pcall(module.OnLogin, module)
				if not ok then ns.Print("error starting " .. module.name .. ": " .. tostring(err)) end
			end
		end
	end
	for _, fn in ipairs(handlers[event] or {}) do
		local ok, err = pcall(fn, event, ...)
		if not ok then ns.Debug(event .. ": " .. tostring(err)) end
	end
end)
ns:RegisterEvent("ADDON_ACTION_FORBIDDEN", Blocked)
ns:RegisterEvent("ADDON_ACTION_BLOCKED", Blocked)

---------------------------------------------------------------------------
-- /aa
---------------------------------------------------------------------------

local PAGE_ALIASES = {
	journal = "journal", j = "journal",
	bestiary = "bestiary", beasts = "bestiary", creatures = "bestiary",
	items = "items", item = "items",
	quests = "quests", quest = "quests",
	merchants = "townsfolk", merchant = "townsfolk", vendors = "townsfolk",
	people = "townsfolk", townsfolk = "townsfolk", npcs = "townsfolk",
	places = "places", zones = "places", place = "places",
	dungeons = "dungeons", dungeon = "dungeons", raids = "dungeons", raid = "dungeons", instances = "dungeons",
	characters = "characters", chars = "characters", alts = "characters",
	trainers = "townsfolk", trainer = "townsfolk", spells = "townsfolk", recipes = "trainers", recipe = "trainers", professions = "trainers",
	gathering = "gathering", gather = "gathering", herbs = "gathering", ore = "gathering", fishing = "gathering",
}

-- (Never assign the game's own globals, not even "X = X or {}": that taints them and the game then
-- blocks its own protected actions and blames the Almanac. Only add our own key.)
StaticPopupDialogs.AZEROTHALMANAC_RESET = {
	text = L["Erase everything the Almanac has recorded, for every character? This can't be undone."],
	button1 = YES or "Yes",
	button2 = NO or "No",
	OnAccept = function() ns.Store:Reset() ns.Print(L["All records erased."]) end,
	timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
}

local DEV_COMMANDS = { toast = true, wgdungeon = true, cardtoast = true, ringzoom = true, rangeprobe = true }

-- (dev, /aa debug) Everything this client might answer about how far away a unit is, in one go.
-- The chat box takes one command per line and caps at 255 characters, so a battery of /dump lines
-- cannot be pasted; this runs them all against your target (or "/aa rangeprobe mouseover"), prints
-- them and keeps them in saved variables, where a whole run can be read after a /reload instead of
-- being scrolled through. Nothing here is used by the addon: it is for finding out whether WoW
-- Forever offers anything Blizzard's client does not.
--
-- Each step writes its name into the log before it runs, so if one of them takes the whole function
-- down the log still says which. That is not hypothetical: a first version died silently after
-- UnitDistanceSquared, and a pcall did not catch it - the game raises a few of its refusals in a way
-- that pcall cannot hold. The order below is deliberate for the same reason: the answers that cost
-- nothing and cannot be refused come first.
function ns.RangeProbe(unit)
	unit = (unit and unit ~= "" and unit) or "target"
	if not UnitExists(unit) then ns.Print("rangeprobe: nothing at " .. tostring(unit)) return end
	local log = {}
	ns.db.probe = { at = date("%Y-%m-%d %H:%M:%S"), unit = unit, name = UnitName(unit), lines = log }
	ns.Print(("|cff9be36brangeprobe|r %s: %s (combat %s)")
		:format(unit, tostring(UnitName(unit)), tostring(InCombatLockdown and InCombatLockdown())))

	-- run one step: its name goes in first, so a step that kills the function names itself
	local function Step(name, fn)
		local at = #log + 1
		log[at] = name .. " = (did not return)"
		local res = { pcall(fn) }
		local out = {}
		for i = 2, #res do out[#out + 1] = tostring(res[i]) end
		log[at] = ("%s = %s%s"):format(name, res[1] and "" or "ERROR ", #out > 0 and table.concat(out, ", ") or "-")
		ns.Print(("|cffffd100%s|r  %s"):format(name, log[at]:match("= (.*)$") or "-"))
	end

	local npcID
	do
		local guid = UnitGUID(unit)
		if guid then npcID = tonumber((select(6, strsplit("-", guid)))) end
	end
	Step("guid / npcID", function() return UnitGUID(unit), npcID end)

	-- 1. ClosestUnitPosition is the only thing on this client that offers a distance outright. Its own
	-- error message gives the signature: local xPos, yPos, distance = ClosestUnitPosition(creatureID).
	-- Called with the targeted creature's id it returned nothing at all, so something else decides
	-- whether it answers. These ask it about the target, about every creature with a nameplate up, and
	-- about a couple of ids that are certainly around, and count what comes back.
	local function Closest(id)
		local r = { ClosestUnitPosition(id) }
		if #r == 0 then return "no answer (0 values)" end
		return unpack(r)
	end
	Step("ClosestUnitPosition(target npcID)", function() return Closest(npcID) end)
	Step("ClosestUnitPosition for each plated creature", function()
		local out = {}
		for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
			local u = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
			local g = u and UnitGUID(u)
			local id = g and tonumber((select(6, strsplit("-", g))))
			if id then
				local r = { ClosestUnitPosition(id) }
				out[#out + 1] = ("%s[%d]=%s"):format(tostring(UnitName(u)), id,
					#r == 0 and "none" or table.concat({ tostring(r[1]), tostring(r[2]), tostring(r[3]) }, "/"))
			end
		end
		return #out > 0 and table.concat(out, " ") or "no plates"
	end)
	Step("ClosestUnitPosition(player npcID 0/1)", function()
		return "0:", Closest(0), "1:", Closest(1)
	end)

	-- 2. the bands, and what they are worth. IsActionInRange exists; the sweep that failed last time
	-- died on GetSpellInfo, which this client has moved to C_Spell.GetSpellInfo.
	Step("CheckInteractDistance 1-5 (28/11.1/9.9/28 yd)", function()
		local r = {}
		for i = 1, 5 do r[i] = tostring(CheckInteractDistance(unit, i)) end
		return unpack(r)
	end)
	Step("IsActionInRange slots that answer", function()
		local SpellName = (C_Spell and C_Spell.GetSpellInfo) and function(id)
			local i = C_Spell.GetSpellInfo(id)
			return i and i.name or id
		end or function(id) return id end
		local out = {}
		for slot = 1, 120 do
			if HasAction(slot) then
				local r = IsActionInRange(slot, unit)
				if r ~= nil then
					local kind, id = GetActionInfo(slot)
					out[#out + 1] = ("%s=%s"):format(tostring(kind == "spell" and SpellName(id) or id), tostring(r))
				end
			end
		end
		return #out > 0 and table.concat(out, " ") or "no slot answered"
	end)
	Step("spell ranges known to the client", function()
		if not (C_Spell and C_Spell.GetSpellInfo) then return "no C_Spell.GetSpellInfo" end
		local out = {}
		for slot = 1, 120 do
			if HasAction(slot) then
				local kind, id = GetActionInfo(slot)
				if kind == "spell" then
					local i = C_Spell.GetSpellInfo(id)
					local mn, mx = C_Spell.GetSpellRange and C_Spell.GetSpellRange(id)
					if i and (mx or 0) > 0 then out[#out + 1] = ("%s %s-%s"):format(i.name, tostring(mn), tostring(mx)) end
				end
			end
		end
		return #out > 0 and table.concat(out, ", ") or "no ranged actions"
	end)

	-- 3. for the record, at whatever distance this run was taken
	Step("UnitPosition(player)", function() return UnitPosition("player") end)
	Step("nameplate scale (constant here: 0.768 near and far)", function()
		local plate = C_NamePlate.GetNamePlateForUnit(unit)
		return plate and plate:GetScale() or "no plate"
	end)

	ns.Print("|cff9be36bsaved|r - /reload and the whole run is in AzerothAlmanacDB.probe")
end

SLASH_AZEROTHALMANAC1 = "/aa"
SLASH_AZEROTHALMANAC2 = "/almanac"
SlashCmdList.AZEROTHALMANAC = function(msg)
	local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()
	ns.doing = "running /aa " .. cmd
	-- (the tools for working on the addon answer only with /aa debug on, 0.64.0)
	if DEV_COMMANDS[cmd] and not ns.db.settings.debug then
		ns.Print(L["that's a developer command: /aa debug turns them on."])
		return
	end
	if cmd == "" then
		ns.UI:Toggle()
	elseif (cmd == "people" or cmd == "townsfolk" or cmd == "tf") and rest:lower() == "check" then
		-- (before the page names: "people" opens the page, "people check" tests the map position)
		ns.Townsfolk:Check()
	elseif cmd == "help" or cmd == "?" then
		ns.Help()
	elseif cmd == "journey" then
		-- (#46, #49) /aa journey: the Characters page's Journey tab; /aa journey sounds | sound <name> <id>
		if rest == "" then
			ns.UI:Open("characters")
			local p = ns.UI:GetPage("characters")
			if p and p.ShowJourney then p:ShowJourney() end
		elseif ns.Journey and ns.Journey.Command then
			ns.Journey.Command(rest)
		end
	elseif PAGE_ALIASES[cmd] == "bestiary" and rest ~= "" then
		local page = ns.UI:GetPage("bestiary")
		local npc = page and page:Find(rest)
		if npc then page:ShowCreature(npc) else ns.Print((L["No creature called \"%s\" in your Almanac yet."]):format(rest)) end
	elseif PAGE_ALIASES[cmd] then
		ns.UI:Open(PAGE_ALIASES[cmd])
	elseif cmd == "options" or cmd == "settings" or cmd == "config" or cmd == "set" then
		ns.Settings:Open(rest)
	elseif cmd == "tf" then
		ns.Settings:Open("townsfolk")
	elseif cmd == "scan" then
		ns.QoL.AuctionPrices:StartScan()
	elseif cmd == "ahpost" then
		if ns.QoL.AuctionPost then ns.QoL.AuctionPost:Status() end
	elseif cmd == "inv" or cmd == "inventory" or cmd == "bags" then
		ns.QoL.InventoryWindow:Toggle()
	elseif cmd == "games" or cmd == "game" or cmd == "gems" then
		ns.QoL.GemMatch:Toggle()
	elseif cmd == "version" or cmd == "ver" or cmd == "v" then
		if rest == "quest" then
			ns.UpdateQuest:Preview()
		else
			ns.Print(("version |cffffffff%s|r  -  %s"):format(ns.VERSION, (L["%s known"]):format(ns.N(ns.Peers and ns.Peers:Count() or 0, "other Almanac player", "other Almanac players"))))
		end
	elseif cmd == "gambit" or cmd == "wild" or cmd == "wildgambit" then
		ns.QoL.WildGambit:Command(rest)
	elseif cmd == "mtt" or cmd == "murloc" or cmd == "tictactoe" or cmd == "ttt" then
		ns.QoL.MurlocTacToe:Command(rest)
	elseif cmd == "heal" or cmd == "healer" then
		if rest == "" then ns.Settings:Open("healer") else ns.QoL.HealAssist:Command(rest) end
	elseif cmd == "talents" or cmd == "talent" or cmd == "planner" then
		if rest == "probe" then ns.QoL.TalentPlanner:ProbeTalents() else ns.QoL.TalentPlanner:Open() end
	elseif cmd == "ranks" or cmd == "rank" then
		ns.QoL.SpellRanker:Check()
	elseif cmd == "rankignore" then
		ns.QoL.SpellRanker:Ignore(rest)
	elseif cmd == "lore" or cmd == "beastlore" then
		-- (2026-10-14) what the last Beast Lore read off the tooltip
		ns.Bestiary:LoreReport()
	elseif cmd == "manacheck" then
		-- (2026-10-15) a probe for the druid mana bar in forms
		ns.QoL.UnitFrames:ManaCheck()
	elseif cmd == "threat" then
		ns.QoL.ThreatMonitor:Preview()
	elseif cmd == "wings" then
		ns.QoL.WingsWhispers:Sample()
	elseif cmd == "node" then
		ns.QoL.NodeHighlight:ClassifyCurrent(rest:lower())
	elseif cmd == "stats" then
		ns.Store:PrintStats()
	elseif cmd == "minimap" then
		ns.MinimapButton:SetShown(not ns.db.settings.minimap.show)
	elseif cmd == "navprobe" then
		if ns.NavArrow and ns.NavArrow.Probe then ns.NavArrow:Probe(rest) end
	elseif cmd == "welcome" then
		if ns.Welcome then ns.Welcome:Show(1) end
	elseif cmd == "where" then
		-- (0.69.1) what the game says about where you are (dungeons it won't name)
		if ns.Dungeons and ns.Dungeons.Report then ns.Dungeons:Report() end
	elseif cmd == "nodes" or cmd == "gathermap" then
		local m = ns.db.settings.nodes
		if rest == "button" then
			m.mmButton = true
			ns.NodePins:ResetMiniButton()
			ns.NodePins:Refresh()
			ns.Print(L["Gathering button put back on the minimap, next to the Almanac's button."])
		else
			m.minimap = not m.minimap
			ns.NodePins:Refresh()
			ns.Print(m.minimap and L["Gathering nodes shown on the minimap."] or L["Gathering nodes hidden on the minimap."])
		end
	elseif cmd == "debug" then
		ns.db.settings.debug = not ns.db.settings.debug
		ns.Print("debug " .. (ns.db.settings.debug and "on" or "off"))
	-- (0.70.0) The art commands (art, atlascheck, ejscan, whatis, cards) and Modules\ArtScan.lua
	-- went with the first public build: they catalogued the game's art while the Almanac was being
	-- written, and nothing a player does reaches them.
	elseif cmd == "toast" then
		if ns.Toast then ns.Toast:Test() end
	elseif cmd == "ringzoom" then
		if ns.Widgets and ns.Widgets.SetRingZoom then ns.Widgets.SetRingZoom(rest) end
	elseif cmd == "cardtoast" then
		if ns.CardToast then ns.CardToast:Test(rest) end
	elseif cmd == "wgdungeon" then
		if ns.WildGambit and ns.WildGambit.DebugDungeon then ns.WildGambit:DebugDungeon(rest) end
	elseif cmd == "rangeprobe" then
		ns.RangeProbe(rest)
	elseif cmd == "reset" then
		StaticPopup_Show("AZEROTHALMANAC_RESET")
	else
		if cmd ~= "" then ns.Print((L["no command \"%s\"."]):format(cmd)) end
		ns.Help()
	end
end

-- /aa help (and any command it doesn't know)
function ns.Help()
	ns.Print(L["commands:"])
	ns.Print("/aa - " .. L["open or close the Almanac"])
	ns.Print("/aa journal | characters | creatures | items | quests | gathering | places | dungeons | people | spells - " .. L["open a page"])
	ns.Print("/aa creatures <name> - " .. L["open Creatures on a creature (/aa bestiary works too)"])
	ns.Print("/aa settings [page] - " .. L["the settings window"])
	ns.Print("/aa people check - " .. L["test the map position of the NPC you're talking to"])
	ns.Print("/aa tf - " .. L["settings for people on the world map"])
	ns.Print("/aa scan - " .. L["full auction house scan (auction house open)"])
	ns.Print("/aa inv - " .. L["Characters page on the Bags tab: every character's bags, bank and gear"])
	ns.Print("/aa version [quest] - " .. L["which version of Azeroth Almanac is loaded (quest: preview the update quest)"])
	ns.Print("/aa games - " .. L["Gem Match"])
	ns.Print("/aa gambit [Name|new|tutorial|leave] - " .. L["Wild Gambit, the creature card game (practice, or challenge another Almanac player)"])
	ns.Print("/aa mtt [name|target|practice|leave|ping name|debug] - " .. L["Murloc Tac Toe: challenge another Azeroth Almanac player, or practise against a gnoll"])
	ns.Print("/aa heal [test|debug|on|off] - " .. L["Healer Assist"])
	ns.Print("/aa node herb|ore|chest|other|reset - " .. L["classify the node you're facing"])
	ns.Print("/qt - " .. L["quest tracker target buttons (/qt help)"])
	ns.Print("/aa stats - " .. L["what has been recorded, and how big the saved data is"])
	ns.Print("/aa lore - " .. L["what your last Beast Lore read about a beast"])
	ns.Print("/aa talents - " .. L["Talent Planner (the Planner tab on your Talents window)"])
	ns.Print("/aa minimap - " .. L["show or hide the minimap button"])
	ns.Print("/aa nodes [button] - " .. L["show or hide gathering nodes on the minimap (button: put the minimap button back)"])
	ns.Print("/aa reset - " .. L["erase all records (asks first)"])
end
