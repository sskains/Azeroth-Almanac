-- /aa maptest: a development check for the planned Travels trail (TASKS section 34) and for the
-- Almanac's world map pins. Draws the playing character's journal points on the open world map as a
-- line through time (old = dark red, recent = bright gold) with a dot at every point, and prints what
-- the client allowed: line objects, how many points fit this map, and the gathering / townsfolk pins.
--   /aa maptest          toggle the test trail (your character) and print the report
--   /aa maptest all      every character, each in its class colour
--   /aa maptest dots     dots only (the fallback if lines don't draw)
--   /aa maptest off      remove it
-- Nothing here is saved; it only reads AzerothAlmanacDB.journal.

local _, ns = ...
local MT = ns:NewModule("MapTest")

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local GAP = 2 * 3600          -- more than this between two points: the line breaks (a new session)
local JUMP = 0.35             -- more than this much of the map between two points: break (hearth, boat)

local overlay
local lines, dots = {}, {}
local mode = nil              -- nil (off), "me", "all", "dots"
local report = {}

local function Canvas()
	local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
	return sc and (sc.Child or sc.child) or nil
end

-- a journal point (map, x, y in percent) on the shown map, 0..1, via the maps' world corners
local function ToShown(map, x, y, shown)
	if not (map and x and y) then return nil end
	if map == shown then return x / 100, y / 100 end
	local Rect = ns.Townsfolk and ns.Townsfolk.MapRect
	local a, b = Rect and Rect(map), Rect and Rect(shown)
	if not (a and b) or a.inst ~= b.inst then return nil end
	local north = a.top - (y / 100) * (a.top - a.bottom)
	local west = a.left - (x / 100) * (a.left - a.right)
	local px = (b.left - west) / (b.left - b.right)
	local py = (b.top - north) / (b.top - b.bottom)
	if px < 0 or px > 1 or py < 0 or py > 1 then return nil end
	return px, py
end

local function Clear()
	for _, l in ipairs(lines) do l:Hide() end
	for _, d in ipairs(dots) do d:Hide() end
end

local function Line(i)
	local l = lines[i]
	if not l then
		l = overlay:CreateLine(nil, "OVERLAY")
		lines[i] = l
	end
	return l
end

local function Dot(i)
	local d = dots[i]
	if not d then
		d = overlay:CreateTexture(nil, "OVERLAY", nil, 2)
		d:SetTexture(CIRCLE)
		dots[i] = d
	end
	return d
end

local function Color(age, cls)
	if cls then return cls.r, cls.g, cls.b end
	-- age 0 (oldest) .. 1 (newest): dark red to bright gold
	return 0.45 + 0.55 * age, 0.12 + 0.73 * age, 0.08 + 0.12 * age
end

local function Draw()
	report = {}
	if not mode then if overlay then Clear() end return end
	local canvas = Canvas()
	local shown = WorldMapFrame and WorldMapFrame:GetMapID()
	if not (canvas and shown) then
		report[#report + 1] = "|cffff6060No world map canvas found.|r"
		return
	end
	if not overlay then
		overlay = CreateFrame("Frame", "AzerothAlmanacMapTest", canvas)
		overlay:SetAllPoints(canvas)
	end
	overlay:SetParent(canvas)
	overlay:SetAllPoints(canvas)
	overlay:SetFrameLevel(canvas:GetFrameLevel() + 2000)
	overlay:Show()
	Clear()
	local w, h = canvas:GetSize()
	local canLines = overlay.CreateLine ~= nil
	local useLines = canLines and mode ~= "dots"

	-- the points, per character, oldest first
	local me = ns.CharKey()
	local byChar, total = {}, 0
	local first, last
	for _, e in ipairs(ns.db.journal or {}) do
		if e.m and e.x and (mode == "all" or e.c == me) then
			total = total + 1
			local px, py = ToShown(e.m, e.x, e.y, shown)
			if px then
				byChar[e.c] = byChar[e.c] or {}
				local list = byChar[e.c]
				list[#list + 1] = { x = px, y = py, t = e.t or 0 }
				first = math.min(first or e.t, e.t)
				last = math.max(last or e.t, e.t)
			end
		end
	end

	local nl, nd, onMap = 0, 0, 0
	local span = math.max(1, (last or 1) - (first or 0))
	local thick = math.max(2, w / 400)
	local dotSize = math.max(5, w / 180)
	for key, list in pairs(byChar) do
		local cls
		if mode == "all" then
			local c = ns.db.chars[key]
			cls = c and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.classFile]
		end
		for i, p in ipairs(list) do
			onMap = onMap + 1
			local age = (p.t - first) / span
			local r, g, b = Color(age, cls)
			nd = nd + 1
			local d = Dot(nd)
			d:SetSize(dotSize, dotSize)
			d:ClearAllPoints()
			d:SetPoint("CENTER", overlay, "TOPLEFT", p.x * w, -p.y * h)
			d:SetVertexColor(r, g, b, 1)
			d:Show()
			local prev = list[i - 1]
			if useLines and prev and (p.t - prev.t) <= GAP
				and ((p.x - prev.x) ^ 2 + (p.y - prev.y) ^ 2) <= JUMP * JUMP then
				nl = nl + 1
				local l = Line(nl)
				l:SetThickness(thick)
				l:SetColorTexture(r, g, b, 0.85)
				l:SetStartPoint("TOPLEFT", overlay, prev.x * w, -prev.y * h)
				l:SetEndPoint("TOPLEFT", overlay, p.x * w, -p.y * h)
				l:Show()
			end
		end
	end

	local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(shown)
	report[#report + 1] = ("Trail test on %s (map %d, canvas %d x %d): line objects %s."):format(
		info and info.name or "?", shown, w, h, canLines and "|cff60ff60available|r" or "|cffff6060NOT available|r")
	report[#report + 1] = ("  %d journal points with a position, %d fit this map: %d dots, %d line segments."):format(total, onMap, nd, nl)
	if first then
		report[#report + 1] = ("  From %s to %s."):format(date("%b %d %H:%M", first), date("%b %d %H:%M", last))
	end
	if onMap == 0 then report[#report + 1] = "  Nothing on this map: try the continent map (Kalimdor / Eastern Kingdoms)." end
end

local function Report()
	local out = {}
	for _, l in ipairs(report) do out[#out + 1] = l end
	if ns.NodePins and ns.NodePins.Diagnose then pcall(ns.NodePins.Diagnose, ns.NodePins, out) end
	if ns.Townsfolk and WorldMapFrame and WorldMapFrame.EnumeratePinsByTemplate then
		local n = 0
		pcall(function() for _ in WorldMapFrame:EnumeratePinsByTemplate("AzerothAlmanacTownsfolkPinTemplate") do n = n + 1 end end)
		out[#out + 1] = ("Townsfolk pins on the map: %d (mixin %s)"):format(n,
			(AzerothAlmanacTownsfolkPinMixin and AzerothAlmanacTownsfolkPinMixin.SetPosition) and "ready" or "NOT READY")
	end
	for _, l in ipairs(out) do ns.Print(l) end
end

local hooked
local function Hook()
	if hooked or not WorldMapFrame then return end
	hooked = true
	-- redraw when the map changes zone or opens; a frame later, once the canvas has its new size
	local function Later() if mode then C_Timer.After(0, function() pcall(Draw) end) end end
	if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", Later) end
	WorldMapFrame:HookScript("OnShow", Later)
end

function MT:Command(rest)
	rest = (rest or ""):lower()
	if rest == "off" then
		mode = nil
	elseif rest == "all" or rest == "dots" then
		mode = rest
	elseif rest == "" and mode then
		mode = nil              -- plain /aa maptest toggles it
	else
		mode = "me"
	end
	if not (WorldMapFrame and WorldMapFrame:IsShown()) then
		ns.Print("Open the world map first, then /aa maptest (try a continent map too).")
		if WorldMapFrame then Hook() end
		Report()
		return
	end
	Hook()
	local ok, err = pcall(Draw)
	if not ok then report = { "|cffff6060Draw failed:|r " .. tostring(err) } end
	if not mode then report = { "Trail test removed." } end
	-- give the pins a fresh pass so the counts are current
	if ns.NodePins and ns.NodePins.Refresh then pcall(ns.NodePins.Refresh, ns.NodePins) end
	Report()
end
