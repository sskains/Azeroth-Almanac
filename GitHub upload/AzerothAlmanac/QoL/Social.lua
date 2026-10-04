-- Ported from Plus Everything (same author) for Azeroth Almanac's quality-of-life helpers.
-- Social: auto-invite players who ask with a keyword ("inv"), and auto-accept group invites
-- from friends (including Battle.net friends) and guild members. Settings > Group Settings.

local _, A = ...
local ns = A.QoL
local SO = ns:NewModule("Social")

local db
local lastInvite = {} -- name -> time, so one ask doesn't send a burst of invites

local function Readable(v) return ns.Readable(v) end

---------------------------------------------------------------------------
-- Who's who
---------------------------------------------------------------------------

local function ShortName(name) return name and (name:match("^[^-]+") or name) end

local function IsFriend(name, guid)
	if guid and C_FriendList and C_FriendList.IsFriend then
		local ok, yes = pcall(C_FriendList.IsFriend, guid)
		if ok and Readable(yes) then return true end
	end
	-- Battle.net friends playing WoW
	if guid and C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID then
		local ok, info = pcall(C_BattleNet.GetGameAccountInfoByGUID, guid)
		if ok and Readable(info) then return true end
	end
	if name and C_FriendList and C_FriendList.GetNumFriends then
		local short = ShortName(name)
		for i = 1, C_FriendList.GetNumFriends() or 0 do
			local info = C_FriendList.GetFriendInfoByIndex(i)
			if info and info.name and ShortName(info.name) == short then return true end
		end
	end
	return false
end

local function IsGuildmate(name, guid)
	if not IsInGuild() then return false end
	if guid and IsGuildMember then
		local ok, yes = pcall(IsGuildMember, guid)
		if ok and Readable(yes) then return true end
	end
	if name and GetNumGuildMembers then
		local short = ShortName(name)
		for i = 1, GetNumGuildMembers() or 0 do
			local member = GetGuildRosterInfo(i)
			if member and ShortName(member) == short then return true end
		end
	end
	return false
end

---------------------------------------------------------------------------
-- Auto-invite on a keyword
---------------------------------------------------------------------------

-- The message asks for an invite: its first word is a keyword and it's short (so "can you inv
-- my friend later" in a long sentence doesn't trigger).
local function Asks(message)
	if type(message) ~= "string" or #message > 24 then return false end
	local first = message:lower():match("^%s*([%a]+)")
	if not first then return false end
	for word in (db.keywords or ""):lower():gmatch("[%a]+") do
		if first == word then return true end
	end
	return false
end

local function CanInvite()
	if not IsInGroup() then return true end
	if IsInRaid() then
		return (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) and GetNumGroupMembers() < 40
	end
	return UnitIsGroupLeader("player") and GetNumGroupMembers() < 5
end

local function Invite(name, guid)
	if not (db.autoInvite and name) then return end
	local short = ShortName(name)
	if short == UnitName("player") or UnitInParty(short) or UnitInRaid(short) then return end
	if db.inviteOnlyKnown and not (IsFriend(name, guid) or IsGuildmate(name, guid)) then return end
	local now = GetTime()
	if lastInvite[name] and now - lastInvite[name] < 10 then return end
	if not CanInvite() then
		ns.Print(("%s asked for an invite, but you can't invite right now (not the leader, or the group is full)."):format(short))
		return
	end
	lastInvite[name] = now
	local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
	invite(name)
	ns.Print(("invited %s (they asked with \"%s\")."):format(short, db.keywords:match("[%a]+") or "inv"))
end

---------------------------------------------------------------------------
-- Auto-accept invites from friends and guild members
---------------------------------------------------------------------------

local function OnInvite(name, guid)
	local friend = db.acceptFriends and IsFriend(name, guid)
	local guild = not friend and db.acceptGuild and IsGuildmate(name, guid)
	if not (friend or guild) then return end
	AcceptGroup()
	-- the game's invite window can close now; it stays open for a moment otherwise
	C_Timer.After(0.1, function() if StaticPopup_Hide then StaticPopup_Hide("PARTY_INVITE") end end)
	ns.Print(("joined %s's group (%s)."):format(ShortName(name) or "?", friend and "friend" or "guild member"))
end

---------------------------------------------------------------------------
-- Module API
---------------------------------------------------------------------------

function SO:OnInitialize(saved)
	db = saved.social
end

function SO:OnLogin()
	local events = CreateFrame("Frame")
	events:RegisterEvent("CHAT_MSG_WHISPER")
	events:RegisterEvent("CHAT_MSG_GUILD")
	events:RegisterEvent("PARTY_INVITE_REQUEST")
	events:SetScript("OnEvent", function(_, event, ...)
		if event == "PARTY_INVITE_REQUEST" then
			local name, _, _, _, _, _, guid = ...
			OnInvite(Readable(name), Readable(guid))
			return
		end
		local message, sender = ...
		local guid = Readable(select(12, ...))
		message, sender = Readable(message), Readable(sender)
		if event == "CHAT_MSG_WHISPER" and db.inviteWhispers and Asks(message) then
			Invite(sender, guid)
		elseif event == "CHAT_MSG_GUILD" and db.inviteGuildChat and Asks(message) then
			Invite(sender, guid)
		end
	end)
end

-- For the settings page and tests.
SO.Asks = function(message) return Asks(message) end
