-- Azeroth Almanac core: modules, events, shared helpers and the /aa command.
-- Each feature registers itself with ns:NewModule(name) and may define:
--   OnInitialize(db)   saved data is loaded and up to date (after ADDON_LOADED)
--   OnLogin()          the player is in the world (PLAYER_LOGIN)
-- Modules talk through a small message bus: ns:On("DISCOVERY", fn) / ns:Fire("DISCOVERY", ...).

local ADDON_NAME, ns = ...
local L = ns.L
AzerothAlmanac = ns -- global so Bindings.xml can reach the window

ns.VERSION = "0.66.2"
ns.ICON = 133742   -- the Almanac's icon (picked with /aa whatis; was INV_Misc_Book_09)

BINDING_HEADER_AZEROTHALMANAC = "Azeroth Almanac"
BINDING_NAME_AZEROTHALMANAC_TOGGLE = L["Open or close the Almanac"]

---------------------------------------------------------------------------
-- Settings defaults (AzerothAlmanacDB.settings)
---------------------------------------------------------------------------

ns.defaults = {
	minimap = { show = true, angle = 200 },
	window = { scale = 1, tab = "journal", scroll = 100, smooth = true },
	toasts = { enabled = true, sound = true, minTier = 1, soundTier = 2, zone = true, subzone = true, instance = true, level = true, creature = true, tier = true, merchant = true, item = true, quest = true, trainer = true, flight = true, node = true, fishing = true, milestone = true },
	bestiary = { tooltip = true },
	peers = { share = true, tooltip = true, nudge = true, accepted = nil },
	nodes = { map = true, minimap = true, herb = true, ore = true, chest = true, sighted = true, size = 14, mmSize = 7, mmButton = true },
	townsfolk = { enabled = true, mapHidden = false, factionOnly = true, myClassOnly = true, continent = false, rims = false, size = 16, groups = {} },
	journalMax = 5000,
	debug = false,
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- This client hands addons "secret" values in some places (enemy health, cast bars ...).
-- They can't be compared, used as keys or turned into text. Returns the value only when it's safe.
function ns.IsSecret(v) return issecretvalue ~= nil and v ~= nil and issecretvalue(v) end
function ns.Readable(v)
	if v == nil or ns.IsSecret(v) then return nil end
	return v
end

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff" .. L["Azeroth Almanac"] .. ":|r " .. tostring(msg))
end

function ns.Debug(msg)
	if ns.db and ns.db.settings.debug then ns.Print("|cff999999" .. tostring(msg) .. "|r") end
end

-- copper -> "1g 20s 5c" with the game's coin icons
-- money the way the game writes it: each amount followed by its coin (gold, silver, copper art),
-- empty coins left out. 13405 -> "1 [gold] 34 [silver] 5 [copper]"
local COINS = {
	{ 10000, "Interface\\MoneyFrame\\UI-GoldIcon" },
	{ 100, "Interface\\MoneyFrame\\UI-SilverIcon" },
	{ 1, "Interface\\MoneyFrame\\UI-CopperIcon" },
}
-- the bags' own coin art (Coin-Gold / -Silver / -Copper atlases) where the client has it
local COIN_ATLAS = { "Coin-Gold", "Coin-Silver", "Coin-Copper" }
local coinMarkup
local function CoinMarkup(i, file)
	if coinMarkup == nil then
		coinMarkup = false
		if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Coin-Gold") then coinMarkup = true end
	end
	if coinMarkup then return "|A:" .. COIN_ATLAS[i] .. ":14:14:2:0|a" end
	return "|T" .. file .. ":0:0:2:0|t"
end

function ns.MoneyText(copper)
	copper = math.floor(tonumber(copper) or 0)
	local parts = {}
	for i, coin in ipairs(COINS) do
		local n = math.floor(copper / coin[1]) % (i == 1 and math.huge or 100)
		if i == 1 then n = math.floor(copper / coin[1]) end
		if n > 0 or (i == 3 and #parts == 0) then
			parts[#parts + 1] = "|cffffffff" .. n .. "|r" .. CoinMarkup(i, coin[2])
		end
	end
	return table.concat(parts, " ")
end

-- a price as the merchant window shows it: coins, then any item or currency the merchant also
-- wants, each as its icon after the amount. cost = "i<itemID>:n;c<currencyID>:n"
function ns.CostText(price, cost)
	local parts = {}
	if (price or 0) > 0 or not cost then parts[#parts + 1] = ns.MoneyText(price or 0) end
	for part in (cost or ""):gmatch("[^;]+") do
		local kind, id, n = part:match("^(%a)(%d+):(%d+)$")
		id = tonumber(id)
		local icon
		if kind == "i" then
			local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
			if instant then
				local ok, _, _, _, _, tex = pcall(instant, id)
				icon = ok and tex or nil
			end
		elseif kind == "c" and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
			local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
			icon = ok and type(info) == "table" and info.iconFileID or nil
		end
		if n then
			parts[#parts + 1] = "|cffffffff" .. n .. "|r" .. (icon and ("|T" .. icon .. ":0:0:2:0|t") or (" " .. (kind == "i" and ("item " .. id) or ("currency " .. id))))
		end
	end
	return table.concat(parts, " ")
end

-- a Lua pattern from one of the game's own message formats ("Discovered %s: %d experience gained")
function ns.Pattern(fmt)
	if type(fmt) ~= "string" then return nil end
	fmt = fmt:gsub("%%%d?%$?d", "\1"):gsub("%%%d?%$?s", "\2")
	fmt = fmt:gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0")
	fmt = fmt:gsub("\1", "(%%d+)"):gsub("\2", "(.+)")
	return "^" .. fmt .. "$"
end

-- "Creature-0-4615-1-27150-3924-000041B7A4" -> "Creature", 3924
function ns.ParseGuid(guid)
	guid = ns.Readable(guid)
	if type(guid) ~= "string" then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	return kind, tonumber(id)
end

function ns.NpcFromGuid(guid)
	local kind, id = ns.ParseGuid(guid)
	if kind == "Creature" or kind == "Vehicle" then return id end
end

-- "Name-Realm" for the character you're playing
function ns.CharKey()
	local name, realm = UnitFullName("player")
	-- (early on - the saved data loading - the realm may not be filled in yet: the normalised
	-- name is what UnitFullName gives later, so the key is the same from the first moment)
	if not realm or realm == "" then realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or "?" end
	return (name or "?") .. "-" .. realm:gsub("%s", "")
end

function ns.ClassColor(classFile)
	local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if c and c.colorStr then return "|c" .. c.colorStr end
	return "|cffffffff"
end

-- "Zaphenat" in its class color, for a "Name-Realm" key. plain: no color (class colors are hard
-- to read on parchment).
function ns.CharName(key, plain)
	local c = key and ns.db and ns.db.chars[key]
	local name = (key or "?"):match("^([^-]+)") or key or "?"
	if plain then return name end
	return ns.ClassColor(c and c.classFile) .. name .. "|r"
end

-- "1 kill" / "5 kills"
function ns.N(n, one, many)
	n = n or 0
	return n .. " " .. (n == 1 and L[one] or L[many])
end

-- "once" / "twice" / "5 times"
function ns.Times(n)
	n = n or 0
	if n == 1 then return L["once"] end
	if n == 2 then return L["twice"] end
	return (L["%d times"]):format(n)
end

function ns.DateText(t)
	if not t then return "?" end
	return date("%b %d, %Y", t)
end

function ns.DateTimeText(t)
	if not t then return "?" end
	return date("%b %d, %Y %H:%M", t)
end

-- "just now", "5 min ago", "3 h ago", "2 days ago", or the date
function ns.AgoText(t)
	if not t then return "?" end
	local d = time() - t
	if d < 60 then return L["just now"] end
	if d < 3600 then return (L["%d min ago"]):format(math.floor(d / 60)) end
	if d < 86400 then return (L["%d h ago"]):format(math.floor(d / 3600)) end
	if d < 86400 * 14 then return (L["%d days ago"]):format(math.floor(d / 86400)) end
	return ns.DateText(t)
end

-- Where the player is: map, x and y in percent (one decimal), zone and subzone names.
function ns.Where()
	local map = ns.Readable(C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
	local x, y
	if map and C_Map.GetPlayerMapPosition then
		local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
		if ok and pos and not ns.IsSecret(pos) and pos.GetXY then
			local okXY, px, py = pcall(pos.GetXY, pos)
			px, py = okXY and ns.Readable(px), okXY and ns.Readable(py)
			if type(px) == "number" and type(py) == "number" then
				x, y = math.floor(px * 1000 + 0.5) / 10, math.floor(py * 1000 + 0.5) / 10
			end
		end
	end
	return { map = map, x = x, y = y, zone = ns.Readable(GetZoneText()), sub = ns.Readable(GetSubZoneText()) }
end

---------------------------------------------------------------------------
-- Modules and messages
---------------------------------------------------------------------------

ns.modules = {}
function ns:NewModule(name)
	local module = { name = name }
	self[name] = module
	tinsert(self.modules, module)
	return module
end

local listeners = {}
function ns:On(message, fn)
	listeners[message] = listeners[message] or {}
	tinsert(listeners[message], fn)
end
function ns:Fire(message, ...)
	for _, fn in ipairs(listeners[message] or {}) do
		local ok, err = pcall(fn, ...)
		if not ok then ns.Debug("listener error (" .. message .. "): " .. tostring(err)) end
	end
end

-- Game events for modules: ns:RegisterEvent("ZONE_CHANGED", fn). One shared frame.
local eventFrame = CreateFrame("Frame")
local handlers = {}
function ns:RegisterEvent(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
		if not ok then ns.Debug("event not available: " .. event) end
	end
	tinsert(handlers[event], fn)
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

-- When the game blocks something and blames the Almanac, write down which function it was and
-- what the Almanac was doing (ns.doing), so it can be fixed. /aa stats shows the count.
ns.doing = "starting"
local function Blocked(event, addon, func)
	if addon ~= ADDON_NAME or not ns.db then return end
	ns.db.diag = ns.db.diag or {}
	local list = ns.db.diag
	-- the latest 30 (the oldest drop off, so a fresh block is always there to read)
	while #list >= 30 do table.remove(list, 1) end
	list[#list + 1] = { t = time(), event = event, func = tostring(func), doing = ns.doing, combat = InCombatLockdown and InCombatLockdown() or nil, v = ns.VERSION }
	-- said once per function per session (the map can trigger the same block many times a fight)
	ns.blockedSaid = ns.blockedSaid or {}
	if ns.blockedSaid[tostring(func)] then return end
	ns.blockedSaid[tostring(func)] = true
	ns.Print(("|cffff6060the game blocked %s while the Almanac was %s.|r This is recorded for fixing."):format(tostring(func), tostring(ns.doing)))
end
eventFrame:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		if ... == ADDON_NAME then
			ns.Store:Load()
			-- this character's settings profile over the live settings, before any module starts
			if ns.Profiles then
				local ok, err = pcall(ns.Profiles.Load, ns.Profiles)
				if not ok then ns.Print("settings profile: " .. tostring(err)) end
			end
			for _, module in ipairs(ns.modules) do
				if module.OnInitialize then
					local ok, err = pcall(module.OnInitialize, module, ns.db)
					if not ok then ns.Print("error starting " .. module.name .. ": " .. tostring(err)) end
				end
			end
		end
	elseif event == "PLAYER_LOGIN" then
		-- blocked-action reports from older versions are history (their causes were fixed since):
		-- keep only this version's
		if ns.db and type(ns.db.diag) == "table" then
			local keep = {}
			for _, d in ipairs(ns.db.diag) do if d.v == ns.VERSION then keep[#keep + 1] = d end end
			ns.db.diag = keep
		end
		for _, module in ipairs(ns.modules) do
			if module.OnLogin then
				local ok, err = pcall(module.OnLogin, module)
				if not ok then ns.Print("error starting " .. module.name .. ": " .. tostring(err)) end
			end
		end
	end
	for _, fn in ipairs(handlers[event] or {}) do
		local ok, err = pcall(fn, event, ...)
		if not ok then ns.Debug(event .. ": " .. tostring(err)) end
	end
end)
ns:RegisterEvent("ADDON_ACTION_FORBIDDEN", Blocked)
ns:RegisterEvent("ADDON_ACTION_BLOCKED", Blocked)

---------------------------------------------------------------------------
-- /aa
---------------------------------------------------------------------------

local PAGE_ALIASES = {
	journal = "journal", j = "journal",
	bestiary = "bestiary", beasts = "bestiary", creatures = "bestiary",
	items = "items", item = "items",
	quests = "quests", quest = "quests",
	merchants = "townsfolk", merchant = "townsfolk", vendors = "townsfolk",
	people = "townsfolk", townsfolk = "townsfolk", npcs = "townsfolk",
	places = "places", zones = "places", place = "places",
	dungeons = "dungeons", dungeon = "dungeons", raids = "dungeons", raid = "dungeons", instances = "dungeons",
	characters = "characters", chars = "characters", alts = "characters",
	trainers = "townsfolk", trainer = "townsfolk", spells = "trainers", recipes = "trainers",
	gathering = "gathering", gather = "gathering", herbs = "gathering", ore = "gathering", fishing = "gathering",
}

-- (Never assign the game's own globals, not even "X = X or {}": that taints them and the game then
-- blocks its own protected actions and blames the Almanac. Only add our own key.)
StaticPopupDialogs.AZEROTHALMANAC_RESET = {
	text = L["Erase everything the Almanac has recorded, for every character? This can't be undone."],
	button1 = YES or "Yes",
	button2 = NO or "No",
	OnAccept = function() ns.Store:Reset() ns.Print(L["All records erased."]) end,
	timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
}

local DEV_COMMANDS = { maptest = true, art = true, toast = true, atlascheck = true, ejscan = true, whatis = true, cards = true }

SLASH_AZEROTHALMANAC1 = "/aa"
SLASH_AZEROTHALMANAC2 = "/almanac"
SlashCmdList.AZEROTHALMANAC = function(msg)
	local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()
	ns.doing = "running /aa " .. cmd
	-- (the tools for working on the addon answer only with /aa debug on, 0.64.0)
	if DEV_COMMANDS[cmd] and not ns.db.settings.debug then
		ns.Print(L["that's a developer command: /aa debug turns them on."])
		return
	end
	if cmd == "" then
		ns.UI:Toggle()
	elseif (cmd == "people" or cmd == "townsfolk" or cmd == "tf") and rest:lower() == "check" then
		-- (before the page names: "people" opens the page, "people check" tests the map position)
		ns.Townsfolk:Check()
	elseif cmd == "help" or cmd == "?" then
		ns.Help()
	elseif PAGE_ALIASES[cmd] == "bestiary" and rest ~= "" then
		local page = ns.UI:GetPage("bestiary")
		local npc = page and page:Find(rest)
		if npc then page:ShowCreature(npc) else ns.Print((L["No creature called \"%s\" in your Almanac yet."]):format(rest)) end
	elseif PAGE_ALIASES[cmd] then
		ns.UI:Open(PAGE_ALIASES[cmd])
	elseif cmd == "options" or cmd == "settings" or cmd == "config" or cmd == "set" then
		ns.Settings:Open(rest)
	elseif cmd == "tf" then
		ns.Settings:Open("townsfolk")
	elseif cmd == "scan" then
		ns.QoL.AuctionPrices:StartScan()
	elseif cmd == "inv" or cmd == "inventory" or cmd == "bags" then
		ns.QoL.InventoryWindow:Toggle()
	elseif cmd == "games" or cmd == "game" or cmd == "gems" then
		ns.QoL.GemMatch:Toggle()
	elseif cmd == "version" or cmd == "ver" or cmd == "v" then
		if rest == "quest" then
			ns.UpdateQuest:Preview()
		else
			ns.Print(("version |cffffffff%s|r  -  %s"):format(ns.VERSION, (L["%d other Almanac players known"]):format(ns.Peers and ns.Peers:Count() or 0)))
		end
	elseif cmd == "gambit" or cmd == "wild" or cmd == "wildgambit" then
		ns.QoL.WildGambit:Command(rest)
	elseif cmd == "mtt" or cmd == "murloc" or cmd == "tictactoe" or cmd == "ttt" then
		ns.QoL.MurlocTacToe:Command(rest)
	elseif cmd == "heal" or cmd == "healer" then
		if rest == "" then ns.Settings:Open("healer") else ns.QoL.HealAssist:Command(rest) end
	elseif cmd == "talents" or cmd == "talent" or cmd == "planner" then
		if rest == "probe" then ns.QoL.TalentPlanner:ProbeTalents() else ns.QoL.TalentPlanner:Open() end
	elseif cmd == "ranks" or cmd == "rank" then
		ns.QoL.SpellRanker:Check()
	elseif cmd == "rankignore" then
		ns.QoL.SpellRanker:Ignore(rest)
	elseif cmd == "threat" then
		ns.QoL.ThreatMonitor:Preview()
	elseif cmd == "wings" then
		ns.QoL.WingsWhispers:Sample()
	elseif cmd == "node" then
		ns.QoL.NodeHighlight:ClassifyCurrent(rest:lower())
	elseif cmd == "stats" then
		ns.Store:PrintStats()
	elseif cmd == "minimap" then
		ns.MinimapButton:SetShown(not ns.db.settings.minimap.show)
	elseif cmd == "maptest" then
		if ns.MapTest then ns.MapTest:Command(rest)
		else ns.Print("The map test is a new file: exit and restart the game once to load it.") end
	elseif cmd == "nodes" or cmd == "gathermap" then
		local m = ns.db.settings.nodes
		if rest == "button" then
			m.mmButton = true
			ns.NodePins:ResetMiniButton()
			ns.NodePins:Refresh()
			ns.Print(L["Gathering button put back on the minimap, next to the Almanac's button."])
		else
			m.minimap = not m.minimap
			ns.NodePins:Refresh()
			ns.Print(m.minimap and L["Gathering nodes shown on the minimap."] or L["Gathering nodes hidden on the minimap."])
		end
	elseif cmd == "debug" then
		ns.db.settings.debug = not ns.db.settings.debug
		ns.Print("debug " .. (ns.db.settings.debug and "on" or "off"))
	elseif cmd == "art" then
		ns.ArtScan:Scan()
	elseif cmd == "toast" then
		if ns.Toast then ns.Toast:Test() end
	elseif cmd == "atlascheck" then
		ns.ArtScan:AtlasCheck()
	elseif cmd == "ejscan" then
		ns.ArtScan:EJScan()
	elseif cmd == "whatis" then
		ns.ArtScan:WhatIs(rest)
	elseif cmd == "cards" then
		ns.ArtScan:Cards()
	elseif cmd == "reset" then
		StaticPopup_Show("AZEROTHALMANAC_RESET")
	else
		if cmd ~= "" then ns.Print((L["no command \"%s\"."]):format(cmd)) end
		ns.Help()
	end
end

-- /aa help (and any command it doesn't know)
function ns.Help()
	ns.Print(L["commands:"])
	ns.Print("/aa - " .. L["open or close the Almanac"])
	ns.Print("/aa journal | characters | creatures | items | quests | gathering | places | dungeons | people | spells - " .. L["open a page"])
	ns.Print("/aa creatures <name> - " .. L["open Creatures on a creature (/aa bestiary works too)"])
	ns.Print("/aa settings [page] - " .. L["the settings window"])
	ns.Print("/aa people check - " .. L["test the map position of the NPC you're talking to"])
	ns.Print("/aa tf - " .. L["settings for people on the world map"])
	ns.Print("/aa scan - " .. L["full auction house scan (auction house open)"])
	ns.Print("/aa inv - " .. L["Characters page on the Bags tab: every character's bags, bank and gear"])
	ns.Print("/aa version [quest] - " .. L["which version of Azeroth Almanac is loaded (quest: preview the update quest)"])
	ns.Print("/aa games - " .. L["Gem Match"])
	ns.Print("/aa gambit [Name|new|tutorial|leave] - " .. L["Wild Gambit, the creature card game (practice, or challenge another Almanac player)"])
	ns.Print("/aa mtt [name|target|practice|leave|ping name|debug] - " .. L["Murloc Tac Toe: challenge another Azeroth Almanac player, or practise against a gnoll"])
	ns.Print("/aa heal [test|debug|on|off] - " .. L["Healer Assist"])
	ns.Print("/aa node herb|ore|chest|other|reset - " .. L["classify the node you're facing"])
	ns.Print("/qt - " .. L["quest tracker target buttons (/qt help)"])
	ns.Print("/aa stats - " .. L["what has been recorded, and how big the saved data is"])
	ns.Print("/aa talents - " .. L["Talent Planner (the Planner tab on your Talents window)"])
	ns.Print("/aa minimap - " .. L["show or hide the minimap button"])
	ns.Print("/aa nodes [button] - " .. L["show or hide gathering nodes on the minimap (button: put the minimap button back)"])
	ns.Print("/aa reset - " .. L["erase all records (asks first)"])
end
