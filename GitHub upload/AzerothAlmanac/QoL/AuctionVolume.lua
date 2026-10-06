-- Ported from Plus Everything (same author) for Azeroth Almanac's quality-of-life helpers.
-- Auction volume: estimates how many of each craftable item sell per day.
-- The game never reports other players' sales, so each full scan keeps a fingerprint of every
-- listing of the items you can craft (stack, buyout, seller, time left). On the next scan, a
-- listing that's gone although it couldn't have expired yet counts as sold (cancels look the
-- same, so it's an estimate). Sales are divided by the time actually watched between scans
-- and scaled to a day, over the last 7 days.
-- Shared with guildmates running Azeroth Almanac: sales (fingerprinted, so a sale seen twice counts
-- once), the watched time, and the lowest prices, which also update your auction prices.

local _, A = ...
local ns = A.QoL
local AV = ns:NewModule("AuctionVolume")

local KEEP_DAYS = 7
local MAX_GAP = 6 * 3600           -- scans further apart than this aren't compared
local MIN_GAP = 60
local MIN_WATCHED = 3600           -- need an hour of watched time before giving a number
local PREFIX = "AzAlmAH"
local SEND_INTERVAL = 1.1 -- (the game lets a prefix send about one message a second; faster ones are dropped)
local MAX_MESSAGE = 240
-- Least time an auction still had, by the game's time-left bucket (short, medium, long, very long).
local MIN_REMAINING = { 0, 30 * 60, 2 * 3600, 12 * 3600 }

local db, current, outbox
local myName

local function Now() return GetServerTime and GetServerTime() or time() end
local function Day(t) return math.floor(t / 86400) end

local function Hash(s)
	local h = 5381
	for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
	return ("%x"):format(h)
end

local function RealmKey()
	return (GetRealmName() or "?") .. " - " .. (UnitFactionGroup("player") or "?")
end

local function Realm()
	local key = RealmKey()
	local r = db.realms[key]
	if not r then
		r = { cover = {}, sales = {}, listed = {} }
		db.realms[key] = r
	end
	return r
end

-- Items tracked: everything made by a recipe Azeroth Almanac has seen (see Crafting.lua).
local function Tracked()
	return ns.db.crafting and ns.db.crafting.recipes or {}
end

---------------------------------------------------------------------------
-- Watched time and sales
---------------------------------------------------------------------------

-- Adds [t1, t2] to an item's watched intervals, merging overlaps and dropping old ones.
local function AddCover(r, id, t1, t2)
	local list = r.cover[id] or {}
	list[#list + 1] = { t1, t2 }
	table.sort(list, function(a, b) return a[1] < b[1] end)
	local merged, cutoff = {}, Now() - KEEP_DAYS * 86400
	for _, w in ipairs(list) do
		if w[2] > cutoff then
			local last = merged[#merged]
			if last and w[1] <= last[2] then
				if w[2] > last[2] then last[2] = w[2] end
			else
				merged[#merged + 1] = { w[1], w[2] }
			end
		end
	end
	r.cover[id] = merged
end

local function AddSale(r, id, day, hash, units)
	r.sales[id] = r.sales[id] or {}
	local days = r.sales[id]
	days[day] = days[day] or {}
	days[day][hash] = units
end

local function Prune(r)
	local oldest = Day(Now()) - KEEP_DAYS
	for id, days in pairs(r.sales) do
		for day in pairs(days) do
			if day < oldest then days[day] = nil end
		end
		if not next(days) then r.sales[id] = nil end
	end
end

-- Estimated sales per day, and details: { hours, days, listed = { n, auctions, sellers, t } }.
function AV:DailyVolume(id)
	local r = Realm()
	local cover = r.cover[id]
	local watched, first = 0, nil
	for _, w in ipairs(cover or {}) do
		watched = watched + (w[2] - w[1])
		first = first and math.min(first, w[1]) or w[1]
	end
	local info = { hours = watched / 3600, listed = r.listed[id], days = first and math.max(1, Day(Now()) - Day(first) + 1) or 0 }
	if watched < MIN_WATCHED then return nil, info end
	local units = 0
	for _, hashes in pairs(r.sales[id] or {}) do
		for _, u in pairs(hashes) do units = units + u end
	end
	return units / watched * 86400, info
end

-- "~12/d", "<1/d" or nil
function AV:ShortVolume(id)
	local perDay = self:DailyVolume(id)
	if not perDay then return nil end
	if perDay < 1 then return "<1/d" end
	return ("~%d/d"):format(math.floor(perDay + 0.5))
end

---------------------------------------------------------------------------
-- Scans (called by AuctionPrices)
---------------------------------------------------------------------------

function AV:OnScanStart()
	current = { items = {}, lows = {} }
	for id in pairs(Tracked()) do current.items[id] = {} end
end

function AV:OnListing(itemID, count, buyout, owner, timeLeft)
	if not current then return end
	local list = current.items[itemID]
	if not list then return end
	-- %.0f, not %d: this client's string.format only takes %d up to 2^31, and joke listings go far higher.
	list[#list + 1] = ("%d:%.0f:%s:%d"):format(count, buyout, owner or "?", timeLeft or 4)
	local unit = buyout / count
	if not current.lows[itemID] or unit < current.lows[itemID] then current.lows[itemID] = unit end
end

-- Counts identical listings so each copy gets its own fingerprint ("base#1", "base#2").
local function Fingerprints(list)
	local seen, out = {}, {}
	for _, entry in ipairs(list) do
		local base, tl = entry:match("^(.*):(%d+)$")
		seen[base] = (seen[base] or 0) + 1
		out[#out + 1] = { base = base, tl = tonumber(tl), key = base .. "#" .. seen[base], units = tonumber(base:match("^(%d+)")) }
	end
	return out
end

local Share -- forward

function AV:OnScanDone()
	if not current then return end
	local r, now = Realm(), Now()
	local prev = r.snap
	local gap = prev and (now - prev.t)
	local found = {} -- id -> { { hash, units }, ... } sold since the last scan
	local watchedIDs = {}
	if prev and gap >= MIN_GAP and gap <= MAX_GAP then
		for id, oldList in pairs(prev.items) do
			local newList = current.items[id]
			if newList then
				watchedIDs[#watchedIDs + 1] = id
				AddCover(r, id, prev.t, now)
				local remaining = {}
				for _, entry in ipairs(newList) do
					local base = entry:match("^(.*):%d+$")
					remaining[base] = (remaining[base] or 0) + 1
				end
				for _, fp in ipairs(Fingerprints(oldList)) do
					if (remaining[fp.base] or 0) > 0 then
						remaining[fp.base] = remaining[fp.base] - 1
					elseif (MIN_REMAINING[fp.tl] or 0) > gap then
						local hash = Hash(id .. ":" .. fp.key)
						AddSale(r, id, Day(now), hash, fp.units)
						found[id] = found[id] or {}
						table.insert(found[id], { hash, fp.units })
					end
				end
			end
		end
	end
	for id, list in pairs(current.items) do
		local units, sellers = 0, {}
		for _, entry in ipairs(list) do
			local count, owner = entry:match("^(%d+):%d+:(.*):%d+$")
			units = units + tonumber(count)
			if owner ~= "?" and owner ~= "" then sellers[owner] = true end -- seller names aren't always sent
		end
		local nSellers = 0
		for _ in pairs(sellers) do nSellers = nSellers + 1 end
		r.listed[id] = { units, #list, nSellers, now }
	end
	r.snap = { t = now, items = current.items }
	Prune(r)
	if db.share and IsInGuild and IsInGuild() then Share(prev and prev.t, now, watchedIDs, found, current.lows) end
	current = nil
	if ns.Crafting and ns.Crafting.Refresh then ns.Crafting:Refresh() end
end

function AV:OnScanAbort()
	current = nil
end

---------------------------------------------------------------------------
-- Guild sharing
---------------------------------------------------------------------------

local function Queue(kind, head, parts)
	local line = ""
	for _, part in ipairs(parts) do
		if #line + #part + 1 > MAX_MESSAGE - #head then
			tinsert(outbox, kind .. "|" .. head .. line)
			line = ""
		end
		line = line .. (line == "" and "" or ",") .. part
	end
	if line ~= "" then tinsert(outbox, kind .. "|" .. head .. line) end
end

function Share(t1, t2, watchedIDs, found, lows)
	local realm = Hash(RealmKey())
	if t1 and #watchedIDs > 0 then
		local ids = {}
		for _, id in ipairs(watchedIDs) do ids[#ids + 1] = tostring(id) end
		Queue("W", ("%s|%d|%d|"):format(realm, t1, t2), ids)
	end
	local sales = {}
	for id, list in pairs(found) do
		for _, s in ipairs(list) do sales[#sales + 1] = ("%d:%s:%d"):format(id, s[1], s[2]) end
	end
	if #sales > 0 then Queue("S", ("%s|%d|"):format(realm, Day(t2)), sales) end
	local prices = {}
	for id, p in pairs(lows) do prices[#prices + 1] = ("%d:%.0f"):format(id, p) end
	if #prices > 0 then Queue("P", ("%s|%d|"):format(realm, t2), prices) end
end

local function Receive(text, sender)
	if Ambiguate(sender, "none") == myName then return end
	local kind, realm, rest = text:match("^(%a)|(%x+)|(.*)$")
	if not kind or realm ~= Hash(RealmKey()) then return end
	local r, tracked = Realm(), Tracked()
	if kind == "W" then
		local t1, t2, ids = rest:match("^(%d+)|(%d+)|(.*)$")
		t1, t2 = tonumber(t1), tonumber(t2)
		if not t1 or t2 - t1 > MAX_GAP or t2 > Now() + 600 then return end
		for id in ids:gmatch("%d+") do
			id = tonumber(id)
			if tracked[id] then AddCover(r, id, t1, t2) end
		end
	elseif kind == "S" then
		local day, list = rest:match("^(%d+)|(.*)$")
		day = tonumber(day)
		if not day then return end
		for id, hash, units in list:gmatch("(%d+):(%x+):(%d+)") do
			id = tonumber(id)
			if tracked[id] then AddSale(r, id, day, hash, tonumber(units)) end
		end
	elseif kind == "P" then
		local t, list = rest:match("^(%d+)|(.*)$")
		t = tonumber(t)
		if not t or not ns.AuctionPrices.ApplySharedPrice then return end
		local localTime = t - Now() + time() -- the sender's server time on this machine's clock
		for id, price in list:gmatch("(%d+):(%d+)") do
			ns.AuctionPrices:ApplySharedPrice(tonumber(id), tonumber(price), localTime)
		end
	end
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------

local function AddTooltipLines(tooltip)
	if not db.tooltip or not tooltip.GetItem then return end
	local _, link = tooltip:GetItem()
	link = ns.Readable(link)
	local id = link and tonumber(link:match("item:(%d+)"))
	if not id or not Tracked()[id] then return end
	local perDay, info = AV:DailyVolume(id)
	if perDay then
		tooltip:AddDoubleLine("Sells about", ("%s a day |cff999999(%.1fh watched)|r"):format(
			perDay < 1 and "<1" or ("~" .. math.floor(perDay + 0.5)), info.hours), 1, 0.82, 0, 1, 1, 1)
	else
		tooltip:AddDoubleLine("Sells about", "|cff999999not enough scans yet|r", 1, 0.82, 0, 1, 1, 1)
	end
	local listed = info.listed
	if listed then
		local sellers = listed[3] > 0 and (", %d sellers"):format(listed[3]) or ""
		tooltip:AddDoubleLine("Listed at last scan", ("%d |cff999999(%d auctions%s)|r"):format(listed[1], listed[2], sellers),
			1, 0.82, 0, 1, 1, 1)
	end
end

---------------------------------------------------------------------------
-- Module API
---------------------------------------------------------------------------

function AV:OnInitialize(saved)
	db = saved.auctionVolume
end

function AV:OnLogin()
	myName = UnitName("player")
	outbox = {}
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
	local events = CreateFrame("Frame")
	events:RegisterEvent("CHAT_MSG_ADDON")
	events:SetScript("OnEvent", function(_, _, prefix, text, channel, sender)
		if prefix == PREFIX and channel == "GUILD" and db.share then Receive(text, sender) end
	end)
	-- Send queued messages a few at a time.
	C_Timer.NewTicker(SEND_INTERVAL, function()
		local text = table.remove(outbox, 1)
		if text and C_ChatInfo and C_ChatInfo.SendAddonMessage then C_ChatInfo.SendAddonMessage(PREFIX, text, "GUILD") end
	end)
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip) AddTooltipLines(tooltip) end)
	else
		for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
			tooltip:HookScript("OnTooltipSetItem", function(self) AddTooltipLines(self) end)
		end
	end
end

function AV:Status()
	local r = Realm()
	local items, hours = 0, 0
	for _, list in pairs(r.cover) do
		items = items + 1
		local h = 0
		for _, w in ipairs(list) do h = h + (w[2] - w[1]) / 3600 end
		hours = math.max(hours, h)
	end
	return items, hours
end

function AV:Forget()
	db.realms[RealmKey()] = nil
end
