-- Bestiary recorder: everything the game lets an addon see about the creatures you meet.
-- (The combat log is off-limits to addons on this client; these are the sources the probes proved.)
--   Seen (target, mouseover, nameplate): name, NPC id, levels, type, family, rarity, zones.
--   After each fight, from Blizzard's damage meter: the abilities that hit you (damage per fight),
--     and each enemy's damage taken, which on a clean kill is about its health; clearly more than
--     that means it healed itself.
--   Casts it started (the spell is hidden, the caster isn't), debuffs it left on you (read after
--     combat), kills, loot per corpse (your own drop rates), money, and skinning / gathering.
-- found.creature[npcID] = {
--   name, lo, hi (levels; -1 = "??"), class (normal / elite / rare / rareelite / worldboss ...),
--   type, family, boss, z = { [mapID] = sightings }, kills,
--   ab = { [spellID] = { f = fights, t = total, hi = most in one fight } },   abilities that hit you
--   casts = n, cs = { [spellID] = n } (only if the client ever shows the spell),
--   db = { [spellID] = n },                                                  debuffs on you
--   hp = { [level or 0] = { samples... } }, heal = { n, hi },                 health and heals
--   corpses = n, loot = { [itemID] = corpses }, money = { n, total },
--   gathered = n, gather = { [itemID] = n } }

local _, ns = ...
local L = ns.L
local B = ns:NewModule("Bestiary")
local R = ns.Readable

local SEEN_AGAIN = 60        -- seconds before the same creature (by GUID) counts as a new sighting
local MAX_SAMPLES = 10

local seenAt = {}            -- guid -> last sighting time
local dead = {}              -- guid -> true once its death was counted
local deadCount = 0
local looted = {}            -- guid -> true once its corpse was looted
local skinned = {}           -- guid -> time its skinning loot was counted (LOOT_READY can fire twice)
local guidCount = 0
local fight = nil            -- the fight in progress: { names = { name = npc }, guids = { guid = npc }, deaths = { guid = npc } }
local lastGather = 0         -- when you last finished a gathering cast (skinning, herbs, mining)

local function Settings() return ns.db.settings end

---------------------------------------------------------------------------
-- Tiers
---------------------------------------------------------------------------

B.TIERS = { L["Sighted"], L["Fought"], L["Studied"], L["Mastered"] }

-- each tier's badge: an icon (first one the client has) in a ring of the tier's colour
--   Sighted: icon 134442 (picked from the macro icons), grey
--   Fought: icon 132223, bronze
--   Studied: an open book, silver
--   Mastered: the gold chevrons icon (file 4622480, picked from the macro icon list), gold
local ATTACK = "Interface\\CURSOR\\Attack"
B.TIER_ICONS = {
	{ 134442, "INV_Misc_Spyglass_02", "INV_Misc_Spyglass_03" },
	{ 132223, ATTACK },
	{ "INV_Misc_Book_11", "INV_Misc_Book_07", "INV_Misc_Book_09" },
	{ 4622480, "Interface\\PvPRankBadges\\PvPRank03", "Spell_Holy_SealOfWisdom" },
}
B.ATTACK_ICON = ATTACK
B.TIER_COLORS = { { 0.62, 0.62, 0.62 }, { 0.76, 0.48, 0.22 }, { 0.82, 0.85, 0.92 }, { 1, 0.82, 0.25 } }
B.TIER_HINTS = {
	L["Seen, not yet fought."],
	L["Killed at least once: health, armour, melee damage and money are known."],
	L["Every ability it can use is known."],
	L["Everything is known: immunities, resistances and the full loot table."],
}

function B:TierIcon(tier)
	local list = B.TIER_ICONS[tier] or B.TIER_ICONS[1]
	if ns.Widgets and ns.Widgets.FindIcon then return ns.Widgets.FindIcon(list) end
	return "Interface\\Icons\\" .. list[1]
end

-- "|T...|t" for text: the tier's icon, trimmed of its border (the sword cursor isn't trimmed)
function B:TierMarkup(tier, size)
	size = size or 16
	local icon = self:TierIcon(tier)
	if type(icon) == "string" and not icon:lower():find("^interface\\icons\\") then return ("|T%s:%d:%d|t"):format(icon, size, size) end
	return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(tostring(icon), size, size)
end

---------------------------------------------------------------------------
-- Creature faces: an NPC's appearance (display ID) is found by loading it into a hidden model, as
-- the Quest Targeter does; kept on the record (rec.display) so it's instant later
---------------------------------------------------------------------------

local resolver, queue, resolving, tries = nil, {}, nil, {}
local kindOf = {} -- npc -> the record kind its face is kept on ("creature", "merchant" ...)
local function ResolveNext()
	if resolving or #queue == 0 then return end
	resolving = table.remove(queue, 1)
	if not resolver then
		resolver = CreateFrame("PlayerModel", nil, UIParent)
		resolver:SetSize(1, 1)
		resolver:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10, -10)
	end
	if resolver.ClearModel then pcall(resolver.ClearModel, resolver) end
	local okBefore, before = pcall(resolver.GetDisplayInfo, resolver)
	before = okBefore and R(before) or 0
	pcall(resolver.SetCreature, resolver, resolving)
	C_Timer.After(1.2, function()
		local npc = resolving
		resolving = nil
		local ok, display = pcall(resolver.GetDisplayInfo, resolver)
		display = ok and R(display) or nil
		local kind = kindOf[npc] or "creature"
		local rec = ns.db and ns.Store:Get(kind, npc)
		if type(display) == "number" and display > 0 and display ~= before and rec then
			rec.display = display
			ns:Fire("CHANGED", kind, npc)
		elseif (tries[npc] or 0) < 3 then
			tries[npc] = (tries[npc] or 0) + 1
			tinsert(queue, npc)
		end
		ResolveNext()
	end)
end

-- the face of a creature in the world: its unit loaded into a hidden model (works for creatures the
-- client hasn't cached by ID yet)
local unitModel, unitBusy
local busyKind
function B:FaceFromUnit(unit, npc, kind)
	kind = kind or "creature"
	local rec = npc and ns.Store:Get(kind, npc)
	if not rec or rec.display or unitBusy then return end
	if not unitModel then
		unitModel = CreateFrame("PlayerModel", nil, UIParent)
		unitModel:SetSize(1, 1)
		unitModel:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10, -10)
	end
	if not pcall(unitModel.SetUnit, unitModel, unit) then return end
	unitBusy, busyKind = npc, kind
	C_Timer.After(0.4, function()
		local id = unitBusy
		unitBusy = nil
		local ok, display = pcall(unitModel.GetDisplayInfo, unitModel)
		display = ok and R(display) or nil
		local k = busyKind or "creature"
		local r = ns.db and ns.Store:Get(k, id)
		if r and type(display) == "number" and display > 0 then
			r.display = display
			ns:Fire("CHANGED", k, id)
		end
	end)
end

-- a display ID read from a model already showing the creature (the Bestiary page's own model)
function B:KeepFace(npc, display)
	local rec = npc and ns.Store:Get("creature", npc)
	display = R(display)
	if rec and not rec.display and type(display) == "number" and display > 0 then
		rec.display = display
		ns:Fire("CHANGED", "creature", npc)
	end
end

function B:LearnFace(npc, kind)
	kind = kind or "creature"
	kindOf[npc] = kind
	local rec = npc and ns.Store:Get(kind, npc)
	if not rec or rec.display or resolving == npc or (tries[npc] or 0) >= 3 then return end
	for _, q in ipairs(queue) do if q == npc then return end end
	tinsert(queue, npc)
	ResolveNext()
end

-- the creature's face on a texture (true), or nothing when it isn't known yet (asks for it)
function B:SetFace(texture, npc, rec, kind)
	if rec and rec.display and SetPortraitTextureFromCreatureDisplayID then
		texture:SetTexCoord(0, 1, 0, 1)
		if texture.SetDesaturated then texture:SetDesaturated(false) end
		SetPortraitTextureFromCreatureDisplayID(texture, rec.display)
		return true
	end
	if npc then self:LearnFace(npc, kind) end
	return false
end

-- paints a tier's own icon on a texture
function B:SetTierTexture(texture, tier)
	if texture.SetDesaturated then texture:SetDesaturated(tier == 1) end
	local icon = self:TierIcon(tier)
	texture:SetTexture(icon)
	if type(icon) == "string" and not icon:lower():find("^interface\\icons\\") then texture:SetTexCoord(0, 1, 0, 1)
	else texture:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
	return false
end

-- the tier's name in its colour
function B:TierText(tier)
	local c = B.TIER_COLORS[tier] or B.TIER_COLORS[1]
	return ("|cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, B.TIERS[tier] or "?")
end

function B:Group(rec)
	if rec.boss or rec.class == "worldboss" then return "boss" end
	if rec.class == "rare" or rec.class == "rareelite" then return "rare" end
	return "normal"
end

-- 1 Sighted, 2 Fought, 3 Studied, 4 Mastered; and kills needed for the next tier
function B:Tier(rec)
	local t = Settings().tiers[self:Group(rec)] or Settings().tiers.normal
	local k = rec.kills or 0
	if k >= t.mastered then return 4, nil end
	if k >= t.studied then return 3, t.mastered - k end
	if k >= 1 then return 2, t.studied - k end
	return 1, 1
end

local function TierCheck(npc, rec, before)
	local after = B:Tier(rec)
	if after > before and after >= 3 then
		ns:Fire("TOAST", "tier", after == 4 and L["Creature mastered"] or L["Creature studied"], rec.name or "?", B:TierIcon(after), after == 4 and 3 or 2)
	end
end

---------------------------------------------------------------------------
-- Names -> NPC ids (the damage meter reports names)
---------------------------------------------------------------------------

local byName
function B:ByName(name, f)
	if not name then return nil end
	f = f or fight
	if f and f.names[name] then return f.names[name] end
	if not byName then
		byName = {}
		for id, rec in pairs(ns.Store:All("creature")) do if rec.name then byName[rec.name] = id end end
	end
	return byName[name]
end

---------------------------------------------------------------------------
-- Seeing a creature
---------------------------------------------------------------------------

local function IsCreatureUnit(unit)
	if R(UnitIsPlayer(unit)) == true then return nil end
	local guid = R(UnitGUID(unit))
	local npc = ns.NpcFromGuid(guid)
	if not npc then return nil end
	-- pets, totems and guardians belonging to players
	if R(UnitPlayerControlled(unit)) == true then return nil end
	-- friendly NPCs belong to the NPCs page (later); the Bestiary is for creatures you could fight
	local reaction = R(UnitReaction(unit, "player"))
	if type(reaction) == "number" and reaction >= 5 then return nil end
	return npc, guid
end

function B:Seen(unit, isBoss)
	local npc, guid = IsCreatureUnit(unit)
	if not npc then return end
	if fight and R(UnitIsDead(unit)) ~= true then
		local name = R(UnitName(unit))
		fight.guids[guid] = npc
		if name then fight.names[name] = npc end
	end
	local now = time()
	local again = seenAt[guid] and now - seenAt[guid] < SEEN_AGAIN
	local rec = ns.Store:Get("creature", npc)
	if again and rec then
		if not rec.display then pcall(B.FaceFromUnit, B, unit, npc) end
		return npc, guid
	end
	seenAt[guid] = now

	local name = R(UnitName(unit))
	local level = R(UnitLevel(unit))
	local class = R(UnitClassification(unit))
	local where = ns.Where()
	rec = ns.Store:Discover("creature", npc, {
		name = name,
		class = class,
		type = R(UnitCreatureType(unit)),
		family = R(UnitCreatureFamily(unit)),
		boss = (isBoss or class == "worldboss") and true or nil,
	}, name, where)
	if not rec then return end
	if byName and name then byName[name] = npc end
	if not rec.display then pcall(B.FaceFromUnit, B, unit, npc) end
	if type(level) == "number" then
		rec.lo = rec.lo and math.min(rec.lo, level) or level
		rec.hi = rec.hi and math.max(rec.hi, level) or level
		if level == -1 then rec.lo, rec.hi = -1, -1 end
	end
	if where.map then
		rec.z = rec.z or {}
		rec.z[where.map] = (rec.z[where.map] or 0) + 1
		B:AddSpot(rec, "spots", where)
	end
	return npc, guid
end

---------------------------------------------------------------------------
-- Deaths and kills
---------------------------------------------------------------------------

-- Where a creature was seen (rec.spots) and killed (rec.kz), per map: { [uiMapID] = { "x:y" } },
-- in map percent, from where you stood. Spots closer than SPOT_GAP are one spot; the oldest go first.
local SPOT_MAX, SPOT_GAP = 24, 1.5
function B:AddSpot(rec, field, where)
	if not (rec and where and where.map and where.x and where.y) then return end
	rec[field] = rec[field] or {}
	local list = rec[field][where.map] or {}
	rec[field][where.map] = list
	for _, s in ipairs(list) do
		local sx, sy = s:match("^([%d%.]+):([%d%.]+)$")
		sx, sy = tonumber(sx), tonumber(sy)
		if sx and (sx - where.x) ^ 2 + (sy - where.y) ^ 2 < SPOT_GAP * SPOT_GAP then return end
	end
	if #list >= SPOT_MAX then table.remove(list, 1) end
	list[#list + 1] = ("%.1f:%.1f"):format(where.x, where.y)
end

-- the spots of one kind on a map: { { x, y } }
function B:Spots(rec, field, map)
	local out = {}
	for _, s in ipairs(rec and rec[field] and rec[field][map] or {}) do
		local x, y = s:match("^([%d%.]+):([%d%.]+)$")
		if x then out[#out + 1] = { x = tonumber(x), y = tonumber(y) } end
	end
	return out
end

-- the session's guid tables are trimmed now and then (they're not saved, but a long session adds up)
local function Trim()
	guidCount = guidCount + 1
	if guidCount < 500 then return end
	guidCount = 0
	seenAt, looted, skinned = {}, {}, {}
end

local function CountKill(guid, npc)
	Trim()
	if dead[guid] then return end
	dead[guid] = true
	deadCount = deadCount + 1
	if deadCount > 600 then dead, deadCount = { [guid] = true }, 1 end
	local rec = ns.Store:Get("creature", npc)
	if not rec then return end
	local before = B:Tier(rec)
	rec.kills = (rec.kills or 0) + 1
	local where = ns.Where()
	B:AddSpot(rec, "kz", where)
	if where.map and where.x then rec.lastKill = { map = where.map, x = where.x, y = where.y, t = time() } end
	if fight then fight.deaths[guid] = npc end
	TierCheck(npc, rec, before)
	ns:Fire("KILL", npc, rec)
	ns:Fire("CHANGED", "creature", npc)
end

function B:CheckDead(unit)
	local npc, guid = IsCreatureUnit(unit)
	if not npc or dead[guid] then return end
	if R(UnitIsDead(unit)) ~= true then return end
	-- someone else's kill (tapped by another player) doesn't count
	if R(UnitIsTapDenied and UnitIsTapDenied(unit)) == true then return end
	if not ns.Store:Get("creature", npc) then self:Seen(unit) end
	CountKill(guid, npc)
end

---------------------------------------------------------------------------
-- Casts and debuffs
---------------------------------------------------------------------------

local function OnCast(unit, spellID)
	if type(unit) ~= "string" or not (unit:find("^nameplate") or unit == "target" or unit == "focus" or unit:find("^boss")) then return end
	local npc, guid = IsCreatureUnit(unit)
	if not npc then return end
	local rec = ns.Store:Get("creature", npc)
	if not rec then
		B:Seen(unit)
		rec = ns.Store:Get("creature", npc)
	end
	if not rec then return end
	rec.casts = (rec.casts or 0) + 1
	spellID = R(spellID)
	if type(spellID) == "number" then
		rec.cs = rec.cs or {}
		rec.cs[spellID] = (rec.cs[spellID] or 0) + 1
	end
end

-- debuffs a creature left on you (aura data can only be read out of combat on this client)
local debuffSeen = {}
local function ReadMyDebuffs()
	if InCombatLockdown() then return end
	local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	if not get then return end
	for i = 1, 40 do
		local ok, a = pcall(get, "player", i, "HARMFUL")
		if not ok or type(a) ~= "table" or ns.IsSecret(a) then break end
		local id, source, instance = R(a.spellId), R(a.sourceUnit), R(a.auraInstanceID)
		if type(id) == "number" and type(source) == "string" and not debuffSeen[instance or id] then
			local npc = ns.NpcFromGuid(R(UnitGUID(source)))
			local rec = npc and ns.Store:Get("creature", npc)
			if rec then
				if instance then debuffSeen[instance] = true end
				rec.db = rec.db or {}
				rec.db[id] = (rec.db[id] or 0) + 1
			end
		end
	end
end

---------------------------------------------------------------------------
-- After a fight: Blizzard's damage meter
---------------------------------------------------------------------------

-- The meter's "Current" session is the last fight on its own: the probe's captures had durations
-- 37, 19, 72, 20 s with totals for that fight only (one Thistlefur Shaman: 863 = its health).
-- So each read after combat is that fight's numbers, read once.

local function SourceDetail(sessionType, meterType, src)
	local guid, cid = src.sourceGUID, src.sourceCreatureID or src.creatureID
	for _, args in ipairs({ { guid, cid }, { guid, nil }, { nil, cid } }) do
		local ok, d = pcall(C_DamageMeter.GetCombatSessionSourceFromType, sessionType, meterType, args[1], args[2])
		if ok and type(d) == "table" and not ns.IsSecret(d) then return d end
	end
end

local function ReadMeter(f)
	if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType and Enum and Enum.DamageMeterType and Enum.DamageMeterSessionType) then return end
	local T, S = Enum.DamageMeterType, Enum.DamageMeterSessionType
	f = f or { names = {}, guids = {}, deaths = {} }

	-- abilities that hit you: your source in Damage Taken, broken down by spell and attacker
	local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, S.Current, T.DamageTaken)
	if ok and type(session) == "table" and not ns.IsSecret(session) then
		for _, src in ipairs(R(session.combatSources) or {}) do
			if R(src.isLocalPlayer) == true then
				local detail = SourceDetail(S.Current, T.DamageTaken, src)
				for _, sp in ipairs(detail and R(detail.combatSpells) or {}) do
					local id, total = R(sp.spellID), R(sp.totalAmount)
					local x = R(sp.combatSpellDetails)
					local attacker = x and R(x.unitName)
					if type(id) == "number" and type(attacker) == "string" and attacker ~= "" and x and R(x.isMob) then
						local npc = B:ByName(attacker, f)
						local rec = npc and ns.Store:Get("creature", npc)
						local amount = type(total) == "number" and total or 0
						if rec and amount > 0 then
							rec.ab = rec.ab or {}
							local a = rec.ab[id] or { f = 0, t = 0, hi = 0 }
							a.f, a.t, a.hi = a.f + 1, a.t + amount, math.max(a.hi, amount)
							rec.ab[id] = a
						end
					end
				end
			end
		end
	end

	-- health and heals: Enemy Damage Taken, for creatures that died in this fight
	ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, S.Current, T.EnemyDamageTaken)
	if ok and type(session) == "table" and not ns.IsSecret(session) then
		-- how many of each creature died, and how many of it were seen at all, this fight
		local died, present = {}, {}
		for _, npc in pairs(f.deaths) do died[npc] = (died[npc] or 0) + 1 end
		for _, npc in pairs(f.guids) do present[npc] = (present[npc] or 0) + 1 end
		for _, src in ipairs(R(session.combatSources) or {}) do
			local npc = R(src.sourceCreatureID) or B:ByName(R(src.name), f)
			local amount = R(src.totalAmount)
			amount = type(amount) == "number" and amount or 0
			local rec = npc and ns.Store:Get("creature", npc)
			-- a clean sample: exactly one of it in the fight, and it died
			if rec and amount > 0 and died[npc] == 1 and (present[npc] or 1) == 1 then
				local lvl = (rec.lo == rec.hi and rec.lo) or 0
				rec.hp = rec.hp or {}
				local list = rec.hp[lvl] or {}
				local est = B:Health(rec, lvl)
				if est and amount > est * 1.25 and #list >= 2 then
					-- took far more than its health: it healed (don't let this skew the health)
					rec.heal = rec.heal or { 0, 0 }
					rec.heal[1] = rec.heal[1] + 1
					rec.heal[2] = math.max(rec.heal[2], amount - est)
				else
					list[#list + 1] = amount
					if #list > MAX_SAMPLES then table.remove(list, 1) end
					rec.hp[lvl] = list
				end
			end
		end
	end
	ns:Fire("CHANGED", "creature")
end

-- about how much health it has (median of clean kills), and from how many samples
function B:Health(rec, lvl)
	if not rec.hp then return nil end
	local list = lvl and rec.hp[lvl]
	if not list then
		-- the level with the most samples
		for _, l in pairs(rec.hp) do if not list or #l > #list then list = l end end
	end
	if not list or #list == 0 then return nil end
	local s = {}
	for i, v in ipairs(list) do s[i] = v end
	table.sort(s)
	return s[math.floor((#s + 1) / 2)], #s
end

---------------------------------------------------------------------------
-- Loot
---------------------------------------------------------------------------

local function MoneyFromText(text)
	if type(text) ~= "string" then return 0 end
	-- "1 Gold\n5 Silver\n12 Copper" (English, or the client's own words for the coins)
	local function Coin(word, fallback)
		return tonumber(text:match("(%d+)%s*" .. tostring(word or fallback))) or tonumber(text:match("(%d+)%s*" .. fallback)) or 0
	end
	return Coin(GOLD, "Gold") * 10000 + Coin(SILVER, "Silver") * 100 + Coin(COPPER, "Copper")
end

local function OnLoot()
	if not (GetNumLootItems and GetLootSourceInfo) then return end
	if R(IsFishingLoot and IsFishingLoot()) == true then return end
	local gathering = GetTime() - lastGather < 3
	local byCorpse = {}
	for slot = 1, GetNumLootItems() do
		local link = R(GetLootSlotLink(slot))
		local item = type(link) == "string" and tonumber(link:match("item:(%d+)"))
		local money = 0
		if not item then
			local okI, _, name = pcall(GetLootSlotInfo, slot)
			money = okI and MoneyFromText(R(name)) or 0
		end
		local sources = { pcall(GetLootSourceInfo, slot) }
		if sources[1] then
			for i = 2, #sources, 2 do
				local guid = R(sources[i])
				local npc = ns.NpcFromGuid(guid)
				if npc then
					local c = byCorpse[guid] or { npc = npc, items = {}, money = 0 }
					byCorpse[guid] = c
					if item then c.items[item] = true end
					c.money = c.money + money
				end
			end
		end
	end
	for guid, c in pairs(byCorpse) do
		local rec = ns.Store:Get("creature", c.npc)
		if rec then
			-- a corpse you can loot was a kill (if it wasn't counted yet)
			if not looted[guid] and not gathering then CountKill(guid, c.npc) end
			if gathering and skinned[guid] then
				-- the same skinning window again
			elseif gathering then
				skinned[guid] = GetTime()
				rec.gathered = (rec.gathered or 0) + 1
				rec.gather = rec.gather or {}
				for item in pairs(c.items) do rec.gather[item] = (rec.gather[item] or 0) + 1 end
			elseif not looted[guid] then
				looted[guid] = true
				rec.corpses = (rec.corpses or 0) + 1
				rec.loot = rec.loot or {}
				for item in pairs(c.items) do rec.loot[item] = (rec.loot[item] or 0) + 1 end
				if c.money > 0 then
					rec.money = rec.money or { 0, 0 }
					rec.money[1], rec.money[2] = rec.money[1] + 1, rec.money[2] + c.money
				end
			end
		end
	end
	ns:Fire("CHANGED", "creature")
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

ns:RegisterEvent("PLAYER_TARGET_CHANGED", function()
	if not ns.db then return end
	ns.doing = "reading your target"
	B:Seen("target")
	B:CheckDead("target")
end)
ns:RegisterEvent("UPDATE_MOUSEOVER_UNIT", function()
	if ns.db then B:Seen("mouseover") end
end)
ns:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, unit)
	if ns.db then B:Seen(unit) end
end)
ns:RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, unit)
	if ns.db then B:CheckDead(unit) end
end)
ns:RegisterEvent("UNIT_FLAGS", function(_, unit)
	if ns.db and unit == "target" then B:CheckDead("target") end
end)
ns:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT", function()
	if not ns.db then return end
	for i = 1, 5 do
		if R(UnitExists("boss" .. i)) == true then B:Seen("boss" .. i, true) end
	end
end)
ns:RegisterEvent("PLAYER_REGEN_DISABLED", function()
	fight = { names = {}, guids = {}, deaths = {} }
	if ns.db then
		B:Seen("target")
		for _, plate in ipairs(C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}) do
			local unit = plate.namePlateUnitToken
			if unit then B:Seen(unit) end
		end
	end
end)
ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
	if not ns.db then return end
	-- deaths the fight ended with (your target, nameplates still up), then close the fight
	B:CheckDead("target")
	for _, plate in ipairs(C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}) do
		local unit = plate.namePlateUnitToken
		if unit then B:CheckDead(unit) end
	end
	local f = fight
	fight = nil
	C_Timer.After(1, function()
		ns.doing = "reading the damage meter"
		ReadMeter(f)
		ReadMyDebuffs()
		ns.doing = "idle"
	end)
end)
ns:RegisterEvent("UNIT_AURA", function(_, unit)
	if ns.db and unit == "player" and not InCombatLockdown() then ReadMyDebuffs() end
end)
for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START" }) do
	ns:RegisterEvent(e, function(_, unit, _, spellID)
		if ns.db then OnCast(unit, spellID) end
	end)
end
-- gathering casts (skinning, herbs, mining) just before a loot window
-- (only Skinning: herbs and veins are objects, which the gathering recorder handles; a corpse looted
-- right after a herb was picked is a corpse, not a pelt)
local GATHER = { [L["Skinning"]] = true }
ns:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
	if unit ~= "player" then return end
	spellID = R(spellID)
	if type(spellID) ~= "number" then return end
	local name
	if C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
		name = ok and type(info) == "table" and R(info.name)
	elseif GetSpellInfo then
		name = GetSpellInfo(spellID)
	end
	if name and GATHER[name] then lastGather = GetTime() end
end)
ns:RegisterEvent("LOOT_READY", function()
	if not ns.db then return end
	ns.doing = "reading loot"
	OnLoot()
	ns.doing = "idle"
end)

---------------------------------------------------------------------------
-- Tooltip line on creatures: "Almanac: Studied - 7 kills"
---------------------------------------------------------------------------

local function TooltipLine(tooltip)
	if not (ns.db and Settings().bestiary.tooltip) then return end
	local guid = R(UnitGUID("mouseover"))
	local npc = ns.NpcFromGuid(guid)
	if not npc then return end
	local rec = ns.Store:Get("creature", npc)
	if not rec then
		tooltip:AddLine("|cff66ccff" .. L["Almanac:"] .. "|r " .. L["not yet in your Almanac"], 0.7, 0.7, 0.7)
		return
	end
	local tier, need = B:Tier(rec)
	local text = ("|cff66ccff%s|r %s %s"):format(L["Almanac:"], B:TierMarkup(tier, 16), B:TierText(tier))
	if (rec.kills or 0) > 0 then text = text .. " - " .. ns.N(rec.kills, "kill", "kills") end
	if need then text = text .. " |cff999999" .. (L["(%d to %s)"]):format(need, B.TIERS[tier + 1]) .. "|r " .. B:TierMarkup(tier + 1, 12) end
	tooltip:AddLine(text, 1, 1, 1)
	-- Studied and up: its abilities, each with its icon (melee left out)
	if tier >= 3 and ns.CreatureDB then
		local known = ns.CreatureDB:KnownSpells(npc, rec, tier)
		local list = {}
		for id in pairs(known) do
			if id ~= 6603 then
				local name, icon
				if C_Spell and C_Spell.GetSpellInfo then
					local ok, info = pcall(C_Spell.GetSpellInfo, id)
					if ok and type(info) == "table" then name, icon = info.name, info.iconID end
				elseif GetSpellInfo then
					local n, _, tex = GetSpellInfo(id)
					name, icon = n, tex
				end
				if name then list[#list + 1] = { name = name, icon = icon } end
			end
		end
		table.sort(list, function(a, b) return a.name < b.name end)
		local MAX = 8
		for i = 1, math.min(#list, MAX) do
			local a = list[i]
			tooltip:AddLine("   " .. (a.icon and ("|T" .. a.icon .. ":14:14:0:0:64:64:5:59:5:59|t ") or "") .. a.name, 0.85, 0.85, 0.85)
		end
		if #list > MAX then tooltip:AddLine("   " .. (L["+%d more in the Bestiary"]):format(#list - MAX), 0.6, 0.6, 0.6) end
	end
end

function B:OnLogin()
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
			if tooltip == GameTooltip then pcall(TooltipLine, tooltip) end
		end)
	elseif GameTooltip and GameTooltip.HookScript then
		pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tooltip) pcall(TooltipLine, tooltip) end)
	end
end

ns:On("RESET", function() byName = nil end)
