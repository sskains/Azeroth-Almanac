-- Milestones: built only from your own discoveries ("First elite", "100 creatures discovered",
-- "10 creatures Mastered"). No totals or percentages: a milestone is a count you reached, never a
-- share of everything there is. Earned once for the account, with the character and the date;
-- each new one gets a toast and a journal entry. Milestones already met when this first runs are
-- recorded quietly.
-- db.milestones[id] = { t = time, c = character key, quiet = true when recorded on first run }

local _, ns = ...
local L = ns.L
local M = ns:NewModule("Milestones")

ns.sessionStart = time()

local ICON = {
	creature = { "INV_Misc_Head_Dragon_01", "Ability_Hunter_Pet_Wolf" },
	mastered = { "Spell_Holy_ChampionsBond", "INV_Misc_Book_11" },
	kills = { "Ability_DualWield", "INV_Sword_04" },
	zone = { "INV_Misc_Map02", "INV_Scroll_03" },
	subzone = { "INV_Misc_Map_01", "INV_Misc_Map02" },
	instance = { "INV_Misc_Key_14", "INV_Misc_Key_03" },
	item = { "INV_Misc_Bag_08", "INV_Chest_Chain_05" },
	rare = { "INV_Misc_Gem_Sapphire_01", "INV_Misc_Gem_01" },
	epic = { "INV_Misc_Gem_Amethyst_01", "INV_Misc_Gem_01" },
	quest = { "INV_Misc_Note_01", "INV_Letter_15" },
	merchant = { "INV_Misc_Coin_02", "INV_Misc_Coin_01" },
	trainer = { "Interface\\AddOns\\AzerothAlmanac\\Media\\Icon_Training", "INV_Misc_Book_08", "INV_Scroll_04" }, -- (0.69.1: the painted lectern)
	townsfolk = { 8197123, "INV_Misc_Spyglass_03", "INV_Misc_Head_Human_01" },
	flight = { "Ability_Mount_Gryphon_01", "INV_Misc_Map_01" },
	herb = { 133939, "Trade_Herbalism", "INV_Misc_Herb_07" },
	ore = { "Trade_Mining", "INV_Ore_Copper_01" },
	fish = { "Trade_Fishing", "INV_Misc_Fish_02" },
	skin = { "INV_Misc_Pelt_Wolf_01", "INV_Misc_LeatherScrap_03" },
	chars = { "INV_Misc_GroupNeedMore", "INV_Misc_Head_Human_01" },
	elite = { "Ability_Warrior_BattleShout", "INV_Misc_Head_Dragon_01" },
	rarecreature = { "Ability_Hunter_SniperShot", "INV_Misc_Spyglass_03" },
	boss = { "INV_Misc_Bone_HumanSkull_01", "Ability_Warrior_Rampage" },
}

-- counts the milestones read: account-wide, or one character's (records they have met). One pass
-- over each kind (0.64.0: was a pass per count)
function M:Stats(char)
	local s = {}
	local function Mine(rec) return not char or (rec.c and rec.c[char]) end
	for _, kind in ipairs({ "zone", "subzone", "instance", "merchant", "trainer", "townsfolk", "flight", "node", "fishing" }) do
		local n = 0
		for _, rec in pairs(ns.Store:All(kind)) do if Mine(rec) then n = n + 1 end end
		s[kind] = n
	end
	-- creatures: how many, their tiers, the elites, rares and bosses, the kills, all at once
	-- (a tier from the account's kills, or that character's own: never from whichever the Almanac
	-- happens to be showing)
	local B = ns.Bestiary
	local c = { creature = 0, mastered = 0, studied = 0, elite = 0, rarecreature = 0, boss = 0, kills = 0 }
	for _, r in pairs(ns.Store:All("creature")) do
		if Mine(r) then
			local k
			if char then k = r.kc and r.kc[char] or 0 else k = r.kills or 0 end
			c.creature = c.creature + 1
			c.kills = c.kills + k
			if B and B.Kills then
				local t = B:Kills(r)
				if k >= t.mastered then c.mastered = c.mastered + 1 end
				if k >= t.studied then c.studied = c.studied + 1 end
			end
			if r.class == "elite" or r.class == "rareelite" or r.class == "worldboss" then c.elite = c.elite + 1 end
			if r.class == "rare" or r.class == "rareelite" then c.rarecreature = c.rarecreature + 1 end
			if (r.boss or r.class == "worldboss") and k > 0 then c.boss = c.boss + 1 end
		end
	end
	for k, v in pairs(c) do s[k] = v end
	local items, rare, epic = 0, 0, 0
	for _, r in pairs(ns.Store:All("item")) do
		if Mine(r) then
			items = items + 1
			if (r.q or 0) >= 3 then rare = rare + 1 end
			if (r.q or 0) >= 4 then epic = epic + 1 end
		end
	end
	s.item, s.rare, s.epic = items, rare, epic
	-- quests done: by any character, or by this one
	local done = {}
	for key, c in pairs(ns.db.chars or {}) do
		if not char or key == char then
			for qid, st in pairs(c.q or {}) do if type(st) == "table" and st.s == "d" then done[qid] = true end end
		end
	end
	s.quest = 0
	for _ in pairs(done) do s.quest = s.quest + 1 end
	local t = ns.Gathering and ns.Gathering:Totals(char) or {}
	s.herb, s.ore, s.fish, s.skin = t.herb or 0, t.ore or 0, t.fish or 0, t.skin or 0
	s.chars = 0
	for _ in pairs(ns.db.chars or {}) do s.chars = s.chars + 1 end
	return s
end

---------------------------------------------------------------------------
-- The milestones
---------------------------------------------------------------------------

M.list = {}
M.byId = {}
local function Add(id, stat, need, title, text, tier)
	local def = { id = id, stat = stat, need = need, title = title, text = text, icon = ICON[stat], tier = tier or 4 }
	M.list[#M.list + 1] = def
	M.byId[id] = def
end

local function Series(stat, steps, title, text)
	-- toast tier: the first step uncommon, the last legendary, the ones between spread across
	for i, n in ipairs(steps) do
		local tier = #steps == 1 and 3 or (2 + math.floor((i - 1) / (#steps - 1) * 3 + 0.5))
		Add(stat .. n, stat, n, (title):format(n), (text):format(n), tier)
	end
end

-- firsts
Add("elite1", "elite", 1, L["First elite"], L["Met an elite creature."])
Add("rarecreature1", "rarecreature", 1, L["Something rare"], L["Met a rare creature."])
Add("boss1", "boss", 1, L["Bossfall"], L["Slew a boss."])
Add("mastered1", "mastered", 1, L["First Master Hunter"], L["A creature reached Master Hunter: everything about it is known."])
Add("instance1", "instance", 1, L["Into the depths"], L["Found a dungeon."])
Add("flight1", "flight", 1, L["Wings"], L["Learned a flight path."])
Add("epic1", "epic", 1, L["Epic find"], L["Came across an epic item."])
Add("fish1", "fish", 1, L["First catch"], L["Caught something while fishing."])
Add("herb1", "herb", 1, L["Green fingers"], L["Gathered a herb."])
Add("ore1", "ore", 1, L["Strike the earth"], L["Mined a vein."])
Add("skin1", "skin", 1, L["First pelt"], L["Skinned a creature."])
Add("chars2", "chars", 2, L["A second life"], L["A second character joined the Almanac."], 3)
-- counts
Series("creature", { 10, 25, 50, 100, 250, 500, 1000 }, L["%d creatures"], L["Discovered %d kinds of creature."])
Series("mastered", { 5, 10, 25, 50, 100 }, L["%d Master Hunter creatures"], L["%d kinds of creature at Master Hunter."])
Series("kills", { 100, 500, 1000, 5000, 10000 }, L["%d kills"], L["Defeated %d creatures."])
Series("elite", { 10, 50 }, L["%d elites"], L["Met %d kinds of elite creature."])
Series("rarecreature", { 5, 20 }, L["%d rares"], L["Met %d rare creatures."])
Series("zone", { 5, 10, 20, 30, 40 }, L["%d zones"], L["Discovered %d zones."])
Series("subzone", { 25, 50, 100, 200, 400 }, L["%d places"], L["Discovered %d places within zones."])
Series("instance", { 5, 10, 20 }, L["%d dungeons"], L["Found %d dungeons and raids."])
Series("item", { 50, 100, 250, 500, 1000, 2500 }, L["%d items"], L["Came across %d different items."])
Series("rare", { 10, 25, 50, 100 }, L["%d rare items"], L["Came across %d rare or better items."])
Series("quest", { 10, 25, 50, 100, 250, 500 }, L["%d quests done"], L["Completed %d different quests."])
Series("merchant", { 10, 25, 50, 100 }, L["%d merchants"], L["Visited %d merchants."])
Series("trainer", { 5, 10, 25 }, L["%d trainers"], L["Trained with %d trainers."])
Series("townsfolk", { 25, 50, 100, 200 }, L["%d people"], L["Met %d people."])
Series("flight", { 5, 10, 20, 30 }, L["%d flight paths"], L["Learned %d flight paths."])
Series("herb", { 50, 100, 250, 500, 1000 }, L["%d herbs gathered"], L["Gathered herbs %d times."])
Series("ore", { 50, 100, 250, 500, 1000 }, L["%d veins mined"], L["Mined %d times."])
Series("fish", { 50, 100, 250, 500, 1000 }, L["%d catches"], L["Caught %d things while fishing."])
Series("skin", { 50, 100, 250, 500 }, L["%d pelts"], L["Skinned %d creatures."])
Series("chars", { 5, 10 }, L["%d characters"], L["%d characters share this Almanac."])

---------------------------------------------------------------------------
-- Earning them
---------------------------------------------------------------------------

function M:Earned(id)
	return ns.db and ns.db.milestones and ns.db.milestones[id]
end

-- the account's milestones, and (0.63.0) each character's own: in a character-only Almanac, a
-- character reaching one is told so even when the account reached it long ago
function M:Check()
	if not ns.db then return end
	ns.db.milestones = ns.db.milestones or {}
	local where = ns.Where()
	local told = {}
	local function Pass(got, s, first, mine)
		for _, def in ipairs(self.list) do
			if not got[def.id] and (s[def.stat] or 0) >= def.need then
				got[def.id] = { t = time(), c = ns.CharKey(), quiet = first or nil }
				if not first and not told[def.id] then
					told[def.id] = true
					ns.Store:AddJournal("milestone", def.id, def.title, where)
					ns:Fire("TOAST", "milestone", mine and L["Milestone reached (this character)"] or L["Milestone reached"], def.title,
						ns.Widgets and ns.Widgets.FindIcon(def.icon) or nil, def.tier)
				end
			end
		end
	end
	local me = ns.ScopeChar()
	local c = me and ns.db.chars and ns.db.chars[me]
	if c then
		c.milestones = c.milestones or {}
		Pass(c.milestones, self:Stats(me), not c.milestonesInit, true)
		c.milestonesInit = true
	end
	Pass(ns.db.milestones, self:Stats(), not ns.db.milestonesInit, false)
	ns.db.milestonesInit = true
end

local pending = false
local function Later()
	if pending or not ns.db then return end
	pending = true
	C_Timer.After(10, function() -- every change asks; the check runs at most every 10 s
		pending = false
		ns.doing = "checking milestones"
		local ok, err = pcall(M.Check, M)
		if not ok then ns.Debug("milestones: " .. tostring(err)) end
		ns.doing = "idle"
	end)
end
ns:On("CHANGED", Later)
ns:On("RESET", function() if ns.db then ns.db.milestones, ns.db.milestonesInit = nil, nil end end)
ns:RegisterEvent("PLAYER_ENTERING_WORLD", Later)

-- earned milestones, newest first: { { def, t, c, quiet } }; char: only those that character earned
function M:EarnedList(char)
	local out = {}
	-- (a character's own list once it has one; before that, the account's that it earned)
	local own = char and ns.db and ns.db.chars and ns.db.chars[char] and ns.db.chars[char].milestones
	for id, e in pairs(own or (ns.db and ns.db.milestones) or {}) do
		local def = self.byId[id]
		if def and (own or not char or e.c == char) then out[#out + 1] = { def = def, t = e.t, c = char or e.c, quiet = e.quiet } end
	end
	table.sort(out, function(a, b)
		if a.t ~= b.t then return a.t > b.t end
		return a.def.need > b.def.need
	end)
	return out
end
