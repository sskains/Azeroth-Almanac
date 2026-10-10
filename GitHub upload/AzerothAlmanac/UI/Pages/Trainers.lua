-- Recipes page (was Spells & Recipes until 0.69.0, #41): the recipes trainers and your profession
-- windows have shown you. (DESIGN 90) Cards (Show all, each profession, and the playing character's
-- Can learn now / Not yet / Learned) or List (profession, then the game's ranks by the skill each
-- recipe needs). A badge on each recipe's icon says whether you've learned it, can learn it now or
-- not yet; a learned recipe's name takes the game's skill-up colour. A profession's overview (your
-- characters' skill bars, trainers met, recipe items found) shows when you open its card.
-- Class spells, weapon skills and riding are on each trainer's own page in People (Training):
-- only what that trainer has shown you.

local _, ns = ...
local L = ns.L
local W = ns.Widgets

-- (the page key stays "trainers", so saved tabs and links keep working)
local page = { key = "trainers", title = L["Recipes"], icon = "Interface\\AddOns\\AzerothAlmanac\\Media\\Tab_Recipes", order = 9 }   -- (0.69.1: the painted recipe book)
local list, detail, countText, nameText, subText, iconTex
local filter = ""
local shown -- { kind = "spell", id } or { kind = "group", group }
local collapsed = {}

local COLOR = { now = "|cff40c040", later = "|cffe03030", known = "|cff999999", other = "|cffffffff" }
local STATUS = { now = L["Can learn now"], later = L["Not yet"], known = L["Learned"], other = "" }
local function TR() return ns.Trainers end

-- (DESIGN 90) the playing character's skill-up colour for a recipe they know, as the profession
-- window last showed it (orange, yellow, green, grey); nil when unknown
local DIFF = { [0] = "|cffff8040", [1] = "|cffffff00", [2] = "|cff40c040", [3] = "|cff808080" }
local function DiffColor(id)
	local c = ns.db and ns.db.chars[ns.CharKey()]
	local d = c and c.recipeDiff and c.recipeDiff[id]
	return d and DIFF[d] or nil
end

-- the learn state as a small badge on the icon: learned (a tick), can learn now (a gold plus), not
-- yet (a lock); nothing for a profession the character doesn't have
local BADGE = {
	known = "Interface\\RaidFrame\\ReadyCheck-Ready",
	now = "Interface\\PaperDollInfoFrame\\Character-Plus",
	later = "Interface\\LFGFrame\\UI-LFG-ICON-LOCK",
}

-- the profession's own icon
local PROF_ICON = {
	Alchemy = "Trade_Alchemy", Blacksmithing = "Trade_BlackSmithing", Enchanting = "Trade_Engraving", Engineering = "Trade_Engineering",
	Leatherworking = "Trade_LeatherWorking", Tailoring = "Trade_Tailoring", Cooking = "INV_Misc_Food_15", ["First Aid"] = "Spell_Holy_SealOfSacrifice",
	Mining = "Trade_Mining", Herbalism = "Trade_Herbalism", Skinning = "INV_Misc_Pelt_Wolf_01", Fishing = "Trade_Fishing",
	Jewelcrafting = "INV_Misc_Gem_01", Inscription = "INV_Inscription_Tradeskill01", Lockpicking = "Spell_Nature_MoonKey",
}
local SECONDARY = { Cooking = 1, ["First Aid"] = 2, Fishing = 3 }
-- (2026-10-10) each profession's painted banner (Media\Recipe_<Name>.tga, 512 x 128; ART_ASSETS.md
-- "Crafting profession cards") and the tint its card takes; a profession without one keeps the plain
-- tinted card with its icon
local PROF_ART = {
	Alchemy = "Recipe_Alchemy", Blacksmithing = "Recipe_Blacksmithing", Enchanting = "Recipe_Enchanting",
	Engineering = "Recipe_Engineering", Leatherworking = "Recipe_Leatherworking", Tailoring = "Recipe_Tailoring",
	Cooking = "Recipe_Cooking", ["First Aid"] = "Recipe_FirstAid",
	-- (the gathering professions' trainer spells, e.g. smelting: the Gathering page's paintings)
	Herbalism = "Gather_Herbalism", Mining = "Gather_Mining", Skinning = "Gather_Skinning", Fishing = "Gather_Fishing",
}
local PROF_TINT = {
	Alchemy = { 0.55, 0.4, 0.8 }, Blacksmithing = { 0.9, 0.45, 0.25 }, Enchanting = { 0.6, 0.45, 0.95 },
	Engineering = { 0.75, 0.6, 0.35 }, Leatherworking = { 0.75, 0.55, 0.35 }, Tailoring = { 0.5, 0.6, 0.85 },
	Cooking = { 0.9, 0.65, 0.3 }, ["First Aid"] = { 0.85, 0.85, 0.8 },
	Herbalism = { 0.35, 0.7, 0.3 }, Mining = { 0.8, 0.52, 0.3 }, Skinning = { 0.65, 0.42, 0.25 }, Fishing = { 0.3, 0.58, 0.85 },
}
local PROF_H = 76
local function ProfIcon(group)
	local v = (group or ""):match("^skill:(.*)$")
	return W.FindIcon({ PROF_ICON[v or ""] or "INV_Misc_Book_08", "INV_Misc_Book_08" })
end

-- the game's profession ranks, by the skill a recipe needs
local BRACKETS = {
	{ 74, L["Apprentice"] }, { 149, L["Journeyman"] }, { 224, L["Expert"] }, { 300, L["Artisan"] }, { 9999, L["Master"] },
}
local function Bracket(skill)
	if not skill then return #BRACKETS + 1, L["No skill shown"] end
	for i, b in ipairs(BRACKETS) do if skill <= b[1] then return i, b[2] end end
	return #BRACKETS, BRACKETS[#BRACKETS][2]
end

-- this character's count of an item (bags and bank): total, in the bank
local function Have(item)
	local INV = ns.QoL and ns.QoL.Inventory
	if not (INV and INV.WhoHas) then return 0, 0 end
	local me = ns.CharKey()
	for _, e in ipairs(INV:WhoHas(item) or {}) do
		if e.key == me then
			local parts = e.parts or {}
			return (parts.bags or 0) + (parts.bank or 0), parts.bank or 0
		end
	end
	return 0, 0
end

-- the recipe item that teaches a recipe (a "Recipe: ..." you've come across), or nil
local function RecipeItemFor(rec)
	local v = (rec.group or ""):match("^skill:(.*)$")
	if not v or not rec.name then return nil end
	for _, it in ipairs(TR():RecipeItems(v)) do
		local name = it.rec.name or (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(it.id))
		local spell = type(name) == "string" and name:match("^[^:]+:%s*(.+)$")
		if spell == rec.name then return it.id end
	end
end

local function SpellIcon(id, rec)
	if rec and rec.icon then return rec.icon end
	if C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, id)
		if ok and type(info) == "table" then return info.iconID end
	end
	return W.FindIcon({ "INV_Misc_QuestionMark" })
end

local function Place(t)
	return (t.sub and t.sub ~= "" and t.sub ~= t.zone) and (t.sub .. ", " .. (t.zone or "?")) or (t.zone or "?")
end

local function TrainerSlot(npc, t, cost)
	local e = { name = t.name or "?", icon = W.FindIcon({ "INV_Misc_Book_08", "INV_Scroll_04" }),
		note = (cost and (cost > 0 and (ns.MoneyText(cost) .. "  ") or (L["free"] .. "  ")) or "") .. Place(t) }
	if t.map and t.x then
		e.tip = (t.title and ("<" .. t.title .. ">\n") or "") .. L["Click to set a waypoint here."]
		e.onClick = function() W.Waypoint(t.map, t.x, t.y, t.name) end
	end
	return e
end

local function ItemSlot(id, n)
	local known = ns.Store:Get("item", id)
	return { item = id, count = n, note = n and n > 1 and ("x" .. n) or nil,
		extra = known and L["Click to open in Items."] or nil,
		onClick = known and function() local p = ns.UI:GetPage("items") if p and p.ShowItem then p:ShowItem(id) end end or nil }
end

local function DescribeSpell(id, rec)
	local b = {}
	local prof = TR():IsProfession(rec.group)
	b[#b + 1] = { "banner", L["General"] }
	b[#b + 1] = { "stat", prof and L["Profession"] or L["Class"], TR():GroupName(rec.group) }
	if rec.rank then b[#b + 1] = { "stat", L["Rank"], rec.rank } end
	if rec.lvl then b[#b + 1] = { "stat", L["Requires level"], tostring(rec.lvl) } end
	if rec.skill then b[#b + 1] = { "stat", L["Requires skill"], tostring(rec.skill) } end
	if rec.cost then b[#b + 1] = { "stat", L["Training cost"], rec.cost > 0 and ns.MoneyText(rec.cost) or L["free"] } end
	if rec.cat then b[#b + 1] = { "stat", L["Category"], rec.cat } end
	b[#b + 1] = { "stat", L["First seen"], ns.CharName(rec.b) .. ", " .. ns.DateText(rec.f) }
	-- (DESIGN 90) what the playing character can do with it now
	local me = ns.CharKey()
	if rec.reagents and TR():StatusFor(me, rec, id) == "known" then
		local can, fromBank, short = math.huge, false, nil
		for _, r in ipairs(rec.reagents) do
			local have, bank = Have(r[1])
			local times = math.floor(have / math.max(1, r[2] or 1))
			if times < can then can = times end
			if bank > 0 then fromBank = true end
			if have < (r[2] or 1) and not short then short = { r[1], (r[2] or 1) - have } end
		end
		if can == math.huge then can = 0 end
		local text = can > 0 and (tostring(can) .. (fromBank and ("  |cff999999" .. L["(some in the bank)"] .. "|r") or "")) or ("|cffff6060" .. L["not yet"] .. "|r")
		if can == 0 and short then
			local n = select(1, (C_Item and C_Item.GetItemInfo or GetItemInfo)(short[1]))
			text = text .. "  |cff999999" .. (L["needs %d more %s"]):format(short[2], n or L["reagents"]) .. "|r"
		end
		b[#b + 1] = { "stat", L["Can make now"], text }
	end
	-- cost and price, when auction scans know them
	local CR = ns.Crafting or (ns.QoL and ns.QoL.Crafting)
	if rec.reagents and rec.made and CR and CR.PriceOf then
		local ok, r = pcall(CR.PriceOf, CR, rec.reagents, rec.made, rec.makes)
		if ok and r and r.cost and r.cost > 0 and #(r.missing or {}) == 0 then
			b[#b + 1] = { "stat", L["Costs to make"], ns.MoneyText(math.floor(r.cost)) }
			if r.value then b[#b + 1] = { "stat", L["Sells for"], ns.MoneyText(math.floor(r.value)) .. "  |cff999999" .. L["(auction, after the cut)"] .. "|r" } end
		end
	end

	-- the rank itself, as its tooltip shows it: cost, cast time, cooldown, range, then what it does
	local tip = TR():Tooltip(id, rec)
	if tip then
		b[#b + 1] = { "banner", rec.rank or L["Details"] }
		for _, ln in ipairs(tip) do
			local left = "|cff" .. (ln.lc or "ffffff") .. ln.l .. "|r"
			if ln.r then
				b[#b + 1] = { "stat", left, "|cff" .. (ln.rc or "ffffff") .. ln.r .. "|r" }
			else
				b[#b + 1] = { "body", "|cff" .. (ln.lc or "ffd100") .. ln.l .. "|r" }
			end
		end
	end

	-- every rank of it that trainers have shown you, with what each one does
	local ranks = {}
	for oid, o in pairs(ns.Store:Shown("spell")) do
		if o.name == rec.name and o.group == rec.group then ranks[#ranks + 1] = { id = oid, rec = o } end
	end
	if #ranks > 1 then
		table.sort(ranks, function(x, y)
			if (x.rec.lvl or 0) ~= (y.rec.lvl or 0) then return (x.rec.lvl or 0) < (y.rec.lvl or 0) end
			return (tonumber((x.rec.rank or ""):match("%d+")) or 0) < (tonumber((y.rec.rank or ""):match("%d+")) or 0)
		end)
		b[#b + 1] = { "banner", (L["All ranks (%d)"]):format(#ranks) }
		local me = ns.CharKey()
		for _, r in ipairs(ranks) do
			local st = TR():StatusFor(me, r.rec, r.id)
			local label = (r.id == id and "|cffffffff" or COLOR[st]) .. (r.rec.rank or r.rec.name or "?") .. "|r"
				.. (r.rec.lvl and ("  |cff999999" .. (L["level %d"]):format(r.rec.lvl) .. "|r") or "")
			b[#b + 1] = { "stat", label, r.rec.cost and (r.rec.cost > 0 and ns.MoneyText(r.rec.cost) or L["free"]) or "" }
			local desc = TR():Description(TR():Tooltip(r.id, r.rec))
			if desc ~= "" then b[#b + 1] = { "small", "      " .. desc } end
		end
	end

	if rec.made then
		b[#b + 1] = { "banner", L["Makes"] }
		b[#b + 1] = { "slots", { ItemSlot(rec.made, rec.makes) } }
	end
	if rec.reagents then
		b[#b + 1] = { "banner", L["Reagents"] }
		local s = {}
		for _, r in ipairs(rec.reagents) do s[#s + 1] = ItemSlot(r[1], r[2]) end
		b[#b + 1] = { "slots", s }
	end

	local teachers = {}
	for npc, cost in pairs(rec.trainers or {}) do
		local t = ns.Store:Get("trainer", npc)
		if t then teachers[#teachers + 1] = TrainerSlot(npc, t, cost) end
	end
	if #teachers > 0 then
		table.sort(teachers, function(x, y) return x.name < y.name end)
		b[#b + 1] = { "banner", L["Taught by"] }
		b[#b + 1] = { "slots", teachers }
	end

	-- where else to learn it: merchants you've met who sell its recipe item
	local recipeItem = RecipeItemFor(rec)
	if recipeItem then
		local sellers = {}
		for _, s in ipairs(ns.Merchants and ns.Merchants.Selling and ns.Merchants:Selling(recipeItem) or {}) do
			local t = s.rec
			local e = { name = t.name or "?", icon = W.FindIcon({ "INV_Misc_Coin_02", "INV_Misc_Bag_08" }),
				note = ((s.e and s.e.price and s.e.price > 0) and (ns.MoneyText(s.e.price) .. "  ") or "") .. Place(t) }
			if t.map and t.x then e.tip = L["Click to set a waypoint here."] e.onClick = function() W.Waypoint(t.map, t.x, t.y, t.name) end end
			sellers[#sellers + 1] = e
		end
		b[#b + 1] = { "banner", L["The recipe item"] }
		b[#b + 1] = { "slots", { ItemSlot(recipeItem) } }
		if #sellers > 0 then
			b[#b + 1] = { "banner", (L["Sold by (%d)"]):format(#sellers) }
			b[#b + 1] = { "slots", sellers }
		end
	end
	-- crafted gear: who it would be an upgrade for
	if rec.made and ns.Upgrades and ns.Upgrades.Lines then
		local ok, lines = pcall(ns.Upgrades.Lines, ns.Upgrades, rec.made)
		if ok and lines and #lines > 0 then
			b[#b + 1] = { "banner", L["Upgrade for"] }
			for _, ln in ipairs(lines) do
				b[#b + 1] = { "small", ("|cff%02x%02x%02x"):format((ln[2] or 1) * 255, (ln[3] or 1) * 255, (ln[4] or 1) * 255) .. ln[1] .. "|r" }
			end
		end
	end

	local rows = {}
	for key in pairs(ns.db.chars) do
		local st = TR():StatusFor(key, rec, id)
		if st ~= "other" then
			local c = ns.db.chars[key]
			local text = STATUS[st]
			if st == "known" then
				local t = c.spells and c.spells[id]
				if t and t > 0 then text = (L["Learned %s"]):format(ns.DateText(t)) end
			elseif st == "later" then
				local need = {}
				if rec.lvl and rec.lvl > (c.level or 1) then need[#need + 1] = (L["level %d"]):format(rec.lvl) end
				if prof and rec.skill then
					local s = c.skills and c.skills[(rec.group or ""):match("^skill:(.*)$") or ""]
					if s and rec.skill > (s.rank or 0) then need[#need + 1] = (L["skill %d"]):format(rec.skill) end
				end
				if #need > 0 then text = (L["Needs %s"]):format(table.concat(need, ", ")) end
			end
			rows[#rows + 1] = { sortKey = ns.CharName(key, true), "stat", ns.CharName(key), COLOR[st] .. text .. "|r" }
		end
	end
	if #rows > 0 then
		b[#b + 1] = { "banner", L["Your characters"] }
		table.sort(rows, function(x, y) return x.sortKey < y.sortKey end) -- (by name, not by colour code)
		for _, r in ipairs(rows) do b[#b + 1] = r end
	end
	return b
end

local function DescribeGroup(group)
	local b = {}
	local name = TR():GroupName(group)
	local prof = TR():IsProfession(group)
	local kind, v = group:match("^(%a+):(.*)$")

	-- your characters: the profession's own skill bar, or their level and spells learned
	local rows = {}
	for key, c in pairs(ns.db.chars) do
		local learned = 0
		for id in pairs(c.spells or {}) do
			local s = ns.Store:Get("spell", id)
			if s and s.group == group then learned = learned + 1 end
		end
		if prof then
			local s = c.skills and c.skills[v]
			if s then rows[#rows + 1] = { key = key, s = s, learned = learned } end
		elseif kind == "class" and c.classFile == v then
			rows[#rows + 1] = { key = key, learned = learned, level = c.level }
		end
	end
	-- (the character you're playing first)
	local me = ns.CharKey()
	table.sort(rows, function(x, y) if (x.key == me) ~= (y.key == me) then return x.key == me end return x.key < y.key end)
	if #rows > 0 then
		b[#b + 1] = { "banner", L["Your characters"] }
		for _, r in ipairs(rows) do
			if r.s then
				-- (0.69.0) the blue skills bar, as on the Creatures and Gathering pages and the Characters page;
				-- (2026-10-09) each character's name on its own line above the bar (it was cut to one letter
				-- in the bar's label column, so two characters' bars looked like one bar twice)
				b[#b + 1] = { "stat", ns.CharName(r.key), r.learned > 0 and (L["%s known"]):format(ns.N(r.learned, "recipe", "recipes"))
					or ("|cff999999" .. L["open their profession window to list their recipes"] .. "|r") }
				b[#b + 1] = { "skillbar", nil, r.s.rank or 0, math.max(1, r.s.max or 1),
					("%s %d / %d"):format(name, r.s.rank or 0, r.s.max or 0) }
			else
				b[#b + 1] = { "stat", ns.CharName(r.key), (L["level %d, %s learned"]):format(r.level or 0, ns.N(r.learned, "spell", "spells")) }
			end
		end
	end

	local trainers = {}
	for npc, t in pairs(ns.Store:Shown("trainer")) do
		if t.group == group then trainers[#trainers + 1] = TrainerSlot(npc, t) end
	end
	table.sort(trainers, function(x, y) return x.name < y.name end)
	if #trainers > 0 then
		b[#b + 1] = { "banner", (L["Trainers met (%d)"]):format(#trainers) }
		b[#b + 1] = { "slots", trainers }
	end

	if prof then
		local items = TR():RecipeItems(v)
		if #items > 0 then
			b[#b + 1] = { "banner", (L["Recipe items found (%d)"]):format(#items) }
			local s = {}
			for _, it in ipairs(items) do s[#s + 1] = ItemSlot(it.id) end
			b[#b + 1] = { "slots", s }
		end
	end
	if #b == 0 then b[#b + 1] = { "small", L["Visit a trainer to fill this in."] } end
	return b
end

-- a profession's own painting behind its pages; class trainers get the book's general card
local function Theme(group)
	local kind, v = (group or ""):match("^(%a+):(.*)$")
	if kind == "skill" and v then return { (v:gsub("%s", "")), "Blacksmithing" } end
	return { "Enchanting", "Blacksmithing" }
end

-- (DESIGN 90) the right side with nothing picked: what the playing character can learn now (the
-- training cost, the nearest trainer you've met who teaches it), recipes learned lately, and recipe
-- items this character carries but hasn't learned
local function Summary()
	local b = {}
	local me = ns.CharKey()
	local c = ns.db.chars[me] or {}
	local now, cost = {}, 0
	local teachers = {}
	for id, rec in pairs(ns.Store:Shown("spell")) do
		if TR():IsProfession(rec.group) and TR():StatusFor(me, rec, id) == "now" then
			now[#now + 1] = { id = id, rec = rec }
			local best
			for npc, t in pairs(rec.trainers or {}) do
				if not best or (t or 0) < best then best = t or 0 end
				teachers[npc] = true
			end
			cost = cost + (best or rec.cost or 0)
		end
	end
	table.sort(now, function(x, y) return (x.rec.skill or 0) < (y.rec.skill or 0) end)
	if #now > 0 then
		b[#b + 1] = { "banner", (L["You can learn now (%d)"]):format(#now) }
		if cost > 0 then b[#b + 1] = { "stat", L["Training cost"], ns.MoneyText(cost) } end
		-- the nearest: one in this zone, else on this continent, else any you've met
		local here = ns.Where and ns.Where() or {}
		local pick, score
		for npc in pairs(teachers) do
			local t = ns.Store:Get("trainer", npc)
			if t then
				local s = (t.map and t.map == here.map) and 3 or (t.zone and t.zone == here.zone) and 2 or 1
				if not score or s > score then pick, score = npc, s end
			end
		end
		local t = pick and ns.Store:Get("trainer", pick)
		if t then b[#b + 1] = { "slots", { TrainerSlot(pick, t) } } end
		local s = {}
		for i, e in ipairs(now) do
			if i > 12 then break end
			s[#s + 1] = { spell = e.id, icon = SpellIcon(e.id, e.rec), name = e.rec.name, note = e.rec.skill and ("|cff999999" .. TR():GroupName(e.rec.group) .. " " .. e.rec.skill .. "|r") or nil,
				onClick = function() page:ShowSpell(e.id) end }
		end
		b[#b + 1] = { "slots", s }
	end
	local lately = {}
	for id, t in pairs(c.spells or {}) do
		local rec = ns.Store:Get("spell", id)
		if rec and t > 0 and TR():IsProfession(rec.group) then lately[#lately + 1] = { id = id, rec = rec, t = t } end
	end
	table.sort(lately, function(x, y) return x.t > y.t end)
	if #lately > 0 then
		b[#b + 1] = { "banner", L["Learned lately"] }
		local s = {}
		for i, e in ipairs(lately) do
			if i > 8 then break end
			s[#s + 1] = { spell = e.id, icon = SpellIcon(e.id, e.rec), name = e.rec.name, note = "|cff999999" .. ns.DateText(e.t) .. "|r",
				onClick = function() page:ShowSpell(e.id) end }
		end
		b[#b + 1] = { "slots", s }
	end
	-- (a recipe item counts until one of your characters knows its recipe)
	local byName = {}
	for sid, sp in pairs(ns.Store:Shown("spell")) do if TR():IsProfession(sp.group) and sp.name then byName[sp.name] = sid end end
	local function Learned(itemID, rec)
		local name = rec.name or (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID))
		local sid = type(name) == "string" and byName[name:match("^[^:]+:%s*(.+)$") or ""]
		if not sid then return false end
		for _, ch in pairs(ns.db.chars) do if ch.spells and ch.spells[sid] then return true end end
		return false
	end
	local carried = {}
	for v in pairs(c.skills or {}) do
		for _, it in ipairs(TR():RecipeItems(v)) do
			if Have(it.id) > 0 and not Learned(it.id, it.rec) then carried[#carried + 1] = ItemSlot(it.id) end
		end
	end
	if #carried > 0 then
		b[#b + 1] = { "banner", L["Recipe items you carry, not yet learned"] }
		b[#b + 1] = { "slots", carried }
	end
	if #b == 0 then b[#b + 1] = { "small", L["Select a recipe, or open a profession's card."] } end
	return b
end

local function Show(sel, keep)
	shown = sel
	if sel then
		local g = sel.group or (sel.id and ns.Store:Get("spell", sel.id) and ns.Store:Get("spell", sel.id).group)
		detail:SetTheme(Theme(g))
	end
	if not sel then
		detail:SetTheme(Theme(nil))
		nameText:SetText(L["Recipes"])
		subText:SetText(ns.CharName(ns.CharKey(), true))
		iconTex:Hide()
		local ok, b = pcall(Summary)
		if ok and b then detail:SetBlocks(b, nil, keep) else detail:SetBlocks(nil, L["Select a recipe."]) end
		return
	end
	if sel.kind == "group" then
		nameText:SetText(TR():GroupName(sel.group))
		subText:SetText(TR():IsProfession(sel.group) and L["Profession"] or L["Trainer"])
		iconTex:Hide()
		detail:SetBlocks(DescribeGroup(sel.group), nil, keep)
		return
	end
	local rec = ns.Store:Get("spell", sel.id)
	if not rec then return Show(nil) end
	nameText:SetText(rec.name or "?")
	subText:SetText((rec.rank and (rec.rank .. "  ·  ") or "") .. TR():GroupName(rec.group))
	iconTex:SetTexture(SpellIcon(sel.id, rec))
	iconTex:Show()
	detail:SetBlocks(DescribeSpell(sel.id, rec), nil, keep)
end

---------------------------------------------------------------------------
-- List (DESIGN 90, agreed with Shannon 2026-10-09): Cards (Show all, the professions, and the
-- playing character's Can learn now / Not yet / Learned) or List (profession, then the game's
-- ranks by the skill a recipe needs, then the recipes). A card opens the list under "Recipes › ...".
---------------------------------------------------------------------------

local PAIR_H = 60
local MEDIA = "Interface\\AddOns\\AzerothAlmanac\\Media\\"
local view, crumb, cardFilter = "cards", nil, nil
local cardBar, backBtn, crumbText, cardsBtn, listBtn, searchBox
local foldedSections = {}

local function Win()
	local s = ns.db and ns.db.settings
	return s and s.window or {}
end

local function GroupOrder(group)
	local v = (group or ""):match("^skill:(.*)$") or group or ""
	return (SECONDARY[v] and ("2" .. SECONDARY[v]) or "1") .. v
end

local function NewText(n) return (n and n > 0) and ("  |cff1eff00+" .. n .. "|r") or "" end

local function Collect()
	local groups, total, n = {}, 0, 0
	local me = ns.CharKey()
	for id, rec in pairs(ns.Store:Shown("spell")) do
		local g = rec.group or "other:?"
		-- (class spells, weapon skills and riding: on their trainer's page in People)
		if TR():IsProfession(g) then
			total = total + 1
			local st = TR():StatusFor(me, rec, id)
			local hit = filter == "" or (rec.name or ""):lower():find(filter, 1, true)
			if hit and (not cardFilter or cardFilter(id, rec, st)) then
				groups[g] = groups[g] or {}
				table.insert(groups[g], { id = id, rec = rec, st = st })
				n = n + 1
			end
		end
	end
	-- (a profession you've met a trainer for shows even with nothing listed yet, in the full list)
	if not cardFilter and filter == "" then
		for _, t in pairs(ns.Store:Shown("trainer")) do
			if t.group and TR():IsProfession(t.group) then groups[t.group] = groups[t.group] or {} end
		end
	end
	-- (#38) recipes found since you last looked: their own group at the top
	local rows = {}
	if ns.New then
		local all = {}
		for _, items in pairs(groups) do for _, it in ipairs(items) do all[#all + 1] = it end end
		local new = ns.New:Split("trainers", all, function(it) return it.rec end, function(it) return it.id end)
		if #new > 0 then
			for g, items in pairs(groups) do
				local keep = {}
				for _, it in ipairs(items) do if not it.isNew then keep[#keep + 1] = it end end
				groups[g] = keep
			end
			rows[#rows + 1] = ns.New:Header(#new)
			if not collapsed.new then for _, it in ipairs(new) do rows[#rows + 1] = it end end
		end
	end
	local order = {}
	for g in pairs(groups) do order[#order + 1] = g end
	table.sort(order, function(a, b) return GroupOrder(a) < GroupOrder(b) end)
	for _, g in ipairs(order) do
		local items = groups[g]
		rows[#rows + 1] = { header = TR():GroupName(g), group = g, key = g, count = #items, depth = 0 }
		if not collapsed[g] then
			-- the game's ranks by the skill each recipe needs, lowest first
			local brackets = {}
			for _, it in ipairs(items) do
				local i, label = Bracket(it.rec.skill)
				brackets[i] = brackets[i] or { label = label, items = {} }
				table.insert(brackets[i].items, it)
			end
			for i = 1, #BRACKETS + 1 do
				local br = brackets[i]
				if br then
					local key = g .. "|" .. i
					rows[#rows + 1] = { header = br.label, group = g, key = key, count = #br.items, depth = 1 }
					if not collapsed[key] then
						table.sort(br.items, function(a, b)
							if (a.rec.skill or 0) ~= (b.rec.skill or 0) then return (a.rec.skill or 0) < (b.rec.skill or 0) end
							if (a.rec.lvl or 0) ~= (b.rec.lvl or 0) then return (a.rec.lvl or 0) < (b.rec.lvl or 0) end
							return (a.rec.name or "") < (b.rec.name or "")
						end)
						for _, it in ipairs(br.items) do rows[#rows + 1] = it end
					end
				end
			end
		end
	end
	return rows, n, total
end

-- the cards
local function Card(icon, name, count, tip, action, plain)
	return { icon = icon, name = name, plain = plain or name, count = count, tip = tip, action = action }
end

local function OpenCard(label, fn, group)
	cardFilter, crumb, view = fn, label, "list"
	filter = ""
	if searchBox then searchBox:SetText("") end
	Win().recipesView = view
	if group then shown = { kind = "group", group = group } end
	page:Refresh()
	if list and list.ScrollTop then list:ScrollTop() end
end

local function BackToCards()
	cardFilter, crumb, view = nil, nil, "cards"
	Win().recipesView = view
	page:Refresh()
	if list and list.ScrollTop then list:ScrollTop() end
end

local function CardRows()
	local rows = {}
	local me = ns.CharKey()
	local total, newAll = 0, 0
	local profs, mine = {}, { now = 0, later = 0, known = 0 }
	for id, rec in pairs(ns.Store:Shown("spell")) do
		local g = rec.group
		if TR():IsProfession(g) then
			total = total + 1
			local isNew = ns.New and ns.New:IsNew("trainers", rec) and 1 or 0
			newAll = newAll + isNew
			local p = profs[g] or { n = 0, new = 0 }
			profs[g] = p
			p.n, p.new = p.n + 1, p.new + isNew
			local st = TR():StatusFor(me, rec, id)
			if mine[st] then mine[st] = mine[st] + 1 end
		end
	end
	if total == 0 then return rows, 0 end
	local function Section(key, text)
		rows[#rows + 1] = { card = "section", header = text, key = key }
		return not foldedSections[key]
	end
	local function Pairs(cards)
		for i = 1, #cards, 2 do rows[#rows + 1] = { card = "pair", a = cards[i], b = cards[i + 1] } end
	end
	Pairs({ Card(MEDIA .. "Tab_Recipes", L["Show all"], tostring(total) .. NewText(newAll), L["Every recipe on the account"], function() OpenCard(L["All recipes"], nil) end) })

	if Section("s:prof", L["Professions"]) then
		local order = {}
		for g in pairs(profs) do order[#order + 1] = g end
		table.sort(order, function(a, b) return GroupOrder(a) < GroupOrder(b) end)
		for _, g in ipairs(order) do
			local p, v = profs[g], g:match("^skill:(.*)$")
			-- the best skill among your characters
			local best, bestKey, bestMax
			for key, c in pairs(ns.db.chars) do
				local s = c.skills and c.skills[v]
				if s and (not best or (s.rank or 0) > best) then best, bestKey, bestMax = s.rank or 0, key, s.max end
			end
			local count = tostring(p.n) .. NewText(p.new) .. (best and ("  |cff999999" .. best .. (bestMax and (" / " .. bestMax) or "") .. "|r") or "")
			local tip = best and (L["Best: %s, %d"]):format(ns.CharName(bestKey, true), best) or v
			-- (2026-10-10) a full-width painted banner per profession, like the Gathering cards
			rows[#rows + 1] = { card = "prof", group = g, name = v, count = count, tip = tip,
				action = function() OpenCard(v, function(_, rec) return rec.group == g end, g) end }
		end
	end

	-- the character you're playing: only their own professions count
	if mine.now + mine.later + mine.known > 0 and Section("s:me", (L["For %s"]):format(ns.CharName(me, true))) then
		local cards = {}
		local defs = {
			{ "now", L["Can learn now"], { "INV_Misc_Book_09", "INV_Misc_Book_08" }, L["Recipes you can learn at a trainer now"] },
			{ "later", L["Not yet"], { "INV_Misc_Book_04", "INV_Misc_Book_08" }, L["Recipes that need more skill or level"] },
			{ "known", L["Learned"], { "INV_Misc_Book_11", "INV_Misc_Book_08" }, L["Recipes you know"] },
		}
		for _, d in ipairs(defs) do
			if mine[d[1]] > 0 then
				local st = d[1]
				cards[#cards + 1] = Card(W.FindIcon(d[3]), d[2], tostring(mine[st]), d[4], function() OpenCard(d[2], function(_, _, s) return s == st end) end)
			end
		end
		Pairs(cards)
	end
	return rows, total
end

local function FillCardRow(row, r)
	row.icon:SetTexture(nil)
	row.text:SetText("")
	row.right:SetText("")
	if row.banner then row.banner:Hide() row.banner:SetSelected(false) end
	if r.card == "prof" then
		for _, c in ipairs(row.halves or {}) do c:Hide() end
		if row.badge then row.badge:Hide() end
		if ns.New then ns.New:MarkRow(row, false) end
		row.indent = 0
		row:SetHeader(false)
		if not W.FillZoneBanner then
			row.text:SetFontObject(GameFontNormalLarge)
			row.text:SetText(r.name)
			row.right:SetText(r.count)
			return
		end
		local tint = PROF_TINT[r.name] or { 0.6, 0.5, 0.35 }
		W.FillZoneBanner(row, { name = r.name, art = PROF_ART[r.name], icon = ProfIcon(r.group), tint = tint, top = 4,
			count = "|cffcccccc" .. r.count .. "|r", pill = { sign = ">", label = (L["Open %s"]):format(r.name), action = r.action } })
		for _, t in ipairs(row.banner.edges) do t:SetColorTexture(tint[1] * 0.75, tint[2] * 0.75, tint[3] * 0.75, 1) end
		return
	end
	if row.badge then row.badge:Hide() end
	if ns.New then ns.New:MarkRow(row, false) end
	for _, c in ipairs(row.halves or {}) do c:Hide() end
	if r.card == "section" then
		row.indent = 0
		row:SetHeader(true, foldedSections[r.key])
		row.text:SetText(r.header)
		return
	end
	row:SetHeader(false)
	local w = row:GetWidth()
	if not w or w < 50 then w = 300 end -- (before the first layout)
	for i, o in ipairs({ r.a, r.b }) do
		local c = W.PairCard(row, i)
		c:ClearAllPoints()
		c:SetPoint("TOPLEFT", row, "TOPLEFT", 4 + (i - 1) * (w / 2), -3)
		c:SetSize(w / 2 - 6, PAIR_H - 6)
		if o then W.FillPairCard(c, o, PAIR_H) else c:Hide() end
	end
end

local function PaintBar()
	if not cardBar then return end
	local inCard = view == "list" and crumb ~= nil
	backBtn:SetShown(inCard)
	crumbText:SetText(inCard and ("|cffffd100" .. L["Recipes"] .. "|r  |cff999999›|r  " .. crumb) or "")
	cardsBtn:SetActive(view == "cards")
	listBtn:SetActive(view ~= "cards")
end

local function FillRecipeRow(row, r)
	for _, c in ipairs(row.halves or {}) do c:Hide() end
	if row.banner then row.banner:Hide() row.banner:SetSelected(false) end
	row.icon:ClearAllPoints()
	if ns.New then ns.New:MarkRow(row, r.isNew, "trainers", r.newKey) end
	if not row.badge then
		row.badge = row:CreateTexture(nil, "OVERLAY", nil, 5)
		row.badge:SetSize(12, 12)
		row.badge:SetPoint("CENTER", row.icon, "BOTTOMRIGHT", -1, 2)
	end
	row.badge:Hide()
	if r.header then
		row.indent = (r.depth or 0) * 12
		row:SetHeader(true, collapsed[r.key])
		row.icon:SetPoint("LEFT", 4, 0)
		row.icon:SetTexture(nil)
		row.text:SetFontObject(r.depth == 1 and GameFontNormal or W.Font("GameFontNormalLarge", "GameFontNormal"))
		row.text:SetText(r.header)
		row.right:SetText(r.newHeader and "" or ("|cff999999" .. (r.count or "") .. "|r"))
		return
	end
	row.indent = 0
	row:SetHeader(false)
	row.icon:SetPoint("LEFT", 24, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.icon:SetTexture(SpellIcon(r.id, r.rec))
	row.text:SetFontObject(GameFontHighlight)
	-- the name in the game's skill-up colour where the profession window has shown it; white otherwise
	local color = (r.st == "known" and DiffColor(r.id)) or "|cffffffff"
	row.text:SetText(color .. (r.rec.name or "?") .. "|r" .. (r.rec.rank and ("  |cff999999" .. r.rec.rank .. "|r") or ""))
	local badge = BADGE[r.st]
	if badge then row.badge:SetTexture(badge) row.badge:Show() end
	local right = {}
	if r.rec.cat then right[#right + 1] = r.rec.cat end
	if r.rec.skill then right[#right + 1] = tostring(r.rec.skill) elseif r.rec.lvl then right[#right + 1] = "[" .. r.rec.lvl .. "]" end
	row.right:SetText("|cff999999" .. table.concat(right, "  ") .. "|r")
end

function page:Build(parent, header)
	view = Win().recipesView == "list" and "list" or "cards"
	local search = W.Search(header, 200, function(text)
		filter = text or ""
		-- (search looks through everything: the whole list, from the cards too)
		if filter ~= "" then cardFilter, crumb, view = nil, nil, "list" end
		page:Refresh()
	end)
	searchBox = search
	search:SetPoint("LEFT", header, "LEFT", 16, -2)
	countText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countText:SetPoint("RIGHT", header, "RIGHT", -12, -2)

	local left = W.Inset(parent)
	left:SetPoint("TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", 0, 0)
	left:SetWidth(320)
	-- Cards / List, and the way back from a card
	cardBar = CreateFrame("Frame", nil, left)
	cardBar:SetPoint("TOPLEFT", 4, -4)
	cardBar:SetPoint("TOPRIGHT", -4, -4)
	cardBar:SetHeight(26)
	backBtn = CreateFrame("Button", nil, cardBar)
	backBtn:SetSize(24, 24)
	backBtn:SetPoint("LEFT", 2, 0)
	backBtn.tex = backBtn:CreateTexture(nil, "ARTWORK")
	backBtn.tex:SetAllPoints()
	backBtn.tex:SetTexture(MEDIA .. "Back_Arrow")
	backBtn:SetHighlightTexture(MEDIA .. "Back_Arrow", "ADD")
	backBtn:SetScript("OnClick", function() BackToCards() end)
	backBtn:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT") GameTooltip:AddLine(L["Back to the cards"], 1, 0.82, 0) GameTooltip:Show() end)
	backBtn:SetScript("OnLeave", GameTooltip_Hide)
	crumbText = cardBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	crumbText:SetPoint("LEFT", backBtn, "RIGHT", 4, 0)
	crumbText:SetJustifyH("LEFT")
	crumbText:SetWordWrap(false)
	listBtn = W.ViewButton(cardBar, "View_List", L["List"], function() cardFilter, crumb, view = nil, nil, "list" Win().recipesView = view page:Refresh() end)
	listBtn:SetPoint("RIGHT", -2, 0)
	cardsBtn = W.ViewButton(cardBar, "View_Cards", L["Cards"], function() filter = "" search:SetText("") BackToCards() end)
	cardsBtn:SetPoint("RIGHT", listBtn, "LEFT", -4, 0)
	crumbText:SetPoint("RIGHT", cardsBtn, "LEFT", -6, 0)
	local listHolder = CreateFrame("Frame", nil, left)
	listHolder:SetPoint("TOPLEFT", 0, -30)
	listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
	list = W.List(listHolder, {
		collapse = { state = collapsed, key = function(r) return (r.newHeader and "new") or (r.header and not r.card and r.key) or nil end, refresh = function() page:Refresh() end },
		rowHeight = 24,
		heightOf = function(r) if r.card == "pair" then return PAIR_H elseif r.card == "prof" then return PROF_H end end,
		spacers = false,
		-- (#62) the card section, or the profession you're scrolling through, stays pinned at the top
		sticky = function(r)
			if r.card == "section" then return { r.header, 1, 0.82, 0.3, foldedSections[r.key] } end
			if r.header and r.depth == 0 and not r.card then return { r.header .. "  |cff999999" .. (r.count or "") .. "|r", 1, 0.82, 0.3, collapsed[r.key] } end
		end,
		emptyText = L["Nothing yet. Open a profession trainer's window, or your own profession window: every recipe you come across is recorded here. Class spells are on each trainer's page in People."],
		update = function(row, r)
			if r.card then return FillCardRow(row, r) end
			FillRecipeRow(row, r)
		end,
		onEnterRow = nil,
		onClick = function(r)
			if r.card == "section" then
				foldedSections[r.key] = (not foldedSections[r.key]) or nil
				page:Refresh()
				return
			end
			if r.card == "prof" then return r.action() end
			if r.card then return end
			if r.newHeader then
				collapsed.new = not collapsed.new
				page:Refresh()
			elseif r.header then
				collapsed[r.key] = not collapsed[r.key]
				-- (a profession's heading also shows its overview on the right)
				if r.depth == 0 then shown = { kind = "group", group = r.group } end
				page:Refresh()
			elseif r.id then
				if ns.New and ns.New:Clicked("trainers", r) then list:Refresh() end
				Show({ kind = "spell", id = r.id })
			end
		end,
	})
	list:SetAllPoints(listHolder)

	detail = W.Detail(parent, 50)
	detail:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
	detail:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
	iconTex = detail.top:CreateTexture(nil, "ARTWORK")
	iconTex:SetSize(44, 44)
	iconTex:SetPoint("TOPLEFT", 2, 0)
	iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	-- (0.69.2) the icon with slightly rounded corners and a thin gold edge, as the game's own, no black quick-slot square
	local iconRing = W.RoundIcon(detail.top, iconTex)
	iconTex:HookScript("OnShow", function() iconRing:SetShown(true) end)
	iconTex:HookScript("OnHide", function() iconRing:SetShown(false) end)
	nameText = detail.top:CreateFontString(nil, "OVERLAY")
	W.HeroFont(nameText, 26)
	nameText:SetPoint("TOPLEFT", 58, -2)
	nameText:SetPoint("RIGHT", detail.top, "RIGHT", -20, 0)
	nameText:SetJustifyH("LEFT")
	subText = detail.top:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	subText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -5)
	Show(nil)
end


function page:Refresh()
	if not list then return end
	PaintBar()
	if view == "cards" then
		local rows, total = CardRows()
		list:SetData(rows)
		list:Select(nil)
		countText:SetText(ns.N(total, "recipe", "recipes"))
		Show(shown, true)
		return
	end
	local rows, n, total = Collect()
	local keep
	for _, r in ipairs(rows) do
		if shown and shown.kind == "spell" and r.id == shown.id then keep = r end
	end
	list:SetData(rows)
	list:Select(keep)
	countText:SetText((L["%d of %d recipes"]):format(n, total))
	Show(shown, true)
end

-- a trainer who teaches this (a class spell's way to People): one you've met, the latest checked first
local function TeacherOf(rec)
	local best, bestT
	for npc in pairs(rec and rec.trainers or {}) do
		local t = ns.Store:Get("trainer", npc)
		if t and (not bestT or (t.checked or 0) > bestT) then best, bestT = npc, t.checked or 0 end
	end
	return best
end
ns.TrainerTeacherOf = TeacherOf

local function ToPeople(npc)
	local people = ns.UI:GetPage("townsfolk")
	if npc and people and people.ShowPerson then people:ShowPerson(npc) else ns.UI:Open("townsfolk") end
end

function page:ShowGroup(group)
	-- (0.69.0) class, weapon and riding trainers: their spells are on their People pages
	if not TR():IsProfession(group) then return ToPeople(nil) end
	return self:ShowOnly(group)
end

-- (0.69.0, #40) opened from a profession card elsewhere: that profession's list under
-- "Recipes › Alchemy" with the back arrow, its overview on the right (group: "skill:<name>")
function page:ShowOnly(group)
	ns.UI:Open("trainers")
	collapsed.new = true
	collapsed[group] = nil
	OpenCard(TR():GroupName(group), function(_, rec) return rec.group == group end, group)
end

function page:ShowSpell(id)
	local rec = ns.Store:Get("spell", id)
	-- (0.69.0) a class spell opens the trainer who teaches it, in People
	if rec and not TR():IsProfession(rec.group) then return ToPeople(TeacherOf(rec)) end
	ns.UI:Open("trainers")
	if rec and rec.group then
		collapsed[rec.group] = nil
		collapsed[rec.group .. "|" .. (Bracket(rec.skill))] = nil
		cardFilter, crumb, view = function(_, r) return r.group == rec.group end, TR():GroupName(rec.group), "list"
	end
	shown = { kind = "spell", id = id }
	self:Refresh()
end

ns:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
	if W.waitingItems and shown and ns.UI:IsShown() and ns.UI:Current() == "trainers" then
		W.waitingItems = false
		C_Timer.After(0.2, function() if shown then ns.UI:Redraw(Show, shown, true) end end) -- (#53: keeps the scroll)
	end
end)

ns:On("RESET", function() shown = nil if list then list:Select(nil) Show(nil) end end)

ns.UI:RegisterPage(page)
