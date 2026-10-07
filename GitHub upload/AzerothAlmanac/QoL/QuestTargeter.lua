-- Ported from Plus Everything (same author) for Azeroth Almanac's quality-of-life helpers.
-- Quest Targeter
-- Puts a small target button beside quest objectives in the tracker.
--   Kill objectives: targets the nearest living mob with that name.
--   Item objectives: targets the nearest mob that drops the item, using the built-in
--   database (Data\DropData.lua), sources learned when looting, and /qt link.
-- Clicking a button also makes it the "selected" objective for the keybinding.
-- The number beside each button is how many matching mobs are nearby, counted
-- from enemy nameplates (so enemy nameplates must be on).

local _, A = ...
local ns = A.QoL
local QT = ns:NewModule("QuestTargeter")

local BUTTON_SIZE = 20
local TRACKER_GAP = 18 -- space between our buttons and the tracker's own quest icons
local BADGE_SPACING = 7 -- between badges side by side on one quest's row
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local MAX_SOURCES_IN_MACRO = 4
local MACRO_LIMIT = 1023         -- most macro text a button gets (older clients cut at 255, hence the line order in MacroFor)
local SKULL = 8
local STAR = 1 -- kept for quest turn-in NPCs
local EXTRA_MARKERS = { 7, 4, 3, 5, 6, 2 } -- cross, triangle, diamond, moon, square, circle
local TURNIN_ICON = "Interface\\GossipFrame\\ActiveQuestIcon"
local ATTACK_ICON = "Interface\\CURSOR\\Attack"
local MAX_CLEAR_LINES = 20
local TRACKER_ROOTS = { "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame" }

local db
local buttons = {}
local pendingSelection = false
local objectives = {} -- objective name -> { quest = title, kind = "monster" | "item" }
local guidNames = {}  -- creature GUID -> name (from target, mouseover and nameplates), used to name loot sources
local counts = {}     -- mob name -> number nearby, filled by CountNearby
local extraMarkLines = {} -- /tm lines for other nearby quest mobs, rebuilt out of combat by BuildMarkLines
local clearMarkLines = {} -- /tm ... 0 lines for the clear-markers hotkey
local NearestPlate        -- defined with the nameplate scan below
local OnlyTaken           -- likewise
local takenPlates = {}    -- name -> how many visible ones are someone else's (see Taken)

-- Targeting looks all around you: out of combat the macro first targets the closest matching
-- nameplate (nameplates exist behind and beside you too). Nameplate tokens can point at other
-- units once combat starts and the macro can't change in combat, so that line carries
-- [nocombat]; in combat (or with no nameplate) the /targetexact lines do the work.
-- Clearing first makes /targetexact pick the closest match instead of cycling.
-- With several drop sources, each later line only fires if nothing living was found yet.
-- Marking has to happen inside the macro: this client blocks SetRaidTarget from addon code.
-- "/tm !N" sets the marker; plain "/tm N" toggles it off again on a mob that already has it
-- (on WoW Forever the "!" form is the one that doesn't toggle; RestedXP does the same).
-- Other nearby quest mobs are marked first and the target gets the skull last, so it ends
-- up with the skull even if it was also handed an extra marker.
-- Pings (/ping [conditions] <type>): the game's own ping on your target, so your group sees
-- which mob you're going for (solo, only you see it). Types by number so it works in any
-- language. A /stopmacro right before it skips the ping when nothing was found: Forever's
-- /ping didn't reliably skip on its own failed conditions (it pinged with nothing found).
QT.pingTypes = {
	{ name = "Attack", n = 1 },
	{ name = "Warning", n = 2 },
	{ name = "On my way", n = 3 },
	{ name = "Assist", n = 4 },
	{ name = "Threat", n = 6 },
}
local PING_TURNIN = 3 -- "On my way" on the NPC you're handing a quest in to

local function CanPing()
	return SLASH_PING1 ~= nil or (C_Ping ~= nil and C_Ping.SendMacroPing ~= nil)
end

local function MacroFor(targets, kind)
	local lines = {}
	if kind == "turnin" then
		-- A quest ready to hand in: target whoever takes it back and put a star on them.
		lines[#lines + 1] = "/cleartarget"
		local plate = NearestPlate(targets)
		if plate then lines[#lines + 1] = ("/target [nocombat,@%s,exists,noharm,nodead] %s"):format(plate, plate) end
		for i, name in ipairs(targets) do
			lines[#lines + 1] = ((i == 1 and not plate) and "/targetexact " or "/targetexact [noexists] ") .. name
		end
		if db.markTurnIns then lines[#lines + 1] = "/tm [exists,nodead,noharm] !" .. STAR end
		if db.pingTurnIns and CanPing() then
			-- found nobody: stop here, so nothing gets pinged
			lines[#lines + 1] = "/stopmacro [noexists][dead][harm]"
			lines[#lines + 1] = "/ping [@target,exists,noharm,nodead] " .. PING_TURNIN
		end
		return table.concat(lines, "\n")
	end
	-- The lines that matter (target, skull, ping) come first and are kept short, in case the
	-- client cuts long macro text (older ones stop at 255 characters); the markers for other
	-- nearby mobs come last. ([harm] already means "a target exists".)
	local plate = NearestPlate(targets)
	-- Every one in sight is someone else's (tapped, or hurt and fighting another player): don't
	-- grab one by name out of combat. In combat the name lines still run (the macro can't
	-- change then, and the mob in front of you is usually your own).
	local combatOnly = not plate and OnlyTaken(targets)
	local head, tail = { "/cleartarget" }, {}
	-- someone else's are in sight too: out of combat, only the nameplate line picks (the name lines
	-- would grab the closest by name, theirs included)
	local anyTaken = false
	for _, name in ipairs(targets) do if takenPlates[name] then anyTaken = true end end
	if plate then
		head[#head + 1] = ("/target [nocombat,@%s,harm,nodead] %s"):format(plate, plate)
		head[#head + 1] = (anyTaken and "/targetexact [noexists,combat] " or "/targetexact [noexists] ") .. targets[1]
	elseif combatOnly then
		head[#head + 1] = "/targetexact [combat] " .. targets[1]
	else
		head[#head + 1] = "/targetexact " .. targets[1]
	end
	-- Landed on a corpse: with a target already set, /targetexact moves on to the next one.
	head[#head + 1] = "/targetexact [dead] " .. targets[1]
	-- Whatever was picked: drop it if it's dead.
	tail[#tail + 1] = "/cleartarget [dead]"
	if db.markTargets then tail[#tail + 1] = "/tm [harm,nodead] !" .. SKULL end
	if db.pingTargets and CanPing() then
		local ping = QT.pingTypes[db.pingType or 1] or QT.pingTypes[1]
		-- nothing found (or only a corpse): stop here, so nothing gets pinged
		tail[#tail + 1] = "/stopmacro [noharm][dead]"
		tail[#tail + 1] = "/ping [@target,harm,nodead] " .. ping.n
	end
	for i = 2, math.min(#targets, MAX_SOURCES_IN_MACRO) do
		head[#head + 1] = (combatOnly and "/targetexact [combat,noexists][combat,dead] " or "/targetexact [noexists][dead] ") .. targets[i]
	end
	for _, line in ipairs(head) do lines[#lines + 1] = line end
	for _, line in ipairs(tail) do lines[#lines + 1] = line end
	-- Markers for the other nearby quest mobs come last: if the text gets cut, only some of them
	-- are lost. (After the /stopmacro they only run when a target was found.) The target's own
	-- plate is left out, and the skull is set once more at the end, so it keeps the skull.
	local extras = 0
	for _, line in ipairs(extraMarkLines) do
		if not (plate and line:find("@" .. plate .. ",", 1, true)) and #table.concat(lines, "\n") + #line + 1 <= MACRO_LIMIT then
			lines[#lines + 1] = line
			extras = extras + 1
		end
	end
	if extras > 0 and db.markTargets then lines[#lines + 1] = "/tm [harm,nodead] !" .. SKULL end
	return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Quest log parsing
---------------------------------------------------------------------------

-- Pulls the name out of "Kobold Vermin slain: 3/8", "Bear Meat: 1/3", "3/8 Kobold Vermin slain", etc.
local function ObjectiveName(text)
	if type(text) ~= "string" or text == "" then return end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s*%-%s*", "")
	local name = text:match("^(.-)%s*:%s*%d+%s*/%s*%d+$") or text:match("^%d+%s*/%s*%d+%s+(.+)$")
	if not name then return end
	name = strtrim((name:gsub("%s+[Ss]lain$", ""):gsub("%s+[Kk]illed$", "")))
	if name ~= "" then return name end
end

local CollectTurnIns -- defined below; adds quests ready to hand in

-- Unfinished kill and item objectives across the whole quest log.
local function CollectObjectives()
	wipe(objectives)
	local function add(text, kind, finished, quest)
		if (kind == "monster" or kind == "item") and not finished then
			local name = ObjectiveName(text)
			if name then objectives[name] = { quest = quest, kind = kind } end
		end
	end

	if GetQuestLogTitle and GetQuestLogLeaderBoard then
		for i = 1, (GetNumQuestLogEntries()) do
			local title, _, _, isHeader = GetQuestLogTitle(i)
			if title and not isHeader then
				for j = 1, (GetNumQuestLeaderBoards(i) or 0) do
					local text, kind, finished = GetQuestLogLeaderBoard(j, i)
					add(text, kind, finished, title)
				end
			end
		end
	elseif C_QuestLog and C_QuestLog.GetInfo then
		for i = 1, C_QuestLog.GetNumQuestLogEntries() do
			local info = C_QuestLog.GetInfo(i)
			if info and not info.isHeader and info.questID then
				for _, obj in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
					add(obj.text, obj.type, obj.finished, info.title)
				end
			end
		end
	end
	CollectTurnIns()
end

-- The NPC named in a quest's completion text: "Return to Magistrate Solomon ...",
-- "Report to Gryan Stoutmantle in Westfall", "Speak with ...".
local FINISHER_PATTERNS = {
	"[Rr]eturn to (%u[^%.,!;]-) in %u", "[Rr]eturn to (%u[^%.,!;]-) with ", "[Rr]eturn to (%u[^%.,!;]-)[%.,!;]",
	"[Rr]eport to (%u[^%.,!;]-) in %u", "[Rr]eport to (%u[^%.,!;]-)[%.,!;]",
	"[Ss]peak with (%u[^%.,!;]-) in %u", "[Ss]peak with (%u[^%.,!;]-)[%.,!;]",
	"[Ss]peak to (%u[^%.,!;]-) in %u", "[Ss]peak to (%u[^%.,!;]-)[%.,!;]",
	" to (%u[%a'%- ]-) in %u",
}
local function FinisherFromText(text)
	if type(text) ~= "string" then return end
	for _, pattern in ipairs(FINISHER_PATTERNS) do
		local name = text:match(pattern)
		if name then
			name = strtrim(name)
			if #name > 2 and #name <= 40 then return name end
		end
	end
end

-- Quests ready to hand in, keyed "turnin:<title>", with the names of the NPCs that take them
-- back: from the Almanac's quest records (the NPC must have been met), else whoever took it last time, else the NPC
-- named in the quest's completion text. Quests handed in at an object are skipped.
function CollectTurnIns()
	local quests, npcs = ns.QuestData and ns.QuestData.quests or {}, ns.QuestData and ns.QuestData.npcs or {}
	if not db.turnIns or not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return end
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		local id = info and not info.isHeader and info.questID
		local ready = id and ((C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(id)) or (C_QuestLog.IsComplete and C_QuestLog.IsComplete(id)))
		if ready then
			local names, npcIDs = {}, {}
			local q = quests[id]
			for npc in (q and q[8] or ""):gmatch("%d+") do
				local entry = npcs[tonumber(npc)]
				if entry then
					names[#names + 1] = entry[1]
					npcIDs[#npcIDs + 1] = tonumber(npc)
				end
			end
			if #names == 0 and db.learnedFinishers[id] then
				names[1] = db.learnedFinishers[id]
				npcIDs[1] = db.learnedFinisherIDs[id]
			end
			if #names == 0 and GetQuestLogCompletionText then
				local ok, text = pcall(GetQuestLogCompletionText, i)
				names[1] = ok and FinisherFromText(text) or nil
			end
			if #names > 0 then
				objectives["turnin:" .. info.title] = { quest = info.title, kind = "turnin", targets = names, npcID = npcIDs[1] }
			end
		end
	end
end

-- The quest title a tracker line shows ("[12] Title" or colored), for matching turn-ins.
local function TitleText(text)
	if type(text) ~= "string" or text == "" then return end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s*%[%d+%+?%]%s*", "")
	return strtrim(text)
end

-- DropData.lua stores zones as area IDs; the client turns them into names.
local areaNames = {}
local function AreaName(id)
	if type(id) == "string" then return id end
	if areaNames[id] == nil then
		areaNames[id] = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(id) or false
	end
	return areaNames[id]
end

local function DropsInZone(entry, zone)
	if #entry < 2 or not (C_Map and C_Map.GetAreaInfo) then return true end
	for k = 2, #entry do
		if AreaName(entry[k]) == zone then return true end
	end
end

local function InDropData(item, mob)
	for _, entry in ipairs(ns.Drops and ns.Drops[item] or {}) do
		if entry[1] == mob then return true end
	end
end

-- The mob names a button for this objective should target. For items that's the
-- sources you've learned or linked, plus the database's sources in your current
-- zone, with any that are nearby right now moved to the front.
local function TargetsFor(name)
	local obj = objectives[name]
	if not obj then return end
	if obj.kind == "turnin" then return obj.targets end
	if obj.kind == "monster" then
		return ns.KillAliases and ns.KillAliases[name] or { name }
	end

	local list, seen = {}, {}
	local function add(mob)
		if not seen[mob] then
			seen[mob] = true
			list[#list + 1] = mob
		end
	end
	for _, mob in ipairs(db.itemSources[name] or {}) do add(mob) end
	local zone = GetRealZoneText()
	for _, entry in ipairs(ns.Drops and ns.Drops[name] or {}) do
		if DropsInZone(entry, zone) then add(entry[1]) end
	end
	if #list == 0 then return end

	local order = {}
	for i, mob in ipairs(list) do order[mob] = i end
	table.sort(list, function(a, b)
		local na, nb = (counts[a] or 0) > 0, (counts[b] or 0) > 0
		if na ~= nb then return na end
		return order[a] < order[b]
	end)
	return list
end

---------------------------------------------------------------------------
-- Learning item drop sources from loot
---------------------------------------------------------------------------

local function AddSource(item, mob)
	db.itemSources[item] = db.itemSources[item] or {}
	for _, existing in ipairs(db.itemSources[item]) do
		if existing == mob then return false end
	end
	tinsert(db.itemSources[item], mob)
	return true
end

local Readable = ns.Readable

local function RememberUnit(unit)
	local guid, name = Readable(UnitGUID(unit)), Readable(UnitName(unit))
	if guid and name then
		guidNames[guid] = name
		-- Learn the creature's NPC ID (6th part of a Creature GUID) for its face on the badges.
		if guid:match("^Creature") and not db.mobIDs[name] then
			db.mobIDs[name] = tonumber((select(6, strsplit("-", guid))))
		end
	end
end

-- A living, attackable unit's readable name, or nil. For mobs you aren't targeting the game
-- can keep "dead?" and "attackable?" secret; a secret answer is treated as alive and
-- attackable rather than skipping the mob. The name must be readable, since that's how
-- the mob is identified; any error just skips the unit.
local function EnemyName(unit)
	local ok, name = pcall(function()
		if not UnitExists(unit) then return nil end
		if Readable(UnitIsDead(unit)) == true then return nil end
		if Readable(UnitCanAttack("player", unit)) == false then return nil end
		return Readable(UnitName(unit))
	end)
	return ok and name or nil
end

-- Someone else's mob: tapped by a player outside your group, or already hurt and fighting a
-- player (or their pet) who isn't you or in your group. Those aren't worth running to.
-- Anything the game keeps secret counts as "not taken", so a mob is never skipped on a guess.
-- (0.55.0) Creature health is secret on this client for anything but your target, so "already
-- hurt" can't be read: a mob in combat with someone who isn't you, your pet or your group counts
-- as taken whatever its health, and so does a tapped one, or one marked as another's kill.
local function Mine(foe)
	for _, mine in ipairs({ "player", "pet" }) do
		if Readable(UnitIsUnit(foe, mine)) == true then return true end
	end
	-- (your group and their pets: a hunter's pet fighting it doesn't make it someone else's)
	local inParty = UnitPlayerOrPetInParty or UnitInParty
	local inRaid = UnitPlayerOrPetInRaid or UnitInRaid
	return Readable(inParty(foe)) == true or Readable(inRaid(foe)) and true or false
end
local function Taken(unit)
	local ok, taken = pcall(function()
		if UnitIsTapDenied and Readable(UnitIsTapDenied(unit)) == true then return true end
		-- (a mob you or your group already tagged is yours, fight or not)
		if UnitIsTapped and UnitIsTappedByPlayer and Readable(UnitIsTapped(unit)) == true
			and Readable(UnitIsTappedByPlayer(unit)) == false and Readable(UnitIsTappedByAllThreatList and UnitIsTappedByAllThreatList(unit)) ~= true then
			return true
		end
		if Readable(UnitAffectingCombat(unit)) ~= true then return false end
		-- in a fight: whose? your threat on it says it's (also) yours
		if UnitThreatSituation then
			local t = Readable(UnitThreatSituation("player", unit))
			if type(t) == "number" then return false end
		end
		local foe = unit .. "target"
		if Readable(UnitExists(foe)) == true then
			if Mine(foe) then return false end
			return true -- fighting a player, their pet, or a guard: not yours to tag
		end
		return false -- (fighting, but whom can't be read: never skipped on a guess)
	end)
	return ok and taken == true
end
QT.Taken = Taken

local function LearnFromLoot()
	if not db.learnFromLoot or not GetLootSourceInfo then return end
	RememberUnit("target")
	RememberUnit("mouseover")
	for slot = 1, GetNumLootItems() do
		local link = GetLootSlotLink(slot)
		local item = link and link:match("%[(.-)%]")
		local obj = item and objectives[item]
		if obj and obj.kind == "item" then
			local sources = { GetLootSourceInfo(slot) }
			for i = 1, #sources, 2 do
				local guid = sources[i]
				local mob = guid and guid:match("^Creature") and guidNames[guid]
				if mob and not InDropData(item, mob) and AddSource(item, mob) then
					ns.Print(("Learned: %s drops from %s."):format(item, mob))
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Finding objective lines in the tracker
---------------------------------------------------------------------------

-- Walks the tracker's frames looking for visible text lines we can make a button for.
local function FindTrackerLines()
	local found = {}
	local titleRegions = {} -- quest title -> its line in the tracker
	local function scan(frame, depth)
		if depth > 15 or not frame:IsVisible() then return end
		for _, region in ipairs({ frame:GetRegions() }) do
			if region:GetObjectType() == "FontString" and region:IsVisible() then
				local text = region:GetText()
				local asTitle = TitleText(text)
				if asTitle and not titleRegions[asTitle] then titleRegions[asTitle] = region end
				local name = ObjectiveName(text)
				local targets = name and TargetsFor(name)
				if targets then
					found[#found + 1] = { key = name, targets = targets, quest = objectives[name].quest, region = region }
				else
					local title = TitleText(text)
					local turnin = title and objectives["turnin:" .. title]
					if turnin then
						found[#found + 1] = { key = "turnin:" .. title, targets = turnin.targets, quest = title, region = region,
							kind = "turnin", npcID = turnin.npcID }
					end
				end
			end
		end
		for _, child in ipairs({ frame:GetChildren() }) do
			scan(child, depth + 1)
		end
	end
	-- Every badge sits on its quest's title row, beside the game's own quest icon: turn-ins
	-- right next to it, a quest's kill and loot objectives side by side going left.
	local function Arrange()
		local perQuest = {}
		for _, line in ipairs(found) do
			local titleRegion = titleRegions[line.quest]
			if titleRegion then
				line.anchor = titleRegion
				perQuest[line.quest] = (perQuest[line.quest] or 0) + 1
				line.slot = perQuest[line.quest]
			else
				line.anchor, line.slot = line.region, 1 -- title not found: stay on the objective's own line
			end
		end
	end
	for _, rootName in ipairs(TRACKER_ROOTS) do
		local root = _G[rootName]
		if root and root.IsVisible then
			local before = #found
			scan(root, 0)
			if #found > before then
				Arrange()
				return found, root
			end
		end
	end
	return found
end

---------------------------------------------------------------------------
-- Nearby counting (enemy nameplates)
---------------------------------------------------------------------------

-- Rough distance from the game's interact checks: 1 = within ~10 yards, 2 = ~28, 3 = further.
-- Out of combat only (the checks are restricted on enemies in combat).
local function Closeness(unit)
	if not CheckInteractDistance or InCombatLockdown() then return 3 end
	local ok, near = pcall(CheckInteractDistance, unit, 3)
	if ok and Readable(near) then return 1 end
	ok, near = pcall(CheckInteractDistance, unit, 4)
	if ok and Readable(near) then return 2 end
	return 3
end

-- Living units by name that have a nameplate (anywhere around you, not just in front),
-- with the closest one kept: name -> { unit, closeness }. Friendly ones are for turn-ins.
local nearestPlate = {}

local function CountNearby()
	wipe(counts)
	wipe(nearestPlate)
	wipe(takenPlates)
	for i = 1, 40 do
		local unit = "nameplate" .. i
		local name = EnemyName(unit)
		if name then
			RememberUnit(unit)
			if Taken(unit) then
				-- visible, but not a target: not counted, targeted or marked
				takenPlates[name] = (takenPlates[name] or 0) + 1
				name = nil
			else
				counts[name] = (counts[name] or 0) + 1
			end
		else
			local ok, friendly = pcall(function()
				if not UnitExists(unit) or Readable(UnitIsDead(unit)) == true or Readable(UnitIsPlayer(unit)) ~= false then return nil end
				return Readable(UnitName(unit))
			end)
			name = ok and friendly or nil
		end
		if name then
			local close = Closeness(unit)
			local best = nearestPlate[name]
			if not best or close < best[2] then nearestPlate[name] = { unit, close } end
		end
	end
end

-- The nameplate of the closest match among names, or nil. (Declared near the top for MacroFor.)
function NearestPlate(names)
	local unit, close
	for _, name in ipairs(names) do
		local p = nearestPlate[name]
		if p and (not close or p[2] < close) then unit, close = p[1], p[2] end
	end
	return unit
end

-- Only someone else's mobs in sight for these names (so /targetexact would just pick one of them).
function OnlyTaken(names)
	local taken = false
	for _, name in ipairs(names) do
		if nearestPlate[name] then return false end
		if takenPlates[name] then taken = true end
	end
	return taken
end

local function CountFor(targets)
	local n, seen = 0, {}
	-- (a name listed twice - an alias that matches the name itself - counts once)
	for _, mob in ipairs(targets) do
		if not seen[mob] then seen[mob] = true n = n + (counts[mob] or 0) end
	end
	return n
end

---------------------------------------------------------------------------
-- Raid markers for other nearby quest mobs
---------------------------------------------------------------------------

-- Every mob name any current objective could want.
local function QuestMobSet()
	local set = {}
	for name, obj in pairs(objectives) do
		if obj.kind ~= "turnin" then
			for _, mob in ipairs(TargetsFor(name) or {}) do set[mob] = true end
		end
	end
	return set
end

-- Markers already on units we can see. Reading markers is allowed; only setting them is
-- blocked. In a group the marker on e.g. a party member's target can be secret; skip those.
local function UsedMarkers()
	local used = {}
	local function check(unit)
		local index = UnitExists(unit) and Readable(GetRaidTargetIndex(unit))
		if index then used[index] = true end
	end
	check("target")
	check("focus")
	check("mouseover")
	for i = 1, 40 do check("nameplate" .. i) end
	if IsInRaid() then
		for i = 1, 40 do check("raid" .. i .. "target") end
	else
		for i = 1, 4 do check("party" .. i .. "target") end
	end
	return used
end

-- Works out which visible quest mobs should get which free marker, as /tm lines that run
-- when you press a sword or the hotkey. Nameplate tokens can point at different mobs once
-- combat starts, and the macro can't be updated in combat, so the lines carry [nocombat].
local function BuildMarkLines()
	wipe(extraMarkLines)
	wipe(clearMarkLines)
	if not db.enabled then return end

	local mobs = QuestMobSet()
	local free = {}
	local used = UsedMarkers()
	for _, index in ipairs(EXTRA_MARKERS) do
		if not used[index] then free[#free + 1] = index end
	end

	local assigned = 0
	for i = 1, 40 do
		local unit = "nameplate" .. i
		local name = EnemyName(unit)
		local marker = name and mobs[name] and GetRaidTargetIndex(unit)
		-- A secret marker means we can't tell whether it's marked: leave that mob alone.
		if name and mobs[name] and not (marker ~= nil and not Readable(marker)) then
			if marker then
				if #clearMarkLines < MAX_CLEAR_LINES then
					clearMarkLines[#clearMarkLines + 1] = ("/tm [@%s,nocombat,exists] 0"):format(unit)
				end
			elseif db.markNearby and assigned < db.markNearbyMax and assigned < #free and not Taken(unit) then
				assigned = assigned + 1
				extraMarkLines[#extraMarkLines + 1] = ("/tm [@%s,nocombat,harm,nodead] !%d"):format(unit, free[assigned])
			end
		end
	end
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------

-- Hidden secure button driven by the keybinding.
local targetButton = CreateFrame("Button", "AzerothAlmanacQuestTargetButton", UIParent, "SecureActionButtonTemplate")
targetButton:SetAttribute("type", "macro")
targetButton:RegisterForClicks("AnyUp", "AnyDown")

-- Hidden secure button for the "clear markers" keybinding.
local clearButton = CreateFrame("Button", "AzerothAlmanacClearMarksButton", UIParent, "SecureActionButtonTemplate")
clearButton:SetAttribute("type", "macro")
clearButton:RegisterForClicks("AnyUp", "AnyDown")

local function UpdateClearButton()
	local macro = db.clearHotkey and #clearMarkLines > 0 and table.concat(clearMarkLines, "\n") or nil
	if clearButton.macro ~= macro then
		clearButton.macro = macro
		clearButton:SetAttribute("macrotext", macro)
	end
end

local function UpdateLook()
	for _, b in ipairs(buttons) do
		if b.key then
			local selected = b.key == db.selected
			b.icon:SetVertexColor(1, 1, 1, selected and 1 or 0.7)
			b.ring:SetAlpha(selected and 1 or 0.75)
			b.portrait:SetAlpha(selected and 1 or 0.85)
			b.sel:SetShown(selected)
		end
	end
end

local function ApplySelection()
	UpdateLook()
	if InCombatLockdown() then
		pendingSelection = true
		return
	end
	pendingSelection = false
	local targets = db.selected and TargetsFor(db.selected)
	local kind = db.selected and objectives[db.selected] and objectives[db.selected].kind
	local macro = targets and MacroFor(targets, kind) or nil
	if targetButton.macro ~= macro then
		targetButton.macro = macro
		targetButton:SetAttribute("macrotext", macro)
	end
end

local function UpdateCounts()
	if not db.enabled then return end -- (off: no nameplate scan at all, 0.62.0)
	CountNearby()
	for _, b in ipairs(buttons) do
		if b.key then
			local n = CountFor(b.targets)
			b.count:SetShown(db.showCounts and b.kind ~= "turnin") -- friendly NPCs aren't counted
			b.count:SetText(n)
			if n > 0 then
				b.count:SetTextColor(0.3, 1, 0.3)
			else
				b.count:SetTextColor(0.5, 0.5, 0.5)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Turn-in NPC portraits
---------------------------------------------------------------------------

-- An NPC's appearance (display ID) is found by loading it by NPC ID into a hidden model, then
-- the game paints that appearance as a portrait. Display IDs are saved, so it's instant later.
local resolver, resolveQueue, resolving, tries = nil, {}, nil, {}
local StyleAllBadges -- forward

local function ResolveNext()
	if resolving or #resolveQueue == 0 then return end
	resolving = table.remove(resolveQueue, 1)
	if not resolver then
		resolver = CreateFrame("PlayerModel", nil, UIParent)
		resolver:SetSize(1, 1)
		resolver:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10, -10) -- off screen
	end
	-- Clear first: when the NPC isn't in the game's cache yet, SetCreature leaves the model as it
	-- was, and the previous NPC's appearance (often a human turn-in NPC) used to be saved as this
	-- one's face.
	local before
	if resolver.ClearModel then pcall(resolver.ClearModel, resolver) end
	local okBefore, shown = pcall(resolver.GetDisplayInfo, resolver)
	before = okBefore and shown or 0
	pcall(resolver.SetCreature, resolver, resolving)
	C_Timer.After(0.6, function()
		local id = resolving
		resolving = nil
		local ok, display = pcall(resolver.GetDisplayInfo, resolver)
		display = ok and ns.Readable(display) or nil
		-- only a fresh appearance counts (not what the model showed before this NPC was asked for)
		if type(display) == "number" and display > 0 and display ~= before then
			db.displayIDs[id] = display
			StyleAllBadges()
		elseif (tries[id] or 0) < 3 then
			tries[id] = (tries[id] or 0) + 1
			tinsert(resolveQueue, id) -- the NPC may not be in the client's cache yet; try again later
		end
		ResolveNext()
	end)
end

local function Resolve(npcID)
	if not npcID or db.displayIDs[npcID] or resolving == npcID or (tries[npcID] or 0) >= 3 then return end
	for _, queued in ipairs(resolveQueue) do
		if queued == npcID then return end
	end
	tinsert(resolveQueue, npcID)
	ResolveNext()
end

-- A quest mob's NPC ID: from the Almanac's Bestiary, else learned from a mob you targeted or moused over.
local function MobID(name)
	return name and ((ns.QuestData and ns.QuestData.mobs and ns.QuestData.mobs[name]) or db.mobIDs[name])
end

-- Badges show a face with a small icon in the corner: the turn-in NPC with a "?", the quest mob
-- with a sword. Without a face, just the icon. (Only textures change here, so it's safe in combat.)
local function StyleBadge(b)
	local npcID
	if b.kind == "turnin" then
		npcID = db.turnInFaces and b.npcID
	else
		npcID = db.mobFaces and b.targets and MobID(b.targets[1])
	end
	local display = npcID and db.displayIDs[npcID]
	b.icon:ClearAllPoints()
	if display and SetPortraitTextureFromCreatureDisplayID then
		SetPortraitTextureFromCreatureDisplayID(b.portrait, display)
		b.portrait:Show()
		b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 3, -3)
		b.icon:SetSize(11, 11)
	else
		b.portrait:Hide()
		b.icon:SetPoint("CENTER")
		b.icon:SetSize(BUTTON_SIZE - 6, BUTTON_SIZE - 6)
		if npcID then Resolve(npcID) end
	end
	b.icon:SetTexture(b.kind == "turnin" and TURNIN_ICON or ATTACK_ICON)
end

function StyleAllBadges()
	for _, b in ipairs(buttons) do
		if b.key then StyleBadge(b) end
	end
end

local function CreateButton(i)
	local b = CreateFrame("Button", "AzerothAlmanacQuestButton" .. i, UIParent, "SecureActionButtonTemplate")
	b:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	b:SetFrameStrata("MEDIUM")
	b:SetAttribute("type", "macro")
	b:RegisterForClicks("AnyUp", "AnyDown")

	-- A round badge like the tracker's own quest icons: thin gold ring, dark middle, icon inside.
	b.sel = b:CreateTexture(nil, "BACKGROUND", nil, -1)
	b.sel:SetTexture(CIRCLE)
	b.sel:SetBlendMode("ADD")
	b.sel:SetPoint("CENTER")
	b.sel:SetSize(BUTTON_SIZE + 6, BUTTON_SIZE + 6)
	b.sel:SetVertexColor(1, 0.82, 0.25, 0.55)
	b.sel:Hide()

	b.ring = b:CreateTexture(nil, "BACKGROUND")
	b.ring:SetTexture(CIRCLE)
	b.ring:SetAllPoints()
	b.ring:SetVertexColor(0.72, 0.56, 0.24, 0.9)
	b.bg = b:CreateTexture(nil, "BORDER")
	b.bg:SetTexture(CIRCLE)
	b.bg:SetPoint("TOPLEFT", 1.5, -1.5)
	b.bg:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
	b.bg:SetVertexColor(0.1, 0.07, 0.04, 0.95)

	-- The turn-in NPC's face, cropped round inside the ring (see StyleBadge).
	b.portrait = b:CreateTexture(nil, "ARTWORK")
	b.portrait:SetPoint("TOPLEFT", 1.5, -1.5)
	b.portrait:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
	local mask = b:CreateMaskTexture()
	mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(b.portrait)
	b.portrait:AddMaskTexture(mask)
	b.portrait:Hide()

	b.icon = b:CreateTexture(nil, "OVERLAY")
	b.icon:SetPoint("CENTER")
	b.icon:SetSize(BUTTON_SIZE - 6, BUTTON_SIZE - 6)
	b.icon:SetTexture(ATTACK_ICON)

	local highlight = b:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetTexture(CIRCLE)
	highlight:SetAllPoints()
	highlight:SetBlendMode("ADD")
	highlight:SetVertexColor(1, 0.85, 0.4, 0.25)

	-- How many are nearby, on the badge's top-left corner (badges can sit side by side).
	b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	b.count:SetPoint("TOPLEFT", b, "TOPLEFT", -4, 4)

	b:SetScript("PostClick", function(self)
		if self.key and self.key ~= db.selected then
			db.selected = self.key
			ApplySelection()
		end
	end)
	b:SetScript("OnEnter", function(self)
		if not self.key then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		if self.kind == "turnin" then
			GameTooltip:AddLine("Turn in: " .. (self.quest or ""))
			GameTooltip:AddLine("Targets " .. table.concat(self.targets, " or "), 1, 1, 1)
			if db.markTurnIns then GameTooltip:AddLine("and marks them with a star.", 1, 1, 1) end
			GameTooltip:AddLine("Your keybind targets the last one you clicked.", 0.6, 0.6, 0.6, true)
			GameTooltip:Show()
			return
		end
		if self.key == self.targets[1] and #self.targets == 1 then
			GameTooltip:AddLine("Target nearest " .. self.key)
		else
			GameTooltip:AddLine("Target a mob for " .. self.key)
			for i, mob in ipairs(self.targets) do
				local r, g, bl = 1, 1, 1
				if i > MAX_SOURCES_IN_MACRO then r, g, bl = 0.5, 0.5, 0.5 end
				GameTooltip:AddDoubleLine(mob, (counts[mob] or 0) .. " near", r, g, bl, 0.6, 0.8, 1)
			end
		end
		if self.quest then GameTooltip:AddLine(self.quest, 1, 1, 1) end
		GameTooltip:AddLine(CountFor(self.targets) .. " nearby with a visible nameplate", 0.6, 0.8, 1)
		GameTooltip:AddLine("Your keybind targets the last one you clicked.", 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:Hide()
	return b
end

-- Lines the buttons up with the tracker. Secure buttons can only be moved, shown
-- or hidden out of combat, so during combat they stay where they were.
local function Layout()
	if InCombatLockdown() then return end

	CollectObjectives()
	CountNearby()
	BuildMarkLines()
	UpdateClearButton()
	local lines, root = {}, nil
	if db.enabled then
		lines, root = FindTrackerLines()
	end

	local uiScale = UIParent:GetEffectiveScale()
	local x = root and root:GetLeft() and root:GetLeft() * root:GetEffectiveScale() / uiScale - TRACKER_GAP

	for i, line in ipairs(lines) do
		local b = buttons[i] or CreateButton(i)
		buttons[i] = b
		local anchor = line.anchor or line.region
		local top, bottom = anchor:GetTop(), anchor:GetBottom()
		if x and top and bottom then
			local y = (top + bottom) / 2 * anchor:GetEffectiveScale() / uiScale
			local macro = MacroFor(line.targets, line.kind)
			if b.macro ~= macro then
				b.macro = macro
				b:SetAttribute("macrotext", macro)
			end
			b.key, b.targets, b.quest, b.kind, b.npcID = line.key, line.targets, line.quest, line.kind, line.npcID
			StyleBadge(b)
			b:ClearAllPoints()
			b:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", x - ((line.slot or 1) - 1) * (BUTTON_SIZE + BADGE_SPACING), y)
			b:Show()
		else
			b.key = nil
			b:Hide()
		end
	end
	for i = #lines + 1, #buttons do
		buttons[i].key = nil
		buttons[i]:Hide()
	end

	ApplySelection()
	UpdateCounts()
end

---------------------------------------------------------------------------
-- Module API (used by Settings)
---------------------------------------------------------------------------

function QT:OnInitialize(saved)
	db = saved.questTargeter
	-- Faces saved before 2026-09-30 could be another NPC's (see ResolveNext); look them up again.
	if (db.facesVersion or 0) < 2 then
		wipe(db.displayIDs)
		db.facesVersion = 2
	end
end

function QT:OnLogin()
	local events = CreateFrame("Frame")
	events:SetScript("OnEvent", function(_, event, ...)
		if event == "PLAYER_REGEN_ENABLED" then
			Layout()
			if pendingSelection then ApplySelection() end
		elseif event == "PLAYER_TARGET_CHANGED" then
			RememberUnit("target")
		elseif event == "UPDATE_MOUSEOVER_UNIT" then
			RememberUnit("mouseover")
		elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
			LearnFromLoot()
		elseif event == "QUEST_TURNED_IN" then
			-- Remember who took the quest back, for quests the database doesn't know.
			local questID = ...
			local who = Readable(UnitName("questnpc")) or Readable(UnitName("npc"))
			if questID and who then
				db.learnedFinishers[questID] = who
				-- Their NPC ID (6th part of a Creature GUID), for the portrait.
				local guid = Readable(UnitGUID("questnpc")) or Readable(UnitGUID("npc"))
				local npcID = guid and guid:match("^Creature") and tonumber((select(6, strsplit("-", guid))))
				if npcID then db.learnedFinisherIDs[questID] = npcID end
			end
		else
			UpdateCounts()
		end
	end)
	for _, event in ipairs({
		"PLAYER_REGEN_ENABLED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
		"PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "LOOT_READY", "LOOT_OPENED", "QUEST_TURNED_IN",
	}) do
		events:RegisterEvent(event)
	end

	Layout()
	-- The tracker reflows on its own schedule, so re-check a few times a second.
	C_Timer.NewTicker(0.25, function()
		Layout()
		if InCombatLockdown() then UpdateCounts() end
	end)
end

-- Out of combat this applies right away; in combat the next Layout after combat picks it up.
function QT:Refresh()
	Layout()
end

function QT:LearnedCount()
	local n = 0
	for _ in pairs(db.itemSources) do n = n + 1 end
	return n
end

function QT:DatabaseCount()
	local n = 0
	for _ in pairs(ns.Drops or {}) do n = n + 1 end
	return n
end

function QT:PrintSources()
	local any = false
	for item, mobs in pairs(db.itemSources) do
		any = true
		ns.Print(item .. ": " .. table.concat(mobs, ", "))
	end
	if not any then ns.Print("No drop sources learned yet. Loot a quest item to teach one.") end
end

function QT:ForgetLearned()
	wipe(db.itemSources)
	self:Refresh()
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

SLASH_AZALMQT1 = "/qt"
SlashCmdList.AZALMQT = function(msg)
	local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()

	if cmd == "" then
		if InCombatLockdown() then return ns.Print("Can't turn the buttons on or off during combat.") end
		db.enabled = not db.enabled
		Layout()
		ns.Print(db.enabled and "Quest tracker buttons on." or "Quest tracker buttons off.")
	elseif cmd == "link" then
		local item, mob = rest:match("^(.-)%s*=%s*(.+)$")
		if not item or item == "" then return ns.Print("Usage: /qt link Spider Ichor = Forest Lurker") end
		if AddSource(item, mob) then ns.Print(("%s now targets %s."):format(item, mob)) end
		Layout()
	elseif cmd == "unlink" and rest ~= "" then
		for item in pairs(db.itemSources) do
			if item:lower() == rest:lower() then
				db.itemSources[item] = nil
				ns.Print("Forgot the learned drop sources for " .. item .. ".")
				return Layout()
			end
		end
		ns.Print("No learned drop sources for " .. rest .. ".")
	elseif cmd == "sources" then
		QT:PrintSources()
	elseif cmd == "debug" then
		-- What Azeroth Almanac reads from every nameplate, to see why a mob isn't counted.
		local function show(v)
			if v == nil then return "nil" end
			if issecretvalue and issecretvalue(v) then return "|cffff9933<secret>|r" end
			return tostring(v)
		end
		local seen = 0
		for i = 1, 40 do
			local unit = "nameplate" .. i
			if UnitExists(unit) then
				seen = seen + 1
				local ok, err = pcall(function()
					ns.Print(("%s: name %s | dead %s | attackable %s | counted as %s"):format(unit,
						show(UnitName(unit)), show(UnitIsDead(unit)), show(UnitCanAttack("player", unit)),
						tostring(EnemyName(unit))))
				end)
				if not ok then ns.Print(unit .. ": error reading it: " .. tostring(err)) end
			end
		end
		ns.Print(("%d nameplates exist (nameplate distance setting: %s)."):format(seen, tostring(GetCVar("nameplateMaxDistance"))))
	else
		ns.Print("Quest Targeter commands:")
		ns.Print("/qt - turn the tracker buttons on or off")
		ns.Print("/qt link <item> = <mob> - set which mob drops a quest item")
		ns.Print("/qt unlink <item> - forget learned drop sources for an item")
		ns.Print("/qt sources - list the drop sources you've learned")
		ns.Print("/aa - open Azeroth Almanac settings")
	end
end
