-- The Journey (0.69.0, #35; DESIGN section 74), shown small in the Journal's top right pane: where a
-- character went in a time frame, on the game's own map art, drawn as a time lapse (a gold line
-- through the places in the order you reached them, its head glowing) that then stays drawn.
--   local j = ns.Widgets.JourneyPane(parent, { onPick = function(entry) end })
--   j:SetCharacter(key)     -- a character's journey (nil: the header's "All characters")
--   j:Focus(entry)          -- turn to the entry's zone and light its marker (nil: back to the whole frame)
--   j:Refresh(replay)       -- redraw (replay: play the time lapse again)
-- Points: the Journey recorder's trail (Modules/JourneyRecorder.lua, 0.69.1) with the journal's own
-- points among it (every discovery has a time, map, x and y: those are the dots you can click). Before
-- the recorder has anything the line runs through the journal's points alone.
-- How you moved shows on the line: a gryphon where a flight took off and landed, a hearthstone where
-- you arrived by hearth, the portal swirl where you went into or out of a dungeon (and at both ends of
-- any jump nothing explains), a skull where you died; boat rides and ghost runs drawn fainter.
-- Character mode: one line in gold. Account mode (everyone): each character in its class colour,
-- all on one clock. A gap of more than 2 hours, or a jump across the map, breaks the line.
-- (#46-#49) Both sizes: a slider to scrub the time lapse and 1x / 2x / 4x. opts.full: the Characters
-- page's Journey tab, full size: a longer time lapse, sounds, Everyone for the selected character's account. Everyone mode (either size):
-- a legend of names in class colours, click one to hide or show their line (kept in
-- settings.window.journeyHidden). Flights draw dotted, boats and zeppelins dashed, ghost runs pale
-- blue. Each character's line has a head: the live face of the one you're playing, the round class
-- icon for the others, in a ring (class colour in Everyone mode), with a short comet trail and,
-- while playing or scrubbing, the time and zone beside it. Pins and faces are round (masked).

local _, ns = ...
local L = ns.L
local W = ns.Widgets

local J = {}
ns.Journey = J

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local GLOW = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"
local GAP = 2 * 3600
local JUMP = 0.35
-- (2026-10-09, Shannon: 1x 90% slower than first built, so a busy week can be followed; 8x added to skim)
local PLAY_TIME = 80         -- seconds for the whole time lapse at 1x in the small pane
local FULL_TIME = { today = 200, week = 300, month = 300, all = 300 } -- (#47) the full-size tab
local SPEEDS = { 1, 2, 4, 8 }
local ZOOM_MAX = 3.5         -- (zoom to the journey: at most this much past the whole map)
local MEDIA = "Interface\\AddOns\\AzerothAlmanac\\Media\\"
local GHOST = { 0.6, 0.85, 1 }
local MAX_POINTS = 800       -- the newest points in the frame (the oldest are left off)
local GOLD = { 1, 0.82, 0.3 }
-- the marks on the line (Modules/JourneyRecorder.lua's kinds)
local PIN_ART = {
	F = { kindArt = "flight", scale = 1.4 },
	f = { kindArt = "flight", scale = 1.4 },
	h = { icon = { "INV_Misc_Rune_01", 134414 }, round = true },
	d = { icon = { "INV_Misc_Bone_HumanSkull_01", "Ability_Rogue_FeignDeath" }, round = true },
	-- (#49) boats and zeppelins: a pin at the dock you left from and the one you came to
	b = { icon = { "INV_Misc_Anchor", "INV_Misc_Spyglass_02" }, round = true },
	z = { icon = { "INV_Misc_Zeppelin", "INV_Gizmo_01", "INV_Misc_Spyglass_02" }, round = true },
	res = { icon = { MEDIA .. "Mark_Ankh" }, round = true },
	i = { icon = { "Interface\\AddOns\\AzerothAlmanac\\Media\\FX_DungeonPortal" }, add = true, scale = 1.8 },
	jump = { icon = { "Interface\\AddOns\\AzerothAlmanac\\Media\\FX_DungeonPortal" }, add = true, scale = 1.5 },
}

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

-- the points from a time on, oldest first: { t, m, x, y, c, e, k } (e: the journal entry; k: how you
-- got there, from the recorder); char nil: every character
function J.Points(from, char)
	local out = J.JournalPoints(from, char)
	local JR = ns.JourneyRecorder
	local trail = JR and JR.Points and JR:Points(from, char) or {}
	if #trail == 0 then return out end
	for _, p in ipairs(trail) do out[#out + 1] = p end
	for i, p in ipairs(out) do p.s = p.s or i end
	table.sort(out, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.s < b.s end)
	-- the newest MAX_POINTS * 4 (a long trail is thinned for drawing, keeping marks and discoveries)
	local cap = MAX_POINTS * 4
	if #out > cap then
		local keep, step = {}, math.ceil(#out / cap)
		for i, p in ipairs(out) do if p.e or p.k or i % step == 0 or i == #out then keep[#keep + 1] = p end end
		out = keep
	end
	return out
end

function J.JournalPoints(from, char)
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

-- (2026-10-09) a point in world yards (west, north), through the maps' world corners; nil when unknown
local function Yards(map, x, y)
	local Rect = ns.Townsfolk and ns.Townsfolk.MapRect
	local r = Rect and Rect(map)
	if not r then return nil end
	return r.left - (x / 100) * (r.left - r.right), r.top - (y / 100) * (r.top - r.bottom), r.inst
end

-- too far, too fast to have been walked or ridden: a jump (a teleport, a summon, a hearth the
-- recorder didn't catch). The recorder writes a point at least every few seconds while you move, so
-- anything over FAST yards a second across more than JUMP_YARDS is not a road.
local FAST, JUMP_YARDS = 30, 150
local function Jumped(q, p)
	local x1, y1, i1 = Yards(q.m, q.x, q.y)
	local x2, y2, i2 = Yards(p.m, p.x, p.y)
	if not (x1 and x2) or i1 ~= i2 then return nil end
	local d = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
	return d > JUMP_YARDS and d / math.max(1, p.t - q.t) > FAST
end

local function ClassRGB(key)
	local c = ns.db and ns.db.chars[key]
	local cc = c and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.classFile]
	if cc then return cc.r, cc.g, cc.b end
	return GOLD[1], GOLD[2], GOLD[3]
end

-- (#49) the class icon from the game's round class sheet, else the Almanac's crest
local function ClassIcon(tex, classFile)
	local c = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
	if c then
		tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
		tex:SetTexCoord(c[1], c[2], c[3], c[4])
	elseif classFile then
		tex:SetTexture(MEDIA .. "Crest_" .. classFile)
		tex:SetTexCoord(0, 1, 0, 1)
	else
		tex:SetTexture(ns.ICON)
		tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
end

-- a circle mask on a texture (smooth round edges, no square corners)
local function Round(owner, tex)
	if not (owner.CreateMaskTexture and tex.AddMaskTexture) then return end
	if tex.roundMask then return end
	local m = owner:CreateMaskTexture()
	m:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	m:SetAllPoints(tex)
	tex:AddMaskTexture(m)
	tex.roundMask = m
end

---------------------------------------------------------------------------
-- (#49, DESIGN 74 "Effects, sounds and icons") what each moment of the time lapse does
---------------------------------------------------------------------------

-- the sounds: each a list of candidates, the first the client has wins (a SOUNDKIT name or a sound
-- file ID). The travel ones are placeholders until picked by ear: /aa journey sounds plays them all,
-- /aa journey sound <name> <file ID or SOUNDKIT name> sets one (kept in settings.window.journeySoundPick).
J.SOUNDS = {
	play = { "IG_ABILITY_PAGE_TURN" },
	flight = { "MAP_PING" },            -- gryphon wing flaps (to pick)
	land = { "IG_MAINMENU_OPTION_CHECKBOX_ON" }, -- soft landing thump (to pick)
	boat = { "MAP_PING" },              -- ship's bell, waves (to pick)
	zeppelin = { "MAP_PING" },          -- engine hum (to pick)
	hearth = { 567400 },                -- hearthstone cast (to pick; iQuestActivate for now)
	portal = { 569767 },                -- portal whoosh (to pick; a nature cast for now)
	death = { 567459 },                 -- low drum (to pick; quest failed for now)
	ghost = { "MAP_PING" },             -- spirit wind (to pick)
	res = { 567439 },                   -- resurrection chime (to pick; quest complete for now)
	arcane = { 569767 },                -- arcane teleport (to pick)
	zone = { "UI_LOOT_TOAST_LESSER_ITEM_WON", "IG_QUEST_LOG_OPEN", "MAP_PING" }, -- discovery chime
	tier2 = { "UI_LOOT_TOAST_LESSER_ITEM_WON", "IG_QUEST_LOG_OPEN", "MAP_PING" },
	tier3 = { "IG_QUEST_LIST_COMPLETE", "UI_EPICLOOT_TOAST" },
	tier4 = { "UI_EPICLOOT_TOAST", 567439 },
	tier5 = { "UI_LEGENDARY_LOOT_TOAST", "UI_EPICLOOT_TOAST", 567439 },
	scrub = { "U_CHAT_SCROLL_BUTTON" },
	speed = { "U_CHAT_SCROLL_BUTTON" },
	legend = { "IG_MAINMENU_OPTION_CHECKBOX_ON" },
	finish = { 567439 },                -- closing chord (quest complete for now)
}
J.SOUND_ORDER = { "play", "flight", "land", "boat", "zeppelin", "hearth", "portal", "death", "ghost", "res", "arcane", "zone", "tier2", "tier3", "tier4", "tier5", "finish" }

local function Win() return ns.db and ns.db.settings and ns.db.settings.window or {} end

-- the candidate that plays, or nil
local function SoundOf(name)
	local pick = Win().journeySoundPick and Win().journeySoundPick[name]
	local list = pick and { pick } or J.SOUNDS[name] or {}
	for _, c in ipairs(list) do
		if type(c) == "number" then return c, "file" end
		local kit = SOUNDKIT and SOUNDKIT[c]
		if kit then return kit, "kit", c end
		if tonumber(c) then return tonumber(c), "file" end
	end
end

function J.PlayNamed(name)
	local id, how = SoundOf(name)
	if not id then return false end
	if how == "file" then return PlaySoundFile and PlaySoundFile(id, "SFX") ~= false
	else return PlaySound(id, "SFX") ~= false end
end

-- (rules) one sound every 0.4 s at most; the bigger tier wins a tie; at 4x only Rare and up
local lastSound, lastTier = 0, 0
function J.Sound(name, tier, speed)
	if Win().journeySounds == false then return end
	if ns.db and ns.db.settings.toasts and ns.db.settings.toasts.sound == false then return end
	tier = tier or 1
	if (speed or 1) >= 4 and tier < 3 then return end
	local now = GetTime()
	if now - lastSound < 0.4 and tier <= lastTier then return end
	lastSound, lastTier = now, tier
	J.PlayNamed(name)
end

-- /aa journey sounds | /aa journey sound <name> <file ID or SOUNDKIT name | default>
function J.Command(rest)
	local a, b, c = strsplit(" ", rest or "", 3)
	a = (a or ""):lower()
	if a == "sounds" then
		ns.Print(L["Journey sounds, one after another (name: what plays):"])
		for i, name in ipairs(J.SOUND_ORDER) do
			C_Timer.After((i - 1) * 1.6, function()
				local id, how, kit = SoundOf(name)
				ns.Print(("  |cffffd100%s|r: %s"):format(name, id and (how == "kit" and kit or ("file " .. id)) or "|cffff6060none found|r"))
				J.PlayNamed(name)
			end)
		end
	elseif a == "sound" and b and J.SOUNDS[b] then
		local w = Win()
		w.journeySoundPick = w.journeySoundPick or {}
		if not c or c == "" or c == "default" then w.journeySoundPick[b] = nil
		else w.journeySoundPick[b] = tonumber(c) or c end
		ns.Print(("Journey sound |cffffd100%s|r: %s"):format(b, tostring(w.journeySoundPick[b] or "default")))
		J.PlayNamed(b)
	else
		ns.Print(L["/aa journey sounds  -  play every Journey sound; /aa journey sound <name> <file ID> (or default)  -  pick one."])
	end
end

-- a discovery's toast tier (1 Common .. 5 Legendary), as the alerts use them
local function TierOf(e)
	local k = e and e.k
	if k == "instance" or k == "zone" then return 3 end
	if k == "level" then
		local lv = tonumber(e.i) or 0
		return lv >= 60 and 5 or (lv % 10 == 0 and 3) or 2
	end
	if k == "milestone" then return 4 end
	if k == "item" then
		local rec = ns.Store and ns.Store:Get("item", e.i)
		local q = rec and rec.q or 1
		return q >= 5 and 5 or q >= 4 and 4 or q >= 3 and 3 or 2
	end
	if k == "quest" or k == "flight" or k == "subzone" then return 2 end
	return 1
end
J.TierOf = TierOf
local TIER_RGB = { { 1, 1, 1 }, { 0.12, 1, 0 }, { 0, 0.44, 0.87 }, { 0.64, 0.21, 0.93 }, { 1, 0.5, 0 } }

local function Saved()
	local s = ns.db and ns.db.settings and ns.db.settings.window
	if not s then return {} end
	s.journeyHidden = s.journeyHidden or {}
	return s.journeyHidden
end

function W.JourneyPane(parent, opts)
	opts = opts or {}
	local full = opts.full and true or false
	local f = W.Inset(parent)
	local state = { range = "today", everyone = false, char = nil, focus = nil, playing = false, clock = 0, speed = 1 }

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -8)
	title:SetPoint("RIGHT", f, "RIGHT", -10, 0)
	title:SetJustifyH("LEFT")
	title:SetWordWrap(false)

	-- the map, centred in the space between the title and the controls (full: a slider row too)
	local BOTTOM = 62 -- (the slider row and the buttons, both sizes)
	local stage = CreateFrame("Frame", nil, f)
	stage:SetPoint("TOPLEFT", 8, -26)
	stage:SetPoint("BOTTOMRIGHT", -8, BOTTOM)
	if stage.SetClipsChildren then stage:SetClipsChildren(true) end -- (the zoomed map stays inside)
	local map = W.ZoneMap(stage)
	local unitW = 540 -- (the stage's width: what pins, dots and lines are sized by, whatever the zoom)
	f.mapX, f.mapY = 0, 0
	local overlay = CreateFrame("Frame", nil, map)
	overlay:SetAllPoints(map)
	overlay:SetFrameLevel(map:GetFrameLevel() + 20)
	local empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	empty:SetPoint("CENTER", stage, "CENTER")
	empty:SetWidth(360)

	local lines, dots, pts, pins, beads = {}, {}, {}, {}, {}
	local heads = {}
	local nl, nb = 0, 0
	local ring = overlay:CreateTexture(nil, "OVERLAY", nil, 7)
	ring:SetTexture(CIRCLE)
	ring:SetVertexColor(1, 0.85, 0.35, 1)
	ring:Hide()

	local function Line()
		nl = nl + 1
		local l = lines[nl]
		if not l then l = overlay:CreateLine(nil, "ARTWORK") lines[nl] = l end
		return l
	end

	-- (#49) the round beads of a dotted flight line
	local function Bead()
		nb = nb + 1
		local t = beads[nb]
		if not t then t = overlay:CreateTexture(nil, "ARTWORK", nil, 2) t:SetTexture(CIRCLE) beads[nb] = t end
		return t
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
				if self.base then self:SetSize(self.base * 2.2, self.base * 2.2) end -- (a speck grows under the mouse)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(p.e.s or "?", 1, 0.82, 0)
				GameTooltip:AddLine(ns.CharName(p.c) .. "  |cff999999" .. date("%b %d %H:%M", p.t) .. "|r", 1, 1, 1)
				GameTooltip:AddLine(L["Click: open this entry."], 0.6, 0.8, 1)
				GameTooltip:Show()
			end)
			d:SetScript("OnLeave", function(self) if self.base then self:SetSize(self.base, self.base) end GameTooltip_Hide() end)
			d:SetScript("OnClick", function(self) if self.p and opts.onPick then opts.onPick(self.p.e) end end)
			dots[i] = d
		end
		return d
	end

	-- (#49) a character's head: glow, face (or class icon) in a ring, a comet trail, the time and zone
	local function Head(key)
		local h = heads[key]
		if h then return h end
		h = CreateFrame("Frame", nil, overlay)
		h:SetFrameLevel(overlay:GetFrameLevel() + 8)
		h:SetSize(26, 26)
		h.glow = h:CreateTexture(nil, "BACKGROUND")
		h.glow:SetTexture(GLOW)
		h.glow:SetBlendMode("ADD")
		h.glow:SetPoint("CENTER")
		h.face = h:CreateTexture(nil, "ARTWORK")
		h.face:SetPoint("CENTER")
		Round(h, h.face)
		h.ring = h:CreateTexture(nil, "OVERLAY")
		h.ring:SetTexture(MEDIA .. "Ring_Class")
		h.ring:SetPoint("CENTER")
		h.label = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		h.label:SetPoint("LEFT", h, "RIGHT", 4, 0)
		h.label:SetShadowOffset(1, -1)
		h.trail = {}
		for i = 1, 6 do
			local t = overlay:CreateTexture(nil, "OVERLAY", nil, 3)
			t:SetTexture(GLOW)
			t:SetBlendMode("ADD")
			t:Hide()
			h.trail[i] = t
		end
		heads[key] = h
		return h
	end

	local function PaintHead(h, key, r, g, b, size)
		h:SetSize(size, size)
		h.glow:SetSize(size * 1.9, size * 1.9)
		h.glow:SetVertexColor(r, g, b)
		h.face:SetSize(size * 0.78, size * 0.78)
		h.ring:SetSize(size * 0.78 / 0.766, size * 0.78 / 0.766)
		h.ring:SetVertexColor(r * 0.6 + 0.4, g * 0.6 + 0.4, b * 0.6 + 0.4)
		-- (the face is set when the head changes hands, and refreshed once a second at most)
		if h.key ~= key or not h.facedAt or GetTime() - h.facedAt > 1 then
			h.key, h.facedAt = key, GetTime()
			-- the character you're playing: their live face; anyone else (or no face): the class icon
			local c = ns.db and ns.db.chars and ns.db.chars[key]
			local live = key == ns.CharKey() and SetPortraitTexture
			if live then
				h.face:SetTexCoord(0, 1, 0, 1)
				local ok = pcall(SetPortraitTexture, h.face, "player")
				if not ok then ClassIcon(h.face, c and c.classFile) end
			else
				ClassIcon(h.face, c and c.classFile)
			end
		end
		for i, t in ipairs(h.trail) do
			local s = size * (0.55 - i * 0.06)
			t:SetSize(s, s)
			t:SetVertexColor(r, g, b, 0.55 - i * 0.08)
		end
	end

	local function HideHeads()
		for _, h in pairs(heads) do
			h:Hide()
			for _, t in ipairs(h.trail) do t:Hide() end
		end
	end

	local function HideAll()
		for _, t in ipairs(pins) do t:Hide() end
		for _, l in ipairs(lines) do l:Hide() end
		for _, t in ipairs(beads) do t:Hide() end
		for _, d in ipairs(dots) do d:Hide() d.p = nil end
		HideHeads()
		ring:Hide()
	end

	local function ZoneName(m)
		local info = MapInfo(m)
		return info and info.name or ""
	end

	-- (#49) effects: short-lived textures that grow, rise and fade (driven by the pane's OnUpdate)
	local fxPool, fxLive = {}, {}
	local function FxOn() return Win().journeyEffects ~= false end
	local function FxLight() return Win().journeyEffectsLight == true end
	local function Fx(px, py, spec)
		if not FxOn() then return end
		local t = table.remove(fxPool) or overlay:CreateTexture(nil, "OVERLAY", nil, 6)
		local w, h = map:GetWidth(), map:GetHeight()
		t:SetTexture(spec.tex or GLOW)
		t:SetTexCoord(0, 1, 0, 1)
		t:SetBlendMode(spec.add == false and "BLEND" or "ADD")
		t:SetVertexColor(spec.r or 1, spec.g or 1, spec.b or 1)
		t:ClearAllPoints()
		t:SetPoint("CENTER", overlay, "TOPLEFT", px * w, -py * h)
		local base = spec.size or math.max(16, unitW / 22)
		t:SetSize(base, (spec.tall or 1) * base)
		t:SetAlpha(spec.a or 1)
		t:Show()
		fxLive[#fxLive + 1] = { t = t, t0 = GetTime() + (spec.delay or 0), dur = spec.dur or 0.8, s0 = spec.s0 or 0.4, s1 = spec.s1 or 1.6,
			a = spec.a or 1, rise = spec.rise or 0, base = base, tall = spec.tall or 1, px = px * w, py = -py * h, delay = spec.delay }
		if spec.delay then t:SetAlpha(0) end
	end
	local function StepFx()
		local now = GetTime()
		for i = #fxLive, 1, -1 do
			local e = fxLive[i]
			local k = (now - e.t0) / e.dur
			if k >= 1 then
				e.t:Hide()
				fxPool[#fxPool + 1] = e.t
				table.remove(fxLive, i)
			elseif k >= 0 then
				local sc = e.s0 + (e.s1 - e.s0) * k
				e.t:SetSize(e.base * sc, e.base * sc * e.tall)
				e.t:SetAlpha(e.a * (1 - k))
				if e.rise ~= 0 then
					e.t:ClearAllPoints()
					e.t:SetPoint("CENTER", overlay, "TOPLEFT", e.px, e.py + e.rise * k)
				end
			end
		end
		-- the map's shake (a death)
		if f.shakeUntil then
			if now < f.shakeUntil then
				map:ClearAllPoints()
				map:SetPoint("TOPLEFT", stage, "TOPLEFT", f.mapX + math.random(-3, 3), f.mapY + math.random(-2, 2))
			else
				f.shakeUntil = nil
				map:ClearAllPoints()
				map:SetPoint("TOPLEFT", stage, "TOPLEFT", f.mapX, f.mapY)
			end
		end
		-- the zone's name over the map, like the game's zone text
		if f.banner and f.bannerAt then
			local k = (now - f.bannerAt) / 2.4
			if k >= 1 then f.banner:Hide() f.bannerAt = nil
			else f.banner:SetAlpha(k < 0.2 and k / 0.2 or (k > 0.7 and (1 - k) / 0.3) or 1) end
		end
	end
	local function ClearFx()
		for _, e in ipairs(fxLive) do e.t:Hide() fxPool[#fxPool + 1] = e.t end
		wipe(fxLive)
		if f.banner then f.banner:Hide() f.bannerAt = nil end
		if f.shakeUntil then f.shakeUntil = nil map:ClearAllPoints() map:SetPoint("TOPLEFT", stage, "TOPLEFT", f.mapX, f.mapY) end
	end
	f.banner = f:CreateFontString(nil, "OVERLAY")
	f.banner:SetFont("Fonts\\MORPHEUS.TTF", full and 30 or 18, "OUTLINE")
	f.banner:SetTextColor(1, 0.82, 0.3)
	f.banner:SetShadowOffset(2, -2)
	f.banner:SetPoint("TOP", stage, "TOP", 0, -18)
	f.banner:Hide()
	local function Banner(text)
		if not FxOn() or not text or text == "" then return end
		f.banner:SetText(text)
		f.banner:SetAlpha(0)
		f.banner:Show()
		f.bannerAt = GetTime()
	end

	local RING = MEDIA .. "Ring_Hollow"
	-- sounds: only on the full-size Journey tab (the Journal's small pane replays on every open, so it
	-- plays its effects silently)
	local function Snd(name, tier) if full then J.Sound(name, tier, state.speed) end end
	-- what reaching a point does (sounds through J.Sound: the throttle and tier rules)
	local function Fire(p, prevSame)
		local light = FxLight()
		local k = p.k
		local q = prevSame
		local speed = state.speed
		local x, y = p.px, p.py
		if k == "F" then
			Fx(x, y, { r = 1, g = 0.9, b = 0.6, dur = 0.7, s1 = 2.2, rise = 10 })
			Snd("flight", 2)
		elseif k == "f" then
			Fx(x, y, { tex = MEDIA .. "FX_Dust", add = false, dur = 0.8, s0 = 0.5, s1 = 1.8, a = 0.9 })
			Snd("land", 2)
		elseif (k == "b" or k == "z") and not (q and q.k == k) then
			if k == "b" then Fx(x, y, { tex = MEDIA .. "FX_Bubbles", dur = 1.2, s0 = 0.6, s1 = 1.6, rise = 14 }) end
			Snd(k == "b" and "boat" or "zeppelin", 2)
		elseif k == "h" then
			if q then Fx(q.px, q.py, { r = 0.4, g = 0.7, b = 1, dur = 0.6, s1 = 2 }) end
			Fx(x, y, { r = 0.6, g = 0.85, b = 1, dur = 1.1, s0 = 0.6, s1 = 1, tall = 3.2, rise = 18 })
			if not light then Fx(x, y, { r = 1, g = 1, b = 0.8, dur = 0.9, s1 = 1.8, delay = 0.2 }) end
			Snd("hearth", 3)
		elseif k == "i" then
			Fx(x, y, { tex = MEDIA .. "FX_DungeonPortal", dur = 1.1, s0 = 0.3, s1 = 1.6, a = 0.95 })
			Snd("portal", 3)
		elseif k == "d" then
			Fx(x, y, { tex = RING, r = 1, g = 0.15, b = 0.1, dur = 0.8, s0 = 0.4, s1 = 2.6 })
			if not light then f.shakeUntil = GetTime() + 0.35 end
			Snd("death", 3)
		elseif k == "g" and not (q and q.k == "g") then
			Fx(x, y, { r = GHOST[1], g = GHOST[2], b = GHOST[3], dur = 1, s1 = 1.8, rise = 12 })
			Snd("ghost", 2)
		elseif k ~= "g" and q and q.k == "g" then
			Fx(x, y, { tex = MEDIA .. "FX_Reincarnation", dur = 1, s0 = 0.5, s1 = 1.8 })
			Snd("res", 3)
		end
		if p.pinFrom and not p.k then
			-- a jump nothing explains: purple flash at both ends
			Fx(q and q.px or x, q and q.py or y, { r = 0.7, g = 0.4, b = 1, dur = 0.6, s1 = 2 })
			Fx(x, y, { r = 0.7, g = 0.4, b = 1, dur = 0.8, s1 = 2.2, delay = 0.1 })
			Snd("arcane", 3)
		end
		-- a discovery passed: by its toast tier
		if p.e then
			local tier = TierOf(p.e)
			local c = TIER_RGB[tier]
			if tier == 1 then
				if not light then Fx(x, y, { tex = RING, r = c[1], g = c[2], b = c[3], dur = 0.5, s0 = 0.3, s1 = 1, a = 0.7 }) end
			else
				if not light or tier >= 3 then Fx(x, y, { tex = RING, r = c[1], g = c[2], b = c[3], dur = 0.7, s0 = 0.4, s1 = 1.6 + tier * 0.3 }) end
				if tier >= 2 and not light then
					local icon = W.KindArt(p.e.k)
					if type(icon) == "string" then Fx(x, y, { tex = icon, add = false, dur = 1.1, s0 = 0.8, s1 = 1, rise = 20 }) end
				end
				if tier >= 4 then Fx(x, y, { r = c[1], g = c[2], b = c[3], dur = 1.2, s0 = 1, s1 = 4, a = 0.6 }) end
				if tier >= 5 then Fx(x, y, { r = 1, g = 0.85, b = 0.4, dur = 1.6, s0 = 0.6, s1 = 1, tall = 5, rise = 30 }) end
				if p.e.k == "zone" then Banner(p.e.s) Snd("zone", 3)
				else Snd("tier" .. tier, tier) end
			end
		end
	end

	-- how much of the line shows: everything up to this time. While playing or scrubbing, each
	-- character's head sits on their latest point, with a short trail behind it.
	local first, last = 0, 0
	local function Reveal(upTo)
		local w, h = map:GetWidth(), map:GetHeight()
		local lastBy, prevBy = {}, {}
		local firing = state.playing and not state.scrubbing
		local active = state.playing or state.scrubbing
		for _, p in ipairs(pts) do
			local on = p.t <= upTo
			if on and not p.fired then
				p.fired = true
				if firing then Fire(p, lastBy[p.c]) end
			end
			if p.dot then p.dot:SetShown(on) end
			for _, o in ipairs(p.segs) do o:SetShown(on) end
			-- (the swirls of unexplained jumps only while playing or scrubbing: at rest they're clutter)
			if p.pin then p.pin:SetShown(on and (active or not p.pin.isJump)) end
			if p.pinFrom then p.pinFrom:SetShown(on and (active or not p.pinFrom.isJump)) end
			if on then
				prevBy[p.c] = prevBy[p.c] or {}
				local trail = prevBy[p.c]
				table.insert(trail, 1, p)
				if #trail > 7 then trail[8] = nil end
				lastBy[p.c] = p
			end
		end
		HideHeads()
		local size = full and math.max(26, unitW / 30) or math.max(18, unitW / 26)
		if not active then
			-- at rest: a small head on each character's last spot, nothing else
			for key, p in pairs(lastBy) do
				local hd = Head(key)
				PaintHead(hd, key, p.r, p.g, p.b, size * 0.7)
				hd:ClearAllPoints()
				hd:SetPoint("CENTER", overlay, "TOPLEFT", p.px * w, -p.py * h)
				hd:SetAlpha(1)
				hd.face:SetDesaturated(false)
				hd.glow:SetAlpha(0.5)
				hd.label:SetText("")
				hd:Show()
			end
			return
		end
		for key, p in pairs(lastBy) do
			local hd = Head(key)
			PaintHead(hd, key, p.r, p.g, p.b, size)
			hd:ClearAllPoints()
			hd:SetPoint("CENTER", overlay, "TOPLEFT", p.px * w, -p.py * h)
			hd:SetAlpha(p.k == "g" and 0.55 or 1)
			hd.face:SetDesaturated(p.k == "d" or p.k == "g")
			if p.k == "b" or p.k == "z" then
				-- (on a boat: a gentle bob; a zeppelin sways)
				local bob = math.sin(GetTime() * (p.k == "b" and 5 or 2.5)) * (p.k == "b" and 2 or 3)
				hd:ClearAllPoints()
				hd:SetPoint("CENTER", overlay, "TOPLEFT", p.px * w + (p.k == "z" and bob or 0), -p.py * h + (p.k == "b" and bob or 0))
			elseif p.k == "F" then
				hd:SetSize(size * 1.25, size * 1.25) -- (taking off: lifted)
			end
			hd.label:SetText(date("%b %d %H:%M", p.t) .. "  ·  " .. ZoneName(p.m))
			hd:Show()
			local trail = prevBy[key]
			for i = 1, 6 do
				local q, t = trail[i + 1], hd.trail[i]
				if q then
					t:ClearAllPoints()
					t:SetPoint("CENTER", overlay, "TOPLEFT", q.px * w, -q.py * h)
					t:Show()
				end
			end
		end
	end

	local slider
	local function PlayTime()
		if full then return FULL_TIME[state.range] or 30 end
		return PLAY_TIME
	end
	local function SetSlider(frac)
		if not slider then return end
		slider.quiet = true
		slider:SetValue(frac * 1000)
		slider.quiet = nil
	end

	local function Finish()
		-- (#49) the end: three gold ripples on each head, a closing chord and the summary
		local w, h = map:GetWidth(), map:GetHeight()
		local zones, flights, deaths, finds = {}, 0, 0, 0
		local lastBy = {}
		for _, p in ipairs(pts) do
			zones[p.m] = true
			if p.k == "F" then flights = flights + 1 end
			if p.k == "d" then deaths = deaths + 1 end
			if p.e then finds = finds + 1 end
			lastBy[p.c] = p
		end
		for _, p in pairs(lastBy) do
			for i = 0, 2 do Fx(p.px, p.py, { tex = RING, r = 1, g = 0.82, b = 0.3, dur = 0.9, s0 = 0.4, s1 = 2.2, delay = i * 0.3 }) end
		end
		local nz = 0
		for _ in pairs(zones) do nz = nz + 1 end
		if full and f.summary then
			f.summary:SetText(ns.N(nz, "zone", "zones") .. "  ·  " .. ns.N(flights, "flight", "flights") .. "  ·  " .. ns.N(deaths, "death", "deaths") .. "  ·  " .. ns.N(finds, "discovery", "discoveries"))
			f.summary:Show()
		end
		if full then J.Sound("finish", 3, 1) end
	end

	f:SetScript("OnUpdate", function(_, elapsed)
		StepFx()
		if not state.playing then return end
		state.clock = state.clock + elapsed * state.speed
		local frac = math.min(1, state.clock / PlayTime())
		local pulse = 0.7 + 0.3 * math.sin(GetTime() * 9)
		for _, hd in pairs(heads) do hd.glow:SetAlpha(pulse) end
		Reveal(first + (last - first) * frac)
		SetSlider(frac)
		if frac >= 1 then
			state.playing = false
			Reveal(last)
			if f.play then f.play:SetText(L["Play"]) end
			Finish()
		end
	end)

	-- a fresh run of the time lapse from `frac` (0..1): points before it count as already passed
	local function Begin(frac)
		local at = first + (last - first) * frac
		for _, p in ipairs(pts) do p.fired = p.t < at end
		if f.summary then f.summary:Hide() end
		if full then J.Sound("play", 2, 1) end
	end

	-- the controls: the time frame, play / pause, me or everyone, speed (full) and a bigger view
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
			-- (from where the slider stands, unless it's at the end)
			local at = slider and slider:GetValue() / 1000 or 0
			if at >= 0.999 then at = 0 end
			state.clock = at * PlayTime()
			state.playing = #pts > 0
			if state.playing then Begin(at) end
			f.play:SetText(L["Pause"])
		end
	end)
	f.play:SetPoint("LEFT", prev, "RIGHT", 10, 0)
	f.who = W.Button(f, L["Everyone"], 84, function() state.everyone = not state.everyone f:Refresh(true) end)
	f.who:SetPoint("LEFT", f.play, "RIGHT", 4, 0)
	do -- (#47, both sizes: the Journal's pane too)
		-- (#47) 1x / 2x / 4x
		f.speed = W.Button(f, "1x", 44, function()
			local i = 1
			for k, v in ipairs(SPEEDS) do if v == state.speed then i = k end end
			state.speed = SPEEDS[i % #SPEEDS + 1]
			f.speed:SetText(state.speed .. "x")
			J.PlayNamed("speed")
		end)
		f.speed:SetPoint("LEFT", f.who, "RIGHT", 4, 0)
		-- (#47) the scrub slider over the whole width, above the buttons
		slider = CreateFrame("Slider", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
		slider:SetOrientation("HORIZONTAL")
		slider:SetHeight(16)
		slider:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 38)
		slider:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 38)
		slider:SetMinMaxValues(0, 1000)
		slider:SetValueStep(1)
		slider:SetObeyStepOnDrag(false)
		local track = slider:CreateTexture(nil, "BACKGROUND")
		track:SetPoint("LEFT") track:SetPoint("RIGHT")
		track:SetHeight(4)
		track:SetColorTexture(0.25, 0.2, 0.12, 0.9)
		slider.fill = slider:CreateTexture(nil, "BORDER")
		slider.fill:SetPoint("LEFT", track, "LEFT")
		slider.fill:SetHeight(4)
		slider.fill:SetColorTexture(1, 0.78, 0.3, 0.9)
		slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
		local thumb = slider:GetThumbTexture()
		if thumb then thumb:SetSize(28, 28) end
		slider:SetScript("OnValueChanged", function(self, v)
			local frac = v / 1000
			self.fill:SetWidth(math.max(1, (self:GetWidth() or 0) * frac))
			if self.quiet then return end
			-- the reader dragged it: stop playing, jump the heads there (no effects while scrubbing)
			state.playing = false
			f.play:SetText(L["Play"])
			state.scrubbing = true
			state.clock = frac * PlayTime()
			Reveal(first + (last - first) * frac)
			if math.abs((self.ticked or 0) - v) > 60 then
				self.ticked = v
				J.PlayNamed("scrub")
			end
		end)
		slider:SetScript("OnMouseUp", function() state.scrubbing = nil end)
	end
	if full then
		f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		f.summary:SetPoint("BOTTOM", stage, "BOTTOM", 0, 6)
		f.summary:SetShadowOffset(1, -1)
		f.summary:Hide()
	end
	f.big = W.Button(f, L["Larger"], 70, function() if opts.onLarger then opts.onLarger() end end)
	f.big:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 7)
	f.big:SetShown(not full and opts.onLarger ~= nil)

	-- (#48) Everyone mode: the names in class colours; click one to hide or show their line
	local legend = CreateFrame("Frame", nil, f)
	legend:SetPoint("TOPRIGHT", stage, "TOPRIGHT", -4, -4)
	legend:SetSize(10, 16)
	legend:SetFrameLevel(overlay:GetFrameLevel() + 12)
	legend.items = {}
	local function Legend(keys)
		for _, b in ipairs(legend.items) do b:Hide() end
		if not keys then legend:Hide() return end
		local hidden = Saved()
		local x = 0
		for i, key in ipairs(keys) do
			local b = legend.items[i]
			if not b then
				b = CreateFrame("Button", nil, legend)
				b:SetHeight(16)
				b.bg = b:CreateTexture(nil, "BACKGROUND")
				b.bg:SetAllPoints()
				b.bg:SetColorTexture(0, 0, 0, 0.55)
				b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				b.text:SetPoint("CENTER")
				b:SetScript("OnClick", function(self)
					local h = Saved()
					h[self.key] = not h[self.key] or nil
					J.PlayNamed("legend")
					f:Refresh(false)
				end)
				b:SetScript("OnEnter", function(self)
					GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
					GameTooltip:SetText(ns.CharName(self.key), 1, 1, 1)
					GameTooltip:AddLine(Saved()[self.key] and L["Click: show their line."] or L["Click: hide their line."], 0.6, 0.8, 1)
					GameTooltip:Show()
				end)
				b:SetScript("OnLeave", GameTooltip_Hide)
				legend.items[i] = b
			end
			b.key = key
			local r, g, bl = ClassRGB(key)
			local off = hidden[key]
			b.text:SetText(ns.CharName(key, true))
			b.text:SetTextColor(off and 0.45 or r, off and 0.45 or g, off and 0.45 or bl)
			b:SetWidth(b.text:GetStringWidth() + 12)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", legend, "TOPLEFT", x, 0)
			x = x + b:GetWidth() + 3
			b:Show()
		end
		legend:SetWidth(math.max(10, x))
		legend:Show()
	end

	function f:IsPlaying() return state.playing end
	function f:SetLarge(on) f.big:SetText(on and L["Smaller"] or L["Larger"]) end

	-- whose journey: a character from the header, else you (or everyone)
	function f:SetCharacter(key) state.char = key state.focus = nil end

	function f:Focus(entry)
		state.focus = entry and entry.m and entry.x and entry or nil
		self:Refresh(false)
	end

	-- (#49) one stretch of line between two points: solid, dashed (boats, zeppelins) or dotted (flights)
	local function Segment(p, q, style, w, h, thick, r, g, b, a)
		local x1, y1, x2, y2 = q.px * w, -q.py * h, p.px * w, -p.py * h
		if style == "solid" then
			local l = Line()
			l:SetThickness(thick)
			l:SetColorTexture(r, g, b, a)
			l:SetStartPoint("TOPLEFT", overlay, x1, y1)
			l:SetEndPoint("TOPLEFT", overlay, x2, y2)
			p.segs[#p.segs + 1] = l
			return
		end
		local dx, dy = x2 - x1, y2 - y1
		local len = math.sqrt(dx * dx + dy * dy)
		if len < 1 then return end
		if style == "dashed" then
			local dash, gap = math.max(5, unitW / 90), math.max(4, unitW / 130)
			local d = 0
			while d < len do
				local e = math.min(len, d + dash)
				local l = Line()
				l:SetThickness(thick)
				l:SetColorTexture(r, g, b, a)
				l:SetStartPoint("TOPLEFT", overlay, x1 + dx * d / len, y1 + dy * d / len)
				l:SetEndPoint("TOPLEFT", overlay, x1 + dx * e / len, y1 + dy * e / len)
				p.segs[#p.segs + 1] = l
				d = e + gap
			end
		else -- dotted
			local step = math.max(6, unitW / 70)
			local size = math.max(3, thick * 1.6)
			for d = 0, len, step do
				local t = Bead()
				t:SetSize(size, size)
				t:SetVertexColor(r, g, b, a)
				t:ClearAllPoints()
				t:SetPoint("CENTER", overlay, "TOPLEFT", x1 + dx * d / len, y1 + dy * d / len)
				p.segs[#p.segs + 1] = t
			end
		end
	end

	function f:Refresh(replay)
		if not ns.db then return end
		HideAll()
		wipe(pts)
		nl, nb = 0, 0
		local scope = ns.ScopeChar()
		-- (full: Everyone works for the selected character's account too)
		local who
		if full then who = scope or ((not state.everyone) and (state.char or ns.CharKey())) or nil
		else who = scope or state.char or ((not state.everyone) and ns.CharKey()) or nil end
		f.who:SetShown(not scope and (full or not state.char))
		if full then f.who:SetText(state.everyone and L["One character"] or L["Everyone"])
		else f.who:SetText(state.everyone and L["Only me"] or L["Everyone"]) end
		for _, b in ipairs(buttons) do
			if b.key == state.range then b:LockHighlight() else b:UnlockHighlight() end
		end
		local all = J.Points(J.From(state.range), who)
		-- (#48) Everyone mode: the legend of names; hidden characters' points left out
		if not who then
			local seen, keys = {}, {}
			for _, p in ipairs(all) do if p.c and not seen[p.c] then seen[p.c] = true keys[#keys + 1] = p.c end end
			table.sort(keys, function(a, b) return ns.CharName(a, true) < ns.CharName(b, true) end)
			Legend(#keys > 1 and keys or nil)
			local hidden = Saved()
			if next(hidden) then
				local kept = {}
				for _, p in ipairs(all) do if not hidden[p.c] then kept[#kept + 1] = p end end
				all = kept
			end
		else
			Legend(nil)
		end
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
		-- the whole map fitted in the stage
		local baseW = (h > sh) and (sw * sh / h) or sw
		local baseH = h * baseW / sw
		-- (zoom to the journey) the area the points cover on this map, with a margin round it
		local x0, x1, y0, y1
		if not state.focus then
			for _, p in ipairs(all) do
				local px, py = ToShown(p.m, p.x, p.y, shown)
				if px then
					x0, x1 = math.min(x0 or px, px), math.max(x1 or px, px)
					y0, y1 = math.min(y0 or py, py), math.max(y1 or py, py)
				end
			end
		end
		local z, cx, cy = 1, 0.5, 0.5
		if x0 then
			local bw, bh = math.max(x1 - x0, 0.03) + 0.1, math.max(y1 - y0, 0.03) + 0.1
			z = math.max(1, math.min(ZOOM_MAX, sw / (bw * baseW), sh / (bh * baseH)))
			cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
		end
		h = map:Draw(shown, baseW * z)
		local w = map:GetWidth()
		-- place it: the journey in the middle, the map's edges never inside the stage
		local ox = (w > sw) and math.min(0, math.max(sw - w, sw / 2 - cx * w)) or (sw - w) / 2
		local oy = (h > sh) and math.min(0, math.max(sh - h, sh / 2 - cy * h)) or (sh - h) / 2
		f.mapX, f.mapY = ox, -oy
		map:ClearAllPoints()
		map:SetPoint("TOPLEFT", stage, "TOPLEFT", f.mapX, f.mapY)
		map:SetPins({})
		unitW = sw
		title:SetText(L["Journey"] .. "  |cff999999" .. whoText .. "  ·  " .. rangeLabel .. "  ·  " .. ZoneName(shown) .. "|r")

		-- the points that fall on this map, each with its dot and the line from the one before it
		local prevBy = {}
		local nd, np = 0, 0
		for _, pin in ipairs(pins) do pin:Hide() end
		local placed = {}
		local function Pin(kind, px, py)
			-- (one pin where several of a kind would sit on top of each other)
			local art0 = PIN_ART[kind] or PIN_ART.jump
			local s0 = math.max(12, unitW / 34) * (art0.scale or 1)
			for _, q in ipairs(placed) do
				if q.kind == kind and ((q.x - px * w) ^ 2 + (q.y - py * h) ^ 2) < (s0 * 0.7) ^ 2 then return q.t end
			end
			np = np + 1
			local t = pins[np]
			if not t then t = overlay:CreateTexture(nil, "OVERLAY", nil, 4) pins[np] = t end
			local art = PIN_ART[kind] or PIN_ART.jump
			t:SetBlendMode(art.add and "ADD" or "BLEND")
			if art.kindArt then
				W.SetTex(t, W.KindArt(art.kindArt)) -- (0.69.1: flights: the game's own gryphon)
			else
				t:SetTexture(W.FindIcon(art.icon))
				if art.round then t:SetTexCoord(0.08, 0.92, 0.08, 0.92) else t:SetTexCoord(0, 1, 0, 1) end
			end
			-- (#49) round, smooth edges for everything but the glowing swirls
			if not art.add then Round(overlay, t) if t.roundMask then t.roundMask:Show() end
			elseif t.roundMask then t:RemoveMaskTexture(t.roundMask) t.roundMask = nil end
			local s = s0
			t:SetSize(s, s)
			t:ClearAllPoints()
			t:SetPoint("CENTER", overlay, "TOPLEFT", px * w, -py * h)
			t:Show()
			t.isJump = kind == "jump"
			placed[#placed + 1] = { kind = kind, x = px * w, y = py * h, t = t }
			return t
		end
		first, last = nil, 0
		local tFirst, tLast = all[1] and all[1].t or 0, all[#all] and all[#all].t or 0
		local thick = math.max(2, unitW / 260)
		local dotSize = math.max(4, unitW / 150) -- (specks; they grow under the mouse)
		local focusDot
		for _, p in ipairs(all) do
			local px, py = ToShown(p.m, p.x, p.y, shown)
			if px then
				p.px, p.py = px, py
				p.segs = {}
				p.pin, p.pinFrom, p.dot = nil, nil, nil
				if who then p.r, p.g, p.b = GOLD[1], GOLD[2], GOLD[3] else p.r, p.g, p.b = ClassRGB(p.c) end
				-- discoveries are the dots you can click; the recorder's points only carry the line
				if p.e then
					nd = nd + 1
					local d = Dot(nd)
					d.p = p
					d:SetSize(dotSize, dotSize)
					d.base = dotSize
					d:ClearAllPoints()
					d:SetPoint("CENTER", overlay, "TOPLEFT", px * w, -py * h)
					d.tex:SetVertexColor(p.r * 0.85, p.g * 0.85, p.b * 0.85, 1)
					p.dot = d
					if state.focus and p.e == state.focus then focusDot = d end
				end
				local q = prevBy[p.c]
				local ride = p.k == "b" or p.k == "z" or (q and (q.k == "b" or q.k == "z"))
				-- how you got here: a hearth, a dungeon door, the graveyard after a death (a flight's
				-- landing gets its dotted line below)
				local moved = p.k == "h" or p.k == "i" or (p.k == "g" and q and q.k == "d")
				local within = q and p.t - q.t <= GAP
				-- joined when it could have been walked: by real distance and speed where the maps say
				-- (else, as before, by how far apart they sit on this map)
				local near = false
				if within then
					local jumped = Jumped(q, p)
					if jumped == nil then near = ((px - q.px) ^ 2 + (py - q.py) ^ 2) <= JUMP * JUMP
					else near = not jumped end
				end
				-- (age fade: the newest stretch full strength, the oldest at about a third)
				local fade = 1 - 0.65 * (tLast - p.t) / math.max(1, tLast - tFirst)
				if q and p.k == "f" and q.k == "F" then
					Segment(p, q, "dotted", w, h, thick, p.r, p.g, p.b, 0.95 * fade) -- (#49) the flight
				elseif q and ride and within then
					Segment(p, q, "dashed", w, h, thick, p.r, p.g, p.b, 0.8 * fade) -- (#49) boat or zeppelin
				elseif q and near and not moved and p.k ~= "f" then
					if p.k == "g" then
						Segment(p, q, "solid", w, h, thick * 0.7, GHOST[1], GHOST[2], GHOST[3], 0.45 * fade) -- (the ghost run, pale blue)
					else
						Segment(p, q, "solid", w, h, thick, p.r, p.g, p.b, 0.9 * fade)
					end
				elseif q and not near and not moved and within and p.k ~= "f" then
					-- a jump nothing explains (a portal, a summon ...): the swirl at both ends
					p.pinFrom = Pin("jump", q.px, q.py)
					p.pin = Pin("jump", px, py)
				end
				if p.k == "F" or p.k == "f" or p.k == "h" or p.k == "i" or p.k == "d" then
					p.pin = Pin(p.k, px, py)
				elseif (p.k == "b" or p.k == "z") and not (q and q.k == p.k) then
					p.pin = Pin(p.k, px, py) -- (the dock a ride left from)
				elseif q and (q.k == "b" or q.k == "z") and p.k ~= q.k then
					p.pin = Pin(q.k, px, py) -- (and the one it came to)
				elseif p.k ~= "g" and q and q.k == "g" then
					p.pin = Pin("res", px, py) -- (back to life)
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
		if slider then slider:SetEnabled(#pts > 1) end
		state.scrubbing = nil
		ClearFx()
		if replay and #pts > 1 and not state.focus then
			state.clock, state.playing = 0, true
			f.play:SetText(L["Pause"])
			SetSlider(0)
			Begin(0)
			Reveal(first)
		else
			state.playing = false
			f.play:SetText(L["Play"])
			SetSlider(1)
			for _, p in ipairs(pts) do p.fired = true end
			Reveal(last)
		end
	end

	-- redraw at the new size once the pane has been laid out (and when it grows or shrinks)
	f:SetScript("OnSizeChanged", function() if f:IsVisible() then C_Timer.After(0, function() f:Refresh(false) end) end end)
	-- the time lapse plays each time the pane opens
	f:SetScript("OnShow", function() C_Timer.After(0, function() if f:IsVisible() then f:Refresh(true) end end) end)
	return f
end
