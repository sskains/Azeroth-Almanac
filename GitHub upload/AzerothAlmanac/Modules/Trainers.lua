-- Trainers: what each trainer teaches, as the trainer window shows it, and the recipes each
-- character knows, as the profession window shows them. Nothing comes from a spell list: a spell
-- or recipe is in the Almanac only once a trainer (or a profession window) has shown it.
--   found.trainer[npcID] = { name, title, map, x, y, zone, sub, group, checked, teaches = { spellID } }
--   found.spell[spellID] = { name, rank, icon, group ("class:PALADIN" / "skill:Blacksmithing"), lvl,
--                            cost, skill = required skill rank, cat (profession window heading),
--                            made = itemID, makes = n, reagents = { { itemID, n } },
--                            trainers = { [npcID] = cost } }
--   chars[key].spells[spellID] = time learned (or 0 when found already known)
--   chars[key].skills[name] = { rank, max }   professions and secondary skills
--   chars[key].recipeDiff[spellID] = 0 orange .. 3 grey, the skill-up colour the profession window last showed (DESIGN 90)
-- groups: "class:<CLASSFILE>" for class trainers, "skill:<profession>" for profession trainers

local _, ns = ...
local L = ns.L
local T = ns:NewModule("Trainers")
local R = ns.Readable

local function Call(fn, ...)
	if not fn then return nil end
	local ok, a, b, c, d, e = pcall(fn, ...)
	if ok then return R(a), R(b), R(c), R(d), R(e) end
end

local function ItemID(link)
	link = R(link)
	if type(link) ~= "string" then return nil end
	return tonumber(link:match("item:(%d+)"))
end

local function Me()
	local c = ns.db.chars[ns.CharKey()]
	if not c then return nil end
	c.spells = c.spells or {}
	c.skills = c.skills or {}
	return c
end

-- the NPC's title ("<Blacksmithing Trainer>") is the second line of its tooltip
local function Title(unit)
	if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
	local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
	if not ok or type(data) ~= "table" or ns.IsSecret(data) then return nil end
	local lines = R(data.lines)
	local line = type(lines) == "table" and lines[2] and R(lines[2].leftText)
	if type(line) == "string" and not line:find("%d") then return line end
end

---------------------------------------------------------------------------
-- Tooltips: the spell's own tooltip lines (mana, cast time, cooldown, range, the rank's description
-- with its amounts), kept as { { l, r, lc, rc } } with colours as hex, the game's text as it is
---------------------------------------------------------------------------

local function Hex(c)
	if type(c) ~= "table" then return nil end
	local r, g, b = R(c.r), R(c.g), R(c.b)
	if not (r and g and b) then return nil end
	return ("%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

-- lines that are the tooltip's frame, not the spell: the name, "Requires level", the issue reporter
local SKIP = { "^Requires [Ll]evel", "^Press F6", "^%s*$", "^<.*>$" }
local function TipLines(data)
	if type(data) ~= "table" or ns.IsSecret(data) then return nil end
	if TooltipUtil and TooltipUtil.SurfaceArgs then pcall(TooltipUtil.SurfaceArgs, data) end
	local out = {}
	for n, line in ipairs(R(data.lines) or {}) do
		if type(line) == "table" then
			if TooltipUtil and TooltipUtil.SurfaceArgs then pcall(TooltipUtil.SurfaceArgs, line) end
			local l, r = R(line.leftText), R(line.rightText)
			local skip = n == 1 or type(l) ~= "string"
			if not skip then
				for _, p in ipairs(SKIP) do if l:find(p) then skip = true break end end
			end
			if not skip then
				out[#out + 1] = { l = l, r = type(r) == "string" and r ~= "" and r or nil, lc = Hex(R(line.leftColor)), rc = Hex(R(line.rightColor)) }
			end
		end
	end
	return #out > 0 and out or nil
end

local function ServiceTip(i)
	if C_TooltipInfo and C_TooltipInfo.GetTrainerService then
		local ok, info = pcall(C_TooltipInfo.GetTrainerService, i)
		if ok and type(info) == "table" then return R(info.id), TipLines(info) end
	end
end


-- a spell's tooltip lines: the game's own for this spell ID when it has them, else the ones saved
-- at the trainer
function T:Tooltip(id, rec)
	if C_TooltipInfo and C_TooltipInfo.GetSpellByID then
		local ok, data = pcall(C_TooltipInfo.GetSpellByID, id)
		local lines = ok and TipLines(data)
		if lines and #lines > 1 then return lines end
	end
	return rec and rec.tip
end

-- the description part (the long lines with no right-hand text)
function T:Description(lines)
	local out = {}
	for _, ln in ipairs(lines or {}) do
		if not ln.r and #ln.l > 30 then out[#out + 1] = ln.l end
	end
	return table.concat(out, "\n")
end

-- a spell's or recipe's record, merged quietly (spells are found in bulk; the trainer gets the journal line)
local function Spell(id, fields)
	local rec = ns.Store:Get("spell", id)
	if rec and rec.c and rec.c[ns.CharKey()] then
		for k, v in pairs(fields) do if v ~= nil then rec[k] = v end end
		return rec
	end
	return (ns.Store:Discover("spell", id, fields, nil, nil, true))
end

---------------------------------------------------------------------------
-- The trainer window
---------------------------------------------------------------------------

local reading = false
function T:ReadTrainer()
	if reading or not GetNumTrainerServices then return end
	local npc = ns.NpcFromGuid(R(UnitGUID("npc")))
	if not npc then return end
	reading = true
	local profession = IsTradeskillTrainer and Call(IsTradeskillTrainer)
	-- list everything, not only what the trainer window's filter shows; then put the filter back
	local filters = {}
	if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
		for _, f in ipairs({ "available", "unavailable", "used" }) do
			filters[f] = Call(GetTrainerServiceTypeFilter, f)
			if not filters[f] then pcall(SetTrainerServiceTypeFilter, f, 1) end
		end
	end
	local services = {}
	local skillName
	for i = 1, (Call(GetNumTrainerServices) or 0) do
		local name, kind, icon, reqLevel, subText = Call(GetTrainerServiceInfo, i)
		if name and kind ~= "header" then
			local id, tip = ServiceTip(i)
			if id then
				local lvl = Call(GetTrainerServiceLevelReq, i) or (type(reqLevel) == "number" and reqLevel or nil)
				local skill, skillRank = Call(GetTrainerServiceSkillReq, i)
				if profession and skill and not skillName then skillName = skill end
				services[#services + 1] = {
					id = id, name = name, status = kind, icon = Call(GetTrainerServiceIcon, i) or (type(icon) ~= "number" or icon > 1000) and icon or nil,
					rank = type(subText) == "string" and subText ~= "" and subText or nil,
					lvl = lvl and lvl > 1 and lvl or nil, cost = Call(GetTrainerServiceCost, i) or 0,
					skill = profession and skillRank and skillRank > 0 and skillRank or nil,
					made = ItemID(Call(GetTrainerServiceItemLink, i)), tip = tip,
				}
			end
		end
	end
	for f, on in pairs(filters) do if not on then pcall(SetTrainerServiceTypeFilter, f, 0) end end
	reading = false
	if #services == 0 then return end

	local title = Title("npc")
	local _, classFile = UnitClass("player")
	local group
	if profession then
		-- "Blacksmithing" from the services' skill requirement, or from the title ("<Blacksmithing Trainer>")
		skillName = skillName or (title and title:gsub("%s*[Tt]rainer$", ""):gsub("^Master%s+", ""):gsub("^Expert%s+", ""))
		group = "skill:" .. (skillName or "?")
	else
		group = "class:" .. (classFile or "?")
		-- weapon masters, riding and other trainers that aren't your class trainer
		if title and not title:find(UnitClass("player"), 1, true) then group = "other:" .. title end
	end

	local where = ns.Where()
	local existing = ns.Store:Get("trainer", npc)
	local name = R(UnitName("npc"))
	local fields = { name = name, title = title, group = group, zone = where.zone, sub = where.sub, map = where.map }
	if not existing or not existing.x then fields.x, fields.y = where.x, where.y end
	local text = name and (where.sub and where.sub ~= "" and (L["%s, %s"]):format(name, where.sub) or name) or "?"
	local rec = ns.Store:Discover("trainer", npc, fields, text, where)
	if not rec then return end
	rec.checked = time()
	rec.teaches = {}

	local me = Me()
	for _, s in ipairs(services) do
		rec.teaches[#rec.teaches + 1] = s.id
		local sp = Spell(s.id, { name = s.name, rank = s.rank, icon = s.icon, group = group, lvl = s.lvl, skill = s.skill, made = s.made, tip = s.tip })
		if sp then
			sp.trainers = sp.trainers or {}
			sp.trainers[npc] = s.cost
			sp.cost = s.cost
		end
		if me and s.status == "used" and not me.spells[s.id] then me.spells[s.id] = 0 end
	end
	ns:Fire("CHANGED", "trainer", npc)
end

local pending = false
local function Soon()
	if pending or not ns.db then return end
	pending = true
	C_Timer.After(0.3, function()
		pending = false
		ns.doing = "reading a trainer"
		pcall(T.ReadTrainer, T)
		ns.doing = "idle"
	end)
end
ns:RegisterEvent("TRAINER_SHOW", Soon)
ns:RegisterEvent("TRAINER_UPDATE", function() if not reading then Soon() end end)

---------------------------------------------------------------------------
-- the older API's words for a recipe's skill-up colour, as Enum.TradeskillRelativeDifficulty numbers
local DIFFICULTY = { optimal = 0, medium = 1, easy = 2, trivial = 3 }

-- The profession window: the recipes this character knows, with reagents and what they make
---------------------------------------------------------------------------

local function Schematic(id)
	if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) then return nil end
	local ok, s = pcall(C_TradeSkillUI.GetRecipeSchematic, id, false)
	if not ok or type(s) ~= "table" or ns.IsSecret(s) then return nil end
	local reagents = {}
	for _, slot in ipairs(s.reagentSlotSchematics or {}) do
		local r = slot.reagents and slot.reagents[1]
		if slot.required ~= false and r and R(r.itemID) and (R(slot.quantityRequired) or 0) > 0 then
			reagents[#reagents + 1] = { R(r.itemID), R(slot.quantityRequired) }
		end
	end
	local made = R(s.outputItemID)
	local n = math.max(R(s.quantityMin) or 1, 1)
	return #reagents > 0 and reagents or nil, made, n
end

function T:ReadProfession()
	if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs) then return end
	local me = Me()
	if not me then return end
	local prof = Call(C_TradeSkillUI.GetBaseProfessionInfo)
	local profName = type(prof) == "table" and R(prof.professionName) or nil
	local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
	if not ok or type(ids) ~= "table" then return end
	local added = 0
	for _, id in ipairs(ids) do
		local info = Call(C_TradeSkillUI.GetRecipeInfo, id)
		id = R(id)
		if id and type(info) == "table" and R(info.learned) then
			local reagents, made, n = Schematic(id)
			local cat
			if info.categoryID and C_TradeSkillUI.GetCategoryInfo then
				local c = Call(C_TradeSkillUI.GetCategoryInfo, R(info.categoryID))
				cat = type(c) == "table" and R(c.name) or nil
			end
			local existing = ns.Store:Get("spell", id)
			local okT, data = pcall(C_TooltipInfo and C_TooltipInfo.GetSpellByID or error, id)
			Spell(id, { name = R(info.name), icon = R(info.icon), group = profName and ("skill:" .. profName) or (existing and existing.group),
				tip = okT and TipLines(data) or nil,
				cat = cat, reagents = reagents, made = made, makes = n and n > 1 and n or nil })
			if not me.spells[id] then
				me.spells[id] = 0
				added = added + 1
			end
			-- (DESIGN 90) its skill-up colour for this character now: 0 orange, 1 yellow, 2 green, 3 grey
			local d = R(info.relativeDifficulty)
			if type(d) ~= "number" then d = DIFFICULTY[R(info.difficulty) or ""] end
			if type(d) == "number" and d >= 0 and d <= 3 then
				me.recipeDiff = me.recipeDiff or {}
				me.recipeDiff[id] = d
			end
		end
	end
	if profName and type(prof) == "table" then
		me.skills[profName] = { rank = R(prof.skillLevel), max = R(prof.maxSkillLevel) }
	end
	if added > 0 then ns:Fire("CHANGED", "spell") end
end

local pendingProf = false
local function SoonProf()
	if pendingProf or not ns.db then return end
	pendingProf = true
	C_Timer.After(1, function()
		pendingProf = false
		ns.doing = "reading the profession window"
		pcall(T.ReadProfession, T)
		ns.doing = "idle"
	end)
end
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "NEW_RECIPE_LEARNED" }) do ns:RegisterEvent(e, SoonProf) end

---------------------------------------------------------------------------
-- Learning, and each character's profession levels (the skills list)
---------------------------------------------------------------------------

ns:RegisterEvent("LEARNED_SPELL_IN_TAB", function(_, id) id = R(id) if ns.db and id and Me() then Me().spells[id] = time() ns:Fire("CHANGED", "spell", id) end end)
ns:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE", function(_, id) id = R(id) if ns.db and id and Me() then Me().spells[id] = time() ns:Fire("CHANGED", "spell", id) end end)

function T:ReadSkills()
	local me = Me()
	if not me then return end
	local header
	for i = 1, ns.NumSkillLines() do -- (0.67.4: C_SkillInfo on WoW Forever; the old globals are gone)
		local name, isHeader, rank, max = ns.SkillLine(i)
		if isHeader then
			header = name
		-- (0.69.0, #37) a rogue's Lockpicking too, whichever heading it sits under
		elseif name and rank and (name == ns.L["Lockpicking"] or header == (TRADE_SKILLS or "Professions") or header == (SECONDARY_SKILLS and SECONDARY_SKILLS:gsub(":$", "") or "Secondary Skills") or header == "Secondary Skills") then
			me.skills[name] = { rank = rank, max = max }
		end
	end
end
ns:RegisterEvent("SKILL_LINES_CHANGED", function() if ns.db then pcall(T.ReadSkills, T) end end)
ns:RegisterEvent("PLAYER_ENTERING_WORLD", function() if ns.db then C_Timer.After(4, function() pcall(T.ReadSkills, T) end) end end)

---------------------------------------------------------------------------
-- Lookups for the pages
---------------------------------------------------------------------------

-- "class:PALADIN" -> "Paladin", "skill:Blacksmithing" -> "Blacksmithing", "other:Weapon Master" -> "Weapon Master"
function T:GroupName(group)
	local kind, v = (group or ""):match("^(%a+):(.*)$")
	if kind == "class" then
		local male = LOCALIZED_CLASS_NAMES_MALE
		return (male and male[v]) or (v:sub(1, 1) .. v:sub(2):lower())
	end
	return v or group or "?"
end

function T:IsProfession(group) return (group or ""):find("^skill:") ~= nil end

-- what this character can do about a spell: "known", "now" (can learn now), "later" (level or
-- skill too low), "other" (another class or a profession it doesn't have)
function T:StatusFor(key, rec, id)
	local c = ns.db.chars[key]
	if not c then return "other" end
	if c.spells and c.spells[id] then return "known" end
	local kind, v = (rec.group or ""):match("^(%a+):(.*)$")
	if kind == "class" then
		if c.classFile ~= v then return "other" end
		return (rec.lvl or 1) <= (c.level or 1) and "now" or "later"
	elseif kind == "skill" then
		local s = c.skills and c.skills[v]
		if not s then return "other" end
		return ((rec.skill or 0) <= (s.rank or 0) and (rec.lvl or 1) <= (c.level or 1)) and "now" or "later"
	end
	return (rec.lvl or 1) <= (c.level or 1) and "now" or "later"
end

-- the recipe items of a profession you've come across (from Items), by the item's own recipe kind
local RECIPE_KIND = { [1] = "Leatherworking", [2] = "Tailoring", [3] = "Engineering", [4] = "Blacksmithing", [5] = "Cooking",
	[6] = "Alchemy", [7] = "First Aid", [8] = "Enchanting", [9] = "Fishing" }
function T:RecipeItems(profession)
	local out = {}
	local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	if not instant then return out end
	for id, rec in pairs(ns.Store:All("item")) do
		local ok, _, _, _, _, _, classID, subClassID = pcall(instant, id)
		if ok and classID == 9 then
			local kind = RECIPE_KIND[subClassID]
			local local_name = kind and C_Item and C_Item.GetItemSubClassInfo and Call(C_Item.GetItemSubClassInfo, 9, subClassID)
			if kind == profession or local_name == profession then out[#out + 1] = { id = id, rec = rec } end
		end
	end
	table.sort(out, function(a, b) return (a.rec.name or "") < (b.rec.name or "") end)
	return out
end
