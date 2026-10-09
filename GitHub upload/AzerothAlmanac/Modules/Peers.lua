-- Almanac players: finds the other players running Azeroth Almanac, so Almanac features that need
-- two players (Murloc Tac Toe, and more later) know who can take part. A small badge on their
-- tooltip ("Almanac", in red, with the Almanac's icon) is all that shows.
--
-- Hidden addon messages (prefix AzAlmHi), one line each:
--   H|version   "hello, who's here?"  answered once, by whisper, with I
--   I|version   "I'm here"            never answered
-- Who gets a hello: the guild at login, the group when it changes, online friends (spaced out), and
-- a player you target or mouse over (once in a while each). No realm-wide channel.
-- A newer version seen on someone else's copy brings up the "New Version Available" quest
-- (UI/UpdateQuest.lua), once per version.
-- Settings (AzerothAlmanacDB.settings.peers): share (answer and say hello), tooltip, nudge.
-- Known players (AzerothAlmanacDB.peers): [key] = { n = name, v = version, via = how, t = last seen }.

local _, ns = ...
local P = ns:NewModule("Peers")
local L = ns.L

local PREFIX = "AzAlmHi"
local REPLY_GAP = 60          -- seconds before answering the same player again
local PING_GAP = 600          -- seconds before saying hello to the same player again (targets, friends)
local FORGET = 30 * 86400     -- players not heard from in 30 days are dropped
local TOOLTIP_DAYS = 30

local known                   -- ns.db.peers
local lastReply, lastPing = {}, {}
local queue, sending = {}, false
local nudgedThisSession = {}

local function S() return ns.db.settings.peers end

---------------------------------------------------------------------------
-- Names: compared without case, spaces or hyphens (Forever surnames), your own realm dropped
---------------------------------------------------------------------------

local function Realm()
	return (GetNormalizedRealmName and GetNormalizedRealmName()) or ((GetRealmName and GetRealmName()) or ""):gsub("%s", "")
end

local function Key(name)
	if type(name) ~= "string" or name == "" then return nil end
	name = name:lower()
	local realm = Realm():lower()
	if realm ~= "" and name:sub(-#realm - 1) == "-" .. realm then name = name:sub(1, -#realm - 2) end
	return (name:gsub("[%s%-]", ""))
end
P.Key = Key

local function UnitFull(unit)
	local name, realm = UnitName(unit)
	if not name then return nil end
	if realm and realm ~= "" then return name .. "-" .. realm end
	return name
end

local function IsMe(name)
	return Key(name) == Key(UnitName("player"))
end

---------------------------------------------------------------------------
-- Versions
---------------------------------------------------------------------------

local function Parts(v)
	local t = {}
	for n in tostring(v or ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end
	return t
end

-- true when a is newer than b
function P.Newer(a, b)
	local x, y = Parts(a), Parts(b)
	if #x == 0 then return false end
	for i = 1, math.max(#x, #y) do
		local p, q = x[i] or 0, y[i] or 0
		if p ~= q then return p > q end
	end
	return false
end

---------------------------------------------------------------------------
-- Sending (a short queue, so a big friends list doesn't go out all at once)
---------------------------------------------------------------------------

local function Pump()
	local item = table.remove(queue, 1)
	if not item then sending = false return end
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		pcall(C_ChatInfo.SendAddonMessage, PREFIX, item[1], item[2], item[3])
	end
	C_Timer.After(1.1, Pump) -- (about one a second: the game's addon-message allowance)
end

local function Send(text, channel, target)
	if not S().share then return end
	queue[#queue + 1] = { text, channel, target }
	if not sending then
		sending = true
		Pump()
	end
end

local function Hello(channel, target)
	Send("H|" .. ns.VERSION, channel, target)
end

local function HelloTo(name)
	local key = Key(name)
	if not key or IsMe(name) then return end
	local now = GetTime()
	if lastPing[key] and now - lastPing[key] < PING_GAP then return end
	local rec = known[key]
	if rec and time() - (rec.t or 0) < PING_GAP then return end -- heard from them recently
	lastPing[key] = now
	Hello("WHISPER", name)
end

local function GroupChannel()
	if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
	if IsInRaid and IsInRaid() then return "RAID" end
	if IsInGroup and IsInGroup() then return "PARTY" end
end

---------------------------------------------------------------------------
-- Hearing
---------------------------------------------------------------------------

local function Remember(sender, version, via)
	local key = Key(sender)
	if not key then return end
	local rec = known[key] or {}
	known[key] = rec
	rec.n = Ambiguate and Ambiguate(sender, "none") or sender
	rec.v = version
	rec.t = time()
	-- the closest tie wins: guild and friends over group over a passer-by
	local rank = { guild = 4, friend = 3, group = 2, seen = 1 }
	if not rec.via or (rank[via] or 0) >= (rank[rec.via] or 0) then rec.via = via end
	if S().nudge and P.Newer(version, ns.VERSION) and not nudgedThisSession[version] then
		nudgedThisSession[version] = true
		P:Nudge(version, rec.n)
	end
end

local function ViaOf(channel, sender)
	if channel == "GUILD" or channel == "OFFICER" then return "guild" end
	if channel == "PARTY" or channel == "RAID" or channel == "INSTANCE_CHAT" then return "group" end
	if C_FriendList and C_FriendList.GetFriendInfo then
		local ok, info = pcall(C_FriendList.GetFriendInfo, Ambiguate(sender, "short"))
		if ok and info then return "friend" end
	end
	return "seen"
end

local function OnMessage(text, channel, sender)
	if not sender or IsMe(sender) then return end
	local kind, version, extra = strsplit("|", text)
	-- (0.66.0) "K|npc|guid": a groupmate looted a corpse inside an instance
	if kind == "K" then
		local npc = tonumber(version)
		if npc and extra and ViaOf(channel, sender) == "group" and ns.NpcFromGuid(extra) == npc and ns.Bestiary then
			pcall(ns.Bestiary.SharedKill, ns.Bestiary, npc, extra)
		end
		return
	end
	if (kind ~= "H" and kind ~= "I") or not version or version == "" then return end
	Remember(sender, version, ViaOf(channel, sender))
	if kind == "H" and S().share then
		local key = Key(sender)
		local now = GetTime()
		if not lastReply[key] or now - lastReply[key] >= REPLY_GAP then
			lastReply[key] = now
			-- spread the answers out, so a guild doesn't all answer in the same instant
			C_Timer.After(0.5 + math.random() * 3, function() Send("I|" .. ns.VERSION, "WHISPER", sender) end)
		end
	end
end

---------------------------------------------------------------------------
-- Saying hello
---------------------------------------------------------------------------

local function HelloFriends()
	if not (C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex) then return end
	local n = C_FriendList.GetNumFriends() or 0
	for i = 1, math.min(n, 60) do
		local info = C_FriendList.GetFriendInfoByIndex(i)
		if info and info.connected and info.name then HelloTo(info.name) end
	end
end

local lastGroupHello = 0
local function HelloGroup()
	local channel = GroupChannel()
	if not channel or GetTime() - lastGroupHello < 30 then return end
	lastGroupHello = GetTime()
	Hello(channel)
end

local function HelloUnit(unit)
	if not (S().share and unit and UnitExists(unit) and UnitIsPlayer(unit)) then return end
	if UnitIsUnit(unit, "player") then return end
	if UnitFactionGroup(unit) ~= UnitFactionGroup("player") then return end
	if UnitIsConnected and not UnitIsConnected(unit) then return end
	local name = UnitFull(unit)
	if name then HelloTo(name) end
end

---------------------------------------------------------------------------
-- The tooltip badge
---------------------------------------------------------------------------

-- (0.66.0) tell the group's other Almanacs about a corpse looted inside an instance
function P:ShareKill(npc, guid)
	local channel = GroupChannel()
	if channel and npc and type(guid) == "string" then Send("K|" .. npc .. "|" .. guid, channel) end
end

function P:Get(nameOrUnit)
	local name = nameOrUnit
	if type(nameOrUnit) == "string" and UnitExists(nameOrUnit) and UnitIsPlayer(nameOrUnit) then name = UnitFull(nameOrUnit) end
	local rec = known and known[Key(name) or ""]
	if rec and time() - (rec.t or 0) <= TOOLTIP_DAYS * 86400 then return rec end
end

local function TooltipBadge(tooltip)
	if not S().tooltip then return end
	local _, unit = tooltip:GetUnit()
	if not unit or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return end
	if P:Get(unit) then
		-- (0.69.1) "Fellow Almanac Adventurer", in the Almanac's red, after its logo
		tooltip:AddLine(("|T%s:16:16|t |cffd8342b%s|r"):format(ns.ICON, L["Fellow Almanac Adventurer"]))
		tooltip:Show()
	end
end

---------------------------------------------------------------------------
-- The update quest
---------------------------------------------------------------------------

function P:Nudge(version, from)
	local db = S()
	if db.accepted == version then return end -- already took the quest for this one
	local function Show()
		if ns.UpdateQuest then ns.UpdateQuest:Show(version, from) end
	end
	if InCombatLockdown and InCombatLockdown() then
		local f = CreateFrame("Frame")
		f:RegisterEvent("PLAYER_REGEN_ENABLED")
		f:SetScript("OnEvent", function(self) self:UnregisterAllEvents() C_Timer.After(2, Show) end)
	else
		C_Timer.After(3, Show)
	end
end

-- the Almanac players heard from in the last `days` days: { { name, version, via, t }, ... }
function P:Recent(days)
	local list, now = {}, time()
	for _, rec in pairs(known or {}) do
		if rec.n and now - (rec.t or 0) <= (days or 7) * 86400 then list[#list + 1] = rec end
	end
	table.sort(list, function(a, b) return (a.t or 0) > (b.t or 0) end)
	return list
end

function P:Count()
	local n, now = 0, time()
	for _, rec in pairs(known or {}) do if now - (rec.t or 0) <= TOOLTIP_DAYS * 86400 then n = n + 1 end end
	return n
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

function P:OnInitialize(db)
	db.peers = db.peers or {}
	known = db.peers
	local now = time()
	for key, rec in pairs(known) do
		if type(rec) ~= "table" or now - (rec.t or 0) > FORGET then known[key] = nil end
	end
end

function P:OnLogin()
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
	ns:RegisterEvent("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
		if prefix == PREFIX and text then OnMessage(text, channel, sender) end
	end)
	ns:RegisterEvent("GROUP_ROSTER_UPDATE", function() C_Timer.After(2, HelloGroup) end)
	ns:RegisterEvent("FRIENDLIST_UPDATE", function() C_Timer.After(1, HelloFriends) end)
	ns:RegisterEvent("PLAYER_TARGET_CHANGED", function() HelloUnit("target") end)
	ns:RegisterEvent("UPDATE_MOUSEOVER_UNIT", function() HelloUnit("mouseover") end)
	-- the guild and group a little after login, once the rosters are in
	C_Timer.After(8, function()
		if IsInGuild and IsInGuild() then Hello("GUILD") end
		HelloGroup()
		if C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
		HelloFriends()
	end)

	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
			if tooltip == GameTooltip then pcall(TooltipBadge, tooltip) end
		end)
	elseif GameTooltip and GameTooltip.HookScript then
		pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tooltip) pcall(TooltipBadge, tooltip) end)
	end
end

-- for tests
P._OnMessage = OnMessage
