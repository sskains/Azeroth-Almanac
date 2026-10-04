-- Items: every item a character comes across, and how.
--   Looted (with what it came from: a creature, an object such as a herb, vein or chest, an item
--   such as a clam or lockbox, or fishing), received (quest, mail, trade, crafted), bought, seen on
--   a merchant, offered as a quest reward, or carried (bags, bank, equipped).
-- found.item[itemID] = { q = quality, how = first way it was found,
--   src = { creature = { [npc] = n }, object = { [objectID] = n }, container = { [itemID] = n },
--           fishing = { [mapID] = n }, merchant = { [npc] = true }, quest = { [questID] = title },
--           crafted = n } }
-- Each character's current belongings: chars[key].items = { [itemID] = count } (bags, bank, worn).
-- New items of uncommon quality and up go in the journal; everything is in the Items page.

local _, ns = ...
local L = ns.L
local Items = ns:NewModule("Items")
local R = ns.Readable

local Container = C_Container or {}

local function ItemID(link)
	link = R(link)
	if type(link) ~= "string" then return nil end
	return tonumber(link:match("item:(%d+)"))
end

local function Quality(id)
	local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local ok, _, _, quality = pcall(getInfo, id)
	return ok and quality or nil
end

local function Name(id)
	local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local ok, name = pcall(getInfo, id)
	return ok and name or nil
end

-- how: "looted", "received", "crafted", "bought", "merchant", "reward", "carried"
-- src: { kind, id, value } added to the item's sources
function Items:Found(id, how, srcKind, srcID, srcValue, where)
	if not id then return end
	local quality = Quality(id)
	local name = Name(id)
	-- carried and on-sale items are recorded quietly: the journal is for things you went and found
	-- (and a reward you were only offered isn't yours yet)
	local quiet = how == "carried" or how == "merchant" or how == "reward" or (quality ~= nil and quality < 2)
	local existing = ns.Store:Get("item", id)
	local rec = ns.Store:Discover("item", id, { q = quality, name = name }, name or (L["item %d"]):format(id), where, quiet)
	if not rec then return end
	if not existing then rec.how = how end
	if srcKind then
		rec.src = rec.src or {}
		local s = rec.src[srcKind] or {}
		rec.src[srcKind] = s
		if srcKind == "crafted" then
			rec.src.crafted = (type(rec.src.crafted) == "number" and rec.src.crafted or 0) + 1
		elseif srcValue ~= nil then
			s[srcID] = srcValue
		else
			s[srcID] = (type(s[srcID]) == "number" and s[srcID] or 0) + 1
		end
	end
	return rec
end

---------------------------------------------------------------------------
-- Loot window: what each slot came from
---------------------------------------------------------------------------

local function OnLoot()
	if not (GetNumLootItems and GetLootSourceInfo) then return end
	local fishing = R(IsFishingLoot and IsFishingLoot()) == true
	local where = ns.Where()
	for slot = 1, GetNumLootItems() do
		local id = ItemID(GetLootSlotLink(slot))
		if id then
			local sources = { pcall(GetLootSourceInfo, slot) }
			local recorded = false
			if sources[1] then
				for i = 2, #sources, 2 do
					local kind, sid = ns.ParseGuid(sources[i])
					if fishing then
						Items:Found(id, "looted", "fishing", where.map or 0, nil, where)
						recorded = true
					elseif kind == "Creature" or kind == "Vehicle" then
						Items:Found(id, "looted", "creature", sid, nil, where)
						recorded = true
					elseif kind == "GameObject" then
						Items:Found(id, "looted", "object", sid, nil, where)
						recorded = true
					elseif kind == "Item" then
						-- an opened container: the item's GUID doesn't name the item, so the last item used is taken
						Items:Found(id, "looted", "container", Items.lastOpened or 0, nil, where)
						recorded = true
					end
				end
			end
			if not recorded then Items:Found(id, "looted", nil, nil, nil, where) end
		end
	end
end

---------------------------------------------------------------------------
-- Chat: items received (quest rewards handed over, mail, trade) and created (crafting)
---------------------------------------------------------------------------

-- the game's own message patterns: "You create: %s." / "You receive item: %s."
local function Pattern(fmt)
	if type(fmt) ~= "string" then return nil end
	fmt = fmt:gsub("%%d", "\1"):gsub("%%s", "\2")
	fmt = fmt:gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0")
	fmt = fmt:gsub("\1", "(%%d+)"):gsub("\2", "(.+)")
	return "^" .. fmt
end
local CREATED = { Pattern(LOOT_ITEM_CREATED_SELF), Pattern(LOOT_ITEM_CREATED_SELF_MULTIPLE) }
local RECEIVED = { Pattern(LOOT_ITEM_PUSHED_SELF), Pattern(LOOT_ITEM_PUSHED_SELF_MULTIPLE) }

ns:RegisterEvent("CHAT_MSG_LOOT", function(_, msg, ...)
	if not ns.db then return end
	msg = R(msg)
	if type(msg) ~= "string" then return end
	local id = ItemID(msg)
	if not id then return end
	for _, p in ipairs(CREATED) do
		if p and msg:match(p) then return Items:Found(id, "crafted", "crafted") end
	end
	for _, p in ipairs(RECEIVED) do
		if p and msg:match(p) then return Items:Found(id, "received") end
	end
	-- plain "You receive loot" lines are handled by the loot window
end)

---------------------------------------------------------------------------
-- Quest rewards (offered and chosen) and merchants' stock
---------------------------------------------------------------------------

local function QuestRewards()
	local qid = R(GetQuestID and GetQuestID())
	local title = R(GetTitleText and GetTitleText())
	if not qid or qid == 0 then return end
	for _, kind in ipairs({ "reward", "choice" }) do
		local n = kind == "reward" and (GetNumQuestRewards and GetNumQuestRewards() or 0) or (GetNumQuestChoices and GetNumQuestChoices() or 0)
		for i = 1, R(n) or 0 do
			local id = ItemID(GetQuestItemLink(kind, i))
			if id then Items:Found(id, "reward", "quest", qid, title or true) end
		end
	end
end
ns:RegisterEvent("QUEST_DETAIL", function() if ns.db then QuestRewards() end end)
ns:RegisterEvent("QUEST_COMPLETE", function() if ns.db then QuestRewards() end end)

-- the container you just opened (for "found inside a clam")
if hooksecurefunc and C_Container and C_Container.UseContainerItem then
	hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
		local id = Container.GetContainerItemID and Container.GetContainerItemID(bag, slot)
		if id then Items.lastOpened = id end
	end)
end

---------------------------------------------------------------------------
-- Belongings: bags, bank, equipped
---------------------------------------------------------------------------

local function ScanBags(bags, into)
	for _, bag in ipairs(bags) do
		local size = Container.GetContainerNumSlots and Container.GetContainerNumSlots(bag) or 0
		for slot = 1, size do
			local info = Container.GetContainerItemInfo and Container.GetContainerItemInfo(bag, slot)
			local id = info and R(info.itemID)
			if id then into[id] = (into[id] or 0) + (R(info.stackCount) or 1) end
		end
	end
end

local bankItems = nil -- what was in the bank the last time it was open (kept per session)
local function Belongings()
	local c = ns.db.chars[ns.CharKey()]
	if not c then return end
	local items = {}
	local bags = {}
	for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do bags[#bags + 1] = bag end
	ScanBags(bags, items)
	for slot = 0, 19 do
		local id = GetInventoryItemID and GetInventoryItemID("player", slot)
		if id then items[id] = (items[id] or 0) + 1 end
	end
	local bank = c.bank or {}
	if bankItems then bank = bankItems end
	for id, n in pairs(bank) do items[id] = (items[id] or 0) + n end
	c.items = items
	c.bank = bank
	for id in pairs(items) do
		if not ns.Store:Get("item", id) then Items:Found(id, "carried") end
	end
	ns:Fire("CHANGED", "item")
end

local function ScanBank()
	local bags = { (Enum and Enum.BagIndex and Enum.BagIndex.Bank) or BANK_CONTAINER or -1 }
	local first = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) + 1
	for bag = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do bags[#bags + 1] = bag end
	bankItems = {}
	ScanBags(bags, bankItems)
end

local pending = false
local function Soon()
	if pending or not ns.db then return end
	pending = true
	C_Timer.After(1, function()
		pending = false
		ns.doing = "reading your bags"
		Belongings()
		ns.doing = "idle"
	end)
end

ns:RegisterEvent("BAG_UPDATE_DELAYED", Soon)
ns:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", Soon)
ns:RegisterEvent("BANKFRAME_OPENED", function() if ns.db then ScanBank() Soon() end end)
ns:RegisterEvent("PLAYERBANKSLOTS_CHANGED", function() if ns.db then ScanBank() Soon() end end)
ns:RegisterEvent("LOOT_READY", function()
	if not ns.db then return end
	ns.doing = "reading loot (items)"
	OnLoot()
	ns.doing = "idle"
end)

function Items:OnLogin()
	C_Timer.After(3, Soon)
end

-- who on the account has this item now: { { key, count }, ... }
function Items:Owners(id)
	local out = {}
	for key, c in pairs(ns.db.chars) do
		local n = c.items and c.items[id]
		if n then out[#out + 1] = { key = key, n = n } end
	end
	table.sort(out, function(a, b) return a.n > b.n end)
	return out
end

-- item names and quality arrive from the server a moment after first asked for: fill them in
ns:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(_, id)
	id = R(id)
	if not (ns.db and id) then return end
	local rec = ns.Store:Get("item", id)
	if rec and not rec.name then
		rec.name = Name(id)
		rec.q = rec.q or Quality(id)
	end
end)
