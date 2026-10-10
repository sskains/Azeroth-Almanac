-- Items page: every item you've come across. Left: cards or the tree (#55, below).
-- Right, on parchment: the item's own tooltip card, then (hover its icon for the game's tooltip) how and when it was
-- first found, who owns it now, and every source you've met: creatures that dropped it (with your
-- own drop rate), merchants selling it, quests rewarding it, objects and containers it came from,
-- fishing and crafting. Sources you haven't met are only counted, from the Classic records.

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local IDB = ns.ItemDB

local page = { key = "items", title = L["Items"], icon = "Interface\\AddOns\\AzerothAlmanac\\Media\\Tab_Items", order = 4 }
local list, detail, countText, iconButton, nameText, typeText, firstText
local filter = ""
local shown
local waiting = false

local QUALITY_NAMES = { [0] = L["Poor"], [1] = L["Common"], [2] = L["Uncommon"], [3] = L["Rare"], [4] = L["Epic"], [5] = L["Legendary"] }
local HOW = {
	looted = L["looted"], received = L["received"], crafted = L["crafted"], bought = L["bought"],
	merchant = L["seen on a merchant"], reward = L["offered as a quest reward"], carried = L["already carried"],
}
local NOTE = "|cffbfbfbf"
local CLASSIC = "|cff8c8c8c"

local function Info(id)
	local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local ok, name, link, quality, ilvl, minLevel, itemType, subType, _, equipLoc, texture, sell = pcall(getInfo, id)
	if not (ok and name) then
		waiting = true
		local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
		local icon = instant and select(5, instant(id))
		return { icon = icon }
	end
	return { name = name, link = link, quality = quality, ilvl = ilvl, minLevel = minLevel, type = itemType, subType = subType,
		equipLoc = equipLoc, icon = texture, sell = sell }
end

local function QualityHex(q, onParchment)
	if onParchment and (q or 1) <= 1 then return "|cff2b1d0e" end
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
	return c and c.hex or "|cffffffff"
end

local function ItemName(id, rec)
	local i = Info(id)
	return i.name or (rec and rec.name) or (L["item %d"]):format(id)
end

---------------------------------------------------------------------------
-- The page for one item
---------------------------------------------------------------------------

local function CreatureName(npc)
	local c = ns.Store:Get("creature", npc)
	return c and c.name or nil
end

---------------------------------------------------------------------------
-- The item's own tooltip card at the top of the page: the game's tooltip (a GameTooltip of our own,
-- so it never fights the mouse-over one), laid into the page and scrolling with it. Other addons'
-- tooltip lines (and the Almanac's vendor / disenchant lines) show on it as they do on hover.
---------------------------------------------------------------------------

local cardHolder, card

local function CardHeight()
	if not (card and shown) then return 0 end
	local i = Info(shown)
	card:SetOwner(cardHolder, "ANCHOR_NONE")
	card:ClearAllPoints()
	card:SetPoint("TOPLEFT", cardHolder, "TOPLEFT", 0, 0)
	card:SetFrameStrata(cardHolder:GetFrameStrata())
	card:SetFrameLevel(cardHolder:GetFrameLevel() + 5)
	local ok = pcall(card.SetHyperlink, card, i.link or ("item:" .. shown))
	if not ok then pcall(card.SetItemByID, card, shown) end
	card:Show()
	local h = math.floor((card:GetHeight() or 0) + 0.5)
	cardHolder:SetSize(math.max(card:GetWidth() or 1, 1), math.max(h, 1))
	return h
end

local function MakeCard(parent)
	cardHolder = CreateFrame("Frame", nil, parent)
	cardHolder:SetSize(1, 1)
	local ok, tip = pcall(CreateFrame, "GameTooltip", "AzerothAlmanacItemCard", cardHolder, "GameTooltipTemplate")
	if not ok then return end
	card = tip
	card:SetClampedToScreen(false)
	cardHolder:SetScript("OnHide", function() card:Hide() end)
end

local function Describe(id, rec)
	local b = {}
	if cardHolder then b[#b + 1] = { "frame", cardHolder, CardHeight } end
	local db = IDB:Get(id)
	local src = rec.src or {}
	local i = Info(id)

	-- General
	b[#b + 1] = { "banner", L["General"] }
	if i.type then b[#b + 1] = { "stat", L["Type"], i.type .. ((i.subType and i.subType ~= i.type) and (", " .. i.subType) or "") } end
	if i.equipLoc and _G[i.equipLoc] and _G[i.equipLoc] ~= "" then b[#b + 1] = { "stat", L["Slot"], _G[i.equipLoc] } end
	if (i.ilvl or 0) > 0 then b[#b + 1] = { "stat", L["Item level"], tostring(i.ilvl) } end
	if (i.minLevel or 0) > 1 then b[#b + 1] = { "stat", L["Requires level"], tostring(i.minLevel) } end
	if (i.sell or 0) > 0 then b[#b + 1] = { "stat", L["Sells for"], ns.MoneyText(i.sell) } end
	-- (0.69.0, #37) a lockbox: the Lockpicking it needs, for your rogue (Almanac shows decides who sees it)
	local G = ns.Gathering
	local lock = G and G.ItemLock and G:ItemLock(id)
	local rogue, rank
	if lock then rogue, rank = G:LockRogue() end
	if rogue then
		local text = G:NeedColor(lock, rank) .. L["Lockpicking"] .. " " .. lock .. "|r"
		if rogue ~= ns.CharKey() then
			text = text .. "  |cff999999" .. (rank and rank >= lock and (L["%s can open this"]):format(ns.CharName(rogue, true)) or (L["too hard for %s yet"]):format(ns.CharName(rogue, true))) .. "|r"
		end
		b[#b + 1] = { "stat", L["Pick the lock"], text }
	end
	b[#b + 1] = { "stat", L["First found"], (HOW[rec.how or ""] or L["found"]) .. ", " .. ns.CharName(rec.b) .. ", " .. ns.DateText(rec.f) }
	local owners = ns.Items:Owners(id)
	local parts = {}
	for _, o in ipairs(owners) do parts[#parts + 1] = ns.CharName(o.key) .. (o.n > 1 and (" x" .. o.n) or "") end
	b[#b + 1] = { "stat", L["Owned by"], #parts > 0 and table.concat(parts, ", ") or (NOTE .. L["nobody now"] .. "|r") }
	-- (#55) who it would be an upgrade for
	local ups = ns.Upgrades and ns.Upgrades:Lines(i.link or id) or {}
	if #ups > 0 then
		local text = {}
		for _, ln in ipairs(ups) do text[#text + 1] = ("|cff%02x%02x%02x%s|r"):format(ln[2] * 255, ln[3] * 255, ln[4] * 255, ln[1]) end
		b[#b + 1] = { "stat", L["Upgrade for"], table.concat(text, "\n") }
	end

	-- Dropped by
	local slots, met = {}, 0
	for npc in pairs(src.creature or {}) do
		met = met + 1
		local c = ns.Store:Get("creature", npc)
		local mine = c and c.loot and c.loot[id]
		local note = ""
		if mine and (c.corpses or 0) > 0 then note = ("%d / %d (%d%%)"):format(mine, c.corpses, math.floor(mine / c.corpses * 100 + 0.5)) end
		if c and ns.Bestiary:Tier(c) >= 4 and db then
			for _, d in ipairs(db.drops) do if d.id == npc then note = note .. CLASSIC .. "  " .. (L["Classic %.1f%%"]):format(d.chance) .. "|r" end end
		end
		slots[#slots + 1] = { name = c and c.name or ("creature " .. npc), icon = W.FindIcon(W.TYPE_ICON[c and c.type or ""] or W.KIND.creature.icon), note = note,
			tip = L["Click to open in Creatures."], onClick = function() local p = ns.UI:GetPage("bestiary") if p then p:ShowCreature(npc) end end }
	end
	if #slots > 0 or (db and db.droppers > 0) then
		b[#b + 1] = { "banner", L["Dropped by"] }
		table.sort(slots, function(x, y) return x.name < y.name end)
		if #slots > 0 then b[#b + 1] = { "slots", slots } end
		if db and db.world then
			b[#b + 1] = { "small", CLASSIC .. (L["A world drop: %s carry it in Classic records."]):format(ns.N(db.droppers, "kind of creature", "kinds of creature")) .. "|r" }
		elseif db and db.droppers > met then
			b[#b + 1] = { "small", CLASSIC .. (L["%s in Classic records; you've met it on %d."]):format(ns.N(db.droppers, "kind of creature drops it", "kinds of creature drop it"), met) .. "|r" }
		end
	end

	-- Sold by
	local selling = ns.Merchants:Selling(id)
	if #selling > 0 or (db and #db.vendors > 0) then
		b[#b + 1] = { "banner", L["Sold by"] }
		local ms = {}
		for _, sl in ipairs(selling) do
			local price = ns.CostText(sl.e.price, sl.e.cost)
			local place = sl.rec.sub and sl.rec.sub ~= "" and sl.rec.sub or sl.rec.zone or "?"
			ms[#ms + 1] = { name = sl.rec.name or "?", icon = W.FindIcon(W.KIND.merchant.icon), note = price .. "  " .. NOTE .. place .. "|r",
				tip = ((sl.e.avail or -1) >= 0 and (L["Limited: %d left when checked."]):format(sl.e.avail) .. "\n" or "") .. L["Click to open in People."],
				onClick = function() local p = ns.UI:GetPage("merchants") if p then p:ShowMerchant(sl.npc) end end }
		end
		if #ms > 0 then b[#b + 1] = { "slots", ms } end
		if db and #db.vendors > #selling then
			b[#b + 1] = { "small", CLASSIC .. (L["%s sell it in Classic records; you've visited %d."]):format(ns.N(#db.vendors, "merchant", "merchants"), #selling) .. "|r" }
		end
	end

	-- Quest rewards, and quests that ask for it
	local function QuestSlot(qid, note)
		local q = ns.Store:Get("quest", qid)
		return { name = q and q.name or (L["quest %d"]):format(qid), icon = "Interface\\GossipFrame\\AvailableQuestIcon", note = note,
			tip = q and L["Click to open in Quests."] or nil,
			onClick = q and function() local p = ns.UI:GetPage("quests") if p then p:ShowQuest(qid) end end or nil }
	end
	if src.quest or (db and #db.quests > 0) then
		b[#b + 1] = { "banner", L["Quest rewards"] }
		local qs, n = {}, 0
		for qid in pairs(src.quest or {}) do
			n = n + 1
			qs[#qs + 1] = QuestSlot(qid)
		end
		table.sort(qs, function(x, y) return x.name < y.name end)
		if #qs > 0 then b[#b + 1] = { "slots", qs } end
		if db and #db.quests > n then
			b[#b + 1] = { "small", CLASSIC .. (L["%s reward it in Classic records; you've been offered %d."]):format(ns.N(#db.quests, "quest", "quests"), n) .. "|r" }
		end
	end
	local needed, seenQ = {}, {}
	for qid, q in pairs(ns.Store:Shown("quest")) do
		for _, r in ipairs(q.req or {}) do
			if r[1] == id and not seenQ[qid] then seenQ[qid] = true needed[#needed + 1] = QuestSlot(qid, "x" .. (r[2] or 1)) end
		end
	end
	for _, qid in ipairs(ns.QuestDB:ForItem(id)) do
		if not seenQ[qid] and ns.Store:Get("quest", qid) then
			seenQ[qid] = true
			local want
			for _, t in ipairs(ns.QuestDB:Get(qid).items) do if t.id == id then want = t.n end end
			needed[#needed + 1] = QuestSlot(qid, want and ("x" .. want) or nil)
		end
	end
	if #needed > 0 then
		b[#b + 1] = { "banner", L["Wanted for quests"] }
		table.sort(needed, function(x, y) return x.name < y.name end)
		b[#b + 1] = { "slots", needed }
	end

	-- Recipes you've seen that make it, or use it
	local makers, uses = {}, {}
	for sid, sp in pairs(ns.Store:Shown("spell")) do
		local entry = function(note)
			return { name = sp.name or "?", icon = sp.icon, note = note, tip = L["Click to open in Recipes."],
				onClick = function() local p = ns.UI:GetPage("trainers") if p then p:ShowSpell(sid) end end }
		end
		if sp.made == id then makers[#makers + 1] = entry(ns.Trainers:GroupName(sp.group)) end
		for _, r in ipairs(sp.reagents or {}) do
			if r[1] == id then uses[#uses + 1] = entry("x" .. (r[2] or 1) .. "  " .. ns.Trainers:GroupName(sp.group)) break end
		end
	end
	if #makers > 0 then
		table.sort(makers, function(x, y) return x.name < y.name end)
		b[#b + 1] = { "banner", L["Made by"] }
		b[#b + 1] = { "slots", makers }
	end
	if #uses > 0 then
		table.sort(uses, function(x, y) return x.name < y.name end)
		b[#b + 1] = { "banner", (L["Reagent for (%d)"]):format(#uses) }
		b[#b + 1] = { "slots", uses }
	end

	-- Other sources
	local other = {}
	for obj, n in pairs(src.object or {}) do other[#other + 1] = { "stat", IDB:ObjectName(obj, true) or (L["an object (%d)"]):format(obj), ns.Times(n) } end
	for cont, n in pairs(src.container or {}) do other[#other + 1] = { "stat", (L["Inside %s"]):format(cont ~= 0 and ItemName(cont) or L["a container"]), ns.Times(n) } end
	for map, n in pairs(src.fishing or {}) do
		local z = ns.Store:Get("zone", map)
		other[#other + 1] = { "stat", (L["Fished up in %s"]):format(z and z.name or "?"), ns.Times(n) }
	end
	if type(src.crafted) == "number" then other[#other + 1] = { "stat", L["Crafted by you"], ns.Times(src.crafted) } end
	if #other > 0 or (db and #db.objects > 0) then
		b[#b + 1] = { "banner", L["Other sources"] }
		for _, o in ipairs(other) do b[#b + 1] = o end
		if db and #db.objects > 0 then
			local metObj = 0
			for _ in pairs(src.object or {}) do metObj = metObj + 1 end
			if #db.objects > metObj then
				b[#b + 1] = { "small", CLASSIC .. (L["%s hold it in Classic records; you've looted %d."]):format(ns.N(#db.objects, "kind of chest, herb or vein", "kinds of chest, herb or vein"), metObj) .. "|r" }
			end
		end
	end
	return b
end

local function Show(id)
	shown = id
	local rec = id and ns.Store:Get("item", id)
	if not rec then
		iconButton:Hide()
		nameText:SetText("")
		typeText:SetText("")
		firstText:SetText("")
		detail:SetBlocks(nil, L["Select an item."])
		return
	end
	waiting = false
	local i = Info(id)
	iconButton:Show()
	iconButton.id = id
	iconButton.icon:SetTexture(i.icon or W.FindIcon({ "INV_Misc_QuestionMark" }))
	-- the edge shows the item's quality: its colour and a thicker line from uncommon up, else the plain thin gold
	local q = i.quality or rec.q
	local qc = type(q) == "number" and q >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] or nil
	if qc then iconButton.ring:Set(qc.r, qc.g, qc.b, true) else iconButton.ring:Set(0.62, 0.5, 0.24, false) end
	nameText:SetText(QualityHex(i.quality or rec.q) .. (i.name or rec.name or (L["item %d"]):format(id)) .. "|r")
	local parts = {}
	if i.type then parts[#parts + 1] = i.type end
	if i.subType and i.subType ~= i.type then parts[#parts + 1] = i.subType end
	if i.equipLoc and _G[i.equipLoc] and _G[i.equipLoc] ~= "" then parts[#parts + 1] = _G[i.equipLoc] end
	local line = table.concat(parts, ", ")
	typeText:SetText(line)
	firstText:SetText(NOTE .. (L["Seen %s, last %s."]):format(ns.Times(rec.n or 1), ns.AgoText(rec.l)) .. "|r")
	detail:SetBlocks(Describe(id, rec))
end

---------------------------------------------------------------------------
-- (#55, DESIGN 80) The left pane: cards (the default) or the tree, switched at the top
--   Cards: Show all; By kind (the game's item classes); By quality (only qualities found); On my
--   characters (what each carries now). A card opens the tree filtered, under "Items › <card>"
--   with the back arrow. Search jumps to the whole tree, every branch with a match unfolded.
--   The tree: kind, then its split (weapon type; armor type, then slot; consumable, trade good,
--   recipe and container sub-kinds; quest items by the quest's zone), then the items, best quality
--   and item level first. Branches start folded and their rows are only built when opened. Grey
--   (Poor) items sit in Junk at the bottom.
--   Can't use: armor and weapons your character has no skill for, or isn't the level for, are
--   tinted red and tagged.
---------------------------------------------------------------------------

local MEDIA = "Interface\\AddOns\\AzerothAlmanac\\Media\\"
local PAIR_H = 60
local view, crumb, cardFilter -- "cards" | "list"; the card's title; function(id, rec, cls) -> keep
local cardBar, backBtn, crumbText, cardsBtn, listBtn
-- folding: tree branches start folded (opened[k] = true once opened), card sections start open
local opened, foldedSections = {}, {}
local folded = setmetatable({}, {
	__index = function(_, k) if type(k) == "string" and k:sub(1, 2) == "t:" then return not opened[k] end return foldedSections[k] end,
	__newindex = function(_, k, v) if type(k) == "string" and k:sub(1, 2) == "t:" then opened[k] = (not v) or nil else foldedSections[k] = v or nil end end,
})

local function Win() return ns.db.settings.window end

-- the game's own class of an item, read at once (no server wait): cached per item
local classOf = {}
local function Class(id)
	local c = classOf[id]
	if c then return c end
	local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	local ok, _, itemType, subType, equipLoc, icon, classID, subID = pcall(instant, id)
	c = { type = ok and itemType or nil, subType = ok and subType or nil, equipLoc = ok and equipLoc or nil, icon = ok and icon or nil,
		cls = ok and classID or nil, sub = ok and subID or nil }
	classOf[id] = c
	return c
end

-- the kinds, in the tree's order: key, label, icon if none found, the game's class IDs
local KINDS = {
	{ "weapon", L["Weapons"], "INV_Sword_04", { 2 } },
	{ "armor", L["Armor"], "INV_Chest_Chain", { 4 } },
	{ "consumable", L["Consumables"], "INV_Potion_51", { 0 } },
	{ "trade", L["Trade Goods"], "INV_Fabric_Linen_01", { 7, 5, 3 } },
	{ "recipe", L["Recipes"], "INV_Scroll_03", { 9 } },
	{ "container", L["Containers"], "INV_Misc_Bag_08", { 1 } },
	{ "quest", L["Quest Items"], "INV_Misc_Note_02", { 12 } },
	{ "ammo", L["Ammunition and Quivers"], "INV_Ammo_Arrow_01", { 6, 11 } },
	{ "key", L["Keys"], "INV_Misc_Key_03", { 13 } },
	{ "misc", L["Miscellaneous"], "INV_Misc_Rune_01", { 15 } },
	{ "junk", L["Junk"], "INV_Misc_Bone_HumanSkull_01", {} },
}
local KIND_OF_CLASS, KIND_BY_KEY = {}, {}
for i, k in ipairs(KINDS) do
	KIND_BY_KEY[k[1]] = { order = i, label = k[2], icon = k[3] }
	for _, c in ipairs(k[4]) do KIND_OF_CLASS[c] = k[1] end
end
local function KindOf(id, rec)
	if (rec.q or 1) == 0 then return "junk" end
	local c = Class(id)
	return KIND_OF_CLASS[c.cls or -1] or "misc"
end

-- armor: what it's made of (or jewelry / shields), then the slot
local JEWELRY = { INVTYPE_FINGER = true, INVTYPE_NECK = true, INVTYPE_TRINKET = true, INVTYPE_CLOAK = true }
local ARMOR_ORDER = { L["Plate"], L["Mail"], L["Leather"], L["Cloth"], L["Shields"], L["Jewelry and cloaks"], L["Other"] }
local SLOT_ORDER = { "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CLOAK", "INVTYPE_CHEST", "INVTYPE_ROBE", "INVTYPE_BODY",
	"INVTYPE_TABARD", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_FINGER", "INVTYPE_TRINKET",
	"INVTYPE_SHIELD", "INVTYPE_HOLDABLE" }
local SLOT_RANK = {}
for i, k in ipairs(SLOT_ORDER) do SLOT_RANK[k] = i end
local function SlotName(loc) return (loc and _G[loc] and _G[loc] ~= "") and _G[loc] or L["Other"] end

-- an item's place in the tree: the branch under its kind, and for armor the slot under that
local function Branch(id, rec, kind)
	local c = Class(id)
	if kind == "armor" then
		local group
		if JEWELRY[c.equipLoc or ""] then group = L["Jewelry and cloaks"]
		elseif c.sub == 6 then group = L["Shields"]
		elseif c.sub == 4 then group = L["Plate"]
		elseif c.sub == 3 then group = L["Mail"]
		elseif c.sub == 2 then group = L["Leather"]
		elseif c.sub == 1 then group = L["Cloth"]
		else group = L["Other"] end
		return group, SlotName(c.equipLoc), SLOT_RANK[c.equipLoc or ""] or 99
	end
	if kind == "quest" then
		-- (by the zone of a quest that wants it, when one is known)
		for qid, q in pairs(ns.Store:Shown("quest")) do
			for _, r in ipairs(q.req or {}) do if r[1] == id then return q.zone or L["Other"] end end
		end
		return L["Other"]
	end
	if kind == "junk" or kind == "key" then return nil end
	return c.subType and c.subType ~= "" and c.subType or L["Other"]
end

-- can the character you're on use it? Armor and weapons: a skill for it (Mail and Plate Mail are
-- learned at 40, so this follows the level too), and the level it asks for. nil: no reason not to
local SKILL_FOR_WEAPON = { [0] = "Axes", [1] = "Two-Handed Axes", [2] = "Bows", [3] = "Guns", [4] = "Maces", [5] = "Two-Handed Maces",
	[6] = "Polearms", [7] = "Swords", [8] = "Two-Handed Swords", [10] = "Staves", [13] = "Fist Weapons", [15] = "Daggers",
	[16] = "Thrown", [18] = "Crossbows", [19] = "Wands" }
local SKILL_FOR_ARMOR = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate Mail", [6] = "Shield" }
local skillCache
local function Skills()
	if skillCache then return skillCache end
	local known = {}
	local n = ns.NumSkillLines and ns.NumSkillLines() or 0
	for i = 1, n do
		local name = ns.SkillLine and ns.SkillLine(i)
		if type(name) == "table" then name = name.name end
		if type(name) == "string" then known[name] = true end
	end
	skillCache = next(known) and known or false
	return skillCache
end
ns:RegisterEvent("SKILL_LINES_CHANGED", function() skillCache = nil end)
local function CantUse(id)
	local c = Class(id)
	local i = Info(id)
	if (i.minLevel or 0) > (UnitLevel("player") or 1) then return (L["Level %d"]):format(i.minLevel) end
	-- (an item only some classes can use: "Classes: Rogue" on its tooltip)
	local limit = ns.Upgrades and ns.Upgrades.ClassLimit and ns.Upgrades.ClassLimit(id)
	if limit and not limit[select(2, UnitClass("player")) or ""] then return L["Can't use"] end
	local need = (c.cls == 2 and SKILL_FOR_WEAPON[c.sub or -1]) or (c.cls == 4 and SKILL_FOR_ARMOR[c.sub or -1]) or nil
	local known = need and Skills()
	if known and not known[need] then return L["Can't use"] end
end

local function NewText(n) return (n and n > 0) and ("  |cff1eff00+" .. n .. "|r") or "" end

-- the items, as tree rows (branches folded unless opened, or unfolded by a search)
local function TreeRows()
	local rows, total, listed = {}, 0, 0
	local searching = filter ~= ""
	local tops = {}
	for id, rec in pairs(ns.Store:Shown("item")) do
		total = total + 1
		local keep = true
		if searching then keep = (rec.name or ""):lower():find(filter, 1, true) ~= nil end
		if keep and cardFilter then keep = cardFilter(id, rec) end
		if keep then
			listed = listed + 1
			local kind = KindOf(id, rec)
			local isNew = ns.New and ns.New:IsNew("items", rec) and 1 or 0
			local t = tops[kind]
			if not t then t = { kind = kind, n = 0, new = 0, subs = {}, items = {} } tops[kind] = t end
			t.n, t.new = t.n + 1, t.new + isNew
			local entry = { id = id, rec = rec, isNew = isNew == 1 or nil, newKey = id }
			local b1, b2, rank = Branch(id, rec, kind)
			if b1 then
				local s = t.subs[b1]
				if not s then s = { label = b1, n = 0, new = 0, subs = {}, items = {} } t.subs[b1] = s end
				s.n, s.new = s.n + 1, s.new + isNew
				if b2 then
					local s2 = s.subs[b2]
					if not s2 then s2 = { label = b2, n = 0, new = 0, items = {}, rank = rank } s.subs[b2] = s2 end
					s2.n, s2.new = s2.n + 1, s2.new + isNew
					table.insert(s2.items, entry)
				else
					table.insert(s.items, entry)
				end
			else
				table.insert(t.items, entry)
			end
		end
	end
	-- a card's tree with one kind in it: open at once
	local nTops = 0
	for _ in pairs(tops) do nTops = nTops + 1 end
	local function Open(key) return searching or (cardFilter and nTops == 1 and key:match("^t:[^/]*$")) or opened[key] end
	local function ByQuality(a, b)
		local qa, qb = a.rec.q or 1, b.rec.q or 1
		if qa ~= qb then return qa > qb end
		local ia, ib = Info(a.id).ilvl or 0, Info(b.id).ilvl or 0
		if ia ~= ib then return ia > ib end
		return (a.rec.name or "") < (b.rec.name or "")
	end
	local function Items(list)
		table.sort(list, ByQuality)
		for _, e in ipairs(list) do rows[#rows + 1] = e end
	end
	local function Subs(map, base, depth, armor)
		local list = {}
		for _, s in pairs(map) do list[#list + 1] = s end
		table.sort(list, function(a, b)
			if armor and depth == 1 then
				local ra, rb = 99, 99
				for i, n in ipairs(ARMOR_ORDER) do if n == a.label then ra = i end if n == b.label then rb = i end end
				if ra ~= rb then return ra < rb end
			end
			if a.rank and b.rank and a.rank ~= b.rank then return a.rank < b.rank end
			return a.label < b.label
		end)
		for _, s in ipairs(list) do
			local key = base .. "/" .. s.label
			rows[#rows + 1] = { header = s.label, key = key, count = s.n, new = s.new, depth = depth }
			if Open(key) then
				if s.subs and next(s.subs) then Subs(s.subs, key, depth + 1, armor) end
				Items(s.items)
			end
		end
	end
	local order = {}
	for _, t in pairs(tops) do order[#order + 1] = t end
	table.sort(order, function(a, b) return KIND_BY_KEY[a.kind].order < KIND_BY_KEY[b.kind].order end)
	for _, t in ipairs(order) do
		local key = "t:" .. t.kind
		rows[#rows + 1] = { header = KIND_BY_KEY[t.kind].label, key = key, count = t.n, new = t.new, depth = 0 }
		if Open(key) then
			Subs(t.subs, key, 1, t.kind == "armor")
			Items(t.items)
		end
	end
	return rows, total, listed
end

-- the cards
local function Card(icon, name, count, new, tip, action, plain)
	return { icon = icon, name = name, plain = plain or name, count = tostring(count) .. NewText(new), tip = tip, action = action }
end

local function OpenCard(label, fn)
	cardFilter, crumb, view = fn, label, "list"
	filter = ""
	if page.search then page.search:SetText("") end
	Win().itemsView = view
	page:Refresh()
	if list and list.ScrollTop then list:ScrollTop() end
end

local function BackToCards()
	cardFilter, crumb, view = nil, nil, "cards"
	Win().itemsView = view
	page:Refresh()
	if list and list.ScrollTop then list:ScrollTop() end
end

local function CardRows()
	local rows = {}
	local total, newAll = 0, 0
	local kinds, quals = {}, {}
	for id, rec in pairs(ns.Store:Shown("item")) do
		total = total + 1
		local isNew = ns.New and ns.New:IsNew("items", rec) and 1 or 0
		newAll = newAll + isNew
		local kind = KindOf(id, rec)
		local k = kinds[kind] or { n = 0, new = 0 }
		kinds[kind] = k
		k.n, k.new = k.n + 1, k.new + isNew
		-- (the card's icon: the best item of its kind)
		if not k.best or (rec.q or 1) > (k.bestQ or -1) then k.best, k.bestQ = id, rec.q or 1 end
		local q = rec.q or 1
		local qq = quals[q] or { n = 0, new = 0 }
		quals[q] = qq
		qq.n, qq.new = qq.n + 1, qq.new + isNew
		if not qq.best then qq.best = id end
	end
	if total == 0 then return rows, 0 end
	local function Section(key, text)
		rows[#rows + 1] = { card = "section", header = text, key = key }
		return not foldedSections[key]
	end
	local function Pairs(cards)
		for i = 1, #cards, 2 do rows[#rows + 1] = { card = "pair", a = cards[i], b = cards[i + 1] } end
	end
	Pairs({ Card(W.FindIcon({ "INV_Misc_Bag_10_Blue", "INV_Misc_Bag_08" }), L["Show all"], total, newAll, L["Every item you've found"], function() OpenCard(L["All items"], nil) end) })

	if Section("s:kind", L["By kind"]) then
		local cards = {}
		for _, k in ipairs(KINDS) do
			local d = kinds[k[1]]
			if d then
				local icon = Class(d.best).icon or W.FindIcon({ k[3] })
				local key = k[1]
				cards[#cards + 1] = Card(icon, k[2], d.n, d.new, k[2], function() OpenCard(k[2], function(id, rec) return KindOf(id, rec) == key end) end)
			end
		end
		Pairs(cards)
	end

	if Section("s:quality", L["By quality"]) then
		local cards = {}
		for q = 5, 0, -1 do
			local d = quals[q]
			if d then
				local name = QualityHex(q) .. QUALITY_NAMES[q] .. "|r"
				cards[#cards + 1] = Card(Class(d.best).icon or W.FindIcon({ "INV_Misc_Gem_Variety_01" }), name, d.n, d.new, QUALITY_NAMES[q],
					function() OpenCard(name, function(_, rec) return (rec.q or 1) == q end) end, QUALITY_NAMES[q])
			end
		end
		Pairs(cards)
	end

	if Section("s:chars", L["On my characters"]) then
		local cards, keys = {}, {}
		for key, c in pairs(ns.db.chars or {}) do if type(c) == "table" and c.items and next(c.items) then keys[#keys + 1] = key end end
		table.sort(keys, function(a, b) if a == ns.CharKey() then return true elseif b == ns.CharKey() then return false end return a < b end)
		for _, key in ipairs(keys) do
			local c = ns.db.chars[key]
			local n = 0
			for _ in pairs(c.items) do n = n + 1 end
			local cls = (c.classFile or ""):lower():gsub("^%l", string.upper)
			local icon = W.FindIcon({ "ClassIcon_" .. cls, "INV_Misc_Bag_08" })
			local name = ns.CharName(key)
			cards[#cards + 1] = Card(icon, name, n, 0, (L["What %s carries now (bags, bank, worn)"]):format(ns.CharName(key, true)),
				function() OpenCard(name, function(id) return c.items[id] ~= nil end) end, ns.CharName(key, true))
		end
		Pairs(cards)
	end
	return rows, total
end

local function FillCardRow(row, r)
	row.icon:SetTexture(nil)
	row.text:SetText("")
	row.right:SetText("")
	if ns.New then ns.New:MarkRow(row, false) end
	for _, c in ipairs(row.halves or {}) do c:Hide() end
	if row.banner then row.banner:Hide() end
	if r.card == "section" then
		row:SetHeader(true, foldedSections[r.key])
		row.text:SetText(r.header)
		return
	end
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
	crumbText:SetText(inCard and ("|cffffd100" .. L["Items"] .. "|r  |cff999999›|r  " .. crumb) or "")
	cardsBtn:SetActive(view == "cards")
	listBtn:SetActive(view ~= "cards")
end

-- a recipe's own page on the Recipes tab: the recipe item's name without "Recipe: ", "Pattern: " ...
local function RecipeSpell(id)
	local name = ItemName(id)
	local spell = name and name:match("^[^:]+:%s*(.+)$")
	if not spell then return nil end
	for sid, sp in pairs(ns.Store:Shown("spell")) do if sp.name == spell then return sid end end
end

function page:Build(parent, header)
	MakeCard(parent)
	view = Win().itemsView == "list" and "list" or "cards"
	-- (the Quality and "Owned now" dropdowns are gone: the cards do their job, #55)
	local search = W.Search(header, 180, function(text)
		filter = text
		-- (search looks through everything: the whole tree, every branch with a match open)
		if filter ~= "" then cardFilter, crumb, view = nil, nil, "list" end
		page:Refresh()
	end)
	search:SetPoint("LEFT", header, "LEFT", 16, -2)
	page.search = search
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
	listBtn = W.ViewButton(cardBar, "View_List", L["List"], function() cardFilter, crumb, view = nil, nil, "list" Win().itemsView = view page:Refresh() end)
	listBtn:SetPoint("RIGHT", -2, 0)
	cardsBtn = W.ViewButton(cardBar, "View_Cards", L["Cards"], function() filter = "" search:SetText("") BackToCards() end)
	cardsBtn:SetPoint("RIGHT", listBtn, "LEFT", -4, 0)
	crumbText:SetPoint("RIGHT", cardsBtn, "LEFT", -6, 0)
	local listHolder = CreateFrame("Frame", nil, left)
	listHolder:SetPoint("TOPLEFT", 0, -30)
	listHolder:SetPoint("BOTTOMRIGHT", 0, 0)
	list = W.List(listHolder, {
		rowHeight = 26,
		heightOf = function(r) if r.card == "pair" then return PAIR_H end end,
		spacers = false,
		-- (#62) the card section, or the kind of item you're scrolling through, stays pinned at the top
		sticky = function(r)
			if r.card == "section" then return { r.header, 1, 0.82, 0.3, foldedSections[r.key] } end
			if r.header and (r.depth or 0) == 0 and not r.card then return { r.header .. "  |cff999999" .. (r.count or "") .. "|r", 1, 0.82, 0.3, folded[r.key] } end
		end,
		collapse = { state = folded, key = function(r) return r.header and r.key or nil end, refresh = function() page:Refresh() end },
		emptyText = L["No items yet. Everything you loot, buy, carry or are offered is recorded here."],
		update = function(row, r)
			if r.card then FillCardRow(row, r) return end
			for _, c in ipairs(row.halves or {}) do c:Hide() end
			if r.header then
				row:SetHeader(true, folded[r.key])
				row.indent = (r.depth or 0) * 12
				row.icon:SetTexture(nil)
				row.text:SetText(r.header)
				row.right:SetText(r.count and ("|cff999999" .. r.count .. "|r" .. NewText(r.new)) or "")
				if ns.New then ns.New:MarkRow(row, false) end
				return
			end
			if ns.New then ns.New:MarkRow(row, r.isNew, "items", r.newKey) end
			local i = Info(r.id)
			if i.name and not r.rec.name then r.rec.name = i.name end   -- names arrive later for some items
			if i.quality and not r.rec.q then r.rec.q = i.quality end
			row.icon:SetTexture(i.icon or Class(r.id).icon or W.FindIcon({ "INV_Misc_QuestionMark" }))
			-- (can't use it: the game's red tint on the slot, and the reason)
			local why = CantUse(r.id)
			if row.icon.SetDesaturated then row.icon:SetDesaturated(false) end
			if why then row.icon:SetVertexColor(1, 0.3, 0.3) else row.icon:SetVertexColor(1, 1, 1) end
			row.text:SetText(QualityHex(i.quality or r.rec.q) .. (i.name or r.rec.name or ("item " .. r.id)) .. "|r")
			local lv = {}
			if (i.ilvl or 0) > 1 then lv[#lv + 1] = "|cff999999" .. (L["ilvl %d"]):format(i.ilvl) .. "|r" end
			if why then lv[#lv + 1] = "|cffff4040" .. why .. "|r"
			elseif (i.minLevel or 0) > 1 then lv[#lv + 1] = "|cff999999" .. (L["lvl %d"]):format(i.minLevel) .. "|r" end
			-- (#55) the upgrade arrow: green for you, gold for another character it can reach
			local mark = ns.Upgrades and ns.Upgrades:RowMark(i.link or r.id)
			if mark then table.insert(lv, 1, mark) end
			row.right:SetText(table.concat(lv, "  "))
		end,
		itemOf = function(r) return r.id end,
		onClick = function(r, _, mouse)
			if r.card then return end
			if r.header then
				folded[r.key] = not folded[r.key]
				page:Refresh()
				return
			end
			W.ItemModifiedClick(r.id)
			if ns.New and ns.New:Clicked("items", r) then list:Refresh() end
			-- a recipe: its page on the Recipes tab (no second page for it here)
			if Class(r.id).cls == 9 and not IsModifiedClick() then
				local sid = RecipeSpell(r.id)
				local recipes = sid and ns.UI:GetPage("trainers")
				if recipes and recipes.ShowSpell then recipes:ShowSpell(sid) return end
			end
			Show(r.id)
		end,
	})
	list:SetAllPoints(listHolder)

	detail = W.Detail(parent, 64)
	detail:SetTheme({ "Blacksmithing" }) -- the profession book's paintings behind the card and body
	detail:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
	detail:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

	-- the item's icon in a slot frame; hover for the game's tooltip, shift-click to link it, ctrl-click to try it on
	iconButton = CreateFrame("Button", nil, detail.top)
	iconButton:SetSize(46, 46)
	iconButton:SetPoint("TOPLEFT", 2, -2)
	iconButton.icon = iconButton:CreateTexture(nil, "ARTWORK")
	iconButton.icon:SetAllPoints()
	-- (0.69.2) the icon without its rim, slightly rounded corners and a thin edge (the item's quality colour from uncommon
	-- up), as the game's own, instead of the black quick-slot square
	iconButton.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	iconButton.ring = W.RoundIcon(iconButton, iconButton.icon)
	iconButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	if iconButton.ring.mask and iconButton:GetHighlightTexture().AddMaskTexture then iconButton:GetHighlightTexture():AddMaskTexture(iconButton.ring.mask) end
	iconButton:SetScript("OnEnter", function(self)
		if not self.id then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		pcall(GameTooltip.SetItemByID, GameTooltip, self.id)
		GameTooltip:Show()
	end)
	iconButton:SetScript("OnLeave", GameTooltip_Hide)
	iconButton:SetScript("OnClick", function(self)
		if self.id then W.ItemModifiedClick(Info(self.id).link or self.id) end
	end)
	W.ItemCursor(iconButton, function(self) return self.id end)

	nameText = detail.top:CreateFontString(nil, "OVERLAY")
	W.HeroFont(nameText, 26)
	nameText:SetPoint("TOPLEFT", iconButton, "TOPRIGHT", 14, 2)
	nameText:SetPoint("RIGHT", detail.top, "RIGHT", -20, 0)
	nameText:SetJustifyH("LEFT")
	typeText = detail.top:CreateFontString(nil, "OVERLAY")
	typeText:SetFontObject(GameFontHighlight)
	typeText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -4)
	typeText:SetPoint("RIGHT", detail.top, "RIGHT", -20, 0)
	typeText:SetJustifyH("LEFT")
	firstText = detail.top:CreateFontString(nil, "OVERLAY")
	firstText:SetFontObject(GameFontHighlightSmall)
	firstText:SetPoint("TOPLEFT", typeText, "BOTTOMLEFT", 0, -3)
	firstText:SetPoint("RIGHT", detail.top, "RIGHT", -20, 0)
	firstText:SetJustifyH("LEFT")
	Show(nil)
end

function page:Refresh()
	if not list then return end
	PaintBar()
	if view == "cards" then
		local rows, total = CardRows()
		list:SetData(rows)
		list:Select(nil)
		countText:SetText(ns.N(total, "item", "items"))
		if shown then Show(shown) end
		return
	end
	local rows, total, listed = TreeRows()
	local keep
	for _, r in ipairs(rows) do if r.id and r.id == shown then keep = r end end
	list:SetData(rows)
	list:Select(keep)
	countText:SetText((L["%d of %d items"]):format(listed, total))
	if shown then Show(shown) end
end

-- back to the cards (the Cards button, the back arrow)
function page:ShowCards() BackToCards() end

function page:ShowItem(id)
	ns.UI:Open("items")
	shown = id
	-- (#55) opened from another page: the tree, its branch open, so the item's row is there to see
	cardFilter, crumb, view = nil, nil, "list"
	local rec = ns.Store:Get("item", id)
	if rec then
		local kind = KindOf(id, rec)
		local b1, b2 = Branch(id, rec, kind)
		opened["t:" .. kind] = true
		if b1 then opened["t:" .. kind .. "/" .. b1] = true end
		if b1 and b2 then opened["t:" .. kind .. "/" .. b1 .. "/" .. b2] = true end
	end
	self:Refresh()
end

ns:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
	if waiting and ns.UI:IsShown() and list then
		waiting = false
		C_Timer.After(0.3, function() if list then ns.UI:Redraw(page.Refresh, page) end end) -- (#53: keeps the scroll)
	end
end)

ns:On("RESET", function() shown = nil if list then list:Select(nil) Show(nil) end end)

ns.UI:RegisterPage(page)
