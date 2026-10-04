-- Ported from Plus Everything (same author) for Azeroth Almanac's quality-of-life helpers.
-- Healer assist: a strip of clickable spell icons for every group member. The icons that fit the
-- member's state light up and the best choice flashes yellow (like the Spell Ranker). Click an icon
-- to cast that spell on that member.
--   Shows heals, heal-over-times and shields (best pick depends on missing health, whether the member
--   is tanking and how low they are), cures for poison / disease / curse / magic, resurrections and
--   (optional) buffs that are missing.
--   Modes: on the Blizzard party / raid frames, or in a movable queue panel. /aa heal for commands.
--
-- The icons are secure buttons, which the game won't let an addon create, move or hide during combat.
-- So the layout is set up out of combat (and re-done as soon as combat ends); in combat the icons
-- only change brightness, flash and numbers. Spell names are matched in English.

local _, A = ...
local ns = A.QoL
local HA = ns:NewModule("HealAssist")

local TICK = 0.2
local GAP = 2
local LABEL_W, HEADER_H = 150, 24
local BAR_H, NAME_H, GROUP_GAP = 16, 11, 5
local PREDICT_COLOR = { 0, 0.83, 0.77 }   -- the game's colour for incoming heals
local HEALTH_COLOR = { 0.28, 0.8, 0.14 }  -- the game's unit-frame green
local DIM, OFF, ABSENT = 0.32, 0.55, 0.12
local HIGHLIGHT_ATLAS = "UI-HUD-ActionBar-IconFrame-Mouseover"
local SOUND_ALERT = 8959

local R = function(v) return ns.Readable(v) end

---------------------------------------------------------------------------
-- What each class can do
---------------------------------------------------------------------------

local function S(name, kind, extra)
	extra = extra or {}
	extra.name, extra.kind = name, kind
	return extra
end

-- kind: heal (direct), hot (heal over time), shield, cleanse, res, buff
local CATALOG = {
	SHAMAN = {
		S("Healing Wave", "heal"), S("Lesser Healing Wave", "heal"), S("Chain Heal", "heal"),
		S("Cure Poison", "cleanse", { cures = { Poison = true } }),
		S("Cure Disease", "cleanse", { cures = { Disease = true } }),
		S("Ancestral Spirit", "res"),
	},
	PRIEST = {
		S("Lesser Heal", "heal"), S("Heal", "heal"), S("Greater Heal", "heal"), S("Flash Heal", "heal"),
		S("Renew", "hot"), S("Power Word: Shield", "shield"),
		S("Abolish Disease", "cleanse", { cures = { Disease = true } }),
		S("Cure Disease", "cleanse", { cures = { Disease = true } }),
		S("Dispel Magic", "cleanse", { cures = { Magic = true } }),
		S("Resurrection", "res"),
		S("Power Word: Fortitude", "buff", { alias = { "Prayer of Fortitude" } }),
		S("Divine Spirit", "buff", { alias = { "Prayer of Spirit" } }),
	},
	DRUID = {
		S("Healing Touch", "heal"), S("Regrowth", "heal"), S("Rejuvenation", "hot"),
		S("Abolish Poison", "cleanse", { cures = { Poison = true } }),
		S("Cure Poison", "cleanse", { cures = { Poison = true } }),
		S("Remove Curse", "cleanse", { cures = { Curse = true } }),
		S("Revive", "res"), S("Rebirth", "res", { combatRes = true }),
		S("Mark of the Wild", "buff", { alias = { "Gift of the Wild" } }),
		S("Thorns", "buff"),
	},
	PALADIN = {
		S("Holy Light", "heal"), S("Flash of Light", "heal"),
		S("Purify", "cleanse", { cures = { Poison = true, Disease = true } }),
		S("Cleanse", "cleanse", { cures = { Poison = true, Disease = true, Magic = true } }),
		S("Redemption", "res"),
	},
	-- pet care: these only work on your own pet (petOnly)
	HUNTER = {
		S("Mend Pet", "hot", { petOnly = true }),
		S("Revive Pet", "res", { petOnly = true, combatRes = true }),
		S("Call Pet", "summon", { petOnly = true }),
	},
	WARLOCK = {
		S("Health Funnel", "funnel", { petOnly = true }),
		S("Summon Imp", "summon", { petOnly = true }),
		S("Summon Voidwalker", "summon", { petOnly = true }),
		S("Summon Succubus", "summon", { petOnly = true }),
		S("Summon Felhunter", "summon", { petOnly = true }),
		S("Summon Felguard", "summon", { petOnly = true }),
	},
	MAGE = {
		S("Remove Curse", "cleanse", { cures = { Curse = true } }),
		S("Arcane Intellect", "buff", { alias = { "Arcane Brilliance" } }),
	},
}

-- A cure that's already ticking: its debuff type needs no new cure.
local ABOLISH = { Poison = "Abolish Poison", Disease = "Abolish Disease" }

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local db
local mine = {}          -- the catalog entries you know, with spell id / icon / cast time: { spell, id, icon, castTime, cost }
local entries = {}       -- unit token -> { token, buttons = { [spell name] = button }, order = { names }, res = last result }
local roster = {}        -- unit tokens in the group right now
local panel
local needLayout = true
local layoutKey = ""
local lastFrameCheck = 0
local testUntil = 0
local hover              -- { button, token, amount } while the mouse is over a heal icon
local lingerUntil = 0    -- "only in combat" keeps showing until this time after combat ends
local hurtNow = false    -- someone in the group (or you) is missing health, so "only in combat" shows anyway
local anyHidden = false  -- the game is hiding at least one member's health
local maxCache = {}      -- token -> last readable maximum health, for members whose maximum is hidden
local holder             -- the secure frame all the icons live in
local shownState = nil
local selfCast = nil     -- { target = name } while you're casting one of your heals
local amountCache = {}
local alerted = {}
local flashFrame

---------------------------------------------------------------------------
-- Game data helpers
---------------------------------------------------------------------------

-- "Only in combat" needs the icons shown the instant combat starts, which only the game's own
-- secure code may do. So every icon is a child of this holder, and while the icons should be
-- hidden the holder carries the game's "[combat] show; hide" visibility driver. For the "keep
-- showing for a few seconds" time the driver is taken off (out of combat) and put back when
-- the time is up.
local function Holder()
	if holder then return holder end
	holder = CreateFrame("Frame", "AzerothAlmanacHealHolder", UIParent, "SecureHandlerStateTemplate")
	holder:SetSize(1, 1)
	holder:SetPoint("CENTER")
	return holder
end

local function SpellName(id)
	if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
	return GetSpellInfo(id)
end

local function RankOf(id)
	local sub = C_Spell and C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id)
		or GetSpellSubtext and GetSpellSubtext(id)
	return sub and tonumber(sub:match("(%d+)%s*$")) or 0
end

local function SpellTexture(id)
	if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
	return select(3, GetSpellInfo(id))
end

local function CastTime(id)
	local ms
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(id)
		ms = info and info.castTime
	else
		ms = select(4, GetSpellInfo(id))
	end
	return (ms or 0) / 1000
end

local function ManaCost(id)
	local costs = C_Spell and C_Spell.GetSpellPowerCost and C_Spell.GetSpellPowerCost(id)
		or GetSpellPowerCost and GetSpellPowerCost(id)
	if type(costs) == "table" then
		for _, c in ipairs(costs) do
			if c.type == 0 then return c.cost or c.minCost or 0 end
		end
	end
	return 0
end

local function Num(text)
	return tonumber((tostring(text):gsub(",", ""))) or 0
end

-- What the spell heals (or absorbs), read from its own tooltip so spell power is included.
local function SpellAmount(m)
	local cached = amountCache[m.id]
	local now = GetTime()
	-- a good reading is kept for 10 seconds; a failed one (the tooltip hadn't loaded) is retried
	-- after a second, and meanwhile the last good reading is used
	if cached and cached.v > 0 and now - cached.t < 10 then return cached.v end
	if cached and cached.v == 0 and now - cached.t < 1 then return cached.good or 0 end
	local tip = HA.scan
	if not tip then
		tip = CreateFrame("GameTooltip", "AzerothAlmanacHealScan", nil, "GameTooltipTemplate")
		HA.scan = tip
	end
	tip:SetOwner(UIParent, "ANCHOR_NONE")
	local value = 0
	if pcall(tip.SetSpellByID, tip, m.id) then
		for i = 2, tip:NumLines() do
			local fs = _G["AzerothAlmanacHealScanTextLeft" .. i]
			local text = fs and R(fs:GetText())
			if text then
				local a, b = text:match("(%d[%d,]*) to (%d[%d,]*)")
				if a then value = (Num(a) + Num(b)) / 2 break end
				local single = text:match("for (%d[%d,]*) over") or text:match("absorbs (%d[%d,]*)")
				if single then value = Num(single) break end
			end
		end
	end
	tip:Hide()
	if value > 0 then
		amountCache[m.id] = { v = value, t = now, good = value }
		return value
	end
	-- nothing readable: ask the game to load the spell, and use the last good reading if there is one
	if C_Spell and C_Spell.RequestLoadSpellData then C_Spell.RequestLoadSpellData(m.id) end
	local good = cached and cached.good
	amountCache[m.id] = { v = 0, t = now, good = good }
	return good or 0
end

local function Short(n)
	if n >= 10000 then return ("%dk"):format(n / 1000 + 0.5) end
	if n >= 1000 then return ("%.1fk"):format(n / 1000) end
	return tostring(math.floor(n + 0.5))
end

-- Your spells from the catalog, at their highest rank.
local function ResolveSpells()
	wipe(mine)
	local _, class = UnitClass("player")
	local list = CATALOG[class]
	if not list or not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return end
	local wanted = {}
	for _, spell in ipairs(list) do
		if spell.kind ~= "buff" or db.buffs then wanted[spell.name] = spell end
	end
	local found = {}
	local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
	for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if info and not info.offSpecID then
			for index = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
				local item = C_SpellBook.GetSpellBookItemInfo(index, bank)
				if item and item.itemType == Enum.SpellBookItemType.Spell and item.spellID then
					local name = item.name or SpellName(item.spellID)
					if name and wanted[name] then
						local rank = RankOf(item.spellID)
						if not found[name] or rank > found[name].rank then found[name] = { id = item.spellID, rank = rank } end
					end
				end
			end
		end
	end
	for _, spell in ipairs(list) do
		local f = found[spell.name]
		if f then
			mine[#mine + 1] = {
				spell = spell, id = f.id, icon = SpellTexture(f.id),
				castTime = CastTime(f.id), cost = ManaCost(f.id),
			}
		end
	end
	wipe(amountCache)
end

local function InRange(name, token)
	if token == "player" then return true end
	local r
	if C_Spell and C_Spell.IsSpellInRange then r = C_Spell.IsSpellInRange(name, token)
	elseif IsSpellInRange then r = IsSpellInRange(name, token) end
	r = R(r)
	if r == false or r == 0 then return false end
	return true
end

local function Cooldown(name)
	local start, duration
	if C_Spell and C_Spell.GetSpellCooldown then
		local info = C_Spell.GetSpellCooldown(name)
		if info then start, duration = info.startTime, info.duration end
	elseif GetSpellCooldown then
		start, duration = GetSpellCooldown(name)
	end
	start, duration = R(start), R(duration)
	if type(start) ~= "number" or type(duration) ~= "number" then return 0, 0 end
	return start, duration
end

---------------------------------------------------------------------------
-- The group
---------------------------------------------------------------------------

-- do you know any pet-care spells (a hunter's Mend Pet, a warlock's Health Funnel ...)?
local function HasPetSpells()
	for _, m in ipairs(mine) do
		if m.spell.petOnly then return true end
	end
	return false
end

local function Units()
	local list = { "player" }
	local pets = {}
	if IsInRaid() then
		list = {}
		for i = 1, GetNumGroupMembers() do
			local token, pet = "raid" .. i, "raidpet" .. i
			if R(UnitIsUnit(token, "player")) then token, pet = "player", "pet" end
			if token ~= "player" or db.includeSelf then
				list[#list + 1] = token
				pets[#pets + 1] = pet
			end
		end
	elseif IsInGroup() then
		if not db.includeSelf then list = {} else pets[1] = "pet" end
		for i = 1, GetNumSubgroupMembers() do
			list[#list + 1] = "party" .. i
			pets[#pets + 1] = "partypet" .. i
		end
	else
		pets[1] = "pet"
	end
	if db.pets then
		for _, pet in ipairs(pets) do list[#list + 1] = pet end
	end
	-- a hunter's or warlock's own pet is always cared for, whatever the pets option says
	if db.petCare and HasPetSpells() then
		local has = false
		for _, t in ipairs(list) do if t == "pet" then has = true end end
		if not has then list[#list + 1] = "pet" end
	end
	return list
end

-- "Only in combat" wants everything hidden right now: out of combat, not in a test run and not
-- within the "keep showing after combat" time.
local function WantHidden()
	if not db.combatOnly then return false end
	local now = GetTime()
	return testUntil <= now and now >= lingerUntil and not InCombatLockdown()
end

-- When the game hides a member's health, "is anyone hurt?" can't be answered in code, so with
-- "also show while anyone is hurt" the icons and rows stay in place and each member's own part
-- fades in only while that member is hurt (the game's health-percent curves drive their alpha).
local function SoftHidden()
	return db.showWhenHurt and anyHidden and WantHidden()
end

local function HideOutOfCombat()
	if not WantHidden() then return false end
	if db.showWhenHurt and (hurtNow or anyHidden) then return false end
	return true
end

local function Enabled()
	if not db.enabled or #mine == 0 then return false end
	return IsInGroup() or db.solo or testUntil > GetTime() or (db.petCare and HasPetSpells())
end

-- Buffs, and debuffs by type, on a unit: debuffTypes[type], debuffNames[name], buffNames[name].
local function ScanAuras(e)
	e.auraDirty = false
	local debuffTypes, debuffNames, buffNames = {}, {}, {}
	local token = e.token
	local blocked = false
	-- In combat the game can refuse to hand an addon a unit's auras (it raises an error rather than
	-- returning nothing), so every call is protected and a refusal just means "no aura info".
	local function each(filter, fn)
		local byIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
		local get = filter == "HARMFUL" and UnitDebuff or UnitBuff
		for i = 1, 40 do
			if byIndex then
				local ok, a = pcall(byIndex, token, i, filter)
				if not ok then blocked = true return end
				a = R(a)
				if not a then return end
				fn(R(a.name), R(a.dispelName))
			elseif get then
				local ok, name, _, _, kind = pcall(get, token, i)
				if not ok then blocked = true return end
				if not name then return end
				fn(R(name), R(kind))
			else
				return
			end
		end
	end
	each("HARMFUL", function(name, kind)
		if name then debuffNames[name] = true end
		if type(kind) == "string" and kind ~= "" then debuffTypes[kind] = true end
	end)
	each("HELPFUL", function(name) if name then buffNames[name] = true end end)
	if blocked and e.debuffTypes then
		-- keep what we knew from before combat rather than forgetting it
		e.auraBlocked = true
		return
	end
	e.auraBlocked = blocked
	e.debuffTypes, e.debuffNames, e.buffNames = debuffTypes, debuffNames, buffNames
end

---------------------------------------------------------------------------
-- What to suggest
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Who has aggro
---------------------------------------------------------------------------

local mobs = {}       -- hostile units in combat we can ask about: nameplates, target, focus, bosses
local lastThreat = 0

local function CollectMobs()
	wipe(mobs)
	local seen = {}
	local function add(unit, needGuid)
		if not R(UnitExists(unit)) then return end
		if not R(UnitCanAttack("player", unit)) or R(UnitIsDead(unit)) ~= false then return end
		if not R(UnitAffectingCombat(unit)) then return end
		local guid = R(UnitGUID(unit))
		if guid then
			if seen[guid] then return end
			seen[guid] = true
		elseif needGuid then
			return   -- can't tell whether it's an enemy we already have
		end
		mobs[#mobs + 1] = unit
	end
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
			local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
			if unit then add(unit, false) end
		end
	end
	add("target", true)
	add("focus", true)
	for i = 1, 5 do add("boss" .. i, true) end
end

-- For every member: how many enemies are attacking them (threat status 2 or 3 on that enemy),
-- the highest status, and who they are. Falls back to the plain "has aggro" status when the
-- game won't say it per enemy.
local function ScanThreat(now)
	lastThreat = now
	CollectMobs()
	for _, token in ipairs(roster) do
		local e = entries[token]
		if e then
			local count, level, list = 0, 0, {}
			if R(UnitExists(token)) then
				for _, mob in ipairs(mobs) do
					local st = R(UnitThreatSituation(token, mob))
					if type(st) == "number" and st >= 1 then
						if st > level then level = st end
						if st >= 2 then
							count = count + 1
							list[#list + 1] = { name = R(UnitName(mob)) or "Enemy", status = st }
						end
					end
				end
				if count == 0 then
					local overall = R(UnitThreatSituation(token))
					if type(overall) == "number" and overall >= 2 then
						count, level = 1, math.max(level, overall)
						list[#list + 1] = { name = "an enemy", status = overall, unknown = true }
					end
				end
			end
			e.threat = { count = count, level = level, list = list }
		end
	end
	if testUntil > now and entries.player then
		entries.player.threat = {
			count = 2, level = 3,
			list = { { name = "Test Wolf", status = 3 }, { name = "Test Boar", status = 2 } },
		}
	end
end

local function IsTank(token)
	if UnitGroupRolesAssigned and R(UnitGroupRolesAssigned(token)) == "TANK" then return true end
	if GetPartyAssignment and R(GetPartyAssignment("MAINTANK", token)) then return true end
	return false
end

-- The smallest heal that covers (about) what's missing, else the biggest; or the fastest.
local function PickEfficient(cands, missing)
	table.sort(cands, function(a, b) return a.amount < b.amount end)
	for _, c in ipairs(cands) do
		if c.amount >= missing * (db.cover / 100) then return c end
	end
	return cands[#cands]
end

local function PickFastest(cands)
	table.sort(cands, function(a, b)
		if a.m.castTime ~= b.m.castTime then return a.m.castTime < b.m.castTime end
		return a.amount > b.amount
	end)
	return cands[1]
end

local function Evaluate(e, now)
	local token = e.token
	local res = { rel = {}, flash = {}, text = {}, amounts = {}, net = {}, soft = {}, score = 0 }
	if not R(UnitExists(token)) then
		if token == "pet" and HasPetSpells() then
			-- no pet out: offer to call or summon one
			local call
			for _, m in ipairs(mine) do
				if m.spell.kind == "summon" or (m.spell.kind == "res" and m.spell.petOnly) then
					res.rel[m.spell.name] = true
					res.text[m.spell.name] = "You have no pet out."
					if m.spell.name == "Call Pet" then call = m end
				end
			end
			if call then res.flash[call.spell.name] = true end
			res.noPet = true
			res.score = 40
			return res
		end
		res.absent = true
		return res
	end
	local test = testUntil > now and token == "player"
	if R(UnitIsConnected(token)) == false and not test then res.absent = true return res end

	local dead = (not test) and R(UnitIsDeadOrGhost(token)) == true
	if dead and e.pet and not (token == "pet" and HasPetSpells()) then res.absent = true return res end
	local cur, max = R(UnitHealth(token)), R(UnitHealthMax(token))
	local pct, missing
	if type(max) == "number" and max > 0 then
		maxCache[token] = max
	else
		-- the maximum is hidden too: use the last one seen, else assume the same as yours
		local guess = maxCache[token]
		if not guess then
			local mine_ = R(UnitHealthMax("player"))
			if type(mine_) == "number" and mine_ > 0 then guess = mine_ end
		end
		if guess then max = guess res.maxGuess = true end
	end
	if type(cur) == "number" and type(max) == "number" and max > 0 and not res.maxGuess then pct, missing = cur / max, max - cur end
	local st = R(UnitThreatSituation(token))
	local aggro = type(st) == "number" and st >= 2
	local threat = e.threat
	if threat and threat.count > 0 then aggro = true end
	-- several enemies on one member: more urgent, and the fast heal comes in a little earlier
	local nAgg = (threat and threat.count > 0) and threat.count or (aggro and 1 or 0)
	local crit = math.min(0.5, (db.critical + math.min(15, 5 * math.max(0, nAgg - 1))) / 100)
	if e.auraDirty or not e.debuffTypes then ScanAuras(e) end
	local debuffTypes, debuffNames, buffNames = e.debuffTypes, e.debuffNames, e.buffNames
	if test then
		max = type(max) == "number" and max > 0 and max or 3000
		pct, missing, aggro = 0.45, max * 0.55, true
		debuffTypes = { Poison = true }
	end
	res.pct, res.aggro, res.dead = pct, aggro, dead
	local inCombat = InCombatLockdown()

	-- the dead
	if dead then
		local first
		for _, m in ipairs(mine) do
			if m.spell.kind == "res" and (not inCombat or m.spell.combatRes) then
				res.rel[m.spell.name] = true
				res.text[m.spell.name] = "Resurrect " .. (UnitName(token) or "them") .. "."
				first = first or m
			end
		end
		if first then res.flash[first.spell.name] = true res.score = 300 end
		return res
	end

	local mana = R(UnitPower("player", 0))
	if type(mana) ~= "number" then mana = math.huge end

	-- cures
	local present = {}
	for kind in pairs(debuffTypes) do
		if not (ABOLISH[kind] and buffNames[ABOLISH[kind]]) then present[kind] = true end
	end
	local cure
	for _, m in ipairs(mine) do
		if m.spell.kind == "cleanse" then
			for kind in pairs(m.spell.cures) do
				if present[kind] then
					res.rel[m.spell.name] = true
					res.text[m.spell.name] = "Removes " .. kind:lower() .. " from " .. (UnitName(token) or "them") .. "."
					cure = cure or m
					break
				end
			end
		end
	end
	if cure then res.score = res.score + 400 end
	if e.auraBlocked then
		-- debuffs can't be seen in combat: offer the cures anyway, a little dimmer, never flashing
		for _, m in ipairs(mine) do
			if m.spell.kind == "cleanse" and not res.rel[m.spell.name] then
				res.rel[m.spell.name] = true
				res.soft[m.spell.name] = true
				res.text[m.spell.name] = "The game hides debuffs in combat, so this cure is always offered."
			end
		end
	end

	-- heals
	local casting = selfCast and selfCast.target and selfCast.target == UnitName(token)
	if pct then
		local incoming = type(UnitGetIncomingHeals) == "function" and R(UnitGetIncomingHeals(token)) or 0
		if type(incoming) ~= "number" then incoming = 0 end
		local effective = math.max(0, missing - incoming)
		-- "ignore small wounds" scales down for low-health characters: at most 12% of their health
		local floor = math.max((max or 0) * 0.04, math.min(db.minMissing, (max or 0) * 0.12))
		local need = pct < 0.97 and missing >= floor
		res.hurt = need
		if need then
			local heals, hots, anyShield = {}, {}, false
			for _, m in ipairs(mine) do
				local kind = m.spell.kind
				if (kind == "heal" or kind == "hot" or kind == "shield") and (not m.spell.petOnly or token == "pet") then
					local amount = SpellAmount(m)
					local c = { m = m, amount = amount, ok = m.cost <= mana }
					-- (a spell whose amount couldn't be read yet is shown but isn't picked or given a number)
					if amount > 0 or m.spell.petOnly then
						if kind == "heal" then heals[#heals + 1] = c
						elseif kind == "hot" then hots[#hots + 1] = c end
					end
					if kind ~= "shield" or (aggro and not debuffNames["Weakened Soul"]) then
						res.rel[m.spell.name] = true
						res.amounts[m.spell.name] = amount
						if kind ~= "shield" and amount > 0 then res.net[m.spell.name] = amount - effective end
						res.text[m.spell.name] = ("%s: heals about %d, %d missing (%s)."):format(m.spell.name, amount, effective,
							amount >= effective and ("about " .. math.floor(amount - effective) .. " overheal") or ("about " .. math.floor(effective - amount) .. " short"))
					end
					if not c.ok then res.text[m.spell.name] = (res.text[m.spell.name] or m.spell.name) .. " Not enough mana." end
				end
			end
			local usable = {}
			for _, c in ipairs(heals) do if c.ok then usable[#usable + 1] = c end end
			if #usable == 0 then usable = heals end

			local pick, why
			local critical = aggro and pct <= crit
			-- your own pet: Mend Pet whenever it's hurt and isn't already on it, under attack or not
			local petHot
			for _, c in ipairs(hots) do
				if c.m.spell.petOnly and not buffNames[c.m.spell.name] and c.ok then petHot = c break end
			end
			if petHot then
				pick, why = petHot, "Your pet is hurt and has no Mend Pet on it."
			elseif critical and #usable > 0 then
				pick, why = PickFastest(usable), "Very low and under attack: the fastest heal."
			elseif aggro and #usable > 0 then
				pick = PickEfficient(usable, effective)
				why = ("Under attack, about %d missing: the smallest heal that covers it, to avoid overhealing."):format(effective)
			elseif #hots > 0 then
				for _, c in ipairs(hots) do
					if not buffNames[c.m.spell.name] and c.ok then
						pick, why = c, "Not under attack: a heal over time is enough."
						break
					end
				end
				if not pick and pct <= 0.5 and #usable > 0 then
					pick, why = PickEfficient(usable, effective), "Low, and the heal over time is already on them."
				end
			elseif #usable > 0 then
				pick, why = PickEfficient(usable, effective), ("About %d missing: the most efficient heal."):format(effective)
			end
			if pick and not casting and pick.ok then
				res.flash[pick.m.spell.name] = true
				res.text[pick.m.spell.name] = (res.text[pick.m.spell.name] or "") .. "\n|cffffd100Recommended:|r " .. why
			end
			-- a warlock's Health Funnel: it costs your health, so it only flashes when the pet is low and you can spare it
			for _, m in ipairs(mine) do
				if m.spell.kind == "funnel" and token == "pet" then
					local own, ownMax = R(UnitHealth("player")), R(UnitHealthMax("player"))
					res.rel[m.spell.name] = true
					res.text[m.spell.name] = "Health Funnel gives your pet health at the cost of your own."
					if pct <= 0.5 and not casting and type(own) == "number" and type(ownMax) == "number" and ownMax > 0 and own / ownMax > 0.6 then
						res.flash[m.spell.name] = true
						res.text[m.spell.name] = res.text[m.spell.name] .. "\n|cffffd100Recommended:|r your pet is low and you have health to spare."
					end
				end
			end
			res.score = res.score + (1 - pct) * 600 + (aggro and 300 or 0) + (critical and 500 or 0)
				+ math.max(0, nAgg - 1) * 120
			if critical then
				-- the heal comes first: don't flash a cure over it
				if cure then res.flash[cure.spell.name] = nil end
			end
		end
	elseif type(max) == "number" and max > 0 then
		-- The game hides current health in combat; only the maximum can be read. Every heal is
		-- offered and the flashing pick follows the game's own health-percent curves (ApplyVisuals).
		local heals, hots = {}, {}
		for _, m in ipairs(mine) do
			local kind = m.spell.kind
			if (kind == "heal" or kind == "hot" or kind == "shield") and (not m.spell.petOnly or token == "pet") then
				local amount = SpellAmount(m)
				local c = { m = m, amount = amount, ok = m.cost <= mana }
				if amount > 0 or m.spell.petOnly then
					if kind == "heal" then heals[#heals + 1] = c
					elseif kind == "hot" then hots[#hots + 1] = c end
				end
				if kind ~= "shield" or (aggro and not debuffNames["Weakened Soul"]) then
					res.rel[m.spell.name] = true
					res.amounts[m.spell.name] = amount
					res.text[m.spell.name] = ("%s: heals about %d."):format(m.spell.name, amount)
				end
			end
		end
		local usable = {}
		for _, c in ipairs(heals) do if c.ok then usable[#usable + 1] = c end end
		if #usable == 0 then usable = heals end
		res.hidden = { max = max, aggro = aggro, crit = crit, heals = usable, hots = hots, buffs = buffNames }
		-- a rough pick for when the curves aren't available: the fastest heal on someone under
		-- attack, otherwise the heal over time
		local pick
		local petHot
		for _, c in ipairs(hots) do
			if c.m.spell.petOnly and not buffNames[c.m.spell.name] and c.ok then petHot = c break end
		end
		-- (your pet's Health Funnel is offered but never flashed here: your own health is hidden too)
		for _, m in ipairs(mine) do
			if m.spell.kind == "funnel" and token == "pet" then
				res.rel[m.spell.name] = true
				res.text[m.spell.name] = "Health Funnel gives your pet health at the cost of your own."
			end
		end
		if petHot then
			pick = petHot
		elseif aggro and #usable > 0 then
			local copy = {}
			for _, c in ipairs(usable) do copy[#copy + 1] = c end
			pick = PickFastest(copy)
		else
			for _, c in ipairs(hots) do
				if not buffNames[c.m.spell.name] and c.ok then pick = c break end
			end
		end
		if pick and not casting then
			res.flash[pick.m.spell.name] = true
			res.text[pick.m.spell.name] = (res.text[pick.m.spell.name] or "") .. "\n|cffffd100Suggested:|r health is hidden in combat, so this is a rough pick."
		end
		if aggro then res.score = res.score + 300 + math.max(0, nAgg - 1) * 120 end
	end
	if cure and (res.flash[cure.spell.name] == nil) and not (aggro and pct and pct <= crit) then
		res.flash[cure.spell.name] = true
	end

	-- missing buffs, out of combat
	if db.buffs and not inCombat and not e.pet then
		for _, m in ipairs(mine) do
			if m.spell.kind == "buff" then
				local has = buffNames[m.spell.name]
				for _, alias in ipairs(m.spell.alias or {}) do has = has or buffNames[alias] end
				if not has and (token == "player" or (R(UnitIsVisible(token)) and InRange(m.spell.name, token))) then
					res.rel[m.spell.name] = true
					res.text[m.spell.name] = m.spell.name .. " is missing."
					res.score = res.score + 50
				end
			end
		end
	end

	if casting then res.casting = true end
	if db.tankFirst and res.score > 0 and IsTank(token) then res.score = res.score + 150 end
	if e.pet then res.score = res.score * 0.6 end   -- pets rank below people
	return res
end

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------

local function HasAtlas(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function SetFlash(b, on)
	if b.flashing == on then return end
	b.flashing = on
	if on then
		b.glow:Show()
		b.pulse:Play()
	else
		b.pulse:Stop()
		b.glow:Hide()
	end
end

local function ButtonTip(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if self.spellID then GameTooltip:SetSpellByID(self.spellID) end
	local text = self.tip
	if text and text ~= "" then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(text, 1, 1, 1, true)
	end
	GameTooltip:AddLine("Click to cast on " .. (UnitName(self.token) or self.token) .. ".", 0.6, 0.8, 1)
	GameTooltip:Show()
	-- the heal-preview on their health bar
	local kind = self.m.spell.kind
	if kind == "heal" or kind == "hot" then hover = { button = self, token = self.token, amount = SpellAmount(self.m) } end
end

local function MakeButton(e, m)
	local size = db.iconSize
	local b = CreateFrame("Button", nil, Holder(), "SecureActionButtonTemplate")
	b:SetFrameStrata("HIGH")
	b:SetSize(size, size)
	-- Newer clients only act on the press or the release, depending on the "cast on key down"
	-- option, so the button listens to both and the game's own click handler picks the right one.
	b:RegisterForClicks("AnyUp", "AnyDown")
	b:SetAttribute("type1", "spell")
	b:SetAttribute("spell1", m.spell.name)
	-- (calling or summoning a pet targets nobody: with no pet out, "pet" would be an invalid target)
	b:SetAttribute("unit1", m.spell.kind == "summon" and "player" or e.token)
	b.token, b.name, b.m, b.spellID = e.token, m.spell.name, m, m.id

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.icon:SetTexture(m.icon)

	b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cooldown:SetAllPoints()
	if b.cooldown.SetDrawEdge then b.cooldown:SetDrawEdge(false) end
	-- the swipe must never take the click away from the button
	b.cooldown:EnableMouse(false)
	if b.cooldown.SetMouseClickEnabled then b.cooldown:SetMouseClickEnabled(false) end
	if b.cooldown.SetMouseMotionEnabled then b.cooldown:SetMouseMotionEnabled(false) end

	b.amount = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	b.amount:SetPoint("BOTTOMRIGHT", -1, 1)
	-- expected overheal (white, +) and shortfall (red, -); in combat these follow the health curves
	b.overFS = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	b.overFS:SetPoint("BOTTOMRIGHT", -1, 1)
	b.overFS:SetTextColor(1, 1, 1)
	b.overFS:SetAlpha(0)
	b.underFS = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	b.underFS:SetPoint("BOTTOMRIGHT", -1, 1)
	b.underFS:SetTextColor(1, 0.25, 0.25)
	b.underFS:SetAlpha(0)

	-- the game's own action-button art: frame, pressed and mouse-over looks
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	if HasAtlas("UI-HUD-ActionBar-IconFrame") then
		b.frameArt = b:CreateTexture(nil, "OVERLAY")
		b.frameArt:SetAtlas("UI-HUD-ActionBar-IconFrame")
		b.frameArt:SetAllPoints()
		b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
		if HasAtlas("UI-HUD-ActionBar-IconFrame-Down") then b:GetPushedTexture():SetAtlas("UI-HUD-ActionBar-IconFrame-Down") end
		if HasAtlas("UI-HUD-ActionBar-IconFrame-Mouseover") then b:GetHighlightTexture():SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover") end
	else
		b:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
		b.normalArt = b:GetNormalTexture()
		b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
		b:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
	end
	b:SetScript("OnSizeChanged", function(self, w)
		if self.normalArt then
			self.normalArt:ClearAllPoints()
			self.normalArt:SetPoint("CENTER", 0, -1)
			self.normalArt:SetSize(w * 1.8, w * 1.8)
		end
	end)
	if b.normalArt then b:GetScript("OnSizeChanged")(b, size) end

	-- the flashing gold band, as on the Spell Ranker
	-- (in its own frame so its alpha can follow the game's health-percent curves in combat)
	b.glowHolder = CreateFrame("Frame", nil, b)
	b.glowHolder:SetAllPoints()
	b.glowHolder:SetFrameLevel(b:GetFrameLevel() + 3)
	b.glowHolder:EnableMouse(false)
	b.glow = b.glowHolder:CreateTexture(nil, "OVERLAY")
	b.glow:SetBlendMode("ADD")
	if HasAtlas(HIGHLIGHT_ATLAS) then
		b.glow:SetAtlas(HIGHLIGHT_ATLAS)
		b.glow:SetVertexColor(1, 0.86, 0.45)
		b.glow:SetPoint("TOPLEFT", -size * 0.04, size * 0.04)
		b.glow:SetPoint("BOTTOMRIGHT", size * 0.04, -size * 0.04)
	else
		b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
		b.glow:SetVertexColor(1, 0.82, 0)
		b.glow:SetPoint("CENTER")
		b.glow:SetSize(size * 1.8, size * 1.8)
	end
	b.glow:Hide()
	b.pulse = b:CreateAnimationGroup()
	b.pulse:SetLooping("REPEAT")
	local up = b.pulse:CreateAnimation("Alpha")
	up:SetTarget(b.glow)
	up:SetFromAlpha(0.15)
	up:SetToAlpha(0.95)
	up:SetDuration(0.45)
	up:SetOrder(1)
	local down = b.pulse:CreateAnimation("Alpha")
	down:SetTarget(b.glow)
	down:SetFromAlpha(0.95)
	down:SetToAlpha(0.15)
	down:SetDuration(0.45)
	down:SetOrder(2)

	b:SetScript("OnEnter", ButtonTip)
	b:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
		if hover and hover.button == self then hover = nil end
	end)
	b:SetAlpha(DIM)
	b:Hide()
	return b
end

local function NewEntry(token)
	return { token = token, buttons = {}, order = {}, auraDirty = true, pet = token:find("pet", 1, true) ~= nil }
end

-- Out of combat only: make sure this member has a button for each spell you know.
local function EnsureButtons(e)
	if InCombatLockdown() then needLayout = true return end
	local changed = false
	local order = {}
	for _, m in ipairs(mine) do
		local name = m.spell.name
		local kind = m.spell.kind
		local petOnly = m.spell.petOnly
		-- pet-care spells go on your own pet only; ordinary pets don't get resurrections or buffs
		local wanted
		if petOnly then wanted = e.token == "pet"
		else wanted = not (e.pet and (kind == "res" or kind == "buff")) end
		if wanted then
			if not e.buttons[name] then
				e.buttons[name] = MakeButton(e, m)
				changed = true
			end
			order[#order + 1] = name
		end
	end
	if #order ~= #e.order then changed = true end
	e.order = order
	if changed then needLayout = true end
end

---------------------------------------------------------------------------
-- Placing the icons (out of combat)
---------------------------------------------------------------------------

local frameCandidates
local function Candidates()
	if frameCandidates then return frameCandidates end
	local list = {}
	for i = 1, 4 do list[#list + 1] = "PartyMemberFrame" .. i .. "PetFrame" end
	for i = 1, 5 do list[#list + 1] = "CompactPartyFramePet" .. i end
	for i = 1, 4 do list[#list + 1] = "PartyMemberFrame" .. i end
	for i = 1, 5 do list[#list + 1] = "CompactPartyFrameMember" .. i end
	for i = 1, 40 do list[#list + 1] = "CompactRaidFrame" .. i end
	for g = 1, 8 do for m = 1, 5 do list[#list + 1] = "CompactRaidGroup" .. g .. "Member" .. m end end
	frameCandidates = list
	return list
end

local function FrameFor(token)
	if token == "player" then return PlayerFrame end
	if token == "pet" and PetFrame and PetFrame:IsVisible() then return PetFrame end
	for _, name in ipairs(Candidates()) do
		local f = _G[name]
		if f and f:IsVisible() then
			local unit = f.unit or (f.GetAttribute and f:GetAttribute("unit"))
			if unit == token then return f end
		end
	end
end

local function SortedList()
	local list = {}
	for _, token in ipairs(roster) do
		local e = entries[token]
		-- a pet that isn't out doesn't get a row, nor does anyone with no icons (a hunter's group members)
		if e and not (e.pet and e.res and e.res.absent) and #e.order > 0 then list[#list + 1] = e end
	end
	table.sort(list, function(a, b)
		local sa, sb = a.res and a.res.score or 0, b.res and b.res.score or 0
		if sa ~= sb then return sa > sb end
		return a.token < b.token
	end)
	return list
end

---------------------------------------------------------------------------
-- Aggro markers: a glow round the member's frame / row, and a skull + enemy count badge
---------------------------------------------------------------------------

local AGGRO_COLORS = { [3] = { 1, 0.12, 0.1 }, [2] = { 1, 0.55, 0.1 }, [1] = { 1, 0.9, 0.2 } }

local function BadgeTip(self)
	local e = self.entry
	local t = e and e.threat
	if not t or t.count == 0 then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(("%s has aggro from %d %s"):format(UnitName(e.token) or e.token, t.count, t.count == 1 and "enemy" or "enemies"), 1, 0.82, 0)
	for _, mob in ipairs(t.list) do
		if mob.unknown then
			GameTooltip:AddLine("The game doesn't say which enemy", 0.7, 0.7, 0.7)
		else
			local c = AGGRO_COLORS[mob.status] or AGGRO_COLORS[3]
			GameTooltip:AddLine(("%s  (%s)"):format(mob.name, mob.status >= 3 and "tanking" or "has aggro, not secure"), c[1], c[2], c[3])
		end
	end
	GameTooltip:Show()
end

local function MakeMarkers(e)
	local glow = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	glow:SetFrameStrata("HIGH")
	glow:EnableMouse(false)
	glow:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
	glow.pulse = glow:CreateAnimationGroup()
	glow.pulse:SetLooping("BOUNCE")
	local fade = glow.pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.45)
	fade:SetDuration(0.7)
	glow:Hide()
	e.glow = glow

	local badge = CreateFrame("Frame", nil, UIParent)
	badge:SetFrameStrata("HIGH")
	badge:SetSize(32, 14)
	badge:EnableMouse(true)
	badge.back = badge:CreateTexture(nil, "BACKGROUND")
	badge.back:SetAllPoints()
	badge.back:SetColorTexture(0, 0, 0, 0.6)
	badge.skull = badge:CreateTexture(nil, "ARTWORK")
	badge.skull:SetSize(10, 10)
	badge.skull:SetPoint("LEFT", 3, 0)
	badge.skull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
	badge.count = badge:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	badge.count:SetPoint("LEFT", badge.skull, "RIGHT", 2, 0)
	badge.count:SetPoint("RIGHT", -3, 0)
	badge.count:SetJustifyH("RIGHT")
	badge.entry = e
	badge:SetScript("OnEnter", BadgeTip)
	badge:SetScript("OnLeave", function() GameTooltip:Hide() end)
	badge:Hide()
	e.badge = badge

	-- pets carry a small green paw print, so they're never mistaken for people
	if e.pet then
		local paw = CreateFrame("Frame", nil, UIParent)
		paw:SetFrameStrata("HIGH")
		paw:SetSize(14, 14)
		paw:EnableMouse(false)
		paw.tex = paw:CreateTexture(nil, "OVERLAY")
		paw.tex:SetAllPoints()
		if HasAtlas("Mobile-Pets") then
			paw.tex:SetAtlas("Mobile-Pets")
		else
			paw.tex:SetTexture("Interface\\Icons\\Ability_Tracking")   -- the paw print of Track Beasts
			paw.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		end
		paw.tex:SetVertexColor(0.55, 1, 0.45)
		paw:Hide()
		e.paw = paw
	end
end

-- Out of combat (it anchors to frames the game may not let us move around in combat).
-- kind "frame": target is the member's unit frame; kind "row": target is the panel row's bar.
local function PlaceMarkers(e, kind, target, y, rowH)
	if not e.glow then MakeMarkers(e) end
	e.placed = true
	local glow, badge = e.glow, e.badge
	glow:ClearAllPoints()
	badge:ClearAllPoints()
	if kind == "frame" then
		glow:SetPoint("TOPLEFT", target, "TOPLEFT", -2, 2)
		glow:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 2, -2)
		local first = e.buttons[e.order[1]]
		if first then badge:SetPoint("RIGHT", first, "LEFT", -2, 0) else badge:SetPoint("TOPRIGHT", target, "BOTTOMLEFT", 0, 0) end
		if e.paw then
			e.paw:ClearAllPoints()
			if first then e.paw:SetPoint("BOTTOMRIGHT", first, "TOPLEFT", 4, -4) else e.paw:SetPoint("TOPLEFT", target, "BOTTOMLEFT", 0, 0) end
		end
	else
		if e.paw then
			e.paw:ClearAllPoints()
			e.paw:SetPoint("BOTTOMLEFT", target, "TOPLEFT", 1, 0)
		end
		glow:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -(y - 2))
		glow:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -(y - 2))
		glow:SetHeight(rowH + 3)
		-- on the name line, so it never covers the health numbers
		badge:SetPoint("BOTTOMRIGHT", target, "TOPRIGHT", 0, 1)
	end
end

-- Any time, even in combat: just shows, hides and recolours.
local function UpdateMarkers(e)
	if not e.glow then return end
	if e.paw then
		local show = e.placed and not HideOutOfCombat() and not (e.res and e.res.absent)
		if show ~= e.paw:IsShown() then e.paw:SetShown(show) end
	end
	local t = e.threat
	local on = db.aggroMarkers and e.placed and t and t.count > 0 and not (e.res and (e.res.absent or e.res.dead))
		and not HideOutOfCombat()
	if not on then
		if e.glow:IsShown() then e.glow.pulse:Stop() e.glow:Hide() end
		if e.badge:IsShown() then e.badge:Hide() end
		return
	end
	local c = AGGRO_COLORS[math.min(3, math.max(1, t.level))]
	if db.aggroGlow then
		if e.glowLevel ~= t.level then e.glowLevel = t.level e.glow:SetBackdropBorderColor(c[1], c[2], c[3], 1) end
		if not e.glow:IsShown() then e.glow:Show() end
		if t.level >= 3 then
			if not e.glow.pulse:IsPlaying() then e.glow.pulse:Play() end
		else
			e.glow.pulse:Stop()
			e.glow:SetAlpha(1)
		end
	elseif e.glow:IsShown() then
		e.glow.pulse:Stop()
		e.glow:Hide()
	end
	if db.aggroBadge then
		e.badge.skull:SetVertexColor(c[1], c[2], c[3])
		e.badge.count:SetText(t.count)
		e.badge.count:SetTextColor(c[1], c[2], c[3])
		if not e.badge:IsShown() then e.badge:Show() end
	elseif e.badge:IsShown() then
		e.badge:Hide()
	end
end

local function BuildPanel()
	if panel then return end
	panel = CreateFrame("Frame", "AzerothAlmanacHealPanel", UIParent, "BackdropTemplate")
	panel:SetFrameStrata("MEDIUM")
	panel:SetClampedToScreen(true)
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetSize(200, 40)
	-- the game's own tooltip / dialog look
	panel:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	panel:SetBackdropColor(1, 1, 1, 0.92)
	panel:SetBackdropBorderColor(0.75, 0.75, 0.75, 1)
	panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	panel.title:SetPoint("TOPLEFT", 10, -7)
	panel.title:SetText("Heal assist")
	panel.hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	panel.hint:SetPoint("TOPRIGHT", -10, -8)
	panel.hint:SetText("drag to move")
	panel.rule = panel:CreateTexture(nil, "ARTWORK")
	panel.rule:SetColorTexture(1, 0.82, 0, 0.25)
	panel.rule:SetHeight(1)
	panel.rule:SetPoint("TOPLEFT", 8, -HEADER_H + 2)
	panel.rule:SetPoint("TOPRIGHT", -8, -HEADER_H + 2)
	panel.labels, panel.bars, panel.rowBg = {}, {}, {}
	panel:SetScript("OnDragStart", function(self)
		if not db.locked and not InCombatLockdown() then self:StartMoving() end
	end)
	panel:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		db.pos = { point, relPoint, x, y }
	end)
	panel:Hide()
end

-- Each button is shown or hidden on its own here (out of combat). "Only in combat" is done one
-- level up, by the secure holder the buttons live in (see Holder).
local function ShowButton(b)
	b:Show()
end

local function ReleaseButton(b)
	b:Hide()
end

-- heals / cures / the rest sit in separate groups with a little extra space between them
local function GroupOf(b)
	local kind = b.m.spell.kind
	if kind == "heal" or kind == "hot" or kind == "shield" or kind == "funnel" then return 1 end
	if kind == "cleanse" then return 2 end
	return 3
end

local function Strip(e, anchorFrame, side, x, y)
	local size, per = db.iconSize, math.max(1, db.perRow)
	local col, line, extra, lastGroup = 0, 0, 0, nil
	for _, name in ipairs(e.order) do
		local b = e.buttons[name]
		local group = GroupOf(b)
		if lastGroup and group ~= lastGroup and col > 0 then extra = extra + GROUP_GAP end
		if col >= per then col, line, extra = 0, line + 1, 0 end
		lastGroup = group
		local px, py = x + extra + col * (size + GAP), y - line * (size + GAP)
		b:SetSize(size, size)
		b:ClearAllPoints()
		if side == "right" then
			b:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", px, py)
		elseif side == "below" then
			b:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", px, py)
		else
			b:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", px, py)
		end
		ShowButton(b)
		col = col + 1
	end
end

local function LayoutPanel(list)
	BuildPanel()
	local size, per = db.iconSize, math.max(1, db.perRow)
	panel:ClearAllPoints()
	local p = db.pos
	if p and p[1] then panel:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
	else panel:SetPoint("CENTER", UIParent, "CENTER", 0, -160) end
	panel.rowUnits = {}
	local y = HEADER_H + 2
	local rows = math.min(#list, db.maxRows)
	for k = 1, rows do
		local e = list[k]
		panel.rowUnits[k] = e
		local lines = math.max(1, math.ceil(#e.order / per))
		local rowH = math.max(lines * (size + GAP), NAME_H + BAR_H + 3)

		-- a tint behind the whole row that follows how urgent the member is
		local bg = panel.rowBg[k]
		if not bg then
			bg = panel:CreateTexture(nil, "BACKGROUND")
			panel.rowBg[k] = bg
		end
		bg:ClearAllPoints()
		bg:SetPoint("TOPLEFT", panel, "TOPLEFT", 5, -(y - 1))
		bg:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -5, -(y - 1))
		bg:SetHeight(rowH + 1)
		bg:SetColorTexture(0, 0, 0, 0.25)
		bg:Show()

		-- the member's health bar and name, like a small unit frame
		local bar = panel.bars[k]
		if not bar then
			bar = CreateFrame("StatusBar", nil, panel)
			bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
			bar:SetStatusBarColor(unpack(HEALTH_COLOR))
			bar:SetMinMaxValues(0, 1)
			bar:SetValue(1)
			-- the game's look: a thin dark outline round a dark red-brown "empty" part
			bar.edge = bar:CreateTexture(nil, "BACKGROUND", nil, -2)
			bar.edge:SetPoint("TOPLEFT", -1, 1)
			bar.edge:SetPoint("BOTTOMRIGHT", 1, -1)
			bar.edge:SetColorTexture(0, 0, 0, 0.95)
			bar.back = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
			bar.back:SetAllPoints()
			bar.back:SetColorTexture(0.2, 0.07, 0.06, 1)
			-- incoming heals: a teal block that starts where the green ends. It's anchored to the
			-- bar's own fill, so it lands in the right place even when the health value is hidden
			-- in combat; a clipping frame cuts it off at the end of the bar.
			bar.predClip = CreateFrame("Frame", nil, bar)
			bar.predClip:SetAllPoints()
			bar.predClip:SetClipsChildren(true)
			bar.predHolder = CreateFrame("Frame", nil, bar.predClip)
			bar.predHolder:SetAllPoints()
			bar.pred = bar.predHolder:CreateTexture(nil, "ARTWORK")
			bar.pred:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
			bar.pred:SetVertexColor(PREDICT_COLOR[1], PREDICT_COLOR[2], PREDICT_COLOR[3], 0.9)
			bar.pred:SetPoint("TOPLEFT", bar:GetStatusBarTexture(), "TOPRIGHT")
			bar.pred:SetPoint("BOTTOMLEFT", bar:GetStatusBarTexture(), "BOTTOMRIGHT")
			bar.pred:SetWidth(0.01)
			-- the hover preview: the same, see-through, right after it
			bar.prev = bar.predHolder:CreateTexture(nil, "ARTWORK")
			bar.prev:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
			bar.prev:SetVertexColor(PREDICT_COLOR[1], PREDICT_COLOR[2], PREDICT_COLOR[3], 0.5)
			bar.prev:SetPoint("TOPLEFT", bar.pred, "TOPRIGHT")
			bar.prev:SetPoint("BOTTOMLEFT", bar.pred, "BOTTOMRIGHT")
			bar.prev:SetWidth(0.01)
			bar.predHolder:Hide()
			-- texts sit on a frame above the bars, like the game's unit frames
			bar.textFrame = CreateFrame("Frame", nil, bar)
			bar.textFrame:SetAllPoints()
			bar.textFrame:SetFrameLevel(bar:GetFrameLevel() + 5)
			bar.pctText = bar.textFrame:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
			bar.pctText:SetPoint("LEFT", 3, 0)
			bar.valText = bar.textFrame:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
			bar.valText:SetPoint("RIGHT", -3, 0)
			-- the name above it, in the class colour
			bar.label = bar.textFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			bar.label:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 1, 1)
			bar.label:SetWidth(LABEL_W - 14)
			bar.label:SetJustifyH("LEFT")
			bar.label:SetWordWrap(false)
			panel.bars[k] = bar
			panel.labels[k] = bar.label
		end
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", panel, "TOPLEFT", 9, -(y + NAME_H + math.floor((rowH - NAME_H - BAR_H) / 2)))
		bar:SetSize(LABEL_W - 12, BAR_H)
		bar:Show()

		Strip(e, panel, "inside", LABEL_W, -y)
		PlaceMarkers(e, "row", bar, y, rowH)
		y = y + rowH + 2
	end
	for k = rows + 1, #panel.bars do
		panel.bars[k]:Hide()
		panel.rowBg[k]:Hide()
	end
	panel:SetSize(LABEL_W + per * (size + GAP) + GROUP_GAP * 2 + 10, y + 6)
	panel.hint:SetShown(not db.locked)
	panel:SetShown(rows > 0 or not db.locked)
	-- see-through out of combat (only-in-combat mode) also means it must not catch the mouse
	panel:EnableMouse(not db.locked and not HideOutOfCombat())
end

local function Layout()
	if InCombatLockdown() then needLayout = true return end
	needLayout = false
	for _, e in pairs(entries) do
		for _, b in pairs(e.buttons) do ReleaseButton(b) end
		e.placed = false
	end
	if not Enabled() then
		if panel then panel:Hide() end
		return
	end
	local list = SortedList()
	local panelList = {}
	if db.mode == "frames" then
		local keys = {}
		for _, e in ipairs(list) do
			local f = FrameFor(e.token)
			if f then
				Strip(e, f, db.side, 4, db.side == "below" and -2 or 0)
				PlaceMarkers(e, "frame", f)
				keys[#keys + 1] = e.token .. "=" .. (f:GetName() or "?")
			elseif not e.pet then
				panelList[#panelList + 1] = e
			end
		end
		layoutKey = table.concat(keys, ",")
	else
		panelList = list
	end
	if #panelList > 0 or db.mode == "panel" then
		LayoutPanel(panelList)
		local tokens = {}
		for k = 1, math.min(#panelList, db.maxRows) do tokens[#tokens + 1] = panelList[k].token end
		if db.mode == "panel" then layoutKey = table.concat(tokens, ",") end
	elseif panel then
		panel:Hide()
	end
end

---------------------------------------------------------------------------
-- Showing the state
---------------------------------------------------------------------------

-- In combat this client hides a unit's current health, but UnitHealthPercent can still be run through
-- a "curve" and its answer handed straight to a frame's alpha without the addon ever reading it.
-- Curves turn the health fraction into 1 / 0 (or bright / dim) at the thresholds the rules use.
local function CurvesAvailable()
	if HA.curvesOK == false then return false end
	return type(UnitHealthPercent) == "function" and C_CurveUtil ~= nil and C_CurveUtil.CreateCurve ~= nil
		and Enum.LuaCurveType ~= nil and Enum.LuaCurveType.Step ~= nil
end

-- A step curve of fn(p) over health fraction p (0..1), with steps at xs.
local function BuildCurve(fn, xs)
	table.sort(xs)
	local steps = {}
	for _, x in ipairs(xs) do
		x = math.min(1, math.max(0, x))
		if #steps == 0 or x - steps[#steps] > 0.0005 then steps[#steps + 1] = x end
	end
	if steps[1] ~= 0 then table.insert(steps, 1, 0) end
	local ok, curve = pcall(C_CurveUtil.CreateCurve)
	if not ok or not curve then return nil end
	if not pcall(curve.SetType, curve, Enum.LuaCurveType.Step) then return nil end
	local lastY
	for i, x in ipairs(steps) do
		local y = fn((x + (steps[i + 1] or 1)) / 2)
		if y ~= lastY then
			if not pcall(curve.AddPoint, curve, x, y) then return nil end
			lastY = y
		end
	end
	return curve
end

-- A straight-line curve through { {x, y}, ... }.
local function BuildLinear(points)
	if not (Enum.LuaCurveType and Enum.LuaCurveType.Linear ~= nil) then return nil end
	local ok, curve = pcall(C_CurveUtil.CreateCurve)
	if not ok or not curve then return nil end
	if not pcall(curve.SetType, curve, Enum.LuaCurveType.Linear) then return nil end
	for _, p in ipairs(points) do
		if not pcall(curve.AddPoint, curve, p[1], p[2]) then return nil end
	end
	return curve
end

-- The curves for one member's current situation, rebuilt only when it changes.
local function CurvesFor(e, h)
	local parts = { h.max, tostring(h.aggro), h.crit, db.cover, DIM }
	for _, c in ipairs(h.heals) do parts[#parts + 1] = c.m.spell.name .. c.amount end
	local allBuffed = #h.hots > 0
	for _, c in ipairs(h.hots) do
		local on = h.buffs[c.m.spell.name] and true or false
		parts[#parts + 1] = c.m.spell.name .. c.amount .. tostring(on)
		if not on then allBuffed = false end
	end
	local key = table.concat(parts, ":")
	if e.curveKey == key then return e.curves end
	e.curveKey, e.curves = key, nil

	local crit, cover = h.crit, db.cover / 100
	local sorted = {}
	for _, c in ipairs(h.heals) do sorted[#sorted + 1] = c end
	table.sort(sorted, function(a, b) return a.amount < b.amount end)
	local fastest
	if #sorted > 0 then
		local copy = {}
		for _, c in ipairs(sorted) do copy[#copy + 1] = c end
		fastest = PickFastest(copy)
	end
	-- the smallest heal covers p when amount >= cover * (1 - p) * max
	local edges = {}
	for i, c in ipairs(sorted) do edges[i] = 1 - c.amount / (cover * h.max) end
	local function efficient(p)
		for i = 1, #sorted do
			if p >= edges[i] then return sorted[i] end
		end
		return sorted[#sorted]
	end

	local xs = { 0, crit, crit + 0.001, 0.5, 0.5001, 0.95, 0.97, 1 }
	for _, x in ipairs(edges) do xs[#xs + 1] = x end

	local curves = { flash = {} }
	curves.alpha = BuildCurve(function(p) return p < 0.97 and 1 or DIM end, xs)
	curves.alphaSoft = BuildCurve(function(p) return p < 0.97 and 1 or 0 end, xs)   -- "only while hurt"
	if not curves.alpha or not curves.alphaSoft then return nil end
	for _, c in ipairs(sorted) do
		local name = c.m.spell.name
		curves.flash[name] = BuildCurve(function(p)
			if h.aggro then
				if p <= crit then return (fastest and fastest.m.spell.name == name) and 1 or 0 end
				if p < 0.97 then return efficient(p).m.spell.name == name and 1 or 0 end
				return 0
			end
			if #h.hots > 0 then
				return (allBuffed and p <= 0.5 and efficient(p).m.spell.name == name) and 1 or 0
			end
			return (p < 0.97 and efficient(p).m.spell.name == name) and 1 or 0
		end, xs)
	end
	for _, c in ipairs(h.hots) do
		local name = c.m.spell.name
		local on = h.buffs[name]
		local petOnly = c.m.spell.petOnly   -- your pet's Mend Pet flashes under attack too
		curves.flash[name] = BuildCurve(function(p)
			return ((petOnly or not h.aggro) and not on and p < 0.95) and 1 or 0
		end, xs)
	end
	for _, curve in pairs(curves.flash) do
		if not curve then return nil end
	end

	-- expected overheal / shortfall of each heal at every health level: amount - (1 - p) * max
	curves.over, curves.under, curves.overA, curves.underA = {}, {}, {}, {}
	local function addNet(c)
		local name, amount = c.m.spell.name, c.amount
		local zero = 1 - amount / h.max   -- the health fraction at which the heal matches what's missing
		local overPts, underPts = { { 0, math.max(0, amount - h.max) } }, { { 0, math.max(0, h.max - amount) } }
		if zero > 0.001 and zero < 0.999 then
			overPts[#overPts + 1] = { zero, 0 }
			underPts[#underPts + 1] = { zero, 0 }
		end
		overPts[#overPts + 1] = { 1, amount }
		underPts[#underPts + 1] = { 1, 0 }
		curves.over[name], curves.under[name] = BuildLinear(overPts), BuildLinear(underPts)
		local nx = { 0, 0.97, 1 }
		if zero > 0 and zero < 1 then nx[#nx + 1] = zero end
		curves.overA[name] = BuildCurve(function(p) return (p < 0.97 and amount - (1 - p) * h.max > 0.5) and 1 or 0 end, nx)
		curves.underA[name] = BuildCurve(function(p) return (p < 0.97 and (1 - p) * h.max - amount > 0.5) and 1 or 0 end, nx)
	end
	curves.hasNet = true
	for _, c in ipairs(sorted) do addNet(c) end
	for _, c in ipairs(h.hots) do addNet(c) end
	for _, name in ipairs({ "over", "under", "overA", "underA" }) do
		for _, curve in pairs(curves[name]) do
			if not curve then curves.hasNet = false end
		end
	end
	e.curves = curves
	return curves
end

-- Heal and heal-over-time buttons driven by the curves. Returns true when it handled this button.
local function ApplyCurves(e, res, b, name)
	local h = res.hidden
	if not h or not CurvesAvailable() then return false end
	local kind = b.m.spell.kind
	if kind ~= "heal" and kind ~= "hot" then return false end
	local curves = CurvesFor(e, h)
	if not curves then HA.curvesOK = false return false end
	local flashCurve = curves.flash[name]
	local token = e.token
	local alphaCurve = SoftHidden() and curves.alphaSoft or curves.alpha
	local ok = pcall(function()
		b:SetAlpha(UnitHealthPercent(token, false, alphaCurve))
		if flashCurve then b.glowHolder:SetAlpha(UnitHealthPercent(token, false, flashCurve)) end
	end)
	if not ok then HA.curvesOK = false return false end
	b.shownAlpha = nil
	b.curveDriven = true
	SetFlash(b, flashCurve ~= nil)
	-- the overheal / shortfall numbers
	local textDriven = false
	if curves.hasNet and HA.netTextOK ~= false and curves.over[name] then
		textDriven = pcall(function()
			b.overFS:SetFormattedText("+%.0f", UnitHealthPercent(token, false, curves.over[name]))
			b.overFS:SetAlpha(UnitHealthPercent(token, false, curves.overA[name]))
			b.underFS:SetFormattedText("-%.0f", UnitHealthPercent(token, false, curves.under[name]))
			b.underFS:SetAlpha(UnitHealthPercent(token, false, curves.underA[name]))
		end)
		if not textDriven then HA.netTextOK = false end
	end
	return true, textDriven
end

local function ApplyVisuals(e, now)
	local res = e.res
	if not res then return end
	for _, name in ipairs(e.order) do
		local b = e.buttons[name]
		if b then
			local rel = res.rel[name]
			local driven, textDriven = false, false
			-- "only while hurt" when the game hides health: buttons that can't follow a curve, and
			-- members who aren't hurt, are simply invisible
			local hideThis = false
			if SoftHidden() then
				local kind = b.m.spell.kind
				local followsCurve = res.hidden and (kind == "heal" or kind == "hot")
				if not followsCurve and not (res.hurt and not res.hidden) then hideThis = true end
			end
			if hideThis then
				if b.shownAlpha ~= 0 or b.curveDriven or b.textDriven then
					b.shownAlpha = 0
					b:SetAlpha(0)
					SetFlash(b, false)
					if b.curveDriven then b.curveDriven = false b.glowHolder:SetAlpha(1) end
					if b.textDriven then b.textDriven = false b.overFS:SetAlpha(0) b.underFS:SetAlpha(0) end
				end
				b.tip = nil
			else
			if not res.absent then driven, textDriven = ApplyCurves(e, res, b, name) end
			if textDriven then
				if b.shownText ~= "" then b.shownText = "" b.amount:SetText("") end
				b.textDriven = true
			elseif b.textDriven then
				b.textDriven = false
				b.overFS:SetAlpha(0)
				b.underFS:SetAlpha(0)
			end
			if not driven then
				if b.curveDriven then
					b.curveDriven = false
					b.glowHolder:SetAlpha(1)
					b.shownAlpha = nil
				end
				local alpha = DIM
				local desat = false
				if res.absent then
					alpha = ABSENT
				elseif rel then
					alpha = res.soft[name] and 0.7 or 1
					if not InRange(name, e.token) or b.m.cost > (R(UnitPower("player", 0)) or math.huge) then
						alpha, desat = OFF, true
					end
				end
				if b.shownAlpha ~= alpha then b.shownAlpha = alpha b:SetAlpha(alpha) end
				if b.shownDesat ~= desat then b.shownDesat = desat b.icon:SetDesaturated(desat) end
				SetFlash(b, (res.flash[name] and not res.absent) and true or false)
			end
			if not textDriven then
				local amount = rel and res.amounts[name]
				local net = rel and res.net[name]
				local text = ""
				if net then
					-- expected overheal (white +) or shortfall (red -)
					if net >= 0 then text = "+" .. Short(net) else text = "|cffff4040-" .. Short(-net) .. "|r" end
				elseif amount and amount > 0 then
					text = Short(amount)
				end
				if b.shownText ~= text then b.shownText = text b.amount:SetText(text) end
			end
			b.tip = res.text[name]
			local start, duration = Cooldown(name)
			if duration > 0 and start > 0 then b.cooldown:SetCooldown(start, duration)
			elseif b.hasCd then b.cooldown:SetCooldown(0, 0) end
			b.hasCd = duration > 0 and start > 0
			end
		end
	end
end

-- Healing on its way to this member: your own cast (you know what it heals for) and, where the
-- game gives it, everyone else's.
local function Incoming(e)
	local inc = 0
	if selfCast and selfCast.target and selfCast.target == UnitName(e.token) then inc = selfCast.amount or 0 end
	if type(UnitGetIncomingHeals) == "function" then
		local v = R(UnitGetIncomingHeals(e.token))
		if type(v) == "number" and v > inc then inc = v end
	end
	return inc
end

local function UpdateLabels()
	if not panel or not panel:IsShown() or not panel.rowUnits then return end
	local scale100 = CurveConstants and CurveConstants.ScaleTo100
	for k, e in ipairs(panel.rowUnits) do
		local label = panel.labels[k]
		local bar = panel.bars[k]
		if label and bar then
			local token = e.token
			local name = UnitName(token) or token
			local _, class = UnitClass(token)
			local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
			local res = e.res
			local pct = res and res.pct
			if e.pet then
				-- "Pet name (Owner)"; a pet that isn't out says so
				local ownerToken = token == "pet" and "player" or (token:gsub("pet", ""))
				local owner = UnitName(ownerToken)
				if res and res.noPet then name = "No pet"
				elseif owner then name = ("%s (%s)"):format(name, owner) end
			end

			-- the health bar: a status bar can be fed the (hidden in combat) health directly
			local filled = pcall(function()
				bar:SetMinMaxValues(0, UnitHealthMax(token))
				bar:SetValue(UnitHealth(token))
			end)
			if not filled then
				bar:SetMinMaxValues(0, 1)
				bar:SetValue(pct or ((res and (res.dead or res.noPet)) and 0 or 1))
			end
			local dead = res and (res.dead or res.absent)
			if bar.dead ~= dead then
				bar.dead = dead
				if dead then bar:SetStatusBarColor(0.45, 0.45, 0.45) else bar:SetStatusBarColor(unpack(HEALTH_COLOR)) end
			end
			label:SetText(name)
			-- room for the paw print in front of a pet's name
			local shift = e.pet and 15 or 1
			if label.shift ~= shift then
				label.shift = shift
				label:ClearAllPoints()
				label:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", shift, 1)
			end
			if color then label:SetTextColor(color.r, color.g, color.b) else label:SetTextColor(1, 1, 1) end

			-- incoming heals: the teal block, and "now > after" in the percentage
			local maxN = R(UnitHealthMax(token))
			if type(maxN) ~= "number" or maxN <= 0 then maxN = res and res.hidden and res.hidden.max or nil end
			-- solid: heals on the way (your cast stays until it lands); see-through: the heal
			-- icon the mouse is over, as a preview. The percentage shows both.
			local sInc = (db.predict and not dead) and Incoming(e) or 0
			local pInc = 0
			if db.predict and not dead and hover and hover.token == token then
				if hover.button and not hover.button:IsMouseOver() then
					hover = nil
				elseif not (selfCast and selfCast.target and selfCast.target == UnitName(token)) then
					pInc = hover.amount or 0
				end
			end
			local barW = bar:GetWidth()
			local sFrac = (maxN and maxN > 0 and sInc > 0) and math.min(1, sInc / maxN) or 0
			local pFrac = (maxN and maxN > 0 and pInc > 0) and math.min(1, pInc / maxN) or 0
			local inc = sInc + pInc
			local frac = math.min(1, sFrac + pFrac)
			if sFrac > 0.003 or pFrac > 0.003 then
				bar.pred:SetWidth(math.max(0.01, sFrac * barW))
				bar.prev:SetWidth(math.max(0.01, pFrac * barW))
				if not bar.predHolder:IsShown() then bar.predHolder:Show() end
			elseif bar.predHolder:IsShown() then
				bar.predHolder:Hide()
			end

			-- percentage on the left, health on the right, as on the game's unit frames
			if dead then
				bar.pctText:SetText(res and res.dead and "Dead" or "")
				bar.valText:SetText("")
			elseif pct and type(maxN) == "number" and maxN > 0 then
				local cur = pct * maxN
				if frac > 0 then
					bar.pctText:SetFormattedText("%d%% > %d%%", math.floor(pct * 100 + 0.5), math.floor(math.min(1, (cur + inc) / maxN) * 100 + 0.5))
				else
					bar.pctText:SetFormattedText("%d%%", math.floor(pct * 100 + 0.5))
				end
				bar.valText:SetText(Short(cur))
			else
				local ok = false
				if scale100 and type(UnitHealthPercent) == "function" then
					if frac > 0 and C_CurveUtil and C_CurveUtil.CreateCurve then
						-- health after the heal, as a curve of the current health fraction
						local key = math.floor(frac * 400)
						if bar.predKey ~= key then
							bar.predKey = key
							bar.predCurve = BuildLinear({ { 0, frac * 100 }, { math.max(0.001, 1 - frac), 100 }, { 1, 100 } })
						end
						if bar.predCurve then
							ok = pcall(bar.pctText.SetFormattedText, bar.pctText, "%.0f%% > %.0f%%",
								UnitHealthPercent(token, false, scale100), UnitHealthPercent(token, false, bar.predCurve))
						end
					end
					if not ok then
						ok = pcall(bar.pctText.SetFormattedText, bar.pctText, "%.0f%%", UnitHealthPercent(token, false, scale100))
					end
				end
				if not ok then bar.pctText:SetText("") end
				if not pcall(bar.valText.SetFormattedText, bar.valText, "%d", UnitHealth(token)) then bar.valText:SetText("") end
			end

			local urgent = res and res.score and res.score > 0 and true or false
			local bg = panel.rowBg[k]

			-- "only while hurt": this member's row fades in only while they're hurt
			local rowAlpha = 1
			if SoftHidden() then
				if res and res.hidden then
					local cv = e.curves and e.curves.alphaSoft
					rowAlpha = nil
					if cv then
						rowAlpha = not pcall(function()
							local v = UnitHealthPercent(token, false, cv)
							bar:SetAlpha(v)
							if bg then bg:SetAlpha(v) end
						end) and 0 or nil
					else
						rowAlpha = 0
					end
				elseif not (res and res.hurt) then
					rowAlpha = 0
				end
			end
			if rowAlpha then
				bar:SetAlpha(rowAlpha)
				if bg then bg:SetAlpha(rowAlpha) end
			end
			if bg and bg.urgent ~= urgent then
				bg.urgent = urgent
				if urgent then bg:SetColorTexture(0.4, 0.28, 0.04, 0.4) else bg:SetColorTexture(0, 0, 0, 0.25) end
			end
		end
	end
end

local function Alert(e, now)
	local res = e.res
	if not res or e.pet or not res.pct or res.dead or not res.aggro then
		alerted[e.token] = nil
		return
	end
	if res.pct <= db.danger / 100 then
		if not alerted[e.token] or now - alerted[e.token] > 5 then
			alerted[e.token] = now
			if db.alertSound then PlaySound(SOUND_ALERT) end
			if db.alertFlash and flashFrame then
				flashFrame:SetAlpha(0.8)
				flashFrame:Show()
				UIFrameFadeOut(flashFrame, 0.6, 0.8, 0)
			end
		end
	elseif res.pct > db.danger / 100 + 0.1 then
		alerted[e.token] = nil
	end
end

local function Tick()
	local now = GetTime()
	local enabled = Enabled()
	local inCombat = InCombatLockdown()
	if not enabled then
		if shownState ~= false and not inCombat then
			shownState = false
			Layout()
			for _, e in pairs(entries) do UpdateMarkers(e) end
		end
		return
	end
	if shownState ~= true then shownState = true needLayout = true end

	if now - lastThreat >= 0.4 then ScanThreat(now) end
	local hurt, hiddenAny = false, false
	for _, token in ipairs(roster) do
		local e = entries[token]
		if e then
			if not inCombat then EnsureButtons(e) end
			e.res = Evaluate(e, now)
			if e.res.hurt then hurt = true end
			if e.res.hidden then hiddenAny = true end
		end
	end
	anyHidden = hiddenAny
	-- "only in combat" also shows while anyone is hurt; when they're healed it lingers like after combat
	if hurt ~= hurtNow then
		hurtNow = hurt
		if not hurt and db.linger then lingerUntil = math.max(lingerUntil, now + math.max(0, db.lingerSeconds or 0)) end
	end

	if not inCombat then
		if db.mode == "panel" then
			local list = SortedList()
			local tokens = {}
			for k = 1, math.min(#list, db.maxRows) do tokens[#tokens + 1] = list[k].token end
			if table.concat(tokens, ",") ~= layoutKey then needLayout = true end
		elseif now - lastFrameCheck > 1.5 then
			lastFrameCheck = now
			local keys = {}
			for _, token in ipairs(roster) do
				local f = FrameFor(token)
				keys[#keys + 1] = token .. "=" .. (f and f:GetName() or "?")
			end
			-- units with a frame are keyed by it; the rest fall into the panel
			if table.concat(keys, ",") ~= HA.frameKey then
				HA.frameKey = table.concat(keys, ",")
				needLayout = true
			end
		end
		if needLayout then Layout() end
	end

	for _, token in ipairs(roster) do
		local e = entries[token]
		if e then
			ApplyVisuals(e, now)
			UpdateMarkers(e)
			Alert(e, now)
		end
	end
	UpdateLabels()

	-- "Only in combat": the holder (all the icons) is hidden out of combat, once any "keep showing"
	-- time is up, and shown again by its secure snippet when combat starts. The panel goes
	-- see-through instead (it can't be shown once combat has started).
	local hide = HideOutOfCombat()
	if holder and not inCombat then
		if hide then
			if not holder.driven then
				holder.driven = true
				RegisterStateDriver(holder, "visibility", "[combat] show; hide")
			end
		else
			if holder.driven then
				holder.driven = false
				UnregisterStateDriver(holder, "visibility")
			end
			if not holder:IsShown() then holder:Show() end
		end
	end
	if panel then
		-- the frame, title and hint are only there while the panel shows as a whole
		local chrome = not SoftHidden()
		if panel.chromeShown ~= chrome then
			panel.chromeShown = chrome
			local a = chrome and 1 or 0
			panel:SetBackdropColor(1, 1, 1, 0.92 * a)
			panel:SetBackdropBorderColor(0.75, 0.75, 0.75, a)
			panel.title:SetAlpha(a)
			panel.rule:SetAlpha(a)
			panel.hint:SetAlpha(a)
		end
		-- the drag hint has no use mid-fight
		local hint = (not db.locked) and not inCombat
		if panel.hintShown ~= hint then
			panel.hintShown = hint
			panel.hint:SetShown(hint)
		end
		local want = hide and 0 or 1
		if panel.wantAlpha ~= want then
			panel.wantAlpha = want
			panel:SetAlpha(want)
			if not inCombat then panel:EnableMouse(not db.locked and not hide) end
		end
	end
end

---------------------------------------------------------------------------
-- Roster, events
---------------------------------------------------------------------------

local function RefreshRoster()
	roster = Units()
	wipe(maxCache)
	local set = {}
	for _, token in ipairs(roster) do
		set[token] = true
		entries[token] = entries[token] or NewEntry(token)
		entries[token].auraDirty = true
	end
	for token, e in pairs(entries) do
		if not set[token] then e.res = nil end
	end
	needLayout = true
end

function HA:Apply()
	if not db then return end
	ResolveSpells()
	RefreshRoster()
	shownState = nil
	HA.frameKey = nil
	if not InCombatLockdown() then
		for _, e in pairs(entries) do EnsureButtons(e) end
		Layout()
	end
end

function HA:ResetPosition()
	db.pos = nil
	needLayout = true
	if not InCombatLockdown() then Layout() end
end

function HA:Test()
	testUntil = GetTime() + 20
	ns.Print("Healer assist test for 20 seconds: you are shown at 45% health, under attack and poisoned.")
	HA:Apply()
	C_Timer.After(20.5, function() HA:Apply() end)
end

local function Debug()
	local function yn(v) return v == nil and "|cffff4444hidden/nil|r" or "|cff44ff44ok|r" end
	ns.Print(("In combat: %s. Spells found: %d. Health-percent curves: %s."):format(tostring(InCombatLockdown()), #mine,
		type(UnitHealthPercent) == "function" and C_CurveUtil and "available" .. (HA.curvesOK == false and " but failed" or "") or "not on this client"))
	for _, m in ipairs(mine) do
		ns.Print(("  %s (%s): heals %d, cast %.1fs, mana %d"):format(m.spell.name, m.spell.kind, SpellAmount(m), m.castTime, m.cost))
	end
	for _, token in ipairs(roster) do
		ns.Print(("%s %s: health %s, max %s, threat %s, dead %s"):format(token, UnitName(token) or "?",
			yn(R(UnitHealth(token))), yn(R(UnitHealthMax(token))), yn(R(UnitThreatSituation(token))), yn(R(UnitIsDeadOrGhost(token)))))
	end
	ScanThreat(GetTime())
	ns.Print(("Enemies in combat that can be asked about: %d."):format(#mobs))
	for _, token in ipairs(roster) do
		local t = entries[token] and entries[token].threat
		if t and t.count > 0 then
			local names = {}
			for _, m in ipairs(t.list) do names[#names + 1] = m.name end
			ns.Print(("  %s has aggro from %d: %s"):format(UnitName(token) or token, t.count, table.concat(names, ", ")))
		end
	end
	ns.Print("'hidden/nil' in combat means the game is hiding that value from addons, and that part can't work in combat.")
end

function HA:Command(arg)
	arg = (arg or ""):lower()
	if arg == "test" then
		HA:Test()
	elseif arg == "debug" then
		Debug()
	elseif arg == "on" or arg == "off" then
		db.enabled = arg == "on"
		HA:Apply()
		ns.Print("Healer assist " .. arg .. ".")
	elseif arg == "panel" or arg == "frames" then
		db.mode = arg
		HA:Apply()
		ns.Print("Healer assist: " .. (arg == "panel" and "queue panel." or "on the group frames."))
	elseif arg == "combat" then
		db.combatOnly = not db.combatOnly
		HA:Apply()
		ns.Print("Healer assist only in combat: " .. (db.combatOnly and "on." or "off."))
	elseif arg == "reset" then
		HA:ResetPosition()
	else
		if ns.Settings and ns.Settings.Open then ns.Settings:Open("healer") end
		ns.Print("/aa heal test | debug | on | off | panel | frames | reset")
	end
end

function HA:OnInitialize(saved)
	db = saved.healAssist
end

function HA:OnLogin()
	flashFrame = CreateFrame("Frame", nil, UIParent)
	flashFrame:SetAllPoints()
	flashFrame:SetFrameStrata("FULLSCREEN_DIALOG")
	local tex = flashFrame:CreateTexture(nil, "BACKGROUND")
	tex:SetAllPoints()
	tex:SetTexture("Interface\\FullScreenTextures\\LowHealth")
	tex:SetBlendMode("ADD")
	flashFrame:EnableMouse(false)
	flashFrame:Hide()

	local ev = CreateFrame("Frame")
	for _, e in ipairs({
		"PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "SPELLS_CHANGED", "PLAYER_LEVEL_UP",
		"PLAYER_REGEN_ENABLED", "PLAYER_EQUIPMENT_CHANGED", "UNIT_AURA",
		"UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
		"UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_SUCCEEDED",
	}) do
		pcall(ev.RegisterEvent, ev, e)
	end
	ev:SetScript("OnEvent", function(_, event, unit, target, _, spellID)
		if event == "UNIT_AURA" then
			local entry = entries[unit]
			if entry then entry.auraDirty = true end
		elseif event == "UNIT_SPELLCAST_SENT" then
			if unit == "player" then
				local name = spellID and SpellName(spellID)
				selfCast = nil
				for _, m in ipairs(mine) do
					if m.spell.name == name and (m.spell.kind == "heal" or m.spell.kind == "hot") then
						selfCast = { target = target, amount = SpellAmount(m) }
						break
					end
				end
			end
		elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED"
			or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_SUCCEEDED" then
			if unit == "player" then selfCast = nil end
		elseif event == "SPELLS_CHANGED" or event == "PLAYER_LEVEL_UP" or event == "PLAYER_EQUIPMENT_CHANGED" then
			ResolveSpells()
			needLayout = true
		else
			-- roster changes, entering the world, combat over
			if event ~= "PLAYER_REGEN_ENABLED" then
				if #mine == 0 then ResolveSpells() end
				RefreshRoster()
			else
				-- combat is over: "only in combat" keeps everything up for a few more seconds
				lingerUntil = (db.combatOnly and db.linger) and (GetTime() + math.max(0, db.lingerSeconds or 0)) or 0
				if holder and holder.driven and lingerUntil > GetTime() then
					-- take the hide-out-of-combat driver off right away so the icons stay up
					holder.driven = false
					UnregisterStateDriver(holder, "visibility")
					holder:Show()
				end
				needLayout = true
			end
		end
	end)

	ResolveSpells()
	RefreshRoster()
	C_Timer.NewTicker(TICK, Tick)
end
