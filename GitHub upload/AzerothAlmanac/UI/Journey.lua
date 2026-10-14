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
local FULL_TIME = { today = 200, yesterday = 200, week = 300, month = 300, all = 300 } -- (#47) the full-size tab
local SPEEDS = { 1, 2, 4, 8 }
local ZOOM_MAX = 3.5         -- (zoom to the journey: at most this much past the whole map)
local MEDIA = "Interface\\AddOns\\AzerothAlmanac\\Media\\"
local GHOST = { 0.6, 0.85, 1 }
local MAX_POINTS = 800       -- the newest points in the frame (the oldest are left off)
local GOLD = { 1, 0.82, 0.3 }
-- (2026-10-13, Shannon; DESIGN 109) a smoother, more whimsical time lapse: the head glides along the
-- line as it grows, idle time is squeezed, effects ease, zones crossfade; gryphon flights in an arc,
-- footstep puffs, a bounce on arrival, day and night on the map, "zzz" over long rests, a sparkly end
local IDLE_FULL = 15         -- a pause up to this long (seconds) plays at full length
local IDLE_RATE = 0.04       -- beyond it, idle time plays at 4% ...
local IDLE_MAX = 120         -- ... and counts as this much at most (a log-out: a short "zzz")
local WALK_MAX = 30          -- the head walks a stretch in at most this long, at the end of the gap
local FLY_MAX = 90           -- (a flight is flown the whole way, but counts at most this long on the play clock)
local SLEEP_AFTER = 600      -- a rest this long (or a log-out) shows "zzz" over the head
local function Ease(k) return 1 - (1 - k) ^ 3 end        -- quick, then settling
local function Smooth(k) if k <= 0 then return 0 elseif k >= 1 then return 1 end return k * k * (3 - 2 * k) end
J.Ease, J.Smooth = Ease, Smooth
-- how long the move into p from q takes (the rest of the gap was spent standing)
local function IsFlight(q, p) return p.k == "f" and q.k == "F" end
local function MoveTime(q, p)
	return math.min(math.max(0, p.t - q.t), IsFlight(q, p) and 1800 or WALK_MAX)
end
local function IdleWeight(idle)
	if idle <= IDLE_FULL then return idle end
	return IDLE_FULL + math.min(IDLE_MAX - IDLE_FULL, (idle - IDLE_FULL) * IDLE_RATE)
end
J.MoveTime, J.IdleWeight = MoveTime, IdleWeight
-- the map's light at an hour of the day (0..24): night 0..1 and the warm of dawn and dusk 0..1
function J.Light(hour)
	local night
	if hour < 4 or hour >= 21 then night = 1
	elseif hour < 6.5 then night = 1 - Smooth((hour - 4) / 2.5)
	elseif hour < 18 then night = 0
	else night = Smooth((hour - 18) / 3) end
	local warm = math.max(math.exp(-((hour - 6.5) / 1.2) ^ 2), math.exp(-((hour - 19) / 1.2) ^ 2))
	return night, warm
end

-- a point's time on the 12-hour clock: "Oct 10 9:05 PM" (Shannon, 2026-10-10)
function J.Stamp(t)
	local d = date("*t", t)
	local h = d.hour % 12
	if h == 0 then h = 12 end
	return ("%s %d:%02d %s"):format(date("%b %d", t), h, d.min, d.hour < 12 and "AM" or "PM")
end
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
	{ key = "yesterday", label = L["Yesterday"] },
	{ key = "week", label = L["Week"] },
	{ key = "month", label = L["Month"] },
	{ key = "all", label = L["All"] },
}

-- when a time frame starts: today from midnight; week and month the last 7 and 30 days
function J.From(range)
	local now = time()
	if range == "today" or range == "yesterday" then
		local d = date("*t", now)
		local midnight = time({ year = d.year, month = d.month, day = d.day, hour = 0 })
		if range == "yesterday" then
			local y = date("*t", midnight - 3600) -- (an hour before midnight: yesterday, whatever the clocks did)
			return time({ year = y.year, month = y.month, day = y.day, hour = 0 })
		end
		return midnight
	elseif range == "week" then return now - 7 * 86400
	elseif range == "month" then return now - 30 * 86400 end
	return 0
end

-- when a time frame ends (nil: now); yesterday ends at today's midnight
function J.To(range)
	if range ~= "yesterday" then return nil end
	return J.From("today")
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

local function Saved()
	local s = ns.db and ns.db.settings and ns.db.settings.window
	if not s then return {} end
	s.journeyHidden = s.journeyHidden or {}
	return s.journeyHidden
end

-- (2026-10-10) where you stopped the time lapse (paused, scrubbed, or closed mid-play), per time
-- frame, for the next time it opens; nil: the whole journey. Kept a day.
function J.KeepPlace(range, frac)
	local s = ns.db and ns.db.settings and ns.db.settings.window
	if not s then return end
	s.journeyAt = s.journeyAt or {}
	s.journeyAt[range or "today"] = (frac and frac > 0.001 and frac < 0.999) and { frac, time() } or nil
end
function J.KeptPlace(range)
	local s = ns.db and ns.db.settings and ns.db.settings.window
	local e = s and s.journeyAt and s.journeyAt[range or "today"]
	if type(e) ~= "table" or time() - (e[2] or 0) > 86400 then return nil end
	return e[1]
end

function W.JourneyPane(parent, opts)
	opts = opts or {}
	local full = opts.full and true or false
	local f = W.Inset(parent)
	local state = { range = "today", sel = {}, char = nil, focus = nil, playing = false, clock = 0, speed = 1 }

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -9)
	title:SetPoint("RIGHT", f, "RIGHT", -230, 0) -- (the time frame and whose journey sit at the top right)
	title:SetJustifyH("LEFT")
	title:SetWordWrap(false)

	-- the map, centred in the space between the title and the controls (full: a slider row too)
	local BOTTOM = 62 -- (the slider row and the buttons, both sizes)
	local stage = CreateFrame("Frame", nil, f)
	stage:SetPoint("TOPLEFT", 8, -32)
	stage:SetPoint("BOTTOMRIGHT", -8, BOTTOM)
	if stage.SetClipsChildren then stage:SetClipsChildren(true) end -- (the zoomed map stays inside)
	local map = W.ZoneMap(stage)
	local unitW = 540 -- (the stage's width: what pins, dots and lines are sized by, whatever the zoom)
	f.mapX, f.mapY = 0, 0
	local overlay = CreateFrame("Frame", nil, map)
	overlay:SetAllPoints(map)
	overlay:SetFrameLevel(map:GetFrameLevel() + 20)
	-- (2026-10-13) the map just left, fading out under the new one (a crossfade, not a blink)
	local ghost
	local function Ghost()
		if not ghost then
			ghost = W.ZoneMap(stage)
			ghost:SetFrameLevel(math.max(0, map:GetFrameLevel() - 1))
			ghost:Hide()
		end
		return ghost
	end
	-- (2026-10-13) day and night: the map dims to blue at night and warms at dawn and dusk, by the
	-- time beside the head (only while playing or scrubbing)
	local tint = CreateFrame("Frame", nil, map)
	tint:SetAllPoints(map)
	tint:SetFrameLevel(map:GetFrameLevel() + 12)
	tint.night = tint:CreateTexture(nil, "ARTWORK")
	tint.night:SetAllPoints()
	tint.night:SetColorTexture(0.06, 0.1, 0.32, 1)
	tint.night:SetAlpha(0)
	tint.warm = tint:CreateTexture(nil, "ARTWORK", nil, 1)
	tint.warm:SetAllPoints()
	tint.warm:SetColorTexture(1, 0.55, 0.25, 1)
	tint.warm:SetBlendMode("ADD")
	tint.warm:SetAlpha(0)
	tint.n, tint.w = 0, 0
	f.tint = tint
	f.GetGhost = function() return ghost end -- (for the tests)
	local empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	empty:SetPoint("CENTER", stage, "CENTER")
	empty:SetWidth(360)

	local lines, dots, pts, pins, beads = {}, {}, {}, {}, {}
	local heads = {}
	f.heads = heads -- (for the tests)
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
				GameTooltip:AddLine(ns.CharName(p.c) .. "  |cff999999" .. J.Stamp(p.t) .. "|r", 1, 1, 1)
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
		-- (2026-10-13) the gryphon carried under the face on a flight, and "zzz" over a long rest
		h.mount = h:CreateTexture(nil, "BORDER")
		h.mount:SetPoint("CENTER")
		W.SetTex(h.mount, W.KindArt("flight"))
		h.mount:Hide()
		h.zz = {}
		for i = 1, 3 do
			local z = h:CreateFontString(nil, "OVERLAY")
			z:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
			z:SetTextColor(0.85, 0.92, 1)
			z:SetText("z")
			z:Hide()
			h.zz[i] = z
		end
		h.hist = {}
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
		-- (2026-10-13, Shannon) the trail glows brightest right behind the head, then dims away as
		-- before (the last ones about where they were); the colour lifted a little toward white
		for i, t in ipairs(h.trail) do
			local s = size * (0.86 - i * 0.09)
			t:SetSize(s, s)
			local lift = 0.35 * 0.6 ^ (i - 1)
			t:SetVertexColor(r + (1 - r) * lift, g + (1 - g) * lift, b + (1 - b) * lift, 0.07 + 0.9 * 0.6 ^ (i - 1))
		end
	end

	local function HideHead(h)
		h:Hide()
		for _, t in ipairs(h.trail) do t:Hide() end
		for _, z in ipairs(h.zz) do z:Hide() end
		h.mount:Hide()
		wipe(h.hist)
		h.lx, h.ly, h.bounceAt, h.walk = nil, nil, nil, 0
	end
	local function HideHeads() for _, h in pairs(heads) do HideHead(h) end end

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
			a = spec.a or 1, rise = spec.rise or 0, base = base, tall = spec.tall or 1, px = px * w, py = -py * h, delay = spec.delay,
			dx = spec.dx or 0, dy = spec.dy or 0, fall = spec.fall or 0 }
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
				-- (2026-10-13) eased: bursts out quickly and settles; a soft fade in, a gentle fade out
				local ek = Ease(k)
				local sc = e.s0 + (e.s1 - e.s0) * ek
				e.t:SetSize(e.base * sc, e.base * sc * e.tall)
				local a = (k < 0.08) and (k / 0.08) or (1 - Smooth((k - 0.3) / 0.7))
				e.t:SetAlpha(e.a * a)
				if e.rise ~= 0 or e.dx ~= 0 or e.dy ~= 0 then
					e.t:ClearAllPoints()
					e.t:SetPoint("CENTER", overlay, "TOPLEFT", e.px + e.dx * ek, e.py + (e.rise + e.dy) * ek - e.fall * k * k)
				end
			end
		end
		-- the map's shake (a death)
		if f.shakeUntil then
			if now < f.shakeUntil then
				-- (2026-10-13) a shudder that dies away, not a random jitter
				local t = now - (f.shakeUntil - 0.45)
				local amp = 4 * math.exp(-t * 7)
				map:ClearAllPoints()
				map:SetPoint("TOPLEFT", stage, "TOPLEFT", f.mapX + amp * math.sin(t * 46), f.mapY + amp * 0.5 * math.cos(t * 38))
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
			else f.banner:SetAlpha(k < 0.2 and Smooth(k / 0.2) or (k > 0.7 and Smooth((1 - k) / 0.3)) or 1) end
		end
	end
	local function ClearFx()
		for _, e in ipairs(fxLive) do e.t:Hide() fxPool[#fxPool + 1] = e.t end
		wipe(fxLive)
		if f.banner then f.banner:Hide() f.bannerAt = nil end
		if f.shakeUntil then f.shakeUntil = nil map:ClearAllPoints() map:SetPoint("TOPLEFT", stage, "TOPLEFT", f.mapX, f.mapY) end
		if ghost then ghost:Hide() end
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
			if not light then f.shakeUntil = GetTime() + 0.45 end
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
		-- (2026-10-13) arriving by gryphon, hearth, portal, a jump or back to life: the head bounces
		if k == "f" or k == "h" or k == "i" or (k ~= "g" and q and q.k == "g") or (p.pinFrom and not k) then
			local hd = heads[p.c]
			if hd then hd.bounceAt = GetTime() end
		end
		-- (2026-10-13, Shannon: "skip past the tier discoveries") passing a discovery fires nothing:
		-- no tier rings, blooms, icons or chimes; a new zone still shows its name
		if p.e and p.e.k == "zone" then Banner(p.e.s) end
	end

	-- how much of the line shows: everything up to this time. While playing or scrubbing, each
	-- character's head glides from their latest point towards the next, the line growing behind it.
	local first, last = 0, 0
	local allPts = {} -- (every point in the frame, on whatever map; `pts`: those on the map shown)
	local Build -- (forward: the map's drawing, below)

	-- (2026-10-13) the play clock: idle time squeezed, so the time lapse spends its length on travel.
	-- Knots of (real time, play weight); frac 0..1 of the play length -> a real time.
	local warpT, warpW = {}, {}
	local function BuildWarp(all)
		wipe(warpT) wipe(warpW)
		if #all == 0 then return end
		local w = 0
		warpT[1], warpW[1] = all[1].t, 0
		for i = 2, #all do
			local q, p = all[i - 1], all[i]
			local dt = p.t - q.t
			if dt > 0 then
				local move = (q.c == p.c) and MoveTime(q, p) or math.min(dt, WALK_MAX)
				local idle = dt - move
				if idle > 0 then
					w = w + IdleWeight(idle)
					warpT[#warpT + 1], warpW[#warpW + 1] = q.t + idle, w
				end
				w = w + ((q.c == p.c and IsFlight(q, p)) and math.min(move, FLY_MAX) or move)
				warpT[#warpT + 1], warpW[#warpW + 1] = p.t, w
			end
		end
	end
	local function TimeAt(frac)
		local n = #warpT
		local total = warpW[n] or 0
		if n < 2 or total <= 0 then return first + (last - first) * frac end
		if frac <= 0 then return warpT[1] end
		if frac >= 1 then return warpT[n] end
		local target = frac * total
		local lo, hi = 1, n
		while hi - lo > 1 do
			local mid = math.floor((lo + hi) / 2)
			if warpW[mid] <= target then lo = mid else hi = mid end
		end
		local w0, w1 = warpW[lo], warpW[hi]
		if w1 <= w0 then return warpT[hi] end
		return warpT[lo] + (warpT[hi] - warpT[lo]) * (target - w0) / (w1 - w0)
	end
	f.TimeAt = TimeAt

	-- a point on the stretch into n, k of the way along (pixels on the overlay; flights bow upward)
	local function PathAt(n, k)
		local x, y = n.ax + n.adx * k, n.ay + n.ady * k
		if n.bow then
			local b = math.sin(math.pi * k) * n.bow
			x, y = x + n.nx * b, y + n.ny * b
		end
		return x, y
	end
	-- how far along the stretch from p into n the head is at upTo (0: still at p)
	local function GlideK(p, n, upTo)
		local move = MoveTime(p, n)
		if move <= 0 then return 0 end
		local k = (upTo - (n.t - move)) / move
		if k <= 0 then return 0 elseif k >= 1 then return 1 end
		return k
	end

	-- a point reached or not: its dot, its line (whole) and its pins
	local function On(p, on, active)
		if p.dot then p.dot:SetShown(on) end
		for _, o in ipairs(p.segs) do
			if o.cut then o.cut = nil o:SetEndPoint("TOPLEFT", overlay, o.x2, o.y2) end
			o:SetShown(on)
		end
		-- (the swirls of unexplained jumps only while playing or scrubbing: at rest they're clutter)
		if p.pin then p.pin:SetShown(on and (active or not p.pin.isJump)) end
		if p.pinFrom then p.pinFrom:SetShown(on and (active or not p.pinFrom.isJump)) end
	end
	-- the stretch into n drawn part way, to k
	local function Partial(n, k)
		for _, o in ipairs(n.segs) do
			if o.frac then o:SetShown(o.frac <= k)
			else
				o:SetShown(k > 0)
				local x, y = PathAt(n, k)
				o:SetEndPoint("TOPLEFT", overlay, x, y)
				o.cut = true
			end
		end
	end

	local cursor, lastBy, partial = 0, {}, {}
	local Heads -- (below)
	local function Reveal(upTo)
		local firing = state.playing and not state.scrubbing
		local active = (state.playing or state.scrubbing) and true or false
		if f.revealAt and upTo >= f.revealAt and f.revealActive == active then
			-- (2026-10-13) forward: only the points newly reached, not every point every frame
			for i = cursor + 1, #pts do
				local p = pts[i]
				if p.t > upTo then break end
				cursor = i
				On(p, true, active)
				if not p.fired then
					p.fired = true
					if firing then Fire(p, lastBy[p.c]) end
				end
				lastBy[p.c] = p
			end
		else
			wipe(lastBy)
			cursor = 0
			for i, p in ipairs(pts) do
				local on = p.t <= upTo
				if on then
					cursor = i
					if not p.fired then
						p.fired = true
						if firing then Fire(p, lastBy[p.c]) end
					end
					lastBy[p.c] = p
				end
				On(p, on, active)
			end
			for c in pairs(partial) do partial[c] = nil end
		end
		f.revealAt, f.revealActive = upTo, active
		f.tintAt = active and upTo or nil
		Heads(upTo, active)
	end
	f.ResetReveal = function() f.revealAt = nil wipe(lastBy) wipe(partial) cursor = 0 end

	local ROCK = { b = true, z = true }
	function Heads(upTo, active)
		local w, h = map:GetWidth(), map:GetHeight()
		local now = GetTime()
		local fx = FxOn()
		local light = FxLight()
		local size = full and math.max(26, unitW / 30) or math.max(18, unitW / 26)
		-- the stretches drawn part way last frame that aren't any more: whole, or not at all
		for c, n in pairs(partial) do
			local p = lastBy[c]
			if not active or not p or p.nextSame ~= n or n.t <= upTo then
				On(n, n.t <= upTo, active)
				partial[c] = nil
			end
		end
		for key, hd in pairs(heads) do if not lastBy[key] and hd:IsShown() then HideHead(hd) end end
		if not active then
			-- at rest: a small head on each character's last spot, nothing else
			for key, p in pairs(lastBy) do
				local hd = Head(key)
				PaintHead(hd, key, p.r, p.g, p.b, size * 0.7)
				hd:ClearAllPoints()
				hd:SetPoint("CENTER", overlay, "TOPLEFT", p.px * w, -p.py * h)
				hd:SetAlpha(1)
				hd.face:SetDesaturated(false)
				if hd.face.SetRotation then hd.face:SetRotation(0) hd.ring:SetRotation(0) end
				hd.glow:SetAlpha(0.5)
				hd.label:SetText("")
				hd.labelKey = nil
				hd.mount:Hide()
				for _, t in ipairs(hd.trail) do t:Hide() end
				for _, z in ipairs(hd.zz) do z:Hide() end
				wipe(hd.hist)
				hd.lx, hd.ly = nil, nil
				hd:Show()
			end
			return
		end
		for key, p in pairs(lastBy) do
			local hd = Head(key)
			-- where the head is: on its point, or gliding along the stretch to the next one
			local n = p.nextSame
			local k = (n and n.style and n.t > upTo) and GlideK(p, n, upTo) or 0
			local x, y
			if k > 0 then
				x, y = PathAt(n, k)
				Partial(n, k)
				partial[key] = n
			else
				x, y = p.px * w, -p.py * h
			end
			local moving = k > 0 and k < 1
			local style = moving and n.style or nil
			local flying = style == "dotted"
			local ride = style == "dashed" and (n.k == "z" or p.k == "z") and "z" or (style == "dashed" and "b") or (not moving and ROCK[p.k or ""] and p.k)
			local ghostly = p.k == "g" or (moving and n.k == "g")
			local sz = size * ((flying or (not moving and p.k == "F")) and 1.15 or 1)
			PaintHead(hd, key, p.r, p.g, p.b, sz)
			hd:SetAlpha(ghostly and 0.55 or 1)
			hd.face:SetDesaturated(p.k == "d" or ghostly)
			-- bob and rock on a boat, sway under a zeppelin, flap on a gryphon
			local ox, oy, rot = 0, 0, 0
			if ride == "b" then oy = math.sin(now * 5) * 2 rot = math.sin(now * 2.6) * 0.14
			elseif ride == "z" then ox = math.sin(now * 2.5) * 3 rot = math.sin(now * 1.6) * 0.06
			elseif flying then oy = math.sin(now * 9) * sz * 0.06 end
			if hd.face.SetRotation then hd.face:SetRotation(rot) hd.ring:SetRotation(rot) end
			hd.mount:SetShown(flying)
			if flying then
				hd.mount:SetSize(sz * 1.35, sz * 1.35)
				hd.mount:ClearAllPoints()
				hd.mount:SetPoint("CENTER", hd, "CENTER", 0, -sz * 0.32)
			end
			-- squash and stretch on arriving
			if hd.bounceAt then
				local t = now - hd.bounceAt
				if t >= 0.7 then hd.bounceAt = nil
				elseif t >= 0 then
					local b = 0.24 * math.exp(-t * 5) * math.cos(t * 17)
					hd.face:SetSize(sz * 0.78 * (1 + b), sz * 0.78 * (1 - b))
					hd.ring:SetSize(sz * 0.78 / 0.766 * (1 + b), sz * 0.78 / 0.766 * (1 - b))
					oy = oy + math.max(0, -b) * sz * 0.5
				end
			end
			hd:ClearAllPoints()
			hd:SetPoint("CENTER", overlay, "TOPLEFT", x + ox, y + oy)
			-- the time and zone beside it (set when they change, not every frame)
			local minute = math.floor(upTo / 60)
			local lk = minute * 100000 + (p.m or 0)
			if hd.labelKey ~= lk then
				hd.labelKey = lk
				hd.label:SetText(J.Stamp(upTo) .. "  ·  " .. ZoneName(p.m))
			end
			hd:Show()
			-- the comet tail: where the head has just been, shrinking into it when it stops
			local hist = hd.hist
			if hd.lx and ((x - hd.lx) ^ 2 + (y - hd.ly) ^ 2) > (sz * 4) ^ 2 then wipe(hist) end -- (a jump: no tail across it)
			local moved = hd.lx and math.sqrt((x - hd.lx) ^ 2 + (y - hd.ly) ^ 2) or 0
			-- (2026-10-13, Shannon: the glow went in the Wetlands) a slow walk across a big zone moves the
			-- head only a little each frame: the tail now shrinks only once the head has really stopped
			-- (it used to lose a glow every 0.1 s whenever a step was short, so a slow walk had none)
			local top = hist[1]
			if moved > 0.001 then hd.stillSince = nil elseif not hd.stillSince then hd.stillSince = now end
			if not top or ((x - top[1]) ^ 2 + (y - top[2]) ^ 2) >= (sz * 0.22) ^ 2 then
				table.insert(hist, 1, { x, y })
				if #hist > 7 then hist[8] = nil end
				hd.histAt = now
			elseif hd.stillSince and now - hd.stillSince > 0.25 and now - (hd.histAt or 0) > 0.08 and #hist > 0 then
				hist[#hist] = nil
				hd.histAt = now
			end
			for i, t in ipairs(hd.trail) do
				local pt = hist[i + 1]
				if pt then
					t:ClearAllPoints()
					t:SetPoint("CENTER", overlay, "TOPLEFT", pt[1], pt[2])
					t:Show()
				else
					t:Hide()
				end
			end
			-- footstep puffs (dust; pale wisps for a ghost, bubbles behind a boat, glints in the air)
			if fx and moving and moved > 0 and moved < sz * 4 then
				hd.walk = (hd.walk or 0) + moved
				local step = sz * (flying and 1.4 or 0.9) * (light and 2 or 1)
				if hd.walk >= step then
					hd.walk = 0
					hd.foot = -(hd.foot or 1)
					local len = math.max(1, math.sqrt(n.adx ^ 2 + n.ady ^ 2))
					local side = hd.foot * sz * 0.14
					local fxp, fyp = x - n.ady / len * side, y + n.adx / len * side
					local spec
					if ghostly then spec = { r = GHOST[1], g = GHOST[2], b = GHOST[3], size = sz * 0.35, dur = 0.9, s0 = 0.6, s1 = 1.4, a = 0.5, rise = 6 }
					elseif flying then spec = { r = 1, g = 0.85, b = 0.45, size = sz * 0.3, dur = 0.8, s0 = 1, s1 = 0.3, a = 0.7, fall = 6 }
					elseif ride == "b" then spec = { tex = MEDIA .. "FX_Bubbles", size = sz * 0.45, dur = 1, s0 = 0.5, s1 = 1.2, a = 0.6, rise = 4 }
					elseif ride == "z" then spec = { r = 1, g = 1, b = 1, size = sz * 0.4, dur = 1.1, s0 = 0.5, s1 = 1.4, a = 0.3 }
					else spec = { tex = MEDIA .. "FX_Dust", add = false, size = sz * 0.32, dur = 0.9, s0 = 0.5, s1 = 1.1, a = 0.55 } end
					Fx(fxp / w, -fyp / h, spec)
				end
			end
			hd.lx, hd.ly = x, y
			-- "zzz" over a long rest (or a log-out) once the head has stood a while
			local nA = p.nextAll
			local asleep = fx and not moving and nA ~= nil and (nA.t - p.t) >= SLEEP_AFTER and (upTo - p.t) >= 20
			for i, z in ipairs(hd.zz) do
				if asleep then
					local ph = (now * 0.55 + i / 3) % 1
					z:SetFont("Fonts\\FRIZQT__.TTF", math.max(9, sz * 0.4), "OUTLINE")
					z:ClearAllPoints()
					z:SetPoint("BOTTOMLEFT", hd, "TOPRIGHT", -sz * 0.25 + ph * sz * 0.5 + math.sin(ph * 6) * 2, -sz * 0.35 + ph * sz * 0.9)
					z:SetScale(0.7 + ph * 0.6)
					z:SetAlpha(math.sin(math.pi * ph) * 0.95)
					z:Show()
				else
					z:Hide()
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
		local light = FxLight()
		local size = full and math.max(26, unitW / 30) or math.max(18, unitW / 26)
		for _, p in pairs(lastBy) do
			for i = 0, 2 do Fx(p.px, p.py, { tex = RING, r = 1, g = 0.82, b = 0.3, dur = 0.9, s0 = 0.4, s1 = 2.2, delay = i * 0.3 }) end
			-- (2026-10-13) and a burst of gold sparkles that drift out and settle
			local n = light and 8 or 18
			for i = 1, n do
				local a = (i / n) * 2 * math.pi + math.random() * 0.4
				local d = size * (1.2 + math.random() * 1.8)
				local warm = math.random()
				Fx(p.px, p.py, { size = size * (0.22 + math.random() * 0.2), r = 1, g = 0.75 + warm * 0.2, b = 0.25 + warm * 0.4,
					dur = 1.1 + math.random() * 0.6, s0 = 1, s1 = 0.35, dx = math.cos(a) * d, dy = math.sin(a) * d + size * 0.4,
					fall = size * 0.8, delay = 0.15 + math.random() * 0.4 })
			end
			if not light then Fx(p.px, p.py, { r = 1, g = 0.85, b = 0.4, dur = 1.4, s0 = 0.8, s1 = 5, a = 0.45 }) end
		end
		local nz = 0
		for _ in pairs(zones) do nz = nz + 1 end
		if full and f.summary then
			f.summary:SetText(ns.N(nz, "zone", "zones") .. "  ·  " .. ns.N(flights, "flight", "flights") .. "  ·  " .. ns.N(deaths, "death", "deaths") .. "  ·  " .. ns.N(finds, "discovery", "discoveries"))
			f.summary:Show()
			f.summaryAt = GetTime() -- (it pops in, below)
		end
		if full then J.Sound("finish", 3, 1) end
	end

	-- (2026-10-10, Shannon) the time lapse follows you zone by zone: when the newest point shown so far
	-- is in another zone, that zone's map takes over (fading in, its name over it); `toCont`: pull back
	-- to the continent the journey ends on (the end of the time lapse)
	local function Follow(upTo, toCont)
		if state.focus or #allPts == 0 then return end
		local m
		if toCont then
			m = Continent(allPts[#allPts].m)
		else
			local cur
			for i = #allPts, 1, -1 do if allPts[i].t <= upTo then cur = allPts[i] break end end
			m = cur and cur.m or allPts[1].m
			-- (2026-10-13) a flight into another zone: the continent while in the air, so the gryphon
			-- can be seen crossing; the landing zone takes over when it lands
			local n = cur and cur.nextAll
			if cur and cur.k == "F" and n and n.k == "f" and n.m ~= cur.m and upTo >= n.t - MoveTime(cur, n) then
				m = Continent(cur.m)
			end
		end
		if not m or m == f.shownMap then return end
		-- (Everyone mode: two characters in different zones would flip the map back and forth)
		if not toCont and f.switchedAt and GetTime() - f.switchedAt < 1.5 then return end
		f.switchedAt = GetTime()
		-- (what's already behind the heads counts as passed: no burst of old effects on the new map)
		for _, p in ipairs(allPts) do if p.t <= upTo then p.fired = true end end
		-- (2026-10-13) the map being left stays underneath and fades out as the new one fades in
		local old, oldW, oldA = f.shownMap, map:GetWidth(), map:GetAlpha()
		if not Build(m, allPts) then return end
		if old and FxOn() then
			local g = Ghost()
			if g:Draw(old, oldW) > 0 then
				g:ClearAllPoints()
				g:SetPoint("TOPLEFT", stage, "TOPLEFT", f.ghostX or 0, f.ghostY or 0)
				g:SetAlpha(oldA or 1)
				g:Show()
			end
		end
		f.fadeTime = toCont and 0.8 or 0.6
		map:SetAlpha(0)
		f.fadeAt = GetTime()
		if not toCont then Banner(ZoneName(m)) end
	end

	f:SetScript("OnUpdate", function(_, elapsed)
		StepFx()
		if f.fadeAt then
			local k = (GetTime() - f.fadeAt) / (f.fadeTime or 0.35)
			if k >= 1 then
				map:SetAlpha(1) f.fadeAt = nil
				if ghost then ghost:Hide() end
			else
				map:SetAlpha(Smooth(k))
				if ghost and ghost:IsShown() then ghost:SetAlpha(1 - Smooth(k)) end
			end
		end
		-- (2026-10-13) day and night, eased towards the hour beside the head (none at rest)
		do
			local nTo, wTo = 0, 0
			if f.tintAt and FxOn() then
				local minute = math.floor(f.tintAt / 60)
				if minute ~= tint.minute then
					tint.minute = minute
					local d = date("*t", f.tintAt)
					tint.nTo, tint.wTo = J.Light((d.hour or 12) + (d.min or 0) / 60)
				end
				nTo, wTo = tint.nTo or 0, tint.wTo or 0
			end
			local e = math.min(1, elapsed * 2.5)
			tint.n = tint.n + (nTo - tint.n) * e
			tint.w = tint.w + (wTo - tint.w) * e
			tint.night:SetAlpha(tint.n * 0.38)
			tint.warm:SetAlpha(tint.w * 0.16)
		end
		if f.summaryAt and f.summary then
			local k = (GetTime() - f.summaryAt) / 0.5
			if k >= 1 then f.summary:SetScale(1) f.summary:SetAlpha(1) f.summaryAt = nil
			else f.summary:SetScale(1 + 0.35 * (1 - Ease(k))) f.summary:SetAlpha(Smooth(k * 1.5)) end
		end
		-- (2026-10-10) Play glows while there's a journey you haven't played since opening; the speed
		-- shows big for a moment when it's changed
		if f.playGlow then
			local want = not state.playing and not state.played and #allPts > 1
			f.playGlow:SetShown(want)
			if want then f.playGlow:SetAlpha(0.35 + 0.45 * (0.5 + 0.5 * math.sin(GetTime() * 3.5))) end
		end
		if f.speedText and f.speedAt then
			local k = (GetTime() - f.speedAt) / 0.6
			if k >= 1 then f.speedAt = nil f.speedText:SetScale(1) else f.speedText:SetScale(1 + 0.5 * (1 - k)) end
		end
		if not state.playing then return end
		state.clock = state.clock + elapsed * state.speed
		local frac = math.min(1, state.clock / PlayTime())
		local pulse = 0.72 + 0.2 * math.sin(GetTime() * 2.4) -- (2026-10-13: breathing, not flickering)
		for _, hd in pairs(heads) do hd.glow:SetAlpha(pulse) end
		local upTo = TimeAt(frac)
		Follow(upTo)
		Reveal(upTo)
		SetSlider(frac)
		if frac >= 1 then
			state.playing = false
			-- the end: pull back to the whole continent, the journey drawn on it
			f.fadeTime = 0.8
			Follow(last, true)
			Reveal(last)
			if f.PaintPlay then f.PaintPlay() end
			J.KeepPlace(state.range, nil) -- (watched to the end: next time it opens on the whole journey)
			Finish()
		end
	end)

	-- a fresh run of the time lapse from `frac` (0..1): points before it count as already passed
	local function Begin(frac)
		local at = TimeAt(frac)
		for _, p in ipairs(pts) do p.fired = p.t < at end
		if f.summary then f.summary:Hide() end
		if full then J.Sound("play", 2, 1) end
	end

	-- the controls (2026-10-10, Shannon): the time frame as a drop-down (always Today when the pane
	-- opens), a Play / Pause picture button that glows while there's a journey to play, Slower and
	-- Faster round the speed (1x 2x 4x 8x, shown big for a moment when changed), me or everyone, and
	-- a bigger view
	local function RangeLabel()
		for _, r in ipairs(J.RANGES) do if r.key == state.range then return r.label end end
		return L["Today"]
	end
	f.range = W.Dropdown(f, RangeLabel(), 92, function(self)
		local items = { { title = true, text = L["Time frame"] } }
		for _, r in ipairs(J.RANGES) do
			items[#items + 1] = { text = r.label, selected = r.key == state.range, run = function()
				state.range = r.key
				state.focus = nil
				f.range:SetText(r.label)
				f:Refresh(false)
			end }
		end
		W.Menu(self, items)
	end)
	f.range:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -3)
	local function PaintPlay()
		local name = state.playing and "Journey_Pause" or "Journey_Play"
		f.play.tex:SetTexture(MEDIA .. name)
		f.play.hl:SetTexture(MEDIA .. name)
		f.play:SetActive(true)
	end
	f.play = W.ViewButton(f, "Journey_Play", function()
		return state.playing and L["Pause"] or L["Play"], state.playing and L["Stops where it is; Play goes on from there."] or L["Plays your journey as a time lapse."]
	end, function()
		if state.playing then
			state.playing = false
			local at = math.min(1, state.clock / PlayTime())
			Reveal(TimeAt(at))
			J.KeepPlace(state.range, at)
		else
			-- (from where the slider stands, unless it's at the end)
			local at = slider and slider:GetValue() / 1000 or 0
			if at >= 0.999 then at = 0 end
			state.clock = at * PlayTime()
			state.playing = #pts > 0
			state.played = true
			if state.playing then Begin(at) end
		end
		PaintPlay()
	end)
	f.play:SetSize(28, 28)
	-- (Play, Slower, the speed, Faster: centred under the map)
	local controls = CreateFrame("Frame", nil, f)
	controls:SetSize(28 + 10 + 24 + 2 + 30 + 2 + 24, 28)
	controls:SetPoint("BOTTOM", f, "BOTTOM", 0, 6)
	f.play:SetPoint("LEFT", controls, "LEFT", 0, 0)
	-- (a glow round Play: there's a journey to watch)
	f.playGlow = f.play:CreateTexture(nil, "OVERLAY")
	f.playGlow:SetTexture(GLOW)
	f.playGlow:SetBlendMode("ADD")
	f.playGlow:SetVertexColor(1, 0.82, 0.3)
	f.playGlow:SetPoint("CENTER")
	f.playGlow:SetSize(58, 58)
	f.playGlow:Hide()
	f.PaintPlay = PaintPlay
	local function SetSpeed(step)
		local i = 1
		for k, v in ipairs(SPEEDS) do if v == state.speed then i = k end end
		i = math.max(1, math.min(#SPEEDS, i + step))
		if SPEEDS[i] == state.speed then return end
		state.speed = SPEEDS[i]
		f.speedText:SetText(state.speed .. "x")
		f.speedAt = GetTime()
		J.PlayNamed("speed")
		f.slower:SetActive(i > 1)
		f.faster:SetActive(i < #SPEEDS)
	end
	f.slower = W.ViewButton(f, "Journey_Slower", function() return L["Slower"], (L["Now %sx"]):format(state.speed) end, function() SetSpeed(-1) end)
	f.slower:SetPoint("LEFT", f.play, "RIGHT", 10, 0)
	f.speedText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.speedText:SetWidth(30)
	f.speedText:SetPoint("LEFT", f.slower, "RIGHT", 2, 0)
	f.speedText:SetText("1x")
	f.faster = W.ViewButton(f, "Journey_Faster", function() return L["Faster"], (L["Now %sx"]):format(state.speed) end, function() SetSpeed(1) end)
	f.faster:SetPoint("LEFT", f.speedText, "RIGHT", 2, 0)
	f.slower:SetActive(false)
	f.faster:SetActive(true)
	f.speed = f.speedText
	-- (2026-10-10, Shannon) whose journey: a drop-down of the account's characters with tick boxes;
	-- Everyone ticks them all (again: back to the default). The default, each time the pane opens or
	-- the character changes, is the character you're playing (or the one the page is showing).
	local function Chars()
		local keys = {}
		for key in pairs(ns.db and ns.db.chars or {}) do keys[#keys + 1] = key end
		table.sort(keys, function(a, b) return ns.CharName(a, true) < ns.CharName(b, true) end)
		return keys
	end
	local function DefaultWho() return state.char or ns.CharKey() end
	local function Picked()
		local keys, n = {}, 0
		for k in pairs(state.sel) do keys[#keys + 1] = k n = n + 1 end
		return keys, n
	end
	local function WhoLabel()
		local keys, n = Picked()
		if n == 1 then return ns.CharName(keys[1], true) end
		if n >= #Chars() then return L["Everyone"] end
		return (L["%d characters"]):format(n)
	end
	local WhoMenu
	WhoMenu = function(anchor)
		local all = Chars()
		local _, n = Picked()
		local items = { { title = true, text = L["Whose journey"] } }
		items[#items + 1] = { text = L["Everyone"], check = n >= #all, keep = true, run = function()
			if n >= #all then state.sel = { [DefaultWho()] = true }
			else state.sel = {} for _, k in ipairs(all) do state.sel[k] = true end end
			f:Refresh(false)
			WhoMenu(anchor)
		end }
		items[#items + 1] = { divider = true }
		for _, k in ipairs(all) do
			local r, g, b = ClassRGB(k)
			items[#items + 1] = { text = ns.CharName(k, true), color = { r, g, b }, check = state.sel[k] == true, keep = true, run = function()
				if state.sel[k] then
					local _, left = Picked()
					if left > 1 then state.sel[k] = nil end -- (someone always stays ticked)
				else
					state.sel[k] = true
				end
				f:Refresh(false)
				WhoMenu(anchor)
			end }
		end
		W.Menu(anchor, items)
	end
	f.who = W.Dropdown(f, WhoLabel(), 120, function(self) WhoMenu(self) end)
	f.who:SetPoint("RIGHT", f.range, "LEFT", -4, 0)
	PaintPlay()
	do -- (#47, both sizes: the Journal's pane too)
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
			PaintPlay()
			state.scrubbing = true
			state.clock = frac * PlayTime()
			f.fadeTime = 0.35
			Follow(TimeAt(frac), frac >= 0.999)
			Reveal(TimeAt(frac))
			if math.abs((self.ticked or 0) - v) > 60 then
				self.ticked = v
				J.PlayNamed("scrub")
			end
		end)
		slider:SetScript("OnMouseUp", function(self)
			state.scrubbing = nil
			J.KeepPlace(state.range, self:GetValue() / 1000)
		end)
	end
	if full then
		f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		f.summary:SetPoint("BOTTOM", stage, "BOTTOM", 0, 6)
		f.summary:SetShadowOffset(1, -1)
		f.summary:Hide()
	end
	-- (2026-10-10, Shannon) Larger / Smaller as a picture button, like the playback ones
	f.big = W.ViewButton(f, "Journey_Larger", function() return f.isLarge and L["Smaller"] or L["Larger"], f.isLarge and L["Back to the Journal's own size."] or L["The Journey over the whole page."] end,
		function() if opts.onLarger then opts.onLarger() end end)
	f.big:SetSize(28, 28)
	f.big:SetActive(true)
	f.big:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 6)
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
					-- (2026-10-10: the ticks in the drop-down decide; a click here unticks them)
					state.sel[self.key] = nil
					J.PlayNamed("legend")
					f:Refresh(false)
				end)
				b:SetScript("OnEnter", function(self)
					GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
					GameTooltip:SetText(ns.CharName(self.key), 1, 1, 1)
					GameTooltip:AddLine(L["Click: hide their line (tick them again in the drop-down)."], 0.6, 0.8, 1)
					GameTooltip:Show()
				end)
				b:SetScript("OnLeave", GameTooltip_Hide)
				legend.items[i] = b
			end
			b.key = key
			local r, g, bl = ClassRGB(key)
			local off = false
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
	function f:SetLarge(on)
		f.isLarge = on and true or false
		local name = MEDIA .. (on and "Journey_Smaller" or "Journey_Larger")
		f.big.tex:SetTexture(name)
		f.big.hl:SetTexture(name)
	end

	-- whose journey: a character from the header, else you; picking one starts the ticks over
	function f:SetCharacter(key) state.char = key state.focus = nil state.sel = { [key or ns.CharKey()] = true } end

	function f:Focus(entry)
		state.focus = entry and entry.m and entry.x and entry or nil
		self:Refresh(false)
	end

	-- (#49) one stretch of line between two points: solid, dashed (boats, zeppelins) or dotted (flights)
	-- (2026-10-13) the stretch is kept on p (start, direction, a flight's bow) so the head can glide along
	-- it and it can be drawn part way: each dash and bead knows how far along it sits (o.frac)
	local function Segment(p, q, style, w, h, thick, r, g, b, a)
		local x1, y1, x2, y2 = q.px * w, -q.py * h, p.px * w, -p.py * h
		local dx, dy = x2 - x1, y2 - y1
		local len = math.sqrt(dx * dx + dy * dy)
		p.style, p.ax, p.ay, p.adx, p.ady, p.bow = style, x1, y1, dx, dy, nil
		if style == "solid" then
			local l = Line()
			l:SetThickness(thick)
			l:SetColorTexture(r, g, b, a)
			l:SetStartPoint("TOPLEFT", overlay, x1, y1)
			l:SetEndPoint("TOPLEFT", overlay, x2, y2)
			l.x2, l.y2, l.frac, l.cut = x2, y2, nil, nil
			p.segs[#p.segs + 1] = l
			return
		end
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
				l.frac, l.cut = d / len, nil
				p.segs[#p.segs + 1] = l
				d = e + gap
			end
		else -- dotted: a flight, bowed upward into a gentle arc
			local nx, ny = -dy / len, dx / len
			if ny < 0 then nx, ny = -nx, -ny end
			p.bow, p.nx, p.ny = math.min(len * 0.18, unitW / 12), nx, ny
			local step = math.max(6, unitW / 70)
			local size = math.max(3, thick * 1.6)
			local arc = len * (1 + 0.6 * (p.bow / len) ^ 2) -- (the arc's length, near enough)
			local count = math.max(1, math.floor(arc / step))
			for i = 0, count do
				local k = i / count
				local t = Bead()
				t:SetSize(size, size)
				t:SetVertexColor(r, g, b, a)
				t:ClearAllPoints()
				local bw = math.sin(math.pi * k) * p.bow
				t:SetPoint("CENTER", overlay, "TOPLEFT", x1 + dx * k + nx * bw, y1 + dy * k + ny * bw)
				t.frac = k
				p.segs[#p.segs + 1] = t
			end
		end
	end

	-- (2026-10-10, Shannon) one map's drawing: `shown` fitted and zoomed to the points that fall on it,
	-- each with its dot, pins and the line from the one before it. Used for the whole frame at rest,
	-- for each zone in turn while the time lapse plays, and for the continent when it ends.
	function Build(shown, all)
		f.ghostX, f.ghostY = f.mapX, f.mapY -- (where the map being left sat, for the crossfade)
		if f.ResetReveal then f.ResetReveal() end
		HideAll()
		wipe(pts)
		nl, nb = 0, 0
		map:Show()
		empty:Hide()
		f.shownMap = shown
		-- fit the map into the stage, keeping its shape
		local sw, sh = stage:GetWidth(), stage:GetHeight()
		if not (sw and sw > 10 and sh and sh > 10) then sw, sh = 540, 300 end
		local h = map:Draw(shown, sw)
		if h == 0 then return false end
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
		title:SetText(L["Journey"] .. "  |cff999999" .. (f.whoText or "") .. "  ·  " .. (f.rangeLabel or "") .. "  ·  " .. ZoneName(shown) .. "|r")

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
				p.style, p.bow, p.nextSame = nil, nil, nil
				if f.drawWho then p.r, p.g, p.b = GOLD[1], GOLD[2], GOLD[3] else p.r, p.g, p.b = ClassRGB(p.c) end -- (one character: gold; was reading an unset global, 2026-10-11)
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
				if q then q.nextSame = p end
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
					-- (2026-10-10, Shannon) crossing into another zone joins line to line, never a portal
					-- swirl (the zone's own map coordinates made the step look like a jump)
					-- (a real teleport, more than 1500 yards across the continent, still swirls)
					if not near and q.m ~= p.m then
						local x1, y1 = Yards(q.m, q.x, q.y)
						local x2, y2 = Yards(p.m, p.x, p.y)
						near = not (x1 and x2) or math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) < 1500
					end
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
			end
		end
		if focusDot then
			ring:ClearAllPoints()
			ring:SetPoint("CENTER", focusDot, "CENTER")
			ring:SetSize(dotSize * 2.6, dotSize * 2.6)
			ring:SetAlpha(0.8)
			ring:Show()
			focusDot:SetFrameLevel(overlay:GetFrameLevel() + 5)
		end
		return true
	end

	function f:Refresh(replay)
		if not ns.db then return end
		HideAll()
		wipe(pts)
		nl, nb = 0, 0
		local scope = ns.ScopeChar()
		-- (full: Everyone works for the selected character's account too)
		if not next(state.sel) then state.sel = { [DefaultWho()] = true } end
		local picked, npicked = Picked()
		local who = scope or (npicked == 1 and picked[1]) or nil
		f.drawWho = who
		f.who:SetShown(not scope)
		f.who:SetText(WhoLabel())
		f.range:SetText(RangeLabel())
		local all = J.Points(J.From(state.range), who)
		-- (yesterday: up to today's midnight)
		local to = J.To(state.range)
		if to then
			local kept = {}
			for _, p in ipairs(all) do if p.t < to then kept[#kept + 1] = p end end
			all = kept
		end
		-- several ticked: only theirs, and the legend of names in class colours
		if not who then
			local kept, seen, keys = {}, {}, {}
			for _, p in ipairs(all) do
				if p.c and state.sel[p.c] then
					kept[#kept + 1] = p
					if not seen[p.c] then seen[p.c] = true keys[#keys + 1] = p.c end
				end
			end
			all = kept
			table.sort(keys, function(a, b) return ns.CharName(a, true) < ns.CharName(b, true) end)
			Legend(#keys > 1 and keys or nil)
		else
			Legend(nil)
		end
		-- the map at rest: the focused entry's zone; else the continent the journey ends on (2026-10-10:
		-- the time lapse plays zone by zone, then the view pulls back to the continent)
		local shown
		if state.focus then shown = state.focus.m
		elseif #all > 0 then shown = Continent(all[#all].m) end
		local rangeLabel
		for _, r in ipairs(J.RANGES) do if r.key == state.range then rangeLabel = r.label end end
		local whoText = who and ns.CharName(who) or WhoLabel()
		f.whoText, f.rangeLabel = whoText, rangeLabel
		-- (2026-10-13) the recorder wrote a point at each zone crossed while on a flight: those are
		-- dropped, so the take-off and the landing pair up (the dotted arc, the gryphon)
		do
			local kept, flying = {}, {}
			for _, p in ipairs(all) do
				local c = p.c or 0
				local fl = flying[c]
				if p.k == "F" then flying[c] = p.t kept[#kept + 1] = p
				elseif fl and not p.k and p.t - fl < 1800 and not p.e then -- (skip it)
				else
					if p.k then flying[c] = nil end
					kept[#kept + 1] = p
				end
			end
			all = kept
		end
		allPts = all
		first, last = (all[1] and all[1].t) or 0, (all[#all] and all[#all].t) or 0
		BuildWarp(all)
		do -- (each point's next one for the same character, on any map: how long they rested)
			local prev = {}
			for _, p in ipairs(all) do
				p.nextAll = nil
				local q = prev[p.c or 0]
				if q then q.nextAll = p end
				prev[p.c or 0] = p
			end
		end
		if not shown then
			map:Hide()
			empty:SetText(L["No journey here yet: each discovery you make marks where you were, and the line joins them."])
			empty:Show()
			title:SetText(L["Journey"] .. "  |cff999999" .. whoText .. "  ·  " .. rangeLabel .. "|r")
			f.play:Disable()
			return
		end
		state.scrubbing = nil
		ClearFx()
		local play = replay and #all > 1 and not state.focus
		f.fadeAt, f.fadeTime = nil, 0.35
		map:SetAlpha(1)
		-- playing: the first point's own zone; at rest: the whole frame
		if not Build(play and all[1].m or shown, all) then
			map:Hide()
			empty:SetText(L["This map can't be drawn here."])
			empty:Show()
			f.play:Disable()
			return
		end
		f.play:SetEnabled(#all > 0)
		if slider then slider:SetEnabled(#all > 1) end
		if play then
			state.clock, state.playing, state.played = 0, true, true
			PaintPlay()
			SetSlider(0)
			Begin(0)
			Reveal(first)
		else
			state.playing = false
			PaintPlay()
			-- (2026-10-10) where you left off (paused or scrubbed, this time frame), else the whole journey
			local at = (not state.focus) and #all > 1 and J.KeptPlace(state.range) or 1
			local upTo = TimeAt(at)
			state.clock = at * PlayTime()
			SetSlider(at)
			for _, p in ipairs(all) do p.fired = p.t <= upTo end
			if at < 1 then
				local m
				for i = #all, 1, -1 do if all[i].t <= upTo then m = all[i].m break end end
				if m and m ~= f.shownMap then Build(m, all) end
			end
			Reveal(upTo)
		end
	end

	-- redraw at the new size once the pane has been laid out (and when it grows or shrinks)
	f:SetScript("OnSizeChanged", function() if f:IsVisible() then C_Timer.After(0, function() f:Refresh(false) end) end end)
	-- (2026-10-10, Shannon) opening the pane: Today, at rest, where you left off (else the whole
	-- journey), Play glowing; closing it mid-play keeps the place
	f:SetScript("OnShow", function()
		state.range, state.played = "today", false
		state.sel = { [state.char or ns.CharKey()] = true }
		C_Timer.After(0, function() if f:IsVisible() then f:Refresh(false) end end)
	end)
	f:SetScript("OnHide", function()
		if state.playing then
			state.playing = false
			J.KeepPlace(state.range, math.min(1, state.clock / PlayTime()))
		end
	end)
	return f
end
