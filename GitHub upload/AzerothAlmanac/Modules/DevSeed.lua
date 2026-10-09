-- DEVELOPMENT ONLY (0.68.0): fills your Almanac with every dungeon and raid, their bosses (at assorted
-- kill counts so every research tier shows; 0.68.2: the map places them from the records), boss loot and runs, to test
-- the Dungeons page. Everything it adds is marked `seeded` and comes out again with "clear"; nothing
-- you recorded yourself is changed. Remove with this file, its .toc line and "seeddungeons" in Core.lua.
--   /aa seeddungeons         (with /aa debug on) seed
--   /aa seeddungeons clear   take every seeded record out again

local _, ns = ...
local L = ns.L
local Seed = ns:NewModule("DevSeed")

local TYPES = { "Beast", "Dragonkin", "Demon", "Elemental", "Giant", "Undead", "Humanoid", "Critter", "Mechanical" }
local KILLS = { 3, 10, 40, 5, 50, 200, 12, 3 } -- (per boss in turn: 0.68.3, every one Mastered or beyond, so all its facts show)

local function BossName(npc)
	local B = ns.Bestiary
	if not (npc and B and B.NameFromGuid) then return nil end
	-- (the game names a creature from a unit link only when it knows it; a few GUID shapes are tried)
	for _, fmt in ipairs({ "Creature-0-0-0-0-%d-0000000000", "Creature-0-4615-0-0-%d-0000000001", "Creature-0-1-1-1-%d-0000000001" }) do
		local name = B.NameFromGuid(fmt:format(npc))
		if name then return name end
	end
end

-- (0.68.3) a boss's creature record as if you'd fought it `kills` times: everything the Creatures page
-- and the dungeon's Abilities / Loot / Other tabs read (health samples, abilities that hit you with
-- their damage, a debuff, casts, every drop with counts, money, skinning). Numbers are made up from
-- the Classic records so they look right; nothing is from a real fight.
local RANK_CLASS = { [0] = "normal", [1] = "elite", [2] = "rareelite", [3] = "worldboss", [4] = "rare" }
local function FillCreature(cr, npc, entry, kills, i)
	local c = ns.CreatureDB and ns.CreatureDB:Get(npc)
	cr.boss = entry.k ~= "r" or nil
	cr.class = c and RANK_CLASS[c.rank or 1] or (entry.k == "r" and "rareelite" or "elite")
	if cr.class == "normal" then cr.class = "elite" end
	cr.lo, cr.hi = c and c.lo, c and c.hi
	cr.type = c and TYPES[c.type or 0] or "Humanoid"
	cr.kills, cr.kc, cr.n = kills, { [ns.CharKey()] = kills }, kills + 2
	-- health: a few clean kills near its Classic health; every third one healed itself once
	local hp = c and c.hpHi or 2000
	local lvl = (cr.lo and cr.lo == cr.hi) and cr.lo or 0
	cr.hp = { [lvl] = { math.floor(hp * 0.97), hp, math.floor(hp * 1.02) } }
	cr.heal = (i % 3 == 0) and { 2, math.floor(hp * 0.15) } or nil
	-- abilities: its melee and every spell in its records, as hits on you
	local dmg = c and c.dmg or 60
	local fights = math.min(kills, 40)
	cr.ab = { [6603] = { f = fights, t = dmg * 12 * fights, hi = dmg * 18 } }
	cr.db, cr.casts = nil, nil
	for k, id in ipairs(c and c.spells or {}) do
		cr.ab[id] = { f = fights, t = dmg * (2 + k) * fights, hi = dmg * (3 + k) }
		if k == 1 then cr.db = { [id] = fights } end
	end
	if c and #c.spells > 0 then cr.casts = fights * #c.spells end
	-- loot: every item in its Classic table and the dungeon records, looted in about its share of kills
	cr.corpses, cr.loot = kills, {}
	local function Add(item, chance)
		if item and not cr.loot[item] then cr.loot[item] = math.max(1, math.floor(kills * math.min(1, math.max(0.05, chance / 100)) + 0.5)) end
	end
	for _, it in ipairs(ns.Dungeons and ns.Dungeons.Items(entry.items) or {}) do Add(it.id, it.chance > 0 and it.chance or 30) end
	for _, e in ipairs(c and c.loot or {}) do Add(e.item, e.chance) end
	if c and c.goldHi then cr.money = { kills, math.floor(((c.goldLo or 0) + c.goldHi) / 2) * kills } else cr.money = nil end
	-- skinning, when it can be skinned
	if c and #c.skin > 0 then
		cr.gathered, cr.gather = kills, {}
		for _, e in ipairs(c.skin) do cr.gather[e.item] = math.max(1, math.floor(kills * e.chance / 100 + 0.5)) end
	else
		cr.gathered, cr.gather = nil, nil
	end
end

function Seed:Run()
	if not ns.db then return end
	local now, me = time(), ns.CharKey()
	local insts = ns.Store:All("instance")
	local creatures = ns.Store:All("creature")
	local names = ns.DevSeedNames or {}
	local char = ns.db.chars[me]
	if char then char.runs = char.runs or {} end
	local done, bossesN = 0, 0
	for idx, d in ipairs(ns.DB and ns.DB.dungeon or {}) do
		-- (a dungeon with no instance ID in the records, one of WoW Forever's own: a made-up key)
		local id = d.id or (-1000 - idx)
		local rec = insts[id]
		if not rec then
			local age = (done + 1) * 86400
			rec = { name = d.name, type = d.raid and "raid" or "party", f = now - age * 3, b = me, n = 2 + done % 5, l = now - age,
				c = { [me] = now - age * 3 }, bosses = {}, best = 1200 + done * 180, seeded = true }
			insts[id] = rec
			done = done + 1
		end
		rec.bosses = rec.bosses or {}
		local runKills = {}
		for i, b in ipairs(d.bosses or {}) do
			if b.k ~= "t" and (b.npc or b.name) then
				local npc = b.npc or (-(700000 + math.abs(id) * 40 + i))
				local key = b.npc or ("n:" .. b.name)
				local old = rec.bosses[key] or rec.bosses[npc]
				-- (seeded ones are made again, so a newer seeder fills them further; your own are left alone)
				if not old or old.seeded then
					local kills = KILLS[(bossesN % #KILLS) + 1]
					bossesN = bossesN + 1
					local name = b.name or names[b.npc] or BossName(b.npc) or ("Boss #" .. tostring(b.npc))
					rec.bosses[key] = { name = name, npc = npc, kills = kills, wipes = (i % 3 == 0) and 1 or 0,
						first = { c = me, t = (rec.f or now) + i * 600 },
						lastKill = (rec.l or now) - i * 60, byEncounter = true, seeded = true }
					runKills[key] = kills
					local cr = creatures[npc]
					if not cr or cr.seeded then
						cr = { f = (rec.f or now) + i * 600, b = me, l = rec.l or now, c = { [me] = rec.f or now }, seeded = true,
							name = name, display = cr and cr.display }
						FillCreature(cr, npc, b, kills, i)
						creatures[npc] = cr
					end
				end
			end
		end
		if char and (not char.runs[id] or char.runs[id].seeded) then
			char.runs[id] = { n = rec.n or 1, last = rec.l or now, kills = runKills, time = (rec.best or 1800) * (rec.n or 1), seeded = true }
		end
	end
	if ns.Store.ClearShown then ns.Store:ClearShown() end
	ns:Fire("CHANGED")
	ns.Print(("seeded %d new dungeons and raids and %d bosses, each researched to Master Hunter or beyond, with abilities, loot, money and skinning filled in (/aa seeddungeons clear takes them out)."):format(done, bossesN))
end

function Seed:Clear()
	if not ns.db then return end
	local insts, creatures = ns.Store:All("instance"), ns.Store:All("creature")
	local n = 0
	for id, rec in pairs(insts) do
		if type(rec) == "table" then
			if rec.seeded then
				insts[id] = nil
				n = n + 1
			else
				for k, b in pairs(rec.bosses or {}) do if b.seeded then rec.bosses[k] = nil end end
			end
		end
	end
	for npc, c in pairs(creatures) do if type(c) == "table" and c.seeded then creatures[npc] = nil end end
	for _, c in pairs(ns.db.chars or {}) do
		for id, r in pairs(c.runs or {}) do if type(r) == "table" and r.seeded then c.runs[id] = nil end end
	end
	if ns.Store.ClearShown then ns.Store:ClearShown() end
	ns:Fire("CHANGED")
	ns.Print(("took out the test data: %d seeded dungeons and raids, with their bosses and runs."):format(n))
end

function Seed:Command(rest)
	if (rest or ""):lower() == "clear" then self:Clear() else self:Run() end
end
