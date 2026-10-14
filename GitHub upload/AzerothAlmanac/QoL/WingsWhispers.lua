-- Ported from Plus Everything (same author) for Azeroth Almanac's quality-of-life helpers.
-- Wings & Whispers: when you take a flight, meet the creature carrying you. Its name,
-- personality and a fun fact the first time; just the ride count after that. A landing quip,
-- optional party chat, and a prompt to play Gem Match on longer flights.
-- The cast is in Data\FlightCrew.lua. Settings > Travel > Wings & Whispers.

local _, A = ...
local ns = A.QoL
local WW = ns:NewModule("WingsWhispers")

local CREW = ns.FlightCrew or {}
local CREW_SIZE = 4          -- regulars at each flight master
local RARE_CHANCE = 0.02     -- a rare guest instead
local GEM_PROMPT_MIN = 45    -- seconds: only offer a game on flights at least this long
local GEM_PROMPT_SHOW = 25   -- seconds the prompt stays up

-- Horde flight masters around Lordaeron use bats.
local BAT_MAPS = { [1420] = true, [1458] = true, [1421] = true, [1424] = true } -- Tirisfal, Undercity, Silverpine, Hillsbrad
local KALIMDOR, EASTERN_KINGDOMS = 1414, 1415
local SPECIES_WORD = { gryphon = "gryphon", windrider = "wind rider", hippogryph = "hippogryph", bat = "bat" }

local db
local current      -- { creature, species, count } for the flight in progress
local prompt       -- the Gem Match prompt frame

---------------------------------------------------------------------------
-- Picking the creature
---------------------------------------------------------------------------

local function CharKey()
	return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function Continent(mapID)
	local guard = 0
	while mapID and guard < 10 do
		if mapID == KALIMDOR or mapID == EASTERN_KINGDOMS then return mapID end
		local info = C_Map.GetMapInfo(mapID)
		mapID = info and info.parentMapID
		guard = guard + 1
	end
end

-- Alliance: gryphons in the Eastern Kingdoms, hippogryphs in Kalimdor. Horde: wind riders,
-- bats around Undercity. (Forever's new routes follow the same rules for now.)
function WW.Species(faction, mapID)
	if faction == "Horde" then
		return BAT_MAPS[mapID or 0] and "bat" or "windrider"
	end
	return Continent(mapID) == KALIMDOR and "hippogryph" or "gryphon"
end

-- A simple stable hash, so each flight master always has the same regulars.
local function Hash(text)
	local h = 5381
	for i = 1, #text do h = (h * 33 + text:byte(i)) % 2147483647 end
	return h
end

-- The regulars at this flight master: CREW_SIZE creatures of the species, picked by its name.
function WW.Crew(species, node)
	local list = CREW[species] or {}
	local crew, used = {}, {}
	local h = Hash(node or "?")
	for i = 1, math.min(CREW_SIZE, #list) do
		local index = (h + i * 7919) % #list + 1
		while used[index] do index = index % #list + 1 end
		used[index] = true
		crew[#crew + 1] = list[index]
	end
	return crew
end

function WW.Pick(species, node, roll)
	roll = roll or math.random()
	if roll < RARE_CHANCE and CREW.rare and #CREW.rare > 0 then
		return CREW.rare[math.random(#CREW.rare)], "rare"
	end
	local crew = WW.Crew(species, node)
	if #crew == 0 then return nil end
	return crew[math.random(#crew)], species
end

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------

-- A line is a string, or { spicy, family }.
local function Say(line, fill)
	if type(line) == "table" then line = (db.spicy and line[1]) or line[2] or line[1] end
	line = tostring(line or "")
	return (line:gsub("{(%w+)}", function(key) return fill and fill[key] ~= nil and tostring(fill[key]) or "" end))
end

local function Pick(list)
	if not list or #list == 0 then return nil end
	return list[math.random(#list)]
end

local function Clock(seconds)
	seconds = math.max(0, math.floor((seconds or 0) + 0.5))
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

-- (0.69.1) through the Almanac's own chat line (its logo and red name), then the feature's name
local HEADER = "|cff66ccffWings & Whispers:|r "
local function Out(text)
	if ns.Print then ns.Print(HEADER .. text) else DEFAULT_CHAT_FRAME:AddMessage(HEADER .. text) end
end

local function Rides(key)
	local char = CharKey()
	db.rides[char] = db.rides[char] or {}
	return db.rides[char], char
end

---------------------------------------------------------------------------
-- A game for the flight: Wild Gambit (its logo as the button), Murloc Tac Toe or Gem Match, one of
-- them recommended (a different one each time, glowing gold)
---------------------------------------------------------------------------

local GAMES = {
	{ key = "gambit", name = "Wild Gambit", module = "WildGambit", logo = "Interface\\AddOns\\AzerothAlmanac\\Media\\Logo_WildGambit",
		pitch = "How about a hand of Wild Gambit?", tip = "Your Almanac's creatures as cards: a quick round against a nearby creature." },
	{ key = "murloc", name = "Murloc Tac Toe", module = "MurlocTacToe", icon = "Interface\\AddOns\\AzerothAlmanac\\Media\\MurlocTacToe_Icon",
		pitch = "Fancy a quick Murloc Tac Toe?", tip = "Murlocs against gnolls, three in a row. Mrglglgl!" },
	{ key = "gem", name = "Gem Match", module = "GemMatch", icon = "Interface\\AddOns\\AzerothAlmanac\\Media\\Icon_GemMatch",
		pitch = "Pass the flight with some Gem Match?", tip = "A match-three game with Classic gems. It pauses by itself in combat." },
}
local lastPick

-- the games you have, and today's recommendation
local function Available()
	local list = {}
	for _, g in ipairs(GAMES) do if ns[g.module] and ns[g.module].Open then list[#list + 1] = g end end
	return list
end
local function Recommend(list)
	local choices = {}
	for _, g in ipairs(list) do if g.key ~= lastPick then choices[#choices + 1] = g end end
	if #choices == 0 then choices = list end
	local g = choices[math.random(#choices)]
	lastPick = g and g.key
	return g
end

-- a row of the three games' buttons (the logo for Wild Gambit, an icon and name for the others);
-- onPlay runs after a game opens (to close what offered it)
local function GameRow(parent, onPlay)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(330, 34)
	row.buttons = {}
	local x = 0
	for i, g in ipairs(GAMES) do
		local b = CreateFrame("Button", nil, row)
		b.game = g
		if g.logo then
			b:SetSize(120, 34)
			b.art = b:CreateTexture(nil, "ARTWORK")
			b.art:SetAllPoints()
			b.art:SetTexture(g.logo)
		else
			b:SetSize(100, 34)
			b.art = b:CreateTexture(nil, "ARTWORK")
			b.art:SetSize(26, 26)
			b.art:SetPoint("LEFT", 2, 0)
			if g.icon:find("\\", 1, true) then
				b.art:SetTexture(g.icon) -- (our own painted icon: whole, no border to crop)
			else
				b.art:SetTexture("Interface\\Icons\\" .. g.icon)
				b.art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			end
			b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			b.label:SetPoint("LEFT", b.art, "RIGHT", 5, 0)
			b.label:SetPoint("RIGHT", -2, 0)
			b.label:SetJustifyH("LEFT")
			b.label:SetText(g.name)
		end
		b.glow = b:CreateTexture(nil, "BACKGROUND")
		b.glow:SetPoint("TOPLEFT", -8, 8)
		b.glow:SetPoint("BOTTOMRIGHT", 8, -8)
		b.glow:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
		b.glow:SetBlendMode("ADD")
		b.glow:SetVertexColor(1, 0.8, 0.3)
		b.glow:Hide()
		b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		b:SetPoint("LEFT", x, 0)
		x = x + b:GetWidth() + 6
		b:SetScript("OnClick", function(self)
			local m = ns[self.game.module]
			if onPlay then onPlay() end
			if m and m.Open then m:Open() end
		end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText(self.game.name)
			GameTooltip:AddLine(self.game.tip, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", GameTooltip_Hide)
		row.buttons[i] = b
	end
	row:SetWidth(x - 6)
	-- shows the games you have, the recommended one glowing; returns it
	function row:Offer()
		local list = Available()
		local have = {}
		for _, g in ipairs(list) do have[g.key] = true end
		local pick = Recommend(list)
		local x2 = 0
		for _, b in ipairs(self.buttons) do
			b:SetShown(have[b.game.key] and true or false)
			if have[b.game.key] then b:ClearAllPoints() b:SetPoint("LEFT", x2, 0) x2 = x2 + b:GetWidth() + 6 end
			b.glow:SetShown(pick and b.game.key == pick.key)
		end
		self:SetWidth(math.max(1, x2 - 6))
		return pick
	end
	-- the recommended game's glow breathes
	row:SetScript("OnUpdate", function(self, e)
		self.t = (self.t or 0) + e
		local a = 0.45 + 0.35 * math.sin(self.t * 3)
		for _, b in ipairs(self.buttons) do if b.glow:IsShown() then b.glow:SetAlpha(a) end end
	end)
	return row
end
WW.GameRow = GameRow

local function BuildPrompt()
	local f = CreateFrame("Frame", "AzerothAlmanacWingsGemPrompt", UIParent, "BackdropTemplate")
	f:SetSize(360, 82)
	f:SetPoint("TOP", UIParent, "TOP", 0, -200)
	f:SetFrameStrata("DIALOG")
	f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	f:SetBackdropBorderColor(1, 0.82, 0)
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.text:SetPoint("TOPLEFT", 12, -10)
	f.text:SetPoint("TOPRIGHT", -26, -10)
	f.text:SetJustifyH("LEFT")
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetSize(20, 20)
	close:SetPoint("TOPRIGHT", -3, -3)
	close:SetScript("OnClick", function() f:Hide() end)
	f.row = GameRow(f, function() f:Hide() end)
	f.row:SetPoint("BOTTOM", f, "BOTTOM", 0, 10)
	f:Hide()
	return f
end

local function ShowGemPrompt(flight)
	if not db.gemPrompt or #Available() == 0 then return end
	if flight.planned and flight.planned < GEM_PROMPT_MIN then return end
	prompt = prompt or BuildPrompt()
	local pick = prompt.row:Offer()
	local pitch = pick and pick.pitch or "A game while you fly?"
	prompt.text:SetText(flight.planned and ("%s  |cffaaaaaa(%s flight)|r"):format(pitch, Clock(flight.planned)) or pitch)
	prompt:SetWidth(math.max(300, prompt.row:GetWidth() + 30))
	prompt:Show()
	prompt.token = (prompt.token or 0) + 1
	local token = prompt.token
	C_Timer.After(GEM_PROMPT_SHOW, function() if prompt.token == token then prompt:Hide() end end)
end

---------------------------------------------------------------------------
-- The talking portrait panel
---------------------------------------------------------------------------
-- (2026-10-13, Shannon; DESIGN 112) like a unit frame: the creature's live 3D model in an ornate round
-- gold ring, its name on a plate that slides out to the right from behind the ring (like a nameplate),
-- the words typing out underneath on the see-through backing. The ride count sits in a small gold
-- medallion on the ring. Bottom center by default; drag it anywhere.
-- Click while it types: the whole text at once. Only the "x" closes it (a landing quip slides away
-- on its own).
-- Its mood (tipsy, sleepy, grumpy, excited) comes from what it says and shows in how it moves.

-- Model (display ID), cry (sound file ID) and framing per species, from the game's flight mounts:
-- Riding Gryphon 541, Wind Rider 2224, Riding Hippogryph 3837, Riding Bat 3574.
local LOOK = {
	gryphon = { display = 6852, sound = 551348 },
	windrider = { display = 6851, sound = 564754 },
	hippogryph = { display = 1936, sound = 551945, facing = -0.6 },
	bat = { display = 1566, sound = 548733, zoom = 0.8 },
}
local RARE_LOOK = {
	kevin = { display = 397, sound = 548556, zoom = 0.75 },    -- a whelp, standing in for a proto-drake
	steve = { display = 8471, sound = 548556, zoom = 0.75 },   -- a faerie dragon, standing in for a dragonhawk
	chicken = { display = 304, sound = 546069, zoom = 0.7 },
	murky = { display = 617, sound = 555997, zoom = 0.75 },
	lurk = { display = 1566, sound = 548733, zoom = 0.8 },
}
-- Animations that read as talking; the first one the model has is used.
local TALK_ANIMS = { 60, 64, 25, 0 }   -- EmoteTalk, EmoteExclamation, ReadyUnarmed, Stand
local EXCLAIM_ANIMS = { 64, 74, 16 }   -- "!": EmoteExclamation, EmoteRoar, AttackUnarmed (a peck)
local ASK_ANIMS = { 65, 60, 0 }        -- "?": EmoteQuestion, EmoteTalk
local ROAR_ANIMS = { 74, 64, 16 }      -- a grumpy start
local TYPE_SPEED = 40                  -- characters per second

local MEDIA = "Interface\\AddOns\\AzerothAlmanac\\Media\\"
local RING = 140                       -- the ring's size (px; 2026-10-13: bigger beside the plate, was 104)
local WINDOW = 0.68                    -- the window's radius, of the ring's (tools/build_wings_ring.py)
local PLATE_X = RING / 2               -- where the plate starts: behind the ring's centre (Shannon kept this)
local PLATE_W, TEXT_W = 430, 326       -- the plate out to the right; the text column on it
local PLATE_TOP = 20                   -- the plate starts this far below the ring's top
local NAME_H = 28                      -- the name bar
local TEXT_X = RING / 2 + 16           -- the text column, from the plate's left (under the ring's edge)
local TRACK_X, TRACK_W = RING / 2 - 4, PLATE_W - RING / 2 - 20 -- the flight's progress line
local SLIDE, FADE = 0.38, 0.3          -- seconds: the plate sliding out; sliding away
-- (2026-10-13, Shannon: 1, 3, 4, 5, 7, 8 of the "quieter, prettier" list)
local GLINT_EVERY, GLINT_TIME = 10, 1.2 -- a glint runs round the gold ring
local GOODBYE = { 67, 66, 113, 0 }     -- landing: EmoteWave, EmoteBow, EmoteSalute
local FEATHER = { gryphon = { 1, 0.95, 0.85 }, windrider = { 0.86, 0.7, 0.5 }, hippogryph = { 0.8, 0.78, 1 } } -- (no bat: fur)

local panel

local function FirstAnim(model, list)
	for _, anim in ipairs(list) do
		if not model.HasAnimation or model:HasAnimation(anim) then return anim end
	end
	return 0
end
local function Anim(f, list) if f.model.SetAnimation then f.model:SetAnimation(FirstAnim(f.model, list)) end end

local function Ease(k) return 1 - (1 - k) ^ 3 end
local function Smooth(k) if k <= 0 then return 0 elseif k >= 1 then return 1 end return k * k * (3 - 2 * k) end

local function PlacePanel()
	panel:ClearAllPoints()
	local p = db.panelPoint
	if p then panel:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else panel:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 190) end
end

local TITLE_FONT = "Fonts\\MORPHEUS.TTF"   -- the quest-title font
local BODY_FONT = "Fonts\\FRIZQT__.TTF"

local function Gradient(tex, left, right)
	tex:SetTexture("Interface\\Buttons\\WHITE8X8")
	if CreateColor and pcall(tex.SetGradient, tex, "HORIZONTAL", CreateColor(unpack(left)), CreateColor(unpack(right))) then return end
	tex:SetColorTexture(left[1], left[2], left[3], (left[4] + right[4]) / 2)
end

local function Shadowed(fs, font, size, r, g, b)
	fs:SetFont(font, size, "")
	fs:SetTextColor(r, g, b)
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetShadowOffset(1, -1)
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
end

-- (2026-10-13) typing by visible letters: a colour code ("|cffffd100", "|r") goes with the letter
-- after it, never half typed. Returns the byte ends of each visible letter.
local function Letters(text)
	local ends, i, n = {}, 1, #text
	while i <= n do
		local c2 = text:sub(i, i + 1)
		if c2 == "|c" then i = i + 10
		elseif c2 == "|r" then
			i = i + 2
			if #ends > 0 then ends[#ends] = i - 1 end
		else
			ends[#ends + 1] = i
			i = i + 1
		end
	end
	return ends
end
WW.Letters = Letters

-- (#10) the creature's mood, from what it says
local MOODS = {
	{ "tipsy", { "ale", "ales", "brew", "drunk", "beer", "mead", "keg", "tavern", "hiccup", "grog", "pint", "tipsy" } },
	{ "sleepy", { "sleep", "asleep", "nap", "naps", "yawn", "tired", "snore", "snores", "dozing", "drowsy", "dream", "dreams" } },
	{ "grumpy", { "grumble", "grumbles", "hate", "hates", "ugh", "cranky", "complain", "complains", "mutter", "mutters", "annoyed", "grudge", "grumpy", "scowl" } },
}
function WW.Mood(text)
	local low = " " .. (text or ""):lower():gsub("[^%a%s']", " ") .. " "
	for _, m in ipairs(MOODS) do
		for _, word in ipairs(m[2]) do
			if low:find(" " .. word .. " ", 1, true) then return m[1] end
		end
	end
	local _, bangs = (text or ""):gsub("!", "")
	if bangs >= 2 then return "excited" end
	return nil
end

-- (#3) a soft chirp as each word starts (quiet, throttled)
local CHIRP = { "U_CHAT_SCROLL_BUTTON", "IG_MAINMENU_OPTION_CHECKBOX_ON" }
local lastChirp = 0
local function Chirp()
	if not (db.sound and db.typeSound ~= false) then return end
	local now = GetTime()
	if now - lastChirp < 0.12 then return end
	lastChirp = now
	for _, name in ipairs(CHIRP) do
		local kit = SOUNDKIT and SOUNDKIT[name]
		if kit then pcall(PlaySound, kit, "SFX") return end
	end
end

local function BuildPanel()
	local f = CreateFrame("Frame", "AzerothAlmanacWingsPanel", UIParent)
	f:SetSize(PLATE_X + PLATE_W, RING)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self.dragged = true self:StartMoving() end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		db.panelPoint = { point, relPoint, x, y }
	end)
	-- left click while it types: the whole text at once; dragging moves it; only the "x" closes it
	f:SetScript("OnMouseDown", function(self) self.dragged = false end)
	f:SetScript("OnMouseUp", function(self, button)
		-- (2026-10-13, Shannon: only the "x" closes it) a click while it types shows all the words
		if button ~= "LeftButton" or self.dragged then return end
		if self.typing then self:FinishTyping() end
	end)

	-- the plate: slides out to the right from behind the ring (a clipping frame that widens)
	f.clip = CreateFrame("Frame", nil, f)
	f.clip:SetPoint("TOPLEFT", PLATE_X, -PLATE_TOP)
	f.clip:SetSize(PLATE_W, 100)
	if f.clip.SetClipsChildren then f.clip:SetClipsChildren(true) end
	local plate = CreateFrame("Frame", nil, f.clip)
	plate:SetPoint("TOPLEFT")
	plate:SetSize(PLATE_W, 100)
	f.plate = plate
	-- see-through backing that fades out to the right (as before), gold hairlines top and bottom
	plate.bg = plate:CreateTexture(nil, "BACKGROUND")
	plate.bg:SetPoint("TOPLEFT", 0, -NAME_H)
	plate.bg:SetPoint("BOTTOMRIGHT")
	Gradient(plate.bg, { 0, 0, 0, 0.72 }, { 0, 0, 0, 0.18 })
	-- (#4) the name bar: a darker band with a gold rule under it, like a nameplate
	plate.nameBg = plate:CreateTexture(nil, "BACKGROUND", nil, 1)
	plate.nameBg:SetPoint("TOPLEFT")
	plate.nameBg:SetPoint("TOPRIGHT")
	plate.nameBg:SetHeight(NAME_H)
	Gradient(plate.nameBg, { 0.06, 0.04, 0.02, 0.9 }, { 0.06, 0.04, 0.02, 0.25 })
	for _, spec in ipairs({ { "TOP", 0, 0.9 }, { "NAME", -NAME_H, 1 }, { "BOTTOM", 0, 0.7 } }) do
		local line = plate:CreateTexture(nil, "BORDER")
		line:SetHeight(spec[1] == "NAME" and 2 or 1)
		if spec[1] == "NAME" then
			line:SetPoint("TOPLEFT", 0, spec[2]) line:SetPoint("TOPRIGHT", 0, spec[2])
		else
			line:SetPoint(spec[1] .. "LEFT") line:SetPoint(spec[1] .. "RIGHT")
		end
		Gradient(line, { 0.9, 0.72, 0.32, spec[3] }, { 0.9, 0.72, 0.32, 0 })
	end

	f.name = plate:CreateFontString(nil, "OVERLAY")
	Shadowed(f.name, TITLE_FONT, 19, 1, 0.82, 0)
	f.name:SetPoint("LEFT", plate, "TOPLEFT", TEXT_X, -NAME_H / 2 - 1)
	f.name:SetJustifyV("MIDDLE")
	f.name:SetWidth(PLATE_W - TEXT_X - 26) -- (clear of the close button)
	f.name:SetWordWrap(false)
	-- the title just under the name bar, then the words
	f.title = plate:CreateFontString(nil, "OVERLAY")
	Shadowed(f.title, BODY_FONT, 11, 0.85, 0.75, 0.55)
	f.title:SetPoint("TOPLEFT", plate, "TOPLEFT", TEXT_X, -NAME_H - 5)
	f.title:SetWidth(TEXT_W)
	f.title:SetWordWrap(false)
	f.text = plate:CreateFontString(nil, "OVERLAY")
	Shadowed(f.text, BODY_FONT, 13, 1, 1, 1)
	f.text:SetSpacing(3)
	f.text:SetWidth(TEXT_W)
	f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -5)
	-- (#5 of the second list) the flight's progress: a gold hairline under the name bar that fills as
	-- you fly; hover it for the route and the time left (it passes drags on to the panel)
	f.track = plate:CreateTexture(nil, "BORDER", nil, 2)
	f.track:SetPoint("TOPLEFT", plate, "TOPLEFT", TRACK_X, -NAME_H - 2)
	f.track:SetSize(TRACK_W, 2)
	f.track:SetColorTexture(1, 0.85, 0.4, 0.12)
	f.progress = plate:CreateTexture(nil, "BORDER", nil, 3)
	f.progress:SetPoint("TOPLEFT", f.track, "TOPLEFT")
	f.progress:SetSize(1, 2)
	Gradient(f.progress, { 1, 0.78, 0.3, 0.95 }, { 1, 0.92, 0.6, 0.95 })
	f.route = CreateFrame("Frame", nil, plate)
	f.route:SetPoint("TOPLEFT", f.track, "TOPLEFT", 0, 4)
	f.route:SetPoint("BOTTOMRIGHT", f.track, "BOTTOMRIGHT", 0, -4)
	f.route:EnableMouse(true)
	f.route:RegisterForDrag("LeftButton")
	f.route:SetScript("OnDragStart", function() f:GetScript("OnDragStart")(f) end)
	f.route:SetScript("OnDragStop", function() f:GetScript("OnDragStop")(f) end)
	f.route:SetScript("OnEnter", function(self)
		if not f.flight then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(("%s  to  %s"):format(f.flight.from or "?", f.flight.to or "?"), 1, 0.82, 0)
		if f.flight.planned then
			local left = math.max(0, f.flight.planned - (GetTime() - f.flight.at))
			GameTooltip:AddLine(("%d:%02d left"):format(math.floor(left / 60), math.floor(left % 60)), 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	f.route:SetScript("OnLeave", GameTooltip_Hide)

	-- (#5, Shannon's pick) the Fun Fact on its own card: warm dark brown, a gold border, a small gold
	-- medallion with "!" at its top left
	f.card = CreateFrame("Frame", nil, plate)
	f.card:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -9)
	f.card:SetSize(TEXT_W, 40)
	f.card.bg = f.card:CreateTexture(nil, "BACKGROUND")
	f.card.bg:SetAllPoints()
	f.card.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
	if not (CreateColor and pcall(f.card.bg.SetGradient, f.card.bg, "VERTICAL", CreateColor(0.15, 0.105, 0.05, 0.72), CreateColor(0.235, 0.17, 0.085, 0.8))) then
		f.card.bg:SetColorTexture(0.2, 0.14, 0.07, 0.76)
	end
	for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local t = f.card:CreateTexture(nil, "BORDER")
		t:SetColorTexture(0.84, 0.65, 0.28, 0.7)
		t:SetPoint(e[1]) t:SetPoint(e[2])
		if e[3] then t:SetHeight(1) else t:SetWidth(1) end
	end
	f.card.icon = f.card:CreateTexture(nil, "ARTWORK")
	f.card.icon:SetTexture(MEDIA .. "WW_Badge")
	f.card.icon:SetSize(20, 20)
	f.card.icon:SetPoint("TOPLEFT", 7, -6)
	f.card.bang = f.card:CreateFontString(nil, "OVERLAY")
	f.card.bang:SetFont(TITLE_FONT, 12, "OUTLINE")
	f.card.bang:SetTextColor(1, 0.85, 0.35)
	f.card.bang:SetPoint("CENTER", f.card.icon, "CENTER", 0, 1)
	f.card.bang:SetText("!")
	f.factHead = f.card:CreateFontString(nil, "OVERLAY")
	Shadowed(f.factHead, TITLE_FONT, 14, 1, 0.82, 0)
	f.factHead:SetPoint("TOPLEFT", f.card, "TOPLEFT", 34, -7)
	f.factHead:SetText("Fun Fact")
	f.fact = f.card:CreateFontString(nil, "OVERLAY")
	Shadowed(f.fact, BODY_FONT, 12, 0.95, 0.9, 0.81)
	f.fact:SetSpacing(3)
	f.fact:SetWidth(TEXT_W - 34 - 10)
	f.fact:SetPoint("TOPLEFT", f.factHead, "BOTTOMLEFT", 0, -3)
	-- a game for the flight (the three games' buttons; one recommended)
	f.gem = GameRow(plate, function() f:Dismiss() end)
	f.gem:SetPoint("BOTTOMRIGHT", plate, "BOTTOMRIGHT", -10, 8)

	-- a small, quiet close button on the name bar
	local close = CreateFrame("Button", nil, plate)
	close:SetSize(18, 18)
	close:SetPoint("RIGHT", plate, "TOPRIGHT", -6, -NAME_H / 2)
	close.x = close:CreateFontString(nil, "OVERLAY")
	close.x:SetFont(BODY_FONT, 15, "OUTLINE")
	close.x:SetPoint("CENTER", 0, 1)
	close.x:SetText("x")
	close.x:SetTextColor(0.8, 0.68, 0.45)
	close:SetAlpha(0.6)
	close:SetScript("OnEnter", function(self) self:SetAlpha(1) self.x:SetTextColor(1, 0.85, 0.4) end)
	close:SetScript("OnLeave", function(self) self:SetAlpha(0.6) self.x:SetTextColor(0.8, 0.68, 0.45) end)
	close:SetScript("OnClick", function() f:Dismiss() end)
	f.close = close
	-- (#6, Shannon's pick) a small "..." beside it: the panel's menu ("Don't show these again" moved here)
	local more = CreateFrame("Button", nil, plate)
	more:SetSize(22, 18)
	more:SetPoint("RIGHT", close, "LEFT", -2, 0)
	more.t = more:CreateFontString(nil, "OVERLAY")
	more.t:SetFont(BODY_FONT, 14, "OUTLINE")
	more.t:SetPoint("CENTER", 0, 3)
	more.t:SetText("...")
	more.t:SetTextColor(0.8, 0.68, 0.45)
	more:SetAlpha(0.6)
	more:SetScript("OnEnter", function(self)
		self:SetAlpha(1) self.t:SetTextColor(1, 0.85, 0.4)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Wings & Whispers")
		GameTooltip:AddLine("Turn these off, typing chirps, panel position.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	more:SetScript("OnLeave", function(self) self:SetAlpha(0.6) self.t:SetTextColor(0.8, 0.68, 0.45) GameTooltip_Hide() end)
	more:SetScript("OnClick", function(self)
		local W = A.Widgets
		if not (W and W.Menu) then return end
		W.Menu(self, {
			{ title = true, text = "Wings & Whispers" },
			{ text = "Don't show these again", run = function()
				db.enabled = false
				f:Dismiss()
				ns.Print("Wings & Whispers is off. Turn it back on in /aa > Wings & Whispers.")
			end },
			{ text = "Soft chirps as the words type out", check = db.typeSound ~= false, run = function() db.typeSound = db.typeSound == false end },
			{ text = "Reset panel position", run = function() WW:ResetPanelPosition() end },
			{ divider = true },
			{ text = "Settings...", run = function() if A.Settings and A.Settings.Open then A.Settings:Open("wings") end end },
		})
	end)
	f.menuButton = more

	-- the portrait: the dark window, the creature, then the gold ring in front (its inner band hides
	-- the model's square corners), all over the plate's left end
	f.portrait = CreateFrame("Frame", nil, f)
	f.portrait:SetSize(RING, RING)
	f.portrait:SetPoint("TOPLEFT")
	f.portrait:SetFrameLevel(f.clip:GetFrameLevel() + 10)
	f.portraitBg = f.portrait:CreateTexture(nil, "BACKGROUND")
	f.portraitBg:SetAllPoints()
	f.portraitBg:SetTexture(MEDIA .. "WW_PortraitBack")
	f.model = CreateFrame("PlayerModel", nil, f.portrait)
	f.model:SetSize(RING * WINDOW, RING * WINDOW)
	f.model:SetPoint("CENTER")
	f.ring = CreateFrame("Frame", nil, f.portrait)
	f.ring:SetAllPoints()
	f.ring:SetFrameLevel(f.model:GetFrameLevel() + 2)
	f.frameArt = f.ring:CreateTexture(nil, "ARTWORK")
	f.frameArt:SetAllPoints()
	f.frameArt:SetTexture(MEDIA .. "WW_PortraitRing")
	f.flush = f.ring:CreateTexture(nil, "OVERLAY") -- (a grumpy flush of red round the ring)
	f.flush:SetPoint("CENTER")
	f.flush:SetSize(RING * 1.25, RING * 1.25)
	f.flush:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
	f.flush:SetBlendMode("ADD")
	f.flush:SetVertexColor(1, 0.25, 0.1)
	f.flush:SetAlpha(0)
	-- (#3) now and then a glint runs round the gold
	f.glint = f.ring:CreateTexture(nil, "OVERLAY", nil, 3)
	f.glint:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
	f.glint:SetBlendMode("ADD")
	f.glint:SetVertexColor(1, 0.95, 0.75)
	f.glint:SetSize(RING * 0.16, RING * 0.16)
	f.glint:SetAlpha(0)
	-- (#4) a feather or two drifting down past the ring as the panel opens
	f.feathers = {}
	for i = 1, 2 do
		local t = f.ring:CreateTexture(nil, "OVERLAY", nil, 4)
		t:SetTexture(MEDIA .. "WW_Feather")
		t:SetSize(22 - i * 3, 22 - i * 3)
		t:Hide()
		f.feathers[i] = t
	end
	-- the ride count in the small gold medallion on the ring
	f.badge = CreateFrame("Frame", nil, f.ring)
	f.badge:SetSize(38, 38)
	f.badge:SetPoint("CENTER", f.portrait, "CENTER", RING * 0.34, -RING * 0.34)
	f.badge:SetFrameLevel(f.ring:GetFrameLevel() + 2)
	f.badge.tex = f.badge:CreateTexture(nil, "ARTWORK")
	f.badge.tex:SetAllPoints()
	f.badge.tex:SetTexture(MEDIA .. "WW_Badge")
	f.count = f.badge:CreateFontString(nil, "OVERLAY")
	f.count:SetFont(TITLE_FONT, 16, "OUTLINE")
	f.count:SetTextColor(1, 0.85, 0.35)
	f.count:SetPoint("CENTER", 0, 1)
	f.badge:EnableMouse(true)
	f.badge:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.tip or "", 1, 0.82, 0)
		GameTooltip:Show()
	end)
	f.badge:SetScript("OnLeave", GameTooltip_Hide)
	-- (#10) mood marks over the ring: rising z's (sleepy), bubbles (tipsy), gold glints (excited)
	f.marks = {}
	for i = 1, 3 do
		local m = f.ring:CreateTexture(nil, "OVERLAY", nil, 2)
		m:SetSize(18, 18)
		m:Hide()
		local z = f.ring:CreateFontString(nil, "OVERLAY")
		z:SetFont(BODY_FONT, 16, "OUTLINE")
		z:SetTextColor(0.85, 0.92, 1)
		z:SetText("z")
		z:Hide()
		f.marks[i] = { tex = m, z = z }
	end

	function f:FinishTyping()
		if not self.typing then return end
		for i, seg in ipairs(self.segments) do
			seg.fs:SetText(seg.text)
			if seg.head then seg.head:Show() end
			self.segIndex = i
		end
		if #self.segments > 1 then self.card:Show() end
		self:DoneTyping()
	end
	function f:DoneTyping()
		self.typing = false
		self.done = true
		self.doneAt = GetTime()
		-- the take-off panel stays until you close it or the flight lands; the landing quip slides away
		self.hideAt = not self.persist and (GetTime() + 4 + self.totalChars / 30) or nil
		Anim(self, { 0 })
	end
	-- (#2) slide away: the plate draws back behind the ring and the whole panel fades
	function f:Dismiss()
		if not self:IsShown() or self.leaving then return end
		self.leaving = GetTime()
		self.typing = false
	end

	f:SetScript("OnUpdate", function(self, elapsed)
		local now = GetTime()
		-- (#2) sliding out (opening) or back in (leaving)
		if self.leaving then
			local k = (now - self.leaving) / FADE
			if k >= 1 then
				self.leaving = nil
				self:Hide()
				self:SetAlpha(1)
				return
			end
			self.clipW = math.max(1, PLATE_W * (1 - Ease(k))) self.clip:SetWidth(self.clipW)
		elseif self.openAt then
			local k = (now - self.openAt) / SLIDE
			if k >= 1 then
				self.openAt = nil
				self.clipW = PLATE_W self.clip:SetWidth(PLATE_W)
				self.portrait:SetAlpha(1)
			else
				self.clipW = math.max(1, PLATE_W * Ease(math.max(0, k))) self.clip:SetWidth(self.clipW)
				self.portrait:SetAlpha(Smooth(k * 2.5))
			end
		end
		-- (the slide-away fade for the whole panel; (#8) the opacity setting for the plate only, so the
		-- ring stays solid and its band always hides the model's square corners. 2026-10-13, Shannon:
		-- the settling dim is gone, it let the plate and the model's corners show through the ring)
		local fade = self.leaving and (1 - Smooth((now - self.leaving) / FADE)) or 1
		self:SetAlpha(math.max(0, fade))
		self.clip:SetAlpha((db.panelAlpha or 100) / 100)
		-- (#3) the glint: round the ring once every GLINT_EVERY seconds
		local gk = ((now - (self.shownAt or now)) % GLINT_EVERY) / GLINT_TIME
		if gk < 1 and now - (self.shownAt or now) > 1.5 then
			local ang = math.pi * 0.75 - gk * math.pi * 2
			self.glint:ClearAllPoints()
			self.glint:SetPoint("CENTER", self.portrait, "CENTER", math.cos(ang) * RING * 0.445, math.sin(ang) * RING * 0.445)
			self.glint:SetAlpha(0.9 * math.sin(gk * math.pi))
		else
			self.glint:SetAlpha(0)
		end
		-- (#4) the feathers drifting down
		for i, t in ipairs(self.feathers) do
			if t:IsShown() then
				local fk = (now - (self.shownAt or now) - (i - 1) * 0.45) / 3.2
				if fk >= 1 then t:Hide()
				elseif fk >= 0 then
					local x = RING * (0.12 + 0.18 * i) + math.sin(fk * 7 + i) * 10
					local y = RING * 0.42 - fk * RING * 1.15
					t:ClearAllPoints()
					t:SetPoint("CENTER", self.portrait, "CENTER", x - RING * 0.3, y)
					if t.SetRotation then t:SetRotation(math.sin(fk * 6 + i) * 0.6 + 0.3) end
					t:SetAlpha(math.min(1, fk * 6) * (1 - Smooth((fk - 0.6) / 0.4)) * 0.9)
				else
					t:SetAlpha(0)
				end
			end
		end
		-- (#5) the flight's progress
		if self.flight and self.flight.planned and self.flight.planned > 0 then
			local pk = math.min(1, (GetTime() - self.flight.at) / self.flight.planned)
			self.progress:SetWidth(math.max(1, TRACK_W * pk))
		end
		-- (#9) a livelier creature: sways while it talks, breathes after; a tilt on "?", a dip on "."
		local mood = self.mood
		local t = now - (self.shownAt or now)
		local sway = (mood == "tipsy" and 0.22) or (mood == "sleepy" and 0.05) or 0.08
		local speed = (mood == "sleepy" and 0.6) or (mood == "excited" and 2.2) or 1.3
		local facing = (self.facing or -0.45) + math.sin(t * speed) * sway
		if self.tiltAt then
			local tk = now - self.tiltAt
			if tk > 0.8 then self.tiltAt = nil else facing = facing + 0.35 * math.exp(-tk * 5) * math.sin(tk * 12) end
		end
		if self.model.SetFacing then self.model:SetFacing(facing) end
		if self.model.SetPosition then
			local bob = self.typing and math.sin(t * ((mood == "excited") and 9 or 6)) * 0.015 or math.sin(t * 1.6) * 0.008
			if self.dipAt then
				local dk = now - self.dipAt
				if dk > 0.5 then self.dipAt = nil else bob = bob - 0.03 * math.sin(math.min(1, dk / 0.5) * math.pi) end
			end
			self.model:SetPosition(0, 0, bob)
		end
		-- (#10) mood marks and the grumpy flush
		if self.flushAt then
			local fk = (now - self.flushAt) / 1.4
			if fk >= 1 then self.flushAt = nil self.flush:SetAlpha(0) else self.flush:SetAlpha(0.55 * math.sin(fk * math.pi)) end
		end
		for i, m in ipairs(self.marks) do
			local ph = (t * ((mood == "sleepy") and 0.45 or 0.7) + i / 3) % 1
			local a = math.sin(math.pi * ph)
			local x, y = RING * 0.18 + ph * RING * 0.22 + math.sin(ph * 6 + i) * 3, RING * 0.25 + ph * RING * 0.35
			if mood == "sleepy" then
				m.z:ClearAllPoints() m.z:SetPoint("CENTER", self.portrait, "CENTER", x, y)
				m.z:SetScale(0.7 + ph * 0.7) m.z:SetAlpha(a) m.z:Show() m.tex:Hide()
			elseif mood == "tipsy" or mood == "excited" then
				m.tex:ClearAllPoints() m.tex:SetPoint("CENTER", self.portrait, "CENTER", x, y)
				m.tex:SetAlpha(a * 0.8) m.tex:Show() m.z:Hide()
			else
				m.tex:Hide() m.z:Hide()
			end
		end
		if self.openAt then return end -- (the words wait for the plate)
		-- typing (body, then the fun fact), "talking"
		if self.typing then
			local seg = self.segments[self.segIndex]
			seg.ends = seg.ends or Letters(seg.text)
			local count = #seg.ends
			self.typed = math.min(count, self.typed + elapsed * TYPE_SPEED)
			local k = math.floor(self.typed)
			local n = k > 0 and seg.ends[k] or 0
			if k ~= self.lastChar then
				seg.fs:SetText(seg.text:sub(1, n))
				local ch = seg.text:sub(n, n)
				local prev = k > 1 and seg.text:sub(seg.ends[k - 1], seg.ends[k - 1]) or " "
				if ch:match("%S") and prev:match("%s") then Chirp() end
				if ch == "!" then Anim(self, EXCLAIM_ANIMS) self.pauseUntil = now + 0.6
				elseif ch == "?" then Anim(self, ASK_ANIMS) self.tiltAt = now self.pauseUntil = now + 0.6
				elseif ch == "." and seg.text:sub(n + 1, n + 1) ~= "." then self.dipAt = now end
				self.lastChar = k
			end
			if self.pauseUntil and now > self.pauseUntil then
				self.pauseUntil = nil
				Anim(self, TALK_ANIMS)
			end
			if k >= count then
				if self.segIndex < #self.segments then
					self.segIndex, self.typed, self.lastChar = self.segIndex + 1, 0, -1
					if self.segments[self.segIndex].head then self.segments[self.segIndex].head:Show() self.card:Show() end
				else
					self:DoneTyping()
				end
			end
		elseif self.hideAt and now > self.hideAt then
			-- (#7) a landing: a little wave or bow first, then it slides away
			self.hideAt = nil
			Anim(self, GOODBYE)
			self.byeAt = now + 1.3
		elseif self.byeAt and now > self.byeAt then
			self.byeAt = nil
			self:Dismiss()
		end
	end)
	f:Hide()
	panel = f
	PlacePanel()
	return f
end

-- info = { creature, kind, species, count, body, fact, gem = flight seconds or true, landing }
function WW.ShowPanel(info)
	local f = panel or BuildPanel()
	local creature = info.creature
	-- the ring's gold: warmer for the Horde, cooler for the Alliance, lilac for a rare guest
	local faction = UnitFactionGroup("player")
	if info.kind == "rare" then f.frameArt:SetVertexColor(0.88, 0.8, 1)
	elseif faction == "Horde" then f.frameArt:SetVertexColor(1, 0.86, 0.78)
	else f.frameArt:SetVertexColor(1, 1, 1) end

	-- the creature's head and shoulders, turned a little toward the text
	local look = (info.kind == "rare" and RARE_LOOK[creature[1]]) or LOOK[info.species] or LOOK.gryphon
	if f.model.ClearModel then f.model:ClearModel() end
	if f.model.SetDisplayInfo then pcall(f.model.SetDisplayInfo, f.model, look.display) end
	if f.model.SetPortraitZoom then f.model:SetPortraitZoom(look.zoom or 0.9) end
	if f.model.SetCamDistanceScale then f.model:SetCamDistanceScale(1) end
	f.facing = look.facing or -0.45
	if f.model.SetFacing then f.model:SetFacing(f.facing) end

	f.name:SetText(creature[2])
	f.title:SetText(info.landing and "" or ("\"%s\""):format(creature[3]))
	f.count:SetText(tostring(info.count or 1))
	f.badge.tip = (info.count or 1) > 1 and ("Flight #%d together"):format(info.count) or "Your first flight together"

	-- measure the full texts first, so the plate is the right height before typing starts
	local body, fact = info.body or "", info.fact
	f.text:SetText(body)
	local hasTitle = not info.landing
	f.text:ClearAllPoints()
	if hasTitle then f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -5)
	else f.text:SetPoint("TOPLEFT", f.plate, "TOPLEFT", TEXT_X, -NAME_H - 8) end
	local height = NAME_H + 8 + (hasTitle and (13 + 5) or 0) + f.text:GetStringHeight()
	if fact then
		f.fact:SetText(fact)
		local cardH = 7 + 16 + 3 + f.fact:GetStringHeight() + 9
		f.card:SetHeight(cardH)
		height = height + 9 + cardH
	end
	-- (2026-10-13, Shannon: "it wasn't expanded at the beginning to show the Fun Fact") the card and
	-- its heading are there from the start; only its words wait their turn
	f.card:SetShown(fact ~= nil)
	local showGem = info.gem ~= nil and not info.landing
	-- the bottom: the games
	height = height + (showGem and (10 + 34 + 8) or 14)
	height = math.max(height, RING - PLATE_TOP + 6)
	f.plate:SetHeight(height)
	f.clip:SetHeight(height)
	f:SetHeight(math.max(RING, PLATE_TOP + height))

	f.segments = { { fs = f.text, text = body } }
	if fact then f.segments[2] = { fs = f.fact, text = fact, head = f.factHead } end
	f.totalChars = #body + (fact and #fact or 0)
	f.text:SetText("")
	f.fact:SetText("")
	f.factHead:Show()
	f.segIndex, f.typed, f.lastChar, f.typing, f.done, f.hideAt, f.pauseUntil = 1, 0, -1, true, false, nil, nil
	f.tiltAt, f.dipAt, f.leaving, f.byeAt, f.doneAt, f.dim = nil, nil, nil, nil, nil, 1
	-- (#5) the flight's progress line (take-off only, when the flight's length is known)
	f.flight = (not info.landing and info.flight and info.flight.planned) and { from = info.flight.from, to = info.flight.to, planned = info.flight.planned, at = GetTime() } or nil
	f.track:SetShown(f.flight ~= nil)
	f.progress:SetShown(f.flight ~= nil)
	f.progress:SetWidth(1)
	f.route:SetShown(f.flight ~= nil)
	-- (#4) feathers in the creature's colours (none for a bat)
	local fc = info.kind ~= "rare" and FEATHER[info.species or ""]
	for _, t in ipairs(f.feathers) do
		t:SetShown(fc and not info.landing and true or false)
		if fc then t:SetVertexColor(fc[1], fc[2], fc[3]) end
		t:SetAlpha(0)
	end
	-- (#8) the size setting
	f:SetScale((db.panelScale or 100) / 100)
	f.persist = not info.landing
	-- (#10) its mood, from its words
	f.mood = WW.Mood(body .. " " .. (fact or ""))
	for _, m in ipairs(f.marks) do
		-- (2026-10-13, Shannon's screenshot: dark squares) FX_Bubbles is painted on black, so it's
		-- drawn added (like the Journey's bubbles), never blended
		if f.mood == "tipsy" then m.tex:SetTexture(MEDIA .. "FX_Bubbles") m.tex:SetVertexColor(1, 0.9, 0.6) m.tex:SetBlendMode("ADD")
		elseif f.mood == "excited" then m.tex:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64") m.tex:SetVertexColor(1, 0.85, 0.4) m.tex:SetBlendMode("ADD") end
	end
	Anim(f, f.mood == "grumpy" and ROAR_ANIMS or TALK_ANIMS)
	f.flushAt = f.mood == "grumpy" and GetTime() or nil
	if f.mood ~= "grumpy" then f.flush:SetAlpha(0) end

	f.gem:SetShown(showGem)
	if showGem then f.gem:Offer() end
	-- (#2) the ring fades in and the plate slides out to the right
	f:SetAlpha(1)
	f.portrait:SetAlpha(0)
	f.clipW = 1 f.clip:SetWidth(1)
	f.openAt, f.shownAt = GetTime(), GetTime()
	f:Show()
	if db.sound and look.sound and PlaySoundFile then pcall(PlaySoundFile, look.sound, "SFX") end
end

-- (#8) the size and opacity settings, applied at once to a panel that's showing
function WW:ApplyLook()
	if panel then panel:SetScale((db.panelScale or 100) / 100) end
end

function WW:ResetPanelPosition()
	db.panelPoint = nil
	if panel then PlacePanel() end
end

---------------------------------------------------------------------------
-- Take-off and landing
---------------------------------------------------------------------------

local function OnTakeoff(flight)
	local species = WW.Species(UnitFactionGroup("player"), flight.mapID)
	local creature, kind = WW.Pick(species, flight.from)
	if not creature then return end
	local key = creature[1]
	local rides = Rides(key)
	rides[key] = (rides[key] or 0) + 1
	db.totals[key] = (db.totals[key] or 0) + 1
	local count = rides[key]
	current = { creature = creature, kind = kind, species = species, count = count }
	local name, title = creature[2], creature[3]
	-- (#5, 2026-10-13) the destination in gold where a line names it
	local fill = { n = count, to = flight.to and ("|cffffd100" .. flight.to .. "|r") or "?" }

	if db.enabled then
		local body, fact
		if count == 1 then
			body = Say(creature[4], fill)
			local f = Pick(creature[5] or {})
			fact = f and Say(f, fill)
		else
			body = Say(Pick(creature[6]) or ("%s again. Ride #{n}."):format(name), fill)
		end
		local useGem = db.gemPrompt and ns.GemMatch and not (flight.planned and flight.planned < GEM_PROMPT_MIN)
		if db.panel and (count == 1 or db.panelRepeats) then
			WW.ShowPanel({ creature = creature, kind = kind, species = species, count = count, body = body, fact = fact,
				gem = useGem and (flight.planned or true) or nil, flight = flight })
			useGem = false -- the panel has its own Gem Match button
		else
			if count == 1 then
				local word = SPECIES_WORD[kind] or SPECIES_WORD[species] or "ride"
				local intro = kind == "rare" and "Surprise! Today you're flying with" or ("Your %s today is"):format(word)
				Out(("%s |cffffd100%s|r, \"%s\". %s"):format(intro, name, title, body))
				if fact then Out("|cffaaaaaaFun fact:|r " .. fact) end
			else
				Out(body)
			end
		end
		if db.center and RaidNotice_AddMessage and RaidWarningFrame then
			RaidNotice_AddMessage(RaidWarningFrame, ("%s, \"%s\"%s"):format(name, title, count > 1 and (" (ride #%d)"):format(count) or ""),
				{ r = 0.4, g = 0.8, b = 1 })
		end
		if db.party and IsInGroup() and not IsInRaid() then
			pcall(SendChatMessage, ("My ride to %s: %s, \"%s\"%s"):format(flight.to or "?", name, title,
				count > 1 and (" (ride #%d together)"):format(count) or " (first time!)"), "PARTY")
		end
		if useGem then ShowGemPrompt(flight) end
	else
		ShowGemPrompt(flight)
	end
end

local function OnLand(flight, seconds)
	if prompt then prompt:Hide() end
	if panel then panel:Hide() end -- the take-off panel closes on landing (the quip may reopen it)
	local ride = current
	current = nil
	if not (db.enabled and db.landing and ride) then return end
	local fill = { n = ride.count, time = Clock(seconds), to = flight.to and ("|cffffd100" .. flight.to .. "|r") or "?" }
	local line = Pick(ride.creature[7])
	if not line then return end
	if db.panel and (ride.count == 1 or db.panelRepeats) then
		WW.ShowPanel({ creature = ride.creature, kind = ride.kind, species = ride.species, count = ride.count, body = Say(line, fill), landing = true })
	else
		Out(Say(line, fill))
	end
end

---------------------------------------------------------------------------
-- Settings page helpers and module API
---------------------------------------------------------------------------

-- The creature this character has flown with most: name, count.
function WW:Favorite()
	local best, bestCount
	for key, n in pairs(db.rides[CharKey()] or {}) do
		if not bestCount or n > bestCount then best, bestCount = key, n end
	end
	if not best then return end
	for _, list in pairs(CREW) do
		for _, c in ipairs(list) do
			if c[1] == best then return c[2], bestCount end
		end
	end
end

function WW:CrewCount()
	local n = 0
	for _, list in pairs(CREW) do n = n + #list end
	return n
end

function WW:ResetRides()
	wipe(db.rides)
	wipe(db.totals)
end

-- /aa wings: a sample take-off, to see the words without flying.
function WW:Sample()
	local species = WW.Species(UnitFactionGroup("player"), C_Map.GetBestMapForUnit("player"))
	local list = CREW[species] or {}
	local c = list[math.random(math.max(1, #list))]
	if not c then return end
	local fact = Pick(c[5])
	if db.panel then
		WW.ShowPanel({ creature = c, kind = species, species = species, count = 1, body = Say(c[4]), fact = fact and Say(fact), gem = db.gemPrompt and 135 or nil })
		return
	end
	Out(("Your %s today is |cffffd100%s|r, \"%s\". %s"):format(SPECIES_WORD[species], c[2], c[3], Say(c[4])))
	if fact then Out("|cffaaaaaaFun fact:|r " .. Say(fact)) end
end

function WW:OnInitialize(saved)
	db = saved.wings
	db.rides = db.rides or {}
	db.totals = db.totals or {}
end

function WW:OnLogin()
	if ns.Travel and ns.Travel.OnFlight then
		ns.Travel:OnFlight(function(event, flight, seconds)
			if event == "takeoff" then OnTakeoff(flight) else OnLand(flight, seconds) end
		end)
	end
end
