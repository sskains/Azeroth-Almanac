-- (#55 part 2, DESIGN 80) Upgrade arrows: is an item better than what a character wears?
--   Green: for the character you're on. Gold: for another of your characters on the same realm and
--   faction, when a copy you own isn't soulbound (so it can be mailed or traded).
-- How:
--   1. Usable: the armor and weapon skills (yours: your skill list; the others: by class, mail and
--      plate from 40), and the level (above it: "Upgrade at NN").
--   2. The spec: the talent tree with the most points (saved per character by Inventory), or the
--      one chosen in Settings > Items; no talents yet: the class's usual levelling tree.
--   3. A score from Data/StatWeights.lua (the item's stats from the game; weapons add their damage per
--      second; an "on use" or "chance on hit" effect a small bonus).
--   4. Against what the character wears in that slot (saved by Inventory): rings, trinkets and
--      one-handers for a character that fights with two against the weaker of the two; a two-hander
--      against main and off hand together.
-- A rough guide, said so in the tooltip.
-- U:For(item) -> { me = { pct, spec, level } | nil, others = { { c, spec, pct, level, reach, note } } }

local _, ns = ...
local L = ns.L
local U = ns:NewModule("Upgrades")
ns.Upgrades = U

local THRESHOLD = 0.02     -- 2% better counts as an upgrade
local ARROW = "Interface\\AddOns\\AzerothAlmanac\\Media\\Arrow_Upgrade"
local cache = {}           -- item -> { t, result }: kept a few seconds (bags, gear and talents change underneath)
local KEEP = 5

local function INV() return ns.QoL and ns.QoL.Inventory end
local function Settings()
	ns.db.settings.upgrades = ns.db.settings.upgrades or { on = true, spec = {} }
	local s = ns.db.settings.upgrades
	s.spec = s.spec or {}
	return s
end
function U:On() return Settings().on ~= false end
function U:Forget() wipe(cache) if U.ForgetStats then U.ForgetStats() end if U.PaintSoon then U.PaintSoon() end end

-- the arrow as text: green (you) or gold (another character)
function U.Arrow(gold, size)
	size = size or 14
	return ("|T%s:%d:%d:0:0:64:64:0:64:0:64:%s|t"):format(ARROW, size, size, gold and "255:200:40" or "60:230:60")
end

---------------------------------------------------------------------------
-- Items: what they are and what's on them
---------------------------------------------------------------------------

local function Instant(item)
	local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	local ok, id, _, _, equipLoc, _, classID, subID = pcall(f, item)
	if ok then return id, equipLoc, classID, subID end
end

local function Full(item)
	local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local r = { pcall(f, item) }
	if not r[1] or not r[2] then return nil end
	-- name, link, quality, ilvl, minLevel, type, subType, stack, equipLoc, icon, sell, classID, subID, bindType
	return { name = r[2], link = r[3], minLevel = r[6] or 0, equipLoc = r[10], bind = r[15] }
end

-- the game's stat names -> ours (most specific first)
local STAT_KEYS = {
	{ "RANGED_ATTACK_POWER", "rap" }, { "ATTACK_POWER", "ap" }, { "STRENGTH", "str" }, { "AGILITY", "agi" },
	{ "STAMINA", "sta" }, { "INTELLECT", "int" }, { "SPIRIT", "spi" }, { "SPELL_HEALING", "heal" }, { "HEALING", "heal" },
	{ "SPELL_DAMAGE", "sp" }, { "SPELL_POWER", "sp" }, { "MANA_REGENERATION", "mp5" }, { "POWER_REGEN0", "mp5" },
	{ "DEFENSE", "def" }, { "DODGE", "dodge" }, { "PARRY", "parry" }, { "BLOCK_VALUE", "block" }, { "BLOCK", "block" },
	{ "CRIT", "crit" }, { "HIT", "hit" }, { "RESISTANCE0", "armor" }, { "DAMAGE_PER_SECOND", "dps" },
}
local statCache = {}
function U.ForgetStats() wipe(statCache) end
local function Stats(link)
	if not link then return nil end
	local s = statCache[link]
	if s then return s end
	local get = (C_Item and C_Item.GetItemStats) or GetItemStats
	if not get then return nil end
	local ok, raw = pcall(get, link)
	if not ok or type(raw) ~= "table" then return nil end
	s = {}
	for key, v in pairs(raw) do
		local K = tostring(key):upper()
		for _, m in ipairs(STAT_KEYS) do
			if K:find(m[1], 1, true) then s[m[2]] = (s[m[2]] or 0) + (tonumber(v) or 0) break end
		end
	end
	if next(s) then statCache[link] = s end
	return s
end

local RANGED = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }

-- an item's worth to a class and tree (nil: the game hasn't sent its stats yet)
function U.Score(link, class, tree)
	local spec = ns.StatWeights[class] and ns.StatWeights[class][tree]
	if not spec then return nil end
	local s = Stats(link)
	if not s then return nil end
	local w = spec.w
	local _, equipLoc = Instant(link)
	local score = 0
	for stat, v in pairs(s) do
		local k = stat
		if stat == "dps" and RANGED[equipLoc or ""] then k = w.rdps and "rdps" or "dps" end
		local weight = w[k] or 0
		if stat == "dps" and RANGED[equipLoc or ""] and not w.rdps then weight = weight * 0.2 end
		score = score + weight * v
	end
	-- an "on use" or "chance on hit" effect: a small bonus, not real maths
	local id = Instant(link)
	local spell = id and GetItemSpell and GetItemSpell(id)
	if spell then score = score + math.max(2, score * 0.03) end
	return score
end

---------------------------------------------------------------------------
-- Characters
---------------------------------------------------------------------------

-- a character's tree: chosen in Settings, else the one with most points, else the class's usual
function U.Tree(c)
	local class = c.class
	local data = ns.StatWeights[class or ""]
	if not data then return nil end
	local chosen = Settings().spec[c.key or ""]
	if chosen and data[chosen] then return chosen, data[chosen].name end
	local best, most = data.start, 0
	for i, n in ipairs(c.talents or {}) do if (n or 0) > most then best, most = i, n end end
	return best, data[best].name
end

local function Me()
	local inv = INV()
	return inv and inv.Me and inv:Me() or nil
end

-- skills of the character you're on (nil if the game won't say)
local skills
local function MySkills()
	if skills ~= nil then return skills or nil end
	local known = {}
	for i = 1, (ns.NumSkillLines and ns.NumSkillLines() or 0) do
		local name = ns.SkillLine(i)
		if type(name) == "string" then known[name] = true end
	end
	skills = next(known) and known or false
	return skills or nil
end
local SKILL_FOR_WEAPON = { [0] = "Axes", [1] = "Two-Handed Axes", [2] = "Bows", [3] = "Guns", [4] = "Maces", [5] = "Two-Handed Maces",
	[6] = "Polearms", [7] = "Swords", [8] = "Two-Handed Swords", [10] = "Staves", [13] = "Fist Weapons", [15] = "Daggers",
	[16] = "Thrown", [18] = "Crossbows", [19] = "Wands" }
local SKILL_FOR_ARMOR = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate Mail", [6] = "Shield" }

-- the classes an item is limited to ("Classes: Rogue, Druid" on its tooltip): { WARRIOR = true ... },
-- or false for anyone. Read from the game's tooltip data (C_TooltipInfo) once per item.
local classLimits = {}
local CLASS_FILE
local function ClassFiles()
	if CLASS_FILE then return CLASS_FILE end
	CLASS_FILE = {}
	for _, t in ipairs({ LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
		for file, name in pairs(t) do CLASS_FILE[name] = file end
	end
	for file in pairs(ns.StatWeights or {}) do
		local plain = file:sub(1, 1) .. file:sub(2):lower()
		CLASS_FILE[plain] = CLASS_FILE[plain] or file
	end
	return CLASS_FILE
end
function U.ClassLimit(item)
	local id = (type(item) == "number" and item) or (type(item) == "string" and tonumber(item:match("item:(%d+)")))
	if not id then return false end
	local hit = classLimits[id]
	if hit ~= nil then return hit end
	if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return false end
	local ok, data = pcall(C_TooltipInfo.GetItemByID, id)
	if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return false end -- (not cached: asked again later)
	local prefix = (ITEM_CLASSES_ALLOWED or "Classes: %s"):gsub("%%s", "(.+)")
	local limit = false
	for _, line in ipairs(data.lines) do
		local text = type(line) == "table" and line.leftText
		local list = type(text) == "string" and text:match("^" .. prefix .. "$")
		if list then
			limit = {}
			for name in list:gmatch("[^,]+") do
				local file = ClassFiles()[(name:gsub("^%s+", ""):gsub("%s+$", ""))]
				if file then limit[file] = true end
			end
			if not next(limit) then limit = false end
			break
		end
	end
	classLimits[id] = limit
	return limit
end

-- can c wear / wield it (ignoring level)? me: their skills; others: their class
local function CanWear(c, classID, subID, isMe, id)
	if classID ~= 2 and classID ~= 4 then return false end
	-- (an item only some classes can use)
	local limit = id and U.ClassLimit(id)
	if limit and not limit[c.class or ""] then return false end
	if classID == 4 and (subID == 0 or subID == 5 or subID == 7 or subID == 8 or subID == 9 or subID == 10 or subID == 11) then
		return true -- (jewelry, cloaks' "miscellaneous", librams, idols, totems: no skill)
	end
	if isMe then
		local known = MySkills()
		local need = classID == 2 and SKILL_FOR_WEAPON[subID] or SKILL_FOR_ARMOR[subID]
		if known and need then return known[need] == true end
	end
	local table_ = classID == 2 and ns.ClassGear.weapon[c.class or ""] or ns.ClassGear.armor[c.class or ""]
	if not table_ then return false end
	local from = table_[subID]
	if classID == 2 then return from == true end
	return from ~= nil and (c.level or 1) >= from
end

---------------------------------------------------------------------------
-- What it would replace
---------------------------------------------------------------------------

local SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPON = { 16 }, INVTYPE_2HWEAPON = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
	INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

-- (a full hyperlink: the game reads a random suffix's stats ("of the Whale") only from a link,
-- not from a bare "item:..." string)
local function AsLink(item)
	if type(item) == "number" then item = "item:" .. item end
	if type(item) ~= "string" then return nil end
	if item:find("|H", 1, true) then return item end
	return "|cffffffff|H" .. item .. "|h[ ]|h|r"
end
U.AsLink = AsLink
local function WornLink(c, slot)
	local item = c.gear and c.gear[slot]
	if not item then return nil end
	-- (the full link, saved since #55: its random suffix and enchant included)
	local full = c.gearLinks and c.gearLinks[slot]
	if type(full) == "string" then return full end
	local inv = INV()
	return (inv and inv.Link and inv.Link(item)) or AsLink(item)
end

-- the score to beat for c in the item's slot (0: empty), or nil if unknown (stats not in yet)
local function Current(c, equipLoc, class, tree)
	local slots = SLOTS[equipLoc or ""]
	if not slots then return nil end
	-- (is anything worn there at all? an empty slot is only "an empty slot" when nothing is)
	local wornAny = false
	for _, sl in ipairs(slots) do if c.gear and c.gear[sl] then wornAny = true end end
	if (equipLoc == "INVTYPE_2HWEAPON" or equipLoc == "INVTYPE_WEAPON") and c.gear and (c.gear[16] or c.gear[17]) then wornAny = true end
	U.lastWorn = wornAny
	local function Of(slot)
		local link = WornLink(c, slot)
		if not link then return 0 end
		local s = Stats(link)
		-- (worn, but the game hasn't told us its stats yet: unknown, never "an empty slot")
		if not s or not next(s) then return nil end
		return U.Score(link, class, tree)
	end
	local mh = WornLink(c, 16)
	local _, mhLoc = mh and Instant(mh)
	if equipLoc == "INVTYPE_2HWEAPON" then
		local a, b = Of(16), (mhLoc == "INVTYPE_2HWEAPON") and 0 or Of(17)
		if not a or not b then return nil end
		return a + b
	end
	if equipLoc == "INVTYPE_WEAPON" then
		local dual = ns.ClassGear.dual[class or ""]
		local oh = WornLink(c, 17)
		local _, ohLoc = oh and Instant(oh)
		if mhLoc == "INVTYPE_2HWEAPON" then return Of(16) end -- (instead of the two-hander: a rough match)
		if dual and (c.level or 1) >= dual and (not oh or ohLoc == "INVTYPE_WEAPON" or ohLoc == "INVTYPE_WEAPONOFFHAND") then
			local a, b = Of(16), Of(17)
			if not a or not b then return nil end
			return math.min(a, b)
		end
		return Of(16)
	end
	if equipLoc == "INVTYPE_WEAPONOFFHAND" or equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" then
		if mhLoc == "INVTYPE_2HWEAPON" then return nil end -- (beside a two-hander: no compare)
		if equipLoc == "INVTYPE_WEAPONOFFHAND" and not ns.ClassGear.dual[class or ""] then return nil end
		return Of(17)
	end
	if #slots == 2 then
		local a, b = Of(slots[1]), Of(slots[2])
		if not a or not b then return nil end
		return math.min(a, b)
	end
	return Of(slots[1])
end

-- how much better for c (a fraction; nil: not an upgrade, or not known yet), and the level it needs
local function Better(c, item, isMe)
	local id, equipLoc, classID, subID = Instant(item)
	if not id or not SLOTS[equipLoc or ""] then return nil end
	if not CanWear(c, classID, subID, isMe, id) then return nil end
	local tree, specName = U.Tree(c)
	if not tree then return nil end
	local full = Full(item)
	local link = (full and full.link) or AsLink(type(item) == "string" and item or id)
	local score = U.Score(link, c.class, tree)
	if not score or score <= 0 then return nil end
	local now = Current(c, equipLoc, c.class, tree)
	if not now then return nil end
	local empty = now <= 0 and not U.lastWorn
	-- (something worn that scores nothing for this spec: compared by a floor, never "an empty slot")
	local base = empty and 0 or math.max(now, 1)
	local pct = empty and 1 or (score - base) / base
	if pct < THRESHOLD then return nil end
	local need = full and full.minLevel or 0
	return pct, specName, (need > (c.level or 1)) and need or nil, empty
end

---------------------------------------------------------------------------
-- Who could have it
---------------------------------------------------------------------------

-- a copy you own that isn't soulbound: where ("bank", "bags", "Thrall's bags" ...), or nil
local function BoundCopy(id)
	local inv = INV()
	for _, c in ipairs(inv and inv.Characters and inv:Characters(true) or {}) do
		for _, where in ipairs({ "bags", "bank" }) do
			for _, container in ipairs(c[where] or {}) do
				for slot, entry in pairs(container.slots or {}) do
					if type(slot) == "number" and type(entry) == "table" and entry[3] and inv.ItemID(entry[1]) == id then return true end
				end
			end
		end
	end
	return false
end

local function UnboundCopy(id, forKey)
	local inv = INV()
	for _, c in ipairs(inv and inv.Characters and inv:Characters(true) or {}) do
		for _, where in ipairs({ "bags", "bank" }) do
			for _, container in ipairs(c[where] or {}) do
				for slot, entry in pairs(container.slots or {}) do
					if type(slot) == "number" and type(entry) == "table" and not entry[3] then
						local eid = inv.ItemID(entry[1])
						if eid == id then
							if c.key == forKey then return where == "bank" and L["in their bank"] or L["in their bags"], c end
							local me = Me()
							if me and c.key == me.key then return where == "bank" and L["in your bank"] or L["in your bags"], c end
							return (where == "bank" and L["in %s's bank"] or L["in %s's bags"]):format(c.name or "?"), c
						end
					end
				end
			end
		end
	end
end

function U:For(item)
	if not self:On() or not item then return nil end
	local key = type(item) == "number" and item or tostring(item)
	local hit = cache[key]
	if hit and GetTime() - hit.t < KEEP then return hit.r or nil end
	local me = Me()
	if not me then return nil end
	local id = Instant(item)
	local result = { others = {} }
	local pct, spec, level, empty = Better(me, item, true)
	if pct then result.me = { pct = pct, spec = spec, level = level, empty = empty } end
	local full = Full(item)
	local bop = full and full.bind == 1
	local inv = INV()
	for _, c in ipairs(inv and inv.Characters and inv:Characters(false) or {}) do
		if c.key ~= me.key then
			local p, s, lvl, emp = Better(c, item, false)
			if p then
				local entry = { c = c, pct = p, spec = s, level = lvl, empty = emp }
				-- (only a character it can reach: same realm and faction, and a copy that isn't bound)
				local reachable = c.realm == me.realm and c.faction == me.faction
				if reachable then
					local where = not bop and id and UnboundCopy(id, c.key)
					if where then entry.reach = where
					elseif bop then entry.note = L["binds when picked up"]
					elseif id and BoundCopy(id) then entry.note = L["yours is soulbound"]
					else entry.note = nil end
					result.others[#result.others + 1] = entry
				end
			end
		end
	end
	if not result.me and #result.others == 0 then cache[key] = { t = GetTime(), r = false } return nil end
	table.sort(result.others, function(a, b) if (a.reach ~= nil) ~= (b.reach ~= nil) then return a.reach ~= nil end return a.pct > b.pct end)
	cache[key] = { t = GetTime(), r = result }
	return result
end

-- the arrow for a row: green (you), else gold (another character it can reach), with "Upgrade at NN"
function U:RowMark(item)
	local r = self:For(item)
	if not r then return nil end
	if r.me then
		if r.me.level then return "|cff9be36b" .. (L["Upgrade at %d"]):format(r.me.level) .. "|r" end
		return self.Arrow(false)
	end
	for _, o in ipairs(r.others) do
		if o.reach and not o.level then return self.Arrow(true) end
	end
end

local function Pct(p, empty) return empty and L["an empty slot"] or ("+%d%%"):format(math.floor(p * 100 + 0.5)) end
local function Name(c) return ns.CharName and c.key and ns.CharName(c.key, true) or c.name or "?" end

-- the lines for a tooltip or the item page: { text, r, g, b }
function U:Lines(item)
	local r = self:For(item)
	if not r then return {} end
	local out = {}
	if r.me then
		local t = (L["Upgrade for you (%s): %s"]):format(r.me.spec or "?", Pct(r.me.pct, r.me.empty))
		if r.me.level then t = t .. "  ·  " .. (L["at level %d"]):format(r.me.level) end
		out[#out + 1] = { self.Arrow(false) .. " " .. t .. "  |cff999999·  " .. L["rough guide"] .. "|r", 0.6, 0.9, 0.4 }
	end
	for _, o in ipairs(r.others) do
		local who = ("%s (%s)"):format(Name(o.c), o.spec or "?")
		if o.reach then
			local t = (L["Upgrade for %s: %s"]):format(who, Pct(o.pct, o.empty)) .. "  ·  " .. o.reach
			if o.level then t = t .. "  ·  " .. (L["at level %d"]):format(o.level) end
			out[#out + 1] = { self.Arrow(true) .. " " .. t, 1, 0.8, 0.25 }
		else
			-- (no copy they can have: "if they get one", and why when it's binding)
			out[#out + 1] = { (o.note and L["Also better for %s if they get their own (%s)"] or L["Also better for %s if they get one"]):format(who, o.note), 0.6, 0.6, 0.6 }
		end
	end
	return out
end

local function AddTooltipLines(tooltip)
	if not (U:On() and tooltip and tooltip.GetItem) then return end
	local _, link = tooltip:GetItem()
	if not link then return end
	local lines = U:Lines(link)
	if #lines == 0 then return end
	for _, ln in ipairs(lines) do tooltip:AddLine(ln[1], ln[2], ln[3], ln[4], true) end
	tooltip:Show()
end

function U:OnLogin()
	-- forget what was worked out when gear, talents or skills change (bags: the few seconds' keep)
	local f = CreateFrame("Frame")
	for _, ev in ipairs({ "GET_ITEM_INFO_RECEIVED", "SKILL_LINES_CHANGED", "CHARACTER_POINTS_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_EQUIPMENT_CHANGED" }) do
		pcall(f.RegisterEvent, f, ev)
	end
	pcall(f.RegisterEvent, f, "BAG_UPDATE_DELAYED")
	-- (the bag arrows: redrawn a moment after anything that could change them, once per burst)
	local pending = false
	local function Soon()
		if pending then return end
		pending = true
		C_Timer.After(0.2, function() pending = false pcall(U.PaintBags, U) end)
	end
	U.PaintSoon = Soon
	f:SetScript("OnEvent", function(_, event)
		if event == "SKILL_LINES_CHANGED" then skills = nil end
		if event ~= "BAG_UPDATE_DELAYED" then wipe(cache) end
		Soon()
	end)
	-- a bag window opening: its arrows
	local frames = { _G.ContainerFrameCombinedBags }
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do frames[#frames + 1] = _G["ContainerFrame" .. i] end
	for _, bf in ipairs(frames) do
		if type(bf) == "table" and bf.HookScript then pcall(bf.HookScript, bf, "OnShow", Soon) end
	end
	if hooksecurefunc and _G.ContainerFrame_Update then hooksecurefunc("ContainerFrame_Update", Soon) end
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip) pcall(AddTooltipLines, tooltip) end)
	else
		for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
			if tooltip and tooltip.HookScript then tooltip:HookScript("OnTooltipSetItem", function(self) pcall(AddTooltipLines, self) end) end
		end
	end
end

---------------------------------------------------------------------------
-- The arrow on the items in your bags (bottom right of the icon): green for you, gold for another
-- character it can reach. The game's bags (the combined backpack or separate bags) and bag addons
-- whose buttons answer GetBagID / their parent's ID and GetID.
---------------------------------------------------------------------------

local function BagButtons()
	local list = {}
	local frames = { _G.ContainerFrameCombinedBags }
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do frames[#frames + 1] = _G["ContainerFrame" .. i] end
	for _, f in ipairs(frames) do
		if type(f) == "table" and f.IsShown and f:IsShown() then
			if f.EnumerateValidItems then
				pcall(function() for _, b in f:EnumerateValidItems() do list[#list + 1] = b end end)
			end
			if f.GetName and f:GetName() then
				for j = 1, (MAX_CONTAINER_ITEMS or 36) do
					local b = _G[f:GetName() .. "Item" .. j]
					if type(b) == "table" and b.IsShown then list[#list + 1] = b end
				end
			end
		end
	end
	return list
end

local function BagSlot(b)
	if type(b) ~= "table" or not b.GetID then return nil end
	local slot = b:GetID()
	local bag = b.GetBagID and b:GetBagID()
	if bag == nil and b.GetParent and b:GetParent() and b:GetParent().GetID then bag = b:GetParent():GetID() end
	if type(bag) == "number" and type(slot) == "number" then return bag, slot end
end

function U:PaintBags()
	local seen = {}
	for _, b in ipairs(BagButtons()) do
		if not seen[b] then
			seen[b] = true
			local mark
			local bag, slot = BagSlot(b)
			if self:On() and bag and b:IsShown() then
				local get = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
				local link = get and get(bag, slot)
				if link then
					local r = self:For(link)
					if r and r.me and not r.me.level then mark = "me"
					elseif r then for _, o in ipairs(r.others) do if o.reach and not o.level then mark = "alt" break end end end
				end
			end
			if mark and not b.aaUpgrade then
				b.aaUpgrade = b:CreateTexture(nil, "OVERLAY", nil, 7)
				b.aaUpgrade:SetTexture(ARROW)
				b.aaUpgrade:SetSize(14, 14)
				b.aaUpgrade:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 2)
			end
			if b.aaUpgrade then
				b.aaUpgrade:SetShown(mark ~= nil)
				if mark == "me" then b.aaUpgrade:SetVertexColor(0.24, 0.9, 0.24) elseif mark then b.aaUpgrade:SetVertexColor(1, 0.78, 0.16) end
			end
		end
	end
end

-- (for Settings and the tests)
U.CanWear, U.Current, U.Better = CanWear, Current, Better
function U:SetTree(key, tree) Settings().spec[key] = tree wipe(cache) end
