-- Bestiary page: every creature you've met. Left: the list (search, filter by rarity or type,
-- this zone only). Right, on parchment: its 3D model (drag to turn it), what it is, its research
-- tier, health and heals, the abilities that hit you, casts, debuffs, loot with your own drop
-- rates, gathering, and where it lives.

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local B = ns.Bestiary

-- the page's own icon (picked by name): the legendary beast upgrade stone, else the creature icon
local page = { key = "bestiary", title = L["Creatures"], icon = "Interface\\AddOns\\AzerothAlmanac\\Media\\Tab_Creatures", order = 3 }
local list, detail, countText, filterButton, model, nameText, subText, tierBar, firstText, badge, killPin, face, gambitCard
local favButton -- (Wild Gambit's favourite star)
local FAV_TEXTURE = "Interface\\AddOns\\AzerothAlmanac\\Media\\Badge_Favorite" -- (a ruby heart in gold)
local FAV_MARKUP = "|T" .. FAV_TEXTURE .. ":13:13|t"
local filter, kindFilter, zoneFilter = "", nil, nil -- zoneFilter: nil (all), "here", or a uiMapID
local zoneButton
local tierFilter -- nil (everything) or a tier 1..6 (Sighted .. 200 kills), the header's dropdown
local tierButton
local TierLabel, TierMenu -- (below)
local tierCounts = { 0, 0, 0, 0, 0, 0 }
-- the tiers as the filter shows them: the research tiers, then 50 and 200 kills (Wild Gambit's
-- Epic and Legendary), in the item quality colours
local FILTER_TIERS = {
	{ B.TIERS[1], "ff9d9d9d" }, { B.TIERS[2], "ffffffff" }, { B.TIERS[3], "ff1eff00" },
	{ B.TIERS[4], "ff0070dd" }, { B.TIERS[5], "ffa335ee" }, { B.TIERS[6], "ffff8000" },
}
local shown -- npc id on the page

local RARITY = {
	normal = L["Normal"], trivial = L["Normal"], minus = L["Normal"],
	elite = L["Elite"], rare = L["Rare"], rareelite = L["Rare Elite"], worldboss = L["Boss"],
}

local function Rarity(rec)
	if rec.boss then return L["Boss"] end
	return RARITY[rec.class or "normal"] or L["Normal"]
end

local function LevelText(rec)
	if not rec.lo then return "?" end
	if rec.lo == -1 then return "??" end
	if rec.lo == rec.hi then return tostring(rec.lo) end
	return rec.lo .. "-" .. rec.hi
end

local function NameColor(rec)
	if rec.boss or rec.class == "worldboss" then return "|cffff8000" end
	if rec.class == "rare" or rec.class == "rareelite" then return "|cffc0c0ff" end
	if rec.class == "elite" then return "|cffffd100" end
	return "|cffffffff"
end

---------------------------------------------------------------------------
-- Spells and items, from the game
---------------------------------------------------------------------------

local function SpellInfo(id)
	if id == 6603 then return L["Melee"], 132147 end
	if C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, id)
		if ok and type(info) == "table" then return info.name, info.iconID end
	elseif GetSpellInfo then
		local name, _, icon = GetSpellInfo(id)
		return name, icon
	end
end

local function SpellDescription(id)
	if id == 6603 or not (C_Spell and C_Spell.GetSpellDescription) then return nil end
	local ok, text = pcall(C_Spell.GetSpellDescription, id)
	if ok and type(text) == "string" and text ~= "" then
		if #text > 160 then text = text:sub(1, 157) .. "..." end
		return text
	end
end

-- what one use of an ability does, read from its own tooltip: "15 - 25 per hit", "120 over 18 sec",
-- or both ("10 - 20 per hit, then 30 over 9 sec"). nil when the tooltip has no damage numbers.
local function DamageNote(id)
	if id == 6603 or not (C_Spell and C_Spell.GetSpellDescription) then return nil end
	local ok, text = pcall(C_Spell.GetSpellDescription, id)
	if not (ok and type(text) == "string" and text ~= "") then return nil end
	text = text:gsub(",", "")
	local parts = {}
	local lo, hi = text:match("(%d+) to (%d+)")
	local overN, overS = text:match("(%d+)[%a ]-damage over (%d+) sec")
	if not overN then overN, overS = text:match("(%d+)[%a ]- over (%d+) sec") end
	if lo and hi and not (overN and text:find(lo .. " to " .. hi .. "[%a ]-over")) then
		parts[#parts + 1] = (lo == hi and lo or (lo .. " - " .. hi)) .. " " .. L["per hit"]
	elseif not overN then
		local one = text:match("(%d+)[%a ]-damage")
		if one then parts[#parts + 1] = one .. " " .. L["per hit"] end
	end
	if overN then parts[#parts + 1] = (L["%s over %s sec"]):format(overN, overS) end
	if #parts == 0 then return nil end
	return table.concat(parts, ", " .. L["then"] .. " ")
end

local waitingItems = false
local function ItemText(id)
	local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local ok, name, _, quality = pcall(getInfo, id)
	local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	local icon = instant and select(5, instant(id))
	local iconText = icon and ("|T" .. icon .. ":16:16:0:0|t ") or ""
	if not (ok and name) then
		waitingItems = true
		return iconText .. (L["item %d"]):format(id)
	end
	local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
	local hex = color and color.hex or "|cffffffff"
	-- dark text reads better on parchment for common items
	if (quality or 1) <= 1 then hex = "|cff2b1d0e" end
	return iconText .. hex .. name .. "|r"
end

local function Icon(id) return id and ("|T" .. id .. ":16:16:0:0|t ") or "" end

---------------------------------------------------------------------------
-- The page for one creature
---------------------------------------------------------------------------

local CDB = ns.CreatureDB
local NOTE = "|cffbfbfbf"      -- secondary text on dark panels
local CLASSIC = "|cff8c8c8c"   -- "Classic records" notes

local function Pct(n, d) return math.floor(n / d * 100 + 0.5) end

local function Describe(npc, rec)
	local b = {}
	local tier = B:Tier(rec)
	local c = CDB:Get(npc)
	local th = B:Kills(rec)

	-- General
	b[#b + 1] = { "banner", L["General"] }
	b[#b + 1] = { "stat", L["Level"], LevelText(rec) }
	b[#b + 1] = { "stat", L["Rarity"], Rarity(rec) }
	b[#b + 1] = { "stat", L["Type"], (rec.type or "?") .. (rec.family and (" (" .. rec.family .. ")") or "") }
	b[#b + 1] = { "stat", L["Kills"], tostring(B:KillCount(rec)) }
	local who = {}
	for key in pairs(rec.c or {}) do if key ~= rec.b then who[#who + 1] = ns.CharName(key) end end
	table.sort(who)
	b[#b + 1] = { "stat", L["First met"], ns.CharName(rec.b) .. ", " .. ns.DateText(rec.f) }
	if #who > 0 then b[#b + 1] = { "stat", L["Also met by"], table.concat(who, ", ") } end
	b[#b + 1] = { "stat", L["Last seen"], ns.AgoText(rec.l) }

	-- Health
	b[#b + 1] = { "banner", L["Health"] }
	local hp, samples = B:Health(rec)
	b[#b + 1] = { "stat", L["Observed"], hp and (L["about %d (%s)"]):format(hp, ns.N(samples, "clean kill", "clean kills")) or (NOTE .. L["unknown: kill one on its own"] .. "|r") }
	if rec.heal then
		b[#b + 1] = { "stat", L["Heals itself"], (L["%s, up to about %d"]):format(ns.Times(rec.heal[1]), rec.heal[2]) }
	end
	if c and tier >= 2 and c.hpLo then
		b[#b + 1] = { "stat", CLASSIC .. L["Classic health"] .. "|r", CLASSIC .. (c.hpLo == c.hpHi and tostring(c.hpLo) or (c.hpLo .. " - " .. c.hpHi)) .. "|r" }
		b[#b + 1] = { "stat", CLASSIC .. L["Classic armor"] .. "|r", CLASSIC .. tostring(c.armor or "?") .. "|r" }
		b[#b + 1] = { "stat", CLASSIC .. L["Classic melee per hit"] .. "|r", CLASSIC .. (L["about %d"]):format(c.dmg or 0) .. "|r" }
	elseif c then
		b[#b + 1] = { "small", CLASSIC .. L["Classic records are revealed once you've fought it."] .. "|r" }
	end

	-- Abilities
	b[#b + 1] = { "banner", L["Abilities"] }
	local known, hidden = CDB:KnownSpells(npc, rec, tier)
	local list = {}
	for id, how in pairs(known) do list[#list + 1] = { id = id, how = how, t = rec.ab and rec.ab[id] and rec.ab[id].t or 0 } end
	table.sort(list, function(x, y)
		if x.t ~= y.t then return x.t > y.t end
		return x.id < y.id
	end)
	local slots = {}
	for _, e in ipairs(list) do
		local a = rec.ab and rec.ab[e.id]
		local note
		local perHit = DamageNote(e.id)
		if e.id == 6603 and c and c.dmg and tier >= 2 then
			perHit = (L["about %d per hit"]):format(c.dmg)
		end
		if perHit then
			note = perHit
		elseif a then
			note = (L["about %d per fight"]):format(math.floor(a.t / a.f + 0.5))
		elseif rec.db and rec.db[e.id] then
			note = (L["left on you %s"]):format(ns.Times(rec.db[e.id]))
		elseif e.how == "studied" then
			note = L["known from study"]
		elseif e.how == "cast" then
			note = L["seen casting it"]
		else
			note = L["seen"]
		end
		local extra = {}
		if a then extra[#extra + 1] = (L["Hit you in %s: about %d per fight, up to %d in one."]):format(ns.N(a.f, "fight", "fights"), math.floor(a.t / a.f + 0.5), a.hi) end
		if rec.db and rec.db[e.id] then extra[#extra + 1] = (L["Its effect stayed on you %s."]):format(ns.Times(rec.db[e.id])) end
		slots[#slots + 1] = { spell = e.id, note = NOTE .. note .. "|r", extra = #extra > 0 and table.concat(extra, " ") or nil }
	end
	if #slots > 0 then b[#b + 1] = { "slots", slots } else b[#b + 1] = { "small", L["None seen yet. Abilities that hit you are recorded after each fight."] } end
	if (rec.casts or 0) > 0 then
		b[#b + 1] = { "small", (L["Seen starting a cast %s (the game hides which spell)."]):format(ns.Times(rec.casts)) }
	end
	if hidden > 0 then
		b[#b + 1] = { "small", CLASSIC .. (L["%s not yet seen. All are revealed at Hunted (%s)."]):format(ns.N(hidden, "more ability", "more abilities"), ns.N(th.studied, "kill", "kills")) .. "|r" }
	end

	-- Defenses
	if c then
		b[#b + 1] = { "banner", L["Defenses"] }
		if tier >= 4 then
			local mech, schools = CDB:Immunities(c)
			local all = {}
			for _, x in ipairs(mech) do all[#all + 1] = x end
			for _, x in ipairs(schools) do all[#all + 1] = x end
			b[#b + 1] = { "stat", L["Immune to"], #all > 0 and table.concat(all, ", ") or L["nothing special"] }
			local res = {}
			for i, v in ipairs(c.res) do if v and v ~= 0 then res[#res + 1] = ("%s %d"):format(CDB.RESIST_NAMES[i], v) end end
			b[#b + 1] = { "stat", L["Resistances"], #res > 0 and table.concat(res, ", ") or L["none"] }
		else
			b[#b + 1] = { "small", CLASSIC .. (L["Immunities and resistances are revealed at Master Hunter (%s)."]):format(ns.N(th.mastered, "kill", "kills")) .. "|r" }
		end
	end

	-- Loot
	b[#b + 1] = { "banner", L["Loot"] }
	local corpses = rec.corpses or 0
	local classic = {}
	if c then for _, e in ipairs(c.loot) do classic[e.item] = e end end
	if corpses == 0 then
		b[#b + 1] = { "small", L["Nothing looted yet."] }
	else
		b[#b + 1] = { "stat", L["Corpses looted"], tostring(corpses) }
		if rec.money and rec.money[1] > 0 then
			b[#b + 1] = { "stat", L["Money per corpse"], (L["about %s"]):format(ns.MoneyText(math.floor(rec.money[2] / corpses + 0.5))) }
		end
		local items = {}
		for id, n in pairs(rec.loot or {}) do items[#items + 1] = { id = id, n = n } end
		table.sort(items, function(x, y) return x.n > y.n end)
		local ls = {}
		for _, e in ipairs(items) do
			local note = ("%d / %d (%d%%)"):format(e.n, corpses, Pct(e.n, corpses))
			if tier >= 4 and classic[e.id] then note = note .. CLASSIC .. "  " .. (L["Classic %.1f%%"]):format(classic[e.id].chance) .. "|r" end
			ls[#ls + 1] = { item = e.id, note = note }
		end
		b[#b + 1] = { "slots", ls }
	end
	if c and #c.loot > 0 then
		local unseen = {}
		for _, e in ipairs(c.loot) do if not (rec.loot and rec.loot[e.item]) then unseen[#unseen + 1] = e end end
		if #unseen > 0 then
			if tier >= 4 then
				b[#b + 1] = { "small", CLASSIC .. L["Other drops in Classic records:"] .. "|r" }
				local cs = {}
				for n, e in ipairs(unseen) do
					if n > 12 then break end
					cs[#cs + 1] = { item = e.item, note = CLASSIC .. ("%.1f%%"):format(e.chance) .. (e.quest and (" " .. L["(quest)"]) or "") .. "|r", grey = true }
				end
				b[#b + 1] = { "slots", cs }
				if #unseen > 12 then b[#b + 1] = { "small", CLASSIC .. (L["...and %d rarer drops."]):format(#unseen - 12) .. "|r" } end
			else
				local common = 0
				for _, e in ipairs(unseen) do if e.chance >= 1 then common = common + 1 end end
				local text = common > 0 and (L["%s and %s not yet found."]):format(ns.N(common, "more common drop", "more common drops"), ns.N(#unseen - common, "rare one", "rare ones"))
					or (L["%s not yet found."]):format(ns.N(#unseen, "rare drop", "rare drops"))
				b[#b + 1] = { "small", CLASSIC .. text .. " " .. L["The full table is revealed at Master Hunter."] .. "|r" }
			end
		end
		if tier >= 2 and c.goldHi then
			b[#b + 1] = { "stat", CLASSIC .. L["Classic money"] .. "|r", CLASSIC .. ns.MoneyText(c.goldLo or 0) .. " - " .. ns.MoneyText(c.goldHi) .. "|r" }
		end
	end
	if (rec.gathered or 0) > 0 or (c and #c.skin > 0 and tier >= 4) then
		b[#b + 1] = { "banner", L["Skinning and gathering"] }
		if (rec.gathered or 0) > 0 then
			local gs = {}
			for id, n in pairs(rec.gather or {}) do gs[#gs + 1] = { item = id, note = ("%d / %d"):format(n, rec.gathered) } end
			b[#b + 1] = { "slots", gs }
		end
		if c and #c.skin > 0 and tier >= 4 then
			local ss = {}
			for _, e in ipairs(c.skin) do ss[#ss + 1] = { item = e.item, note = CLASSIC .. (L["Classic %.0f%%"]):format(e.chance) .. "|r", grey = not (rec.gather and rec.gather[e.item]) } end
			b[#b + 1] = { "slots", ss }
		end
	end

	-- Where
	b[#b + 1] = { "banner", L["Where"] }
	local zones = {}
	for map, n in pairs(rec.z or {}) do
		local z = ns.Store:Get("zone", map)
		local name = z and z.name
		if not name and C_Map and C_Map.GetMapInfo then
			local ok, info = pcall(C_Map.GetMapInfo, map)
			name = ok and info and info.name
		end
		zones[#zones + 1] = { name = name or ("map " .. map), n = n, map = map, known = ns.Store:Shown("zone")[map] ~= nil }
	end
	table.sort(zones, function(x, y) return x.n > y.n end)
	local zs = {}
	for _, z in ipairs(zones) do
		local kills = #B:Spots(rec, "kz", z.map)
		zs[#zs + 1] = { name = z.name, icon = W.KindIcon("zone"),
			note = (L["seen %s"]):format(ns.Times(z.n)) .. (kills > 0 and ("  ·  " .. (L["killed in %d spots"]):format(kills)) or ""),
			tip = z.known and L["Click to open in Places, with where it was seen and killed on the map."] or nil,
			onClick = z.known and function() local p = ns.UI:GetPage("places") if p then p:ShowZone(z.map, npc) end end or nil }
	end
	-- (0.68.3) a dungeon boss: its dungeon (inside one, the game doesn't say which map you're on)
	local dungeon, instID
	if ns.Dungeons and ns.Dungeons.DungeonOf then dungeon, instID = ns.Dungeons:DungeonOf(npc) end
	if dungeon and instID then
		zs[#zs + 1] = { name = dungeon.name, icon = W.KindIcon("instance"), note = ns.Dungeons:SizeText(instID, ns.Store:Get("instance", instID)),
			tip = L["Click to open it in Dungeons."],
			onClick = function() local p = ns.UI:GetPage("dungeons") if p and p.ShowDungeon then p:ShowDungeon(instID) end end }
	end
	if #zs > 0 then b[#b + 1] = { "slots", zs } end
	if #zs == 0 then b[#b + 1] = { "small", "?" } end

	-- quests you've found that ask for it
	local qs = {}
	for _, qid in ipairs(ns.QuestDB:ForTarget(npc)) do
		local q = ns.Store:Get("quest", qid)
		if q then
			local s = ns.Quests:MyStatus(qid)
			qs[#qs + 1] = { name = q.name or (L["quest %d"]):format(qid), icon = "Interface\\GossipFrame\\" .. (s == "a" and "ActiveQuestIcon" or "AvailableQuestIcon"),
				note = s == "d" and L["Done"] or s == "a" and L["In the quest log"] or nil, tip = L["Click to open in Quests."],
				onClick = function() local p = ns.UI:GetPage("quests") if p then p:ShowQuest(qid) end end }
		end
	end
	if #qs > 0 then
		table.sort(qs, function(x, y) return x.name < y.name end)
		b[#b + 1] = { "banner", L["Wanted for quests"] }
		b[#b + 1] = { "slots", qs }
	end
	if not c then
		b[#b + 1] = { "gap", 6 }
		b[#b + 1] = { "small", L["Not in the Classic records: everything here comes from your own adventures."] }
	end
	return b
end

-- each kind of creature gets a profession's painting behind its card
local TYPE_THEME = {
	Beast = { "Skinning", "Leatherworking", "Fishing" }, Humanoid = { "Tailoring", "Blacksmithing" },
	Elemental = { "Enchanting", "Mining" }, Undead = { "Alchemy", "FirstAid" }, Demon = { "Enchanting", "Alchemy" },
	Dragonkin = { "Blacksmithing", "Mining" }, Mechanical = { "Engineering", "Blacksmithing" },
	Giant = { "Mining" }, Critter = { "Herbalism", "Cooking" },
}

local function Show(npc, keepModel)
	shown = npc
	local rec = npc and ns.Store:Get("creature", npc)
	detail:SetTheme(rec and (TYPE_THEME[rec.type or ""] or { "Skinning", "Mining" }) or nil)
	if not rec then
		model:Hide()
		if face then face:Hide() end
		nameText:SetText("")
		subText:SetText("")
		tierBar:Hide()
		badge:Hide()
		firstText:SetText("")
		killPin:Hide()
		if gambitCard then gambitCard:Hide() end
		if favButton then favButton:Hide() end
		detail:SetBlocks(nil, L["Select a creature."])
		return
	end
	model:Show()
	if not keepModel or model.npc ~= npc then
		model.npc = npc
		model:ClearModel()
		pcall(model.SetCreature, model, npc)
		-- the page's own model knows the creature's appearance: keep it for its face badge
		if not rec.display then
			C_Timer.After(1, function()
				if model.npc == npc then
					local ok, d = pcall(model.GetDisplayInfo, model)
					if ok then
						B:KeepFace(npc, d)
						if gambitCard and shown == npc then pcall(gambitCard.ShowCreature, gambitCard, npc) end
					end
				end
			end)
		end
		model.facing = 0.4
		pcall(model.SetFacing, model, model.facing)
	end
	nameText:SetText(NameColor(rec) .. (rec.name or "?") .. "|r")
	if face then
		if not B:SetFace(face.art, npc, rec) then
			W.SetIcon(face.art, W.TYPE_ICON[rec.type or ""] or W.KIND.creature.icon)
			face.art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		end
		local kind = W.DragonFor(rec)
		if kind == "boss" or kind == "worldboss" then face:SetRing(1, 0.5, 0)
		elseif kind == "elite" then face:SetRing(1, 0.82, 0)
		elseif kind then face:SetRing(0.78, 0.78, 0.95)
		else face:SetRing(0.62, 0.5, 0.24) end
		W.SetDragon(face.dragon, kind, face, face:GetWidth())
		W.SetFactionBadge(face.faction, rec.faction)
		face:Show()
	end
	subText:SetText((L["Level %s %s %s"]):format(LevelText(rec), Rarity(rec), rec.family or rec.type or ""))
	local tier, need = B:FullTier(rec)
	local th = B:Kills(rec)
	tierBar:Show()
	-- the skills bar towards the next tier (Fought, Studied, Mastered, Revered at 50, Exalted at
	-- 200); past 200 it stays full and the kills keep counting
	local kills = B:KillCount(rec)
	local t1, t3, t4, t5, t6 = B:Thresholds(rec)
	local at = { t1, t3, t4, t5, t6 } -- the kills for tiers 2 .. 6
	-- the next tier with more kills to go (bosses and rares go Fought and Studied at one kill)
	local nextTier = tier + 1
	while at[nextTier - 1] and at[nextTier - 1] <= kills do nextTier = nextTier + 1 end
	while nextTier < 6 and at[nextTier] and at[nextTier] <= at[nextTier - 1] do nextTier = nextTier + 1 end
	local nextAt = at[nextTier - 1]
	if nextAt then
		tierBar:Set(nil, kills, nextAt, (L["%d / %d kills"]):format(kills, nextAt) .. "  ·  " .. (L["%d to %s"]):format(nextAt - kills, B.TIERS[nextTier]))
	else
		tierBar:Set(nil, 1, 1, ns.N(kills, "kill", "kills") .. "  ·  " .. B.TIERS[6])
	end
	tierBar:SetMarkers({ { t1, 2 }, { t3, 3 }, { t4, 4 }, { t5, 5 }, { t6, 6 } }, kills, nextAt or kills)
	badge:SetTier(tier, need, npc, rec)
	if gambitCard then pcall(gambitCard.ShowCreature, gambitCard, npc) end
	if favButton then favButton:SetCreature(npc) end
	firstText:SetText(NOTE .. (L["First met by %s on %s."]):format(ns.CharName(rec.b), ns.DateText(rec.f)) .. "|r")
	killPin.rec = rec
	killPin:SetShown(type(rec.lastKill) == "table" and rec.lastKill.map ~= nil)
	detail:SetBlocks(Describe(npc, rec))
end

---------------------------------------------------------------------------
-- List, filters
---------------------------------------------------------------------------

local function Matches(rec)
	if filter ~= "" and not ((rec.name or ""):lower():find(filter, 1, true)) then return false end
	if kindFilter then
		local k, v = kindFilter[1], kindFilter[2]
		if k == "rarity" then
			local group = rec.boss and "boss" or (rec.class == "rare" or rec.class == "rareelite") and "rare" or rec.class == "elite" and "elite" or "normal"
			if group ~= v then return false end
		elseif k == "type" and rec.type ~= v then
			return false
		end
	end
	if zoneFilter then
		local map = zoneFilter == "here" and ns.Where().map or zoneFilter
		if not (map and rec.z and rec.z[map]) then return false end
	end
	return true
end

-- a creature's place in the tier filter: its research tier, or 50 / 200 kills past Mastered
local function FilterTier(rec)
	return (B:FullTier(rec))
end

local function TierIconFor(t)
	return B:TierIcon(t)
end

local function TierName(t)
	local f = FILTER_TIERS[t]
	return ("|c%s%s|r"):format(f[2], f[1])
end

-- the button's label, and the chosen tier's round badge beside it
function TierLabel()
	local badge = tierButton and tierButton.badge
	if badge then
		badge:SetShown(tierFilter ~= nil)
		if tierFilter then
			B:SetTierTexture(badge.art, tierFilter)
			badge.art:SetTexture(TierIconFor(tierFilter))
			badge:SetRing(B:TierRing(tierFilter))
		end
		if tierButton.label then
			tierButton.label:ClearAllPoints()
			tierButton.label:SetPoint("LEFT", tierFilter and 30 or 10, 0)
			tierButton.label:SetPoint("RIGHT", tierButton.arrow, "LEFT", -4, 0)
		end
	end
	if not tierFilter then return L["Every tier"] end
	return TierName(tierFilter)
end

function TierMenu(anchor)
	local items = { { title = true, text = L["Tier"] } }
	local all = 0
	for t = 1, 6 do all = all + tierCounts[t] end
	local function Pick(value)
		tierFilter = value
		tierButton:SetText(TierLabel())
		page:Refresh()
	end
	items[#items + 1] = { text = L["Everything"] .. "  |cff999999" .. all .. "|r", selected = tierFilter == nil, run = function() Pick(nil) end }
	for t = 1, 6 do
		local f = FILTER_TIERS[t]
		items[#items + 1] = { text = ("|c%s%s|r  |cff999999%d|r"):format(f[2], f[1], tierCounts[t]), icon = TierIconFor(t), ring = { B:TierRing(t) },
			selected = tierFilter == t, run = function() Pick(t) end }
	end
	W.Menu(anchor, items)
end

-- world objects that answer as units (supply baskets, crates ...): kept out of Creatures
-- (B:IsObject). Every other filter applies first; the tier menu counts what's left in each tier
local function Collect()
	local rows, total = {}, 0
	for t = 1, 6 do tierCounts[t] = 0 end
	for npc, rec in pairs(ns.Store:Shown("creature")) do
		if not B:IsObject(rec) then
			total = total + 1
			if Matches(rec) then
				local tier = FilterTier(rec)
				tierCounts[tier] = tierCounts[tier] + 1
				if not tierFilter or tierFilter == tier then rows[#rows + 1] = { npc = npc, rec = rec } end
			end
		end
	end
	table.sort(rows, function(a, b) return (a.rec.name or "") < (b.rec.name or "") end)
	-- (0.69.0, #38) creatures met since you last looked come first, then the alphabetical list
	local listed = #rows
	if ns.New then
		local new, rest = ns.New:Split("bestiary", rows, function(r) return r.rec end, function(r) return r.npc end)
		if #new > 0 then
			rows = { ns.New:Header(#new) }
			for _, r in ipairs(new) do rows[#rows + 1] = r end
			rows[#rows + 1] = { header = (L["All creatures (%d)"]):format(#rest), key = "all" }
			for _, r in ipairs(rest) do rows[#rows + 1] = r end
		end
	end
	return rows, total, listed
end

local function FilterLabel()
	if not kindFilter then return L["All creatures"] end
	return kindFilter[3]
end

local function FilterMenu(anchor)
	local items = { { title = true, text = L["Show"] } }
	local function Add(text, value)
		local cur = kindFilter
		items[#items + 1] = { text = text, selected = (cur == nil and value == nil) or (cur and value and cur[1] == value[1] and cur[2] == value[2]) or false, run = function()
			kindFilter = value
			filterButton:SetText(FilterLabel())
			page:Refresh()
		end }
	end
	Add(L["All creatures"], nil)
	Add(L["Normal"], { "rarity", "normal", L["Normal"] })
	Add(L["Elite"], { "rarity", "elite", L["Elite"] })
	Add(L["Rare"], { "rarity", "rare", L["Rare"] })
	Add(L["Boss"], { "rarity", "boss", L["Boss"] })
	local types = {}
	for _, rec in pairs(ns.Store:Shown("creature")) do if rec.type then types[rec.type] = true end end
	local sorted = {}
	for t in pairs(types) do sorted[#sorted + 1] = t end
	table.sort(sorted)
	for _, t in ipairs(sorted) do Add(t, { "type", t, t }) end
	W.Menu(anchor, items)
end

local function ZoneName(map)
	local z = ns.Store:Get("zone", map)
	if z and z.name then return z.name end
	local ok, info = pcall(C_Map.GetMapInfo, map)
	return ok and type(info) == "table" and info.name or nil
end

local function ZoneLabel()
	if not zoneFilter then return L["All zones"] end
	if zoneFilter == "here" then return L["This zone"] end
	return ZoneName(zoneFilter) or L["All zones"]
end

-- every zone a met creature was seen in, by name
local function ZoneMenu(anchor)
	local items = { { title = true, text = L["Zone"] } }
	local function Add(text, value, icon)
		items[#items + 1] = { text = text, icon = icon, selected = zoneFilter == value, run = function()
			zoneFilter = value
			zoneButton:SetText(ZoneLabel())
			page:Refresh()
		end }
	end
	Add(L["All zones"], nil)
	Add(L["This zone"], "here")
	local seen, zones = {}, {}
	for _, rec in pairs(ns.Store:Shown("creature")) do
		for map in pairs(rec.z or {}) do
			if not seen[map] then
				seen[map] = true
				local name = ZoneName(map)
				if name then zones[#zones + 1] = { map = map, name = name } end
			end
		end
	end
	table.sort(zones, function(a, b) return a.name < b.name end)
	if #zones > 0 then items[#items + 1] = { title = true, text = L["Known zones"] } end
	for _, z in ipairs(zones) do Add(z.name, z.map) end
	W.Menu(anchor, items)
end
page.ZoneMenu = ZoneMenu

function page:Build(parent, header)
	local search = W.Search(header, 104, function(text)
		filter = text
		page:Refresh()
	end)
	search:SetPoint("LEFT", header, "LEFT", 16, -2)
	filterButton = W.Dropdown(header, FilterLabel(), 132, function(self) FilterMenu(self) end)
	filterButton:SetPoint("LEFT", search, "RIGHT", 10, 0)
	zoneButton = W.Dropdown(header, ZoneLabel(), 120, function(self) ZoneMenu(self) end)
	zoneButton:SetPoint("LEFT", filterButton, "RIGHT", 6, 0)
	countText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

	-- the tier filter: one dropdown, Everything or a single tier, each in its quality colour with
	-- its icon and how many creatures are at it
	tierButton = W.Dropdown(header, TierLabel(), 212, function(self) TierMenu(self) end) -- (room for "Legendary Hunter" on one line)
	tierButton:SetPoint("LEFT", zoneButton, "RIGHT", 6, 0)
	tierButton.badge = W.Portrait(tierButton, 18):SetThin()
	tierButton.badge:SetPoint("LEFT", 8, 0)
	tierButton.badge:EnableMouse(false)
	tierButton:SetText(TierLabel())
	countText:SetPoint("RIGHT", header, "RIGHT", -12, -2)

	local left = W.Inset(parent)
	left:SetPoint("TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", 0, 0)
	left:SetWidth(320)
	list = W.List(left, {
		rowHeight = 26,
		round = true,
		emptyText = L["No creatures yet. Every creature you meet is recorded here."],
		update = function(row, r)
			if r.header then
				-- (0.69.0) the New group's heading, and the one over the rest of the list
				row:SetHeader(true)
				row.icon:SetTexture(nil)
				row.text:SetText(r.header)
				row.right:SetText("")
				if type(row.tierTex) == "table" then row.tierTex:Hide() end
				if type(row.dragon) == "table" then row.dragon:Hide() end
				if type(row.faction) == "table" then row.faction:Hide() end
				if ns.New then ns.New:MarkRow(row, false) end
				return
			end
			if ns.New then ns.New:MarkRow(row, r.isNew, "bestiary", r.newKey) end
			-- the creature's face once known, else its type's icon (critters and no type in grey)
			if not B:SetFace(row.icon, r.npc, r.rec) then
				W.SetIcon(row.icon, W.TYPE_ICON[r.rec.type or ""] or W.KIND.creature.icon)
				row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				if row.icon.SetDesaturated then row.icon:SetDesaturated(r.rec.type == "Critter" or r.rec.type == nil) end
			end
			local WGm = ns.QoL and ns.QoL.WildGambit
			local star = (WGm and WGm.IsFavorite and WGm:IsFavorite(r.npc)) and (FAV_MARKUP .. " ") or ""
			row.text:SetText(star .. NameColor(r.rec) .. (r.rec.name or "?") .. "|r")
			-- elites, rares and bosses: the target frame's dragon round the face
			if type(row.dragon) ~= "table" then
				row.dragon = row.icon:GetParent():CreateTexture(nil, "OVERLAY", nil, 3)
			end
			local dragon = W.SetDragon(row.dragon, W.DragonFor(r.rec), row.icon, row.icon:GetWidth())
			-- Alliance or Horde: the faction crest at the face's bottom right
			if type(row.faction) ~= "table" then
				row.faction = row.icon:GetParent():CreateTexture(nil, "OVERLAY", nil, 5)
				row.faction:SetSize(12, 12)
				row.faction:SetPoint("CENTER", row.icon, "BOTTOMRIGHT", -1, 2)
			end
			W.SetFactionBadge(row.faction, r.rec.faction)
			if row.hasDragon ~= dragon then
				row.hasDragon = dragon
				row.text:SetPoint("LEFT", row.icon, "RIGHT", dragon and 15 or 7, 0)
			end
			local tier = B:FullTier(r.rec) -- (Revered and Exalted too)
			-- the tier as a small badge at the right end (the creature's face once Fought)
			if type(row.tierTex) ~= "table" then
				row.tierTex = W.Portrait(row, 21):SetThin() -- (round in a ring of the tier's colour, as the detail badge)
				row.tierTex:SetPoint("RIGHT", -5, 0)
				row.tierTex:EnableMouse(false)
			end
			row.tierTex:Show()
			B:SetTierTexture(row.tierTex.art, tier)
			row.tierTex:SetRing(B:TierRing(tier))
			row.right:ClearAllPoints()
			row.right:SetPoint("RIGHT", row.tierTex, "LEFT", -6, 0)
			row.right:SetText("|cff999999" .. LevelText(r.rec) .. "|r")
		end,
		onClick = function(r, row, mouse)
			if r.header or (mouse and mouse ~= "LeftButton") then return end
			if ns.New and ns.New:Clicked("bestiary", r) then list:Refresh() end
			Show(r.npc)
		end,
	})
	list:SetAllPoints(left)

	detail = W.Detail(parent, 170)
	detail:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
	detail:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

	-- your Wild Gambit card for the creature fills the top left (its spikes inside the box); without
	-- Wild Gambit, the model in a dark recessed box. The page's own model stays (unseen with the
	-- card), as it learns the creature's appearance for its face badge and the card.
	local WG = ns.QoL and ns.QoL.WildGambit
	local ok, card = false, nil
	if WG and WG.Showcase then ok, card = pcall(WG.Showcase, WG, detail.top) end
	local box
	if ok and card then
		box = CreateFrame("Frame", nil, detail.top)
		card:SetParent(box)
		card:SetScale(0.94) -- 92 x 124 and 17 of spike each side: about 149, clear of the panel edges
		card:SetPoint("CENTER", box, "CENTER")
		card:Hide()
		gambitCard = card
	else
		box = W.Inset(detail.top)
	end
	box:SetPoint("TOPLEFT", 0, 0)
	box:SetSize(170, 170)
	model = W.Try("PlayerModel", nil, box)
	model:SetPoint("TOPLEFT", 4, -4)
	model:SetPoint("BOTTOMRIGHT", -4, 4)
	model:EnableMouse(true)
	model:SetScript("OnMouseDown", function(self) self.dragX = GetCursorPosition() end)
	model:SetScript("OnMouseUp", function(self) self.dragX = nil end)
	model:SetScript("OnUpdate", function(self)
		if not self.dragX then return end
		local x = GetCursorPosition()
		self.facing = (self.facing or 0) + (x - self.dragX) / 90
		self.dragX = x
		pcall(self.SetFacing, self, self.facing)
	end)
	if gambitCard then
		model:SetAlpha(0)
		model:EnableMouse(false)
		gambitCard:SetFrameLevel(model:GetFrameLevel() + 4)
		-- the favourite heart (top left of the card box): a favourite is always on Wild Gambit's
		-- pick table and drawn more often; five at most, a sixth replaces one of them
		favButton = CreateFrame("Button", nil, box)
		favButton:SetSize(26, 26)
		favButton:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -4) -- (top left of the card box, clear of the card)
		favButton:SetFrameLevel(gambitCard:GetFrameLevel() + 30)
		favButton.icon = favButton:CreateTexture(nil, "ARTWORK")
		favButton.icon:SetAllPoints()
		favButton.icon:SetTexture(FAV_TEXTURE)
		favButton:SetHighlightTexture(FAV_TEXTURE, "ADD")
		function favButton:Paint()
			local on = WG:IsFavorite(self.npc)
			self.icon:SetDesaturated(not on)
			self.icon:SetAlpha(on and 1 or 0.45)
		end
		function favButton:SetCreature(npc)
			self.npc = npc
			self:Paint()
			self:Show()
		end
		local function Changed(npc)
			favButton:Paint()
			pcall(gambitCard.ShowCreature, gambitCard, npc)
			page:Refresh()
		end
		local function Name(n)
			local r = ns.Store:Get("creature", n)
			return type(r) == "table" and r.name or ("#" .. tostring(n))
		end
		favButton:SetScript("OnClick", function(self)
			local npc = self.npc
			if not npc then return end
			if WG:IsFavorite(npc) then WG:SetFavorite(npc, false) Changed(npc) return end
			if WG:SetFavorite(npc, true) ~= "full" then Changed(npc) return end
			-- five already: choose one to replace
			local items = { { text = (L["Five favourites already. Replace one with %s:"]):format(Name(npc)), title = true } }
			for _, old in ipairs(WG:Favorites()) do
				local oldNpc = old
				items[#items + 1] = { text = Name(oldNpc), icon = FAV_TEXTURE, run = function()
					WG:SetFavorite(npc, true, oldNpc)
					Changed(npc)
				end }
			end
			items[#items + 1] = { text = L["Keep them all"], run = function() end }
			W.Menu(self, items)
		end)
		favButton:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			local on = WG:IsFavorite(self.npc)
			GameTooltip:AddLine(on and L["Favourite"] or L["Make it a favourite"], 1, 0.82, 0)
			GameTooltip:AddLine((L["A favourite is always on Wild Gambit's pick table and is drawn more often with your chosen card. Up to %d (%d now)."]):format(WG.FAV_MAX, #WG:Favorites()), 1, 1, 1, true)
			if on then GameTooltip:AddLine(L["Click to remove it."], 0.6, 0.6, 0.6) end
			GameTooltip:Show()
		end)
		favButton:SetScript("OnLeave", GameTooltip_Hide)
		favButton:Hide()
	end

	-- the creature's face in a ring left of its name, in the target frame's dragon when it's an
	-- elite, rare or boss; the name and level line start after it
	local FACE, NAME_X = 44, 92
	face = W.Portrait(detail.top, FACE)
	face:SetPoint("CENTER", box, "TOPRIGHT", 14 + FACE / 2, -6 - FACE / 2)
	face.dragon = face:CreateTexture(nil, "OVERLAY", nil, 3)
	face.faction = face:CreateTexture(nil, "OVERLAY", nil, 6)
	face.faction:SetSize(20, 20)
	face.faction:SetPoint("CENTER", face, "BOTTOMRIGHT", -3, 4)
	face.faction:Hide()
	nameText = detail.top:CreateFontString(nil, "OVERLAY")
	W.HeroFont(nameText, 26)
	nameText:SetPoint("TOPLEFT", box, "TOPRIGHT", NAME_X, -6)
	nameText:SetPoint("RIGHT", detail.top, "RIGHT", -72, 0)
	nameText:SetJustifyH("LEFT")
	subText = detail.top:CreateFontString(nil, "OVERLAY")
	subText:SetFontObject(GameFontHighlight)
	subText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -6)
	subText:SetPoint("RIGHT", detail.top, "RIGHT", -72, 0)
	subText:SetJustifyH("LEFT")
	tierBar = W.SkillBar(detail.top) -- the character sheet's blue skill bar
	-- tier milestones: a tick on the bar and the tier's icon under it, lit once reached
	tierBar.marks = {}
	function tierBar:SetMarkers(list, kills, max)
		self.markList, self.markKills, self.markMax = list, kills, max
		local bar = self.bar
		local inner = math.max((bar:GetWidth() or 0) - 6, 1)
		local shown = 0
		-- only the next milestone is marked (its tick on the bar and its icon under it)
		local nextIndex
		for i, m in ipairs(list) do if kills < m[1] then nextIndex = i break end end
		for i, m in ipairs(list) do
			local mk = self.marks[i]
			if not mk then
				mk = CreateFrame("Frame", nil, self)
				mk:SetSize(18, 18)
				mk:SetFrameLevel(bar:GetFrameLevel() + 5)
				mk.tick = bar:CreateTexture(nil, "OVERLAY", nil, 6)
				mk.tick:SetSize(2, 17)
				mk.icon = mk:CreateTexture(nil, "ARTWORK")
				mk.icon:SetAllPoints()
				mk.ring = mk:CreateTexture(nil, "BACKGROUND")
				mk.ring:SetTexture(W.CIRCLE)
				mk.ring:SetPoint("TOPLEFT", -2, 2)
				mk.ring:SetPoint("BOTTOMRIGHT", 2, -2)
				local mask = mk:CreateMaskTexture()
				mask:SetTexture(W.CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
				mask:SetAllPoints(mk.icon)
				if mk.icon.AddMaskTexture then mk.icon:AddMaskTexture(mask) end
				mk:EnableMouse(true)
				mk:SetScript("OnEnter", function(f)
					GameTooltip:SetOwner(f, "ANCHOR_BOTTOM")
					GameTooltip:AddLine(B:TierMarkup(f.tier, 18) .. " " .. B:TierText(f.tier))
					GameTooltip:AddLine((L["at %s"]):format(ns.N(f.at, "kill", "kills")), 1, 1, 1)
					GameTooltip:AddLine(B.TIER_HINTS[f.tier], 0.8, 0.8, 0.8, true)
					GameTooltip:Show()
				end)
				mk:SetScript("OnLeave", GameTooltip_Hide)
				self.marks[i] = mk
			end
			local at, tier = m[1], m[2]
			mk.at, mk.tier = at, tier
			local x = 3 + inner * math.min(at / math.max(max, 1), 1)
			local reached = kills >= at
			local c = B.TIER_COLORS[tier]
			mk.tick:ClearAllPoints()
			mk.tick:SetPoint("CENTER", bar, "LEFT", x, 0)
			mk.tick:SetColorTexture(c[1], c[2], c[3], reached and 0.95 or 0.5)
			mk.tick:SetShown(i == nextIndex and at < max)
			mk:ClearAllPoints()
			mk:SetPoint("TOP", bar, "BOTTOMLEFT", x, -3)
			B:SetTierTexture(mk.icon, tier)
			if mk.icon.SetDesaturated then mk.icon:SetDesaturated(not reached) end
			mk.icon:SetAlpha(reached and 1 or 0.55)
			mk.ring:SetVertexColor(reached and c[1] or 0.3, reached and c[2] or 0.3, reached and c[3] or 0.3)
			mk:SetShown(i == nextIndex)
			if i == nextIndex then shown = shown + 1 end
		end
		for i = #list + 1, #self.marks do self.marks[i]:Hide() self.marks[i].tick:Hide() end
		-- the lines under the bar close up when no milestone icons are left
		if firstText then
			firstText:ClearAllPoints()
			firstText:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, shown > 0 and -28 or -10)
			firstText:SetPoint("RIGHT", detail.top, "RIGHT", -20, 0)
		end
	end
	tierBar.bar:HookScript("OnSizeChanged", function()
		if tierBar.markList then tierBar:SetMarkers(tierBar.markList, tierBar.markKills, tierBar.markMax) end
	end)
	tierBar:SetPoint("TOPLEFT", subText, "BOTTOMLEFT", 14 - NAME_X, -14)
	tierBar:SetPoint("RIGHT", detail.top, "RIGHT", -72, 0)
	firstText = detail.top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	firstText:SetPoint("TOPLEFT", tierBar, "BOTTOMLEFT", 0, -28) -- below the tier markers
	firstText:SetPoint("RIGHT", detail.top, "RIGHT", -20, 0)

	-- a waypoint (the game's map pin and arrow) on the spot of the last kill
	-- the game's own map pin (the user waypoint's diamond), else the skull
	local pinIcon = W.PinMarkup(18)
	killPin = W.Button(detail.top, pinIcon .. " " .. L["Pin last kill"], 150, function(self)
		local k = self.rec and self.rec.lastKill
		if type(k) == "table" and k.map then W.Waypoint(k.map, k.x, k.y, (self.rec.name or "?") .. " - " .. L["last kill"]) end
	end)
	killPin:SetPoint("TOPLEFT", firstText, "BOTTOMLEFT", 0, -10)
	killPin:SetScript("OnEnter", function(self)
		local k = self.rec and self.rec.lastKill
		if type(k) ~= "table" or not k.map then return end
		local zone = ns.Store:Get("zone", k.map)
		local name = zone and zone.name
		if not name and C_Map and C_Map.GetMapInfo then
			local ok, info = pcall(C_Map.GetMapInfo, k.map)
			name = ok and info and info.name
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L["Pin last kill"], 1, 0.82, 0)
		GameTooltip:AddLine(("%s  (%.1f, %.1f)"):format(name or "?", k.x, k.y), 1, 1, 1)
		GameTooltip:AddLine(ns.AgoText(k.t), 0.7, 0.7, 0.7)
		GameTooltip:AddLine(L["Sets the game's map pin and arrow there."], 0.6, 0.8, 1, true)
		GameTooltip:Show()
	end)
	killPin:SetScript("OnLeave", GameTooltip_Hide)
	killPin:Hide()
	firstText:SetJustifyH("LEFT")

	-- the research tier as a large badge: its icon in a ring of the tier's colour (a glow when
	-- Mastered); hover for the tier's name and what it reveals
	local BADGE = 48
	badge = W.Portrait(detail.top, BADGE):SetThin()
	badge:SetPoint("TOPRIGHT", detail.top, "TOPRIGHT", -10, -8)
	-- Master Hunter and up: a soft glow in the tier's colour that breathes, behind a quieter ring
	badge.glow = badge:CreateTexture(nil, "BACKGROUND", nil, -1)
	badge.glow:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
	badge.glow:SetBlendMode("ADD")
	badge.glow:SetPoint("CENTER")
	badge.glow:SetSize(BADGE * 1.7, BADGE * 1.7)
	badge.pulse = 0
	badge:SetScript("OnUpdate", function(self, elapsed)
		if not self.glow:IsShown() then return end
		self.pulse = self.pulse + elapsed
		local p = 0.5 + 0.5 * math.sin(self.pulse * 2.2)
		self.glow:SetAlpha(0.22 + 0.33 * p)
		local size = BADGE * (1.6 + 0.15 * p)
		self.glow:SetSize(size, size)
	end)
	-- Fought shows the creature's face with the attack sword in the corner, as the Quest Targeter
	badge.corner = badge:CreateTexture(nil, "OVERLAY")
	badge.corner:SetSize(16, 16)
	badge.corner:SetPoint("BOTTOMRIGHT", 3, -3)
	badge.corner:SetTexture(B.ATTACK_ICON)
	badge:EnableMouse(true)
	function badge:SetTier(tier, need, npc, rec)
		self.tier, self.need = tier, need
		local c = B.TIER_COLORS[tier]
		if tier >= 4 then
			-- the ring goes quiet (half its colour, half bronze); the glow carries the tier
			self:SetRing(c[1] * 0.45 + 0.62 * 0.55, c[2] * 0.45 + 0.5 * 0.55, c[3] * 0.45 + 0.24 * 0.55)
		else
			self:SetRing(c[1], c[2], c[3])
		end
		B:SetTierTexture(self.art, tier)
		self.corner:Hide()
		self.glow:SetVertexColor(c[1], c[2], c[3])
		self.glow:SetShown(tier >= 4)
		self:Show()
	end
	badge:SetScript("OnEnter", function(self)
		if not self.tier then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(B:TierMarkup(self.tier, 20) .. " " .. B:TierText(self.tier))
		GameTooltip:AddLine(B.TIER_HINTS[self.tier], 1, 1, 1, true)
		if self.need and B.TIERS[self.tier + 1] then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(B:TierMarkup(self.tier + 1, 14) .. " " .. (L["%d more kills to %s"]):format(self.need, B.TIERS[self.tier + 1]), 0.7, 0.7, 0.7)
		end
		GameTooltip:Show()
	end)
	badge:SetScript("OnLeave", GameTooltip_Hide)
	badge:Hide()

	Show(nil)
end

function page:Refresh()
	if not list then return end
	local rows, total, listed = Collect()
	local keep
	for _, r in ipairs(rows) do if r.npc and r.npc == shown then keep = r end end
	list:SetData(rows)
	list:Select(keep)
	countText:SetText((L["%d of %d"]):format(listed or #rows, total))
	if shown then Show(shown, true) end
end

-- item names arrive from the server a moment after they're first asked for
ns:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
	if (waitingItems or W.waitingItems) and shown and ns.UI:IsShown() and ns.UI:Current() == "bestiary" then
		waitingItems = false
		W.waitingItems = false
		C_Timer.After(0.2, function() if shown then Show(shown, true) end end)
	end
end)

ns:On("RESET", function() shown = nil if list then list:Select(nil) Show(nil) end end)

-- open the Bestiary on one creature
-- (0.68.0) a creature's detail blocks (General, Health, Abilities, Defenses, Loot, Where ...), for
-- other pages to show (the Dungeons page splits them into its boss tabs)
function page:CreatureBlocks(npc)
	local rec = npc and ns.Store:Get("creature", npc)
	if not rec then return nil end
	local ok, b = pcall(Describe, npc, rec)
	return ok and b or nil
end

function page:ShowCreature(npc)
	ns.UI:Open("bestiary")
	shown = npc
	self:Refresh()
end

-- /aa bestiary <name>: open the page on a creature
function page:Find(text)
	text = (text or ""):lower()
	for npc, rec in pairs(ns.Store:Shown("creature")) do
		if (rec.name or ""):lower() == text then return npc end
	end
end

ns.UI:RegisterPage(page)
