-- Almanac Probe: a test addon for Azeroth Almanac.
-- The combat log is off-limits to addons on this client, so this checks every other source that could
-- describe the creatures you meet, and records how often each one gives a usable value or a hidden
-- ("secret") one, in combat and out of it. Nothing is shown during play except one login line.
--   /aap report    what each source gave (also saved to AlmanacProbeDB for reading outside the game)
--   /aap meter     which damage meter views returned something (full copies go to the saved file)
--   /aap world     which world checks (gossip, quest text, books, merchants, trainers, zones, factions,
--                  flight maps, services, level-ups, deaths, gathering/fishing loot) saved something
--   /aap model     shows your target's 3D model by NPC id; /aap model2 <id> tries it with no target
--   /aap creatures what was learned per creature, from in-game sources only
--   /aap reset     start over
--   /aap testlog   try registering the combat log and switching logging on (both blocked: popups)
-- Every read is wrapped so a blocked or missing function is recorded instead of erroring.

local ADDON = ...
local db
local inCombat = false
local f = CreateFrame("Frame")

local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffAlmanac Probe:|r " .. msg) end

---------------------------------------------------------------------------
-- Secret-safe helpers
---------------------------------------------------------------------------

local function IsSecret(v) return issecretvalue ~= nil and v ~= nil and issecretvalue(v) end

-- "secret", "nil" or "ok"
local function State(v)
	if v == nil then return "nil" end
	if IsSecret(v) then return "secret" end
	return "ok"
end

local function Safe(v)
	if v == nil then return nil end
	if IsSecret(v) then return nil end
	return v
end

local function Text(v)
	if v == nil then return "nil" end
	if IsSecret(v) then return "<secret>" end
	local s = tostring(v)
	if #s > 80 then s = s:sub(1, 80) .. "..." end
	return s
end

-- A copy of a returned value with hidden parts marked, for the saved file.
local function Dump(v, depth)
	if IsSecret(v) then return "<secret>" end
	if type(v) ~= "table" then
		if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then return v end
		return tostring(v)
	end
	if (depth or 0) <= 0 then return "<table>" end
	local out, n = {}, 0
	for k, x in pairs(v) do
		n = n + 1
		if n > 25 then out["..."] = "more entries"; break end
		local key = IsSecret(k) and ("<secret key " .. n .. ">") or k
		if type(key) ~= "string" and type(key) ~= "number" then key = tostring(key) end
		out[key] = Dump(x, depth - 1)
	end
	return out
end

---------------------------------------------------------------------------
-- Tally: db.tests[test][field .. "@in" / "@out"] = { ok = n, secret = n, none = n, samples = {...} }
---------------------------------------------------------------------------

local function Note(test, field, v)
	local t = db.tests[test]
	if not t then t = {} db.tests[test] = t end
	local key = field .. (inCombat and "@in" or "@out")
	local s = t[key]
	if not s then s = { ok = 0, secret = 0, none = 0, samples = {} } t[key] = s end
	local st = State(v)
	if st == "ok" then
		s.ok = s.ok + 1
		if #s.samples < 4 then
			local text = Text(v)
			local dup = false
			for _, x in ipairs(s.samples) do if x == text then dup = true break end end
			if not dup then s.samples[#s.samples + 1] = text end
		end
	elseif st == "secret" then
		s.secret = s.secret + 1
	else
		s.none = s.none + 1
	end
	return Safe(v)
end

local function Event(name) db.events[name] = (db.events[name] or 0) + 1 end

local function Try(test, fn, ...)
	if not fn then
		db.missing[test] = true
		return false
	end
	local ok, a, b, c, d, e, g, h, i, j, k = pcall(fn, ...)
	if not ok then
		db.errors[test] = Text(a)
		return false
	end
	return true, a, b, c, d, e, g, h, i, j, k
end

---------------------------------------------------------------------------
-- Creatures learned from in-game sources (keyed by NPC id, else by name)
---------------------------------------------------------------------------

local function NpcFromGuid(guid)
	if type(guid) ~= "string" then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
	return tonumber(id)
end

local function Creature(guid, name)
	local npc = NpcFromGuid(guid)
	if npc and type(name) == "string" then db.nameToNpc[name] = npc end
	local key = npc or (type(name) == "string" and (db.nameToNpc[name] or name))
	if not key then return nil end
	local c = db.creatures[key]
	if not c then
		c = { spells = {}, auras = {}, levels = {}, maps = {} }
		db.creatures[key] = c
	end
	if type(name) == "string" and not c.name then c.name = name end
	return c
end

local function PlayerMap()
	local ok, map = Try("C_Map.GetBestMapForUnit", C_Map and C_Map.GetBestMapForUnit, "player")
	return ok and Safe(map) or nil
end

---------------------------------------------------------------------------
-- 1. Unit info: target, mouseover, nameplates
---------------------------------------------------------------------------

local function ReadUnit(unit, why)
	local ok, exists = Try("UnitExists", UnitExists, unit)
	if not ok or Safe(exists) ~= true then return end
	local _, isPlayer = Try("UnitIsPlayer", UnitIsPlayer, unit)
	if Safe(isPlayer) == true then return end
	local test = "unit:" .. why
	local _, guid = Try("UnitGUID", UnitGUID, unit)
	guid = Note(test, "guid", guid)
	if type(guid) == "string" and not guid:find("^Creature") and not guid:find("^Vehicle") then return end
	local _, name = Try("UnitName", UnitName, unit)
	name = Note(test, "name", name)
	local _, level = Try("UnitLevel", UnitLevel, unit)
	level = Note(test, "level", level)
	local _, hp = Try("UnitHealth", UnitHealth, unit)
	Note(test, "health", hp)
	local _, hpMax = Try("UnitHealthMax", UnitHealthMax, unit)
	hpMax = Note(test, "healthMax", hpMax)
	local _, class = Try("UnitClassification", UnitClassification, unit)
	class = Note(test, "classification", class)
	local _, ctype = Try("UnitCreatureType", UnitCreatureType, unit)
	ctype = Note(test, "creatureType", ctype)
	local _, family = Try("UnitCreatureFamily", UnitCreatureFamily, unit)
	family = Note(test, "creatureFamily", family)
	local _, reaction = Try("UnitReaction", UnitReaction, unit, "player")
	reaction = Note(test, "reaction", reaction)
	local _, powerMax = Try("UnitPowerMax", UnitPowerMax, unit)
	Note(test, "powerMax", powerMax)
	local _, dead = Try("UnitIsDead", UnitIsDead, unit)
	Note(test, "dead", dead)

	local c = Creature(guid, name)
	if not c then return end
	c.seen = (c.seen or 0) + 1
	if type(level) == "number" then c.levels[level] = true end
	if type(hpMax) == "number" and hpMax > 1 then
		c.hpLo = math.min(c.hpLo or hpMax, hpMax)
		c.hpHi = math.max(c.hpHi or hpMax, hpMax)
	end
	if class then c.class = class end
	if ctype then c.type = ctype end
	if family then c.family = family end
	if reaction then c.reaction = reaction end
	local map = PlayerMap()
	if map then c.maps[map] = true end
	if guid then c.guidOk = true end
end

-- Tooltip lines for a unit (only when not fighting, to keep it cheap)
local function ReadTooltip(unit)
	if inCombat or not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return end
	local ok, data = Try("C_TooltipInfo.GetUnit", C_TooltipInfo.GetUnit, unit)
	if not ok or type(data) ~= "table" or IsSecret(data) then return end
	local lines = Safe(data.lines)
	if type(lines) ~= "table" then return end
	for i, line in ipairs(lines) do
		local text = Note("tooltip", "line" .. math.min(i, 5), line.leftText)
		if i == 1 and #db.samples.tooltip < 6 and type(text) == "string" then
			local all = {}
			for _, l in ipairs(lines) do all[#all + 1] = Text(l.leftText) end
			db.samples.tooltip[#db.samples.tooltip + 1] = table.concat(all, " | ")
		end
	end
end

---------------------------------------------------------------------------
-- 2. Enemy casts: spell-cast events and cast bars
---------------------------------------------------------------------------

local castStart = {}

local function IsEnemyUnit(unit)
	return type(unit) == "string" and (unit:find("^nameplate") or unit == "target" or unit == "focus" or unit:find("^boss"))
end

local function OnCast(event, unit, castGUID, spellID)
	if not IsEnemyUnit(unit) then return end
	local _, isPlayer = Try("UnitIsPlayer", UnitIsPlayer, unit)
	if Safe(isPlayer) == true then return end
	local test = "cast:" .. event
	spellID = Note(test, "spellID", spellID)
	Note(test, "castGUID", castGUID)
	local _, guid = Try("UnitGUID", UnitGUID, unit)
	guid = Note(test, "casterGUID", guid)
	local _, name = Try("UnitName", UnitName, unit)
	name = Note(test, "casterName", name)

	local interruptible
	if event == "UNIT_SPELLCAST_START" and UnitCastingInfo then
		local ok, cname, _, _, startMs, endMs, _, _, notInterruptible, cid = Try("UnitCastingInfo", UnitCastingInfo, unit)
		if ok then
			Note("castbar", "name", cname)
			Note("castbar", "spellID", cid)
			startMs, endMs = Note("castbar", "startTime", startMs), Note("castbar", "endTime", endMs)
			notInterruptible = Note("castbar", "notInterruptible", notInterruptible)
			if type(notInterruptible) == "boolean" then interruptible = not notInterruptible end
			if type(startMs) == "number" and type(endMs) == "number" then
				castStart["ms|" .. tostring(guid) .. tostring(spellID)] = endMs - startMs
			end
			if not spellID then spellID = Safe(cid) end
		end
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" and UnitChannelInfo then
		local ok, cname, _, _, _, _, _, notInterruptible, cid = Try("UnitChannelInfo", UnitChannelInfo, unit)
		if ok then
			Note("channelbar", "name", cname)
			Note("channelbar", "spellID", cid)
			Note("channelbar", "notInterruptible", notInterruptible)
			if not spellID then spellID = Safe(cid) end
		end
	end

	if not spellID then return end
	local c = Creature(guid, name)
	if not c then return end
	local s = c.spells[spellID]
	if not s then
		s = { casts = 0 }
		c.spells[spellID] = s
		local ok, info = Try("C_Spell.GetSpellInfo", C_Spell and C_Spell.GetSpellInfo, spellID)
		if ok and type(info) == "table" then s.name = Safe(info.name) end
	end
	if event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_CHANNEL_START" then s.casts = s.casts + 1 end
	if interruptible ~= nil then s.interruptible = interruptible end
	local ms = castStart["ms|" .. tostring(guid) .. tostring(spellID)]
	if ms then s.castMs = ms end
end

---------------------------------------------------------------------------
-- 3. Auras: debuffs on you, buffs and debuffs on your target
---------------------------------------------------------------------------

local function ReadAuras(unit, filter)
	local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	if not get then db.missing["C_UnitAuras.GetAuraDataByIndex"] = true return end
	local test = "aura:" .. unit .. ":" .. filter
	for i = 1, 40 do
		local ok, a = Try(test, get, unit, i, filter)
		if not ok or a == nil then break end
		if IsSecret(a) then Note(test, "whole aura", a) break end
		local name = Note(test, "name", a.name)
		local id = Note(test, "spellId", a.spellId)
		local source = Note(test, "sourceUnit", a.sourceUnit)
		Note(test, "duration", a.duration)
		Note(test, "applications", a.applications)
		Note(test, "dispelName", a.dispelName)
		-- who put it there: the source unit's creature
		local guid, sname
		if type(source) == "string" then
			local _, g = Try("UnitGUID", UnitGUID, source)
			local _, n = Try("UnitName", UnitName, source)
			guid, sname = Safe(g), Safe(n)
		elseif unit ~= "player" then
			local _, g = Try("UnitGUID", UnitGUID, unit)
			local _, n = Try("UnitName", UnitName, unit)
			guid, sname = Safe(g), Safe(n)
		end
		if type(id) == "number" and (guid or sname) then
			local c = (guid == nil or NpcFromGuid(guid)) and Creature(guid, sname)
			if c then
				local key = filter .. ":" .. id
				local x = c.auras[key] or { n = 0, name = name }
				x.n = x.n + 1
				c.auras[key] = x
			end
		end
	end
end

---------------------------------------------------------------------------
-- 4. Damage numbers on you (UNIT_COMBAT)
---------------------------------------------------------------------------

local function OnUnitCombat(unit, action, flag, amount, school)
	if unit ~= "player" then return end
	Note("UNIT_COMBAT", "action", action)
	Note("UNIT_COMBAT", "flag", flag)
	Note("UNIT_COMBAT", "amount", amount)
	Note("UNIT_COMBAT", "school", school)
end

---------------------------------------------------------------------------
-- 5. Blizzard's damage meter, read after each fight
---------------------------------------------------------------------------

local meterLast = {}
local function ReadMeter()
	if not C_DamageMeter then db.missing["C_DamageMeter"] = true return end
	if not db.meterFunctions then
		local names = {}
		for k, v in pairs(C_DamageMeter) do if type(v) == "function" then names[#names + 1] = k end end
		table.sort(names)
		db.meterFunctions = names
		local enums = {}
		for k, v in pairs(Enum or {}) do
			if type(k) == "string" and k:find("DamageMeter") then enums[k] = Dump(v, 1) end
		end
		db.meterEnums = enums
	end
	local T, S = Enum and Enum.DamageMeterType, Enum and Enum.DamageMeterSessionType
	if not (T and S and C_DamageMeter.GetCombatSessionFromType) then return end
	for _, kind in ipairs({ "DamageTaken", "EnemyDamageTaken", "DamageDone" }) do
		if T[kind] then
			local ok, session = Try("meter:" .. kind, C_DamageMeter.GetCombatSessionFromType, S.Current, T[kind])
			if ok and type(session) == "table" and not IsSecret(session) then
				if #db.samples.meter < 6 then db.samples.meter[#db.samples.meter + 1] = { kind = kind, session = Dump(session, 3) } end
				local sources = Safe(session.combatSources)
				for _, src in ipairs(type(sources) == "table" and sources or {}) do
					local test = "meter:" .. kind
					local sname = Note(test, "sourceName", src.name)
					local sguid = Note(test, "sourceGUID", src.sourceGUID)
					local creatureID = Note(test, "creatureID", src.sourceCreatureID or src.creatureID)
					Note(test, "totalAmount", src.totalAmount)
					if C_DamageMeter.GetCombatSessionSourceFromType then
						local ok2, detail = Try("meter:" .. kind .. ":source", C_DamageMeter.GetCombatSessionSourceFromType, S.Current, T[kind], src.sourceGUID, src.sourceCreatureID or src.creatureID)
						local spells = ok2 and type(detail) == "table" and Safe(detail.combatSpells)
						for _, one in ipairs(type(spells) == "table" and spells or {}) do
							local id = Note(test, "spellID", one.spellID)
							local total = Note(test, "spellTotal", one.totalAmount)
							local x = Safe(one.combatSpellDetails)
							local uname, isMob, class
							if type(x) == "table" then
								uname = Note(test, "detail.unitName", x.unitName)
								isMob = Note(test, "detail.isMob", x.isMob)
								class = Note(test, "detail.classification", x.classification)
							end
							-- damage taken: the attacker is in the spell's details
							if kind == "DamageTaken" and isMob and type(uname) == "string" and type(id) == "number" then
								local c = Creature(nil, uname)
								local s = c.spells[id] or { casts = 0 }
								c.spells[id] = s
								-- the current session may be a running total: count only what's new since the last read
								local lastKey = uname .. "|" .. id
								local prev = meterLast[lastKey] or 0
								if type(total) == "number" then meterLast[lastKey] = total end
								if type(total) == "number" and total < prev then prev = 0 end
								total = type(total) == "number" and (total - prev) or nil
								if total and total > 0 then
									s.meterFights = (s.meterFights or 0) + 1
									s.meterTotal = (s.meterTotal or 0) + total
									s.meterHi = math.max(s.meterHi or 0, total)
								end
								if not s.name then
									local okI, info = Try("C_Spell.GetSpellInfo", C_Spell and C_Spell.GetSpellInfo, id)
									if okI and type(info) == "table" then s.name = Safe(info.name) end
								end
								if class then c.class = class end
							end
							-- enemy damage taken: the source is the creature itself (creatureID given)
							if kind == "EnemyDamageTaken" and type(creatureID) == "number" then
								local c = db.creatures[creatureID] or db.creatures[sname or ""]
								if c then c.meterCreatureID = creatureID end
							end
						end
					end
				end
			end
		end
	end
end

-- Every meter view after each fight, saved whole (with each source's breakdown) so the saved file
-- shows exactly what the game gives: looking for enemy heals (Interrupts, EnemyDamageTaken, healing views).
local function MeterDeep()
	local T, S = Enum and Enum.DamageMeterType, Enum and Enum.DamageMeterSessionType
	if not (T and S and C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then return end
	db.samples.meterFull = db.samples.meterFull or {}
	local full = db.samples.meterFull
	local okA, avail = Try("meter:GetAvailableCombatSessions", C_DamageMeter.GetAvailableCombatSessions)
	if okA and (full.available or 0) < 3 then
		full.available = (full.available or 0) + 1
		full["available" .. full.available] = Dump(avail, 3)
	end
	for kind, value in pairs(T) do
		local list = full[kind] or {}
		full[kind] = list
		if #list < 6 then
			local ok, session = Try("meterDeep:" .. kind, C_DamageMeter.GetCombatSessionFromType, S.Current, value)
			if ok and type(session) == "table" and not IsSecret(session) then
				local entry = { session = Dump(session, 4), sources = {} }
				local sources = Safe(session.combatSources)
				for i, src in ipairs(type(sources) == "table" and sources or {}) do
					if i > 6 then break end
					local guid, cid = src.sourceGUID, src.sourceCreatureID or src.creatureID
					local tries = { { guid, cid }, { guid, nil }, { nil, cid } }
					for t, args in ipairs(tries) do
						local ok2, detail = pcall(C_DamageMeter.GetCombatSessionSourceFromType, S.Current, value, args[1], args[2])
						if ok2 and detail ~= nil then
							entry.sources[i] = { name = Text(src.name), call = t, detail = Dump(detail, 5) }
							Note("meterDeep:" .. kind, "sourceDetail", t)
							break
						elseif not ok2 then
							entry.sources[i] = { name = Text(src.name), error = Text(detail) }
						end
					end
				end
				if Safe(session.totalAmount) ~= 0 or #entry.sources > 0 then list[#list + 1] = entry end
			end
		end
	end
end

---------------------------------------------------------------------------
-- 6. Loot and deaths
---------------------------------------------------------------------------

local function ReadLoot()
	if not (GetNumLootItems and GetLootSourceInfo) then db.missing["loot"] = true return end
	local _, fishing = Try("IsFishingLoot", IsFishingLoot)
	fishing = Note("loot", "isFishing", fishing)
	for slot = 1, GetNumLootItems() do
		local ok, link = Try("GetLootSlotLink", GetLootSlotLink, slot)
		link = ok and Note("loot", "itemLink", link) or nil
		local item = type(link) == "string" and tonumber(link:match("item:(%d+)"))
		-- item set membership (a return of the item info), for "set pieces found"
		if item then
			local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
			local okI, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14, r15, setID = pcall(getInfo, item)
			if okI and r1 then Note("loot", "itemSetID", setID or 0) end
		end
		local sources = { pcall(GetLootSourceInfo, slot) }
		if sources[1] then
			for i = 2, #sources, 2 do
				local guid = Note("loot", "sourceGUID", sources[i])
				-- what kind of thing it came from: Creature, GameObject (herb, ore, chest), Item (container) ...
				if type(guid) == "string" then
					local kind, _, _, _, _, id = strsplit("-", guid)
					local key = (fishing and "fishing:" or "") .. tostring(kind)
					db.lootKinds[key] = db.lootKinds[key] or {}
					local lk = db.lootKinds[key]
					if #lk < 15 then lk[#lk + 1] = tostring(id) .. " -> " .. tostring(item) .. " @map " .. tostring(PlayerMap()) end
				elseif fishing then
					db.lootKinds["fishing:no source"] = (type(db.lootKinds["fishing:no source"]) == "number" and db.lootKinds["fishing:no source"] or 0) + 1
				end
				local npc = NpcFromGuid(guid)
				if npc and item then
					local c = Creature(guid, nil)
					c.loot = c.loot or {}
					c.loot[item] = (c.loot[item] or 0) + 1
				end
			end
		end
	end
end

local dead = {}
local function CheckDeath(unit)
	local _, guid = Try("UnitGUID", UnitGUID, unit)
	guid = Safe(guid)
	if not guid or dead[guid] or not NpcFromGuid(guid) then return end
	local _, isDead = Try("UnitIsDead", UnitIsDead, unit)
	local st = State(isDead)
	Note("death", "UnitIsDead", isDead)
	if st == "ok" and isDead then
		dead[guid] = true
		local _, name = Try("UnitName", UnitName, unit)
		local c = Creature(guid, Safe(name))
		if c then c.killsSeen = (c.killsSeen or 0) + 1 end
	end
end

---------------------------------------------------------------------------
-- 6b. The rest of the world (probe 0.3): what each window and event hands an addon.
-- Each check saves a few samples to db.world[name] and tallies readable / secret values.
---------------------------------------------------------------------------

local function Sample(name, value)
	db.world[name] = db.world[name] or {}
	local list = db.world[name]
	if #list < 8 then list[#list + 1] = Dump(value, 3) end
end

local function Where()
	local map = PlayerMap()
	local x, y
	if map and C_Map and C_Map.GetPlayerMapPosition then
		local ok, pos = Try("C_Map.GetPlayerMapPosition", C_Map.GetPlayerMapPosition, map, "player")
		if ok and pos and not IsSecret(pos) and pos.GetXY then
			local okXY, px, py = pcall(pos.GetXY, pos)
			if okXY then x, y = Safe(px), Safe(py) end
		end
	end
	local _, zone = Try("GetZoneText", GetZoneText)
	local _, sub = Try("GetSubZoneText", GetSubZoneText)
	return { map = map, x = x and math.floor(x * 1000) / 10, y = y and math.floor(y * 1000) / 10, zone = Safe(zone), sub = Safe(sub) }
end

-- the NPC or object you're talking to
local function Npc(test)
	local _, guid = Try("UnitGUID npc", UnitGUID, "npc")
	local _, name = Try("UnitName npc", UnitName, "npc")
	return { guid = Note(test, "npcGUID", guid), name = Note(test, "npcName", name) }
end

local function OnGossip()
	local who = Npc("gossip")
	local text
	if C_GossipInfo and C_GossipInfo.GetText then
		local ok, t = Try("C_GossipInfo.GetText", C_GossipInfo.GetText)
		text = ok and Note("gossip", "text", t) or nil
	end
	local options
	if C_GossipInfo and C_GossipInfo.GetOptions then
		local ok, o = Try("C_GossipInfo.GetOptions", C_GossipInfo.GetOptions)
		if ok then options = Dump(o, 2) Note("gossip", "options", o) end
	end
	Sample("gossip", { who = who, text = text, options = options, where = Where() })
end

local function OnQuestText(event)
	local who = Npc("questText")
	local _, title = Try("GetTitleText", GetTitleText)
	local body
	if event == "QUEST_DETAIL" then
		local _, t = Try("GetQuestText", GetQuestText); body = t
		local _, obj = Try("GetObjectiveText", GetObjectiveText)
		Note("questText", "objective", obj)
	elseif event == "QUEST_PROGRESS" then
		local _, t = Try("GetProgressText", GetProgressText); body = t
	elseif event == "QUEST_COMPLETE" then
		local _, t = Try("GetRewardText", GetRewardText); body = t
	end
	Note("questText", "title", title)
	Note("questText", "body:" .. event, body)
	Sample("questText", { event = event, who = who, title = Safe(title), body = Text(body), where = Where() })
end

local function OnItemText()
	local _, title = Try("ItemTextGetItem", ItemTextGetItem)
	local _, text = Try("ItemTextGetText", ItemTextGetText)
	local _, page = Try("ItemTextGetPage", ItemTextGetPage)
	local _, material = Try("ItemTextGetMaterial", ItemTextGetMaterial)
	Note("book", "title", title)
	Note("book", "text", text)
	Note("book", "page", page)
	local _, guid = Try("UnitGUID npc", UnitGUID, "npc")
	Sample("book", { title = Safe(title), page = Safe(page), material = Safe(material), text = Text(text), source = Text(guid), where = Where() })
end

local function OnMerchant()
	local who = Npc("merchant")
	local okN, n = Try("GetMerchantNumItems", GetMerchantNumItems)
	n = okN and Safe(n) or 0
	local items = {}
	for i = 1, math.min(n, 60) do
		local info
		if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
			local ok, t = Try("C_MerchantFrame.GetItemInfo", C_MerchantFrame.GetItemInfo, i)
			if ok then info = t end
		end
		if not info then
			local ok, name, tex, price, qty, avail, usable, extended = Try("GetMerchantItemInfo", GetMerchantItemInfo, i)
			if ok then info = { name = name, price = price, stackCount = qty, numAvailable = avail, hasExtendedCost = extended } end
		end
		local okL, link = Try("GetMerchantItemLink", GetMerchantItemLink, i)
		if type(info) == "table" then
			Note("merchant", "price", info.price)
			Note("merchant", "numAvailable", info.numAvailable)
			Note("merchant", "extendedCost", info.hasExtendedCost)
		end
		Note("merchant", "link", okL and link or nil)
		if i <= 12 then items[#items + 1] = { info = Dump(info, 1), link = okL and Text(link) or nil } end
		if type(info) == "table" and Safe(info.hasExtendedCost) then
			local okC, nCost = Try("GetMerchantItemCostInfo", GetMerchantItemCostInfo, i)
			Note("merchant", "costCount", okC and nCost or nil)
		end
	end
	Sample("merchant", { who = who, count = n, items = items, where = Where() })
end

local function OnTrainer()
	local who = Npc("trainer")
	local okN, n = Try("GetNumTrainerServices", GetNumTrainerServices)
	n = okN and Safe(n) or 0
	local list = {}
	for i = 1, math.min(n, 80) do
		local _, name, rank, category = Try("GetTrainerServiceInfo", GetTrainerServiceInfo, i)
		local _, cost = Try("GetTrainerServiceCost", GetTrainerServiceCost, i)
		local _, level = Try("GetTrainerServiceLevelReq", GetTrainerServiceLevelReq, i)
		Note("trainer", "name", name)
		Note("trainer", "cost", cost)
		Note("trainer", "level", level)
		if i <= 15 then list[#list + 1] = Text(name) .. " " .. Text(rank) .. " [" .. Text(category) .. "] lv " .. Text(level) .. " cost " .. Text(cost) end
	end
	Sample("trainer", { who = who, count = n, services = list, where = Where() })
end

local function OnTradeSkill()
	local okN, n = Try("GetNumTradeSkills", GetNumTradeSkills)
	local _, line = Try("GetTradeSkillLine", GetTradeSkillLine)
	n = okN and Safe(n) or 0
	local list = {}
	for i = 1, math.min(n, 10) do
		local _, name, kind = Try("GetTradeSkillInfo", GetTradeSkillInfo, i)
		Note("tradeskill", "name", name)
		list[#list + 1] = Text(name) .. " (" .. Text(kind) .. ")"
	end
	Sample("tradeskill", { line = Safe(line), count = n, first = list })
end

local function OnTaxi()
	local okN, n = Try("NumTaxiNodes", NumTaxiNodes)
	n = okN and Safe(n) or 0
	local list = {}
	for i = 1, math.min(n, 40) do
		local _, name = Try("TaxiNodeName", TaxiNodeName, i)
		local _, kind = Try("TaxiNodeGetType", TaxiNodeGetType, i)
		Note("taxi", "name", name)
		list[#list + 1] = Text(name) .. " " .. Text(kind)
	end
	Sample("taxi", { count = n, nodes = list, where = Where() })
end

local function OnZone()
	local w = Where()
	local explored
	if C_MapExplorationInfo and w.map then
		local okT, tex = Try("C_MapExplorationInfo.GetExploredMapTextures", C_MapExplorationInfo.GetExploredMapTextures, w.map)
		Note("exploration", "textures", okT and tex or nil)
		explored = okT and type(tex) == "table" and #tex or nil
		if C_Map and C_Map.GetPlayerMapPosition then
			local okP, pos = Try("C_Map.GetPlayerMapPosition", C_Map.GetPlayerMapPosition, w.map, "player")
			if okP and pos then
				local okA, areas = Try("C_MapExplorationInfo.GetExploredAreaIDsAtPosition", C_MapExplorationInfo.GetExploredAreaIDsAtPosition, w.map, pos)
				Note("exploration", "areaIDs", okA and areas or nil)
				w.areas = okA and Dump(areas, 1) or nil
			end
		end
	else
		db.missing["C_MapExplorationInfo"] = true
	end
	w.exploredTextures = explored
	Sample("zone", w)
end

local function OnFactions()
	local list, count = {}, 0
	if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
		local okN, n = Try("C_Reputation.GetNumFactions", C_Reputation.GetNumFactions)
		n = okN and Safe(n) or 0
		for i = 1, math.min(n, 60) do
			local ok, d = Try("C_Reputation.GetFactionDataByIndex", C_Reputation.GetFactionDataByIndex, i)
			if ok and type(d) == "table" then
				count = count + 1
				Note("faction", "name", d.name)
				Note("faction", "standing", d.reaction)
				if #list < 12 then list[#list + 1] = Text(d.name) .. " " .. Text(d.reaction) .. " " .. Text(d.currentStanding) end
			end
		end
	elseif GetNumFactions and GetFactionInfo then
		local okN, n = Try("GetNumFactions", GetNumFactions)
		n = okN and Safe(n) or 0
		for i = 1, math.min(n, 60) do
			local ok, name, _, standing = Try("GetFactionInfo", GetFactionInfo, i)
			if ok then
				count = count + 1
				Note("faction", "name", name)
				Note("faction", "standing", standing)
				if #list < 12 then list[#list + 1] = Text(name) .. " " .. Text(standing) end
			end
		end
	end
	Sample("factions", { count = count, first = list })
end

-- interactions with services: innkeeper, banker, mailbox, spirit healer, auction house, flight master ...
local function OnInteraction(event, kind)
	local who = Npc("interaction")
	Note("interaction", "type", kind)
	Sample("interaction", { event = event, type = Text(kind), who = who, where = Where() })
end

local function OnLevel(level)
	Sample("levelUp", { level = Text(level), where = Where(), time = time() })
end

local function OnPlayerDead()
	Sample("playerDeath", { where = Where(), time = time() })
	-- the damage meter's Deaths view is saved by MeterDeep when combat ends
end

-- Creature model by NPC id: /aap model shows your target's model the way the Almanac would
-- (without the creature being there).
local modelFrame
local function ShowModel()
	local _, guid = Try("UnitGUID", UnitGUID, "target")
	local npc = NpcFromGuid(Safe(guid))
	if not npc then return Print("Target a creature first, then /aap model.") end
	if not modelFrame then
		modelFrame = CreateFrame("PlayerModel", nil, UIParent)
		modelFrame:SetSize(220, 260)
		modelFrame:SetPoint("CENTER", 300, 0)
		modelFrame:EnableMouse(true)
		modelFrame:SetScript("OnMouseDown", function(self) self:Hide() end)
	end
	modelFrame:Show()
	modelFrame:ClearModel()
	local ok, err = pcall(modelFrame.SetCreature, modelFrame, npc)
	local okF, file = pcall(modelFrame.GetModelFileID, modelFrame)
	db.world.model = db.world.model or {}
	db.world.model[#db.world.model + 1] = { npc = npc, setCreature = ok and "ok" or Text(err), modelFileID = okF and Text(file) or "error" }
	Print(("Model for NPC %d: SetCreature %s, model file %s. Click the model to close it. Clear your target and run /aap model2 %d to try it with the creature gone.")
		:format(npc, ok and "ok" or ("failed: " .. Text(err)), okF and Text(file) or "?", npc))
end

local function ShowModelById(npc)
	if not modelFrame then
		modelFrame = CreateFrame("PlayerModel", nil, UIParent)
		modelFrame:SetSize(220, 260)
		modelFrame:SetPoint("CENTER", 300, 0)
		modelFrame:EnableMouse(true)
		modelFrame:SetScript("OnMouseDown", function(self) self:Hide() end)
	end
	modelFrame:Show()
	modelFrame:ClearModel()
	local ok, err = pcall(modelFrame.SetCreature, modelFrame, npc)
	local okF, file = pcall(modelFrame.GetModelFileID, modelFrame)
	db.world.model = db.world.model or {}
	db.world.model[#db.world.model + 1] = { npc = npc, byIdOnly = true, setCreature = ok and "ok" or Text(err), modelFileID = okF and Text(file) or "error" }
	Print(("Model for NPC %d (by ID only): SetCreature %s, model file %s. Click it to close."):format(npc, ok and "ok" or ("failed: " .. Text(err)), okF and Text(file) or "?"))
end

---------------------------------------------------------------------------
-- 7. The combat log: can it be registered? can logging be switched on?
---------------------------------------------------------------------------

-- Both of these are blocked for addons on this client: each one shows the "blocked from an action
-- only available to the Blizzard UI" popup (seen 2026-10-03). So they only run on request
-- (/aap testlog), and the game's ADDON_ACTION_FORBIDDEN event says which function was refused.
local function TestCombatLog()
	db.combatLog.forbidden = {}
	local ok, err = pcall(f.RegisterEvent, f, "COMBAT_LOG_EVENT_UNFILTERED")
	db.combatLog.register = ok and "no error" or ("refused: " .. Text(err))
	if LoggingCombat then
		local okSet, res = pcall(LoggingCombat, true)
		db.combatLog.setLogging = okSet and ("no error, returned " .. Text(res)) or ("error: " .. Text(res))
	else
		db.combatLog.setLogging = "LoggingCombat is missing"
	end
end

local function ReadLogSettings()
	local okC, cvar = pcall(GetCVar, "advancedCombatLogging")
	db.combatLog.advancedCVar = okC and Text(cvar) or "error"
end

---------------------------------------------------------------------------
-- Report
---------------------------------------------------------------------------

local function Pct(s) local n = s.ok + s.secret return n > 0 and math.floor(s.ok / n * 100 + 0.5) or nil end

local function Report()
	local refused = {}
	for k in pairs(db.combatLog.forbidden or {}) do refused[#refused + 1] = k end
	Print(("Report. Combat log test: %s. Logging on by addon: %s. Refused by the game: %s. Advanced logging setting: %s.")
		:format(db.combatLog.register or "not run (/aap testlog)", db.combatLog.setLogging or "not run",
			#refused > 0 and table.concat(refused, ", ") or "none", db.combatLog.advancedCVar or "?"))
	local names = {}
	for k in pairs(db.tests) do names[#names + 1] = k end
	table.sort(names)
	for _, test in ipairs(names) do
		local parts = {}
		local fields = {}
		for k in pairs(db.tests[test]) do fields[#fields + 1] = k end
		table.sort(fields)
		for _, k in ipairs(fields) do
			local s = db.tests[test][k]
			local p = Pct(s)
			if p then parts[#parts + 1] = ("%s %d%%"):format(k, p) end
		end
		Print("|cffffd100" .. test .. "|r (readable %, @out = out of combat, @in = in combat): " .. table.concat(parts, ", "))
	end
	local miss = {}
	for k in pairs(db.missing) do miss[#miss + 1] = k end
	if #miss > 0 then Print("Missing on this client: " .. table.concat(miss, ", ")) end
	local errs = 0
	for _ in pairs(db.errors) do errs = errs + 1 end
	if errs > 0 then Print(errs .. " functions errored (details in the saved file).") end
	local n = 0
	for _ in pairs(db.creatures) do n = n + 1 end
	Print(n .. " creatures recorded. /aap creatures for details. Everything is also in WTF\\...\\SavedVariables\\AlmanacProbe.lua after /reload or logout.")
end

local function CreatureReport()
	local count = 0
	for key, c in pairs(db.creatures) do
		count = count + 1
		if count > 15 then Print("(more in the saved file)") break end
		local lv = {}
		for l in pairs(c.levels) do lv[#lv + 1] = l end
		table.sort(lv)
		local sp = {}
		for id, s in pairs(c.spells) do
			local t = (s.name or ("spell " .. id))
			if s.casts > 0 then t = t .. " x" .. s.casts end
			if s.castMs then t = t .. (" %.1fs cast"):format(s.castMs / 1000) end
			if s.interruptible ~= nil then t = t .. (s.interruptible and " interruptible" or " not interruptible") end
			if s.meterFights then t = t .. (" hit you for %d over %d fights"):format(s.meterTotal, s.meterFights) end
			sp[#sp + 1] = t
		end
		local au = {}
		for k, x in pairs(c.auras) do au[#au + 1] = (x.name or k) .. " x" .. x.n end
		Print(("|cffffd100%s|r (%s) lv %s, hp %s, %s %s %s, seen %d, kills %d | abilities: %s | auras: %s"):format(
			c.name or "?", tostring(key), table.concat(lv, "/"), c.hpHi and (c.hpLo == c.hpHi and c.hpHi or (c.hpLo .. "-" .. c.hpHi)) or "?",
			c.class or "?", c.type or "?", c.family or "", c.seen or 0, c.killsSeen or 0,
			#sp > 0 and table.concat(sp, "; ") or "-", #au > 0 and table.concat(au, "; ") or "-"))
	end
	if count == 0 then Print("No creatures yet.") end
end

local function Fresh()
	return { tests = {}, events = {}, missing = {}, errors = {}, creatures = {}, nameToNpc = {}, world = {}, lootKinds = {}, combatLog = {}, samples = { tooltip = {}, meter = {} },
		started = time(), build = select(1, GetBuildInfo()), interface = select(4, GetBuildInfo()) }
end

SLASH_ALMANACPROBE1 = "/aap"
SlashCmdList.ALMANACPROBE = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "reset" then
		AlmanacProbeDB = Fresh()
		db = AlmanacProbeDB
		ReadLogSettings()
		Print("Reset.")
	elseif msg == "testlog" then
		TestCombatLog()
		Print("Tried the combat log and LoggingCombat. Click Ignore on any popup; /aap report shows what was refused.")
	elseif msg == "meter" then
		local full = db.samples.meterFull or {}
		local parts = {}
		for kind, list in pairs(full) do
			if type(list) == "table" and #list > 0 then parts[#parts + 1] = kind .. " " .. #list end
		end
		table.sort(parts)
		Print("Meter views saved after fights: " .. (#parts > 0 and table.concat(parts, ", ") or "none yet") .. ". Details in the saved file.")
	elseif msg == "creatures" then
		CreatureReport()
	elseif msg == "model" then
		ShowModel()
	elseif msg:match("^model2%s+%d+") then
		ShowModelById(tonumber(msg:match("^model2%s+(%d+)")))
	elseif msg == "world" then
		local parts = {}
		for k, v in pairs(db.world) do parts[#parts + 1] = k .. " " .. (type(v) == "table" and #v or 0) end
		for k, v in pairs(db.lootKinds) do parts[#parts + 1] = "loot from " .. k .. " " .. (type(v) == "table" and #v or tostring(v)) end
		table.sort(parts)
		Print("World checks saved: " .. (#parts > 0 and table.concat(parts, ", ") or "none yet") .. ". Details in the saved file.")
	else
		Report()
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = {
	"PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
	"NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_HEALTH", "UNIT_AURA", "UNIT_COMBAT",
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_INTERRUPTED",
	"LOOT_READY", "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED", "DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED",
	"GOSSIP_SHOW", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "ITEM_TEXT_READY", "MERCHANT_SHOW", "TRAINER_SHOW",
	"TRADE_SKILL_SHOW", "TAXIMAP_OPENED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "UPDATE_FACTION",
	"PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_LEVEL_UP", "PLAYER_DEAD",
}
for _, e in ipairs(events) do pcall(f.RegisterEvent, f, e) end
local lastFaction = 0

f:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_LOGIN" then
		if type(AlmanacProbeDB) ~= "table" or not AlmanacProbeDB.tests then AlmanacProbeDB = Fresh() end
		db = AlmanacProbeDB
		db.nameToNpc = db.nameToNpc or {}
		db.world = db.world or {}
		db.lootKinds = db.lootKinds or {}
		db.version = "0.3"
		C_Timer.After(5, OnFactions)
		db.logins = (db.logins or 0) + 1
		db.combatLog.forbidden = db.combatLog.forbidden or {}
		ReadLogSettings()
		Print("running. Fight a few creatures (casters too), loot them, then type /aap report.")
		return
	end
	if not db then return end
	Event(event)
	if event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
		local who, what = ...
		if who == ADDON then db.combatLog.forbidden[Text(what)] = event end
		return
	end
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		local ok, _, sub, _, sguid = pcall(CombatLogGetCurrentEventInfo)
		Note("combatlog", "subevent", ok and sub or nil)
		Note("combatlog", "sourceGUID", ok and sguid or nil)
	elseif event == "PLAYER_REGEN_DISABLED" then
		inCombat = true
		ReadUnit("target", "target")
		ReadAuras("target", "HELPFUL")
	elseif event == "PLAYER_REGEN_ENABLED" then
		inCombat = false
		ReadAuras("player", "HARMFUL")
		C_Timer.After(1, function() ReadMeter() MeterDeep() end)
	elseif event == "PLAYER_TARGET_CHANGED" then
		ReadUnit("target", "target")
		ReadTooltip("target")
		ReadAuras("target", "HELPFUL")
		ReadAuras("target", "HARMFUL")
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		ReadUnit("mouseover", "mouseover")
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		ReadUnit(..., "nameplate")
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		CheckDeath(...)
	elseif event == "UNIT_HEALTH" then
		local unit = ...
		if unit == "target" or (type(unit) == "string" and unit:find("^nameplate")) then
			local _, hp = Try("UnitHealth", UnitHealth, unit)
			Note("UNIT_HEALTH", "health", hp)
			if Safe(hp) == 0 then CheckDeath(unit) end
		end
	elseif event == "UNIT_AURA" then
		local unit = ...
		if unit == "player" then ReadAuras("player", "HARMFUL")
		elseif unit == "target" then ReadAuras("target", "HELPFUL") ReadAuras("target", "HARMFUL") end
	elseif event == "UNIT_COMBAT" then
		OnUnitCombat(...)
	elseif event:find("^UNIT_SPELLCAST") then
		OnCast(event, ...)
	elseif event == "LOOT_READY" then
		ReadLoot()
	elseif event == "GOSSIP_SHOW" then
		OnGossip()
	elseif event == "QUEST_DETAIL" or event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then
		OnQuestText(event)
	elseif event == "ITEM_TEXT_READY" then
		OnItemText()
	elseif event == "MERCHANT_SHOW" then
		C_Timer.After(0.5, OnMerchant)
	elseif event == "TRAINER_SHOW" then
		C_Timer.After(0.3, OnTrainer)
	elseif event == "TRADE_SKILL_SHOW" then
		C_Timer.After(0.5, OnTradeSkill)
	elseif event == "TAXIMAP_OPENED" then
		OnTaxi()
	elseif event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" then
		OnZone()
	elseif event == "UPDATE_FACTION" then
		if GetTime() - lastFaction > 60 then lastFaction = GetTime() OnFactions() end
	elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
		OnInteraction(event, ...)
	elseif event == "PLAYER_LEVEL_UP" then
		OnLevel(...)
	elseif event == "PLAYER_DEAD" then
		OnPlayerDead()
	elseif event:find("^DAMAGE_METER") then
		-- only counted (Event above); the meter is read once after each fight
	end
end)
