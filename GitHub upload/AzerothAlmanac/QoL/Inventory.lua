-- Ported from Plus Everything (same author) for Azeroth Almanac's quality-of-life helpers.
-- Inventory: remembers every character on the account: bags, bank, equipped gear, mailbox,
-- posted auctions, professions and gold. The game only shows a character's items while you
-- play them (and the bank while it's open), so each part is saved when it's seen and dated.
-- Adds "who has this" lines to item tooltips; the window is InventoryWindow.lua.
-- Saved data is account-wide (AzerothAlmanacDB), so every character sees the others.

local _, A = ...
local ns = A.QoL
local INV = ns:NewModule("Inventory")

local ATTACHMENTS = ATTACHMENTS_MAX_RECEIVE or 16
local TOOLTIP_MAX = 8
local LOCATIONS = { "bags", "bank", "gear", "mail", "auction" }
local LOCATION_LABEL = { bags = "bags", bank = "bank", gear = "worn", mail = "mail", auction = "AH" }

local db, me
local bankOpen, mailOpen = false, false
local index -- itemID -> { charKey -> { bags = n, bank = n, ... } }, rebuilt when data changes
local pendingMail

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local Container = C_Container or {}

---------------------------------------------------------------------------
-- Items: a plain item is saved as its ID; one with an enchant or random suffix as its item string.
---------------------------------------------------------------------------

local function Compact(link)
	if not link then return end
	local itemString = link:match("|H(item:[^|]+)|h") or (link:find("^item:") and link)
	if not itemString then return end
	local id, enchant, _, _, _, _, suffix = itemString:match("^item:(%d+):?(%-?%d*):?(%-?%d*):?(%-?%d*):?(%-?%d*):?(%-?%d*):?(%-?%d*)")
	if not id then return end
	if (enchant == "" or enchant == "0") and (suffix == "" or suffix == "0") then return tonumber(id) end
	return itemString
end

function INV.ItemID(item)
	if type(item) == "number" then return item end
	return item and tonumber(item:match("^item:(%d+)"))
end

-- The bank sections worth showing. This client keeps bank items in bank tabs, but still
-- reports the old main bank container (-1) as 32 slots that are always empty; that one is
-- left out once it's empty and there's anything else to show.
function INV.VisibleBank(containers)
	local list = {}
	for _, container in ipairs(containers or {}) do
		local empty = true
		for slot in pairs(container.slots) do
			if type(slot) == "number" then empty = false break end
		end
		if not (container.id == -1 and empty and #containers > 1) then list[#list + 1] = container end
	end
	return list
end

-- A bag's display name. Bank tabs carry an internal name like "Character Bank Tab Bag (DNT)"
-- ("do not translate"); those become "Bank tab 1", "Bank tab 2", ...
function INV.BagName(name, tabNumber)
	if name and (name:find("%(DNT%)") or name:find("Bank Tab")) then return "Bank tab " .. (tabNumber or 1) end
	return name
end

-- A link for a saved item (nil while the game hasn't loaded the item yet).
function INV.Link(item)
	local _, link = GetInfo(type(item) == "number" and item or item)
	return link
end

---------------------------------------------------------------------------
-- The current character
---------------------------------------------------------------------------

local function Key(name, realm) return name .. "-" .. realm end

local function Me()
	if me then return me end
	local name, realm = UnitName("player"), GetRealmName()
	local key = Key(name, realm)
	local c = db.chars[key] or {}
	db.chars[key] = c
	c.name, c.realm = name, realm
	me = c
	me.key = key
	return me
end

local function Touch()
	index = nil
	if INV.OnChange then INV.OnChange() end
end

local function ScanBasics()
	local c = Me()
	local _, classFile, classID = UnitClass("player")
	local _, raceFile, raceID = UnitRace("player")
	c.class, c.classID = classFile, classID
	c.race, c.raceFile, c.raceID = UnitRace("player"), raceFile, raceID
	c.sex = UnitSex("player")
	c.level = UnitLevel("player")
	c.faction = UnitFactionGroup("player")
	c.money = GetMoney()
	c.seen = time()
	INV.ScanXP()
	INV.ScanLocation()
end

-- Where the character is: zone, subzone, map and position, and their hearthstone. Updated on
-- zone changes and at logout, so it's where you left them. (No position inside instances.)
function INV.ScanLocation()
	local c = Me()
	local zone = ns.Readable(GetRealZoneText())
	if not zone or zone == "" then return end -- loading screen
	c.zone, c.subzone = zone, ns.Readable(GetSubZoneText()) or ""
	c.mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
	c.x, c.y = nil, nil
	if c.mapID and C_Map.GetPlayerMapPosition then
		local ok, pos = pcall(C_Map.GetPlayerMapPosition, c.mapID, "player")
		if ok and pos then
			local x, y = pos.x, pos.y
			if pos.GetXY then x, y = pos:GetXY() end
			if x and x > 0 then c.x, c.y = x, y end
		end
	end
	c.hearth = GetBindLocation and GetBindLocation() or c.hearth
	c.locTime = time()
	Touch()
end

-- XP, rested XP and whether you're in a rest area (inn or city), saved with the time so the
-- rested XP gained since can be estimated while you play other characters.
function INV.ScanXP()
	local c = Me()
	local xp, xpMax = UnitXP("player"), UnitXPMax("player")
	-- A level that needs 0 XP means the game has let go of the character (logging out,
	-- loading): keep what was saved.
	if not xpMax or xpMax <= 0 then return end
	c.xp, c.xpMax = xp, xpMax
	c.rested = GetXPExhaustion() or 0
	c.resting = IsResting() and true or false
	c.restTime = time()
	c.maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or nil
	Touch()
end

local REST_PER_8H = 0.05       -- of a level's XP, in an inn or city
local REST_OUTSIDE = 0.25      -- ...times this when logged out anywhere else
local REST_CAP = 1.5           -- rested XP stops at 150% of a level

local MAX_CHECKS = 10          -- login checks kept per character
local MIN_CHECK_HOURS = 1      -- shorter absences are too small to measure

-- How far off the Classic rates have been on this account: the average of actual / predicted
-- rested XP gained, separately for rest areas and the open (1 until there's a check).
function INV:RateFactor(resting)
	local cal = db.restCalibration[resting and "rest" or "open"]
	if not cal or (cal.n or 0) == 0 then return 1, 0 end
	return math.max(0.2, math.min(5, cal.sum / cal.n)), cal.n
end

-- Rested XP gained over some seconds, at the calibrated rate.
local function Gain(c, seconds, resting)
	return seconds / (8 * 3600) * REST_PER_8H * c.xpMax * (resting and 1 or REST_OUTSIDE) * INV:RateFactor(resting)
end

-- Rested XP now (estimated for characters you're not playing): amount, share of a level,
-- whether it's capped. nil at max level or before the character's XP was seen.
function INV:Rested(c)
	if not c or not c.xpMax or c.xpMax <= 0 or (c.maxLevel and (c.level or 0) >= c.maxLevel) then return nil end
	local elapsed = (c.key == Me().key or not c.restTime) and 0 or math.max(0, time() - c.restTime)
	local cap = REST_CAP * c.xpMax
	local amount = math.min(cap, (c.rested or 0) + Gain(c, elapsed, c.resting))
	return amount, amount / c.xpMax, amount >= cap - 0.5, elapsed > 0
end

-- On login, before anything is updated: compare what was predicted for this character with
-- the rested XP the game actually has, keep the result, and learn the rate from it.
local function CheckRestedOnLogin()
	local c = Me()
	if not (c.restTime and c.xpMax and c.xpMax > 0 and c.level) then return end
	if c.maxLevel and c.level >= c.maxLevel then return end
	if UnitLevel("player") ~= c.level or UnitXPMax("player") ~= c.xpMax then return end -- levelled elsewhere?
	local elapsed = time() - c.restTime
	if elapsed < MIN_CHECK_HOURS * 3600 then return end
	local actual = GetXPExhaustion() or 0
	local cap = REST_CAP * c.xpMax
	local predicted = math.min(cap, (c.rested or 0) + Gain(c, elapsed, c.resting))
	c.restChecks = c.restChecks or {}
	tinsert(c.restChecks, 1, { t = time(), hours = elapsed / 3600, resting = c.resting, predicted = predicted, actual = actual })
	while #c.restChecks > MAX_CHECKS do table.remove(c.restChecks) end
	-- Learn only from checks that didn't hit the cap (a capped value says nothing about the rate).
	local classicGain = elapsed / (8 * 3600) * REST_PER_8H * c.xpMax * (c.resting and 1 or REST_OUTSIDE)
	local actualGain = actual - (c.rested or 0)
	if actual < cap - 1 and classicGain >= c.xpMax * 0.01 and actualGain >= 0 then
		local cal = db.restCalibration[c.resting and "rest" or "open"] or { sum = 0, n = 0 }
		cal.sum, cal.n = cal.sum + actualGain / classicGain, cal.n + 1
		if cal.n > 20 then cal.sum, cal.n = cal.sum / cal.n * 20, 20 end -- keep it a recent average
		db.restCalibration[c.resting and "rest" or "open"] = cal
	end
end

local function ScanContainer(bag)
	local size = Container.GetContainerNumSlots and Container.GetContainerNumSlots(bag) or 0
	if size <= 0 then return nil end
	local slots = { size = size }
	for slot = 1, size do
		local info = Container.GetContainerItemInfo(bag, slot)
		if info and (info.hyperlink or info.itemID) then
			slots[slot] = { Compact(info.hyperlink) or info.itemID, info.stackCount or 1 }
		end
	end
	if bag > 0 and C_Container.ContainerIDToInventoryID and GetInventoryItemLink then
		local ok, invID = pcall(C_Container.ContainerIDToInventoryID, bag)
		local link = ok and invID and GetInventoryItemLink("player", invID)
		slots.bag = link and Compact(link)
	end
	return slots
end

local function BagIDs()
	local ids = {}
	local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
	for bag = 0, last do ids[#ids + 1] = bag end
	local keyring = (Enum and Enum.BagIndex and Enum.BagIndex.Keyring) or KEYRING_CONTAINER
	if keyring then ids[#ids + 1] = keyring end
	return ids
end

local function BankIDs()
	local bank = (Enum and Enum.BagIndex and Enum.BagIndex.Bank) or BANK_CONTAINER or -1
	local ids = { bank }
	local first = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) + 1
	for bag = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do ids[#ids + 1] = bag end
	return ids
end

-- While logging out or on a loading screen the game reports every bag as empty (no slots).
-- Such a read must never replace what was saved, so a scan only counts if the backpack
-- (or, for the bank, the bank itself) came back with slots.
local function ScanBags()
	local c = Me()
	local bags = {}
	for _, bag in ipairs(BagIDs()) do
		local slots = ScanContainer(bag)
		if slots then bags[#bags + 1] = { id = bag, slots = slots } end
	end
	if not (bags[1] and bags[1].id == 0) then return end
	c.bags = bags
	c.bagsTime = time()
	c.money = GetMoney()
	Touch()
end

local function ScanBank()
	if not bankOpen then return end
	local c = Me()
	local bank = {}
	local bankID = BankIDs()[1]
	for _, bag in ipairs(BankIDs()) do
		local slots = ScanContainer(bag)
		if slots then bank[#bank + 1] = { id = bag, slots = slots } end
	end
	if not (bank[1] and bank[1].id == bankID) then return end
	c.bank = bank
	c.bankTime = time()
	Touch()
end

local function ScanGear()
	local c = Me()
	local gear, any = {}, false
	for slot = 0, 19 do
		local link = GetInventoryItemLink("player", slot)
		if link then
			gear[slot] = Compact(link)
			any = true
			if slot == 0 then c.ammoCount = GetInventoryItemCount("player", 0) end
		end
	end
	-- Same guard as the bags: an all-empty read (loading or logging out) keeps what was saved.
	if not any and c.gear and next(c.gear) then return end
	c.gear = gear
	c.gearTime = time()
	Touch()
end

local function ScanMail()
	if not mailOpen or not GetInboxNumItems then return end
	local c = Me()
	local mail = { items = {}, money = 0 }
	local now = time()
	for i = 1, GetInboxNumItems() do
		local _, _, sender, subject, money, cod, daysLeft, hasItem = GetInboxHeaderInfo(i)
		mail.money = mail.money + (money or 0)
		if hasItem then
			for a = 1, ATTACHMENTS do
				local link = GetInboxItemLink(i, a)
				if link then
					local _, _, _, count = GetInboxItem(i, a)
					tinsert(mail.items, { Compact(link), count or 1, sender = sender, expires = now + (daysLeft or 0) * 86400 })
				end
			end
		end
	end
	mail.time = now
	c.mail = mail
	Touch()
end

local function ScanAuctions()
	if not (C_AuctionHouse and C_AuctionHouse.GetNumOwnedAuctions) then return end
	local c = Me()
	local list = {}
	local now = time()
	for i = 1, C_AuctionHouse.GetNumOwnedAuctions() do
		local a = C_AuctionHouse.GetOwnedAuctionInfo(i)
		if a and a.status ~= 1 and a.itemLink then -- 1 = sold
			tinsert(list, { Compact(a.itemLink), a.quantity or 1, buyout = a.buyoutAmount, bid = a.bidAmount,
				ends = a.timeLeftSeconds and (now + a.timeLeftSeconds) })
		end
	end
	c.auctions = { items = list, time = now }
	Touch()
end

-- The main profession skill lines. The game can also list a same-named sub-line (another ID)
-- for a profession; only one entry per profession is kept, preferring these.
local MAIN_PROFESSIONS = { [171] = true, [164] = true, [333] = true, [202] = true, [182] = true, [165] = true,
	[186] = true, [393] = true, [197] = true, [185] = true, [129] = true, [356] = true, [762] = true }

-- One entry per profession name: the main line if listed, else the one with the higher skill.
function INV.UniqueProfessions(list)
	local byName, order = {}, {}
	for _, p in ipairs(list or {}) do
		local have = byName[p.name]
		if not have then
			byName[p.name] = p
			order[#order + 1] = p.name
		else
			local better = (MAIN_PROFESSIONS[p.id] and not MAIN_PROFESSIONS[have.id])
				or (MAIN_PROFESSIONS[p.id] == MAIN_PROFESSIONS[have.id] and (p.rank or 0) > (have.rank or 0))
			if better then byName[p.name] = p end
		end
	end
	local out = {}
	for _, name in ipairs(order) do out[#out + 1] = byName[name] end
	return out
end

local PROFESSION_HEADERS = { [TRADE_SKILLS or "Professions"] = true, [SECONDARY_SKILLS or "Secondary Skills"] = true,
	Professions = true, ["Secondary Skills"] = true }

local function ScanProfessions()
	if not (C_SkillInfo and C_SkillInfo.GetNumSkillLines) then return end
	local c = Me()
	local list, inProfessions = {}, false
	for i = 1, C_SkillInfo.GetNumSkillLines() do
		local info = C_SkillInfo.GetSkillLineInfo(i)
		if info then
			if info.isHeader then
				inProfessions = PROFESSION_HEADERS[info.name] or false
			-- (0.69.0, #37) a rogue's Lockpicking (633) too, from whichever heading it sits under
			elseif info.skillID and (inProfessions or info.skillID == 633) then
				tinsert(list, { id = info.skillID, name = info.name, rank = info.rank or 0, max = info.maxRank or 0 })
			end
		end
	end
	c.professions = INV.UniqueProfessions(list)
	c.professionsTime = time()
	Touch()
end

-- Mail you send to your own characters shows up in their mailbox before they log in.
local function CaptureSend(recipient)
	if not recipient or recipient == "" then return end
	local name, realm = recipient:match("^([^%-]+)%-?(.*)$")
	realm = (realm ~= "" and realm) or GetRealmName()
	local key = Key(name:sub(1, 1):upper() .. name:sub(2):lower(), realm)
	if not db.chars[key] or key == Me().key then return end
	local items = {}
	for a = 1, ATTACHMENTS_MAX_SEND or 12 do
		local link = GetSendMailItemLink and GetSendMailItemLink(a)
		if link then
			local _, _, _, count = GetSendMailItem(a)
			tinsert(items, { Compact(link), count or 1, sender = Me().name, expires = time() + 30 * 86400 })
		end
	end
	pendingMail = { key = key, items = items, money = GetSendMailMoney and GetSendMailMoney() or 0 }
end

local function ApplySentMail()
	local p = pendingMail
	pendingMail = nil
	if not p then return end
	local c = db.chars[p.key]
	c.mail = c.mail or { items = {}, money = 0, time = 0 }
	for _, item in ipairs(p.items) do tinsert(c.mail.items, item) end
	c.mail.money = (c.mail.money or 0) + p.money
	Touch()
end

---------------------------------------------------------------------------
-- Counting (for tooltips, crafting and the dungeon journal)
---------------------------------------------------------------------------

local function Add(t, key, loc, id, count)
	if not id then return end
	local byChar = t[id]
	if not byChar then byChar = {} t[id] = byChar end
	local e = byChar[key]
	if not e then e = {} byChar[key] = e end
	e[loc] = (e[loc] or 0) + count
end

local function BuildIndex()
	index = {}
	for key, c in pairs(db.chars) do
		for _, part in ipairs({ { "bags", c.bags }, { "bank", c.bank } }) do
			for _, container in ipairs(part[2] or {}) do
				for slot, entry in pairs(container.slots) do
					if type(slot) == "number" then Add(index, key, part[1], INV.ItemID(entry[1]), entry[2]) end
				end
			end
		end
		for slot, item in pairs(c.gear or {}) do
			Add(index, key, "gear", INV.ItemID(item), slot == 0 and (c.ammoCount or 1) or 1)
		end
		for _, entry in ipairs(c.mail and c.mail.items or {}) do Add(index, key, "mail", INV.ItemID(entry[1]), entry[2]) end
		for _, entry in ipairs(c.auctions and c.auctions.items or {}) do Add(index, key, "auction", INV.ItemID(entry[1]), entry[2]) end
	end
	return index
end

-- { { key, char, total, parts = { bags = n, ... } }, ... } for an item, most first. Hidden characters left out.
function INV:WhoHas(itemID)
	local byChar = (index or BuildIndex())[itemID]
	local out = {}
	for key, parts in pairs(byChar or {}) do
		if not db.hidden[key] then
			local total = 0
			for _, n in pairs(parts) do total = total + n end
			tinsert(out, { key = key, char = db.chars[key], total = total, parts = parts })
		end
	end
	table.sort(out, function(a, b) return a.total > b.total end)
	return out
end

-- How many of an item your other (shown) characters have.
function INV:CountOnAlts(itemID)
	local n = 0
	for _, e in ipairs(self:WhoHas(itemID)) do
		if e.key ~= Me().key then n = n + e.total end
	end
	return n
end

function INV:ClassColor(c)
	local color = c and c.class and (RAID_CLASS_COLORS or {})[c.class]
	if color then return color.r, color.g, color.b end
	return 0.9, 0.9, 0.9
end

local function Breakdown(parts)
	local bits = {}
	for _, loc in ipairs(LOCATIONS) do
		if parts[loc] then bits[#bits + 1] = ("%s %d"):format(LOCATION_LABEL[loc], parts[loc]) end
	end
	return table.concat(bits, ", ")
end
INV.Breakdown = Breakdown

local function AddTooltipLines(tooltip)
	if not db.tooltip or not tooltip.GetItem then return end
	local _, link = tooltip:GetItem()
	link = ns.Readable(link)
	local id = link and tonumber(link:match("item:(%d+)"))
	if not id then return end
	local list = INV:WhoHas(id)
	if #list == 0 then return end
	local total = 0
	for i, e in ipairs(list) do
		total = total + e.total
		if i <= TOOLTIP_MAX then
			local r, g, b = INV:ClassColor(e.char)
			tooltip:AddDoubleLine(("%s |cff999999(%s)|r"):format(e.char.name, Breakdown(e.parts)), e.total, r, g, b, 1, 1, 1)
		end
	end
	if #list > TOOLTIP_MAX then tooltip:AddLine(("  ...and %d more characters"):format(#list - TOOLTIP_MAX), 0.6, 0.6, 0.6) end
	if #list > 1 then tooltip:AddDoubleLine("Total", total, 1, 0.82, 0, 1, 1, 1) end
end

---------------------------------------------------------------------------
-- Module API
---------------------------------------------------------------------------

function INV:OnInitialize(saved)
	db = saved.inventory
	db.restCalibration = db.restCalibration or {}
end

function INV:OnLogin()
	CheckRestedOnLogin() -- before ScanBasics overwrites what was saved at logout
	ScanBasics()
	ScanGear()
	ScanBags()
	ScanProfessions()

	local events = CreateFrame("Frame")
	local handlers = {
		BAG_UPDATE_DELAYED = function() ScanBags() ScanBank() end,
		PLAYERBANKSLOTS_CHANGED = ScanBank,
		PLAYERBANKBAGSLOTS_CHANGED = ScanBank,
		BANKFRAME_OPENED = function() bankOpen = true ScanBank() end,
		BANKFRAME_CLOSED = function() ScanBank() bankOpen = false end,
		PLAYER_EQUIPMENT_CHANGED = ScanGear,
		UNIT_INVENTORY_CHANGED = function(unit) if unit == "player" then ScanGear() end end,
		PLAYER_MONEY = ScanBasics,
		PLAYER_XP_UPDATE = function() INV.ScanXP() end,
		ZONE_CHANGED = function() INV.ScanLocation() end,
		ZONE_CHANGED_INDOORS = function() INV.ScanLocation() end,
		ZONE_CHANGED_NEW_AREA = function() INV.ScanLocation() end,
		PLAYER_ENTERING_WORLD = function() C_Timer.After(1, INV.ScanLocation) end,
		HEARTHSTONE_BOUND = function() INV.ScanLocation() end,
		UPDATE_EXHAUSTION = function() INV.ScanXP() end,
		PLAYER_UPDATE_RESTING = function() INV.ScanXP() end,
		PLAYER_LEVEL_UP = function() C_Timer.After(0.5, ScanBasics) end,
		MAIL_SHOW = function() mailOpen = true end,
		MAIL_INBOX_UPDATE = ScanMail,
		MAIL_CLOSED = function() ScanMail() mailOpen = false end,
		MAIL_SEND_SUCCESS = ApplySentMail,
		MAIL_FAILED = function() pendingMail = nil end,
		OWNED_AUCTIONS_UPDATED = ScanAuctions,
		AUCTION_HOUSE_SHOW = function() if C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions then pcall(C_AuctionHouse.QueryOwnedAuctions, {}) end end,
		SKILL_LINES_CHANGED = ScanProfessions,
		-- At logout the game already reports empty bags, 0 XP and 0 gold, so nothing is read
		-- then (it's all saved as it changes); only the time is noted, for the rested estimate.
		PLAYER_LOGOUT = function()
			local c = Me()
			c.restTime, c.seen = time(), time()
		end,
	}
	for event in pairs(handlers) do pcall(events.RegisterEvent, events, event) end
	events:SetScript("OnEvent", function(_, event, ...) handlers[event](...) end)
	if SendMail then hooksecurefunc("SendMail", CaptureSend) end

	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip) AddTooltipLines(tooltip) end)
	else
		for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
			tooltip:HookScript("OnTooltipSetItem", function(self) AddTooltipLines(self) end)
		end
	end
end

-- Characters for the window: shown ones first by realm, then hidden ones (when asked for).
function INV:Characters(includeHidden)
	local list = {}
	for key, c in pairs(db.chars) do
		if includeHidden or not db.hidden[key] then
			c.key = key
			tinsert(list, c)
		end
	end
	table.sort(list, function(a, b)
		if (a.realm or "") ~= (b.realm or "") then return (a.realm or "") < (b.realm or "") end
		if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
		return a.name < b.name
	end)
	return list
end

function INV:Me() return Me() end
function INV:IsHidden(key) return db.hidden[key] and true or false end

function INV:SetHidden(key, hidden)
	db.hidden[key] = hidden or nil
	Touch()
end

function INV:Remove(key)
	if key == Me().key then return end
	db.chars[key] = nil
	db.hidden[key] = nil
	Touch()
end

function INV:TotalMoney()
	local total = 0
	for key, c in pairs(db.chars) do
		if not db.hidden[key] then total = total + (c.money or 0) end
	end
	return total
end

function INV:Settings() return db end
