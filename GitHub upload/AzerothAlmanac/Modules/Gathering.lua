-- Gathering and fishing: every herb, vein, chest and other lootable object a character opens, and
-- every catch while fishing. Creatures skinned are kept on the creature's own page (Bestiary).
--   A node is known by its name ("Copper Vein"); the hidden item database names the object once
--   it has been looted (an object can't be named after the fact otherwise). Each gather records
--   where (zone and a few spots per zone), your skill at the time, and what came out.
--   Tiers by times gathered, named after the profession ranks (fixed, like the creature tiers):
--   Sighted (seen, never gathered), Apprentice 1, Journeyman 5 (reveals everything the node can
--   hold: the Classic records), Expert 15 (adds how likely each is), Artisan 50, Master 200.
--   Fishing is kept per zone: catches, your skill, the pools (schools) you fished from.
-- found.node[name]   = { name, kind = "herb" | "ore" | "chest", ids = { [objectID] = true }, gathered,
--                        items = { [item] = times }, qty = { [item] = total }, z = { [map] = n },
--                        spots = { [map] = { "x:y" } }, skill = { lo, hi } }
--                      sighted = times seen, sz = { [map] = n }, seen = { [map] = { "x:y" } }
--   Sighted: a herb, vein or chest in front of you (the game's soft interact target, the one the
--   gathering highlight sparkles) is recorded even when you can't gather it yet - skill too low,
--   or just passing by - with where you stood, so it can be found on the map. Quest objects and
--   other objects (mailboxes, benches) are left out.
-- found.fishing[map] = { name, zone, gathered, items, qty, pools = { [name] = n }, spots, skill }

local _, ns = ...
local L = ns.L
local G = ns:NewModule("Gathering")
local R = ns.Readable

G.TIERS = { L["Sighted"], L["Apprentice"], L["Journeyman"], L["Expert"], L["Artisan"], L["Master"] }
G.AT = { 0, 1, 5, 15, 50, 200 } -- times gathered for each tier (hard-coded, not a setting)
G.STUDIED, G.MASTERED = G.AT[3], G.AT[4] -- (what's revealed: everything it holds, then the chances)
-- the gatherer's title in a rank toast ("Expert Miner"); chests and objects keep the rank alone
G.TRADE = { herb = L["Herbalist"], ore = L["Miner"], fish = L["Angler"] }
G.TIER_HINTS = {
	L["Seen, never gathered."],
	L["Gathered at least once: what came out is recorded."],
	L["Everything it can hold is known."],
	L["How likely each find is, too."],
	L["A gatherer's milestone: 50 times."],
	L["Few know it better: 200 times."],
}

-- the gathering spell just cast decides the kind, and which skill to read
local SPELLS = {
	[L["Herb Gathering"]] = "herb", [L["Mining"]] = "ore", [L["Opening"]] = "chest", [L["Opening - No Text"]] = "chest",
	[L["Fishing"]] = "fish",
}
local SKILL = { herb = L["Herbalism"], ore = L["Mining"], fish = L["Fishing"] }
G.KINDS = {
	{ key = "herb", label = L["Herbs"], icon = { "Trade_Herbalism", "INV_Misc_Herb_07" }, flavor = "Herbalism" },
	{ key = "ore", label = L["Ore and stone"], icon = { "Trade_Mining", "INV_Ore_Copper_01" }, flavor = "Mining" },
	{ key = "chest", label = L["Chests and objects"], icon = { 1450989, 132594, "INV_Box_02" }, flavor = "Blacksmithing" },
	{ key = "fish", label = L["Fishing"], icon = { "Trade_Fishing", "INV_Misc_Fish_02" }, flavor = "Fishing" },
}
G.KIND = {}
for _, k in ipairs(G.KINDS) do G.KIND[k.key] = k end

local lastCast, lastKind = 0, nil
local opened = {} -- loot already counted: [guid or "fish"] = time

local function Call(fn, ...)
	if not fn then return nil end
	local ok, a, b, c, d, e, f, g = pcall(fn, ...)
	if ok then return R(a), R(b), R(c), R(d), R(e), R(f), R(g) end
end

-- your rank in a skill (Herbalism, Mining, Fishing), or nil
function G:SkillRank(name)
	if not (name and GetNumSkillLines and GetSkillLineInfo) then return nil end
	for i = 1, (Call(GetNumSkillLines) or 0) do
		local n, isHeader, _, rank = Call(GetSkillLineInfo, i)
		if n == name and not isHeader then return rank end
	end
end

local function SpellName(id)
	if C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, id)
		return ok and type(info) == "table" and R(info.name) or nil
	elseif GetSpellInfo then
		return (Call(GetSpellInfo, id))
	end
end

ns:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
	if unit ~= "player" then return end
	spellID = R(spellID)
	if type(spellID) ~= "number" then return end
	local kind = SPELLS[SpellName(spellID) or ""]
	if kind then lastCast, lastKind = GetTime(), kind end
end)

local function Skill(rec, kind)
	local rank = G:SkillRank(SKILL[kind])
	if not rank then return end
	rec.skill = rec.skill or { rank, rank }
	if rank < rec.skill[1] then rec.skill[1] = rank end
	if rank > rec.skill[2] then rec.skill[2] = rank end
end

-- quest items (item class 12): an object that only gives these is a quest object (a Sack of Oats,
-- a Farm Chicken Egg), not something you gather. Those stay with the item (Items page: looted from)
-- and its quest.
local QUEST_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12
local function IsQuestItem(item)
	local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	if not instant then return false end
	local ok, _, _, _, _, _, classID = pcall(instant, item)
	return ok and R(classID) == QUEST_CLASS
end
G.IsQuestItem = IsQuestItem

local function OnlyQuestItems(items)
	local any = false
	for item in pairs(items or {}) do
		any = true
		if not IsQuestItem(item) then return false end
	end
	return any
end
G.OnlyQuestItems = OnlyQuestItems

local function Fill(rec, items, where)
	rec.gathered = (rec.gathered or 0) + 1
	rec.items = rec.items or {}
	rec.qty = rec.qty or {}
	for item, q in pairs(items) do
		rec.items[item] = (rec.items[item] or 0) + 1
		rec.qty[item] = (rec.qty[item] or 0) + q
	end
	if where.map then
		rec.z = rec.z or {}
		rec.z[where.map] = (rec.z[where.map] or 0) + 1
		if ns.Bestiary then ns.Bestiary:AddSpot(rec, "spots", where) end
	end
end

-- the tier a node or fishing spot has reached (1 Sighted .. 6 Master), and how many more to the next
function G:Tier(rec)
	local n = rec and rec.gathered or 0
	for t = #self.AT, 2, -1 do
		if n >= self.AT[t] then return t, self.AT[t + 1] and (self.AT[t + 1] - n) or nil end
	end
	return 1, self.AT[2] - n
end

-- a tier's badge: the creature tiers' (same colours), with the profession's own icon for Apprentice
function G:TierIcon(tier, kind)
	local B = ns.Bestiary
	local k = self.KIND[kind or ""]
	if tier == 2 and k and ns.Widgets and ns.Widgets.FindIcon then return ns.Widgets.FindIcon(k.icon) end
	return B and B:TierIcon(tier) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

function G:TierMarkup(tier, size, kind)
	size = size or 16
	local icon = self:TierIcon(tier, kind)
	if type(icon) == "string" and not icon:lower():find("^interface\\icons\\") then return ("|T%s:%d:%d|t"):format(icon, size, size) end
	return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(tostring(icon), size, size)
end

-- the rank as a title: "Expert Miner", "Journeyman Herbalist" (chests: "Expert")
function G:Title(tier, kind)
	local trade = self.TRADE[kind or ""]
	return trade and (self.TIERS[tier] .. " " .. trade) or self.TIERS[tier]
end

local function TierCheck(rec, before, label, kind)
	local after = G:Tier(rec)
	if after > before and after >= 3 then
		ns:Fire("TOAST", "tier", G:Title(after, kind), label, G:TierIcon(after, kind), after - 1)
	end
end

local function OnLoot()
	if not (ns.db and GetNumLootItems and GetLootSourceInfo) then return end
	local fishing = R(IsFishingLoot and IsFishingLoot()) == true
	local recent = GetTime() - lastCast < 4
	local kind = recent and lastKind or nil
	local where = ns.Where()
	local now = GetTime()
	local byObject, catch, pools = {}, {}, {}
	for slot = 1, (Call(GetNumLootItems) or 0) do
		local link = Call(GetLootSlotLink, slot)
		local item = type(link) == "string" and tonumber(link:match("item:(%d+)"))
		if item then
			local _, _, qty = Call(GetLootSlotInfo, slot)
			qty = tonumber(qty) or 1
			local sources = { pcall(GetLootSourceInfo, slot) }
			local fromObject = false
			if sources[1] then
				for i = 2, #sources, 2 do
					local guid = R(sources[i])
					local gkind, id = ns.ParseGuid(guid)
					if gkind == "GameObject" and id then
						local name = ns.DB and ns.DB.object and ns.DB.object[id]
						if fishing then
							if name then pools[name] = true end
						elseif name then
							local o = byObject[guid] or { id = id, name = name, items = {} }
							byObject[guid] = o
							o.items[item] = (o.items[item] or 0) + qty
							fromObject = true
						end
					end
				end
			end
			if fishing then catch[item] = (catch[item] or 0) + qty end
		end
	end

	if fishing then
		if next(catch) and where.map and (not opened.fish or now - opened.fish > 2) then
			opened.fish = now
			local rec = ns.Store:Get("fishing", where.map)
			local before = G:Tier(rec)
			rec = ns.Store:Discover("fishing", where.map, { name = where.zone, zone = where.zone },
				(L["Fishing in %s"]):format(where.zone or "?"), where)
			if rec then
				Fill(rec, catch, where)
				Skill(rec, "fish")
				rec.pools = rec.pools or {}
				for name in pairs(pools) do rec.pools[name] = (rec.pools[name] or 0) + 1 end
				TierCheck(rec, before, (L["Fishing in %s"]):format(where.zone or "?"), "fish")
			end
			ns:Fire("CHANGED", "fishing", where.map)
		end
		return
	end

	for guid, o in pairs(byObject) do
		local keep = kind == "herb" or kind == "ore" or not OnlyQuestItems(o.items)
		local last = opened[guid]
		if keep and last and now - last < 2 then
			-- the same loot window again (LOOT_READY can fire twice)
		elseif keep and last and now - last < 300 then
			-- another swing at the same vein: its ore and gems count, the gather doesn't again
			opened[guid] = now
			local rec = ns.Store:Get("node", o.name)
			if rec then
				rec.items = rec.items or {}
				rec.qty = rec.qty or {}
				for item, q in pairs(o.items) do
					if not rec.items[item] then rec.items[item] = 1 end
					rec.qty[item] = (rec.qty[item] or 0) + q
				end
				ns:Fire("CHANGED", "node", o.name)
			end
		elseif keep then
			opened[guid] = now
			local okind = (kind ~= "fish" and kind) or "chest"
			local rec = ns.Store:Get("node", o.name)
			local before = G:Tier(rec)
			local label = G.KIND[okind].label
			rec = ns.Store:Discover("node", o.name, { name = o.name }, (L["%s (%s)"]):format(o.name, label:lower()), where)
			if rec then
				-- a gathering cast names the kind; an object opened without one is a chest (or other)
				if kind and kind ~= "fish" or not rec.kind then rec.kind = okind end
				rec.ids = rec.ids or {}
				rec.ids[o.id] = true
				Fill(rec, o.items, where)
				Skill(rec, rec.kind)
				TierCheck(rec, before, o.name, rec.kind)
			end
			ns:Fire("CHANGED", "node", o.name)
		end
	end
end

ns:RegisterEvent("LOOT_READY", function()
	ns.doing = "reading gathering loot"
	local ok, err = pcall(OnLoot)
	if not ok then ns.Debug("gathering: " .. tostring(err)) end
	ns.doing = "idle"
end)

-- everything a node can hold in the Classic records, over all its object IDs: { { item, chance } }
function G:Contents(rec)
	local best = {}
	for id in pairs(rec and rec.ids or {}) do
		for _, e in ipairs(ns.ItemDB:ObjectLoot(id)) do
			if not best[e.item] or e.chance > best[e.item] then best[e.item] = e.chance end
		end
	end
	local out = {}
	for item, chance in pairs(best) do out[#out + 1] = { item = item, chance = chance } end
	table.sort(out, function(a, b) return a.chance > b.chance end)
	return out
end

---------------------------------------------------------------------------
-- Sighted: nodes in front of you, gathered or not
---------------------------------------------------------------------------

local sightedAt = {} -- [guid] = time, so standing by a node counts it once
local sightCount = 0
local SIGHT_AGAIN = 120

-- herb / ore / chest from the name (the gathering highlight's rules), or nil for anything else
local function KindOf(name)
	local NH = ns.QoL and ns.QoL.NodeHighlight
	local k = NH and NH.Classify and select(2, pcall(NH.Classify, name))
	if k == "herb" or k == "ore" or k == "chest" then return k end
end

-- everything the object can hold is a quest item (by the Classic records)
local function QuestOnlyObject(id)
	local list = ns.ItemDB and ns.ItemDB:ObjectLoot(id) or {}
	if #list == 0 then return false end
	for _, e in ipairs(list) do if not IsQuestItem(e.item) then return false end end
	return true
end

function G:Sight()
	if not ns.db then return end
	local guid = R(UnitGUID("softinteract"))
	if type(guid) ~= "string" or not guid:match("^GameObject") then return end
	local now = time()
	if sightedAt[guid] and now - sightedAt[guid] < SIGHT_AGAIN then return end
	local _, id = ns.ParseGuid(guid)
	local name = (id and ns.DB and ns.DB.object and ns.DB.object[id]) or R(UnitName("softinteract"))
	if type(name) ~= "string" or name == "" then return end
	local kind = KindOf(name)
	if not kind then return end
	local NH = ns.QoL and ns.QoL.NodeHighlight
	if NH and NH.IsQuestObject and NH.IsQuestObject(id, name) then return end
	if id and QuestOnlyObject(id) then return end
	sightedAt[guid] = now
	sightCount = sightCount + 1
	if sightCount > 400 then sightCount, sightedAt, opened = 0, { [guid] = now }, {} end
	local where = ns.Where()
	local rec = ns.Store:Get("node", name)
	local text = (L["%s (%s)"]):format(name, G.KIND[kind].label:lower())
	rec = ns.Store:Discover("node", name, { name = name }, text, where)
	if not rec then return end
	rec.kind = rec.kind or kind
	if id then rec.ids = rec.ids or {} rec.ids[id] = true end
	rec.sighted = (rec.sighted or 0) + 1
	if where.map then
		rec.sz = rec.sz or {}
		rec.sz[where.map] = (rec.sz[where.map] or 0) + 1
		if ns.Bestiary then ns.Bestiary:AddSpot(rec, "seen", where) end
	end
	ns:Fire("CHANGED", "node", name)
end

ns:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED", function()
	local ok, err = pcall(G.Sight, G)
	if not ok then ns.Debug("gathering sight: " .. tostring(err)) end
end)

-- quest objects recorded before they were told apart: removed once their items are known
local function Tidy()
	if not ns.db then return end
	local nodes = ns.Store:All("node")
	local removed = false
	for name, rec in pairs(nodes) do
		if rec.kind ~= "herb" and rec.kind ~= "ore" and OnlyQuestItems(rec.items) then nodes[name] = nil removed = true end
	end
	if removed then ns:Fire("CHANGED", "node") end
end
ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
	C_Timer.After(5, function()
		pcall(Tidy)
		-- build the object contents index now, not in the middle of the first sighting
		if ns.ItemDB and ns.ItemDB.ObjectLoot then pcall(ns.ItemDB.ObjectLoot, ns.ItemDB, 0) end
	end)
end)

-- totals for milestones and the overview: gathers by kind, fish caught, creatures skinned
function G:Totals()
	local t = { herb = 0, ore = 0, chest = 0, fish = 0, skin = 0 }
	for _, rec in pairs(ns.Store:All("node")) do t[rec.kind or "chest"] = (t[rec.kind or "chest"] or 0) + (rec.gathered or 0) end
	for _, rec in pairs(ns.Store:All("fishing")) do t.fish = t.fish + (rec.gathered or 0) end
	for _, rec in pairs(ns.Store:All("creature")) do t.skin = t.skin + (rec.gathered or 0) end
	return t
end
