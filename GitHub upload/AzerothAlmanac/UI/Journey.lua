-- The Journey (0.69.0, #35; DESIGN section 74), shown small in the Journal's top right pane: where a
-- character went in a time frame, on the game's own map art, drawn as a time lapse (a gold line
-- through the places in the order you reached them, its head glowing) that then stays drawn.
--   local j = ns.Widgets.JourneyPane(parent, { onPick = function(entry) end })
--   j:SetCharacter(key)     -- a character's journey (nil: the header's "All characters")
--   j:Focus(entry)          -- turn to the entry's zone and light its marker (nil: back to the whole frame)
--   j:Refresh(replay)       -- redraw (replay: play the time lapse again)
-- Points: until the Journey recorder exists (DESIGN 74, "Recorder") the line runs through the
-- journal's own points (every discovery has a time, map, x and y), as /aa maptest draws them.
-- J.Points(from, char) is the one place that reads them, so the recorder only has to feed it.
-- Character mode: one line in gold. Account mode (everyone): each character in its class colour,
-- all on one clock. A gap of more than 2 hours, or a jump across the map, breaks the line.

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local J = {}
ns.Journey = J

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local GLOW = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"
local GAP = 2 * 3600
local JUMP = 0.35
local PLAY_TIME = 8          -- seconds for the whole time lapse in the small pane
local MAX_POINTS = 800       -- the newest points in the frame (the oldest are left off)
local GOLD = { 1, 0.82, 0.3 }

J.RANGES = {
	{ key = "today", label = L["Today"] },
	{ key = "week", label = L["Week"] },
	{ key = "month", label = L["Month"] },
	{ key = "all", label = L["All"] },
}

-- when a time frame starts: today from midnight; week and month the last 7 and 30 days
function J.From(range)
	local now = time()
	if range == "today" then
		local d = date("*t", now)
		return time({ year = d.year, month = d.month, day = d.day, hour = 0 })
	elseif range == "week" then return now - 7 * 86400
	elseif range == "month" then return now - 30 * 86400 end
	return 0
end

-- the points from a time on, oldest first: { t, m, x, y, c, e } (e: the journal entry);
-- char nil: every character
function J.Points(from, char)
	local out = {}
	local j = ns.db and ns.db.journal or {}
	for i = #j, 1, -1 do
		local e = j[i]
		if (e.t or 0) < from then break end
		if e.m and e.x and e.y and (not char or e.c == char) then
			out[#out + 1] = { t = e.t or 0, m = e.m, x = e.x, y = e.y, c = e.c, e = e }
			if #out >= MAX_POINTS then break end
		end
	end
	-- (the journal is in time order; reversed here to oldest first)
	local n = #out
	for i = 1, math.floor(n / 2) do out[i], out[n + 1 - i] = out[n + 1 - i], out[i] end
	return out
end

local function MapInfo(map)
	if not (C_Map and C_Map.GetMapInfo and map) then return nil end
	local ok, info = pcall(C_Map.GetMapInfo, map)
	return ok and type(info) == "table" and info or nil
end

-- the continent a map is on (itself when it is one), or the map
local CONTINENT = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2
local function Continent(map)
	local m, guard = map, 0
	while m and guard < 8 do
		local info = MapInfo(m)
		if not info then break end
		if info.mapType == CONTINENT then return m end
		m, guard = info.parentMapID, guard + 1
	end
	return map
end

-- a point (map, x, y in percent) on the shown map, 0..1, through the maps' world corners
local function ToShown(map, x, y, shown)
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

local function ClassRGB(key)
	local c = ns.db and ns.db.chars[key]
	local cc = c and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.classFile]
	if cc then return cc.r, cc.g, cc.b end
	return GOLD[1], GOLD[2], GOLD[3]
end

function W.JourneyPane(parent, opts)
	opts = opts or {}
	local f = W.Inset(parent)
	local state = { range = "today", everyone = false, char = nil, focus = nil, playing = false, clock = 0 }

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -8)
	title:SetPoint("RIGHT", f, "RIGHT", -10, 0)
	title:SetJustifyH("LEFT")
	title:SetWordWrap(false)

	-- the map, centred in the space between the title and the controls
	local stage = CreateFrame("Frame", nil, f)
	stage:SetPoint("TOPLEFT", 8, -26)
	stage:SetPoint("BOTTOMRIGHT", -8, 34)
	local map = W.ZoneMap(stage)
	local overlay = CreateFrame("Frame", nil, map)
	overlay:SetAllPoints(map)
	overlay:SetFrameLevel(map:GetFrameLevel() + 20)
	local empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	empty:SetPoint("CENTER", stage, "CENTER")
	empty:SetWidth(360)

	local lines, dots, pts = {}, {}, {}
	local head = overlay:CreateTexture(nil, "OVERLAY", nil, 6)
	head:SetTexture(GLOW)
	head:SetBlendMode("ADD")
	head:SetSize(30, 30)
	head:Hide()
	local ring = overlay:CreateTexture(nil, "OVERLAY", nil, 7)
	ring:SetTexture(CIRCLE)
	ring:SetVertexColor(1, 0.85, 0.35, 1)
	ring:Hide()

	local function Line(i)
		local l = lines[i]
		if not l then l = overlay:CreateLine(nil, "ARTWORK") lines[i] = l end
		return l
	end

	local function Dot(i)
		local d = dots[i]
		if not d then
			d = CreateFrame("Button", nil, overlay)
			d.tex = d:CreateTexture(nil, "OVERLAY")
			d.tex:SetAllPoints()
			d.tex:SetTexture(CIRCLE)
			d:SetScript("OnEnter", function(self)
				local p = self.p
				if not p then return end
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(p.e.s or "?", 1, 0.82, 0)
				GameTooltip:AddLine(ns.CharName(p.c) .. "  |cff999999" .. date("%b %d %H:%M", p.t) .. "|r", 1, 1, 1)
				GameTooltip:AddLine(L["Click: open this entry."], 0.6, 0.8, 1)
				GameTooltip:Show()
			end)
			d:SetScript("OnLeave", GameTooltip_Hide)
			d:SetScript("OnClick", function(self) if self.p and opts.onPick then opts.onPick(self.p.e) end end)
			dots[i] = d
		end
		return d
	end

	local function HideAll()
		for _, l in ipairs(lines) do l:Hide() end
		for _, d in ipairs(dots) do d:Hide() d.p = nil end
		head:Hide()
		ring:Hide()
	end

	-- how much of the line shows: everything up to this time
	local function Reveal(upTo)
		local w, h = map:GetWidth(), map:GetHeight()
		local last
		for _, p in ipairs(pts) do
			local on = p.t <= upTo
			if p.dot then p.dot:SetShown(on) end
			if p.line then p.line:SetShown(on) end
			if on then last = p end
		end
		if last and state.playing then
			head:ClearAllPoints()
			head:SetPoint("CENTER", overlay, "TOPLEFT", last.px * w, -last.py * h)
			head:SetVertexColor(last.r, last.g, last.b)
			head:Show()
		else
			head:Hide()
		end
	end

	local first, last = 0, 0
	f:SetScript("OnUpdate", function(_, elapsed)
		if not state.playing then return end
		state.clock = state.clock + elapsed
		local frac = math.min(1, state.clock / PLAY_TIME)
		head:SetAlpha(0.7 + 0.3 * math.sin(GetTime() * 9))
		Reveal(first + (last - first) * frac)
		if frac >= 1 then
			state.playing = false
			Reveal(last)
			if f.play then f.play:SetText(L["Play"]) end
		end
	end)

	-- the controls: the time frame, play / pause, me or everyone, and a bigger view
	local buttons = {}
	local prev
	for _, r in ipairs(J.RANGES) do
		local b = W.Button(f, r.label, 58, function() state.range = r.key state.focus = nil f:Refresh(true) end)
		b:SetPoint("BOTTOMLEFT", prev or f, prev and "BOTTOMRIGHT" or "BOTTOMLEFT", prev and 2 or 8, prev and 0 or 7)
		b.key = r.key
		buttons[#buttons + 1] = b
		prev = b
	end
	f.play = W.Button(f, L["Play"], 64, function()
		if state.playing then
			state.playing = false
			f.play:SetText(L["Play"])
			Reveal(last)
		else
			state.clock = 0
			state.playing = #pts > 0
			f.play:SetText(L["Pause"])
		end
	end)
	f.play:SetPoint("LEFT", prev, "RIGHT", 10, 0)
	f.who = W.Button(f, L["Everyone"], 84, function() state.everyone = not state.everyone f:Refresh(true) end)
	f.who:SetPoint("LEFT", f.play, "RIGHT", 4, 0)
	f.big = W.Button(f, L["Larger"], 70, function() if opts.onLarger then opts.onLarger() end end)
	f.big:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 7)

	function f:IsPlaying() return state.playing end
	function f:SetLarge(on) f.big:SetText(on and L["Smaller"] or L["Larger"]) end

	-- whose journey: a character from the header, else you (or everyone)
	function f:SetCharacter(key) state.char = key state.focus = nil end

	function f:Focus(entry)
		state.focus = entry and entry.m and entry.x and entry or nil
		self:Refresh(false)
	end

	function f:Refresh(replay)
		if not ns.db then return end
		HideAll()
		wipe(pts)
		local scope = ns.ScopeChar()
		local who = scope or state.char or ((not state.everyone) and ns.CharKey()) or nil
		f.who:SetShown(not (scope or state.char))
		f.who:SetText(state.everyone and L["Only me"] or L["Everyone"])
		for _, b in ipairs(buttons) do
			if b.key == state.range then b:LockHighlight() else b:UnlockHighlight() end
		end
		local all = J.Points(J.From(state.range), who)
		-- the map: the focused entry's zone; else the newest point's zone, or its continent when the
		-- line leaves that zone
		local shown
		if state.focus then shown = state.focus.m
		elseif #all > 0 then
			shown = all[#all].m
			for _, p in ipairs(all) do if p.m ~= shown then shown = Continent(shown) break end end
		end
		local rangeLabel
		for _, r in ipairs(J.RANGES) do if r.key == state.range then rangeLabel = r.label end end
		local whoText = who and ns.CharName(who) or L["Everyone"]
		if not shown then
			map:Hide()
			empty:SetText(L["No journey here yet: each discovery you make marks where you were, and the line joins them."])
			empty:Show()
			title:SetText(L["Journey"] .. "  |cff999999" .. whoText .. "  ·  " .. rangeLabel .. "|r")
			f.play:Disable()
			return
		end
		empty:Hide()
		-- fit the map into the stage, keeping its shape
		local sw, sh = stage:GetWidth(), stage:GetHeight()
		if not (sw and sw > 10 and sh and sh > 10) then sw, sh = 540, 300 end
		local h = map:Draw(shown, sw)
		if h == 0 then
			map:Hide()
			empty:SetText(L["This map can't be drawn here."])
			empty:Show()
			f.play:Disable()
			return
		end
		if h > sh then h = map:Draw(shown, sw * sh / h) end
		map:ClearAllPoints()
		map:SetPoint("CENTER", stage, "CENTER")
		map:SetPins({})
		local w = map:GetWidth()
		local mapName = MapInfo(shown) and MapInfo(shown).name or "?"
		title:SetText(L["Journey"] .. "  |cff999999" .. whoText .. "  ·  " .. rangeLabel .. "  ·  " .. mapName .. "|r")

		-- the points that fall on this map, each with its dot and the line from the one before it
		local prevBy = {}
		local nl, nd = 0, 0
		first, last = nil, 0
		local thick = math.max(2, w / 260)
		local dotSize = math.max(6, w / 90)
		local focusDot
		for _, p in ipairs(all) do
			local px, py = ToShown(p.m, p.x, p.y, shown)
			if px then
				p.px, p.py = px, py
				if who then p.r, p.g, p.b = GOLD[1], GOLD[2], GOLD[3] else p.r, p.g, p.b = ClassRGB(p.c) end
				nd = nd + 1
				local d = Dot(nd)
				d.p = p
				d:SetSize(dotSize, dotSize)
				d:ClearAllPoints()
				d:SetPoint("CENTER", overlay, "TOPLEFT", px * w, -py * h)
				d.tex:SetVertexColor(p.r * 0.85, p.g * 0.85, p.b * 0.85, 1)
				p.dot = d
				if state.focus and p.e == state.focus then focusDot = d end
				local q = prevBy[p.c]
				if q and p.t - q.t <= GAP and ((px - q.px) ^ 2 + (py - q.py) ^ 2) <= JUMP * JUMP then
					nl = nl + 1
					local l = Line(nl)
					l:SetThickness(thick)
					l:SetColorTexture(p.r, p.g, p.b, 0.9)
					l:SetStartPoint("TOPLEFT", overlay, q.px * w, -q.py * h)
					l:SetEndPoint("TOPLEFT", overlay, px * w, -py * h)
					p.line = l
				end
				prevBy[p.c] = p
				pts[#pts + 1] = p
				first = first or p.t
				last = p.t
			end
		end
		first = first or 0
		if focusDot then
			ring:ClearAllPoints()
			ring:SetPoint("CENTER", focusDot, "CENTER")
			ring:SetSize(dotSize * 2.6, dotSize * 2.6)
			ring:SetAlpha(0.8)
			ring:Show()
			focusDot:SetFrameLevel(overlay:GetFrameLevel() + 5)
		end
		f.play:SetEnabled(#pts > 0)
		if replay and #pts > 1 and not state.focus then
			state.clock, state.playing = 0, true
			f.play:SetText(L["Pause"])
			Reveal(first)
		else
			state.playing = false
			f.play:SetText(L["Play"])
			Reveal(last)
		end
	end

	-- redraw at the new size once the pane has been laid out (and when it grows or shrinks)
	f:SetScript("OnSizeChanged", function() if f:IsVisible() then C_Timer.After(0, function() f:Refresh(false) end) end end)
	-- the time lapse plays each time the Journal opens
	f:SetScript("OnShow", function() C_Timer.After(0, function() if f:IsVisible() then f:Refresh(true) end end) end)
	return f
end
