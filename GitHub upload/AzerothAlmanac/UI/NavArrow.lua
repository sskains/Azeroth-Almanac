-- The navigation arrow (Shannon, 2026-10-11; DESIGN 98): Wild Gambit's gold winged pointer
-- (Media\Header_TurnGem) at the top of the screen, turning to lead you to
--   1. your map pin (the game's user waypoint: the Almanac's "Set waypoint" buttons, or one you drop
--      on the world map) - always first; cleared on arrival unless Settings say otherwise;
--   2. else the quest you've Focused in the quest tracker (the game's super-tracked quest): its
--      turn-in NPC once it's complete, else the nearest spot where you've seen or killed what its
--      unfinished objectives ask for (the creature, or a creature that drops the item);
--   3. else nothing. A quest with no known spot hides the arrow and says what's missing.
-- (Shannon, 2026-10-11; DESIGN 101) Where the game's own map marks the quest (C_QuestLog.GetQuestsOnMap:
-- the area of a quest in progress, the turn-in of a complete one), the arrow follows that too, met or
-- not: in progress, after your own nearest spot; complete, before the turn-in NPC you've met.
-- Distance and direction come from the map positions in world yards (Map % -> world through the
-- map's corners), so it works across zones on one continent; another continent shows its name only;
-- inside an instance (no position) it hides. Shift-drag moves it, right-click opens its menu.

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local NA = ns:NewModule("NavArrow")

local ART = "Interface\\AddOns\\AzerothAlmanac\\Media\\Header_TurnGem"
local GLOW = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"
NA.ARRIVE = 8          -- yards
NA.AREA = 40           -- yards: within this of a quest creature's recorded spot, you're in its area
NA.ON_COURSE = math.rad(15)
NA.SIZE = 56
local frame
local target          -- { kind = "pin" | "quest", map, x, y (percent), name, why }
local note            -- a line when there's no arrow ("Not found yet: ...")
local arrived = false

local function S() return ns.db and ns.db.settings.nav or {} end

---------------------------------------------------------------------------
-- Positions (pure, tested offline)
---------------------------------------------------------------------------

-- a position's x, y: a vector object (GetXY) or, as WoW Forever gives a map pin's, a plain { x, y }
local function XY(v)
	if type(v) ~= "table" then return nil end
	if v.GetXY then
		local ok, x, y = pcall(v.GetXY, v)
		if ok then return x, y end
	end
	return v.x, v.y
end
NA.XY = XY

-- a map's corners in world yards: { inst, top, left, bottom, right } (top/bottom = north, left/right = west)
local rects = {}
function NA.Rect(map)
	if rects[map] ~= nil then return rects[map] end
	rects[map] = false
	if not (map and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return false end
	local ok1, inst, tl = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(0, 0))
	local ok2, _, br = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(1, 1))
	if ok1 and ok2 and type(tl) == "table" and type(br) == "table" then
		local top, left = XY(tl)
		local bottom, right = XY(br)
		if top and left and bottom and right and top ~= bottom and left ~= right then
			rects[map] = { inst = inst, top = top, left = left, bottom = bottom, right = right }
		end
	end
	return rects[map]
end

-- a map spot (x, y in percent) in world yards: inst, north, west
function NA.World(map, x, y)
	local r = NA.Rect(map)
	if not (r and x and y) then return nil end
	local north = r.top + (r.bottom - r.top) * (y / 100)
	local west = r.left + (r.right - r.left) * (x / 100)
	return r.inst, north, west
end

-- from (n1, w1) to (n2, w2): distance in yards and the bearing (radians, 0 = north, counter-clockwise,
-- as GetPlayerFacing counts)
function NA.Bearing(n1, w1, n2, w2)
	local dn, dw = n2 - n1, w2 - w1
	local b = math.atan2(dw, dn)
	if b < 0 then b = b + 2 * math.pi end
	return math.sqrt(dn * dn + dw * dw), b
end

-- the turn from where you face to the bearing, in -pi..pi (positive: to your left)
function NA.Turn(bearing, facing)
	local d = (bearing - facing) % (2 * math.pi)
	if d > math.pi then d = d - 2 * math.pi end
	return d
end

-- where you stand: map, x, y in percent (not rounded)
local function Me()
	local map = ns.Readable(C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
	if not (map and C_Map.GetPlayerMapPosition) then return nil end
	local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
	if not (ok and pos and not ns.IsSecret(pos)) then return nil end
	local x, y = XY(pos)
	x, y = ns.Readable(x), ns.Readable(y)
	if type(x) ~= "number" or type(y) ~= "number" or (x == 0 and y == 0) then return nil end
	return map, x * 100, y * 100
end

---------------------------------------------------------------------------
-- Where to go
---------------------------------------------------------------------------

local function Pin()
	if not (C_Map and C_Map.HasUserWaypoint and C_Map.GetUserWaypoint) then return nil end
	local okHas, has = pcall(C_Map.HasUserWaypoint)
	if not (okHas and has) then return nil end
	local ok, p = pcall(C_Map.GetUserWaypoint)
	if not (ok and p and p.uiMapID and p.position) then return nil end
	local x, y = XY(p.position)
	if not (x and y) then return nil end
	local named = NA.pinFor
	local name = named and named.map == p.uiMapID and math.abs(named.x - x * 100) < 0.05 and math.abs(named.y - y * 100) < 0.05 and named.name
	return { kind = "pin", map = p.uiMapID, x = x * 100, y = y * 100, name = name or L["Your map pin"], why = L["Your map pin"] }
end
-- (the Almanac's own "Set waypoint" names its pin)
if W and W.Waypoint then
	local set = W.Waypoint
	W.Waypoint = function(map, x, y, name)
		NA.pinFor = map and x and y and { map = map, x = x, y = y, name = name } or nil
		return set(map, x, y, name)
	end
end

local function Focused()
	if not (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID) then return nil end
	local ok, q = pcall(C_SuperTrack.GetSuperTrackedQuestID)
	q = ok and ns.Readable(q)
	return q and q > 0 and q or nil
end

local function QuestTitle(q)
	if C_QuestLog and C_QuestLog.GetTitleForQuestID then
		local ok, t = pcall(C_QuestLog.GetTitleForQuestID, q)
		if ok and t then return t end
	end
	local rec = ns.Store:Get("quest", q)
	return rec and rec.name or ("#" .. q)
end

local function Complete(q)
	if C_QuestLog and C_QuestLog.IsComplete then
		local ok, done = pcall(C_QuestLog.IsComplete, q)
		if ok and done ~= nil then return done and true or false end
	end
	return false
end

-- the unfinished objectives' texts (lower case), or nil when the game doesn't say
local function Open(q)
	if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return nil end
	local ok, list = pcall(C_QuestLog.GetQuestObjectives, q)
	if not (ok and type(list) == "table") then return nil end
	local out = {}
	for _, o in ipairs(list) do if not o.finished and o.text then out[#out + 1] = o.text:lower() end end
	return out
end

local function Wanted(open, name)
	if not open then return true end
	if not name then return false end
	name = name:lower()
	for _, t in ipairs(open) do if t:find(name, 1, true) then return true end end
	return false
end

-- the spots (map percent) of the creatures that answer the quest's open objectives
local function Spots(q, db)
	local open = Open(q)
	local out = {}
	local function Add(npc, what)
		local c = ns.Store:Get("creature", npc)
		if not c then return end
		for _, field in ipairs({ "kz", "spots" }) do
			for map, list in pairs(c[field] or {}) do
				for _, s in ipairs(list) do
					local x, y = s:match("^([%d.]+):([%d.]+)$")
					if x then out[#out + 1] = { map = map, x = tonumber(x), y = tonumber(y), name = c.name or what } end
				end
			end
		end
	end
	for _, t in ipairs(db.targets or {}) do
		if not t.object then
			local c = ns.Store:Get("creature", t.id)
			if c and Wanted(open, c.name) then Add(t.id) end
		end
	end
	local IDB = ns.ItemDB
	for _, it in ipairs(db.items or {}) do
		local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(it.id)) or (GetItemInfo and GetItemInfo(it.id))
		local rec = ns.Store:Get("item", it.id)
		name = name or (rec and rec.name)
		if Wanted(open, name) then
			local idb = IDB and IDB:Get(it.id)
			for _, d in ipairs(idb and idb.drops or {}) do Add(d[1] or d.id, name) end
		end
	end
	return out
end

-- the game's marker for the quest, from the map you're on up to the continent (Forever answers on
-- the zone and the continent maps; the waypoint calls give nothing): { map, x, y } in percent, or nil
local function GameMarker(q)
	local QL = C_QuestLog
	if not (QL and QL.GetQuestsOnMap and C_Map and C_Map.GetBestMapForUnit) then return nil end
	local map = ns.Readable(C_Map.GetBestMapForUnit("player"))
	for _ = 1, 5 do
		if not map then return nil end
		local ok, list = pcall(QL.GetQuestsOnMap, map)
		if ok and type(list) == "table" then
			for _, e in ipairs(list) do
				local x, y = ns.Readable(e.x), ns.Readable(e.y)
				if ns.Readable(e.questID) == q and type(x) == "number" and type(y) == "number" then
					return { map = map, x = x * 100, y = y * 100 }
				end
			end
		end
		local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
		map = info and info.parentMapID
		if map == 0 then map = nil end
	end
end
NA.GameMarker = GameMarker
NA.GAME_AREA = 60      -- yards: the game marks the middle of a quest's area, which is wide

-- yards from you to a map spot (nil when either isn't placeable, or on another continent)
local function YardsTo(map, x, y)
	local me, mx, my = Me()
	if not me then return nil end
	local mi, mn, mw = NA.World(me, mx, my)
	local ti, tn, tw = NA.World(map, x, y)
	if not (mi and ti and mi == ti) then return nil end
	return (NA.Bearing(mn, mw, tn, tw))
end

local function QuestTarget(q)
	local Q, QDB = ns.Quests, ns.QuestDB
	local db = QDB and QDB:Get(q)
	local rec = ns.Store:Get("quest", q) or {}
	local title = QuestTitle(q)
	if Complete(q) then
		local turnIn = (L["Turn in: %s"]):format(title)
		local g = GameMarker(q)
		if g then
			-- who takes it: as met, else as the quest database names them, else just "Turn in"
			local who = rec.ender and rec.ender.name
			if not who and db and Q then
				for _, e in ipairs(db.enders or {}) do who = who or (Q:NameOf(e.id, e.object)) end
			end
			return { kind = "quest", map = g.map, x = g.x, y = g.y, name = who or L["Turn in"], why = turnIn }
		end
		local pos = rec.epos
		if not pos and db and Q then
			for _, e in ipairs(db.enders or {}) do
				local name, met = Q:NameOf(e.id, e.object)
				if name and met and met.map and met.x then pos = { name = name, map = met.map, x = met.x, y = met.y } break end
			end
		end
		if pos and pos.map and pos.x then
			return { kind = "quest", map = pos.map, x = pos.x, y = pos.y, name = pos.name or rec.ender and rec.ender.name or L["Turn in"],
				why = (L["Turn in: %s"]):format(title) }
		end
		return nil, (L["Turn in %s: you haven't met who takes it yet."]):format(title)
	end
	-- the game's marker for its area: after your own spots (they're exact), or alone for a quest the
	-- database doesn't have (WoW Forever's own)
	local function FromGame()
		local g = GameMarker(q)
		if not g then return nil end
		local d = YardsTo(g.map, g.x, g.y)
		if d and d <= NA.GAME_AREA then return nil, (L["%s: around here"]):format(title), true end
		return { kind = "quest", map = g.map, x = g.x, y = g.y, name = title, why = title, game = true }
	end
	if not db then
		local t, why, area = FromGame()
		if t or why then return t, why, area end
		return nil, (L["%s: no known place yet."]):format(title)
	end
	local me, mx, my = Me()
	local mi, mn, mw
	if me then mi, mn, mw = NA.World(me, mx, my) end
	local best, bestD
	for _, s in ipairs(Spots(q, db)) do
		local inst, n, w = NA.World(s.map, s.x, s.y)
		if inst then
			local d = (mi == inst and mn) and NA.Bearing(mn, mw, n, w) or 1e9
			if not bestD or d < bestD then best, bestD = s, d end
		end
	end
	-- (2026-10-11) a spot is where *you* stood when you saw or killed it, not where the creature is:
	-- close to one, you're in its area, so say so instead of "Arrived" with nothing in front of you
	if best and bestD and bestD <= NA.AREA then
		return nil, (L["%s: around here"]):format(best.name or title), true
	end
	if best then
		return { kind = "quest", map = best.map, x = best.x, y = best.y, name = best.name, why = title }
	end
	local t, why, area = FromGame()
	if t or why then return t, why, area end
	return nil, (L["%s: not found yet."]):format(title)
end

function NA:Resolve()
	local s = S()
	note = nil
	if s.enabled == false then target = nil return end
	local pin = Pin()
	if pin then
		if not (target and target.kind == "pin" and target.map == pin.map and math.abs(target.x - pin.x) < 0.01 and math.abs(target.y - pin.y) < 0.01) then arrived = false end
		target = pin
		return
	end
	local q = Focused()
	if q then
		local t, why, area = QuestTarget(q)
		target, note, NA.inArea = t, why, area
		return
	end
	target = nil
end

---------------------------------------------------------------------------
-- The arrow
---------------------------------------------------------------------------

local function Build()
	frame = CreateFrame("Button", "AzerothAlmanacNavArrow", UIParent)
	frame:SetSize(NA.SIZE + 140, NA.SIZE + 40)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:RegisterForClicks("RightButtonUp")
	local p = S().point
	if p then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else frame:SetPoint("TOP", UIParent, "TOP", 0, -24) end
	frame:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local a, _, b, x, y = self:GetPoint()
		ns.db.settings.nav.point = { a, b, x, y }
	end)
	frame.glow = frame:CreateTexture(nil, "BACKGROUND")
	frame.glow:SetTexture(GLOW)
	frame.glow:SetBlendMode("ADD")
	frame.glow:SetSize(NA.SIZE * 1.6, NA.SIZE * 1.6)
	frame.glow:SetPoint("TOP", 0, NA.SIZE * 0.3 - 2)
	frame.glow:SetVertexColor(1, 0.85, 0.35, 0.9)
	frame.glow:Hide()
	frame.arrow = frame:CreateTexture(nil, "ARTWORK")
	frame.arrow:SetTexture(ART)
	frame.arrow:SetSize(NA.SIZE, NA.SIZE)
	frame.arrow:SetPoint("TOP", 0, 0)
	frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.name:SetPoint("TOP", frame.arrow, "BOTTOM", 0, -1)
	frame.name:SetWidth(NA.SIZE + 220)
	frame.name:SetWordWrap(false)
	frame.dist = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.dist:SetPoint("TOP", frame.name, "BOTTOM", 0, -1)
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(target and target.name or L["Navigation arrow"], 1, 0.82, 0.25)
		if target then GameTooltip:AddLine(target.why, 1, 1, 1, true) end
		if note then GameTooltip:AddLine(note, 0.8, 0.8, 0.8, true) end
		GameTooltip:AddLine(L["Shift-drag to move  ·  Right-click for options"], 0.55, 0.55, 0.55)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", GameTooltip_Hide)
	frame:SetScript("OnClick", function(self)
		W.Menu(self, {
			{ text = L["Clear the map pin"], run = function() if C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end NA:Resolve() NA:Paint() end },
			{ text = L["Hide the arrow"], run = function() ns.db.settings.nav.enabled = false NA:Resolve() NA:Paint() ns.Print(L["Navigation arrow off: Settings > Quest Targeter turns it back on."]) end },
			{ text = L["Reset its position"], run = function() ns.db.settings.nav.point = nil frame:ClearAllPoints() frame:SetPoint("TOP", UIParent, "TOP", 0, -24) end },
		})
	end)
	frame.elapsed = 0
	frame:SetScript("OnUpdate", function(self, e)
		self.elapsed = self.elapsed + e
		if self.elapsed < 0.05 then return end
		self.elapsed = 0
		NA:Paint()
	end)
	frame:Hide()
end

local function Yards(d)
	if d >= 1000 then return ("%.1f km"):format(d / 1000 * 0.9144) end
	return (L["%d yd"]):format(math.floor(d + 0.5))
end

-- (2026-10-11) the arrow paints 20 times a second: text only goes to the game when it changed
local function Put(fs, text)
	if fs.shown ~= text then fs.shown = text fs:SetText(text) end
end

function NA:Paint()
	if not frame then return end
	local s = S()
	if s.enabled == false or not (target or note) then frame:Hide() return end
	local scale = s.scale or 1
	if frame.scale ~= scale then frame.scale = scale frame:SetScale(scale) end -- (20 times a second: only when it changes)
	if not frame:IsShown() then frame:Show() end
	if not target then
		frame.arrow:Hide() frame.glow:Hide()
		Put(frame.name, (NA.inArea and "|cffffd100" or "|cffbbbbbb") .. (note or "") .. "|r")
		Put(frame.dist, "")
		return
	end
	Put(frame.name, target.name or "")
	local me, mx, my = Me()
	local mi, mn, mw
	if me then mi, mn, mw = NA.World(me, mx, my) end
	local ti, tn, tw = NA.World(target.map, target.x, target.y)
	if not (mi and ti) then
		frame.arrow:Hide() frame.glow:Hide()
		Put(frame.dist, L["No position here"])
		return
	end
	if mi ~= ti then
		local info = C_Map.GetMapInfo and C_Map.GetMapInfo(target.map)
		frame.arrow:Hide() frame.glow:Hide()
		Put(frame.dist, (L["In %s"]):format(info and info.name or "?"))
		return
	end
	local d, bearing = NA.Bearing(mn, mw, tn, tw)
	if d <= NA.ARRIVE then
		frame.arrow:Hide() frame.glow:Show()
		Put(frame.dist, "|cff40ff40" .. L["Arrived"] .. "|r")
		if not arrived then
			arrived = true -- (silent: Shannon, 2026-10-11)
			if target.kind == "pin" and s.clearPin ~= false and C_Map.ClearUserWaypoint then
				C_Timer.After(1.5, function() pcall(C_Map.ClearUserWaypoint) NA:Resolve() NA:Paint() end)
			end
		end
		return
	end
	arrived = false
	local facing = GetPlayerFacing and ns.Readable(GetPlayerFacing())
	local text = Yards(d)
	local speed = GetUnitSpeed and ns.Readable((GetUnitSpeed("player")))
	if s.eta ~= false and type(speed) == "number" and speed > 0.5 then
		local secs = d / speed
		text = text .. "  ·  " .. (secs >= 60 and ("%d:%02d"):format(math.floor(secs / 60), math.floor(secs % 60)) or ("%ds"):format(math.floor(secs + 0.5)))
	end
	Put(frame.dist, text)
	if type(facing) ~= "number" then frame.arrow:Hide() frame.glow:Hide() return end
	local turn = NA.Turn(bearing, facing)
	frame.arrow:Show()
	frame.arrow:SetRotation(turn + math.pi / 2)
	frame.glow:SetShown(math.abs(turn) <= NA.ON_COURSE)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

function NA:OnLogin()
	Build()
	local function Update() NA:Resolve() NA:Paint() end
	for _, e in ipairs({ "USER_WAYPOINT_UPDATED", "SUPER_TRACKING_CHANGED", "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE",
		"ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
		ns:RegisterEvent(e, Update)
	end
	-- (records grow as you play: a new spot may be nearer)
	C_Timer.NewTicker(2, function() if ns.db.settings.nav.enabled ~= false then NA:Resolve() end end)
	Update()
end

function NA:Refresh() NA:Resolve() NA:Paint() end

-- (Shannon, 2026-10-11; DESIGN 101) /aa navprobe [questID]: what the game itself says about where a
-- quest is (the newer map's quest markers), to see which of these WoW Forever has before the arrow
-- uses them for quests whose creatures and NPCs you haven't met
local function Fmt(v)
	if type(v) == "number" then return (v == math.floor(v) and "%d" or "%.4f"):format(v) end
	if type(v) == "table" then
		local x, y = XY(v)
		if x then return ("(%.4f, %.4f)"):format(x, y) end
		local parts = {}
		for k, w in pairs(v) do
			if #parts >= 12 then parts[#parts + 1] = "..." break end
			parts[#parts + 1] = tostring(k) .. "=" .. (type(w) == "table" and (XY(w) and Fmt(w) or "{...}") or tostring(w))
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(v)
end
local function Call(label, fn, ...)
	if type(fn) ~= "function" then ns.Print(("  %s: |cff999999not on this client|r"):format(label)) return end
	local r = { pcall(fn, ...) }
	if not r[1] then ns.Print(("  %s: |cffff6060error|r %s"):format(label, tostring(r[2]))) return end
	local out = {}
	for i = 2, math.max(2, #r) do out[#out + 1] = Fmt(r[i]) end
	ns.Print(("  %s: %s"):format(label, table.concat(out, ", ")))
	return select(2, unpack(r))
end

function NA:Probe(arg)
	local q = tonumber(arg) or Focused()
	if not q and C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
		for i = 1, C_QuestLog.GetNumQuestLogEntries() do
			local info = C_QuestLog.GetInfo(i)
			if info and not info.isHeader and info.questID then q = info.questID break end
		end
	end
	ns.Print("|cff9be36bNavigation probe|r (send these lines to Claude)")
	if not q then ns.Print("  no quest: Focus one in the quest tracker, or /aa navprobe <questID>") return end
	ns.Print(("  quest %d: %s, %s"):format(q, QuestTitle(q), Complete(q) and "complete" or "in progress"))
	local QL = C_QuestLog or {}
	-- what this client offers (names only)
	local names = {}
	for k, v in pairs(QL) do
		if type(v) == "function" and (k:find("Waypoint") or k:find("Map") or k:find("POI")) then names[#names + 1] = k end
	end
	table.sort(names)
	ns.Print("  C_QuestLog: " .. (#names > 0 and table.concat(names, " ") or "none"))
	local extra = {}
	for _, k in ipairs({ "QuestPOIGetIconInfo", "QuestPOIGetSecondaryLocations", "GetQuestPOIBlobCount", "QuestMapUpdateAllQuests" }) do
		if type(_G[k]) == "function" then extra[#extra + 1] = k end
	end
	if C_TaskQuest then extra[#extra + 1] = "C_TaskQuest" end
	if C_QuestInfoSystem then extra[#extra + 1] = "C_QuestInfoSystem" end
	ns.Print("  others: " .. (#extra > 0 and table.concat(extra, " ") or "none"))
	-- the quest's own answers
	Call("GetNextWaypoint", QL.GetNextWaypoint, q)
	Call("GetNextWaypointText", QL.GetNextWaypointText, q)
	Call("GetQuestUiMapID", QL.GetQuestUiMapID, q)
	Call("QuestPOIGetIconInfo", _G.QuestPOIGetIconInfo, q)
	-- the maps from where you stand up to the continent: is the quest on each, and where
	local map = ns.Readable(C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
	for _ = 1, 4 do
		if not map then break end
		local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
		local label = ("map %d %s"):format(map, info and info.name or "?")
		Call(label .. " GetNextWaypointForMap", QL.GetNextWaypointForMap, q, map)
		if type(QL.GetQuestsOnMap) == "function" then
			local ok, list = pcall(QL.GetQuestsOnMap, map)
			local found
			for _, e in ipairs(ok and type(list) == "table" and list or {}) do
				if e.questID == q then found = e end
			end
			ns.Print(("  %s GetQuestsOnMap: %s (%d quests on it)"):format(label, found and Fmt(found) or "not on it",
				ok and type(list) == "table" and #list or 0))
		end
		if C_TaskQuest and C_TaskQuest.GetQuestLocation then Call(label .. " TaskQuest", C_TaskQuest.GetQuestLocation, q, map) end
		map = info and info.parentMapID
		if map == 0 then map = nil end
	end
end

function NA:Target() return target, note end
