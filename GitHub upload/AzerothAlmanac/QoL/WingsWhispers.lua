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
local GEM_PROMPT_MIN = 45    -- seconds: only offer Gem Match on flights at least this long
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

local HEADER = "|cff66ccffWings & Whispers:|r "
local function Out(text)
	DEFAULT_CHAT_FRAME:AddMessage(HEADER .. text)
end

local function Rides(key)
	local char = CharKey()
	db.rides[char] = db.rides[char] or {}
	return db.rides[char], char
end

---------------------------------------------------------------------------
-- Gem Match prompt
---------------------------------------------------------------------------

local function BuildPrompt()
	local f = CreateFrame("Button", "AzerothAlmanacWingsGemPrompt", UIParent, "BackdropTemplate")
	f:SetSize(250, 34)
	f:SetPoint("TOP", UIParent, "TOP", 0, -200)
	f:SetFrameStrata("DIALOG")
	f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	f:SetBackdropBorderColor(1, 0.82, 0)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(24, 24)
	f.icon:SetPoint("LEFT", 6, 0)
	f.icon:SetTexture("Interface\\Icons\\INV_Misc_Gem_Ruby_02")
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.text:SetPoint("LEFT", f.icon, "RIGHT", 8, 0)
	f.text:SetPoint("RIGHT", -24, 0)
	f.text:SetJustifyH("LEFT")
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetSize(20, 20)
	close:SetPoint("RIGHT", -3, 0)
	close:SetScript("OnClick", function() f:Hide() end)
	f:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	f:SetScript("OnClick", function(self)
		self:Hide()
		if ns.GemMatch then ns.GemMatch:Open() end
	end)
	f:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Gem Match")
		GameTooltip:AddLine("A match-three game with Classic gems, to pass the flight. It pauses by itself in combat.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", GameTooltip_Hide)
	f:Hide()
	return f
end

local function ShowGemPrompt(flight)
	if not db.gemPrompt or not ns.GemMatch then return end
	if flight.planned and flight.planned < GEM_PROMPT_MIN then return end
	prompt = prompt or BuildPrompt()
	prompt.text:SetText(flight.planned and ("Play Gem Match? (%s flight)"):format(Clock(flight.planned)) or "Play Gem Match while you fly?")
	prompt:Show()
	prompt.token = (prompt.token or 0) + 1
	local token = prompt.token
	C_Timer.After(GEM_PROMPT_SHOW, function() if prompt.token == token then prompt:Hide() end end)
end

---------------------------------------------------------------------------
-- The talking portrait panel
---------------------------------------------------------------------------
-- Built from the game's own Talking Head art (the story-moment pop-up): faction portrait
-- frame, text background, a live 3D model of the creature that "talks" while the text types
-- out, and its cry. Bottom center by default; drag it anywhere.

-- Model (display ID) and cry (sound file ID) per species, from the game's flight mounts:
-- Riding Gryphon 541, Wind Rider 2224, Riding Hippogryph 3837, Riding Bat 3574.
local LOOK = {
	gryphon = { display = 6852, sound = 551348 },
	windrider = { display = 6851, sound = 564754 },
	hippogryph = { display = 1936, sound = 551945 },
	bat = { display = 1566, sound = 548733 },
}
local RARE_LOOK = {
	kevin = { display = 397, sound = 548556 },    -- a whelp, standing in for a proto-drake
	steve = { display = 8471, sound = 548556 },   -- a faerie dragon, standing in for a dragonhawk
	chicken = { display = 304, sound = 546069 },
	murky = { display = 617, sound = 555997 },
	lurk = { display = 1566, sound = 548733 },
}
-- Animations that read as talking; the first one the model has is used.
local TALK_ANIMS = { 60, 64, 25, 0 }   -- EmoteTalk, EmoteExclamation, ReadyUnarmed, Stand
local PUNCT_ANIMS = { 16, 74, 64 }     -- AttackUnarmed (a peck), EmoteRoar, EmoteExclamation
local TYPE_SPEED = 40                  -- characters per second

local panel

local function HasAtlas(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function PanelAtlas(texture, atlas, fallback)
	if HasAtlas(atlas) then texture:SetAtlas(atlas) return true end
	if fallback then fallback(texture) end
	return false
end

local function FirstAnim(model, list)
	for _, anim in ipairs(list) do
		if not model.HasAnimation or model:HasAnimation(anim) then return anim end
	end
	return 0
end

local function PlacePanel()
	panel:ClearAllPoints()
	local p = db.panelPoint
	if p then panel:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else panel:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 190) end
end

local TITLE_FONT = "Fonts\\MORPHEUS.TTF"   -- the quest-title font
local BODY_FONT = "Fonts\\FRIZQT__.TTF"
local PANEL_W, PORTRAIT, TEXT_W = 560, 104, 400

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

local function BuildPanel()
	local f = CreateFrame("Frame", "AzerothAlmanacWingsPanel", UIParent)
	f:SetSize(PANEL_W, 140)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		db.panelPoint = { point, relPoint, x, y }
	end)
	-- right-click to dismiss (left-drag moves it)
	f:SetScript("OnMouseUp", function(self, button) if button == "RightButton" then self:Hide() end end)

	-- Dark, see-through backing that fades out to the right (like the quest dialog), with a
	-- thin gold line along the top and bottom.
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	Gradient(f.bg, { 0, 0, 0, 0.82 }, { 0, 0, 0, 0.35 })
	for _, point in ipairs({ "TOP", "BOTTOM" }) do
		local line = f:CreateTexture(nil, "BORDER")
		line:SetPoint(point .. "LEFT")
		line:SetPoint(point .. "RIGHT")
		line:SetHeight(1)
		Gradient(line, { 0.85, 0.68, 0.3, 0.9 }, { 0.85, 0.68, 0.3, 0 })
	end

	-- portrait: dark backing, the 3D creature, then the faction frame on top
	f.portrait = CreateFrame("Frame", nil, f)
	f.portrait:SetSize(PORTRAIT, PORTRAIT)
	f.portrait:SetPoint("TOPLEFT", 12, -12)
	f.portraitBg = f.portrait:CreateTexture(nil, "BACKGROUND")
	f.portraitBg:SetPoint("TOPLEFT", 6, -6)
	f.portraitBg:SetPoint("BOTTOMRIGHT", -6, 6)
	PanelAtlas(f.portraitBg, "TalkingHeads-PortraitBg", function(t) t:SetColorTexture(0.05, 0.05, 0.08, 1) end)
	f.model = CreateFrame("PlayerModel", nil, f.portrait)
	f.model:SetPoint("TOPLEFT", 7, -7)
	f.model:SetPoint("BOTTOMRIGHT", -7, 7)
	f.ring = CreateFrame("Frame", nil, f.portrait)
	f.ring:SetAllPoints()
	f.ring:SetFrameLevel(f.model:GetFrameLevel() + 2)
	f.frameArt = f.ring:CreateTexture(nil, "OVERLAY")
	f.frameArt:SetAllPoints()

	local x = 12 + PORTRAIT + 14
	f.name = f:CreateFontString(nil, "OVERLAY")
	Shadowed(f.name, TITLE_FONT, 22, 1, 0.82, 0)
	f.name:SetPoint("TOPLEFT", x, -14)
	f.name:SetWidth(TEXT_W - 20) -- stays clear of the close button
	f.name:SetWordWrap(false)
	-- the title on its own line under the name
	f.title = f:CreateFontString(nil, "OVERLAY")
	Shadowed(f.title, BODY_FONT, 11, 0.85, 0.75, 0.55)
	f.title:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 1, -3)
	f.title:SetWidth(TEXT_W)
	f.title:SetWordWrap(false)
	f.text = f:CreateFontString(nil, "OVERLAY")
	Shadowed(f.text, BODY_FONT, 14, 1, 1, 1)
	f.text:SetSpacing(3)
	f.text:SetWidth(TEXT_W)
	f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", -1, -8)
	f.factHead = f:CreateFontString(nil, "OVERLAY")
	Shadowed(f.factHead, TITLE_FONT, 16, 1, 0.82, 0)
	f.factHead:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -10)
	f.factHead:SetText("Fun Fact")
	f.fact = f:CreateFontString(nil, "OVERLAY")
	Shadowed(f.fact, BODY_FONT, 13, 0.92, 0.92, 0.92)
	f.fact:SetSpacing(3)
	f.fact:SetWidth(TEXT_W)
	f.fact:SetPoint("TOPLEFT", f.factHead, "BOTTOMLEFT", 0, -4)

	-- "Ride #4" on the bottom row, like the quest dialog's page counter (placed in ShowPanel)
	f.count = f:CreateFontString(nil, "OVERLAY")
	Shadowed(f.count, TITLE_FONT, 14, 1, 0.82, 0)
	f.count:SetJustifyH("RIGHT")
	f.count:SetJustifyV("MIDDLE")

	f.gem = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.gem:SetSize(170, 22)
	f.gem:SetPoint("BOTTOMRIGHT", -12, 10)
	f.gem:SetScript("OnClick", function() f:Hide() if ns.GemMatch then ns.GemMatch:Open() end end)

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetSize(24, 24)
	close:SetPoint("TOPRIGHT", -6, -8)
	close:SetScript("OnClick", function() f:Hide() end)

	-- "Don't show these again": turns Wings & Whispers off (back on in /aa > Wings & Whispers).
	-- Closing the panel without it only hides this one; the landing quip still comes.
	f.optOut = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	f.optOut:SetSize(22, 22)
	f.optOut:SetPoint("BOTTOMLEFT", 12 + PORTRAIT + 10, 8)
	f.optOutText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.optOutText:SetPoint("LEFT", f.optOut, "RIGHT", 2, 0)
	f.optOutText:SetText("Don't show these again")
	f.optOut:SetScript("OnClick", function(self)
		if not self:GetChecked() then return end
		db.enabled = false
		f:Hide()
		ns.Print("Wings & Whispers is off. Turn it back on in /aa > Wings & Whispers.")
	end)

	-- typing (body, then the fun fact), "talking" and fading out
	f:SetScript("OnUpdate", function(self, elapsed)
		if self.typing then
			local seg = self.segments[self.segIndex]
			self.typed = math.min(#seg.text, self.typed + elapsed * TYPE_SPEED)
			local n = math.floor(self.typed)
			if n ~= self.lastChar then
				seg.fs:SetText(seg.text:sub(1, n))
				local ch = seg.text:sub(n, n)
				if (ch == "." or ch == "!" or ch == "?") and self.model.SetAnimation then
					self.model:SetAnimation(FirstAnim(self.model, PUNCT_ANIMS))
					self.pauseUntil = GetTime() + 0.6
				end
				self.lastChar = n
			end
			if self.pauseUntil and GetTime() > self.pauseUntil then
				self.pauseUntil = nil
				if self.model.SetAnimation then self.model:SetAnimation(FirstAnim(self.model, TALK_ANIMS)) end
			end
			if n >= #seg.text then
				if self.segIndex < #self.segments then
					self.segIndex, self.typed, self.lastChar = self.segIndex + 1, 0, -1
					if self.segments[self.segIndex].head then self.segments[self.segIndex].head:Show() end
				else
					self.typing = false
					-- the take-off panel stays until you close it or the flight lands; the landing quip fades
					self.hideAt = not self.persist and (GetTime() + 4 + self.totalChars / 30) or nil
					if self.model.SetAnimation then self.model:SetAnimation(0) end
				end
			end
		elseif self.hideAt and GetTime() > self.hideAt then
			local alpha = self:GetAlpha() - elapsed * 1.5
			if alpha <= 0 then self:Hide() self:SetAlpha(1) self.hideAt = nil else self:SetAlpha(alpha) end
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
	local faction = info.kind == "rare" and "Neutral" or (UnitFactionGroup("player") == "Horde" and "Horde" or "Alliance")
	if not PanelAtlas(f.frameArt, ("TalkingHeads-%s-PortraitFrame"):format(faction)) then f.frameArt:SetTexture(nil) end

	-- the creature's head and shoulders, turned a little toward the text
	local look = (info.kind == "rare" and RARE_LOOK[creature[1]]) or LOOK[info.species] or LOOK.gryphon
	if f.model.ClearModel then f.model:ClearModel() end
	if f.model.SetDisplayInfo then pcall(f.model.SetDisplayInfo, f.model, look.display) end
	if f.model.SetPortraitZoom then f.model:SetPortraitZoom(look.zoom or 0.9) end
	if f.model.SetCamDistanceScale then f.model:SetCamDistanceScale(1) end
	if f.model.SetFacing then f.model:SetFacing(look.facing or -0.45) end
	if f.model.SetAnimation then f.model:SetAnimation(FirstAnim(f.model, TALK_ANIMS)) end

	f.name:SetText(creature[2])
	f.title:SetText(info.landing and "" or ("\"%s\""):format(creature[3]))
	f.count:SetText(info.count > 1 and ("Ride #%d"):format(info.count) or (info.landing and "" or "First flight"))

	-- measure the full texts first, so the panel is the right height before typing starts
	local body, fact = info.body or "", info.fact
	f.text:SetText(body)
	local height = 14 + 24 + 3 + 13 + 8 + f.text:GetStringHeight()
	if fact then
		f.fact:SetText(fact)
		height = height + 10 + 18 + 4 + f.fact:GetStringHeight()
	end
	local showGem = info.gem ~= nil and not info.landing
	-- the bottom row: "Don't show these again", the ride counter and the Gem Match button
	height = math.max(height + 40, PORTRAIT + 24)
	f.optOut:SetChecked(false)
	-- the counter sits left of the Gem Match button, or in the bottom-right corner
	f.count:ClearAllPoints()
	if showGem then f.count:SetPoint("RIGHT", f.gem, "LEFT", -12, 0) else f.count:SetPoint("BOTTOMRIGHT", -16, 14) end
	f:SetHeight(height)

	f.segments = { { fs = f.text, text = body } }
	if fact then f.segments[2] = { fs = f.fact, text = fact, head = f.factHead } end
	f.totalChars = #body + (fact and #fact or 0)
	f.text:SetText("")
	f.fact:SetText("")
	f.factHead:Hide()
	f.segIndex, f.typed, f.lastChar, f.typing, f.hideAt, f.pauseUntil = 1, 0, -1, true, nil, nil
	f.persist = not info.landing

	f.gem:SetShown(showGem)
	if type(info.gem) == "number" then f.gem:SetText(("Play Gem Match (%s)"):format(Clock(info.gem))) else f.gem:SetText("Play Gem Match") end
	f:SetAlpha(1)
	f:Show()
	if db.sound and look.sound and PlaySoundFile then pcall(PlaySoundFile, look.sound, "SFX") end
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
	local fill = { n = count, to = flight.to or "?" }

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
				gem = useGem and (flight.planned or true) or nil })
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
	local fill = { n = ride.count, time = Clock(seconds), to = flight.to or "?" }
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
